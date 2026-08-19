import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../services/admin_service.dart';
import '../models/admin_models.dart';
import '../models/admin_permissions.dart';
import '../widgets/notification_bell_widget.dart';
import 'admin_notification_screen.dart';
import 'admin_users_screen.dart';
import 'admin_proposals_screen.dart';
import 'admin_trash_screen.dart';
import 'admin_pricing_screen.dart';
import 'admin_affiliate_screen.dart';
import 'admin_add_user_screen.dart';
import 'admin_whatsapp_import_screen.dart';
import 'admin_login_screen.dart';
import 'admin_edit_requests_screen.dart';
import 'admin_testimonials_screen.dart';
import 'admin_ads_screen.dart';
import 'admin_tracking_screen.dart';
import 'admin_accounts_screen.dart';
import 'admin_usage_stats_screen.dart';
import 'admin_marketing_screen.dart';

// ── Thin screen wrappers for the new standalone Ads and Verification tabs ──
// AdminAdsCard and VerificationSettingsCard are self-contained widgets
// defined in their own files — these wrappers just give each a full-screen
// Scaffold so they work as top-level tab destinations.
class AdminAdsScreen extends StatelessWidget {
  final void Function(VoidCallback)? onRefreshCallback;
  const AdminAdsScreen({super.key, this.onRefreshCallback});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1E),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const ViewOnlyBanner(pageKey: AdminPageKeys.ads),
          AdminAdsCard(onRefreshCallback: onRefreshCallback),
        ]),
      ),
    );
  }
}

class AdminVerificationScreen extends StatelessWidget {
  final void Function(VoidCallback)? onRefreshCallback;
  const AdminVerificationScreen({super.key, this.onRefreshCallback});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1E),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const ViewOnlyBanner(pageKey: AdminPageKeys.verification),
          VerificationSettingsCard(onRefreshCallback: onRefreshCallback),
        ]),
      ),
    );
  }
}


// ── Responsive scale helper ────────────────────────────────────────────────
class _S {
  final double scale;
  const _S(this.scale);
  double f(double size) => size * scale;
  double s(double size) => size * scale;
  double d(double size) => size * scale;
  static _S of(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final scale = (w / 390.0).clamp(0.72, 1.0);
    return _S(scale);
  }
}

class AdminDashboardScreen extends StatefulWidget {
  final AdminService adminService;
  const AdminDashboardScreen({super.key, required this.adminService});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with TickerProviderStateMixin {
  // _tab is always the GLOBAL tab index (0..9), matching kAdminTabPages and
  // the IndexedStack below, even when some tabs are hidden for this admin.
  int _tab = AdminPerms.i.firstVisibleTabIndex;

  final _perms = AdminPerms.i;

  /// Tab indexes this admin is allowed to open, in order.
  List<int> get _visibleTabIndexes {
    final out = <int>[];
    for (int i = 0; i < kAdminTabPages.length; i++) {
      if (_perms.canView(kAdminTabPages[i].key)) out.add(i);
    }
    return out.isEmpty ? [0] : out;
  }

  String _pageKey(int index) => kAdminTabPages[index].key;
  bool _canEditTab(int index) => _perms.canEdit(_pageKey(index));
  VoidCallback? _addAffiliate;
  VoidCallback? _refreshAffiliate;
  VoidCallback? _refreshAds;
  VoidCallback? _refreshVerification;
  VoidCallback? _refreshTestimonials;
  final _marketingKey = GlobalKey<AdminMarketingScreenState>();
  bool _refreshing = false;
  int _affiliateTrashCount = 0;
  int _pendingCount = 0;
  int _unreadNotifCount = 0;
  int _refreshKey = 0;
  late AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    widget.adminService.addListener(_onServiceUpdate);
    // Load real data from Supabase, then run expiry check
    widget.adminService.loadData().then((_) {
      widget.adminService.checkAndExpireSubscriptions();
    });
    _refreshUnreadNotifCount();
  }

  Future<void> _refreshUnreadNotifCount() async {
    final count = await NotificationBellWidget.unreadCount();
    if (mounted) setState(() => _unreadNotifCount = count);
  }

  @override
  void dispose() {
    widget.adminService.removeListener(_onServiceUpdate);
    _spinCtrl.dispose();
    super.dispose();
  }

  void _onServiceUpdate() => setState(() {
    _pendingCount = widget.adminService.pendingProposals;
  });

  Future<void> _loadAffiliateTrashCount() async {
    try {
      final db = SupabaseService.instance;
      final trashRes = await db.client.from('affiliates').select('id').eq('deleted', true);
      final totalRes = await db.client.from('affiliates').select('id').or('deleted.is.null,deleted.eq.false');
      if (mounted) setState(() {
        _affiliateTrashCount = (trashRes as List).length;
      });
    } catch (_) {}
  }

