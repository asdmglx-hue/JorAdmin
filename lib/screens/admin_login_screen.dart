import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../services/admin_service.dart';
import '../services/fcm_service.dart';
import '../services/supabase_service.dart';
import 'admin_dashboard_screen.dart';

// ── Responsive scale helper ────────────────────────────────────────────────
class _S {
  final double scale;
  final bool isTablet;
  final bool isLandscape;
  const _S(this.scale, {this.isTablet = false, this.isLandscape = false});

  double f(double size) => size * scale;
  double s(double size) => size * scale;
  double d(double size) => size * scale;

  static _S of(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final h = mq.size.height;
    final isTablet = w >= 600;
    final isLandscape = mq.orientation == Orientation.landscape;
    // Scale up for tablets, scale down for small phones, cap at 1.3 for large tablets
    final scale = isTablet
        ? (w / 390.0).clamp(1.0, 1.3)
        : (w / 390.0).clamp(0.72, 1.0);
    return _S(scale, isTablet: isTablet, isLandscape: isLandscape);
  }
}

// ── AdminLoginScreen ──────────────────────────────────────────────────────────
class AdminLoginScreen extends StatefulWidget {
  final AdminService? adminService;
  const AdminLoginScreen({super.key, this.adminService});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen>
    with SingleTickerProviderStateMixin {
  final _db = SupabaseService.instance;
  late final AdminService _svc;

  static const String _adminEmail = 'admin@jorapp.com';
  static const int _pinLength = 6;

  final List<String> _pin = [];
  bool _hasError = false;
  bool _loading = false;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _svc = widget.adminService ?? AdminService();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _onKey(String digit) {
    if (_pin.length >= _pinLength || _loading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin.add(digit);
      _hasError = false;
    });
    if (_pin.length == _pinLength) _verify();
  }

  void _onDelete() {
    if (_pin.isEmpty || _loading) return;
    HapticFeedback.lightImpact();
    setState(() => _pin.removeLast());
  }

