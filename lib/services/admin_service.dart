import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/admin_models.dart';
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

  static const String _adminPin = '786786';

  List<AdminUser> get users => List.unmodifiable(_users);
  List<ActivationCode> get codes => List.unmodifiable(_codes);
  List<AdminAccount> get adminAccounts => List.unmodifiable(_adminAccounts);
  bool get isLoggedIn => _isLoggedIn;
  bool get loading => _loading;
  String? get loadError => _loadError;
  int get affiliateTotalCount => _affiliateTotalCount;
  int get affiliateTrashCount => _affiliateTrashCount;

  // ── Auth ──────────────────────────────────────────────────────────────────
  bool login(String pin) {
    if (pin == _adminPin) {
      _isLoggedIn = true;
      notifyListeners();
      loadData(); // kick off real data load after login
      _startRealtimeSync();
      return true;
    }
    return false;
  }

  void logout() {
    _isLoggedIn = false;
    _users = [];
    _codes = [];
    _syncChannel?.unsubscribe();
    _syncChannel = null;
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
      final results = await Future.wait([
        _db.fetchAdminUsers(),
        _db.fetchActivationCodes(),
        _db.fetchMonthlyRevenue(),
        _db.client.from('affiliates').select('id').or('deleted.is.null,deleted.eq.false'),
        _db.client.from('affiliates').select('id').eq('deleted', true),
        _db.fetchVisitorCount(),
      ]);
      // A newer loadData() call started and already applied its own (more
      // current) results while we were fetching — discard ours instead of
      // overwriting good data with something older.
      if (requestId != _loadRequestId) return;
      final freshUsers = results[0] as List<AdminUser>;
      // Don't let a DB reload resurrect users we've already optimistically deleted
      _users = freshUsers.map((u) {
        if (_pendingDeleteIds.contains(u.id)) {
          // If DB confirms deleted, safe to remove from guard set
          if (u.status == ProposalStatus.deleted) _pendingDeleteIds.remove(u.id);
          return u.copyWith(status: ProposalStatus.deleted);
        }
        if (_pendingRestoreStatus.containsKey(u.id)) {
          return u.copyWith(status: _pendingRestoreStatus[u.id], deletedFrom: null);
        }
        return u;
      }).toList();
      _codes = results[1] as List<ActivationCode>;
      _cachedMonthlyRevenue = (results[2] as double?) ?? 0.0;
      _affiliateTotalCount = (results[3] as List).length;
      _affiliateTrashCount = (results[4] as List).length;
      // Real all-time visitor count — every unique device that's ever
      // opened the app, not a proxy based on profile submissions. Doesn't
      // need a "deleted offset" the way user/revenue counts do, because
      // deleting a proposal never removes anyone from app_visitors — the
      // two tables are unrelated (device visits vs. submitted profiles).
      _cachedVisitorCount = results[5] as int;
      // Load persisted offsets from app_settings (survive logout/login)
      final settings = await _db.fetchAppSettings();
      _deletedUsersRevenue   = double.tryParse(settings['deleted_users_revenue_offset']  ?? '0') ?? 0;
      _deletedUsersCount     = int.tryParse(settings['deleted_users_count_offset']       ?? '0') ?? 0;
      _applyResetBaselineSettings(settings);
      debugPrint('[AdminService] loadData — deletedRevenue=$_deletedUsersRevenue deletedCount=$_deletedUsersCount visitorCount=$_cachedVisitorCount monthlyRevenue=$_cachedMonthlyRevenue');
    } catch (e, stackTrace) {
      _loadError = e.toString();
      debugPrint('❌ loadData ERROR: $e');
      debugPrint('❌ loadData STACK: $stackTrace');
      // Keep any previously loaded data on error — don't blank the screen
    } finally {
      _loading = false;
      notifyListeners();
    }
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
    File? profilePhoto,
    File? cnicFront,
    File? cnicBack,
    File? degreeCertificate,
    File? degreeCertificate2,
    File? degreeCertificate3,
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
  }) async {
    final err = await _db.createAdminAccount(name: name, cnic: cnic, password: password);
    if (err == null) await loadAdminAccounts();
    return err;
  }

  /// Returns null on success, or an error message to show the user.
  Future<String?> updateAdminAccount({
    required String id,
    required String name,
    required String cnic,
    required String password,
  }) async {
    final err = await _db.updateAdminAccount(id: id, name: name, cnic: cnic, password: password);
    if (err == null) await loadAdminAccounts();
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
