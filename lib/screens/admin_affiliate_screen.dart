import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../services/supabase_service.dart';

const _kBg     = Color(0xFF16132A);
const _kCard   = Color(0xFF1E1A33);
const _kBorder = Color(0xFF2D2847);
const _kText   = Colors.white;
const _kSub    = Color(0xFFB0ADCB);
const _kFaint  = Color(0xFF6B6893);

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

class AdminAffiliateScreen extends StatefulWidget {
  final void Function(VoidCallback)? onRegisterCallback;
  final void Function(VoidCallback)? onRefreshCallback;
  final VoidCallback? onAffiliateDeleted;
  const AdminAffiliateScreen({super.key, this.onRegisterCallback, this.onRefreshCallback, this.onAffiliateDeleted});
  @override
  State<AdminAffiliateScreen> createState() => _AdminAffiliateScreenState();
}

class _AdminAffiliateScreenState extends State<AdminAffiliateScreen> {
  final _db = SupabaseService.instance;
  List<Map<String, dynamic>> _affiliates = [];
  bool _loading = true;
  bool _sheetOpen = false;
  String? _error;
  String _generatedCode = '';
  Set<String> _selectedIds = {};
  bool _selecting = false;

  void _enterSelectMode(String id) {
    HapticFeedback.mediumImpact();
    setState(() { _selecting = true; _selectedIds = {id}; });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) { _selectedIds.remove(id); if (_selectedIds.isEmpty) _selecting = false; }
      else _selectedIds.add(id);
    });
  }

  void _cancelSelect() => setState(() { _selecting = false; _selectedIds.clear(); });

  Future<void> _deleteSelected() async {
    final ids = List<String>.from(_selectedIds);
    // Remove instantly from local list — no flicker
    _cancelSelect();
    setState(() => _affiliates.removeWhere((a) => ids.contains(a['id'] as String)));
    widget.onAffiliateDeleted?.call();
    final now = DateTime.now().toIso8601String();
    try {
      for (final id in ids) {
        await _db.client.from('affiliates').update({'deleted': true, 'deleted_at': now}).eq('id', id);
      }
    } catch (_) {
      // On failure reload to restore correct state
      _loadAffiliates();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAffiliates();
    _generateCode();
    widget.onRegisterCallback?.call(_showAddDialog);
    widget.onRefreshCallback?.call(_loadAffiliates);
  }

  void _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    setState(() => _generatedCode = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join());
  }

  Future<void> _loadAffiliates() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _db.client
          .from('affiliates')
          .select('*, affiliate_referrals(id, commission_amount, is_paid)')
          .or('deleted.is.null,deleted.eq.false')
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() { _affiliates = List<Map<String, dynamic>>.from(res); _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _addAffiliate(String name, String phone, String code) async {
    try {
      await _db.client.from('affiliates').insert({
        'name': name.trim(), 'phone': phone.trim(),
        'code': code.trim().toUpperCase(), 'total_commission': 0, 'paid_commission': 0,
      });
      _loadAffiliates();
      _generateCode();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: kRose));
    }
  }

  Future<void> _deleteAffiliate(String id) async {
    // Remove instantly from local list — no flicker
    setState(() => _affiliates.removeWhere((a) => a['id'] == id));
    widget.onAffiliateDeleted?.call();
    try {
      await _db.client.from('affiliates').update({
        'deleted': true,
        'deleted_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
    } catch (_) {
      // On failure reload to restore correct state
      _loadAffiliates();
    }
  }

  void _showAddDialog() {
    final nameCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();
    final codeCtrl  = TextEditingController(text: _generatedCode);

    showDialog(context: context, useRootNavigator: true, builder: (_) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Affiliate Member', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _kText)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _darkField(nameCtrl, 'Full Name', Icons.person_outline_rounded),
          const SizedBox(height: 12),
          _darkField(phoneCtrl, 'Phone Number', Icons.phone_outlined, keyboard: TextInputType.phone),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _darkField(codeCtrl, 'Affiliate Code', Icons.tag_rounded)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
                final code = List.generate(6, (_) => chars[Random().nextInt(chars.length)]).join();
                codeCtrl.text = code;
                setDlg(() {});
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: kPurple.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.refresh_rounded, color: kPurple, size: 20),
              ),
            ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: _kFaint))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPurple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty || codeCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              _addAffiliate(nameCtrl.text, phoneCtrl.text, codeCtrl.text);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ));
  }

  void _showReferrals(Map<String, dynamic> affiliate) async {
    if (_sheetOpen) return;
    setState(() => _sheetOpen = true);
    try {
      final res = await _db.client
          .from('affiliate_referrals')
          .select('*, proposals(name, cnic, status)')
          .eq('affiliate_id', affiliate['id'])
          .order('created_at', ascending: false);
      if (!mounted) { setState(() => _sheetOpen = false); return; }

      final referrals = List<Map<String, dynamic>>.from(res);
      final paid    = referrals.where((r) => r['is_paid'] as bool? ?? false).fold<int>(0, (s, r) => s + ((r['commission_amount'] as num?)?.toInt() ?? 0));
      final pending = referrals.where((r) => !(r['is_paid'] as bool? ?? false)).fold<int>(0, (s, r) => s + ((r['commission_amount'] as num?)?.toInt() ?? 0));

      bool sortNewest = true;
      Set<String> selected = {};
      bool selecting = false;
      List<Map<String, dynamic>> sorted = List.from(referrals);

      await showModalBottomSheet(
        context: context,
        useRootNavigator: true,
        backgroundColor: _kCard,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => StatefulBuilder(
          builder: (ctx, setSheet) => DraggableScrollableSheet(
            initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.4, expand: false,
            builder: (_, ctrl) => Column(children: [
              SizedBox(height: _S.of(ctx).s(8)),
              Container(width: _S.of(ctx).d(40), height: _S.of(ctx).d(4), decoration: BoxDecoration(color: _kBorder, borderRadius: BorderRadius.circular(_S.of(ctx).s(2)))),
              SizedBox(height: _S.of(ctx).s(12)),

              // ── Header ──
              Padding(
                padding: EdgeInsets.symmetric(horizontal: _S.of(ctx).s(16)),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(affiliate['name'] as String? ?? '', style: TextStyle(fontSize: _S.of(ctx).f(16), fontWeight: FontWeight.w800, color: _kText), overflow: TextOverflow.ellipsis, maxLines: 1),
                    Text('${referrals.length} referrals', style: TextStyle(fontSize: _S.of(ctx).f(12), color: _kSub)),
                  ])),
                  SizedBox(width: _S.of(ctx).s(12)),
                  SizedBox(width: _S.of(ctx).d(80), child: _miniStatBox(ctx, 'Paid', 'Rs $paid', const Color(0xFF2E7D32), isZero: paid == 0)),
                  SizedBox(width: _S.of(ctx).s(8)),
                  SizedBox(width: _S.of(ctx).d(80), child: _miniStatBox(ctx, 'Pending', 'Rs $pending', kRose, isZero: pending == 0)),
                ]),
              ),
              const SizedBox(height: 10),

              // ── Sort bar ──
              SizedBox(height: _S.of(ctx).s(10)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: _S.of(ctx).s(16)),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => setSheet(() {
                      sortNewest = !sortNewest;
                      sorted = sortNewest
                          ? (List.from(referrals)..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String)))
                          : (List.from(referrals)..sort((a, b) => (a['created_at'] as String).compareTo(b['created_at'] as String)));
                    }),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: _S.of(ctx).s(10), vertical: _S.of(ctx).s(5)),
                      decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(_S.of(ctx).s(8))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(sortNewest ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: _S.of(ctx).d(12), color: kPurple),
                        SizedBox(width: _S.of(ctx).s(4)),
                        Text(sortNewest ? 'Newest First' : 'Oldest First', style: TextStyle(fontSize: _S.of(ctx).f(11), fontWeight: FontWeight.w700, color: kPurple)),
                      ]),
                    ),
                  ),
                  const Spacer(),
                  if (selecting)
                    GestureDetector(
                      onTap: () => setSheet(() { selected.clear(); selecting = false; }),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: _S.of(ctx).s(10), vertical: _S.of(ctx).s(5)),
                        decoration: BoxDecoration(color: _kBorder, borderRadius: BorderRadius.circular(_S.of(ctx).s(8))),
                        child: Text('Cancel', style: TextStyle(fontSize: _S.of(ctx).f(11), fontWeight: FontWeight.w700, color: _kSub)),
                      ),
                    ),
                ]),
              ),
              SizedBox(height: _S.of(ctx).s(8)),
              Divider(height: 1, color: _kBorder),

              // ── List ──
              Expanded(
                child: sorted.isEmpty
                  ? Center(child: Text('No referrals yet', style: TextStyle(color: _kSub)))
                  : ListView.separated(
                      controller: ctrl,
                      padding: EdgeInsets.symmetric(horizontal: _S.of(ctx).s(16), vertical: _S.of(ctx).s(12)),
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) => SizedBox(height: _S.of(ctx).s(8)),
                      itemBuilder: (_, i) {
                        final r = sorted[i];
                        final rid = r['id'] as String;
                        final proposal = r['proposals'] as Map?;
                        final isPaid = r['is_paid'] as bool? ?? false;
                        final isSelected = selected.contains(rid);
                        final createdAt = r['created_at'] as String?;
                        final dateLabel = createdAt != null ? _fmtDate(createdAt) : '';
                        final cnic = proposal?['cnic'] as String? ?? 'N/A';

                        return GestureDetector(
                          onLongPress: () => setSheet(() { selecting = true; selected.add(rid); }),
                          onTap: selecting ? () => setSheet(() { isSelected ? selected.remove(rid) : selected.add(rid); }) : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: EdgeInsets.all(_S.of(ctx).s(12)),
                            decoration: BoxDecoration(
                              color: isSelected ? kPurple.withOpacity(0.15) : _kBg,
                              borderRadius: BorderRadius.circular(_S.of(ctx).s(12)),
                              border: Border.all(color: isSelected ? kPurple : _kBorder),
                            ),
                            child: Row(children: [
                              if (selecting)
                                Padding(
                                  padding: EdgeInsets.only(right: _S.of(ctx).s(10)),
                                  child: Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                    color: isSelected ? kPurple : _kFaint, size: 20),
                                ),
                              Container(
                                width: _S.of(ctx).d(36), height: _S.of(ctx).d(36),
                                decoration: BoxDecoration(color: kPurple.withOpacity(0.2), borderRadius: BorderRadius.circular(_S.of(ctx).s(10))),
                                child: Center(child: Text(
                                  (proposal?['name'] ?? '?').substring(0, 1).toUpperCase(),
                                  style: TextStyle(fontSize: _S.of(ctx).f(16), fontWeight: FontWeight.w800, color: kPurple),
                                )),
                              ),
                              SizedBox(width: _S.of(ctx).s(10)),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(proposal?['name'] ?? 'Unknown', style: TextStyle(fontSize: _S.of(ctx).f(13), fontWeight: FontWeight.w700, color: _kText), overflow: TextOverflow.ellipsis, maxLines: 1)),
                                  SizedBox(width: _S.of(ctx).s(6)),
                                  Text(dateLabel, style: TextStyle(fontSize: _S.of(ctx).f(10), color: _kSub)),
                                  SizedBox(width: _S.of(ctx).s(6)),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: _S.of(ctx).s(7), vertical: _S.of(ctx).s(2)),
                                    decoration: BoxDecoration(
                                      color: isPaid ? const Color(0xFF2E7D32).withOpacity(0.2) : kRose.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(_S.of(ctx).s(6)),
                                    ),
                                    child: Text(isPaid ? 'Paid' : 'Pending',
                                      style: TextStyle(fontSize: _S.of(ctx).f(10), fontWeight: FontWeight.w700,
                                        color: isPaid ? const Color(0xFF2E7D32) : kRose)),
                                  ),
                                ]),
                                SizedBox(height: _S.of(ctx).s(3)),
                                Row(children: [
                                  Text('CNIC: $cnic', style: TextStyle(fontSize: _S.of(ctx).f(11), color: _kSub)),
                                  const Spacer(),
                                  Text('Rs ${((r['commission_amount'] ?? 0) as num).toInt()}',
                                    style: TextStyle(fontSize: _S.of(ctx).f(12), fontWeight: FontWeight.w700, color: _kText)),
                                ]),
                              ])),
                            ]),
                          ),
                        );
                      },
                    ),
              ),
              // ── Mark as Paid button ──
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(ctx).padding.bottom + 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selecting && selected.isNotEmpty ? kPurple : (pending > 0 ? kPurple : _kBorder),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: _S.of(ctx).s(14)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_S.of(ctx).s(12))),
                    ),
                    onPressed: (selecting && selected.isEmpty) || (!selecting && pending == 0) ? null : () async {
                      final unpaidSelected = selecting
                          ? sorted.where((r) => selected.contains(r['id'] as String) && !(r['is_paid'] as bool? ?? false)).toList()
                          : sorted.where((r) => !(r['is_paid'] as bool? ?? false)).toList();
                      if (unpaidSelected.isEmpty) return;
                      final totalAmt = unpaidSelected.fold<int>(0, (s, r) => s + ((r['commission_amount'] as num?)?.toInt() ?? 0));
                      final confirm = await showDialog<bool>(
                        context: ctx,
                        builder: (_) => AlertDialog(
                          backgroundColor: _kCard,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Confirm Payment', style: TextStyle(color: _kText, fontWeight: FontWeight.w800)),
                          content: Text("Mark ${unpaidSelected.length} referral(s) as paid? Total: Rs $totalAmt", style: const TextStyle(color: _kSub, fontSize: 13)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: _kFaint))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: kPurple, foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      int paidAmt = 0;
                      for (final r in unpaidSelected) {
                        await _db.client.from('affiliate_referrals').update({'is_paid': true, 'paid_at': DateTime.now().toIso8601String()}).eq('id', r['id'] as String);
                        r['is_paid'] = true;
                        paidAmt += ((r['commission_amount'] as num?)?.toInt() ?? 0);
                      }
                      await _db.client.from('affiliates').update({'paid_commission': paid + paidAmt}).eq('id', affiliate['id'] as String);
                      setSheet(() { selected.clear(); selecting = false; });
                      _loadAffiliates();
                    },
                    child: Text(
                      'Mark as Paid',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: _S.of(ctx).f(14)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _sheetOpen = false);
    }
  }

  String _fmtDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) { return ''; }
  }

  Widget _miniStatBox(BuildContext context, String label, String value, Color color, {bool isZero = false}) {
    final s = _S.of(context);
    final c = isZero ? _kFaint : color;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: s.s(10), vertical: s.s(7)),
      decoration: BoxDecoration(color: _kBorder.withOpacity(0.5), borderRadius: BorderRadius.circular(s.s(10))),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w800, color: c)),
        SizedBox(height: s.s(1)),
        Text(label, style: TextStyle(fontSize: s.f(9.5), color: _kSub)),
      ]),
    );
  }

  Widget _darkField(TextEditingController ctrl, String label, IconData icon, {TextInputType? keyboard}) {
    return TextField(
      controller: ctrl, keyboardType: keyboard,
      style: const TextStyle(fontSize: 14, color: _kText),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(fontSize: 13, color: _kSub),
        prefixIcon: Icon(icon, size: 18, color: _kFaint),
        filled: true, fillColor: _kBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPurple)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  void _confirmDelete(String id) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Move to Trash?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _kText)),
      content: const Text('This will move the affiliate to trash. You can restore them later.', style: TextStyle(fontSize: 13, color: _kSub)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: _kFaint))),
        TextButton(onPressed: () { Navigator.pop(context); _deleteAffiliate(id); },
          child: const Text('Move to Trash', style: TextStyle(color: kRose))),
      ],
    ));
  }

  void _confirmDeleteSelected() {
    final count = _selectedIds.length;
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: _kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Move $count to Trash?', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _kText)),
      content: Text('Move $count affiliate${count != 1 ? 's' : ''} to trash. You can restore them later.', style: const TextStyle(fontSize: 13, color: _kSub)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: _kFaint))),
        TextButton(onPressed: () { Navigator.pop(context); _deleteSelected(); },
          child: const Text('Move to Trash', style: TextStyle(color: kRose, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final totalReferrals = _affiliates.fold<int>(0, (s, a) {
      final list = a['affiliate_referrals'] as List?;
      return s + (list?.length ?? 0);
    });
    final totalPaid = _affiliates.fold<int>(0, (s, a) {
      final list = a['affiliate_referrals'] as List?;
      if (list == null) return s;
      return s + list.where((r) => r['is_paid'] as bool? ?? false).fold<int>(0, (x, r) => x + ((r['commission_amount'] as num?)?.toInt() ?? 0));
    });
    final pendingPayment = _affiliates.fold<int>(0, (s, a) {
      final list = a['affiliate_referrals'] as List?;
      if (list == null) return s;
      return s + list.where((r) => !(r['is_paid'] as bool? ?? false)).fold<int>(0, (x, r) => x + ((r['commission_amount'] as num?)?.toInt() ?? 0));
    });

    return Container(
      color: _kBg,
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(_S.of(context).s(16), _S.of(context).s(16), _S.of(context).s(16), 0),
          child: Column(children: [
            Row(children: [
              _statBox('Total Affiliates', '${_affiliates.length}', kPurple, isZero: _affiliates.isEmpty),
              SizedBox(width: _S.of(context).s(10)),
              _statBox('Total Referrals', '$totalReferrals', kPurple, isZero: totalReferrals == 0),
            ]),
            SizedBox(height: _S.of(context).s(10)),
            Row(children: [
              _statBox('Total Paid', 'Rs $totalPaid', const Color(0xFF2E7D32), isZero: totalPaid == 0),
              SizedBox(width: _S.of(context).s(10)),
              _statBox('Pending Payment', 'Rs $pendingPayment', kRose, isZero: pendingPayment == 0),
            ]),
          ]),
        ),
        Expanded(
          child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPurple))
            : _error != null
              ? _buildError()
              : _affiliates.isEmpty
                ? _buildEmpty()
                : Column(children: [
                    // ── Selection action bar ──
                    if (_selecting) Container(
                      margin: EdgeInsets.fromLTRB(_S.of(context).s(16), _S.of(context).s(12), _S.of(context).s(16), 0),
                      padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(14), vertical: _S.of(context).s(10)),
                      decoration: BoxDecoration(
                        color: kPurple.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(_S.of(context).s(12)),
                        border: Border.all(color: kPurple.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        Icon(Icons.check_circle_rounded, color: kPurple, size: _S.of(context).d(16)),
                        SizedBox(width: _S.of(context).s(8)),
                        Text('${_selectedIds.length} selected', style: TextStyle(color: kPurple, fontSize: _S.of(context).f(13), fontWeight: FontWeight.w700)),
                        const Spacer(),
                        GestureDetector(
                          onTap: _cancelSelect,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(10), vertical: _S.of(context).s(5)),
                            decoration: BoxDecoration(color: _kBorder, borderRadius: BorderRadius.circular(_S.of(context).s(8))),
                            child: Text('Cancel', style: TextStyle(color: _kSub, fontSize: _S.of(context).f(12), fontWeight: FontWeight.w600)),
                          ),
                        ),
                        SizedBox(width: _S.of(context).s(8)),
                        GestureDetector(
                          onTap: _selectedIds.isEmpty ? null : () => _confirmDeleteSelected(),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(10), vertical: _S.of(context).s(5)),
                            decoration: BoxDecoration(
                              color: _selectedIds.isEmpty ? _kBorder : kRose.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(_S.of(context).s(8)),
                              border: Border.all(color: _selectedIds.isEmpty ? Colors.transparent : kRose.withOpacity(0.4)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.delete_outline_rounded, size: _S.of(context).d(14), color: _selectedIds.isEmpty ? _kFaint : kRose),
                              SizedBox(width: _S.of(context).s(4)),
                              Text('Move to Trash', style: TextStyle(color: _selectedIds.isEmpty ? _kFaint : kRose, fontSize: _S.of(context).f(12), fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.all(_S.of(context).s(16)),
                        itemCount: _affiliates.length,
                        separatorBuilder: (_, __) => SizedBox(height: _S.of(context).s(10)),
                        itemBuilder: (_, i) {
                          final id = _affiliates[i]['id'] as String;
                          final isSelected = _selectedIds.contains(id);
                          return _AffiliateCard(
                            affiliate: _affiliates[i],
                            isSelected: isSelected,
                            isSelecting: _selecting,
                            onTap: _selecting ? () => _toggleSelect(id) : () => _showReferrals(_affiliates[i]),
                            onLongPress: () => _enterSelectMode(id),
                            onDelete: () => _confirmDelete(id),
                          );
                        },
                      ),
                    ),
                  ]),
        ),
      ]),
    );
  }

  Widget _statBox(String label, String value, Color color, {bool isZero = false}) {
    final c = isZero ? _kFaint : color;
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: _S.of(context).s(12), horizontal: _S.of(context).s(10)),
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(_S.of(context).s(12)), border: Border.all(color: _kBorder)),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: _S.of(context).f(15), fontWeight: FontWeight.w900, color: c)),
          SizedBox(height: _S.of(context).s(2)),
          Text(label, style: TextStyle(fontSize: _S.of(context).f(10), color: _kSub), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _buildError() {
    final isNoInternet = (_error ?? '').toLowerCase().contains('socket') ||
        (_error ?? '').toLowerCase().contains('connection') ||
        (_error ?? '').toLowerCase().contains('network') ||
        (_error ?? '').toLowerCase().contains('host lookup') ||
        (_error ?? '').toLowerCase().contains('no address');
    return Center(
      child: Builder(builder: (context) {
        final s = _S.of(context);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: s.s(32)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: s.d(52), height: s.d(52),
                decoration: BoxDecoration(
                  color: kPurple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(s.s(14)),
                ),
                child: Icon(
                  isNoInternet ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
                  color: kPurple, size: s.d(24),
                ),
              ),
              SizedBox(height: s.s(12)),
              Text(
                isNoInternet ? 'No Internet Connection' : 'Something Went Wrong',
                style: TextStyle(fontSize: s.f(14), fontWeight: FontWeight.w800, color: _kText),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: s.s(4)),
              Text(
                isNoInternet
                    ? 'Please check your connection and try again.'
                    : 'Could not load affiliates. Please try again.',
                style: TextStyle(fontSize: s.f(12), color: _kSub, height: 1.4),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: s.s(16)),
              GestureDetector(
                onTap: _loadAffiliates,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: s.s(12), vertical: s.s(6)),
                  decoration: BoxDecoration(
                    color: kPurple,
                    borderRadius: BorderRadius.circular(s.s(8)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.refresh_rounded, size: s.d(13), color: Colors.white),
                    SizedBox(width: s.s(5)),
                    Text('Try Again', style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Builder(builder: (context) { final s = _S.of(context); return Container(width: s.d(56), height: s.d(56), decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(16))), child: Icon(Icons.people_outline_rounded, color: kPurple, size: s.d(28))); }),
      Builder(builder: (context) => SizedBox(height: _S.of(context).s(12))),
      Builder(builder: (context) => Text('No affiliates yet', style: TextStyle(fontSize: _S.of(context).f(15), fontWeight: FontWeight.w800, color: _kText))),
      Builder(builder: (context) => SizedBox(height: _S.of(context).s(4))),
      Builder(builder: (context) => Text('Tap + to add your first affiliate', style: TextStyle(fontSize: _S.of(context).f(12), color: _kSub))),
    ]));
  }
}