  void _showAddProposalSheet(BuildContext context, dynamic svc, _S s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1A33),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add Proposal', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('How would you like to add?', style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 20),
            // Option 1: Generate with AI
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AdminWhatsAppImportScreen(svc: svc))).then((_) => _doRefresh());
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kPurple.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kPurple.withOpacity(0.4)),
                ),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: kPurple.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.auto_awesome, color: kPurple, size: 20),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Generate with AI', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('Paste WhatsApp message — AI fills the form', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ])),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            // Option 2: Add Manually
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AdminAddUserScreen(svc: svc))).then((_) => _doRefresh());
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kPurple.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kPurple.withOpacity(0.4)),
                ),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: kPurple.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.edit_note_rounded, color: kPurple, size: 20),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Add Manually', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('Fill in all fields yourself', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ])),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
                ]),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _doRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    _spinCtrl.repeat();
    await widget.adminService.loadData();
    _spinCtrl.stop();
    _spinCtrl.reset();
    if (!mounted) return;
    setState(() { _refreshing = false; _refreshKey++; });
  }

  void _showSettingsDialog(BuildContext ctx, dynamic svc) {
    // Step 1 — pick what to change
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16132A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          if (_perms.accountName.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'Signed in as ${_perms.accountName}${_perms.isSuper ? ' · full access' : ''}',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11.5, fontWeight: FontWeight.w500),
            ),
          ],
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _SettingOption(
            icon: Icons.lock_reset_rounded,
            color: kPurple,
            label: 'Change My Password',
            onTap: () { Navigator.pop(ctx); _showChangePasswordDialog(ctx); },
          ),
          const SizedBox(height: 10),
          if (_perms.canEdit(AdminPageKeys.settings)) ...[
            _SettingOption(
              icon: Icons.chat_rounded,
              color: const Color(0xFF25D366),
              label: 'Change WhatsApp',
              onTap: () { Navigator.pop(ctx); _showChangeWaDialog(ctx); },
            ),
            const SizedBox(height: 10),
            _SettingOption(
              icon: Icons.admin_panel_settings_rounded,
              color: kAmber,
              label: 'Create Admin',
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AdminAccountsScreen(svc: widget.adminService),
                ));
              },
            ),
            const SizedBox(height: 10),
          ],
          _SettingOption(
            icon: Icons.monitor_heart_rounded,
            color: const Color(0xFF25D366),
            label: 'Usage & Monitoring',
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => const AdminUsageStatsScreen(),
              ));
            },
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4))),
          ),
        ],
      ),
    );
  }

  // ── Change my own password ────────────────────────────────────────────────
  //  Replaces the old "Change PIN" dialog. Updates the password on this
  //  admin's own admin_accounts row via the admin_panel_change_password RPC.
  void _showChangePasswordDialog(BuildContext ctx) {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool saving = false;
    String? error;

    final accountId = _perms.accountId;
    if (accountId == null) return;

    showDialog(
      context: ctx,
      builder: (_) => StatefulBuilder(
        builder: (dlgCtx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF16132A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.lock_reset_rounded, color: kPurple, size: 20),
            const SizedBox(width: 8),
            const Text('Change Password', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _passwordField(oldCtrl, 'Current password', onChanged: (_) => setDlg(() {})),
            const SizedBox(height: 12),
            _passwordField(newCtrl, 'New password (min 6)', onChanged: (_) => setDlg(() {})),
            const SizedBox(height: 12),
            _passwordField(confirmCtrl, 'Confirm new password', onChanged: (_) => setDlg(() {})),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(fontSize: 12, color: kRose)),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4))),
            ),
            Builder(builder: (context) {
              final hasInput = oldCtrl.text.isNotEmpty &&
                  newCtrl.text.length >= 6 &&
                  confirmCtrl.text.isNotEmpty;
              final enabled = hasInput && !saving;
              return GestureDetector(
                onTap: !enabled ? null : () async {
                  if (newCtrl.text.trim() != confirmCtrl.text.trim()) {
                    setDlg(() => error = 'Passwords do not match');
                    return;
                  }
                  setDlg(() { saving = true; error = null; });
                  final err = await SupabaseService.instance.changeAdminPassword(
                    id: accountId,
                    oldPassword: oldCtrl.text,
                    newPassword: newCtrl.text,
                  );
                  if (err != null) {
                    setDlg(() { saving = false; error = err; });
                    return;
                  }
                  if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: enabled ? kPurple : kPurple.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Save', style: TextStyle(color: Colors.white.withOpacity(enabled ? 1 : 0.6), fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showChangeWaDialog(BuildContext ctx) {
    final currentSaved = SupabaseService.instance.cachedSettings['whatsapp_number'] ?? '923000000000';
    final waCtrl = TextEditingController(text: currentSaved);
    bool saving = false;
    String? error;
    String? success;

    showDialog(
      context: ctx,
      builder: (_) => StatefulBuilder(
        builder: (dlgCtx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF16132A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 20),
            const SizedBox(width: 8),
            const Text('WhatsApp', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: waCtrl,
              keyboardType: TextInputType.phone,
              onChanged: (_) => setDlg(() {}),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: '923001234567',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                helperText: 'Country code + number, no + (e.g. 923001234567)',
                helperStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
                filled: true,
                fillColor: Colors.black.withOpacity(0.25),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: kPurple)),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(error!, style: const TextStyle(fontSize: 11, color: kRose)),
            ],
            if (success != null) ...[
              const SizedBox(height: 6),
              Text(success!, style: const TextStyle(fontSize: 11, color: kGreen)),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4))),
            ),
            Builder(builder: (context) {
              // Nothing to actually save unless the number is a valid
              // length AND actually different from what's already saved —
              // same "only enabled when there's something to save"
              // behavior as the Change PIN dialog.
              final digits = waCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
              final hasChange = digits.length >= 10 && digits != currentSaved;
              final enabled = hasChange && !saving;
              return GestureDetector(
              onTap: !enabled ? null : () async {
                final num = waCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
                if (num.length < 10) { setDlg(() => error = 'Enter a valid number'); return; }
                setDlg(() { saving = true; error = null; success = null; });
                try {
                  await SupabaseService.instance.client.from('app_settings')
                    .upsert({'key': 'whatsapp_number', 'value': num});
                  await SupabaseService.instance.fetchAppSettings();
                  if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                } catch (e) {
                  setDlg(() { saving = false; error = 'Failed to save'; });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: enabled ? const Color(0xFF25D366) : const Color(0xFF25D366).withOpacity(0.35), borderRadius: BorderRadius.circular(8)),
                child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Save', style: TextStyle(color: Colors.white.withOpacity(enabled ? 1 : 0.6), fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              );
            }),
          ],
        ),
      ),
    );
  }


  Widget _passwordField(TextEditingController ctrl, String label, {ValueChanged<String>? onChanged}) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4)),
        counterText: '',
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = widget.adminService;

    // Safety net: an admin with no pages assigned gets a clear message
    // instead of an empty screen.
    if (_perms.visibleTabs.isEmpty) return _buildNoAccess(svc);

    // Force light status bar icons (white) for dark admin background
    if (!kIsWeb) SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF0F0D1A),
      statusBarIconBrightness: Brightness.light,
    ));
    // Pages this admin has no access to are never built at all.
    Widget gate(String key, Widget Function() build) =>
        _perms.canView(key) ? build() : const SizedBox.shrink();

    final tabContent = IndexedStack(
      index: _tab,
      children: [
        gate(AdminPageKeys.dashboard, () => _DashboardHome(svc: svc, refreshKey: _refreshKey,
          affiliateTrashCount: _affiliateTrashCount, affiliateTotalCount: svc.affiliateTotalCount)),
        gate(AdminPageKeys.orders, () => AdminProposalsScreen(svc: svc)),
        gate(AdminPageKeys.users, () => AdminUsersScreen(svc: svc)),
        gate(AdminPageKeys.pricing, () => const AdminPricingScreen()),
        gate(AdminPageKeys.affiliate, () => AdminAffiliateScreen(onRegisterCallback: (cb) => _addAffiliate = cb, onRefreshCallback: (cb) => _refreshAffiliate = cb, onAffiliateDeleted: _loadAffiliateTrashCount)),
        gate(AdminPageKeys.content, () => AdminTestimonialsScreen(onRefreshCallback: (cb) => _refreshTestimonials = cb)),
        gate(AdminPageKeys.ads, () => AdminAdsScreen(onRefreshCallback: (cb) => _refreshAds = cb)),
        gate(AdminPageKeys.verification, () => AdminVerificationScreen(onRefreshCallback: (cb) => _refreshVerification = cb)),
        gate(AdminPageKeys.tracking, () => const AdminTrackingScreen()),
        gate(AdminPageKeys.marketing, () => AdminMarketingScreen(key: _marketingKey)),
      ],
    );

    // Web: sidebar layout. Mobile: bottom nav.
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0D1A),
        body: Row(children: [
          _buildSidebar(svc),
          Expanded(
            child: Column(children: [
              _buildHeader(svc),
              Expanded(child: tabContent),
            ]),
          ),
        ]),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(svc),
            Expanded(child: tabContent),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }


  // ── No pages assigned ───────────────────────────────────────────────────
  Widget _buildNoAccess(AdminService svc) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline_rounded, size: 54, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 16),
              const Text('No pages assigned',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Your account has no access yet. Ask the main admin to give you access in Settings → Create Admin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () {
                  svc.logout();
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => AdminLoginScreen(adminService: svc)));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                  decoration: BoxDecoration(color: kRose, borderRadius: BorderRadius.circular(10)),
                  child: const Text('Logout',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Web sidebar navigation ──────────────────────────────────────────────
  Widget _buildSidebar(AdminService svc) {
    // Only the tabs this admin may open.
    final visible = _visibleTabIndexes;
    final items = visible
        .map((i) => (kAdminTabPages[i].icon, kAdminTabPages[i].label))
        .toList();
    return Container(
      width: 210,
      decoration: const BoxDecoration(
        color: Color(0xFF16132A),
        border: Border(right: BorderSide(color: Color(0x12FFFFFF))),
      ),
      child: Column(
        children: [
          // Logo header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Row(children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPurple, kPurpleDeep]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: Icon(Icons.person_rounded, color: Colors.white, size: 18)),
              ),
              const SizedBox(width: 10),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Jor Admin', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                Text('admin.joronline.com', style: TextStyle(color: Color(0x55FFFFFF), fontSize: 9.5)),
              ]),
            ]),
          ),
          const Divider(color: Color(0x10FFFFFF), height: 1),
          const SizedBox(height: 6),
          // Nav items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: items.length,
              itemBuilder: (_, pos) {
                final i = visible[pos];
                final selected = _tab == i;
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _tab = i);
                      if (i == 4) _loadAffiliateTrashCount();
                      if (i == 6) _refreshAds?.call();
                      if (i == 7) _refreshVerification?.call();
                      // Tab 8 (Tracking) — no auto-refresh needed
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? kPurple.withOpacity(0.14) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: selected ? Border.all(color: kPurple.withOpacity(0.25)) : null,
                      ),
                      child: Row(children: [
                        Stack(clipBehavior: Clip.none, children: [
                          Icon(items[pos].$1, size: 19,
                            color: selected ? kPurple : Colors.white.withOpacity(0.4)),
                          if (i == 1 && _pendingCount > 0)
                            Positioned(right: -6, top: -4,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(color: kRose, shape: BoxShape.circle),
                                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                                child: Text(_pendingCount > 99 ? '99+' : '$_pendingCount',
                                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
                                  textAlign: TextAlign.center),
                              )),
                        ]),
                        const SizedBox(width: 11),
                        Text(items[pos].$2, style: TextStyle(
                          color: selected ? kPurple : Colors.white.withOpacity(0.55),
                          fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(color: Color(0x10FFFFFF), height: 1),
          // Refresh + logout row
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => svc.loadData(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.refresh_rounded, color: Color(0x66FFFFFF), size: 16),
                        SizedBox(width: 6),
                        Text('Refresh', style: TextStyle(color: Color(0x66FFFFFF), fontSize: 11.5)),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AdminService svc) {
    final s = _S.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(s.s(20), s.s(16), s.s(20), s.s(12)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.07))),
      ),
      child: Row(
        children: [
          Image.asset('assets/logo/logo.png', width: s.d(56), height: s.d(56), fit: BoxFit.contain),
          SizedBox(width: s.s(12)),
          Expanded(
            child: Text('Admin Panel', style: TextStyle(fontSize: s.f(17), fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
          ),
          if (_tab == 3) ...[SizedBox(width: s.s(4))],
          if (_tab == 1 || _tab == 2) ...[
            RotationTransition(
              turns: _spinCtrl,
              child: GestureDetector(
                onTap: _doRefresh,
                child: Container(
                  width: s.d(36), height: s.d(36),
                  decoration: BoxDecoration(color: _refreshing ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                  child: Icon(Icons.refresh_rounded, color: _refreshing ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.5), size: s.d(18)),
                ),
              ),
            ),
            SizedBox(width: s.s(8)),
          ],
          if (_tab == 2 && _canEditTab(2)) ...[
            _EditRequestsHeaderBadge(onReturn: _doRefresh),
            SizedBox(width: s.s(8)),
          ],
          if (_tab == 1 && _canEditTab(1)) ...[
            GestureDetector(
              onTap: () => _showAddProposalSheet(context, svc, s),
              child: Container(
                width: s.d(36), height: s.d(36),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                child: Icon(Icons.person_add_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18)),
              ),
            ),
            SizedBox(width: s.s(8)),
          ],
          if ((_tab == 1 || _tab == 2) && _canEditTab(_tab)) ...[
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminTrashScreen(svc: svc, source: _tab == 1 ? 'orders' : 'users'))),
              child: Container(
                width: s.d(36), height: s.d(36),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                child: Icon(Icons.delete_outline_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18)),
              ),
            ),
            SizedBox(width: s.s(8)),
          ],
          if (_tab == 0 || _tab == 3) ...[
            RotationTransition(
              turns: _spinCtrl,
              child: GestureDetector(
                onTap: _doRefresh,
                child: Container(
                  width: s.d(36), height: s.d(36),
                  decoration: BoxDecoration(color: _refreshing ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                  child: Icon(Icons.refresh_rounded, color: _refreshing ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.5), size: s.d(18)),
                ),
              ),
            ),
            SizedBox(width: s.s(8)),
          ],
          if (_tab == 4) ...[
            GestureDetector(
              onTap: () => _refreshAffiliate?.call(),
              child: Container(width: s.d(36), height: s.d(36), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                child: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18))),
            ),
            SizedBox(width: s.s(8)),
            if (_canEditTab(4)) ...[
              GestureDetector(
                onTap: () => _addAffiliate?.call(),
                child: Container(width: s.d(36), height: s.d(36), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                  child: Icon(Icons.person_add_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18))),
              ),
              SizedBox(width: s.s(8)),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminTrashScreen(svc: svc, source: 'affiliates')))
                  .then((_) { _refreshAffiliate?.call(); _loadAffiliateTrashCount(); }),
                child: Container(width: s.d(36), height: s.d(36), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                  child: Icon(Icons.delete_outline_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18))),
              ),
              SizedBox(width: s.s(8)),
            ],
          ],
          if (_tab == 5) ...[
            GestureDetector(
              onTap: () => _refreshTestimonials?.call(),
              child: Container(
                width: s.d(36), height: s.d(36),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                child: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18))),
            ),
            SizedBox(width: s.s(8)),
          ],
          if (_tab == 6) ...[
            GestureDetector(
              onTap: () => _refreshAds?.call(),
              child: Container(
                width: s.d(36), height: s.d(36),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                child: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18))),
            ),
            SizedBox(width: s.s(8)),
          ],
          if (_tab == 8) ...[
            // Tracking tab — no refresh action needed (search is manual)
            SizedBox(width: s.s(8)),
          ],
          if (_tab == 9) ...[
            GestureDetector(
              onTap: () => _marketingKey.currentState?.refresh(),
              child: Container(
                width: s.d(36), height: s.d(36),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                child: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18)),
              ),
            ),
            SizedBox(width: s.s(8)),
            if (_canEditTab(9)) GestureDetector(
              onTap: () => _marketingKey.currentState?.openTrash(),
              child: Container(
                width: s.d(36), height: s.d(36),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                child: Icon(Icons.delete_outline_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18)),
              ),
            ),
            if (_canEditTab(9)) SizedBox(width: s.s(8)),
            if (_canEditTab(9)) GestureDetector(
              onTap: () => _marketingKey.currentState?.showImportExportMenu(context),
              child: Container(
                width: s.d(36), height: s.d(36),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.arrow_upward_rounded, color: Colors.white.withOpacity(0.5), size: s.d(14)),
                    Transform.translate(
                      offset: Offset(-s.d(4), 0),
                      child: Icon(Icons.arrow_downward_rounded, color: Colors.white.withOpacity(0.5), size: s.d(14)),
                    ),
                  ]),
                ),
              ),
            ),
            SizedBox(width: s.s(8)),
          ],
          if (_tab == 7) ...[
            GestureDetector(
              onTap: () => _refreshVerification?.call(),
              child: Container(
                width: s.d(36), height: s.d(36),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                child: Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18))),
            ),
            SizedBox(width: s.s(8)),
          ],
          if (_tab == _perms.firstVisibleTabIndex && _perms.canView(AdminPageKeys.settings)) ...[
            GestureDetector(
              onTap: () => _showSettingsDialog(context, svc),
              child: Container(width: s.d(36), height: s.d(36), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                child: Icon(Icons.settings_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18))),
            ),
            SizedBox(width: s.s(8)),
          ],
          // ✨ Notification Bell Widget (dashboard tab only)
          if (_tab == _perms.firstVisibleTabIndex) ...[GestureDetector(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminNotificationScreen()));
              _refreshUnreadNotifCount();
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: s.d(36),
                  height: s.d(36),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(s.s(10)),
                  ),
                  child: Icon(Icons.notifications_outlined, color: Colors.white.withOpacity(0.5), size: s.d(18)),
                ),
                if (_unreadNotifCount > 0)
                  Positioned(
                    right: -4, top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: kRose, shape: BoxShape.circle),
                      constraints: BoxConstraints(minWidth: s.d(16), minHeight: s.d(16)),
                      child: Text(
                        _unreadNotifCount > 9 ? '9+' : '$_unreadNotifCount',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: s.f(9), fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: s.s(8)),
          ],
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF16132A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(16))),
                  title: Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: s.f(16))),
                  content: Text('Are you sure you want to logout?', style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: s.f(13.5))),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4)))),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        svc.logout();
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => AdminLoginScreen(adminService: svc)),
                        );
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: s.s(16), vertical: s.s(8)),
                        decoration: BoxDecoration(color: kRose, borderRadius: BorderRadius.circular(s.s(8))),
                        child: Text('Logout', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(13))),
                      ),
                    ),
                  ],
                ),
              );
            },
            child: Container(
              width: s.d(36), height: s.d(36),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
              child: Icon(Icons.logout_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    // Only the tabs this admin may open.
    final visible = _visibleTabIndexes;
    final items = visible.map((i) {
      final page = kAdminTabPages[i];
      return (page.icon, kAdminTabShortLabels[page.key] ?? page.label);
    }).toList();
    final s = _S.of(context);
    // Each tab item is fixed width so the bar scrolls horizontally when
    // there are more tabs than fit on screen — same pattern used by
    // YouTube, Instagram, and other apps with many nav items.
    const double itemWidth = 72;
    return Container(
      height: s.d(64),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.07))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.asMap().entries.map((e) {
            final i = visible[e.key];
            final item = e.value;
            final selected = _tab == i;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _tab = i);
                if (i == 4) _loadAffiliateTrashCount();
                if (i == 6) _refreshAds?.call();
                if (i == 7) _refreshVerification?.call();
              },
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: itemWidth,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          item.$1,
                          size: s.d(22),
                          color: selected ? kPurple : Colors.white.withOpacity(0.3),
                        ),
                        // Badge on Orders tab (index 1)
                        if (i == 1 && _pendingCount > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(color: kRose, shape: BoxShape.circle),
                              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                              child: Text(
                                _pendingCount > 99 ? '99+' : '${_pendingCount}',
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: s.s(3)),
                    Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: s.f(10),
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? kPurple : Colors.white.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Settings option row ────────────────────────────────────────────────────────
class _SettingOption extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  const _SettingOption({required this.icon, required this.color, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.3), size: 20),
        ]),
      ),
    );
  }
}

