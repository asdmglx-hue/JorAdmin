import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../models/admin_permissions.dart';
import '../services/admin_supabase_extension.dart';
import '../models/admin_models.dart';
import '../utils/theme.dart';
import '../utils/realtime_refresh.dart';

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

// ─────────────────────────────────────────────────────────────────────────────
//  AdminPricingScreen — admin sets Standard plan & Featured post prices
// ─────────────────────────────────────────────────────────────────────────────
class AdminPricingScreen extends StatefulWidget {
  const AdminPricingScreen({super.key});
  @override
  State<AdminPricingScreen> createState() => _AdminPricingScreenState();
}

class _AdminPricingScreenState extends State<AdminPricingScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  bool _saving   = false;
  bool _freeMode = false;
  // When Free Mode is on, restrict the free unlock to CNICs that have never
  // had an active subscription before (a genuine "new user" trial), rather
  // than making every user's unlock free — with its own trial length,
  // separate from the normal Standard Plan duration.
  bool _freeModeNewUsersOnly = false;
  final _freeModeTrialDaysCtrl = TextEditingController();
  bool _referralEnabled = true;
  bool _referralSignupEnabled = true;
  bool _helpCenterEnabled = true;
  String _helpCenterPageName = 'Help Center';
  String _paymentMode = 'auto'; // 'auto' = online SafePay, 'manual' = bank transfer only
  bool _paymentSectionExpanded = false;
  bool _pricingSectionExpanded = false;
  final _referralRateCtrl     = TextEditingController();
  final _accountNumberCtrl    = TextEditingController();
  final _accountTitleCtrl     = TextEditingController();
  final _paymentInstructionCtrl = TextEditingController();
  final _featuredInstructionCtrl = TextEditingController();
  final _bankNameCtrl         = TextEditingController();
  final _bankAccountCtrl      = TextEditingController();
  final _bankHolderCtrl       = TextEditingController();
  final _bankSwiftCtrl        = TextEditingController();
  String? _error;

  // Snapshot of every saved value, taken right after loading (and again
  // right after a successful save) — compared against the live current
  // values to decide whether the Save button should be enabled at all.
  Map<String, String> _originalSnapshot = {};

  Map<String, String> _currentSnapshot() => {
        'free_mode': _freeMode.toString(),
        'free_mode_new_users_only': _freeModeNewUsersOnly.toString(),
        'free_mode_trial_days': _freeModeTrialDaysCtrl.text.trim(),
        'standard_plan_price': _standardPriceCtrl.text.trim(),
        'standard_plan_days': _standardDaysCtrl.text.trim(),
        'featured_post_price': _featuredPriceCtrl.text.trim(),
        'featured_post_duration': _featuredDaysCtrl.text.trim(),
        'max_featured_per_city': _featuredMaxPerCityCtrl.text.trim(),
        'max_featured_general': _featuredMaxGeneralCtrl.text.trim(),
        'referral_enabled': _referralEnabled.toString(),
        'referral_signup_enabled': _referralSignupEnabled.toString(),
        'help_center_enabled': _helpCenterEnabled.toString(),
        'help_center_page_name': _helpCenterPageName,
        'referral_commission': _referralRateCtrl.text.trim(),
        'payment_mode': _paymentMode,
        'account_number': _accountNumberCtrl.text.trim(),
        'account_title': _accountTitleCtrl.text.trim(),
        'payment_instruction': _paymentInstructionCtrl.text.trim(),
        'featured_payment_instruction': _featuredInstructionCtrl.text.trim(),
        'bank_name': _bankNameCtrl.text.trim(),
        'bank_account': _bankAccountCtrl.text.trim(),
        'bank_holder': _bankHolderCtrl.text.trim(),
        'bank_swift': _bankSwiftCtrl.text.trim(),
      };

  bool get _hasChanges => !mapEquals(_currentSnapshot(), _originalSnapshot);

  // Controllers
  final _standardPriceCtrl  = TextEditingController();
  final _standardDaysCtrl   = TextEditingController();
  final _featuredPriceCtrl  = TextEditingController();
  final _featuredDaysCtrl   = TextEditingController();
  final _featuredMaxPerCityCtrl = TextEditingController();
  final _featuredMaxGeneralCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [
      _standardPriceCtrl, _standardDaysCtrl, _featuredPriceCtrl, _featuredDaysCtrl,
      _featuredMaxPerCityCtrl, _featuredMaxGeneralCtrl,
      _freeModeTrialDaysCtrl, _referralRateCtrl, _accountNumberCtrl, _accountTitleCtrl,
      _paymentInstructionCtrl, _featuredInstructionCtrl, _bankNameCtrl, _bankAccountCtrl,
      _bankHolderCtrl, _bankSwiftCtrl,
    ]) {
      c.addListener(() { if (mounted) setState(() {}); });
    }
    _loadSettings();
  }

  @override
  void dispose() {
    _standardPriceCtrl.dispose();
    _standardDaysCtrl.dispose();
    _featuredPriceCtrl.dispose();
    _featuredDaysCtrl.dispose();
    _featuredMaxPerCityCtrl.dispose();
    _featuredMaxGeneralCtrl.dispose();
    _referralRateCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountTitleCtrl.dispose();
    _paymentInstructionCtrl.dispose();
    _featuredInstructionCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankAccountCtrl.dispose();
    _bankHolderCtrl.dispose();
    _bankSwiftCtrl.dispose();
    _freeModeTrialDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _client.from('app_settings').select();
      final map = { for (final r in res as List) r['key'] as String : r['value'] as String };
      _standardPriceCtrl.text  = map['standard_plan_price']    ?? '1000';
      _standardDaysCtrl.text   = map['standard_plan_days']     ?? '90';
      _featuredPriceCtrl.text  = map['featured_post_price']    ?? '200';
      _featuredDaysCtrl.text   = map['featured_post_duration'] ?? '1';
      _featuredMaxPerCityCtrl.text = map['max_featured_per_city'] ?? '5';
      _featuredMaxGeneralCtrl.text = map['max_featured_general'] ?? '20';
      _freeMode = map['free_mode'] == 'true';
      _freeModeNewUsersOnly = map['free_mode_new_users_only'] == 'true';
      _freeModeTrialDaysCtrl.text = map['free_mode_trial_days'] ?? '30';
      _referralEnabled = map['referral_enabled'] != 'false';
      _referralSignupEnabled = map['referral_signup_enabled'] != 'false';
      _helpCenterEnabled = map['help_center_enabled'] != 'false';
      _helpCenterPageName = map['help_center_page_name'] ?? 'Help Center';
      _paymentMode = map['payment_mode'] ?? 'auto';
      _referralRateCtrl.text        = map['referral_commission'] ?? '500';
      _accountNumberCtrl.text       = map['account_number']      ?? '';
      _accountTitleCtrl.text        = map['account_title']       ?? '';
      _paymentInstructionCtrl.text    = map['payment_instruction']          ?? '';
      _featuredInstructionCtrl.text   = map['featured_payment_instruction'] ?? '';
      _bankNameCtrl.text            = map['bank_name']           ?? '';
      _bankAccountCtrl.text         = map['bank_account']        ?? '';
      _bankHolderCtrl.text          = map['bank_holder']         ?? '';
      _bankSwiftCtrl.text           = map['bank_swift']          ?? '';
      _originalSnapshot = _currentSnapshot();
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.pricing, what: 'saving prices')) return;
    // Validate
    final sp  = int.tryParse(_standardPriceCtrl.text.trim());
    final sd  = int.tryParse(_standardDaysCtrl.text.trim());
    final fp  = int.tryParse(_featuredPriceCtrl.text.trim());
    final fd  = int.tryParse(_featuredDaysCtrl.text.trim());

    if (sp == null || sp <= 0) { _showError('Enter a valid Standard Plan price'); return; }
    if (sd == null || sd <= 0) { _showError('Enter valid days for Standard Plan'); return; }
    if (fp == null || fp <= 0) { _showError('Enter a valid Featured Post price'); return; }
    if (fd == null || fd <= 0) { _showError('Enter valid days for Featured Post'); return; }
    final fmpc = int.tryParse(_featuredMaxPerCityCtrl.text.trim());
    if (fmpc == null || fmpc <= 0) { _showError('Enter a valid Max Featured per city count'); return; }
    final fmg = int.tryParse(_featuredMaxGeneralCtrl.text.trim());
    if (fmg == null || fmg <= 0) { _showError('Enter a valid Max Featured (General) count'); return; }
    final rc  = int.tryParse(_referralRateCtrl.text.trim());
    if (rc == null || rc < 0) { _showError('Enter a valid Referral Commission amount'); return; }
    final ftd = int.tryParse(_freeModeTrialDaysCtrl.text.trim());
    if (_freeMode && _freeModeNewUsersOnly && (ftd == null || ftd <= 0)) {
      _showError('Enter valid trial days for new-user Free Mode');
      return;
    }

    // Confirmation popup
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1A33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: EdgeInsets.all(_S.of(context).s(20)),
          child: Builder(builder: (context) {
            final s = _S.of(context);
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Save Pricing?', style: TextStyle(fontSize: s.f(16), fontWeight: FontWeight.w800, color: Colors.white)),
              SizedBox(height: s.s(8)),
              Text('Price changes take effect immediately for new subscribers.',
                  style: TextStyle(fontSize: s.f(13), color: Colors.white.withOpacity(0.5), height: 1.5)),
              SizedBox(height: s.s(20)),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, false),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: s.s(12)),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(10))),
                    child: Center(child: Text('Cancel', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: s.f(13)))),
                  ),
                )),
                SizedBox(width: s.s(10)),
                Expanded(child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, true),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: s.s(12)),
                    decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(s.s(10))),
                    child: Center(child: Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(13)))),
                  ),
                )),
              ]),
            ]);
          }),
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await Future.wait([
        _client.rpc('admin_upsert_setting', params: {'p_key': 'free_mode', 'p_value': _freeMode.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'free_mode_new_users_only', 'p_value': _freeModeNewUsersOnly.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'free_mode_trial_days', 'p_value': (ftd ?? 30).toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'standard_plan_price',    'p_value': sp.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'standard_plan_days',     'p_value': sd.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'featured_post_price',    'p_value': fp.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'featured_post_duration', 'p_value': fd.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'max_featured_per_city',  'p_value': fmpc.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'max_featured_general',   'p_value': fmg.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'referral_enabled', 'p_value': _referralEnabled.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'referral_signup_enabled', 'p_value': _referralSignupEnabled.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'help_center_enabled', 'p_value': _helpCenterEnabled.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'referral_commission',    'p_value': rc.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'payment_mode',           'p_value': _paymentMode}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'account_number',         'p_value': _accountNumberCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'account_title',          'p_value': _accountTitleCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'payment_instruction',          'p_value': _paymentInstructionCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'featured_payment_instruction', 'p_value': _featuredInstructionCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'bank_name',              'p_value': _bankNameCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'bank_account',           'p_value': _bankAccountCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'bank_holder',            'p_value': _bankHolderCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'bank_swift',             'p_value': _bankSwiftCtrl.text.trim()}),
      ]);
      if (!mounted) return;
      await SupabaseService.instance.fetchAppSettings(); // refresh cache + notify all listeners
      _originalSnapshot = _currentSnapshot();
      HapticFeedback.lightImpact();
      _revalidateWebsiteFooter();
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildToggle(bool value, Color color, VoidCallback onTap) {
    final s = _S.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: s.d(36), height: s.d(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(s.s(10)),
          color: value ? color : Colors.white.withOpacity(0.15),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: s.d(16), height: s.d(16),
            margin: EdgeInsets.symmetric(horizontal: s.s(2)),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
          ),
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: kRose, behavior: SnackBarBehavior.floating, margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // Tells the website to immediately refresh its footer cache via the
  // existing proposal-status-changed webhook — same endpoint, same secret,
  // same pattern as admin approval/rejection and all other revalidation.
  // No separate /api/revalidate endpoint or REVALIDATE_TOKEN needed.
  Future<void> _revalidateWebsiteFooter() async {
    try {
      await http.post(
        Uri.parse('https://joronline.com/api/webhooks/proposal-status-changed'),
        headers: {
          'Content-Type': 'application/json',
          'x-webhook-secret': '89897ad4d61258ec79b72c4b5f3b6622c4a0d60533ed5189b8383886ccf1df6c',
        },
        body: '{"footer_changed":true}',
      );
    } catch (_) {
      // Non-fatal — the toggle/rename already saved successfully.
    }
  }

  Future<void> _onToggleHelpCenter() async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.pricing, what: 'changing this setting')) return;
    if (_helpCenterEnabled) {
      // Turning off never needs a check.
      setState(() => _helpCenterEnabled = false);
      _revalidateWebsiteFooter();
      return;
    }
    // Turning on requires at least one affiliate actually marked as a
    // Center — otherwise this would flip on a link to an empty page.
    try {
      final res = await _client
          .from('affiliates')
          .select('id')
          .eq('is_center', true)
          .or('deleted.is.null,deleted.eq.false')
          .limit(1);
      final hasCenter = (res as List).isNotEmpty;
      if (!hasCenter) {
        _showError('Mark at least one affiliate as a Center first (long-press an affiliate → Add as Center).');
        return;
      }
      setState(() => _helpCenterEnabled = true);
      _revalidateWebsiteFooter();
    } catch (_) {
      _showError('Could not check Center status. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const ViewOnlyBanner(pageKey: AdminPageKeys.pricing),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPurple))
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    ]);
  }

  Widget _buildError() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Builder(builder: (context) { final s = _S.of(context); return Icon(Icons.wifi_off_rounded, color: Colors.white.withOpacity(0.3), size: s.d(40)); }),
      Builder(builder: (context) => SizedBox(height: _S.of(context).s(12))),
      Builder(builder: (context) => Text('Could not load settings', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: _S.of(context).f(14)))),
      Builder(builder: (context) => SizedBox(height: _S.of(context).s(16))),
      Builder(builder: (context) {
        final s = _S.of(context);
        return GestureDetector(onTap: _loadSettings,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s.s(20), vertical: s.s(10)),
            decoration: BoxDecoration(color: kPurple.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(10)), border: Border.all(color: kPurple.withOpacity(0.4))),
            child: Text('Retry', style: TextStyle(color: kPurple, fontWeight: FontWeight.w700, fontSize: s.f(13))),
          ),
        );
      }),
    ]));
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(_S.of(context).s(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Subscription / Rishta Profile / Featured Post ──
        Builder(builder: (context) {
          final s = _S.of(context);
          return Container(
            padding: EdgeInsets.all(s.s(18)),
            decoration: BoxDecoration(
              color: const Color(0xFF16132A),
              borderRadius: BorderRadius.circular(s.s(20)),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // — Subscription Mode —
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _pricingSectionExpanded = !_pricingSectionExpanded),
                child: Row(children: [
                  Container(
                    width: s.d(40), height: s.d(40),
                    decoration: BoxDecoration(
                      color: (_freeMode ? kPurple : kInkFaint).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(s.s(12)),
                    ),
                    child: Icon(_freeMode ? Icons.lock_open_rounded : Icons.lock_rounded,
                      color: _freeMode ? kPurple : kInkFaint, size: s.d(20)),
                  ),
                  SizedBox(width: s.s(12)),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_freeMode ? 'Free Mode ON' : 'Subscription Mode',
                      style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w800,
                        color: _freeMode ? kPurple : Colors.white)),
                    Text(_freeMode ? 'Users can unlock profiles for free' : 'Users must pay to unlock profiles',
                      style: TextStyle(fontSize: s.f(11.5), color: Colors.white.withOpacity(0.4))),
                  ])),
                  GestureDetector(
                    onTap: () => setState(() => _freeMode = !_freeMode),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: s.d(36), height: s.d(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(s.s(10)),
                        color: _freeMode ? kPurple : Colors.white.withOpacity(0.15),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 200),
                        alignment: _freeMode ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          width: s.d(16), height: s.d(16),
                          margin: EdgeInsets.symmetric(horizontal: s.s(2)),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: s.s(8)),
                  AnimatedRotation(
                    turns: _pricingSectionExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.4), size: s.d(22)),
                  ),
                ]),
              ),

              if (_pricingSectionExpanded) ...[
              // — New-users-only restriction + trial length (only relevant while Free Mode is ON) —
              if (_freeMode) ...[
                SizedBox(height: s.s(14)),
                Container(
                  padding: EdgeInsets.all(s.s(14)),
                  decoration: BoxDecoration(
                    color: kPurple.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(s.s(14)),
                    border: Border.all(color: kPurple.withOpacity(0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Only for new users', style: TextStyle(fontSize: s.f(13), fontWeight: FontWeight.w700, color: Colors.white)),
                        SizedBox(height: s.s(2)),
                        Text('Restrict free access to CNICs that have\nnever had an active subscription before',
                          style: TextStyle(fontSize: s.f(11), color: Colors.white.withOpacity(0.45))),
                      ])),
                      SizedBox(width: s.s(10)),
                      GestureDetector(
                        onTap: () => setState(() => _freeModeNewUsersOnly = !_freeModeNewUsersOnly),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: s.d(26), height: s.d(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(s.s(8)),
                            color: _freeModeNewUsersOnly ? kPurple : Colors.white.withOpacity(0.15),
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 200),
                            alignment: _freeModeNewUsersOnly ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              width: s.d(12), height: s.d(12),
                              margin: EdgeInsets.symmetric(horizontal: s.s(2)),
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ]),
                    if (_freeModeNewUsersOnly) ...[
                      SizedBox(height: s.s(12)),
                      Row(children: [
                        Expanded(child: Text('Free trial length (days)', style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7)))),
                        SizedBox(width: s.s(10)),
                        SizedBox(
                          width: s.d(70),
                          child: TextField(
                            controller: _freeModeTrialDaysCtrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: TextStyle(color: Colors.white, fontSize: s.f(14)),
                            decoration: InputDecoration(
                              hintText: '30',
                              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                              filled: true,
                              fillColor: Colors.white.withOpacity(0.05),
                              contentPadding: EdgeInsets.symmetric(horizontal: s.s(10), vertical: s.s(8)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ]),
                ),
              ],

              Divider(color: Colors.white.withOpacity(0.07), height: s.s(32)),

              // — Rishta Profile —
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: s.d(40), height: s.d(40),
                    decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(12))),
                    child: Icon(Icons.visibility_rounded, color: kPurple, size: s.d(20)),
                  ),
                  SizedBox(width: s.s(12)),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Rishta Profile', style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w800, color: Colors.white)),
                    Text('Unlocks phone number and profile photos', style: TextStyle(fontSize: s.f(11.5), color: Colors.white.withOpacity(0.4))),
                  ])),
                ]),
                SizedBox(height: s.s(18)),
                Row(children: [
                  Expanded(child: _PricingField(label: 'Plan Price', hint: '1000', controller: _standardPriceCtrl, icon: Icons.currency_rupee_rounded, color: kPurple)),
                  SizedBox(width: s.s(10)),
                  Expanded(child: _PricingField(label: 'Validity (days)', hint: '90', controller: _standardDaysCtrl, icon: Icons.calendar_month_rounded, color: kPurple)),
                ]),
              ]),

              Divider(color: Colors.white.withOpacity(0.07), height: s.s(32)),

              // — Featured Post —
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: s.d(40), height: s.d(40),
                    decoration: BoxDecoration(color: kAmber.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(12))),
                    child: Icon(Icons.bolt_rounded, color: kAmber, size: s.d(20)),
                  ),
                  SizedBox(width: s.s(12)),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Featured Post', style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w800, color: Colors.white)),
                    Text('Featured a profile to the top of the group', style: TextStyle(fontSize: s.f(11.5), color: Colors.white.withOpacity(0.4))),
                  ])),
                ]),
                SizedBox(height: s.s(18)),
                Row(children: [
                  Expanded(child: _PricingField(label: 'Featured Price', hint: '200', controller: _featuredPriceCtrl, icon: Icons.currency_rupee_rounded, color: kAmber)),
                  SizedBox(width: s.s(10)),
                  Expanded(child: _PricingField(label: 'Duration (days)', hint: '1', controller: _featuredDaysCtrl, icon: Icons.timer_rounded, color: kAmber)),
                ]),
                SizedBox(height: s.s(12)),
                Row(children: [
                  Expanded(
                    child: _PricingField(
                      label: 'Max Featured per city',
                      hint: '5',
                      controller: _featuredMaxPerCityCtrl,
                      icon: Icons.location_city_rounded,
                      color: kAmber,
                    ),
                  ),
                  SizedBox(width: s.s(10)),
                  Expanded(
                    child: _PricingField(
                      label: 'Max Featured (General)',
                      hint: '20',
                      controller: _featuredMaxGeneralCtrl,
                      icon: Icons.public_rounded,
                      color: kAmber,
                    ),
                  ),
                ]),
              ]),
              ],

            ]),
          );
        }),
        SizedBox(height: _S.of(context).s(16)),

        // ── Referral Commission + toggle ──
        _PricingCard(
          icon: Icons.handshake_rounded,
          color: kPurple,
          title: 'Affiliate Program',
          subtitle: _referralEnabled ? 'Refer and Earn is ON' : 'Refer and Earn is OFF',
          headerTrailing: _buildToggle(_referralEnabled, kPurple, () => setState(() => _referralEnabled = !_referralEnabled)),
          disabled: !_referralEnabled,
          fields: const [],
          extraContent: Builder(builder: (context) {
            final s = _S.of(context);
            final signupColor = _referralSignupEnabled ? kPurple : kInkFaint;
            final helpCenterColor = _helpCenterEnabled ? kPurple : kInkFaint;
            final priceColor = _referralEnabled ? kPurple : kInkFaint;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(14)),
                decoration: BoxDecoration(
                  color: helpCenterColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(s.s(12)),
                  border: Border.all(color: helpCenterColor.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.support_agent_rounded, size: s.d(18), color: helpCenterColor.withOpacity(0.7)),
                  SizedBox(width: s.s(10)),
                  Expanded(child: Row(children: [
                    Flexible(child: Text(_helpCenterPageName, style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w800, color: helpCenterColor))),
                    SizedBox(width: s.s(4)),
                    GestureDetector(
                      onTap: () async {
                        final ctrl = TextEditingController(text: _helpCenterPageName);
                        final newName = await showDialog<String>(
                          context: context,
                          builder: (dialogCtx) => AlertDialog(
                            backgroundColor: const Color(0xFF1E1A33),
                            title: const Text('Rename Page', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                            content: TextField(
                              controller: ctrl,
                              autofocus: true,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.black.withOpacity(0.25),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              ),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(dialogCtx, ctrl.text.trim()), child: const Text('Save')),
                            ],
                          ),
                        );
                        if (newName == null || newName.isEmpty || newName == _helpCenterPageName) return;
                        setState(() => _helpCenterPageName = newName);
                        await _client.rpc('admin_upsert_setting', params: {'p_key': 'help_center_page_name', 'p_value': newName});
                        _revalidateWebsiteFooter();
                      },
                      child: Icon(Icons.edit_rounded, size: s.d(14), color: helpCenterColor.withOpacity(0.5)),
                    ),
                  ])),
                  _buildToggle(_helpCenterEnabled, kPurple, () => _onToggleHelpCenter()),
                ]),
              ),
              SizedBox(height: s.s(14)),
              if (_referralEnabled) ...[
                Container(
                  padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(14)),
                  decoration: BoxDecoration(
                    color: signupColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(s.s(12)),
                    border: Border.all(color: signupColor.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    Icon(Icons.person_add_rounded, size: s.d(18), color: signupColor.withOpacity(0.7)),
                    SizedBox(width: s.s(10)),
                    Expanded(child: Text('New Signups', style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w800, color: signupColor))),
                    _buildToggle(_referralSignupEnabled, kPurple, () => setState(() => _referralSignupEnabled = !_referralSignupEnabled)),
                  ]),
                ),
                SizedBox(height: s.s(14)),
              ],
              Container(
                padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(14)),
                decoration: BoxDecoration(
                  color: priceColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(s.s(12)),
                  border: Border.all(color: priceColor.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.payments_rounded, size: s.d(18), color: priceColor.withOpacity(0.7)),
                  SizedBox(width: s.s(10)),
                  Expanded(child: Text('Commission', style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w800, color: priceColor))),
                  IntrinsicWidth(
                    child: TextFormField(
                      controller: _referralRateCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w800, color: priceColor),
                      decoration: InputDecoration(
                        hintText: '500',
                        hintStyle: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.2)),
                        prefix: Text('Rs. ', style: TextStyle(fontSize: s.f(13), fontWeight: FontWeight.w700, color: priceColor.withOpacity(0.6))),
                        isDense: true,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ]),
              ),
            ]);
          }),
        ),
        SizedBox(height: _S.of(context).s(16)),

        // ── Payment Mode + Details ──
        Builder(builder: (context) {
          final s = _S.of(context);
          const modeColor = kPurple;
          return Container(
            padding: EdgeInsets.all(s.s(18)),
            decoration: BoxDecoration(
              color: const Color(0xFF16132A),
              borderRadius: BorderRadius.circular(s.s(20)),
              border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // — Payment Mode —
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _paymentSectionExpanded = !_paymentSectionExpanded),
                child: Row(children: [
                  Container(
                    width: s.d(40), height: s.d(40),
                    decoration: BoxDecoration(color: modeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(12))),
                    child: Icon(Icons.payment_rounded, color: modeColor, size: s.d(20)),
                  ),
                  SizedBox(width: s.s(12)),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Manual Payment', style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w800, color: Colors.white)),
                    Text('Wallet / Bank Transfer', style: TextStyle(fontSize: s.f(11.5), color: Colors.white.withOpacity(0.4))),
                  ])),
                  GestureDetector(
                    onTap: () => setState(() => _paymentMode = _paymentMode == 'auto' ? 'manual' : 'auto'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: s.d(36), height: s.d(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(s.s(10)),
                        color: _paymentMode == 'manual' ? kPurple : Colors.white.withOpacity(0.15),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 200),
                        alignment: _paymentMode == 'manual' ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          width: s.d(16), height: s.d(16),
                          margin: EdgeInsets.symmetric(horizontal: s.s(2)),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: s.s(8)),
                  AnimatedRotation(
                    turns: _paymentSectionExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.4), size: s.d(22)),
                  ),
                ]),
              ),

              if (_paymentSectionExpanded) ...[
              // — Manual Payment Details —
              if (_paymentMode == 'manual') ...[
                Divider(color: Colors.white.withOpacity(0.07), height: s.s(32)),

                // Payment Method
                Text('Payment Method', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
                SizedBox(height: s.s(8)),
                _buildManualTextField(controller: _accountTitleCtrl, hint: 'e.g. JazzCash', icon: Icons.account_balance_wallet_rounded),
                SizedBox(height: s.s(12)),

                // Account Number
                Text('Account Number', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
                SizedBox(height: s.s(8)),
                _buildManualTextField(controller: _accountNumberCtrl, hint: 'e.g. 03001234567', icon: Icons.phone_rounded, keyboard: TextInputType.phone),
                SizedBox(height: s.s(16)),

                Row(children: [
                  Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: s.s(10)),
                    child: Text('Bank Account (optional)', style: TextStyle(fontSize: s.f(10.5), color: Colors.white.withOpacity(0.3), fontWeight: FontWeight.w600)),
                  ),
                  Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                ]),
                SizedBox(height: s.s(12)),

                // Bank Name
                Text('Bank Name', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
                SizedBox(height: s.s(8)),
                _buildManualTextField(controller: _bankNameCtrl, hint: 'e.g. Meezan Bank', icon: Icons.account_balance_rounded),
                SizedBox(height: s.s(12)),

                // Account Holder Name
                Text('Account Holder Name', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
                SizedBox(height: s.s(8)),
                _buildManualTextField(controller: _bankHolderCtrl, hint: 'e.g. Muhammad Ali', icon: Icons.person_rounded),
                SizedBox(height: s.s(12)),

                // IBAN
                Text('IBAN', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
                SizedBox(height: s.s(8)),
                _buildManualTextField(controller: _bankAccountCtrl, hint: 'e.g. PK36SCBL0000001123456702', icon: Icons.credit_card_rounded),
                SizedBox(height: s.s(12)),

                // Swift Code
                Text('Swift Code', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
                SizedBox(height: s.s(8)),
                _buildManualTextField(controller: _bankSwiftCtrl, hint: 'e.g. MEZNPKKA', icon: Icons.code_rounded),
                SizedBox(height: s.s(12)),

                // Payment Instructions (Rishta Profile)
                Text('Payment Instructions (Rishta Profile)', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
                SizedBox(height: s.s(8)),
                TextFormField(
                  controller: _paymentInstructionCtrl,
                  maxLines: 3,
                  style: TextStyle(fontSize: s.f(13), color: Colors.white, height: 1.5),
                  decoration: InputDecoration(
                    hintText: 'e.g. Send payment proof to WhatsApp after transfer...',
                    hintStyle: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.2), height: 1.5),
                    filled: true,
                    fillColor: kPurple.withOpacity(0.06),
                    contentPadding: EdgeInsets.all(s.s(14)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kPurple.withOpacity(0.3))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kPurple.withOpacity(0.3))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kPurple, width: 1.5)),
                  ),
                ),
                SizedBox(height: s.s(12)),

                // Payment Instructions (Featured Post)
                Text('Payment Instructions (Featured Post)', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
                SizedBox(height: s.s(8)),
                TextFormField(
                  controller: _featuredInstructionCtrl,
                  maxLines: 3,
                  style: TextStyle(fontSize: s.f(13), color: Colors.white, height: 1.5),
                  decoration: InputDecoration(
                    hintText: 'e.g. WhatsApp your preferred date and city for the featured post...',
                    hintStyle: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.2), height: 1.5),
                    filled: true,
                    fillColor: kPurple.withOpacity(0.06),
                    contentPadding: EdgeInsets.all(s.s(14)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kPurple.withOpacity(0.3))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kPurple.withOpacity(0.3))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kPurple, width: 1.5)),
                  ),
                ),
              ],
              ],

            ]),
          );
        }),

        SizedBox(height: _S.of(context).s(16)),

        // ── Coupon Codes ──
        const _CouponCodesSection(),

        SizedBox(height: _S.of(context).s(25)),

        // ── Save button ──
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: (_saving || !_hasChanges) ? null : _save,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(vertical: _S.of(context).s(16)),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: (_saving || !_hasChanges)
                      ? [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.08)]
                      : [kPurple, kPurpleDeep],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(_S.of(context).s(16)),
                boxShadow: (_saving || !_hasChanges) ? [] : [BoxShadow(color: kPurple.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Center(
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Save', style: TextStyle(color: _hasChanges ? Colors.white : Colors.white.withOpacity(0.3), fontWeight: FontWeight.w800, fontSize: _S.of(context).f(15))),
                      ]),
              ),
            ),
          ),
        ),
        SizedBox(height: _S.of(context).s(20)),
      ]),
    );
  }

  Widget _buildManualTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
  }) {
    final s = _S.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      style: TextStyle(fontSize: s.f(14), fontWeight: FontWeight.w600, color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: s.f(13), color: Colors.white.withOpacity(0.2)),
        prefixIcon: Icon(icon, color: kPurple.withOpacity(0.7), size: s.d(18)),
        filled: true,
        fillColor: kPurple.withOpacity(0.06),
        contentPadding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(14)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kPurple.withOpacity(0.3))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kPurple.withOpacity(0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kPurple, width: 1.5)),
      ),
    );
  }

  Widget _buildStandardPreview() {
    final price = _standardPriceCtrl.text.isEmpty ? '1,000' : _fmt(_standardPriceCtrl.text);
    final days  = _standardDaysCtrl.text.isEmpty  ? '90'    : _standardDaysCtrl.text;
    return _PreviewChip(text: 'Rs. $price / $days days', color: kPurple);
  }

  Widget _buildFeaturedPreview() {
    final price = _featuredPriceCtrl.text.isEmpty ? '200' : _fmt(_featuredPriceCtrl.text);
    final days  = _featuredDaysCtrl.text.isEmpty  ? '1'   : _featuredDaysCtrl.text;
    final d     = int.tryParse(days) ?? 1;
    return _PreviewChip(text: 'Rs. $price / ${d == 1 ? "1 day" : "$d days"}', color: kAmber);
  }

  String _fmt(String v) {
    final n = int.tryParse(v);
    if (n == null) return v;
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    return n.toString();
  }
}