  Future<void> _verify() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 150));
    final pin = _pin.join();

    bool success = await _db.adminLogin(_adminEmail, pin);

    if (!mounted) return;

    if (success) {
      await FCMService.instance.saveAdminToken(); // ✨ FIXED: Added await
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminDashboardScreen(adminService: _svc),
        ),
      );
    } else {
      HapticFeedback.heavyImpact();
      _shakeCtrl.forward(from: 0);
      setState(() {
        _hasError = true;
        _pin.clear();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: kInk,
      statusBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: kInk,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            // Cap width so tablets don't stretch the keypad wall-to-wall
            constraints: const BoxConstraints(maxWidth: 480),
            child: s.isLandscape
                ? _buildLandscapeLayout(s)
                : _buildPortraitLayout(s),
          ),
        ),
      ),
    );
  }

  // ── Portrait layout ────────────────────────────────────────────────────────
  Widget _buildPortraitLayout(_S s) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: s.s(24)),
        child: Column(
          children: [
            SizedBox(height: s.s(52)),
            _buildLogo(s),
            SizedBox(height: s.s(20)),
            _buildTitle(s),
            SizedBox(height: s.s(40)),
            _buildPinDots(s),
            SizedBox(height: s.s(20)),
            _buildFeedback(s),
            SizedBox(height: s.s(36)),
            _buildKeypad(s),
            SizedBox(height: s.s(32)),
          ],
        ),
      ),
    );
  }

  // ── Landscape layout ───────────────────────────────────────────────────────
  // Two-column: left = logo + title + PIN dots, right = keypad
  Widget _buildLandscapeLayout(_S s) {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: s.s(24), vertical: s.s(16)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left column
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLogo(s),
                  SizedBox(height: s.s(16)),
                  _buildTitle(s),
                  SizedBox(height: s.s(28)),
                  _buildPinDots(s),
                  SizedBox(height: s.s(12)),
                  _buildFeedback(s),
                ],
              ),
            ),
            SizedBox(width: s.s(24)),
            // Right column – keypad
            _buildKeypad(s),
          ],
        ),
      ),
    );
  }

  // ── Shared sub-widgets ─────────────────────────────────────────────────────
  Widget _buildLogo(_S s) {
    return Container(
      width: s.d(68),
      height: s.d(68),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPurple, kPurpleDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(s.s(18)),
        boxShadow: [
          BoxShadow(
              color: kPurple.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 8))
        ],
      ),
      child: Icon(Icons.admin_panel_settings_rounded,
          color: Colors.white, size: s.d(36)),
    );
  }

  Widget _buildTitle(_S s) {
    return Column(
      children: [
        Text(
          'Admin Panel',
          style: TextStyle(
              fontSize: s.f(22),
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5),
        ),
        SizedBox(height: s.s(5)),
        Text(
          'Enter your 6-digit PIN to continue',
          style: TextStyle(
              fontSize: s.f(13), color: Colors.white.withOpacity(0.5)),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPinDots(_S s) {
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (context, child) {
        final shake =
            _hasError ? math.sin(_shakeAnim.value * 3 * math.pi) * 10 : 0.0;
        return Transform.translate(offset: Offset(shake, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_pinLength, (i) {
          final filled = i < _pin.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: EdgeInsets.symmetric(horizontal: s.s(8)),
            width: s.d(14),
            height: s.d(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? (_hasError ? kRose : kPurple)
                  : Colors.white.withOpacity(0.15),
              boxShadow: filled && !_hasError
                  ? [
                      BoxShadow(
                          color: kPurple.withOpacity(0.5), blurRadius: 8)
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildFeedback(_S s) {
    return SizedBox(
      height: s.d(24),
      child: Center(
        child: _loading
            ? SizedBox(
                width: s.d(20),
                height: s.d(20),
                child: const CircularProgressIndicator(
                    color: kPurple, strokeWidth: 2))
            : _hasError
                ? Text(
                    'Incorrect PIN. Try again.',
                    style: TextStyle(
                        fontSize: s.f(12), color: kRose.withOpacity(0.9)),
                  )
                : const SizedBox(),
      ),
    );
  }

  Widget _buildKeypad(_S s) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _KeypadRow(digits: const ['1', '2', '3'], onKey: _onKey, s: s),
        SizedBox(height: s.s(10)),
        _KeypadRow(digits: const ['4', '5', '6'], onKey: _onKey, s: s),
        SizedBox(height: s.s(10)),
        _KeypadRow(digits: const ['7', '8', '9'], onKey: _onKey, s: s),
        SizedBox(height: s.s(10)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _BackButton(onTap: () => Navigator.pop(context), s: s),
            _KeypadButton(label: '0', onTap: () => _onKey('0'), s: s),
            _DeleteButton(onTap: _onDelete, s: s),
          ],
        ),
      ],
    );
  }
}

// ── Keypad widgets ─────────────────────────────────────────────────────────────
class _KeypadRow extends StatelessWidget {
  final List<String> digits;
  final void Function(String) onKey;
  final _S s;
  const _KeypadRow(
      {required this.digits, required this.onKey, required this.s});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children:
            digits.map((d) => _KeypadButton(label: d, onTap: () => onKey(d), s: s)).toList(),
      );
}

class _KeypadButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final _S s;
  const _KeypadButton(
      {required this.label, required this.onTap, required this.s});

  @override
  State<_KeypadButton> createState() => _KeypadButtonState();
}

class _KeypadButtonState extends State<_KeypadButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: s.d(72),
        height: s.d(72),
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(s.s(18)),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
                fontSize: s.f(24),
                fontWeight: FontWeight.w600,
                color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  final VoidCallback onTap;
  final _S s;
  const _DeleteButton({required this.onTap, required this.s});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: s.d(72),
        height: s.d(72),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(s.s(18)),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Icon(Icons.backspace_outlined,
            color: Colors.white.withOpacity(0.7), size: s.d(22)),
      ),
    );
  }
}

class _BackButton extends StatefulWidget {
  final VoidCallback onTap;
  final _S s;
  const _BackButton({required this.onTap, required this.s});

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: s.d(72),
        height: s.d(72),
        decoration: BoxDecoration(
          color: _pressed
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(s.s(18)),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Center(
          child: Icon(Icons.arrow_back_ios_rounded,
              color: Colors.white.withOpacity(0.7), size: s.d(20)),
        ),
      ),
    );
  }
}