// ── Dashboard Home ─────────────────────────────────────────────────────────────
class _DashboardHome extends StatelessWidget {
  final AdminService svc;
  final int refreshKey;
  final int affiliateTrashCount;
  final int affiliateTotalCount;
  const _DashboardHome({required this.svc, this.refreshKey = 0,
    this.affiliateTrashCount = 0, this.affiliateTotalCount = 0});

  double get _monthlyRevenue => svc.monthlyRevenue;

  static const _monthNames = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  void _confirmResetStats(BuildContext context, AdminService svc, _S s) {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.dashboard, what: 'resetting stats')) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16132A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(18))),
        title: Text('Reset Stats?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: s.f(16))),
        content: Text(
          'This resets All Time Users, All Time Visitors, All-Time Revenue, and Monthly Revenue back to 0 on the dashboard.',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: s.f(13), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: s.f(13))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              HapticFeedback.heavyImpact();
              try {
                await svc.resetAllTimeStats();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Reset failed: $e'),
                    backgroundColor: kRose,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(12))),
                  ));
                }
              }
            },
            child: Text('Reset', style: TextStyle(color: kRose, fontWeight: FontWeight.w700, fontSize: s.f(13))),
          ),
        ],
      ),
    );
  }

  /// A simple list of every completed month's frozen revenue — no picker,
  /// no range to get wrong, just "here's what each past month made."
  Future<void> _addToCurrentMonthRevenue(BuildContext context) async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.dashboard, what: 'editing revenue')) return;
    final amountCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add to Current Month', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            prefixText: 'Rs. ',
            prefixStyle: const TextStyle(color: Colors.white54),
            hintText: 'e.g. 500 or -500 to subtract',
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(_, true), child: const Text('Add', style: TextStyle(color: kPurple, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (confirmed != true) return;
    final amount = double.tryParse(amountCtrl.text.trim());
    if (amount == null || amount == 0) return;
    final settings = await SupabaseService.instance.fetchAppSettings();
    final monthlyOffset = double.tryParse(settings['monthly_revenue_deleted_offset'] ?? '0') ?? 0;
    final allTimeOffset = double.tryParse(settings['deleted_users_revenue_offset'] ?? '0') ?? 0;
    await Future.wait([
      SupabaseService.instance.client.from('app_settings')
          .upsert({'key': 'monthly_revenue_deleted_offset', 'value': (monthlyOffset + amount).toString()}),
      SupabaseService.instance.client.from('app_settings')
          .upsert({'key': 'deleted_users_revenue_offset', 'value': (allTimeOffset + amount).toString()}),
    ]);
    svc.loadData();
  }

  Future<void> _showRevenueHistory(BuildContext context) async {
    var future = SupabaseService.instance.fetchMonthlyRevenueHistory();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setHistoryState) => Dialog(
        backgroundColor: const Color(0xFF1E1A33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Revenue History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 4),
              Text('Each month is locked in the moment it ends', style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.5))),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360, minWidth: 260),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(child: CircularProgressIndicator(color: kPurple, strokeWidth: 2)),
                      );
                    }
                    final rows = snapshot.data ?? [];
                    if (rows.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: Center(child: Text('No completed months yet',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13))),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withOpacity(0.06)),
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        final y = r['year'] as int;
                        final m = r['month'] as int;
                        final revenue = (r['total_revenue'] as num?)?.toDouble() ?? 0;
                        final revenueCtrl = TextEditingController(text: revenue.toInt().toString());
                        return GestureDetector(
                          onTap: () async {
                                if (!AdminPerms.i.guardEdit(AdminPageKeys.dashboard, what: 'editing revenue')) return;
                                revenueCtrl.text = revenue.toInt().toString();
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    backgroundColor: const Color(0xFF1E1A33),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: Text('Edit ${_monthNames[m]} $y', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                                    content: TextField(
                                      controller: revenueCtrl,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(color: Colors.white, fontSize: 14),
                                      decoration: InputDecoration(
                                        prefixText: 'Rs. ',
                                        prefixStyle: const TextStyle(color: Colors.white54),
                                        filled: true,
                                        fillColor: Colors.white.withOpacity(0.05),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      ),
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                                      TextButton(onPressed: () => Navigator.pop(_, true), child: const Text('Save', style: TextStyle(color: kPurple, fontWeight: FontWeight.w800))),
                                    ],
                                  ),
                                );
                                if (confirmed != true) return;
                                final newVal = double.tryParse(revenueCtrl.text.trim());
                                if (newVal == null) return;
                                final delta = newVal - revenue;
                                final s2 = await SupabaseService.instance.fetchAppSettings();
                                final allTimeOffset2 = double.tryParse(s2['deleted_users_revenue_offset'] ?? '0') ?? 0;
                                final now2 = DateTime.now();
                                final isCurrentMonth = y == now2.year && m == now2.month;
                                final monthlyOffset2 = double.tryParse(s2['monthly_revenue_deleted_offset'] ?? '0') ?? 0;
                                try {
                                  debugPrint('[REV] Saving year=$y month=$m newVal=$newVal');
                                  final res = await SupabaseService.instance.client
                                      .from('monthly_revenue_log')
                                      .update({'total_revenue': newVal})
                                      .eq('year', y)
                                      .eq('month', m)
                                      .select();
                                  debugPrint('[REV] Update result: $res');
                                  final s3 = await SupabaseService.instance.fetchAppSettings();
                                  final allTimeOffset2 = double.tryParse(s3['deleted_users_revenue_offset'] ?? '0') ?? 0;
                                  await SupabaseService.instance.client.from('app_settings')
                                      .upsert({'key': 'deleted_users_revenue_offset', 'value': (allTimeOffset2 + delta).toString()});
                                  if (isCurrentMonth) {
                                    final monthlyOffset2 = double.tryParse(s3['monthly_revenue_deleted_offset'] ?? '0') ?? 0;
                                    await SupabaseService.instance.client.from('app_settings')
                                        .upsert({'key': 'monthly_revenue_deleted_offset', 'value': (monthlyOffset2 + delta).toString()});
                                  }
                                } catch (e, st) {
                                  debugPrint('[REV] ERROR: $e');
                                  debugPrint('[REV] STACK: $st');
                                }
                                svc.loadData();
                                // Refresh data inside popup without closing
                                setHistoryState(() {
                                  future = SupabaseService.instance.fetchMonthlyRevenueHistory();
                                });
                              },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Row(children: [
                              Text('${_monthNames[m]} $y', style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600)),
                              const Spacer(),
                              Text('Rs. ${revenue.toInt()}', style: const TextStyle(color: kGreen, fontSize: 13.5, fontWeight: FontWeight.w800)),
                              const SizedBox(width: 6),
                              const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white24),
                            ]),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Text('Close', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      if (!AdminPerms.i.guardEdit(AdminPageKeys.dashboard, what: 'clearing revenue history')) return;
                      final confirmed = await showDialog<bool>(
                        context: ctx,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF1E1A33),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Clear Revenue History?', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                          content: const Text('This will permanently delete all monthly revenue records. This cannot be undone.', style: TextStyle(color: Colors.white54, fontSize: 13)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                            TextButton(onPressed: () => Navigator.pop(_, true), child: const Text('Clear', style: TextStyle(color: kRose, fontWeight: FontWeight.w800))),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      await SupabaseService.instance.client.from('monthly_revenue_log').delete().gte('year', 0);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: kRose.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: kRose.withOpacity(0.3))),
                      child: const Center(child: Text('Clear History', style: TextStyle(color: kRose, fontWeight: FontWeight.w600, fontSize: 13))),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
        ),
      ),
    );
  }

  bool _hasFeaturedBoostToday(AdminUser u) {
    final now = DateTime.now();
    return u.featuredSchedule.any((b) =>
      !b.isUsed && now.isAfter(b.scheduledDate) && now.isBefore(b.scheduledDate.add(const Duration(hours: 24))));
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(s.s(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Overview', style: TextStyle(fontSize: s.f(18), fontWeight: FontWeight.w700, color: Colors.white)),
        SizedBox(height: s.s(1)),
        Row(children: [
          Text('All-time performance snapshot', style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.4))),
          const Spacer(),
          GestureDetector(
            onTap: () => _confirmResetStats(context, svc, s),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: s.s(9), vertical: s.s(5)),
              decoration: BoxDecoration(
                color: kPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(s.s(8)),
                border: Border.all(color: kPurple.withOpacity(0.25)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.restart_alt_rounded, size: s.d(12), color: kPurple),
                SizedBox(width: s.s(5)),
                Text('Reset Stats', style: TextStyle(fontSize: s.f(11), fontWeight: FontWeight.w700, color: kPurple)),
              ]),
            ),
          ),
        ]),
        SizedBox(height: s.s(16)),
        Row(children: [
          Expanded(child: _BigStatCard(
            label: 'All Time Users',
            value: svc.totalAllTimeSubscribers.toString(),
            rawValue: svc.totalAllTimeSubscribers,
            refreshKey: refreshKey,
            icon: Icons.people_alt_rounded,
            color: const Color(0xFF2563EB),
            bg: const Color(0xFF2563EB).withOpacity(0.12),
          )),
          SizedBox(width: s.s(12)),
          Expanded(child: _BigStatCard(
            label: 'All Time Visitors',
            value: svc.totalUniqueVisitors.toString(),
            rawValue: svc.totalUniqueVisitors,
            refreshKey: refreshKey,
            icon: Icons.visibility_rounded,
            color: const Color(0xFFD41B5E),
            bg: const Color(0xFFD41B5E).withOpacity(0.12),
          )),
        ]),
        SizedBox(height: s.s(12)),
        Row(children: [
          Expanded(child: _BigStatCard(
            label: 'All-Time Revenue',
            value: 'Rs. ${_fmt(svc.allTimeRevenue)}',
            rawValue: svc.allTimeRevenue.toInt(),
            refreshKey: refreshKey,
            icon: Icons.trending_up_rounded,
            color: const Color(0xFFFFB200),
            bg: const Color(0xFFFFB200).withOpacity(0.12),
          )),
          SizedBox(width: s.s(12)),
          Expanded(
            child: Container(
                padding: EdgeInsets.all(s.s(16)),
                decoration: BoxDecoration(
                  color: const Color(0xFF16132A),
                  borderRadius: BorderRadius.circular(s.s(18)),
                  border: Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: s.d(40), height: s.d(40),
                      decoration: BoxDecoration(
                        color: _monthlyRevenue > 0 ? kGreen.withOpacity(0.12) : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(s.s(12)),
                      ),
                      child: Icon(Icons.payments_rounded,
                        color: _monthlyRevenue > 0 ? kGreen : Colors.white24, size: s.d(22)),
                    ),
                    const Spacer(),
                    Row(children: [
                      GestureDetector(
                        onTap: () => _addToCurrentMonthRevenue(context),
                        child: Container(
                          padding: EdgeInsets.all(s.s(6)),
                          decoration: BoxDecoration(color: kPurple.withOpacity(0.12), borderRadius: BorderRadius.circular(s.s(8))),
                          child: Icon(Icons.add_rounded, size: s.d(18), color: kPurple),
                        ),
                      ),
                      SizedBox(width: s.s(6)),
                      GestureDetector(
                        onTap: () => _showRevenueHistory(context),
                        child: Container(
                          padding: EdgeInsets.all(s.s(6)),
                          decoration: BoxDecoration(color: kPurple.withOpacity(0.08), borderRadius: BorderRadius.circular(s.s(8))),
                          child: Icon(Icons.history_rounded, size: s.d(18), color: kPurple.withOpacity(0.6)),
                        ),
                      ),
                    ]),
                  ]),
                  SizedBox(height: s.s(12)),
                  _CountUp(
                    end: _monthlyRevenue.toInt(),
                    refreshKey: refreshKey,
                    prefix: 'Rs. ',
                    style: TextStyle(
                      fontSize: s.f(22), fontWeight: FontWeight.w800,
                      color: _monthlyRevenue > 0 ? kGreen : Colors.white24,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: s.s(2)),
                  Text('Monthly Revenue', style: TextStyle(fontSize: s.f(11.5), color: Colors.white.withOpacity(0.45))),
                ]),
              ),
            ),
        ]),
        SizedBox(height: s.s(24)),
        Text('User Breakdown', style: TextStyle(fontSize: s.f(18), fontWeight: FontWeight.w700, color: Colors.white)),
        SizedBox(height: s.s(12)),
        _StatusBreakdown(svc: svc, refreshKey: refreshKey, affiliateTrashCount: affiliateTrashCount, affiliateTotalCount: affiliateTotalCount),
        SizedBox(height: s.s(16)),
        _CityBreakdownHeader(svc: svc),
      ]),
    );
  }
}