class _AffiliateCard extends StatelessWidget {
  final Map<String, dynamic> affiliate;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;
  final bool isSelected;
  final bool isSelecting;
  const _AffiliateCard({
    required this.affiliate, required this.onTap, required this.onDelete,
    required this.onLongPress, this.isSelected = false, this.isSelecting = false,
  });

  @override
  Widget build(BuildContext context) {
    final name     = affiliate['name'] ?? '';
    final phone    = affiliate['phone'] ?? '';
    final code     = affiliate['code'] ?? '';
    final refList  = affiliate['affiliate_referrals'] as List?;
    final refCount = refList?.length ?? 0;
    final initial  = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.all(_S.of(context).s(14)),
        decoration: BoxDecoration(
          color: isSelected ? kPurple.withOpacity(0.12) : _kCard,
          borderRadius: BorderRadius.circular(_S.of(context).s(14)),
          border: Border.all(color: isSelected ? kPurple.withOpacity(0.5) : _kBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (isSelecting) ...[
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: isSelected ? kPurple : _kFaint,
              size: _S.of(context).d(20),
            ),
            SizedBox(width: _S.of(context).s(10)),
          ],
          Container(width: _S.of(context).d(36), height: _S.of(context).d(36),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [kPurple.withOpacity(0.8), kPurpleDeep]),
              borderRadius: BorderRadius.circular(_S.of(context).s(10)),
            ),
            child: Center(child: Text(initial, style: TextStyle(fontSize: _S.of(context).f(14), fontWeight: FontWeight.w900, color: Colors.white)))),
          SizedBox(width: _S.of(context).s(12)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: Text(name, style: TextStyle(fontSize: _S.of(context).f(14), fontWeight: FontWeight.w700, color: _kText), overflow: TextOverflow.ellipsis, maxLines: 1)),
              SizedBox(width: _S.of(context).s(6)),
              _chip(context, code, kPurple),
              SizedBox(width: _S.of(context).s(4)),
              _chip(context, 'Referrals $refCount', kAmber),
              if (!isSelecting) ...[
                SizedBox(width: _S.of(context).s(6)),
                GestureDetector(onTap: onDelete, child: Icon(Icons.delete_outline_rounded, size: _S.of(context).d(18), color: _kFaint)),
              ],
            ]),
            SizedBox(height: _S.of(context).s(3)),
            Text(phone, style: TextStyle(fontSize: _S.of(context).f(11), color: _kSub)),
          ])),
        ]),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, Color color) {
    final s = _S.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s.s(7), vertical: s.s(3)),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(6))),
      child: Text(label, style: TextStyle(fontSize: s.f(10), fontWeight: FontWeight.w700, color: color)),
    );
  }
}
