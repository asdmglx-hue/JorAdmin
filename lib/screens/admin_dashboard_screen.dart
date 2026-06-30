import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../services/admin_service.dart';
import '../models/admin_models.dart';
import 'admin_users_screen.dart';
import 'admin_proposals_screen.dart';
import 'admin_trash_screen.dart';
import 'admin_pricing_screen.dart';
import 'admin_locations_screen.dart';
import 'admin_affiliate_screen.dart';
import 'admin_add_user_screen.dart';
import 'admin_whatsapp_import_screen.dart';

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
  int _tab = 0;
  VoidCallback? _addAffiliate;
  VoidCallback? _refreshAffiliate;
  bool _refreshing = false;
  int _affiliateTrashCount = 0;
  int _affiliateTotalCount = 0;
  int _pendingCount = 0;
  int _refreshKey = 0;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
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
    _loadAffiliateTrashCount();
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
        _affiliateTotalCount = (totalRes as List).length;
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
        title: const Text('Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _SettingOption(
            icon: Icons.pin_rounded,
            color: kPurple,
            label: 'Change PIN',
            onTap: () { Navigator.pop(ctx); _showChangePinDialog(ctx); },
          ),
          const SizedBox(height: 10),
          _SettingOption(
            icon: Icons.chat_rounded,
            color: const Color(0xFF25D366),
            label: 'Change WhatsApp',
            onTap: () { Navigator.pop(ctx); _showChangeWaDialog(ctx); },
          ),
          const SizedBox(height: 10),
          _SettingOption(
            icon: Icons.visibility_rounded,
            color: kAmber,
            label: 'Admin View',
            onTap: () { Navigator.pop(ctx); _showAdminViewDialog(ctx); },
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

  void _showChangePinDialog(BuildContext ctx) {
    final oldPinCtrl = TextEditingController();
    final newPinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool saving = false;
    String? error;

    showDialog(
      context: ctx,
      builder: (_) => StatefulBuilder(
        builder: (dlgCtx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF16132A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.pin_rounded, color: kPurple, size: 20),
            const SizedBox(width: 8),
            const Text('Change PIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _pinField(oldPinCtrl, 'Current PIN'),
            const SizedBox(height: 12),
            _pinField(newPinCtrl, 'New PIN'),
            const SizedBox(height: 12),
            _pinField(confirmCtrl, 'Confirm New PIN'),
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
            GestureDetector(
              onTap: saving ? null : () async {
                final op = oldPinCtrl.text.trim();
                final np = newPinCtrl.text.trim();
                final cp = confirmCtrl.text.trim();
                if (op.length != 6) { setDlg(() => error = 'Current PIN must be 6 digits'); return; }
                if (np.length != 6) { setDlg(() => error = 'New PIN must be 6 digits'); return; }
                if (np != cp) { setDlg(() => error = 'PINs do not match'); return; }
                setDlg(() { saving = true; error = null; });
                try {
                  const email = 'admin@jorapp.com';
                  final reauth = await SupabaseService.instance.client.auth.signInWithPassword(
                    email: email, password: op,
                  );
                  if (reauth.user == null) {
                    setDlg(() { saving = false; error = 'Current PIN is incorrect'; });
                    return;
                  }
                  await SupabaseService.instance.client.auth.updateUser(
                    UserAttributes(password: np),
                  );
                  if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('PIN changed successfully!'),
                    backgroundColor: kGreen,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ));
                } catch (e) {
                  setDlg(() { saving = false; error = 'Current PIN is incorrect'; });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(8)),
                child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAdminViewDialog(BuildContext ctx) async {
    final cnicCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    await SupabaseService.instance.fetchAppSettings();
    final isFirstSetup = (SupabaseService.instance.cachedSettings['admin_view_cnic'] ?? '').isEmpty;

    if (!ctx.mounted) return;

    // Instantiate ONCE before showing — prevents builder from recreating it on every setState
    final dialog = _AdminViewDialog(
      isFirstSetup: isFirstSetup,
      cnicCtrl: cnicCtrl,
      passCtrl: passCtrl,
      onSuccess: (cnic, isNew) {
        Navigator.of(ctx).pop();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isNew
            ? 'Admin credentials created successfully!'
            : isFirstSetup
              ? 'Admin credentials saved!'
              : 'Admin credentials updated successfully.'),
          backgroundColor: kAmber,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      },
    );

    showDialog(
      context: ctx,
      builder: (_) => dialog,
    );
  }

  void _showChangeWaDialog(BuildContext ctx) {
    final waCtrl = TextEditingController(
      text: SupabaseService.instance.cachedSettings['whatsapp_number'] ?? '923000000000',
    );
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
            GestureDetector(
              onTap: saving ? null : () async {
                final num = waCtrl.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
                if (num.length < 10) { setDlg(() => error = 'Enter a valid number'); return; }
                setDlg(() { saving = true; error = null; success = null; });
                try {
                  await SupabaseService.instance.client.from('app_settings')
                    .upsert({'key': 'whatsapp_number', 'value': num});
                  await SupabaseService.instance.fetchAppSettings();
                  if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('WhatsApp number updated!'),
                    backgroundColor: kGreen,
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ));
                } catch (e) {
                  setDlg(() { saving = false; error = 'Failed to save'; });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFF25D366), borderRadius: BorderRadius.circular(8)),
                child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _pinField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 8),
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
    // Force light status bar icons (white) for dark admin background
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF0F0D1A),
      statusBarIconBrightness: Brightness.light,
    ));
    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(svc),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _DashboardHome(svc: svc, refreshKey: _refreshKey, selectedMonth: _selectedMonth, onMonthChanged: (m) => setState(() { _selectedMonth = m; _refreshKey++; }), affiliateTrashCount: _affiliateTrashCount, affiliateTotalCount: _affiliateTotalCount),
                  AdminProposalsScreen(svc: svc),
                  AdminUsersScreen(svc: svc),
                  const AdminPricingScreen(),
                  AdminAffiliateScreen(onRegisterCallback: (cb) => _addAffiliate = cb, onRefreshCallback: (cb) => _refreshAffiliate = cb, onAffiliateDeleted: _loadAffiliateTrashCount),
                  const AdminLocationsScreen(),
                ],
              ),
            ),
            _buildBottomNav(),
          ],
        ),
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
          if (_tab == 1) ...[
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
          if (_tab == 1 || _tab == 2) ...[
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
          if (_tab == 0) ...[
            GestureDetector(
              onTap: () => _showSettingsDialog(context, svc),
              child: Container(width: s.d(36), height: s.d(36), decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                child: Icon(Icons.settings_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18))),
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
                      onTap: () { Navigator.pop(context); svc.logout(); Navigator.pop(context); },
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
    final items = [
      (Icons.dashboard_rounded, 'Dashboard'),
      (Icons.shopping_cart_rounded, 'Orders'),
      (Icons.people_rounded, 'Users'),
      (Icons.attach_money_rounded, 'Pricing'),
      (Icons.handshake_outlined, 'Affiliate'),
      (Icons.location_on_rounded, 'Locations'),
    ];
    final s = _S.of(context);
    return Container(
      height: s.d(64),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.07))),
      ),
      child: Row(
        children: items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          final selected = _tab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _tab = i);
              if (i == 4) _loadAffiliateTrashCount();
              },
              behavior: HitTestBehavior.opaque,
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
                              _pendingCount > 99 ? '99+' : '$_pendingCount',
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
  final DateTime selectedMonth;
  final void Function(DateTime) onMonthChanged;
  final int affiliateTrashCount;
  final int affiliateTotalCount;
  const _DashboardHome({required this.svc, this.refreshKey = 0,
    required this.selectedMonth, required this.onMonthChanged, this.affiliateTrashCount = 0, this.affiliateTotalCount = 0});

  double get _monthlyRevenue {
    // Use the DB-backed monthlyRevenue which includes permanently deleted users' contributions
    final now = DateTime.now();
    if (selectedMonth.year == now.year && selectedMonth.month == now.month) {
      return svc.monthlyRevenue;
    }
    // For past months, compute from live users only (deleted users' past months not tracked)
    final monthEnd = DateTime(selectedMonth.year, selectedMonth.month + 1, 1);
    return svc.users
        .where((u) => u.subscriptionStart != null &&
            !u.subscriptionStart!.isBefore(selectedMonth) &&
            u.subscriptionStart!.isBefore(monthEnd))
        .fold(0.0, (sum, u) => sum + u.totalSpending);
  }

  Future<void> _pickMonth(BuildContext context) async {
    final now = DateTime.now();
    DateTime? tempFrom = selectedMonth;
    DateTime? tempTo;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: const Color(0xFF1E1A33),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filter Revenue by Date', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 4),
                Text('Select a date range to filter monthly revenue', style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.5))),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: tempFrom ?? now,
                      firstDate: DateTime(2024),
                      lastDate: now,
                      builder: (ctx, child) => Theme(
                        data: ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(primary: kPurple, onPrimary: Colors.white, surface: Color(0xFF2A2545), onSurface: Colors.white),
                        ),
                        child: child!,
                      ),
                    );
                    if (d != null) setS(() { tempFrom = d; if (tempTo != null && tempTo!.isBefore(d)) tempTo = null; });
                  },
                  child: _dateBtn('From', tempFrom),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: tempTo ?? tempFrom ?? now,
                      firstDate: tempFrom ?? DateTime(2024),
                      lastDate: now,
                      builder: (ctx, child) => Theme(
                        data: ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(primary: kPurple, onPrimary: Colors.white, surface: Color(0xFF2A2545), onSurface: Colors.white),
                        ),
                        child: child!,
                      ),
                    );
                    if (d != null) setS(() => tempTo = d);
                  },
                  child: _dateBtn('To', tempTo),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () {
                      onMonthChanged(DateTime(now.year, now.month, 1));
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Text('Reset', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13))),
                    ),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: GestureDetector(
                    onTap: () {
                      if (tempFrom != null) onMonthChanged(DateTime(tempFrom!.year, tempFrom!.month, 1));
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
                    ),
                  )),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateBtn(String label, DateTime? date) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: date != null ? kPurple.withOpacity(0.1) : Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: date != null ? kPurple.withOpacity(0.4) : Colors.white.withOpacity(0.1)),
    ),
    child: Row(children: [
      Icon(Icons.calendar_today_rounded, size: 14, color: date != null ? kPurple : Colors.white38),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w600)),
      const Spacer(),
      Text(date != null ? '${date.day}/${date.month}/${date.year}' : 'Select',
          style: TextStyle(fontSize: 13, color: date != null ? Colors.white : Colors.white38, fontWeight: FontWeight.w700)),
    ]),
  );

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
        SizedBox(height: s.s(4)),
        Text('All-time performance snapshot', style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.4))),
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
            child: GestureDetector(
              onTap: () => _pickMonth(context),
              child: Container(
                padding: EdgeInsets.all(s.s(16)),
                decoration: BoxDecoration(
                  color: const Color(0xFF16132A),
                  borderRadius: BorderRadius.circular(s.s(18)),
                  border: Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
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
                    Transform.translate(
                      offset: const Offset(0, -10),
                      child: Icon(Icons.calendar_today_rounded, size: s.d(14), color: kPurple),
                    ),
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
  if (v >= 1000) return '${(v/1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
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
      else if (val >= 1000) fmt = '${(val/1000).toStringAsFixed(val % 1000 == 0 ? 0 : 1)}k';
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

    final row1 = [('Active', active), ('Inactive', inactive), ('Paused', paused), ('Featured', featured)];
    final row2 = [('Pending', pending), ('Rejected', rejected), ('Removed', removed), ('Affiliate', affiliate)];

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
      final isOverseas = u.country != null && u.country!.isNotEmpty;
      if (isOverseas) {
        // Normalize UAE variants
        String country = u.country!;
        if (country.toLowerCase() == 'united arab emirates' || country.toLowerCase() == 'uae') {
          country = 'UAE';
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
          child: ListView.separated(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => SizedBox(height: s.s(10)),
            itemBuilder: (_, i) {
              final entry = sorted[i];
              final fraction = maxCount > 0 ? entry.value / maxCount : 0.0;
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
                SizedBox(width: s.s(10)),
                SizedBox(
                  width: s.s(28),
                  child: Text('${entry.value}',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w700,
                      color: entry.value == maxCount ? kPurple : Colors.white.withOpacity(0.45))),
                ),
              ]);
            },
          ),
        ),
    ]);
  }
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