String _fmt(double v) {
  if (v >= 1000000) return '${(v/1000000).toStringAsFixed(1)}M';
  if (v >= 10000) return '${(v/1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
  return v.toStringAsFixed(0);
}


// ── Count-up animation widget ─────────────────────────────────────────────
class _CountUp extends StatefulWidget {
  final int end;
  final TextStyle style;
  final String prefix;
  final String suffix;
  final int refreshKey;
  const _CountUp({required this.end, required this.style, this.prefix = '', this.suffix = '', this.refreshKey = 0});
  @override State<_CountUp> createState() => _CountUpState();
}

class _CountUpState extends State<_CountUp> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  int get _ms => widget.end <= 3 ? 3000 : widget.end <= 5 ? 2500 : widget.end <= 20 ? 1600 : 1200;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: Duration(milliseconds: _ms));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void didUpdateWidget(_CountUp old) {
    super.didUpdateWidget(old);
    if (old.end != widget.end || old.refreshKey != widget.refreshKey) {
      _ctrl.duration = Duration(milliseconds: _ms);
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) {
      final val = (widget.end * _anim.value).round();
      String fmt;
      if (val >= 1000000) fmt = '${(val/1000000).toStringAsFixed(1)}M';
      else if (val >= 10000) fmt = '${(val/1000).toStringAsFixed(val % 1000 == 0 ? 0 : 1)}k';
      else fmt = val.toString();
      return Text('${widget.prefix}$fmt${widget.suffix}', style: widget.style);
    },
  );
}

