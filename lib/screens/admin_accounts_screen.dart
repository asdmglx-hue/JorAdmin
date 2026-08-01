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

// ── CNIC auto-formatter (13 digits, dashes at positions 5 and 12) ─────────
class _CnicFormatter extends TextInputFormatter {
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

// ── AdminAccountsScreen ─────────────────────────────────────────────────────
// Dashboard → Settings → Create Admin. Lets the admin create, update, list,
// and remove CNIC+password logins. Logging in with one of these on the
// regular login screen unlocks full (unblurred/unmasked) viewing of every
// profile — it is unrelated to this Admin Panel's own PIN login.
class AdminAccountsScreen extends StatefulWidget {
  final AdminService svc;
  const AdminAccountsScreen({super.key, required this.svc});

  @override
  State<AdminAccountsScreen> createState() => _AdminAccountsScreenState();
}

class _AdminAccountsScreenState extends State<AdminAccountsScreen> {
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
    widget.svc.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    widget.svc.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() { if (mounted) setState(() {}); }

  Future<void> _load() async {
    await widget.svc.loadAdminAccounts();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await widget.svc.loadAdminAccounts();
    if (mounted) setState(() => _refreshing = false);
  }

  void _openForm({AdminAccount? existing}) {
    showDialog(
      context: context,
      builder: (_) => _AdminAccountFormDialog(svc: widget.svc, existing: existing),
    );
  }

  void _confirmDelete(AdminAccount account) {
    final s = _S.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16132A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(16))),
        title: Text('Remove Admin?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: s.f(16))),
        content: Text(
          '${account.name} (${account.cnic}) will no longer be able to log in with unlocked access.',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: s.f(13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4))),
          ),
          GestureDetector(
            onTap: () async {
              Navigator.pop(ctx);
              await widget.svc.deleteAdminAccount(account.id);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: kRose, borderRadius: BorderRadius.circular(8)),
              child: const Text('Remove', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final accounts = widget.svc.adminAccounts;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16132A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Admin Accounts', style: TextStyle(fontSize: s.f(16), fontWeight: FontWeight.w700)),
            Text('${accounts.length} account${accounts.length != 1 ? 's' : ''}',
                style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.4))),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: _refresh,
            child: Container(
              margin: EdgeInsets.only(right: s.s(8)),
              padding: EdgeInsets.all(s.s(6)),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(8))),
              child: _refreshing
                  ? SizedBox(width: s.d(16), height: s.d(16), child: const CircularProgressIndicator(color: Colors.white54, strokeWidth: 2))
                  : Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18)),
            ),
          ),
          GestureDetector(
            onTap: () => _openForm(),
            child: Container(
              margin: EdgeInsets.only(right: s.s(16)),
              padding: EdgeInsets.symmetric(horizontal: s.s(12), vertical: s.s(6)),
              decoration: BoxDecoration(
                color: kPurple.withOpacity(0.15),
                borderRadius: BorderRadius.circular(s.s(8)),
                border: Border.all(color: kPurple.withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, color: kPurple, size: s.d(16)),
                SizedBox(width: s.s(4)),
                Text('Add', style: TextStyle(color: kPurple, fontSize: s.f(12), fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white.withOpacity(0.07)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPurple))
          : accounts.isEmpty
              ? _buildEmptyState(s)
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(s.s(16), s.s(14), s.s(16), s.s(24)),
                  itemCount: accounts.length,
                  itemBuilder: (_, i) => _AdminAccountCard(
                    account: accounts[i],
                    onEdit: () => _openForm(existing: accounts[i]),
                    onDelete: () => _confirmDelete(accounts[i]),
                  ),
                ),
    );
  }

  Widget _buildEmptyState(_S s) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(s.s(32)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.admin_panel_settings_outlined, color: Colors.white.withOpacity(0.15), size: s.d(56)),
          SizedBox(height: s.s(16)),
          Text('No admin accounts yet', style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w700, fontSize: s.f(15))),
          SizedBox(height: s.s(6)),
          Text(
            'Create one to let a CNIC + password log in with every profile unlocked.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: s.f(12.5)),
          ),
          SizedBox(height: s.s(20)),
          GestureDetector(
            onTap: () => _openForm(),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: s.s(18), vertical: s.s(10)),
              decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(s.s(10))),
              child: Text('+ Create Admin', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(13))),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Account card ────────────────────────────────────────────────────────────
