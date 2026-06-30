import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
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
  int _deletedVisitorsCount = 0;

  static const String _adminPin = '786786';

  List<AdminUser> get users => List.unmodifiable(_users);
  List<ActivationCode> get codes => List.unmodifiable(_codes);
  bool get isLoggedIn => _isLoggedIn;
  bool get loading => _loading;
  String? get loadError => _loadError;

  // ── Auth ──────────────────────────────────────────────────────────────────
  bool login(String pin) {
    if (pin == _adminPin) {
      _isLoggedIn = true;
      notifyListeners();
      loadData(); // kick off real data load after login
      return true;
    }
    return false;
  }

  void logout() {
    _isLoggedIn = false;
    _users = [];
    _codes = [];
    notifyListeners();
    _db.adminLogout();
  }

  // ── Load all data from Supabase ───────────────────────────────────────────
  Future<void> loadData() async {
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _db.fetchAdminUsers(),
        _db.fetchActivationCodes(),
        _db.fetchMonthlyRevenue(),
      ]);
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
      // Load persisted offsets from app_settings (survive logout/login)
      final settings = await _db.fetchAppSettings();
      _deletedUsersRevenue   = double.tryParse(settings['deleted_users_revenue_offset']  ?? '0') ?? 0;
      _deletedUsersCount     = int.tryParse(settings['deleted_users_count_offset']       ?? '0') ?? 0;
      _deletedVisitorsCount  = int.tryParse(settings['deleted_visitors_count_offset']    ?? '0') ?? 0;
      debugPrint('[AdminService] loadData — deletedRevenue=$_deletedUsersRevenue deletedCount=$_deletedUsersCount deletedVisitors=$_deletedVisitorsCount monthlyRevenue=$_cachedMonthlyRevenue');
    } catch (e) {
      _loadError = e.toString();
      debugPrint('❌ loadData ERROR: $e');
      debugPrint('❌ loadData STACK: ${StackTrace.current}');
      // Keep any previously loaded data on error — don't blank the screen
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Stats (computed from local cache — always fast) ───────────────────────
  int get totalAllTimeSubscribers =>
      _users.where((u) => u.totalSpending > 0 && u.adminNotes != 'AI_IMPORTED').length + _deletedUsersCount;

  int get currentActiveUsers =>
      _users.where((u) => u.subscriptionStatus == SubscriptionStatus.active).length;

  double get allTimeRevenue =>
      _users.fold(0.0, (sum, u) => sum + u.totalSpending) + _deletedUsersRevenue;

  double _cachedMonthlyRevenue = 0;

  double get monthlyRevenue => _cachedMonthlyRevenue;

  int get pendingProposals =>
      _users.where((u) => u.status == ProposalStatus.pending).length;

  int get totalUniqueVisitors => _users.where((u) => u.adminNotes != 'AI_IMPORTED').length + _deletedVisitorsCount;

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
  }) async {
    await _db.addUserWithPhotos(
      data: data,
      profilePhoto: profilePhoto,
      cnicFront: cnicFront,
      cnicBack: cnicBack,
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

  Future<void> approveProposal(String userId) async {
    // Optimistically update local state first
    _setStatus(userId, ProposalStatus.active);
    await _db.approveProposal(userId);
    // Reload to get updated subscription fields (expiry, tier, etc.)
    await loadData();
  }

  Future<void> approveAiProposal(String userId) async {
    // Optimistically update local state first
    _setStatus(userId, ProposalStatus.active);
    await _db.approveAiProposal(userId);
    await loadData();
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
    await _db.permanentlyDeleteUser(userId);
    _users.removeWhere((u) => u.id == userId);
    await _reloadOffsets();
    notifyListeners();
  }

  Future<void> _reloadOffsets() async {
    final settings = await _db.fetchAppSettings();
    _deletedUsersRevenue  = double.tryParse(settings['deleted_users_revenue_offset']  ?? '0') ?? 0;
    _deletedUsersCount    = int.tryParse(settings['deleted_users_count_offset']       ?? '0') ?? 0;
    _deletedVisitorsCount = int.tryParse(settings['deleted_visitors_count_offset']    ?? '0') ?? 0;
    _cachedMonthlyRevenue = await _db.fetchMonthlyRevenue();
    debugPrint('[AdminService] _reloadOffsets — deletedRevenue=$_deletedUsersRevenue deletedCount=$_deletedUsersCount deletedVisitors=$_deletedVisitorsCount monthlyRevenue=$_cachedMonthlyRevenue');
  }

  // ── Expire subscriptions — delegates to DB function ───────────────────────
  Future<void> checkAndExpireSubscriptions() async {
    await _db.checkAndExpireSubscriptions();
    // Reload to reflect changes
    await loadData();
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
}
