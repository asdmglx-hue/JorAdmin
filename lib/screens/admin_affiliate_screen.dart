import 'dart:math';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/theme.dart';
import '../services/supabase_service.dart';
import '../utils/realtime_refresh.dart';

const _kBg     = Color(0xFF16132A);
const _kCard   = Color(0xFF1E1A33);
const _kBorder = Color(0xFF2D2847);
const _kText   = Colors.white;
const _kSub    = Color(0xFFB0ADCB);
const _kFaint  = Color(0xFF6B6893);

Widget _darkField(TextEditingController ctrl, String label, IconData icon, {TextInputType? keyboard, List<TextInputFormatter>? inputFormatters}) {
  return TextField(
    controller: ctrl, keyboardType: keyboard, inputFormatters: inputFormatters,
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

Widget _darkFieldObscure(TextEditingController ctrl, String label, bool obscured, VoidCallback onToggle) {
  return TextField(
    controller: ctrl, obscureText: obscured,
    style: const TextStyle(fontSize: 14, color: _kText),
    decoration: InputDecoration(
      labelText: label, labelStyle: const TextStyle(fontSize: 13, color: _kSub),
      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: _kFaint),
      suffixIcon: GestureDetector(
        onTap: onToggle,
        child: Icon(obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: _kFaint),
      ),
      filled: true, fillColor: _kBg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _kBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _kBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPurple)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
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
  AutoRefreshSync? _sync;

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
    _sync = subscribeAutoRefresh(
      client: _db.client,
      channelName: 'admin-sync-affiliates',
      tables: const ['affiliates', 'affiliate_referrals'],
      onChange: () { if (mounted) _loadAffiliates(); },
    );
  }

  @override
  void dispose() {
    _sync?.unsubscribe();
    super.dispose();
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

  Future<void> _addAffiliateSecure({
    required String name,
    required String phone,
    required String password,
    required String code,
    required String address,
    String? city,
    required String timing,
    required Uint8List cnicFrontBytes,
    required Uint8List cnicBackBytes,
  }) async {
    final cnicFrontUrl = await _db.uploadAffiliateCnic(cnicFrontBytes, side: 'front');
    final cnicBackUrl = await _db.uploadAffiliateCnic(cnicBackBytes, side: 'back');
    await _db.client.rpc('affiliate_register_secure', params: {
      'p_name': name.trim(),
      'p_phone': phone.trim(),
      'p_password': password,
      'p_code': code.trim().toUpperCase(),
      'p_support_center_address': address.trim().isEmpty ? null : address.trim(),
      'p_support_center_city': city?.trim().isEmpty == true ? null : city?.trim(),
      'p_timing': timing.trim(),
      'p_cnic_front_url': cnicFrontUrl,
      'p_cnic_back_url': cnicBackUrl,
    });
    _loadAffiliates();
    _generateCode();
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

  void _showAffiliateDetail(Map<String, dynamic> affiliate) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AffiliateDetailSheet(
        affiliate: affiliate,
        onSaved: () => _loadAffiliates(),
      ),
    );
  }

  void _showAddDialog() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddAffiliateSheet(
        initialCode: _generatedCode,
        onRegenerateCode: () {
          const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
          return List.generate(6, (_) => chars[Random().nextInt(chars.length)]).join();
        },
        onSubmit: _addAffiliateSecure,
      ),
    );
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

  void _toggleCenter(String id, bool currentValue) async {
    setState(() {
      final idx = _affiliates.indexWhere((a) => a['id'] == id);
      if (idx != -1) _affiliates[idx]['is_center'] = !currentValue;
    });
    try {
      await _db.client.from('affiliates').update({'is_center': !currentValue}).eq('id', id);
    } catch (_) {
      _loadAffiliates();
    }
  }

  void _showLongPressMenu(Map<String, dynamic> affiliate) {
    HapticFeedback.mediumImpact();
    final id = affiliate['id'] as String;
    final isCenter = affiliate['is_center'] == true;
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: _kBorder, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          ListTile(
            leading: Icon(isCenter ? Icons.storefront_outlined : Icons.storefront_rounded, color: kPurple),
            title: Text(isCenter ? 'Remove from Center' : 'Add as Center', style: const TextStyle(color: _kText, fontWeight: FontWeight.w700)),
            subtitle: Text(
              isCenter ? 'Will no longer be listed on the Help Center page' : 'Will be listed on the public Help Center page',
              style: const TextStyle(color: _kFaint, fontSize: 12),
            ),
            onTap: () { Navigator.pop(sheetCtx); _toggleCenter(id, isCenter); },
          ),
          const SizedBox(height: 8),
        ]),
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
                            onLongPress: () => _showLongPressMenu(_affiliates[i]),
                            onDelete: () => _confirmDelete(id),
                            onView: () => _showAffiliateDetail(_affiliates[i]),
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