class _BigStatCard extends StatelessWidget {
  final String label;
  final String value;
  final int? rawValue;
  final int refreshKey;
  final IconData icon;
  final Color color;
  final Color bg;
  const _BigStatCard({
    required this.label, required this.value, this.rawValue, this.refreshKey = 0,
    required this.icon, required this.color, required this.bg,
  });

  bool get _isZero {
    if (rawValue != null) return rawValue == 0;
    return value == '0' || value == 'Rs. 0';
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = _isZero ? Colors.white24 : color;
    final effectiveBg = _isZero ? Colors.white.withOpacity(0.05) : bg;
    final s = _S.of(context);
    return Container(
      padding: EdgeInsets.all(s.s(16)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(s.s(18)),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: s.d(40), height: s.d(40),
          decoration: BoxDecoration(color: effectiveBg, borderRadius: BorderRadius.circular(s.s(12))),
          child: Icon(icon, color: effectiveColor, size: s.d(22)),
        ),
        SizedBox(height: s.s(12)),
        _CountUp(
          end: rawValue ?? int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
          refreshKey: refreshKey,
          prefix: value.startsWith('Rs.') ? 'Rs. ' : '',
          style: TextStyle(fontSize: s.f(22), fontWeight: FontWeight.w800, color: effectiveColor, letterSpacing: -0.5),
        ),
        SizedBox(height: s.s(2)),
        Text(label, style: TextStyle(fontSize: s.f(11.5), color: Colors.white.withOpacity(0.45))),
      ]),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  final AdminService svc;
  final int refreshKey;
  final int affiliateTrashCount;
  final int affiliateTotalCount;
  const _StatusBreakdown({required this.svc, this.refreshKey = 0, this.affiliateTrashCount = 0, this.affiliateTotalCount = 0});

