import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';

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
  bool _referralEnabled = true;
  String _paymentMode = 'auto'; // 'auto' = online SafePay, 'manual' = bank transfer only
  final _referralRateCtrl     = TextEditingController();
  final _accountNumberCtrl    = TextEditingController();
  final _accountTitleCtrl     = TextEditingController();
  final _paymentInstructionCtrl = TextEditingController();
  final _bankNameCtrl         = TextEditingController();
  final _bankAccountCtrl      = TextEditingController();
  final _bankHolderCtrl       = TextEditingController();
  final _bankSwiftCtrl        = TextEditingController();
  String? _error;

  // Controllers
  final _standardPriceCtrl  = TextEditingController();
  final _standardDaysCtrl   = TextEditingController();
  final _featuredPriceCtrl  = TextEditingController();
  final _featuredDaysCtrl   = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _standardPriceCtrl.dispose();
    _standardDaysCtrl.dispose();
    _featuredPriceCtrl.dispose();
    _featuredDaysCtrl.dispose();
    _referralRateCtrl.dispose();
    _accountNumberCtrl.dispose();
    _accountTitleCtrl.dispose();
    _paymentInstructionCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankAccountCtrl.dispose();
    _bankHolderCtrl.dispose();
    _bankSwiftCtrl.dispose();
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
      _freeMode = map['free_mode'] == 'true';
      _referralEnabled = map['referral_enabled'] != 'false';
      _paymentMode = map['payment_mode'] ?? 'auto';
      _referralRateCtrl.text        = map['referral_commission'] ?? '500';
      _accountNumberCtrl.text       = map['account_number']      ?? '';
      _accountTitleCtrl.text        = map['account_title']       ?? '';
      _paymentInstructionCtrl.text  = map['payment_instruction'] ?? '';
      _bankNameCtrl.text            = map['bank_name']           ?? '';
      _bankAccountCtrl.text         = map['bank_account']        ?? '';
      _bankHolderCtrl.text          = map['bank_holder']         ?? '';
      _bankSwiftCtrl.text           = map['bank_swift']          ?? '';
    } catch (e) {
      _error = e.toString();
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    // Validate
    final sp  = int.tryParse(_standardPriceCtrl.text.trim());
    final sd  = int.tryParse(_standardDaysCtrl.text.trim());
    final fp  = int.tryParse(_featuredPriceCtrl.text.trim());
    final fd  = int.tryParse(_featuredDaysCtrl.text.trim());

    if (sp == null || sp <= 0) { _showError('Enter a valid Standard Plan price'); return; }
    if (sd == null || sd <= 0) { _showError('Enter valid days for Standard Plan'); return; }
    if (fp == null || fp <= 0) { _showError('Enter a valid Featured Post price'); return; }
    if (fd == null || fd <= 0) { _showError('Enter valid days for Featured Post'); return; }
    final rc  = int.tryParse(_referralRateCtrl.text.trim());
    if (rc == null || rc < 0) { _showError('Enter a valid Referral Commission amount'); return; }

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
        _client.rpc('admin_upsert_setting', params: {'p_key': 'standard_plan_price',    'p_value': sp.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'standard_plan_days',     'p_value': sd.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'featured_post_price',    'p_value': fp.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'featured_post_duration', 'p_value': fd.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'referral_enabled', 'p_value': _referralEnabled.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'referral_commission',    'p_value': rc.toString()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'payment_mode',           'p_value': _paymentMode}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'account_number',         'p_value': _accountNumberCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'account_title',          'p_value': _accountTitleCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'payment_instruction',    'p_value': _paymentInstructionCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'bank_name',              'p_value': _bankNameCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'bank_account',           'p_value': _bankAccountCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'bank_holder',            'p_value': _bankHolderCtrl.text.trim()}),
        _client.rpc('admin_upsert_setting', params: {'p_key': 'bank_swift',             'p_value': _bankSwiftCtrl.text.trim()}),
      ]);
      if (!mounted) return;
      await SupabaseService.instance.fetchAppSettings(); // refresh cache + notify all listeners
      _showSuccess();
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: kRose, behavior: SnackBarBehavior.floating, margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showSuccess() {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(children: [
        Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        SizedBox(width: 10),
        Text('Pricing updated successfully!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ]),
      backgroundColor: kGreen, behavior: SnackBarBehavior.floating, margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator(color: kPurple))
        : _error != null
            ? _buildError()
            : _buildContent();
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

        // ── Free Mode Toggle ──
        Container(
          padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(16), vertical: _S.of(context).s(14)),
          decoration: BoxDecoration(
            color: _freeMode ? kGreen.withOpacity(0.1) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(_S.of(context).s(14)),
            border: Border.all(color: _freeMode ? kGreen.withOpacity(0.4) : Colors.white.withOpacity(0.08)),
          ),
          child: Row(children: [
            Container(
              width: _S.of(context).d(38), height: _S.of(context).d(38),
              decoration: BoxDecoration(
                color: (_freeMode ? kGreen : kInkFaint).withOpacity(0.15),
                borderRadius: BorderRadius.circular(_S.of(context).s(10)),
              ),
              child: Icon(_freeMode ? Icons.lock_open_rounded : Icons.lock_rounded,
                color: _freeMode ? kGreen : kInkFaint, size: _S.of(context).d(20)),
            ),
            SizedBox(width: _S.of(context).s(12)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_freeMode ? 'Free Mode ON' : 'Subscription Mode',
                style: TextStyle(fontSize: _S.of(context).f(14), fontWeight: FontWeight.w800,
                  color: _freeMode ? kGreen : Colors.white)),
              SizedBox(height: _S.of(context).s(2)),
              Text(_freeMode ? 'Users can unlock profiles for free' : 'Users must pay to unlock profiles',
                style: TextStyle(fontSize: _S.of(context).f(11.5), color: Colors.white.withOpacity(0.4))),
            ])),
            Switch(
              value: _freeMode,
              onChanged: (v) => setState(() => _freeMode = v),
              activeColor: kGreen,
              inactiveThumbColor: kInkFaint,
              inactiveTrackColor: Colors.white.withOpacity(0.1),
            ),
          ]),
        ),
        SizedBox(height: _S.of(context).s(16)),

        // ── Standard Plan ──
        _PricingCard(
          icon: Icons.visibility_rounded,
          color: _freeMode ? kInkFaint : kPurple,
          disabled: _freeMode,
          title: 'Rishta Profile',
          subtitle: 'Unlocks phone number and profile photos',
          fields: [
            _PricingField(
              label: 'Plan Price',
              hint: '1000',
              controller: _standardPriceCtrl,
              icon: Icons.currency_rupee_rounded,
              color: kPurple,
            ),
            _PricingField(
              label: 'Validity (days)',
              hint: '90',
              controller: _standardDaysCtrl,
              icon: Icons.calendar_month_rounded,
              color: kPurple,
            ),
          ],
        ),
        SizedBox(height: _S.of(context).s(16)),

        // ── Featured Post ──
        _PricingCard(
          icon: Icons.bolt_rounded,
          color: kAmber,
          title: 'Featured Post',
          subtitle: 'Featured a profile to the top of the group',
          fields: [
            _PricingField(
              label: 'Featured Price',
              hint: '200',
              controller: _featuredPriceCtrl,
              icon: Icons.currency_rupee_rounded,
              color: kAmber,
            ),
            _PricingField(
              label: 'Duration (days)',
              hint: '1',
              controller: _featuredDaysCtrl,
              icon: Icons.timer_rounded,
              color: kAmber,
            ),
          ],
        ),
        SizedBox(height: _S.of(context).s(16)),

        // ── Referral Commission + toggle ──
        _PricingCard(
          icon: Icons.handshake_rounded,
          color: _referralEnabled ? kPurple : kInkFaint,
          disabled: !_referralEnabled,
          title: 'Referral Commission',
          subtitle: _referralEnabled ? 'Amount paid to affiliate per referral' : 'Referral program is off',
          preview: GestureDetector(
            onTap: () => setState(() => _referralEnabled = !_referralEnabled),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _S.of(context).d(36), height: _S.of(context).d(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_S.of(context).s(10)),
                color: _referralEnabled ? kPurple : Colors.white.withOpacity(0.15),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: _referralEnabled ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: _S.of(context).d(16), height: _S.of(context).d(16),
                  margin: EdgeInsets.symmetric(horizontal: _S.of(context).s(2)),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          fields: [
            _PricingField(
              label: '',
              hint: '500',
              controller: _referralRateCtrl,
              icon: Icons.currency_rupee_rounded,
              color: _referralEnabled ? kPurple : kInkFaint,
            ),
          ],
        ),
        SizedBox(height: _S.of(context).s(16)),

        // ── Payment Mode toggle ──
        _PricingCard(
          icon: Icons.payment_rounded,
          color: _paymentMode == 'auto' ? kGreen : kAmber,
          title: 'Payment Mode',
          subtitle: _paymentMode == 'auto' ? 'Auto Payment' : 'Manual Payment',
          preview: GestureDetector(
            onTap: () => setState(() => _paymentMode = _paymentMode == 'auto' ? 'manual' : 'auto'),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _S.of(context).d(36), height: _S.of(context).d(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_S.of(context).s(10)),
                color: _paymentMode == 'auto' ? kGreen : Colors.white.withOpacity(0.15),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: _paymentMode == 'auto' ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: _S.of(context).d(16), height: _S.of(context).d(16),
                  margin: EdgeInsets.symmetric(horizontal: _S.of(context).s(2)),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                ),
              ),
            ),
          ),
          fields: const [],
        ),

        // ── Manual Payment Details (visible only when manual mode is ON) ──
        if (_paymentMode == 'manual') ...[
          SizedBox(height: _S.of(context).s(12)),
          Container(
            padding: EdgeInsets.all(_S.of(context).s(18)),
            decoration: BoxDecoration(
              color: kAmber.withOpacity(0.06),
              borderRadius: BorderRadius.circular(_S.of(context).s(16)),
              border: Border.all(color: kAmber.withOpacity(0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.info_outline_rounded, color: kAmber, size: _S.of(context).d(16)),
                SizedBox(width: _S.of(context).s(8)),
                Text('Manual Payment Details', style: TextStyle(fontSize: _S.of(context).f(13), fontWeight: FontWeight.w800, color: kAmber)),
              ]),
              SizedBox(height: _S.of(context).s(4)),
              Text('Shown to users when they select a plan', style: TextStyle(fontSize: _S.of(context).f(11), color: Colors.white.withOpacity(0.35))),
              SizedBox(height: _S.of(context).s(16)),

              // Payment Method (e.g. JazzCash, EasyPaisa)
              Text('Payment Method', style: TextStyle(fontSize: _S.of(context).f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
              SizedBox(height: _S.of(context).s(8)),
              _buildManualTextField(controller: _accountTitleCtrl, hint: 'e.g. JazzCash', icon: Icons.account_balance_wallet_rounded),
              SizedBox(height: _S.of(context).s(12)),

              // Account Number
              Text('Account Number', style: TextStyle(fontSize: _S.of(context).f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
              SizedBox(height: _S.of(context).s(8)),
              _buildManualTextField(controller: _accountNumberCtrl, hint: 'e.g. 03001234567', icon: Icons.phone_rounded, keyboard: TextInputType.phone),
              SizedBox(height: _S.of(context).s(16)),

              // Divider
              Row(children: [
                Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(10)),
                  child: Text('Bank Account (optional)', style: TextStyle(fontSize: _S.of(context).f(10.5), color: Colors.white.withOpacity(0.3), fontWeight: FontWeight.w600)),
                ),
                Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
              ]),
              SizedBox(height: _S.of(context).s(12)),

              // Bank Name
              Text('Bank Name', style: TextStyle(fontSize: _S.of(context).f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
              SizedBox(height: _S.of(context).s(8)),
              _buildManualTextField(controller: _bankNameCtrl, hint: 'e.g. Meezan Bank', icon: Icons.account_balance_rounded),
              SizedBox(height: _S.of(context).s(12)),

              // Account Holder Name
              Text('Account Holder Name', style: TextStyle(fontSize: _S.of(context).f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
              SizedBox(height: _S.of(context).s(8)),
              _buildManualTextField(controller: _bankHolderCtrl, hint: 'e.g. Muhammad Ali', icon: Icons.person_rounded),
              SizedBox(height: _S.of(context).s(12)),

              // IBAN
              Text('IBAN', style: TextStyle(fontSize: _S.of(context).f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
              SizedBox(height: _S.of(context).s(8)),
              _buildManualTextField(controller: _bankAccountCtrl, hint: 'e.g. PK36SCBL0000001123456702', icon: Icons.credit_card_rounded),
              SizedBox(height: _S.of(context).s(12)),

              // Swift Code
              Text('Swift Code', style: TextStyle(fontSize: _S.of(context).f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
              SizedBox(height: _S.of(context).s(8)),
              _buildManualTextField(controller: _bankSwiftCtrl, hint: 'e.g. MEZNPKKA', icon: Icons.code_rounded),
              SizedBox(height: _S.of(context).s(12)),

              // Payment Instructions
              Text('Payment Instructions', style: TextStyle(fontSize: _S.of(context).f(11.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
              SizedBox(height: _S.of(context).s(8)),
              TextFormField(
                controller: _paymentInstructionCtrl,
                maxLines: 3,
                style: TextStyle(fontSize: _S.of(context).f(13), color: Colors.white, height: 1.5),
                decoration: InputDecoration(
                  hintText: 'e.g. Send payment proof to WhatsApp after transfer...',
                  hintStyle: TextStyle(fontSize: _S.of(context).f(12), color: Colors.white.withOpacity(0.2), height: 1.5),
                  filled: true,
                  fillColor: kAmber.withOpacity(0.06),
                  contentPadding: EdgeInsets.all(_S.of(context).s(14)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(_S.of(context).s(12)), borderSide: BorderSide(color: kAmber.withOpacity(0.3))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_S.of(context).s(12)), borderSide: BorderSide(color: kAmber.withOpacity(0.3))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(_S.of(context).s(12)), borderSide: BorderSide(color: kAmber, width: 1.5)),
                ),
              ),
            ]),
          ),
        ],

        SizedBox(height: _S.of(context).s(25)),

        // ── Save button ──
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: _saving ? null : _save,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(vertical: _S.of(context).s(16)),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _saving ? [kPurple.withOpacity(0.5), kPurpleDeep.withOpacity(0.5)] : [kPurple, kPurpleDeep],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(_S.of(context).s(16)),
                boxShadow: _saving ? [] : [BoxShadow(color: kPurple.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Center(
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Save Pricing', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: _S.of(context).f(15))),
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
        prefixIcon: Icon(icon, color: kAmber.withOpacity(0.7), size: s.d(18)),
        filled: true,
        fillColor: kAmber.withOpacity(0.06),
        contentPadding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(14)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kAmber.withOpacity(0.3))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kAmber.withOpacity(0.3))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kAmber, width: 1.5)),
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

// ── Pricing card ──────────────────────────────────────────────────────────────
class _PricingCard extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final List<_PricingField> fields;
  final Widget? preview;
  final bool disabled;

  const _PricingCard({
    required this.icon, required this.color,
    required this.title, required this.subtitle,
    required this.fields, this.preview,
    this.disabled = false,
  });

  @override
  State<_PricingCard> createState() => _PricingCardState();
}

class _PricingCardState extends State<_PricingCard> {
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
        // Card header
        Row(children: [
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
        ]),
        SizedBox(height: _S.of(context).s(18)),
        // Fields
        Row(children: widget.fields.asMap().entries.map((e) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: e.key > 0 ? _S.of(context).s(10) : 0),
              child: e.value,
            ),
          );
        }).toList()),
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