// ── Add Affiliate — full registration sheet ─────────────────────────────────
// Collects everything needed for the admin-registration flow: name, phone
// (validated against the same Pakistani-number rule used elsewhere in the
// app — 11 digits starting with 0, or 10 digits without it), a password
// (hashed server-side inside affiliate_register_secure — never sent or
// stored as plaintext beyond this in-memory form), CNIC front/back photos,
// timing, and an optional support center address (the only non-required
// field). Everything else — the actual RPC call and R2 uploads — is
// handled by the onSubmit callback passed in from the parent state.
class _AddAffiliateSheet extends StatefulWidget {
  final String initialCode;
  final String Function() onRegenerateCode;
  final Future<void> Function({
    required String name,
    required String phone,
    required String password,
    required String code,
    required String address,
    String? city,
    required String timing,
    required Uint8List cnicFrontBytes,
    required Uint8List cnicBackBytes,
  }) onSubmit;

  const _AddAffiliateSheet({required this.initialCode, required this.onRegenerateCode, required this.onSubmit});

  @override
  State<_AddAffiliateSheet> createState() => _AddAffiliateSheetState();
}

class _AddAffiliateSheetState extends State<_AddAffiliateSheet> {
  late final TextEditingController _name, _phone, _password, _confirmPassword, _address, _code;
  String? _city;
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;
  Uint8List? _cnicFrontBytes;
  Uint8List? _cnicBackBytes;
  bool _obscurePw = true;
  bool _obscureConfirmPw = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _phone = TextEditingController();
    _password = TextEditingController();
    _confirmPassword = TextEditingController();
    _address = TextEditingController();
    _code = TextEditingController(text: widget.initialCode);
  }

  @override
  void dispose() {
    _name.dispose(); _phone.dispose(); _password.dispose();
    _confirmPassword.dispose(); _address.dispose(); _code.dispose();
    super.dispose();
  }

  Future<void> _pickCnic({required bool isFront}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    setState(() {
      if (isFront) { _cnicFrontBytes = bytes; } else { _cnicBackBytes = bytes; }
    });
  }

  Future<void> _pickTime({required bool isOpen}) async {
    final initial = (isOpen ? _openTime : _closeTime) ?? const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: kPurple, surface: _kCard, onSurface: _kText),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isOpen) { _openTime = picked; } else { _closeTime = picked; }
    });
  }

  String _formatTime(TimeOfDay t) {
    final hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  // Same Pakistani mobile number rule used elsewhere in the app (see
  // submit_proposal_screen.dart): strip non-digits, then require 11 digits
  // if it starts with 0 (e.g. 03001234567) or 10 digits without the
  // leading 0 (e.g. 3001234567).
  String? _phoneError() {
    final digits = _phone.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return 'Phone number is required';
    final required = digits.startsWith('0') ? 11 : 10;
    if (digits.length != required) {
      return 'Enter a valid Pakistani number ($required digits)';
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() => _error = null);

    if (_name.text.trim().isEmpty) { setState(() => _error = 'Name is required'); return; }
    final phoneErr = _phoneError();
    if (phoneErr != null) { setState(() => _error = phoneErr); return; }
    if (_password.text.length < 6) { setState(() => _error = 'Password must be at least 6 characters'); return; }
    if (_password.text != _confirmPassword.text) { setState(() => _error = 'Passwords do not match'); return; }
    if (_openTime == null || _closeTime == null) { setState(() => _error = 'Please select opening and closing time'); return; }
    if (_code.text.trim().isEmpty) { setState(() => _error = 'Affiliate code is required'); return; }
    if (_cnicFrontBytes == null) { setState(() => _error = 'CNIC front photo is required'); return; }
    if (_cnicBackBytes == null) { setState(() => _error = 'CNIC back photo is required'); return; }

    final timingStr = '${_formatTime(_openTime!)} - ${_formatTime(_closeTime!)}';

    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        name: _name.text, phone: _phone.text, password: _password.text, code: _code.text,
        address: _address.text, city: _city, timing: timingStr,
        cnicFrontBytes: _cnicFrontBytes!, cnicBackBytes: _cnicBackBytes!,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _submitting = false; _error = 'Failed to register: $e'; });
    }
  }

  Widget _timeButton({required String label, required TimeOfDay? time, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _kBg, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: time != null ? kPurple.withOpacity(0.5) : _kBorder),
        ),
        child: Row(children: [
          Icon(Icons.access_time_rounded, size: 18, color: _kFaint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              time != null ? _formatTime(time) : label,
              style: TextStyle(fontSize: 14, color: time != null ? _kText : _kSub, fontWeight: time != null ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _cnicPicker({required String label, required Uint8List? bytes, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: _kBg, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bytes != null ? kPurple.withOpacity(0.5) : _kBorder),
        ),
        child: bytes != null
            ? ClipRRect(borderRadius: BorderRadius.circular(11), child: Image.memory(bytes, fit: BoxFit.cover, width: double.infinity))
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_a_photo_outlined, color: _kFaint, size: 22),
                const SizedBox(height: 6),
                Text(label, style: TextStyle(color: _kFaint, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // viewInsets.bottom lifts the sheet above the keyboard while typing;
      // MediaQuery.padding.bottom adds room for the phone's own gesture
      // bar / nav bezel so the submit button isn't sitting underneath it
      // once the keyboard is closed.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: _kCard, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(context).padding.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Add Affiliate Member', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kText))),
              GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.4), size: 22)),
            ]),
            const SizedBox(height: 16),

            _darkField(_name, 'Full Name', Icons.person_outline_rounded),
            const SizedBox(height: 12),
            _darkField(_phone, 'Phone Number', Icons.phone_outlined, keyboard: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)]),
            const SizedBox(height: 12),

            _AffiliateCityPicker(value: _city, onChanged: (v) => setState(() => _city = v)),
            const SizedBox(height: 12),
            _darkField(_address, 'Support Center Address (optional)', Icons.location_on_outlined),
            const SizedBox(height: 12),
            Text('Timing', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _kSub)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _timeButton(label: 'Opens', time: _openTime, onTap: () => _pickTime(isOpen: true))),
              const SizedBox(width: 10),
              Expanded(child: _timeButton(label: 'Closes', time: _closeTime, onTap: () => _pickTime(isOpen: false))),
            ]),
            const SizedBox(height: 12),

            Row(children: [
              Expanded(child: _darkField(_code, 'Affiliate Code', Icons.tag_rounded)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _code.text = widget.onRegenerateCode()),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: kPurple.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.refresh_rounded, color: kPurple, size: 20),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            Text('CNIC Photos', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _kSub)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _cnicPicker(label: 'CNIC Front', bytes: _cnicFrontBytes, onTap: () => _pickCnic(isFront: true))),
              const SizedBox(width: 10),
              Expanded(child: _cnicPicker(label: 'CNIC Back', bytes: _cnicBackBytes, onTap: () => _pickCnic(isFront: false))),
            ]),
            const SizedBox(height: 16),

            _darkFieldObscure(_password, 'Password', _obscurePw, () => setState(() => _obscurePw = !_obscurePw)),
            const SizedBox(height: 12),
            _darkFieldObscure(_confirmPassword, 'Confirm Password', _obscureConfirmPw, () => setState(() => _obscureConfirmPw = !_obscureConfirmPw)),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: kRose, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Register Affiliate', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Affiliate detail/edit sheet ─────────────────────────────────────────────