// ── Coupon Codes section ───────────────────────────────────────────────────
class _CouponCodesSection extends StatefulWidget {
  const _CouponCodesSection();
  @override
  State<_CouponCodesSection> createState() => _CouponCodesSectionState();
}

class _CouponCodesSectionState extends State<_CouponCodesSection> {
  final _db = SupabaseService.instance;
  List<CouponCode> _coupons = [];
  bool _loading = true;
  String? _error;
  bool _expanded = false;
  AutoRefreshSync? _sync;

  @override
  void initState() {
    super.initState();
    _load();
    _sync = subscribeAutoRefresh(
      client: _db.client,
      channelName: 'admin-sync-coupon-codes',
      tables: const ['coupon_codes'],
      onChange: () { if (mounted) _load(); },
    );
  }

  @override
  void dispose() {
    _sync?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final coupons = await _db.fetchCouponCodes();
      if (mounted) setState(() { _coupons = coupons; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _showAddDialog() async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.pricing, what: 'adding coupons')) return;
    final codeCtrl = TextEditingController();
    final percentCtrl = TextEditingController();
    final freeDaysCtrl = TextEditingController();
    final trialDaysCtrl = TextEditingController();
    String couponType = 'percentage'; // 'percentage', 'free_days', or 'free_trial'
    String? errorText;
    DateTime? expiresAt;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        final s = _S.of(ctx);
        return AnimatedPadding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: MediaQuery.removeViewInsets(
            removeBottom: true,
            context: ctx,
            child: Dialog(
          backgroundColor: const Color(0xFF1E1A33),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: EdgeInsets.zero,
          child: SingleChildScrollView(
            child: Padding(
            padding: EdgeInsets.all(s.s(20)),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('New Coupon Code', style: TextStyle(fontSize: s.f(16), fontWeight: FontWeight.w800, color: Colors.white)),
              SizedBox(height: s.s(14)),
              Text('Code', style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7))),
              SizedBox(height: s.s(6)),
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(color: Colors.white, fontSize: s.f(14)),
                decoration: InputDecoration(
                  hintText: 'e.g. EID2026',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  filled: true, fillColor: Colors.white.withOpacity(0.05),
                  contentPadding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(10)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide.none),
                ),
              ),
              SizedBox(height: s.s(14)),
              Text('What does this coupon give?', style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7))),
              SizedBox(height: s.s(8)),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => setDialogState(() => couponType = 'percentage'),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: s.s(10)),
                    decoration: BoxDecoration(
                      color: couponType == 'percentage' ? kPurple.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(s.s(10)),
                      border: Border.all(color: couponType == 'percentage' ? kPurple : Colors.transparent),
                    ),
                    child: Center(child: Text('% Discount', style: TextStyle(color: couponType == 'percentage' ? kPurple : Colors.white.withOpacity(0.5), fontWeight: FontWeight.w700, fontSize: s.f(11)))),
                  ),
                )),
                SizedBox(width: s.s(6)),
                Expanded(child: GestureDetector(
                  onTap: () => setDialogState(() => couponType = 'free_days'),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: s.s(10)),
                    decoration: BoxDecoration(
                      color: couponType == 'free_days' ? kPurple.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(s.s(10)),
                      border: Border.all(color: couponType == 'free_days' ? kPurple : Colors.transparent),
                    ),
                    child: Center(child: Text('Bonus Days', style: TextStyle(color: couponType == 'free_days' ? kPurple : Colors.white.withOpacity(0.5), fontWeight: FontWeight.w700, fontSize: s.f(11)))),
                  ),
                )),
                SizedBox(width: s.s(6)),
                Expanded(child: GestureDetector(
                  onTap: () => setDialogState(() => couponType = 'free_trial'),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: s.s(10)),
                    decoration: BoxDecoration(
                      color: couponType == 'free_trial' ? kPurple.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(s.s(10)),
                      border: Border.all(color: couponType == 'free_trial' ? kPurple : Colors.transparent),
                    ),
                    child: Center(child: Text('Free Trial', style: TextStyle(color: couponType == 'free_trial' ? kPurple : Colors.white.withOpacity(0.5), fontWeight: FontWeight.w700, fontSize: s.f(11)))),
                  ),
                )),
              ]),
              SizedBox(height: s.s(14)),
              if (couponType == 'percentage') ...[
                Text('Discount %', style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7))),
                SizedBox(height: s.s(6)),
                TextField(
                  controller: percentCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(color: Colors.white, fontSize: s.f(14)),
                  decoration: InputDecoration(
                    hintText: 'e.g. 20',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true, fillColor: Colors.white.withOpacity(0.05),
                    contentPadding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(10)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide.none),
                  ),
                ),
                SizedBox(height: s.s(6)),
                Text('Reduce the plan price by this percentage — user pays less.',
                  style: TextStyle(fontSize: s.f(10.5), color: Colors.white.withOpacity(0.35))),
              ] else if (couponType == 'free_days') ...[
                Text('Bonus days', style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7))),
                SizedBox(height: s.s(6)),
                TextField(
                  controller: freeDaysCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(color: Colors.white, fontSize: s.f(14)),
                  decoration: InputDecoration(
                    hintText: 'e.g. 30',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true, fillColor: Colors.white.withOpacity(0.05),
                    contentPadding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(10)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide.none),
                  ),
                ),
                SizedBox(height: s.s(6)),
                Text('Add this many bonus days on top of the normal plan duration.',
                  style: TextStyle(fontSize: s.f(10.5), color: Colors.white.withOpacity(0.35))),
              ] else ...[
                Text('Trial days', style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7))),
                SizedBox(height: s.s(6)),
                TextField(
                  controller: trialDaysCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(color: Colors.white, fontSize: s.f(14)),
                  decoration: InputDecoration(
                    hintText: 'e.g. 7',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    filled: true, fillColor: Colors.white.withOpacity(0.05),
                    contentPadding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(10)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide.none),
                  ),
                ),
                SizedBox(height: s.s(6)),
                Text('User gets free access for this many days — no payment required.',
                  style: TextStyle(fontSize: s.f(10.5), color: Colors.white.withOpacity(0.35))),
              ],
              SizedBox(height: s.s(14)),
              Text('Expiry date (optional)', style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7))),
              SizedBox(height: s.s(6)),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: expiresAt ?? DateTime.now().add(const Duration(days: 30)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) setDialogState(() => expiresAt = picked);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(12)),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(s.s(10))),
                  child: Row(children: [
                    Icon(Icons.calendar_today_rounded, size: s.d(15), color: Colors.white.withOpacity(0.5)),
                    SizedBox(width: s.s(8)),
                    Text(
                      expiresAt == null ? 'Never expires' : '${expiresAt!.day}/${expiresAt!.month}/${expiresAt!.year}',
                      style: TextStyle(color: expiresAt == null ? Colors.white.withOpacity(0.4) : Colors.white, fontSize: s.f(13)),
                    ),
                    const Spacer(),
                    if (expiresAt != null)
                      GestureDetector(
                        onTap: () => setDialogState(() => expiresAt = null),
                        child: Icon(Icons.close_rounded, size: s.d(16), color: Colors.white.withOpacity(0.4)),
                      ),
                  ]),
                ),
              ),
              if (errorText != null) ...[
                SizedBox(height: s.s(10)),
                Text(errorText!, style: TextStyle(color: kRose, fontSize: s.f(12))),
              ],
              SizedBox(height: s.s(18)),
              Row(children: [
                Expanded(child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                )),
                SizedBox(width: s.s(10)),
                Expanded(child: GestureDetector(
                  onTap: () async {
                    final code = codeCtrl.text.trim();
                    if (code.isEmpty) { setDialogState(() => errorText = 'Enter a coupon code'); return; }

                    int? pct;
                    int? freeDays;
                    int? trialDays;
                    if (couponType == 'percentage') {
                      pct = int.tryParse(percentCtrl.text.trim());
                      if (pct == null || pct <= 0 || pct > 100) { setDialogState(() => errorText = 'Enter a discount between 1–100'); return; }
                    } else if (couponType == 'free_days') {
                      freeDays = int.tryParse(freeDaysCtrl.text.trim());
                      if (freeDays == null || freeDays <= 0) { setDialogState(() => errorText = 'Enter a number of bonus days'); return; }
                    } else {
                      trialDays = int.tryParse(trialDaysCtrl.text.trim());
                      if (trialDays == null || trialDays <= 0) { setDialogState(() => errorText = 'Enter a number of trial days'); return; }
                    }

                    try {
                      await _db.createCouponCode(code, type: couponType, discountPercent: pct, freeDays: freeDays, trialDays: trialDays, expiresAt: expiresAt);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      final msg = e.toString().contains('duplicate') || e.toString().contains('unique')
                          ? 'That code already exists'
                          : 'Failed to create coupon';
                      setDialogState(() => errorText = msg);
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: s.s(12)),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [kPurple, kPurpleDeep]),
                      borderRadius: BorderRadius.circular(s.s(10)),
                    ),
                    child: Center(child: Text('Create', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(13)))),
                  ),
                )),
              ]),
            ]),
          ),
          ),
          ),
        ),
      );
      }),
    );

    if (created == true) _load();
  }

  Future<void> _confirmDelete(CouponCode c) async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.pricing, what: 'deleting coupons')) return;
    final s = _S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete coupon?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text('"${c.code}" will stop working immediately.', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: s.f(13))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: kRose, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteCouponCode(c.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return Container(
      padding: EdgeInsets.all(s.s(18)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(s.s(20)),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(children: [
            Container(
              width: s.d(40), height: s.d(40),
              decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(12))),
              child: Icon(Icons.local_offer_rounded, color: kPurple, size: s.d(20)),
            ),
            SizedBox(width: s.s(12)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Coupon Codes', style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w800, color: Colors.white)),
              Text('Promotional discounts', style: TextStyle(fontSize: s.f(11.5), color: Colors.white.withOpacity(0.4))),
            ])),
            GestureDetector(
              onTap: _showAddDialog,
              child: Container(
                width: s.d(30), height: s.d(30),
                decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(9))),
                child: Icon(Icons.add_rounded, color: kPurple, size: s.d(18)),
              ),
            ),
            SizedBox(width: s.s(8)),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.4), size: s.d(22)),
            ),
          ]),
        ),
        if (_expanded) ...[
        SizedBox(height: s.s(14)),
        if (_loading)
          Center(child: Padding(padding: EdgeInsets.all(s.s(20)), child: const CircularProgressIndicator(color: kPurple)))
        else if (_error != null)
          Text('Failed to load coupons: $_error', style: TextStyle(color: kRose, fontSize: s.f(12)))
        else if (_coupons.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: s.s(10)),
            child: Text('No coupon codes yet — tap "Add" to create one.', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: s.f(12.5))),
          )
        else
          ..._coupons.map((c) => Padding(
                padding: EdgeInsets.only(bottom: s.s(10)),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(c.code, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: s.f(14))),
                      SizedBox(width: s.s(8)),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: s.s(8), vertical: s.s(2)),
                        decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(6))),
                        child: Text(
                          c.isPercentage ? '${c.discountPercent}% off' : c.isFreeTrial ? '${c.trialDays} day trial' : '${c.freeDays} bonus days',
                          style: TextStyle(color: kPurple, fontWeight: FontWeight.w700, fontSize: s.f(11)),
                        ),
                      ),
                      if (c.isExpired) ...[
                        SizedBox(width: s.s(6)),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: s.s(8), vertical: s.s(2)),
                          decoration: BoxDecoration(color: kRose.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(6))),
                          child: Text('Expired', style: TextStyle(color: kRose, fontWeight: FontWeight.w700, fontSize: s.f(11))),
                        ),
                      ],
                    ]),
                    SizedBox(height: s.s(2)),
                    Text(
                      c.expiresAt == null
                          ? 'Used ${c.timesUsed} time${c.timesUsed == 1 ? '' : 's'} · Never expires'
                          : 'Used ${c.timesUsed} time${c.timesUsed == 1 ? '' : 's'} · ${c.isExpired ? 'Expired' : 'Expires'} ${c.expiresAt!.day}/${c.expiresAt!.month}/${c.expiresAt!.year}',
                      style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: s.f(11)),
                    ),
                  ])),
                  GestureDetector(
                    onTap: () async { await _db.setCouponActive(c.id, !c.active); _load(); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: s.d(36), height: s.d(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(s.s(10)),
                        color: c.active ? kPurple : Colors.white.withOpacity(0.15),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 200),
                        alignment: c.active ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          width: s.d(16), height: s.d(16),
                          margin: EdgeInsets.symmetric(horizontal: s.s(2)),
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: s.s(8)),
                  GestureDetector(
                    onTap: () => _confirmDelete(c),
                    child: Padding(
                      padding: EdgeInsets.all(s.s(6)),
                      child: Icon(Icons.delete_outline_rounded, color: Colors.white.withOpacity(0.35), size: s.d(20)),
                    ),
                  ),
                ]),
              )),
        ],
      ]),
    );
  }
}