  bool _hasFeaturedBoostToday(AdminUser u) {
    final now = DateTime.now();
    return u.featuredSchedule.any((b) =>
      !b.isUsed && now.isAfter(b.scheduledDate) && now.isBefore(b.scheduledDate.add(const Duration(hours: 24))));
  }

  @override
  Widget build(BuildContext context) {
    final users = svc.users;
    final active   = users.where((u) => u.status == ProposalStatus.active && u.subscriptionStatus == SubscriptionStatus.active).length;
    final inactive = users.where((u) => u.subscriptionStatus == SubscriptionStatus.expired).length;
    final paused   = users.where((u) => u.status == ProposalStatus.paused).length;
    final featured = users.where((u) => _hasFeaturedBoostToday(u)).length;
    final pending  = users.where((u) => u.status == ProposalStatus.pending).length;
    final rejected = users.where((u) => u.status == ProposalStatus.deleted && u.deletedFrom == 'orders').length;
    final removed  = users.where((u) => u.status == ProposalStatus.deleted && u.deletedFrom == 'users').length;
    final affiliate = affiliateTotalCount;

    final activeUsers = users.where((u) => u.status == ProposalStatus.active && u.subscriptionStatus == SubscriptionStatus.active);
    final activeMale   = activeUsers.where((u) => u.gender.toLowerCase() == 'male').length;
    final activeFemale = activeUsers.where((u) => u.gender.toLowerCase() == 'female').length;
    // Count cities/countries using the exact same logic as the User Location
    // section below — so the numbers always match what's shown there.
    final localCitySet = <String>{};
    final countrySet = <String>{};
    for (final u in users) {
      if (u.status == ProposalStatus.deleted) continue;
      if (u.status == ProposalStatus.pending) continue;
      if (u.subscriptionStatus == SubscriptionStatus.expired) continue;
      final isOverseas = u.country != null && u.country!.isNotEmpty &&
          u.country!.toLowerCase() != 'pakistan';
      if (isOverseas) {
        String country = u.country!;
        if (country.toLowerCase() == 'united arab emirates' || country.toLowerCase() == 'uae') country = 'UAE';
        else if (country.toLowerCase() == 'united kingdom' || country.toLowerCase() == 'uk') country = 'UK';
        else if (country.toLowerCase() == 'united states' || country.toLowerCase() == 'united states of america' || country.toLowerCase() == 'usa') country = 'USA';
        else if (country.toLowerCase() == 'ksa' || country.toLowerCase() == 'saudi arabia') country = 'Saudi Arabia';
        countrySet.add(country);
      } else {
        final cityName = u.city == 'Other' && (u.location?.isNotEmpty ?? false) ? u.location! : u.city;
        if (cityName.isNotEmpty && cityName != 'Other') localCitySet.add(cityName);
      }
    }
    final totalCities    = localCitySet.length;
    final totalCountries = countrySet.length;

    // Local vs Overseas
    final localCount = users.where((u) =>
      u.status != ProposalStatus.deleted &&
      u.status != ProposalStatus.pending &&
      u.subscriptionStatus != SubscriptionStatus.expired &&
      (u.country == null || u.country!.isEmpty || u.country!.toLowerCase() == 'pakistan')
    ).length;
    final overseasCount = users.where((u) =>
      u.status != ProposalStatus.deleted &&
      u.status != ProposalStatus.pending &&
      u.subscriptionStatus != SubscriptionStatus.expired &&
      u.country != null && u.country!.isNotEmpty && u.country!.toLowerCase() != 'pakistan'
    ).length;

    final row1 = [('Active', active), ('Inactive', inactive), ('Paused', paused), ('Featured', featured)];
    final row2 = [('Pending', pending), ('Rejected', rejected), ('Removed', removed), ('Affiliate', affiliate)];
    final row3 = [('Male', activeMale), ('Female', activeFemale), ('Cities', totalCities), ('Countries', totalCountries)];

    final sc = _S.of(context);
    Widget cell(String label, int count) => Expanded(
      child: Column(children: [
        _CountUp(end: count, refreshKey: refreshKey,
          style: TextStyle(fontSize: sc.f(22), fontWeight: FontWeight.w800, color: count == 0 ? Colors.white24 : kPurple)),
        SizedBox(height: sc.s(2)),
        Text(label, style: TextStyle(fontSize: sc.f(10.5), color: Colors.white.withOpacity(0.4))),
      ]),
    );

    return Container(
      padding: EdgeInsets.all(sc.s(16)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(sc.s(18)),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(children: [
        Row(children: row1.map((t) => cell(t.$1, t.$2)).toList()),
        SizedBox(height: sc.s(14)),
        Container(height: 1, color: Colors.white.withOpacity(0.07)),
        SizedBox(height: sc.s(14)),
        Row(children: row2.map((t) => cell(t.$1, t.$2)).toList()),
        SizedBox(height: sc.s(14)),
        Container(height: 1, color: Colors.white.withOpacity(0.07)),
        SizedBox(height: sc.s(14)),
        Row(children: row3.map((t) => cell(t.$1, t.$2)).toList()),
        SizedBox(height: sc.s(14)),
        Container(height: 1, color: Colors.white.withOpacity(0.07)),
        SizedBox(height: sc.s(14)),
        FutureBuilder<List<int>>(
          future: Future.wait([
            SupabaseService.instance.client.from('coupon_codes').select('id').then((r) => (r as List).length),
            SupabaseService.instance.client.from('ads').select('id').then((r) => (r as List).length),
          ]),
          builder: (_, snap) {
            final d = snap.data ?? [0, 0];
            return Row(children: [cell('Local', localCount), cell('Overseas', overseasCount), cell('Coupons', d[0]), cell('Ads', d[1])]);
          },
        ),
        SizedBox(height: sc.s(14)),
        Container(height: 1, color: Colors.white.withOpacity(0.07)),
        SizedBox(height: sc.s(14)),
        FutureBuilder<List<int>>(
          future: Future.wait([
            // Edit requests: count distinct proposals with at least one 'applied' field
            SupabaseService.instance.client.from('profile_edit_requests').select('proposal_id').eq('status', 'applied')
                .then((r) => (r as List).map((e) => e['proposal_id']).toSet().length),
            SupabaseService.instance.client.from('profile_reports').select('id').eq('status', 'pending').then((r) => (r as List).length),
            SupabaseService.instance.client.from('cnic_verification_requests').select('id').eq('status', 'pending').then((r) => (r as List).length),
            SupabaseService.instance.client.from('admin_accounts').select('id').then((r) => (r as List).length),
          ]),
          builder: (_, snap) {
            final d = snap.data ?? [0, 0, 0, 0];
            return Row(children: [cell('Review', d[0]), cell('Report', d[1]), cell('Verify', d[2]), cell('Admins', d[3])]);
          },
        ),
      ]),
    );
  }
}

// ── City Breakdown ─────────────────────────────────────────────────────────────
class _CityBreakdownHeader extends StatefulWidget {
  final AdminService svc;
  const _CityBreakdownHeader({required this.svc});
  @override
  State<_CityBreakdownHeader> createState() => _CityBreakdownHeaderState();
}

class _CityBreakdownHeaderState extends State<_CityBreakdownHeader> {
  bool _isLocal = true;

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final users = widget.svc.users;

