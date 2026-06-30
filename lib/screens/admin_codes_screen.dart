import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../services/admin_service.dart';
import '../models/admin_models.dart';

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

class AdminCodesScreen extends StatefulWidget {
  final AdminService svc;
  const AdminCodesScreen({super.key, required this.svc});

  @override
  State<AdminCodesScreen> createState() => _AdminCodesScreenState();
}

class _AdminCodesScreenState extends State<AdminCodesScreen> {
  String _lastGenerated = '';

  void _generateCode(SubscriptionTier tier) {
    final price = tier == SubscriptionTier.featured ? 2000.0 : 1000.0;
    final code = widget.svc.generateCode(tier, price);
    setState(() => _lastGenerated = code);
    HapticFeedback.mediumImpact();
    _showCodeDialog(code, tier);
  }

  void _showCodeDialog(String code, SubscriptionTier tier) {
    final isFeature = tier == SubscriptionTier.featured;
    showDialog(
      context: context,
      builder: (_) => Builder(builder: (context) {
        final s = _S.of(context);
        return AlertDialog(
          backgroundColor: const Color(0xFF16132A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(20))),
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: kGreen, size: s.d(20)),
              SizedBox(width: s.s(8)),
              Text('Code Generated!',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(15))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(s.s(16)),
                decoration: BoxDecoration(
                  color: isFeature ? kAmber.withOpacity(0.1) : kPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(s.s(14)),
                  border: Border.all(
                    color: isFeature ? kAmber.withOpacity(0.3) : kPurple.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      code,
                      style: TextStyle(
                        fontSize: s.f(22),
                        fontWeight: FontWeight.w900,
                        color: isFeature ? kAmber : kPurple,
                        letterSpacing: 2,
                      ),
                    ),
                    SizedBox(height: s.s(6)),
                    Text(
                      '${isFeature ? 'Featured' : 'Basic'} • Rs.${isFeature ? '2,000' : '1,000'} • 3 months',
                      style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.5)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: s.s(14)),
              Text(
                'Share this code with the customer after payment confirmation.',
                style: TextStyle(fontSize: s.f(12.5), color: Colors.white.withOpacity(0.5)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                HapticFeedback.lightImpact();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Code copied to clipboard!'),
                    backgroundColor: kGreen,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: s.s(20), vertical: s.s(8)),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPurple, kPurpleDeep]),
                  borderRadius: BorderRadius.circular(s.s(10)),
                ),
                child: Text('Copy Code',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(13))),
              ),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final codes = widget.svc.codes.reversed.toList();
    final unused = codes.where((c) => !c.isUsed).length;
    final used = codes.where((c) => c.isUsed).length;

    return ListView(
      padding: EdgeInsets.all(s.s(16)),
      children: [
        // Stats
        Row(
          children: [
            Expanded(child: _StatMini(label: 'Total Codes', value: codes.length.toString(), color: kPurple)),
            SizedBox(width: s.s(10)),
            Expanded(child: _StatMini(label: 'Unused', value: unused.toString(), color: kGreen)),
            SizedBox(width: s.s(10)),
            Expanded(child: _StatMini(label: 'Used', value: used.toString(), color: kAmber)),
          ],
        ),
        SizedBox(height: s.s(20)),

        // Generate section
        Container(
          padding: EdgeInsets.all(s.s(16)),
          decoration: BoxDecoration(
            color: const Color(0xFF16132A),
            borderRadius: BorderRadius.circular(s.s(18)),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Generate New Code',
                  style: TextStyle(fontSize: s.f(14), fontWeight: FontWeight.w700, color: Colors.white)),
              SizedBox(height: s.s(4)),
              Text('Generate after receiving payment from subscriber.',
                  style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.4))),
              SizedBox(height: s.s(14)),
              Row(
                children: [
                  Expanded(
                    child: _GenBtn(
                      label: 'Basic',
                      sublabel: 'Rs. 1,000',
                      color: kPurple,
                      icon: Icons.star_border_rounded,
                      onTap: () => _generateCode(SubscriptionTier.basic),
                    ),
                  ),
                  SizedBox(width: s.s(10)),
                  Expanded(
                    child: _GenBtn(
                      label: 'Featured',
                      sublabel: 'Rs. 2,000',
                      color: kAmber,
                      icon: Icons.star_rounded,
                      onTap: () => _generateCode(SubscriptionTier.featured),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: s.s(20)),

        Text('Code History',
            style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w700, color: Colors.white)),
        SizedBox(height: s.s(10)),

        ...codes.map((c) => _CodeRow(code: c, svc: widget.svc)),
      ],
    );
  }
}

