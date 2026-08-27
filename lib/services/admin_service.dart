import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_models.dart';
import '../models/admin_permissions.dart';
import 'supabase_service.dart';
import 'admin_supabase_extension.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AdminService — Supabase-backed bridge
//
//  All 4 admin screens continue calling svc.users, svc.codes, svc.pauseUser()
//  etc. exactly as before. This class now:
//    1. Loads real data from Supabase on login (loadData())
//    2. Delegates every mutation to SupabaseService (writes to DB)
//    3. Updates the local cache and calls notifyListeners() so screens rebuild
//
//  The mock fallback is kept ONLY for the local PIN check (786786) so the
//  admin panel stays accessible even before Supabase Auth is fully configured.
// ─────────────────────────────────────────────────────────────────────────────

class AdminService extends ChangeNotifier {
  final _db = SupabaseService.instance;
  dynamic get client => _db.client;

  List<AdminUser> _users = [];
  List<ActivationCode> _codes = [];
  List<AdminAccount> _adminAccounts = [];
  bool _isLoggedIn = false;
  bool _loading = false;
  String? _loadError;
  // IDs currently being deleted — loadData will not overwrite these
  final Set<String> _pendingDeleteIds = {};
  // IDs currently being restored — loadData will not revert these
  final Map<String, ProposalStatus> _pendingRestoreStatus = {};
  // Offsets loaded from DB — persist across logout/login
  double _deletedUsersRevenue = 0;
  int _deletedUsersCount = 0;
  int _affiliateTotalCount = 0;
  int _affiliateTrashCount = 0;
  // Real all-time unique visitor count (app_visitors table — actual app
  // opens by unique device, not a proxy based on profile submissions).
  int _cachedVisitorCount = 0;

  // Proposal IDs with a pending self-service CNIC verification submission
  // (cnic_verification_requests, status='pending') — drives the red dot
  // on the View icon in the Users tab, and lets the Edit screen know
  // whether to show a submitted-documents section for this profile.
  // Replaces the old standalone "Verify" tab/list in the Requests screen:
  // review now happens per-profile from the Edit screen instead of a
  // separate bulk queue.
  Set<String> _pendingVerificationProposalIds = {};
  Set<String> get pendingVerificationProposalIds => Set.unmodifiable(_pendingVerificationProposalIds);
  RealtimeChannel? _verificationSyncChannel;

  Future<void> loadPendingVerifications() async {
    try {
      final rows = await client.from('cnic_verification_requests').select('proposal_id').eq('status', 'pending') as List;
      _pendingVerificationProposalIds = rows.map((r) => r['proposal_id'] as String).toSet();
      notifyListeners();
    } catch (_) {}
  }