    // Build local (Pakistan) city map
    final localMap = <String, int>{};
    final overseasMap = <String, int>{};
    for (final u in users) {
      if (u.status == ProposalStatus.deleted) continue;
      if (u.status == ProposalStatus.pending) continue;
      if (u.subscriptionStatus == SubscriptionStatus.expired) continue;
      final isOverseas = u.country != null && u.country!.isNotEmpty &&
          u.country!.toLowerCase() != 'pakistan';
      if (isOverseas) {
        // Normalize UAE variants
        String country = u.country!;
        if (country.toLowerCase() == 'united arab emirates' || country.toLowerCase() == 'uae') {
          country = 'UAE';
        } else if (country.toLowerCase() == 'united kingdom' || country.toLowerCase() == 'uk') {
          country = 'UK';
        } else if (country.toLowerCase() == 'united states' || country.toLowerCase() == 'united states of america' || country.toLowerCase() == 'usa') {
          country = 'USA';
        } else if (country.toLowerCase() == 'ksa' || country.toLowerCase() == 'saudi arabia') {
          country = 'Saudi Arabia';
        }
        overseasMap[country] = (overseasMap[country] ?? 0) + 1;
      } else {
        final cityName = u.city == 'Other' && (u.location?.isNotEmpty ?? false)
            ? u.location!
            : u.city;
        if (cityName.isNotEmpty && cityName != 'Other') {
          localMap[cityName] = (localMap[cityName] ?? 0) + 1;
        }
      }
    }