// ── Pricing card ──────────────────────────────────────────────────────────────
class _PricingCard extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final List<_PricingField> fields;
  final Widget? preview;
  final Widget? topContent;
  final Widget? extraContent;
  final Widget? headerTrailing;
  final bool disabled;

  const _PricingCard({
    required this.icon, required this.color,
    required this.title, required this.subtitle,
    required this.fields, this.preview, this.topContent, this.extraContent,
    this.headerTrailing,
    this.disabled = false,
  });

  @override
  State<_PricingCard> createState() => _PricingCardState();
}

class _PricingCardState extends State<_PricingCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      f.controller.addListener(() => setState(() {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.disabled ? 0.45 : 1.0,
      child: Stack(children: [
        Container(
          padding: EdgeInsets.all(_S.of(context).s(18)),
          decoration: BoxDecoration(
            color: const Color(0xFF16132A),
            borderRadius: BorderRadius.circular(_S.of(context).s(20)),
            border: Border.all(color: widget.color.withOpacity(0.25), width: 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Card header — tap to expand/collapse
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(children: [
            Container(
              width: _S.of(context).d(40), height: _S.of(context).d(40),
              decoration: BoxDecoration(color: widget.color.withOpacity(0.15), borderRadius: BorderRadius.circular(_S.of(context).s(12))),
              child: Icon(widget.icon, color: widget.color, size: _S.of(context).d(20)),
            ),
            SizedBox(width: _S.of(context).s(12)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(widget.title, style: TextStyle(fontSize: _S.of(context).f(15), fontWeight: FontWeight.w800, color: Colors.white)),
                const Spacer(),
                if (widget.preview != null) widget.preview!,
              ]),
              Text(widget.subtitle, style: TextStyle(fontSize: _S.of(context).f(11.5), color: Colors.white.withOpacity(0.4))),
            ])),
            if (widget.headerTrailing != null) ...[
              SizedBox(width: _S.of(context).s(8)),
              widget.headerTrailing!,
            ],
            SizedBox(width: _S.of(context).s(8)),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.4), size: _S.of(context).d(22)),
            ),
          ]),
        ),
        if (_expanded) ...[
        if (widget.topContent != null) ...[
          SizedBox(height: _S.of(context).s(14)),
          widget.topContent!,
        ],
        if (widget.fields.isNotEmpty) ...[
          SizedBox(height: _S.of(context).s(18)),
          Row(children: widget.fields.asMap().entries.map((e) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: e.key > 0 ? _S.of(context).s(10) : 0),
                child: e.value,
              ),
            );
          }).toList()),
        ],
        if (widget.extraContent != null) ...[
          SizedBox(height: _S.of(context).s(14)),
          widget.extraContent!,
        ],
        ],
      ]),
    ),

  ]),
  );
  }
}