class _AdminAccountCard extends StatelessWidget {
  final AdminAccount account;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _AdminAccountCard({required this.account, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: s.s(10)),
      padding: EdgeInsets.all(s.s(14)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(s.s(16)),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(children: [
        Container(
          width: s.d(40),
          height: s.d(40),
          decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(10))),
          child: Icon(Icons.person_rounded, color: kPurple, size: s.d(20)),
        ),
        SizedBox(width: s.s(12)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(account.name, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(14))),
            SizedBox(height: s.s(2)),
            Text(account.cnic, style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: s.f(12), letterSpacing: 0.3)),
          ]),
        ),
        GestureDetector(
          onTap: onEdit,
          child: Container(
            padding: EdgeInsets.all(s.s(8)),
            margin: EdgeInsets.only(right: s.s(6)),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(8))),
            child: Icon(Icons.edit_rounded, color: Colors.white.withOpacity(0.6), size: s.d(16)),
          ),
        ),
        GestureDetector(
          onTap: onDelete,
          child: Container(
            padding: EdgeInsets.all(s.s(8)),
            decoration: BoxDecoration(color: kRose.withOpacity(0.12), borderRadius: BorderRadius.circular(s.s(8))),
            child: Icon(Icons.delete_outline_rounded, color: kRose, size: s.d(16)),
          ),
        ),
      ]),
    );
  }
}

// ── Create / Edit form dialog ───────────────────────────────────────────────
class _AdminAccountFormDialog extends StatefulWidget {
  final AdminService svc;
  final AdminAccount? existing;
  const _AdminAccountFormDialog({required this.svc, this.existing});

  @override
  State<_AdminAccountFormDialog> createState() => _AdminAccountFormDialogState();
}

class _AdminAccountFormDialogState extends State<_AdminAccountFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _cnicCtrl;
  late final TextEditingController _passCtrl;
  bool _passObscure = true;
  bool _saving = false;
  String? _error;
  int _cnicDigits = 0;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _cnicCtrl = TextEditingController(text: widget.existing?.cnic ?? '');
    _passCtrl = TextEditingController(text: widget.existing?.password ?? '');
    _cnicDigits = (widget.existing?.cnic ?? '').replaceAll('-', '').length;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cnicCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final cnic = _cnicCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    if (cnic.replaceAll('-', '').length != 13) {
      setState(() => _error = 'Enter complete CNIC (13 digits)');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }

    setState(() { _saving = true; _error = null; });

    final err = _isEdit
        ? await widget.svc.updateAdminAccount(id: widget.existing!.id, name: name, cnic: cnic, password: pass)
        : await widget.svc.createAdminAccount(name: name, cnic: cnic, password: pass);

    if (!mounted) return;

    if (err != null) {
      setState(() { _saving = false; _error = err; });
      return;
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return AlertDialog(
      backgroundColor: const Color(0xFF16132A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Icon(Icons.admin_panel_settings_rounded, color: kPurple, size: 20),
        const SizedBox(width: 8),
        Text(_isEdit ? 'Update Admin' : 'Create Admin',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Name field
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _fieldDecoration(hint: 'Name', icon: Icons.badge_outlined),
          ),
          const SizedBox(height: 12),
          // CNIC field
          Stack(children: [
            TextField(
              controller: _cnicCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
                _CnicFormatter(),
              ],
              style: const TextStyle(color: Colors.white, fontSize: 14),
              onChanged: (v) => setState(() { _cnicDigits = v.replaceAll('-', '').length; _error = null; }),
              decoration: _fieldDecoration(hint: '35202-1234567-1', icon: Icons.credit_card_rounded, trailingPad: true),
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
            controller: _passCtrl,
            obscureText: _passObscure,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _fieldDecoration(
              hint: 'Password (min 6 chars)',
              icon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                icon: Icon(_passObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Colors.white.withOpacity(0.4), size: 18),
                onPressed: () => setState(() => _passObscure = !_passObscure),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(fontSize: 12, color: kRose)),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4))),
        ),
        GestureDetector(
          onTap: _saving ? null : _submit,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(8)),
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(_isEdit ? 'Save' : 'Create', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({required String hint, required IconData icon, Widget? suffixIcon, bool trailingPad = false}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
      filled: true, fillColor: Colors.white.withOpacity(0.06),
      contentPadding: EdgeInsets.fromLTRB(14, 12, trailingPad || suffixIcon != null ? 48 : 14, 12),
      prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.4), size: 18),
      suffixIcon: suffixIcon,
      border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: kPurple.withOpacity(0.6))),
    );
  }
}