// ── CNIC auto-formatter for admin view dialog ─────────────────────────────────
class _CnicDashFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue val) {
    final digits = val.text.replaceAll('-', '');
    if (digits.length > 13) return old;
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 5 || i == 12) buf.write('-');
      buf.write(digits[i]);
    }
    final s = buf.toString();
    return val.copyWith(text: s, selection: TextSelection.collapsed(offset: s.length));
  }
}

// ── Admin View Dialog ─────────────────────────────────────────────────────────
class _AdminViewDialog extends StatefulWidget {
  final bool isFirstSetup;
  final TextEditingController cnicCtrl;
  final TextEditingController passCtrl;
  final void Function(String cnic, bool isNew) onSuccess;

  _AdminViewDialog({
    required this.isFirstSetup,
    required this.cnicCtrl,
    required this.passCtrl,
    required this.onSuccess,
  });

  @override
  State<_AdminViewDialog> createState() => _AdminViewDialogState();
}

class _AdminViewDialogState extends State<_AdminViewDialog> {
  bool _saving      = false;
  bool _passObscure = true;
  bool _isCreateNew = false; // false = update existing, true = create new
  int  _cnicDigits  = 0;
  String? _error;

  Future<void> _submit() async {
    final cnic = widget.cnicCtrl.text.trim();
    final pass = widget.passCtrl.text.trim();

    if (cnic.replaceAll('-', '').length != 13) {
      setState(() => _error = 'Enter complete CNIC (13 digits)');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      final client = SupabaseService.instance.client;

      if (_isCreateNew) {
        // Load existing credentials list and append new one
        final existing = SupabaseService.instance.cachedSettings['admin_view_credentials'] ?? '[]';
        List<dynamic> list = [];
        try { list = List<dynamic>.from(jsonDecode(existing)); } catch (_) {}
        // Check for duplicate CNIC
        if (list.any((e) => e['cnic'] == cnic)) {
          setState(() { _saving = false; _error = 'This CNIC already has credentials'; });
          return;
        }
        list.add({'cnic': cnic, 'password': pass});
        await client.rpc('upsert_app_setting', params: {'p_key': 'admin_view_credentials', 'p_value': jsonEncode(list)});
      } else {
        // Update the primary credential
        await client.rpc('upsert_app_setting', params: {'p_key': 'admin_view_cnic',     'p_value': cnic});
        await client.rpc('upsert_app_setting', params: {'p_key': 'admin_view_password', 'p_value': pass});
      }
      await SupabaseService.instance.fetchAppSettings();

      widget.onSuccess(cnic, _isCreateNew);
    } catch (e) {
      setState(() { _saving = false; _error = 'Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF16132A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Icon(Icons.visibility_rounded, color: kAmber, size: 20),
        const SizedBox(width: 8),
        Text(
          widget.isFirstSetup ? 'Set Admin Credentials' : (_isCreateNew ? 'Create New Credential' : 'Update Credentials'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Toggle: Update existing vs Create new
        if (!widget.isFirstSetup) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(children: [
              Icon(_isCreateNew ? Icons.person_add_rounded : Icons.edit_rounded,
                color: _isCreateNew ? kGreen : kAmber, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                _isCreateNew ? 'Create New Credential' : 'Update Existing',
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w600),
              )),
              Switch(
                value: _isCreateNew,
                onChanged: (v) => setState(() { _isCreateNew = v; _error = null; widget.cnicCtrl.clear(); widget.passCtrl.clear(); _cnicDigits = 0; }),
                activeColor: kGreen,
                inactiveThumbColor: kAmber,
                inactiveTrackColor: kAmber.withOpacity(0.3),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        // CNIC field
        Stack(children: [
          TextField(
            controller: widget.cnicCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
              _CnicDashFormatter(),
            ],
            style: const TextStyle(color: Colors.white, fontSize: 14),
            onChanged: (v) => setState(() { _cnicDigits = v.replaceAll('-', '').length; _error = null; }),
            decoration: InputDecoration(
              hintText: '35202-1234567-1',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
              filled: true, fillColor: Colors.white.withOpacity(0.06),
              contentPadding: const EdgeInsets.fromLTRB(14, 12, 48, 12),
              prefixIcon: Icon(Icons.credit_card_rounded, color: Colors.white.withOpacity(0.4), size: 18),
              border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: kAmber.withOpacity(0.6))),
            ),
          ),
          Positioned(right: 10, top: 0, bottom: 0,
            child: Center(child: _cnicDigits == 0
              ? const SizedBox.shrink()
              : _cnicDigits == 13
                ? Icon(Icons.check_circle_rounded, size: 16, color: kGreen)
                : Text('$_cnicDigits/13', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))))),
        ]),
        const SizedBox(height: 12),
        // Password field
        TextField(
          controller: widget.passCtrl,
          obscureText: _passObscure,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'New password (min 6 chars)',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
            filled: true, fillColor: Colors.white.withOpacity(0.06),
            contentPadding: const EdgeInsets.fromLTRB(14, 12, 48, 12),
            prefixIcon: Icon(Icons.lock_outline_rounded, color: Colors.white.withOpacity(0.4), size: 18),
            suffixIcon: IconButton(
              icon: Icon(_passObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.white.withOpacity(0.4), size: 18),
              onPressed: () => setState(() => _passObscure = !_passObscure),
            ),
            border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: kAmber.withOpacity(0.6))),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(fontSize: 12, color: kRose)),
        ],
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4))),
        ),
        GestureDetector(
          onTap: _saving ? null : _submit,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: kAmber, borderRadius: BorderRadius.circular(8)),
            child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(
                  widget.isFirstSetup ? 'Save' : 'Update',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ),
      ],
    );
  }
}