// ── Single pricing input field ────────────────────────────────────────────────
class _PricingField extends StatelessWidget {
  final String label, hint;
  final TextEditingController controller;
  final IconData icon;
  final Color color;

  const _PricingField({
    required this.label, required this.hint,
    required this.controller, required this.icon, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label.isNotEmpty) ...[Text(label, style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))), SizedBox(height: s.s(8))],
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(fontSize: s.f(18), fontWeight: FontWeight.w800, color: color),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: s.f(18), fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.15)),
          prefix: icon == Icons.currency_rupee_rounded
              ? Text('Rs. ', style: TextStyle(fontSize: s.f(16), fontWeight: FontWeight.w700, color: color.withOpacity(0.7)))
              : null,
          prefixIcon: icon != Icons.currency_rupee_rounded ? Icon(icon, color: color.withOpacity(0.7), size: s.d(18)) : null,
          filled: true,
          fillColor: color.withOpacity(0.08),
          contentPadding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(14)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: color.withOpacity(0.3))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: color.withOpacity(0.3))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: color, width: 1.5)),
        ),
      ),
    ]);
  }
}

// ── Live preview chip ─────────────────────────────────────────────────────────
class _PreviewChip extends StatelessWidget {
  final String text;
  final Color color;
  const _PreviewChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s.s(8), vertical: s.s(3)),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(s.s(20)),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(text, style: TextStyle(fontSize: s.f(9.5), fontWeight: FontWeight.w700, color: color)),
    );
  }
}