    final sorted = (_isLocal ? localMap : overseasMap).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxCount = sorted.isEmpty ? 1 : sorted.first.value;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Heading + toggle ──
      Row(children: [
        Text('User Location', style: TextStyle(fontSize: s.f(18), fontWeight: FontWeight.w700, color: Colors.white)),
        const Spacer(),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(s.s(20)),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _ToggleBtn(label: 'Local', selected: _isLocal, onTap: () => setState(() => _isLocal = true)),
            _ToggleBtn(label: 'Overseas', selected: !_isLocal, onTap: () => setState(() => _isLocal = false)),
          ]),
        ),
      ]),
      SizedBox(height: s.s(12)),

      // ── Card ──
      if (sorted.isEmpty)
        Container(
          padding: EdgeInsets.all(s.s(16)),
          decoration: BoxDecoration(
            color: const Color(0xFF16132A),
            borderRadius: BorderRadius.circular(s.s(18)),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Center(child: Text(
            _isLocal ? 'No local users' : 'No overseas users',
            style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.3)),
          )),
        )
      else
        Container(
          padding: EdgeInsets.all(s.s(16)),
          decoration: BoxDecoration(
            color: const Color(0xFF16132A),
            borderRadius: BorderRadius.circular(s.s(18)),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: _buildLocationList(sorted, maxCount, s),
        ),
    ]);
  }
}

  Widget _locationRow(MapEntry<String, int> entry, double fraction, int maxCount, _S s) {
    return Row(children: [
      SizedBox(
        width: s.s(96),
        child: Text(entry.key,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w600, color: Colors.white70)),
      ),
      SizedBox(width: s.s(10)),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(s.s(4)),
          child: Stack(children: [
            Container(height: s.d(6), color: Colors.white.withOpacity(0.07)),
            FractionallySizedBox(
              widthFactor: fraction,
              child: Container(
                height: s.d(6),
                decoration: BoxDecoration(
                  color: kPurple.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(s.s(4)),
                ),
              ),
            ),
          ]),
        ),
      ),
      SizedBox(width: s.s(8)),
      SizedBox(
        width: s.s(44),
        child: Text('${entry.value}',
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w700,
            color: entry.value == maxCount ? kPurple : Colors.white.withOpacity(0.45))),
      ),
    ]);
  }

  Widget _buildLocationList(List<MapEntry<String, int>> sorted, int maxCount, _S s) {
    Widget row(int i) {
      final entry = sorted[i];
      final fraction = maxCount > 0 ? entry.value / maxCount : 0.0;
      return _locationRow(entry, fraction, maxCount, s);
    }
    // Show 12 rows visible, rest scrollable — no divider, seamless flow
    final itemHeight = s.s(10) + s.d(6) + s.s(10); // separator + bar + padding
    final visibleHeight = 12 * itemHeight;
    return SizedBox(
      height: sorted.length <= 12 ? null : visibleHeight,
      child: ListView.separated(
        shrinkWrap: sorted.length <= 12,
        physics: sorted.length <= 12
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics(),
        itemCount: sorted.length,
        separatorBuilder: (_, __) => SizedBox(height: s.s(10)),
        itemBuilder: (_, i) => row(i),
      ),
    );
  }


class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: s.s(12), vertical: s.s(5)),
        decoration: BoxDecoration(
          color: selected ? kPurple : Colors.transparent,
          borderRadius: BorderRadius.circular(s.s(20)),
        ),
        child: Text(label, style: TextStyle(
          fontSize: s.f(11),
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? Colors.white : Colors.white.withOpacity(0.4),
        )),
      ),
    );
  }
}


// ── Edit Requests header badge ──────────────────────────────────────────────
// Sits in the dashboard header next to refresh. Shows a count of profiles
// that still have at least one field neither ticked (kept) nor crossed
// (reverted) — reuses the same EditRequest.build() walk-algorithm as the
// review screen itself, so the two always agree. Self-manages its own
// reload after returning from that screen.
class _EditRequestsHeaderBadge extends StatefulWidget {
  final VoidCallback? onReturn;
  const _EditRequestsHeaderBadge({this.onReturn});
  @override State<_EditRequestsHeaderBadge> createState() => _EditRequestsHeaderBadgeState();
}

class _EditRequestsHeaderBadgeState extends State<_EditRequestsHeaderBadge> {
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    try {
      final data = await Supabase.instance.client
          .from('profile_edit_requests')
          .select('*, proposals(name, city, cnic, proposal_number)')
          .order('submitted_at', ascending: true)
          .limit(1000);

      final Map<String, List<Map<String, dynamic>>> byProposal = {};
      final Map<String, Map<String, dynamic>> metaByProposal = {};
      for (final row in data as List) {
        final r = row as Map<String, dynamic>;
        final pid = r['proposal_id'] as String;
        byProposal.putIfAbsent(pid, () => []).add(r);
        metaByProposal[pid] = (r['proposals'] as Map<String, dynamic>?) ?? {};
      }

      final editCount = byProposal.entries
          .map((entry) => EditRequest.build(
                proposalId: entry.key,
                rows: entry.value,
                proposalMeta: metaByProposal[entry.key] ?? {},
              ))
          .where((req) => req.hasPending)
          .length;

      // Collective count now — pending edits, reports, AND CNIC
      // verification requests together, since this one icon is the
      // entry point for all three (via the Review/Report/Verify toggle
      // inside AdminEditRequestsScreen).
      int reportCount = 0;
      try {
        final reportData = await Supabase.instance.client
            .from('profile_reports')
            .select('id')
            .eq('status', 'pending');
        reportCount = (reportData as List).length;
      } catch (_) {}

      int verificationCount = 0;
      try {
        final verificationData = await Supabase.instance.client
            .from('cnic_verification_requests')
            .select('id')
            .eq('status', 'pending');
        verificationCount = (verificationData as List).length;
      } catch (_) {}

      if (mounted) setState(() => _pendingCount = editCount + reportCount + verificationCount);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return GestureDetector(
      onTap: () async {
        await Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AdminEditRequestsScreen()));
        _loadCount();
        widget.onReturn?.call();
      },
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: s.d(36), height: s.d(36),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
          child: Icon(Icons.edit_note_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18)),
        ),
        if (_pendingCount > 0)
          Positioned(
            right: -4, top: -4,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: s.s(5), vertical: s.s(1)),
              decoration: BoxDecoration(
                color: kRose, borderRadius: BorderRadius.circular(s.s(10)),
                border: Border.all(color: const Color(0xFF0F0D1E), width: 1.5),
              ),
              child: Text('${_pendingCount}',
                style: TextStyle(color: Colors.white, fontSize: s.f(9), fontWeight: FontWeight.w800)),
            ),
          ),
      ]),
    );
  }
}
