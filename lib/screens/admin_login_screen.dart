import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/theme.dart';
import '../services/admin_service.dart';
import '../services/fcm_service.dart';
import 'admin_dashboard_screen.dart';

class _S {
  final double scale;
  final bool isTablet;
  const _S(this.scale, {this.isTablet = false});
  double f(double size) => size * scale;
  double s(double size) => size * scale;
  double d(double size) => size * scale;
  static _S of(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final isTablet = w >= 600;
    final scale = kIsWeb ? 1.0 : isTablet ? (w / 390.0).clamp(1.0, 1.3) : (w / 390.0).clamp(0.72, 1.0);
    return _S(scale, isTablet: isTablet);
  }
}

class AdminLoginScreen extends StatefulWidget {
  final AdminService? adminService;
  const AdminLoginScreen({super.key, this.adminService});
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen>
    with SingleTickerProviderStateMixin {
  late final AdminService _svc;
  final _phoneCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _passFocus = FocusNode();
  bool _obscure  = true;
  bool _loading  = false;
  String? _error;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  bool get _canSubmit =>
      !_loading && _phoneCtrl.text.trim().length == 11 && _passCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _svc = widget.adminService ?? AdminService();
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );
    _init();
  }

  Future<void> _init() async {
    await _loadSaved();
    if (!kIsWeb) await _checkAutoLogin();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('admin_phone') ?? '';
    if (saved.isNotEmpty && mounted) {
      setState(() => _phoneCtrl.text = saved);
      _passFocus.requestFocus();
    }
  }

  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPhone = prefs.getString('admin_phone') ?? '';
    final savedPass  = prefs.getString('admin_password') ?? '';
    if (savedPhone.isEmpty || savedPass.isEmpty) return;
    if (!mounted) return;
    setState(() => _loading = true);
    final result = await _svc.loginWithCredentials(savedPhone, savedPass);
    if (!mounted) return;
    if (result == null) {
      if (!kIsWeb) await FCMService.instance.saveAdminToken();
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => AdminDashboardScreen(adminService: _svc)));
      return;
    }
    await prefs.remove('admin_password');
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _passFocus.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    FocusScope.of(context).unfocus();
    final phone    = _phoneCtrl.text.trim();
    final password = _passCtrl.text.trim();
    setState(() { _loading = true; _error = null; });
    final result = await _svc.loginWithCredentials(phone, password);
    if (!mounted) return;
    if (result == null) {
      if (!kIsWeb) await FCMService.instance.saveAdminToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('admin_phone', phone);
      await prefs.setString('admin_password', password);
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => AdminDashboardScreen(adminService: _svc)));
      return;
    }
    if (!kIsWeb) HapticFeedback.heavyImpact();
    _shakeCtrl.forward(from: 0);
    setState(() {
      _loading = false;
      _error = result == 'offline'
          ? 'No internet connection. Please try again.'
          : 'Wrong phone number or password.';
      _passCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    if (!kIsWeb) {
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: kInk,
        statusBarIconBrightness: Brightness.light,
      ));
    }
    return Scaffold(
      backgroundColor: kInk,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: s.s(24), vertical: s.s(28)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AnimatedBuilder(
                animation: _shakeAnim,
                builder: (context, child) {
                  final shake = _error != null ? math.sin(_shakeAnim.value * 3 * math.pi) * 8 : 0.0;
                  return Transform.translate(offset: Offset(shake, 0), child: child);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLogo(s),
                    SizedBox(height: s.s(20)),
                    Text('Admin Panel',
                        style: TextStyle(fontSize: s.f(22), fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
                    SizedBox(height: s.s(6)),
                    Text('Sign in with your phone number and password',
                        style: TextStyle(fontSize: s.f(13), color: Colors.white.withOpacity(0.5)),
                        textAlign: TextAlign.center),
                    SizedBox(height: s.s(30)),
                    _buildPhoneField(s),
                    SizedBox(height: s.s(12)),
                    _buildPasswordField(s),
                    SizedBox(height: s.s(14)),
                    _buildError(s),
                    SizedBox(height: s.s(6)),
                    _buildSubmit(s),
                    SizedBox(height: s.s(18)),
                    Text('Access is set by the main admin in Settings → Create Admin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: s.f(11), height: 1.5, color: Colors.white.withOpacity(0.28))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(_S s) {
    return Container(
      width: s.d(68), height: s.d(68),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kPurple, kPurpleDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(s.s(18)),
        boxShadow: [BoxShadow(color: kPurple.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: s.d(36)),
    );
  }

  Widget _buildPhoneField(_S s) {
    return TextField(
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      style: TextStyle(color: Colors.white, fontSize: s.f(15), letterSpacing: 0.4),
      onChanged: (_) => setState(() => _error = null),
      onSubmitted: (_) => _passFocus.requestFocus(),
      decoration: _decoration(s, hint: '03011234567', label: 'Phone Number', icon: Icons.phone_rounded),
    );
  }

  Widget _buildPasswordField(_S s) {
    return TextField(
      controller: _passCtrl,
      focusNode: _passFocus,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      style: TextStyle(color: Colors.white, fontSize: s.f(15)),
      onChanged: (_) => setState(() => _error = null),
      onSubmitted: (_) => _submit(),
      decoration: _decoration(s,
          hint: 'Password',
          label: 'Password',
          icon: Icons.lock_outline_rounded,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.white.withOpacity(0.4), size: s.d(19)),
            onPressed: () => setState(() => _obscure = !_obscure),
          )),
    );
  }

  Widget _buildError(_S s) {
    return SizedBox(
      height: s.d(20),
      child: _error == null
          ? const SizedBox.shrink()
          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.error_outline_rounded, size: s.d(14), color: kRose),
              SizedBox(width: s.s(6)),
              Flexible(child: Text(_error!, style: TextStyle(fontSize: s.f(12.5), color: kRose.withOpacity(0.95)))),
            ]),
    );
  }

  Widget _buildSubmit(_S s) {
    return GestureDetector(
      onTap: _canSubmit ? _submit : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        height: s.d(52),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _canSubmit ? [kPurple, kPurpleDeep] : [kPurple.withOpacity(0.3), kPurpleDeep.withOpacity(0.3)],
          ),
          borderRadius: BorderRadius.circular(s.s(14)),
          boxShadow: _canSubmit ? [BoxShadow(color: kPurple.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 6))] : null,
        ),
        child: Center(
          child: _loading
              ? SizedBox(width: s.d(20), height: s.d(20), child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text('Login',
                  style: TextStyle(color: Colors.white.withOpacity(_canSubmit ? 1 : 0.6), fontSize: s.f(15), fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  InputDecoration _decoration(_S s, {required String hint, required String label, required IconData icon, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: s.f(13)),
      floatingLabelStyle: TextStyle(color: kPurple, fontSize: s.f(13)),
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: s.f(13.5)),
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      contentPadding: EdgeInsets.fromLTRB(s.s(14), s.s(16), suffixIcon != null ? s.s(52) : s.s(14), s.s(16)),
      prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.4), size: s.d(19)),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(12)), borderSide: BorderSide(color: kPurple.withOpacity(0.7), width: 1.4)),
    );
  }
}