// Opened from the view (eye) icon on each card. Shows everything captured
// at signup — name, phone, support center address, timing, code, and both
// CNIC photos (tap to view full-screen) — with the core fields editable.
// Saves go straight to the affiliates table via a normal authenticated
// update (unlike registration, this isn't creating a new password/identity,
// so it doesn't need to go through affiliate_register_secure).
class _AffiliateDetailSheet extends StatefulWidget {
  final Map<String, dynamic> affiliate;
  final VoidCallback onSaved;
  const _AffiliateDetailSheet({required this.affiliate, required this.onSaved});

  @override
  State<_AffiliateDetailSheet> createState() => _AffiliateDetailSheetState();
}

class _AffiliateDetailSheetState extends State<_AffiliateDetailSheet> {
  late final TextEditingController _name, _phone, _address;
  String? _city;
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;
  bool _editing = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.affiliate;
    _name = TextEditingController(text: a['name'] ?? '');
    _phone = TextEditingController(text: a['phone'] ?? '');
    _address = TextEditingController(text: a['support_center_address'] ?? '');
    _city = (a['support_center_city'] as String?)?.isNotEmpty == true ? a['support_center_city'] as String : null;
    final parsed = _parseTiming(a['timing'] as String?);
    _openTime = parsed?.$1;
    _closeTime = parsed?.$2;
  }

  @override
  void dispose() {
    _name.dispose(); _phone.dispose(); _address.dispose();
    super.dispose();
  }

  // Parses a "9:00 AM - 6:00 PM" style string (as produced by the
  // registration form) back into two TimeOfDay values for editing. Returns
  // null if the stored value doesn't match that shape (e.g. an older,
  // free-typed entry) — the picker just starts empty in that case rather
  // than guessing.
  (TimeOfDay, TimeOfDay)? _parseTiming(String? raw) {
    if (raw == null) return null;
    final parts = raw.split(' - ');
    if (parts.length != 2) return null;
    final open = _parseOne(parts[0].trim());
    final close = _parseOne(parts[1].trim());
    if (open == null || close == null) return null;
    return (open, close);
  }

  TimeOfDay? _parseOne(String s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false).firstMatch(s.trim());
    if (m == null) return null;
    var hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    final period = m.group(3)!.toUpperCase();
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatTime(TimeOfDay t) {
    final hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  Future<void> _pickTime({required bool isOpen}) async {
    final initial = (isOpen ? _openTime : _closeTime) ?? const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(primary: kPurple, surface: _kCard, onSurface: _kText)),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() { if (isOpen) { _openTime = picked; } else { _closeTime = picked; } });
  }

  String? _phoneError() {
    final digits = _phone.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return 'Phone number is required';
    final required = digits.startsWith('0') ? 11 : 10;
    if (digits.length != required) return 'Enter a valid Pakistani number ($required digits)';
    return null;
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (_name.text.trim().isEmpty) { setState(() => _error = 'Name is required'); return; }
    final phoneErr = _phoneError();
    if (phoneErr != null) { setState(() => _error = phoneErr); return; }
    if (_openTime == null || _closeTime == null) { setState(() => _error = 'Please select opening and closing time'); return; }

    setState(() => _saving = true);
    try {
      await SupabaseService.instance.client.from('affiliates').update({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'support_center_address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'support_center_city': _city,
        'timing': '${_formatTime(_openTime!)} - ${_formatTime(_closeTime!)}',
      }).eq('id', widget.affiliate['id']);
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = 'Failed to save: $e'; });
    }
  }

  void _viewImage(String? url) {
    if (url == null || url.isEmpty) return;
    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
    ));
  }

  Widget _thumb(String label, String? url) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _kSub)),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () => _viewImage(url),
        child: Container(
          height: 90,
          decoration: BoxDecoration(color: _kBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _kBorder)),
          child: url == null || url.isEmpty
              ? Center(child: Icon(Icons.image_not_supported_outlined, color: _kFaint, size: 20))
              : ClipRRect(borderRadius: BorderRadius.circular(11), child: Image.network(url, fit: BoxFit.cover, width: double.infinity)),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.affiliate;
    final code = a['code'] ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: _kCard, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(context).padding.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Affiliate Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kText))),
              if (!_editing)
                GestureDetector(
                  onTap: () => setState(() => _editing = true),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.edit_outlined, size: 16, color: kPurple),
                    const SizedBox(width: 4),
                    Text('Edit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kPurple)),
                  ]),
                ),
              const SizedBox(width: 14),
              GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.4), size: 22)),
            ]),
            const SizedBox(height: 4),
            Text('Code: $code', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kPurple)),
            const SizedBox(height: 18),

            if (_editing) ...[
              _darkField(_name, 'Full Name', Icons.person_outline_rounded),
              const SizedBox(height: 12),
              _darkField(_phone, 'Phone Number', Icons.phone_outlined, keyboard: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)]),
              const SizedBox(height: 12),
              _AffiliateCityPicker(value: _city, onChanged: (v) => setState(() => _city = v)),
              const SizedBox(height: 12),
              _darkField(_address, 'Support Center Address (optional)', Icons.location_on_outlined),
              const SizedBox(height: 12),
              Text('Timing', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _kSub)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _timeButton(label: 'Opens', time: _openTime, onTap: () => _pickTime(isOpen: true))),
                const SizedBox(width: 10),
                Expanded(child: _timeButton(label: 'Closes', time: _closeTime, onTap: () => _pickTime(isOpen: false))),
              ]),
            ] else ...[
              _detailRow(Icons.person_outline_rounded, 'Name', a['name'] ?? '—'),
              _detailRow(Icons.phone_outlined, 'Phone', a['phone'] ?? '—'),
              _detailRow(Icons.location_city_outlined, 'City', (a['support_center_city'] as String?)?.isNotEmpty == true ? a['support_center_city'] : 'Not provided'),
              _detailRow(Icons.location_on_outlined, 'Support Center', (a['support_center_address'] as String?)?.isNotEmpty == true ? a['support_center_address'] : 'Not provided'),
              _detailRow(Icons.access_time_rounded, 'Timing', (a['timing'] as String?)?.isNotEmpty == true ? a['timing'] : 'Not provided'),
            ],

            const SizedBox(height: 18),
            Text('CNIC Photos', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _kSub)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _thumb('CNIC Front', a['cnic_front_url'] as String?)),
              const SizedBox(width: 10),
              Expanded(child: _thumb('CNIC Back', a['cnic_back_url'] as String?)),
            ]),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: kRose, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],

            if (_editing) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: _kFaint),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: _kFaint)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14, color: _kText, fontWeight: FontWeight.w600)),
        ])),
      ]),
    );
  }

  Widget _timeButton({required String label, required TimeOfDay? time, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: _kBg, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: time != null ? kPurple.withOpacity(0.5) : _kBorder),
        ),
        child: Row(children: [
          Icon(Icons.access_time_rounded, size: 18, color: _kFaint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              time != null ? _formatTime(time) : label,
              style: TextStyle(fontSize: 14, color: time != null ? _kText : _kSub, fontWeight: time != null ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AffiliateCard extends StatelessWidget {
  final Map<String, dynamic> affiliate;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;
  final VoidCallback onView;
  final bool isSelected;
  final bool isSelecting;
  const _AffiliateCard({
    required this.affiliate, required this.onTap, required this.onDelete,
    required this.onLongPress, required this.onView, this.isSelected = false, this.isSelecting = false,
  });

  @override
  Widget build(BuildContext context) {
    final name     = affiliate['name'] ?? '';
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
              if (!isSelecting) ...[
                GestureDetector(onTap: onView, child: Icon(Icons.visibility_outlined, size: _S.of(context).d(18), color: kPurple)),
                SizedBox(width: _S.of(context).s(8)),
                if (affiliate['is_center'] == true) ...[
                  Icon(Icons.storefront_rounded, size: _S.of(context).d(18), color: kPurple),
                  SizedBox(width: _S.of(context).s(8)),
                ],
                GestureDetector(onTap: onDelete, child: Icon(Icons.delete_outline_rounded, size: _S.of(context).d(18), color: _kFaint)),
                SizedBox(width: _S.of(context).s(8)),
              ],
              _chip(context, 'Referrals $refCount', kAmber),
            ]),
            SizedBox(height: _S.of(context).s(3)),
            Text('Code: $code', style: TextStyle(fontSize: _S.of(context).f(11), fontWeight: FontWeight.w700, color: kPurple)),
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

// ── City picker for support center location — same city list and UI
// pattern used in admin_add_user_screen.dart's own city picker, so a
// support center's city is chosen from the exact same list as everywhere
// else in the app, not typed freely (which the website's Help Center
// sort-by-location feature depends on matching exactly). ──────────────
class _AffiliateCityPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _AffiliateCityPicker({required this.value, required this.onChanged});

  void _open(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _AffiliateCitySheet(
        selected: value,
        onSelect: (v) { onChanged(v); Navigator.pop(context); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final hasValue = value != null && value!.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('City', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
      SizedBox(height: s.s(5)),
      GestureDetector(
        onTap: () => _open(context),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(13)),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(10)), border: Border.all(color: Colors.white.withOpacity(0.1))),
          child: Row(children: [
            Expanded(child: Text(hasValue ? value! : 'Select city',
              style: TextStyle(fontSize: s.f(13.5), color: hasValue ? Colors.white : Colors.white38, fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400))),
            Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: s.d(22)),
          ]),
        ),
      ),
    ]);
  }
}
class _AffiliateCitySheet extends StatefulWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _AffiliateCitySheet({required this.selected, required this.onSelect});
  @override
  State<_AffiliateCitySheet> createState() => _AffiliateCitySheetState();
}

