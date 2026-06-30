import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/theme.dart';

final _db = Supabase.instance.client;
typedef _S = _Sizer;

// ignore: non_constant_identifier_names
_Sizer _SizerOf(BuildContext ctx) => _Sizer(ctx);
class _Sizer {
  final BuildContext _ctx;
  _Sizer(this._ctx);
  static _Sizer of(BuildContext ctx) => _Sizer(ctx);
  double s(double v) => v;
  double d(double v) => v;
  double f(double v) => v;
}

class AdminLocationsScreen extends StatefulWidget {
  const AdminLocationsScreen({super.key});
  @override
  State<AdminLocationsScreen> createState() => _AdminLocationsScreenState();
}

class _AdminLocationsScreenState extends State<AdminLocationsScreen> {
  List<Map<String, dynamic>> _centers = [];
  bool _loading = true;
  String? _filterCity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await _db.from('jor_centers').select().order('city').order('sort_order');
      setState(() { _centers = List<Map<String, dynamic>>.from(res); _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  List<String> get _cities {
    final cities = _centers.map((c) => c['city'] as String).toSet().toList()..sort();
    return cities;
  }

  List<Map<String, dynamic>> get _filtered => _filterCity == null
      ? _centers
      : _centers.where((c) => c['city'] == _filterCity).toList();

  void _showForm({Map<String, dynamic>? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CenterForm(
        existing: existing,
        onSaved: _load,
      ),
    );
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A35),
        title: const Text('Delete Center?', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        content: const Text('This will permanently remove this center.', style: TextStyle(color: Colors.white54, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: kRose, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true) return;
    await _db.from('jor_centers').delete().eq('id', id);
    _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> center) async {
    await _db.from('jor_centers').update({'is_active': !(center['is_active'] as bool)}).eq('id', center['id']);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1E),
      body: Column(children: [
        // ── Content ──
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPurple))
            : _filtered.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.location_off_rounded, size: 48, color: Colors.white.withOpacity(0.15)),
                  const SizedBox(height: 12),
                  Text('No centers yet', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14)),
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => _showForm(), child: const Text('Add First Center', style: TextStyle(color: kPurple, fontWeight: FontWeight.w700))),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final c = _filtered[i];
                    final active = c['is_active'] as bool? ?? true;
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1A35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(active ? 0.08 : 0.04)),
                      ),
                      child: Column(children: [
                        // Card header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 0),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(c['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(20)),
                                  child: Text(c['city'] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                                ),
                              ]),
                              const SizedBox(height: 8),
                              _InfoRow(icon: Icons.location_on_outlined, text: c['address'] ?? ''),
                              const SizedBox(height: 4),
                              _InfoRow(icon: Icons.phone_outlined, text: c['phone'] ?? ''),
                              const SizedBox(height: 4),
                              _InfoRow(icon: Icons.access_time_rounded, text: c['timing'] ?? ''),
                            ])),
                          ]),
                        ),
                        // Action bar
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                            // Edit
                            GestureDetector(
                              onTap: () => _showForm(existing: c),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                                ),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.edit_rounded, size: 11, color: Colors.white70),
                                  SizedBox(width: 4),
                                  Text('Edit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70)),
                                ]),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Delete
                            GestureDetector(
                              onTap: () => _delete(c['id']),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: kRose.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(color: kRose.withOpacity(0.2)),
                                ),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.delete_outline_rounded, size: 11, color: kRose),
                                  SizedBox(width: 4),
                                  Text('Delete', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kRose)),
                                ]),
                              ),
                            ),
                          ]),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      ]),

      // ── FAB ──
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        backgroundColor: kPurple,
        icon: const Icon(Icons.add_location_alt_rounded, color: Colors.white),
        label: const Text('Add Center', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ── Add / Edit Form ────────────────────────────────────────────────────────────
class _CenterForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const _CenterForm({this.existing, required this.onSaved});
  @override
  State<_CenterForm> createState() => _CenterFormState();
}

class _CenterFormState extends State<_CenterForm> {
  late final TextEditingController _name, _city, _address, _phone, _timing;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name    = TextEditingController(text: e?['name']    ?? '');
    _city    = TextEditingController(text: e?['city']    ?? '');
    _address = TextEditingController(text: e?['address'] ?? '');
    _phone   = TextEditingController(text: e?['phone']   ?? '');
    _timing  = TextEditingController(text: e?['timing']  ?? '');
  }

  @override
  void dispose() {
    _name.dispose(); _city.dispose(); _address.dispose();
    _phone.dispose(); _timing.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _city.text.trim().isEmpty ||
        _address.text.trim().isEmpty || _phone.text.trim().isEmpty ||
        _timing.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }
    setState(() => _saving = true);
    final data = {
      'name':    _name.text.trim(),
      'city':    _city.text.trim(),
      'address': _address.text.trim(),
      'phone':   _phone.text.trim(),
      'timing':  _timing.text.trim(),
    };
    try {
      if (widget.existing != null) {
        await _db.from('jor_centers').update(data).eq('id', widget.existing!['id']);
      } else {
        await _db.from('jor_centers').insert(data);
      }
      if (mounted) { Navigator.pop(context); widget.onSaved(); }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1A35),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(isEdit ? 'Edit Center' : 'Add Center',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.4), size: 22),
            ),
          ]),
          const SizedBox(height: 16),
          _Field(ctrl: _name,    label: 'Center Name',    hint: 'Jor Rishta Center — Lahore'),
          const SizedBox(height: 10),
          _Field(ctrl: _city,    label: 'City',           hint: 'Lahore'),
          const SizedBox(height: 10),
          _Field(ctrl: _address, label: 'Address',        hint: 'Full address', maxLines: 2),
          const SizedBox(height: 10),
          _Field(ctrl: _phone,   label: 'Phone',          hint: '0300-1234567', kb: TextInputType.phone),
          const SizedBox(height: 10),
          _Field(ctrl: _timing,  label: 'Timing',         hint: 'Mon–Sat: 10am – 7pm'),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _saving ? null : _save,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [kPurple, kPurpleDeep]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(isEdit ? 'Save Changes' : 'Add Center',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Small helpers ──────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final int maxLines;
  final TextInputType kb;
  const _Field({required this.ctrl, required this.label, required this.hint, this.maxLines = 1, this.kb = TextInputType.text});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
      const SizedBox(height: 5),
      TextField(
        controller: ctrl,
        keyboardType: kb,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 13),
          filled: true,
          fillColor: Colors.black.withOpacity(0.25),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPurple)),
        ),
      ),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 13, color: Colors.white38),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: Colors.white60, height: 1.4))),
    ]);
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? kPurple : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? kPurple : Colors.white.withOpacity(0.1), width: selected ? 1.5 : 1),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? Colors.white : Colors.white54,
        )),
      ),
    );
  }
}