  void _startVerificationSync() {
    _verificationSyncChannel?.unsubscribe();
    _verificationSyncChannel = client
        .channel('admin_service_cnic_verification_sync')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'cnic_verification_requests',
          callback: (_) async {
            await loadPendingVerifications();
            // Also reload the users list so hasPendingVerificationRequest
            // gets updated on the AdminUser objects in memory
            await loadData();
            notifyListeners();
          },
        )
        .subscribe();
  }

  // "Reset stats" baselines — subtracted from the live-computed totals
  // below so the dashboard can show 0 right after an admin resets it,
  // without touching any real underlying data (proposals, payments, or
  // the app_visitors table are never modified by a reset). Persisted in
  // app_settings so the reset survives logout/login. Monthly revenue's
  // baseline is additionally scoped to the month it was reset in, so it
  // doesn't incorrectly suppress a later month's real revenue.
  double _usersResetBaseline = 0;
  double _visitorsResetBaseline = 0;
  double _revenueResetBaseline = 0;
  double _monthlyRevenueResetBaseline = 0;
  String? _monthlyRevenueResetMonth; // 'YYYY-M', or null if never reset

  // Keeps every admin's view in sync with changes made by OTHER admins,
  // without re-fetching the whole table. Set up once, after login.
  RealtimeChannel? _syncChannel;

  /// The admin_accounts row of whoever is currently signed in.
  AdminAccount? _currentAccount;
  AdminAccount? get currentAccount => _currentAccount;

  List<AdminUser> get users => List.unmodifiable(_users);
  List<ActivationCode> get codes => List.unmodifiable(_codes);
  List<AdminAccount> get adminAccounts => List.unmodifiable(_adminAccounts);
  bool get isLoggedIn => _isLoggedIn;
  bool get loading => _loading;
  String? get loadError => _loadError;
  int get affiliateTotalCount => _affiliateTotalCount;
  int get affiliateTrashCount => _affiliateTrashCount;

  // ── Auth ──────────────────────────────────────────────────────────────────
  //  CNIC + password, checked against admin_accounts. Returns:
  //    null            → signed in
  //    'invalid'       → wrong CNIC or password
  //    'offline'       → could not reach the server
  Future<String?> loginWithCredentials(String cnic, String password) async {
    Map<String, dynamic>? row;
    try {
      row = await _db.adminPanelLogin(cnic, password);
    } catch (e) {
      debugPrint('[loginWithCredentials] error: $e');
      return 'offline';
    }
    if (row == null) return 'invalid';

    final permissions = parseAdminPermissions(row['permissions']);
    _currentAccount = AdminAccount(
      id: row['id'] as String,
      name: (row['name'] as String?) ?? 'Admin',
      cnic: (row['cnic'] as String?) ?? '',
      password: '',
      createdAt: DateTime.now(),
      isSuper: row['is_super'] == true,
      permissions: permissions,
    );

    AdminPerms.i.apply(
      id: _currentAccount!.id,
      name: _currentAccount!.name,
      cnic: _currentAccount!.cnic,
      isSuper: _currentAccount!.isSuper,
      permissions: permissions,
    );

    // Background session used by the database write policies. If it fails,
    // most pages still work, so warn instead of blocking the login.
    final sessionOk = await _db.ensurePanelSession();
    if (!sessionOk) {
      AdminPerms.messengerKey.currentState?.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF3A1730),
          content: Text(
            'Connected, but the server session did not open. Ads, affiliates and content may not save.',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      );
    }

    _isLoggedIn = true;
    notifyListeners();
    loadData(); // kick off real data load after login
    _startRealtimeSync();
    loadPendingVerifications();
    _startVerificationSync();
    return null;
  }

  void logout() {
    _isLoggedIn = false;
    _currentAccount = null;
    AdminPerms.i.clear();
    _users = [];
    _codes = [];
    _syncChannel?.unsubscribe();
    _syncChannel = null;
    _verificationSyncChannel?.unsubscribe();
    _verificationSyncChannel = null;
    _pendingVerificationProposalIds = {};
    notifyListeners();
    _db.adminLogout();
  }

  // ── Load all data from Supabase ───────────────────────────────────────────
  // Multiple screens each call loadData() in their own initState (dashboard,
  // users tab, proposals tab, etc.), so it's normal for several calls to
  // land within the same second — e.g. on app start, or a quick tab switch.
  // Without a guard, each call kicks off its own full fetch+pagination pass
  // and they all race to overwrite `_users` with no ordering guarantee: a
  // call that started EARLIER can finish LATER (e.g. because the flood of
  // simultaneous requests slowed one of them down) and stomp a good result
  // with a stale/partial one. `_loadDataFuture` makes overlapping callers
  // share a single in-flight fetch, and `_loadRequestId` makes sure that even
  // if two fetches somehow do run concurrently, only the newest one's result
  // is ever applied.
  Future<void>? _loadDataFuture;
  int _loadRequestId = 0;
  // Tracks when we last successfully loaded all users — used to fetch only
  // changed rows on subsequent refreshes instead of the full table.
  DateTime? _lastSyncTime;

  Future<void> loadData() {
    if (_loadDataFuture != null) return _loadDataFuture!;
    final future = _loadDataImpl();
    _loadDataFuture = future;
    future.whenComplete(() => _loadDataFuture = null);
    return future;
  }

  Future<void> _loadDataImpl() async {
    final requestId = ++_loadRequestId;
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final isFirstLoad = _lastSyncTime == null || _users.isEmpty;
      final syncFrom = _lastSyncTime;
      // Record sync time before fetching so any changes that land during
      // this fetch are included in the next incremental sync.
      final syncStarted = DateTime.now().toUtc();

      // All non-user fetches run in parallel regardless of first/incremental.
      // fetchAppSettings runs in parallel too — was sequential before.
      final sideResults = await Future.wait([
        _db.fetchActivationCodes(),
        _db.fetchMonthlyRevenue(),
        _db.client.from('affiliates').select('id').or('deleted.is.null,deleted.eq.false'),
        _db.client.from('affiliates').select('id').eq('deleted', true),
        _db.fetchVisitorCount(),
        _db.fetchAppSettings(),
      ]);

      List<AdminUser> freshUsers;
      if (isFirstLoad) {
        // First load — fetch everything via the summary view (1 call).
        freshUsers = await _db.fetchAdminUsers();
      } else {
        // Incremental refresh — only rows changed since last sync.
        // Typically 0–10 rows instead of 2341, so this feels instant.
        freshUsers = await _db.fetchAdminUsersSince(syncFrom!);
      }

      if (requestId != _loadRequestId) return;

      if (isFirstLoad) {
        // Replace full list on first load.
        _users = freshUsers.map((u) => _applyPendingOps(u)).toList();
      } else {
        // Merge changed rows into existing list — add new, update existing.
        final updatedIds = freshUsers.map((u) => u.id).toSet();
        _users = [
          ..._users.where((u) => !updatedIds.contains(u.id)),
          ...freshUsers.map((u) => _applyPendingOps(u)),
        ];
        // Re-sort by updated_at desc to keep order consistent.
        _users.sort((a, b) => b.postedAt.compareTo(a.postedAt));
      }

      _lastSyncTime = syncStarted;
      _codes = sideResults[0] as List<ActivationCode>;
      _cachedMonthlyRevenue = (sideResults[1] as double?) ?? 0.0;
      _affiliateTotalCount = (sideResults[2] as List).length;
      _affiliateTrashCount = (sideResults[3] as List).length;
      _cachedVisitorCount = sideResults[4] as int;
      final settings = sideResults[5] as Map<String, String>;
      _deletedUsersRevenue = double.tryParse(settings['deleted_users_revenue_offset'] ?? '0') ?? 0;
      _deletedUsersCount   = int.tryParse(settings['deleted_users_count_offset']      ?? '0') ?? 0;
      _applyResetBaselineSettings(settings);
      debugPrint('[AdminService] loadData (${isFirstLoad ? "full" : "incremental"}) — users=${_users.length} changed=${freshUsers.length}');
    } catch (e, stackTrace) {
      _loadError = e.toString();
      debugPrint('❌ loadData ERROR: $e');
      debugPrint('❌ loadData STACK: $stackTrace');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // Applies pending optimistic ops (delete/restore) to a freshly fetched user.
  AdminUser _applyPendingOps(AdminUser u) {
    if (_pendingDeleteIds.contains(u.id)) {
      if (u.status == ProposalStatus.deleted) _pendingDeleteIds.remove(u.id);
      return u.copyWith(status: ProposalStatus.deleted);
    }
    if (_pendingRestoreStatus.containsKey(u.id)) {
      return u.copyWith(status: _pendingRestoreStatus[u.id], deletedFrom: null);
    }
    return u;
  }

  // ── Stats (computed from local cache — always fast) ───────────────────────
  // "All Time Users" = anyone who has ever paid, full stop. Used to exclude
  // AI/WhatsApp-imported profiles even if they'd genuinely paid — but
  // whether someone is a paying customer should depend on whether they
  // paid, not how their profile originally entered the system.
  int get totalAllTimeSubscribers {
    final raw = _users.where((u) => u.totalSpending > 0).length + _deletedUsersCount;
    return (raw - _usersResetBaseline).clamp(0, double.infinity).toInt();
  }

  int get currentActiveUsers =>
      _users.where((u) => u.subscriptionStatus == SubscriptionStatus.active).length;

  double get allTimeRevenue {
    final raw = _users.fold(0.0, (sum, u) => sum + u.totalSpending) + _deletedUsersRevenue;
    return (raw - _revenueResetBaseline).clamp(0, double.infinity);
  }

  double _cachedMonthlyRevenue = 0;

  double get monthlyRevenue {
    final now = DateTime.now();
    final thisMonthKey = '${now.year}-${now.month}';
    // Only apply the baseline if it was set for the CURRENT month — once
    // the month rolls over, a stale baseline from a past reset shouldn't
    // suppress next month's genuinely new revenue.
    if (_monthlyRevenueResetMonth == thisMonthKey) {
      return (_cachedMonthlyRevenue - _monthlyRevenueResetBaseline).clamp(0, double.infinity);
    }
    return _cachedMonthlyRevenue;
  }

  int get pendingProposals =>
      _users.where((u) => u.status == ProposalStatus.pending).length;

  // "All Time Visitors" = every unique device that's ever opened the app
  // (app_visitors, tracked by trackAppVisit() on launch) — a genuinely
  // different, much larger number than "people who submitted a full
  // profile" (most visitors never get that far). Previously this counted
  // non-AI-imported proposals instead, which understated the real number
  // by roughly 85x against live data, since it required completing a full
  // profile submission just to be counted as having "visited" at all.
  int get totalUniqueVisitors => (_cachedVisitorCount - _visitorsResetBaseline).clamp(0, double.infinity).toInt();

  // Resets the four dashboard "all time"/"monthly" counters to 0 going
  // forward, WITHOUT deleting any real underlying data — no proposals,
  // payments, or app_visitors rows are touched. Works by remembering the
  // current totals as a baseline (persisted in app_settings) that's then
  // subtracted from the live-computed totals above, so genuinely new
  // activity from this point on still counts normally.
  Future<void> resetAllTimeStats() async {
    final rawUsers    = _users.where((u) => u.totalSpending > 0).length + _deletedUsersCount;
    final rawRevenue  = _users.fold(0.0, (sum, u) => sum + u.totalSpending) + _deletedUsersRevenue;
    final rawVisitors = _cachedVisitorCount;
    final rawMonthly  = _cachedMonthlyRevenue;
    final now = DateTime.now();
    final thisMonthKey = '${now.year}-${now.month}';

    await Future.wait([
      _db.client.rpc('admin_upsert_setting', params: {'p_key': 'users_reset_baseline', 'p_value': rawUsers.toString()}),
      _db.client.rpc('admin_upsert_setting', params: {'p_key': 'revenue_reset_baseline', 'p_value': rawRevenue.toString()}),
      _db.client.rpc('admin_upsert_setting', params: {'p_key': 'visitors_reset_baseline', 'p_value': rawVisitors.toString()}),
      _db.client.rpc('admin_upsert_setting', params: {'p_key': 'monthly_revenue_reset_baseline', 'p_value': rawMonthly.toString()}),
      _db.client.rpc('admin_upsert_setting', params: {'p_key': 'monthly_revenue_reset_month', 'p_value': thisMonthKey}),
    ]);

    _usersResetBaseline = rawUsers.toDouble();
    _revenueResetBaseline = rawRevenue;
    _visitorsResetBaseline = rawVisitors.toDouble();
    _monthlyRevenueResetBaseline = rawMonthly;
    _monthlyRevenueResetMonth = thisMonthKey;
    notifyListeners();
  }

  int get activeFeaturedPosts =>
      _users.fold(0, (sum, u) => sum + u.featuredSchedule.where((b) => b.isActive).length);

  // ── User management — write to DB then update local cache ─────────────────
  Future<void> addUser(Map<String, dynamic> data) async {
    await _db.addUser(data);
    await loadData();
  }

  Future<void> addUserWithPhotos({
    required Map<String, dynamic> data,
    Uint8List? profilePhoto,
    Uint8List? cnicFront,
    Uint8List? cnicBack,
    Uint8List? degreeCertificate,
    Uint8List? degreeCertificate2,
    Uint8List? degreeCertificate3,
  }) async {
    await _db.addUserWithPhotos(
      data: data,
      profilePhoto: profilePhoto,
      cnicFront: cnicFront,
      cnicBack: cnicBack,
      degreeCertificate: degreeCertificate,
      degreeCertificate2: degreeCertificate2,
      degreeCertificate3: degreeCertificate3,
    );
    await loadData();
  }

  Future<void> updateUser(AdminUser updated) async {
    await _db.updateUser(updated);
    _replaceUser(updated);
  }

  Future<void> pauseUser(String userId) async {
    await _db.pauseUser(userId);
    _setStatus(userId, ProposalStatus.paused);
  }

  // Tick / untick an AI card. Updates the local cache first so the tick
  // flips instantly, then writes the column. If the write fails the local
  // value is put back, so the tick never lies about what's in the DB.
  /// Approve or reject one document for a proposal. Updates the local cache
  /// immediately so the UI reflects the change without a full reload.
  Future<void> setDocVerificationStatus(String userId, String docKey, String status) async {
    // Optimistic local update
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx != -1) {
      final updated = Map<String, String>.from(_users[idx].docVerification)
        ..[docKey] = status;
      _users[idx] = _users[idx].copyWith(docVerification: updated);
      notifyListeners();
    }
    try {
      await _db.setDocVerificationStatus(userId, docKey, status);
      // Reload to get the recalculated is_doc_verified
      final fresh = await _db.fetchSingleAdminUser(userId);
      if (fresh != null) {
        final i = _users.indexWhere((u) => u.id == userId);
        if (i != -1) { _users[i] = fresh; notifyListeners(); }
      }
    } catch (_) {
      // Revert optimistic change on failure
      final i = _users.indexWhere((u) => u.id == userId);
      if (i != -1) { notifyListeners(); }
    }
  }

  Future<void> setAiContacted(String userId, bool value) async {
    final idx = _users.indexWhere((u) => u.id == userId);
    final previous = idx == -1 ? null : _users[idx].aiContacted;
    if (idx != -1) {
      _users[idx] = _users[idx].copyWith(aiContacted: value);
      notifyListeners();
    }
    try {
      await _db.setAiContacted(userId, value);
    } catch (_) {
      final i = _users.indexWhere((u) => u.id == userId);
      if (i != -1 && previous != null) {
        _users[i] = _users[i].copyWith(aiContacted: previous);
        notifyListeners();
      }
    }
  }

  Future<void> activateUser(String userId) async {
    await _db.activateUser(userId);
    _setStatus(userId, ProposalStatus.active);
  }

  // Guards against a double-tap (or any other accidental concurrent call)
  // running approveProposal twice for the same proposal. Without this, a
  // second overlapping call's "has this CNIC ever been active before?"
  // check can see the FIRST call's own approved_at write that already
  // landed, and wrongly conclude a genuinely-new user was "already active,"
  // charging the standard price instead of granting the new-user free trial.
  final Set<String> _approvingIds = {};

  Future<void> approveProposal(String userId) async {
    if (_approvingIds.contains(userId)) return;
    _approvingIds.add(userId);
    try {
      // Optimistically update local state first
      _setStatus(userId, ProposalStatus.active);
      await _db.approveProposal(userId);
      // Refresh just this one user to pick up server-computed subscription
      // fields (expiry, tier, etc.) — not the whole table.
      await _syncSingleUser(userId);
    } finally {
      _approvingIds.remove(userId);
    }
  }

  Future<void> approveAiProposal(String userId) async {
    // Optimistically update local state first
    _setStatus(userId, ProposalStatus.active);
    await _db.approveAiProposal(userId);
    await _syncSingleUser(userId);
  }

  Future<void> deleteUser(String userId, {String from = 'users'}) async {
    // Register as pending-delete so loadData() can't resurrect this user
    _pendingDeleteIds.add(userId);
    // Optimistically update local state first so UI removes the card immediately
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx != -1) {
      _users[idx] = _users[idx].copyWith(status: ProposalStatus.deleted, deletedFrom: from);
      notifyListeners();
    }
    await _db.deleteUser(userId, from: from);
    // Keep in _pendingDeleteIds — loadData() will clean it up once DB confirms deleted status
  }

  Future<void> restoreUser(String userId, [String? from]) async {
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx == -1) return;
    from ??= _users[idx].deletedFrom;
    final status = from == 'users' ? ProposalStatus.active : ProposalStatus.pending;
    // Guard against loadData() reverting this during the DB write
    _pendingRestoreStatus[userId] = status;
    // Optimistically update local state first so card disappears immediately
    _users[idx] = _users[idx].copyWith(status: status, deletedFrom: null);
    notifyListeners();
    await _db.restoreUser(userId, from);
    _pendingRestoreStatus.remove(userId);
  }

  Future<bool> deleteUserByNumber(int number) async {
    AdminUser? user; try { user = _users.firstWhere((u) => u.proposalNumber == number); } catch (_) { user = null; }
    if (user == null) return false;
    debugPrint('[AdminService] deleteUserByNumber — deleting ${user.name} spending=${user.totalSpending}');
    // Photos are intentionally left in R2 storage now — permanently
    // deleting a profile no longer removes its images immediately.
    // They're only cleaned up later, manually, via Usage & Monitoring's
    // "Scan for Unused Photos" tool, which will correctly detect them
    // as orphaned once this profile row is gone.
    await _db.permanentlyDeleteUser(user.id);
    _users.removeWhere((u) => u.id == user!.id);
    await _reloadOffsets();
    notifyListeners();
    return true;
  }

  AdminUser? findUserByNumber(int number) { try { return _users.firstWhere((u) => u.proposalNumber == number); } catch (_) { return null; } }

  Future<void> permanentlyDeleteUser(String userId) async {
    AdminUser? user; try { user = _users.firstWhere((u) => u.id == userId); } catch (_) { user = null; }
    debugPrint('[AdminService] permanentlyDeleteUser — id=$userId name=${user?.name} spending=${user?.totalSpending}');
    // Photos are intentionally left in R2 storage now — see the matching
    // comment in deleteUserByNumber above for why.
    await _db.permanentlyDeleteUser(userId);
    _users.removeWhere((u) => u.id == userId);
    await _reloadOffsets();
    notifyListeners();
  }

  Future<void> _reloadOffsets() async {
    final settings = await _db.fetchAppSettings();
    _deletedUsersRevenue  = double.tryParse(settings['deleted_users_revenue_offset']  ?? '0') ?? 0;
    _deletedUsersCount    = int.tryParse(settings['deleted_users_count_offset']       ?? '0') ?? 0;
    _cachedMonthlyRevenue = await _db.fetchMonthlyRevenue();
    _applyResetBaselineSettings(settings);
    debugPrint('[AdminService] _reloadOffsets — deletedRevenue=$_deletedUsersRevenue deletedCount=$_deletedUsersCount monthlyRevenue=$_cachedMonthlyRevenue');
  }

  void _applyResetBaselineSettings(Map<String, String> settings) {
    _usersResetBaseline           = double.tryParse(settings['users_reset_baseline']           ?? '0') ?? 0;
    _visitorsResetBaseline        = double.tryParse(settings['visitors_reset_baseline']         ?? '0') ?? 0;
    _revenueResetBaseline         = double.tryParse(settings['revenue_reset_baseline']          ?? '0') ?? 0;
    _monthlyRevenueResetBaseline  = double.tryParse(settings['monthly_revenue_reset_baseline']  ?? '0') ?? 0;
    _monthlyRevenueResetMonth     = settings['monthly_revenue_reset_month'];
  }

  // ── Expire subscriptions — delegates to DB function ───────────────────────
  Future<void> checkAndExpireSubscriptions() async {
    await _db.checkAndExpireSubscriptions();
    // Reload to reflect changes
    await loadData();
  }

  // ── Admin accounts (Dashboard → Settings → Create Admin) ──────────────────
  Future<void> loadAdminAccounts() async {
    try {
      _adminAccounts = await _db.fetchAdminAccounts();
      notifyListeners();
    } catch (e) {
      debugPrint('❌ loadAdminAccounts ERROR: $e');
    }
  }

  /// Returns null on success, or an error message to show the user.
  Future<String?> createAdminAccount({
    required String name,
    required String cnic,
    required String password,
    bool isSuper = false,
    Map<String, String> permissions = const {},
  }) async {
    final err = await _db.createAdminAccount(
      name: name, cnic: cnic, password: password,
      isSuper: isSuper, permissions: permissions,
    );
    if (err == null) await loadAdminAccounts();
    return err;
  }

  /// Returns null on success, or an error message to show the user.
  Future<String?> updateAdminAccount({
    required String id,
    required String name,
    required String cnic,
    required String password,
    bool isSuper = false,
    Map<String, String> permissions = const {},
  }) async {
    final err = await _db.updateAdminAccount(
      id: id, name: name, cnic: cnic, password: password,
      isSuper: isSuper, permissions: permissions,
    );
    if (err == null) {
      await loadAdminAccounts();
      // If an admin edited their own account, refresh the live permissions
      // so the change takes effect without a re-login.
      if (_currentAccount?.id == id) {
        _currentAccount = AdminAccount(
          id: id, name: name, cnic: cnic.replaceAll('-', ''), password: '',
          createdAt: _currentAccount!.createdAt,
          isSuper: isSuper, permissions: permissions,
        );
        AdminPerms.i.apply(
          id: id, name: name, cnic: cnic.replaceAll('-', ''),
          isSuper: isSuper, permissions: permissions,
        );
      }
    }
    return err;
  }

  Future<void> deleteAdminAccount(String id) async {
    await _db.deleteAdminAccount(id);
    _adminAccounts.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  // ── Activation codes ──────────────────────────────────────────────────────
  String generateCode(SubscriptionTier tier, double price) {
    // Generate locally for instant UI feedback, then persist async
    final rnd = Random();
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final suffix = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    final prefix = tier == SubscriptionTier.featured ? 'FEAT' : 'BASC';
    final code = '$prefix-$suffix';

    // Add to local cache immediately
    _codes = [
      ActivationCode(code: code, tier: tier, price: price, createdAt: DateTime.now()),
      ..._codes,
    ];
    notifyListeners();

    // Persist to Supabase asynchronously
    _db.generateCode(tier, price);

    return code;
  }

  // ── Featured credits & scheduling ─────────────────────────────────────────
  Future<void> confirmFeaturedTokens(String userId) async {
    await _db.confirmFeaturedTokens(userId);
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx == -1) return;
    final user = _users[idx];
    if (user.pendingFeaturedTokens <= 0) return;
    _users[idx] = user.copyWith(
      featuredPointsPurchased: user.featuredPointsPurchased + user.pendingFeaturedTokens,
      totalSpending: user.totalSpending + (user.pendingFeaturedTokens * 200.0),
      pendingFeaturedTokens: 0,
    );
    notifyListeners();
  }

  Future<void> addFeaturedCredits(String userId, int credits, {int pricePerCredit = 200}) async {
    await _db.addFeaturedCredits(userId, credits, pricePerCredit: pricePerCredit);
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx == -1) return;
    _users[idx] = _users[idx].copyWith(
      featuredPointsPurchased: _users[idx].featuredPointsPurchased + credits,
      totalSpending: _users[idx].totalSpending + (credits * pricePerCredit.toDouble()),
    );
    notifyListeners();
  }

  void removeFeaturedCredits(String userId, int credits) {
    // UI-only update (AdminUsersScreen calls this for display adjustment)
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx == -1) return;
    final user = _users[idx];
    final newPurchased = (user.featuredPointsPurchased - credits)
        .clamp(user.featuredPointsUsed, 9999);
    final removed = user.featuredPointsPurchased - newPurchased;
    if (removed <= 0) return;
    _users[idx] = user.copyWith(
      featuredPointsPurchased: newPurchased,
      totalSpending: (user.totalSpending - (removed * 200.0)).clamp(0, double.infinity),
    );
    notifyListeners();
  }

  Future<String?> scheduleFeaturedPost(String userId, DateTime date, String city) async {
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx == -1) return 'not_found';
    final user = _users[idx];
    if ((user.featuredPointsPurchased - user.featuredPointsUsed) <= 0) return 'no_credits';

    final err = await _db.scheduleFeaturedPost(userId, date, city);
    if (err != null) return err;

    final newBoost = FeaturedBoost(scheduledDate: date, city: city);
    _users[idx] = user.copyWith(
      featuredSchedule: [...user.featuredSchedule, newBoost],
      featuredPointsUsed: user.featuredPointsUsed + 1,
    );
    notifyListeners();
    return null;
  }

  Future<void> removeFeaturedSchedule(String userId, int boostIndex) async {
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx == -1) return;
    final user = _users[idx];
    final boost = user.featuredSchedule[boostIndex];
    if (boost.isUsed) return;

    // Need the DB id to delete — if available use it, else reload
    if (boost.id != null) {
      await _db.removeFeaturedSchedule(boost.id!, userId);
    }

    final newSchedule = List<FeaturedBoost>.from(user.featuredSchedule)..removeAt(boostIndex);
    _users[idx] = user.copyWith(
      featuredSchedule: newSchedule,
      featuredPointsUsed: user.featuredPointsUsed - 1,
    );
    notifyListeners();
  }

  // ── Kept for compatibility (submit screen calls this) ─────────────────────
  void addPendingProposal(AdminUser user) {
    _users = [user, ..._users];
    notifyListeners();
  }

  // ── Internal helpers ──────────────────────────────────────────────────────
  void _replaceUser(AdminUser updated) {
    final idx = _users.indexWhere((u) => u.id == updated.id);
    if (idx != -1) {
      _users[idx] = updated;
      notifyListeners();
    }
  }

  void _setStatus(String userId, ProposalStatus status) {
    final idx = _users.indexWhere((u) => u.id == userId);
    if (idx != -1) {
      _users[idx] = _users[idx].copyWith(status: status);
      notifyListeners();
    }
  }

  // ── Realtime sync — keeps every admin's view current ──────────────────────
  // Listens for changes to ANY proposal, made by ANY admin (or the automatic
  // subscription-expiry checker), and refreshes just that one person's data
  // locally — never the whole table. Own actions already update instantly
  // via the optimistic local updates elsewhere in this file (_setStatus,
  // _replaceUser, etc.); this is what keeps this admin's screen current
  // when someone ELSE makes a change, without waiting for a manual refresh
  // or a full reload.
  void _startRealtimeSync() {
    _syncChannel?.unsubscribe();
    _syncChannel = _db.client
        .channel('public:proposals:admin-sync')
        .onPostgresChanges(
          // New proposal submitted (new order / new user) — wasn't covered
          // before, so new rows only ever showed up after a manual refresh.
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'proposals',
          callback: (payload) {
            final id = payload.newRecord['id'] as String?;
            if (id == null) return;
            // Already present locally (e.g. this admin's own submit-flow
            // already added it via addPendingProposal) — nothing to do.
            if (_users.any((u) => u.id == id)) return;
            _syncNewUser(id);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'proposals',
          callback: (payload) {
            final id = payload.newRecord['id'] as String?;
            if (id == null) return;
            if (_users.any((u) => u.id == id)) {
              _syncSingleUser(id);
            } else {
              // Wasn't loaded yet (e.g. the insert event was missed while
              // offline) — pick it up now instead of waiting for a full
              // manual reload.
              _syncNewUser(id);
            }
          },
        )
        .onPostgresChanges(
          // Row permanently removed (by another admin, or a cleanup job) —
          // drop it from this admin's local list too.
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'proposals',
          callback: (payload) {
            final id = payload.oldRecord['id'] as String?;
            if (id == null) return;
            final idx = _users.indexWhere((u) => u.id == id);
            if (idx != -1) {
              _users.removeAt(idx);
              notifyListeners();
            }
          },
        )
        .onPostgresChanges(
          // Activation codes generated/used/expired by another admin session.
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'activation_codes',
          callback: (_) => _debouncedRefetchCodes(),
        )
        .onPostgresChanges(
          // Admin accounts created/edited/removed by another admin session.
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'admin_accounts',
          callback: (_) => _debouncedRefetchAdminAccounts(),
        )
        .subscribe();
  }

  Timer? _codesDebounce;
  void _debouncedRefetchCodes() {
    _codesDebounce?.cancel();
    _codesDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        _codes = await _db.fetchActivationCodes();
        notifyListeners();
      } catch (e) {
        debugPrint('[AdminService] refetch activation_codes failed: $e');
      }
    });
  }

  Timer? _adminAccountsDebounce;
  void _debouncedRefetchAdminAccounts() {
    _adminAccountsDebounce?.cancel();
    _adminAccountsDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        _adminAccounts = await _db.fetchAdminAccounts();
        notifyListeners();
      } catch (e) {
        debugPrint('[AdminService] refetch admin_accounts failed: $e');
      }
    });
  }

  // Fetches a row this admin hasn't loaded yet (new insert, or an update
  // that arrived for a row missed earlier) and adds it to the local list.
  Future<void> _syncNewUser(String id) async {
    if (_syncingIds.contains(id)) return;
    _syncingIds.add(id);
    try {
      final fresh = await _db.fetchSingleAdminUser(id);
      if (fresh != null && !_users.any((u) => u.id == fresh.id)) {
        _users = [fresh, ..._users];
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AdminService] _syncNewUser($id) failed: $e');
    } finally {
      _syncingIds.remove(id);
    }
  }

  // Guards against overlapping syncs for the same id if several rapid
  // updates arrive close together (e.g. an admin action followed almost
  // immediately by this same change echoing back through the realtime
  // channel) — avoids piling up redundant requests for one person.
  final Set<String> _syncingIds = {};

  Future<void> _syncSingleUser(String id) async {
    if (_syncingIds.contains(id)) return;
    _syncingIds.add(id);
    try {
      final fresh = await _db.fetchSingleAdminUser(id);
      if (fresh != null) _replaceUser(fresh);
    } catch (e) {
      debugPrint('[AdminService] _syncSingleUser($id) failed: $e');
      // Deliberately silent otherwise — this is a background sync; a
      // failure here just means this admin's view stays as it was until
      // the next successful sync or manual refresh, not a user-facing error.
    } finally {
      _syncingIds.remove(id);
    }
  }

  @override
  void dispose() {
    _syncChannel?.unsubscribe();
    _codesDebounce?.cancel();
    _adminAccountsDebounce?.cancel();
    super.dispose();
  }
}