class _AffiliateCitySheetState extends State<_AffiliateCitySheet> {
  String _query = '';
  final _ctrl = TextEditingController();

  Map<String, List<String>> get _filtered {
    if (_query.isEmpty) return kCitiesGrouped;
    final q = _query.toLowerCase();
    final result = <String, List<String>>{};
    for (final entry in kCitiesGrouped.entries) {
      final matches = entry.value.where((v) => v.toLowerCase().contains(q)).toList();
      if (matches.isNotEmpty) result[entry.key] = matches;
    }
    return result;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final filtered = _filtered;
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(color: Color(0xFF0F0D1A), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        SizedBox(height: s.s(10)),
        Container(width: s.d(40), height: s.d(4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(2)))),
        Padding(
          padding: EdgeInsets.fromLTRB(s.s(20), s.s(14), s.s(20), 0),
          child: Row(children: [
            Text('Select City', style: TextStyle(fontSize: s.f(17), fontWeight: FontWeight.w800, color: Colors.white)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(fontSize: s.f(13), color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w600))),
          ]),
        ),
        SizedBox(height: s.s(12)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: s.s(16)),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(2)),
            decoration: BoxDecoration(color: const Color(0xFF16132A), borderRadius: BorderRadius.circular(s.s(14)), border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: Row(children: [
              Icon(Icons.search_rounded, size: s.d(20), color: Colors.white.withOpacity(0.3)),
              SizedBox(width: s.s(8)),
              Expanded(child: TextField(
                controller: _ctrl,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(fontSize: s.f(14), color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search city...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: s.f(14)),
                  border: InputBorder.none, isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: s.s(12)),
                ),
              )),
              if (_query.isNotEmpty)
                GestureDetector(onTap: () { _ctrl.clear(); setState(() => _query = ''); }, child: Icon(Icons.close_rounded, size: s.d(18), color: Colors.white.withOpacity(0.3))),
            ]),
          ),
        ),
        SizedBox(height: s.s(8)),
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text('No cities found', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: s.f(14))))
              : ListView(
                  padding: EdgeInsets.fromLTRB(s.s(16), s.s(4), s.s(16), s.s(24)),
                  children: [
                    for (final entry in filtered.entries) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(s.s(4), s.s(12), s.s(4), s.s(6)),
                        child: Text(entry.key, style: TextStyle(fontSize: s.f(11), fontWeight: FontWeight.w700, color: kPurple.withOpacity(0.8), letterSpacing: 0.5)),
                      ),
                      ...entry.value.map((city) {
                        final isSel = city == widget.selected;
                        return GestureDetector(
                          onTap: () => widget.onSelect(city),
                          child: Container(
                            margin: EdgeInsets.only(bottom: s.s(4)),
                            padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(12)),
                            decoration: BoxDecoration(
                              color: isSel ? kPurple.withOpacity(0.15) : const Color(0xFF16132A),
                              borderRadius: BorderRadius.circular(s.s(12)),
                              border: Border.all(color: isSel ? kPurple.withOpacity(0.4) : Colors.white.withOpacity(0.06)),
                            ),
                            child: Row(children: [
                              Expanded(child: Text(city, style: TextStyle(fontSize: s.f(14), color: isSel ? kPurple : Colors.white.withOpacity(0.85), fontWeight: isSel ? FontWeight.w700 : FontWeight.w400))),
                              if (isSel) Icon(Icons.check_rounded, color: kPurple, size: s.d(18)),
                            ]),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
        ),
      ]),
    );
  }
}

// ── Multiline field with a live character counter ──────────────────────────