class _StatMini extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatMini({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return Container(
      padding: EdgeInsets.all(s.s(12)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(s.s(14)),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(fontSize: s.f(22), fontWeight: FontWeight.w800, color: color)),
          SizedBox(height: s.s(2)),
          Text(label,
              style: TextStyle(fontSize: s.f(10.5), color: Colors.white.withOpacity(0.4)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _GenBtn extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _GenBtn({required this.label, required this.sublabel, required this.color, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: s.s(14)),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(s.s(14)),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: s.d(26)),
            SizedBox(height: s.s(6)),
            Text(label,
                style: TextStyle(fontSize: s.f(13.5), fontWeight: FontWeight.w700, color: color)),
            Text(sublabel,
                style: TextStyle(fontSize: s.f(11), color: color.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  final ActivationCode code;
  final AdminService svc;
  const _CodeRow({required this.code, required this.svc});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final isFeature = code.tier == SubscriptionTier.featured;
    final user = code.isUsed
        ? svc.users.where((u) => u.id == code.usedByUserId).firstOrNull
        : null;

    return Container(
      margin: EdgeInsets.only(bottom: s.s(8)),
      padding: EdgeInsets.all(s.s(12)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(s.s(14)),
        border: Border.all(
          color: code.isUsed ? Colors.white.withOpacity(0.06) : kGreen.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: s.d(36), height: s.d(36),
            decoration: BoxDecoration(
              color: (isFeature ? kAmber : kPurple).withOpacity(0.12),
              borderRadius: BorderRadius.circular(s.s(10)),
            ),
            child: Icon(
              isFeature ? Icons.star_rounded : Icons.star_border_rounded,
              color: isFeature ? kAmber : kPurple,
              size: s.d(18),
            ),
          ),
          SizedBox(width: s.s(10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code.code,
                  style: TextStyle(
                    fontSize: s.f(14),
                    fontWeight: FontWeight.w800,
                    color: code.isUsed ? Colors.white.withOpacity(0.4) : Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: s.s(2)),
                Text(
                  code.isUsed
                      ? 'Used by ${user?.name ?? 'Unknown'}'
                      : '${isFeature ? 'Featured' : 'Basic'} • Rs.${code.price.toInt()}',
                  style: TextStyle(fontSize: s.f(11), color: Colors.white.withOpacity(0.35)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: s.s(8), vertical: s.s(3)),
                decoration: BoxDecoration(
                  color: (code.isUsed ? Colors.white24 : kGreen).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(s.s(8)),
                ),
                child: Text(
                  code.isUsed ? 'Used' : 'Available',
                  style: TextStyle(
                    fontSize: s.f(10),
                    fontWeight: FontWeight.w700,
                    color: code.isUsed ? Colors.white38 : kGreen,
                  ),
                ),
              ),
              SizedBox(height: s.s(3)),
              if (!code.isUsed)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code.code));
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Code copied!'),
                        backgroundColor: kGreen,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                  child: Icon(Icons.copy_rounded, size: s.d(14), color: kPurple.withOpacity(0.7)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

  final AdminService svc;
  const AdminCodesScreen({super.key, required this.svc});

  @override
  State<AdminCodesScreen> createState() => _AdminCodesScreenState();
}

class _AdminCodesScreenState extends State<AdminCodesScreen> {
  String _lastGenerated = '';

  void _generateCode(SubscriptionTier tier) {
    final price = tier == SubscriptionTier.featured ? 2000.0 : 1000.0;
    final code = widget.svc.generateCode(tier, price);
    setState(() => _lastGenerated = code);
    HapticFeedback.mediumImpact();
    _showCodeDialog(code, tier);
  }

  void _showCodeDialog(String code, SubscriptionTier tier) {
    final isFeature = tier == SubscriptionTier.featured;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16132A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: kGreen, size: 20),
            const SizedBox(width: 8),
            const Text('Code Generated!',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isFeature ? kAmber.withOpacity(0.1) : kPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isFeature ? kAmber.withOpacity(0.3) : kPurple.withOpacity(0.3),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    code,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isFeature ? kAmber : kPurple,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${isFeature ? 'Featured' : 'Basic'} • Rs.${isFeature ? '2,000' : '1,000'} • 3 months',
                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Share this code with the customer after payment confirmation.',
              style: TextStyle(fontSize: 12.5, color: Colors.white.withOpacity(0.5)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              HapticFeedback.lightImpact();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Code copied to clipboard!'),
                  backgroundColor: kGreen,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kPurple, kPurpleDeep]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Copy Code',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final codes = widget.svc.codes.reversed.toList();
    final unused = codes.where((c) => !c.isUsed).length;
    final used = codes.where((c) => c.isUsed).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats
        Row(
          children: [
            Expanded(child: _StatMini(label: 'Total Codes', value: codes.length.toString(), color: kPurple)),
            const SizedBox(width: 10),
            Expanded(child: _StatMini(label: 'Unused', value: unused.toString(), color: kGreen)),
            const SizedBox(width: 10),
            Expanded(child: _StatMini(label: 'Used', value: used.toString(), color: kAmber)),
          ],
        ),
        const SizedBox(height: 20),

        // Generate section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF16132A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Generate New Code',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 4),
              Text('Generate after receiving payment from subscriber.',
                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _GenBtn(
                      label: 'Basic',
                      sublabel: 'Rs. 1,000',
                      color: kPurple,
                      icon: Icons.star_border_rounded,
                      onTap: () => _generateCode(SubscriptionTier.basic),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _GenBtn(
                      label: 'Featured',
                      sublabel: 'Rs. 2,000',
                      color: kAmber,
                      icon: Icons.star_rounded,
                      onTap: () => _generateCode(SubscriptionTier.featured),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        const Text('Code History',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 10),

        ...codes.map((c) => _CodeRow(code: c, svc: widget.svc)),
      ],
    );
  }
}

class _StatMini extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatMini({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 10.5, color: Colors.white.withOpacity(0.4)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _GenBtn extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _GenBtn({required this.label, required this.sublabel, required this.color, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
            Text(sublabel,
                style: TextStyle(fontSize: 11, color: color.withOpacity(0.6))),
          ],
        ),
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  final ActivationCode code;
  final AdminService svc;
  const _CodeRow({required this.code, required this.svc});

  @override
  Widget build(BuildContext context) {
    final isFeature = code.tier == SubscriptionTier.featured;
    final user = code.isUsed
        ? svc.users.where((u) => u.id == code.usedByUserId).firstOrNull
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: code.isUsed ? Colors.white.withOpacity(0.06) : kGreen.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: (isFeature ? kAmber : kPurple).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isFeature ? Icons.star_rounded : Icons.star_border_rounded,
              color: isFeature ? kAmber : kPurple,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code.code,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: code.isUsed ? Colors.white.withOpacity(0.4) : Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  code.isUsed
                      ? 'Used by ${user?.name ?? 'Unknown'}'
                      : '${isFeature ? 'Featured' : 'Basic'} • Rs.${code.price.toInt()}',
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (code.isUsed ? Colors.white24 : kGreen).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  code.isUsed ? 'Used' : 'Available',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: code.isUsed ? Colors.white38 : kGreen,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              if (!code.isUsed)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code.code));
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Code copied!'),
                        backgroundColor: kGreen,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  },
                  child: Icon(Icons.copy_rounded, size: 14, color: kPurple.withOpacity(0.7)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
