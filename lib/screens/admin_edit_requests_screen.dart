// lib/screens/admin/admin_edit_requests_screen.dart
// Shows pending profile edit requests for admin to approve or reject.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/theme.dart';

// ── Responsive scale helper ────────────────────────────────────────────────
class _S {
  final double scale;
  const _S(this.scale);
  double f(double v) => v * scale;
  double s(double v) => v * scale;
  double d(double v) => v * scale;
  static _S of(BuildContext c) {
    final w = MediaQuery.of(c).size.width;
    return _S((w / 390.0).clamp(0.72, 1.0));
  }
}

const _kBg      = Color(0xFF0F0D1E);
const _kCard    = Color(0xFF1A1730);
const _kPurple  = Color(0xFF534AB7);
const _kGreen   = Color(0xFF10B981);
const _kRose    = Color(0xFFE11D48);
const _kAmber   = Color(0xFFF59E0B);
const _kInkFaint= Color(0x80FFFFFF);

final _supabase = Supabase.instance.client;

class EditRequest {
  final List<String> ids;       // all request IDs for this user (may be multiple)
  final String proposalId;
  final String proposalName;
  final String proposalCnic;
  final int proposalNumber;
  final Map<String, dynamic> changes;  // merged changes from all requests
  final Map<String, dynamic> oldValues;  // old values at time of submission
  final Map<String, dynamic> currentData;
  final String status;
  final DateTime submittedAt;   // earliest submission time

  // Convenience getter for single-ID callers
  String get id => ids.first;

  const EditRequest({
    required this.ids, required this.proposalId, required this.proposalName,
    required this.proposalCnic, required this.proposalNumber,
    required this.changes, required this.oldValues, required this.currentData, required this.status,
    required this.submittedAt,
  });

  factory EditRequest.fromJson(Map<String, dynamic> json) {
    final proposal = json['proposals'] as Map<String, dynamic>? ?? {};
    return EditRequest(
      ids: [json['id'] as String],
      proposalId: json['proposal_id'] as String,
      proposalName: proposal['name'] as String? ?? 'Unknown',
      proposalCnic: proposal['cnic'] as String? ?? '',
      proposalNumber: proposal['proposal_number'] as int? ?? 0,
      changes: Map<String, dynamic>.from((json['changes'] as Map?) ?? {}),
      oldValues: Map<String, dynamic>.from((json['old_values'] as Map?) ?? {}),
      currentData: Map<String, dynamic>.from(proposal),
      status: json['status'] as String? ?? 'pending',
      submittedAt: DateTime.parse(json['submitted_at'] as String),
    );
  }

  /// Merge another request's changes into this one (later changes win, old values from earliest).
  EditRequest mergeWith(EditRequest other) {
    final merged = Map<String, dynamic>.from(changes)..addAll(other.changes);
    final mergedOld = Map<String, dynamic>.from(other.oldValues)..addAll(oldValues);
    return EditRequest(
      ids: [...ids, ...other.ids],
      proposalId: proposalId,
      proposalName: proposalName,
      proposalCnic: proposalCnic,
      proposalNumber: proposalNumber,
      changes: merged,
      oldValues: mergedOld,
      currentData: currentData,
      status: status,
      submittedAt: submittedAt.isBefore(other.submittedAt) ? submittedAt : other.submittedAt,
    );
  }
}

class AdminEditRequestsScreen extends StatefulWidget {
  const AdminEditRequestsScreen({super.key});
  @override State<AdminEditRequestsScreen> createState() => _AdminEditRequestsScreenState();
}

class _AdminEditRequestsScreenState extends State<AdminEditRequestsScreen> {
  List<EditRequest> _requests = [];
  bool _loading = true;
  String _filter = 'applied';
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  List<EditRequest> get _filtered {
    if (_search.isEmpty) return _requests;
    final q = _search.toLowerCase();
    final numSearch = _search.startsWith('#') ? int.tryParse(_search.substring(1)) : null;
    return _requests.where((r) =>
      r.proposalName.toLowerCase().contains(q) ||
      r.proposalCnic.toLowerCase().contains(q) ||
      (numSearch != null && r.proposalNumber == numSearch)
    ).toList();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _supabase
          .from('profile_edit_requests')
          .select('*, proposals(name, city, cnic, proposal_number, *)')
          .eq('status', _filter)
          .order('submitted_at', ascending: true) // oldest first so later changes win on merge
          .limit(500);

      // Group by proposal_id — merge all change maps per user into one card
      final Map<String, EditRequest> grouped = {};
      for (final row in data as List) {
        final req = EditRequest.fromJson(row as Map<String, dynamic>);
        if (grouped.containsKey(req.proposalId)) {
          grouped[req.proposalId] = grouped[req.proposalId]!.mergeWith(req);
        } else {
          grouped[req.proposalId] = req;
        }
      }

      if (mounted) setState(() {
        // Sort by latest submission (most recent first for display)
        _requests = grouped.values.toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(EditRequest req) async {
    final confirmed = await _confirm(
      context,
      title: 'Approve Changes?',
      body: 'This will update ${req.proposalName}\'s profile with ${req.changes.length} change${req.changes.length > 1 ? 's' : ''}.',
      confirmLabel: 'Approve',
      confirmColor: _kGreen,
    );
    if (confirmed != true) return;

    try {
      // Apply changes to proposals table
      await _supabase.from('proposals').update(req.changes).eq('id', req.proposalId);
      // Mark ALL requests for this user as approved
      await _supabase.from('profile_edit_requests').update({
        'status': 'approved',
        'reviewed_at': DateTime.now().toIso8601String(),
      }).inFilter('id', req.ids);
      // Notify user
      await _supabase.functions.invoke('notify-edit-request', body: {
        'type': 'edit_approved',
        'proposal_id': req.proposalId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Approved — ${req.proposalName}\'s profile updated'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 72),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: _kRose, behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _reject(EditRequest req) async {
    final confirmed = await _confirm(
      context,
      title: 'Reject Changes?',
      body: 'The user will be notified that their changes were not approved.',
      confirmLabel: 'Reject',
      confirmColor: _kRose,
    );
    if (confirmed != true) return;

    try {
      // Mark ALL requests for this user as rejected
      await _supabase.from('profile_edit_requests').update({
        'status': 'rejected',
        'reviewed_at': DateTime.now().toIso8601String(),
      }).inFilter('id', req.ids);
      // Notify user
      await _supabase.functions.invoke('notify-edit-request', body: {
        'type': 'edit_rejected',
        'proposal_id': req.proposalId,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: const Text('Rejected — user notified'),
          backgroundColor: _kRose,
          behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 72),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: _kRose, behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _revert(EditRequest req) async {
    final confirmed = await _confirm(
      context,
      title: 'Revert to Pending?',
      body: 'This will mark the request as pending again for re-review.',
      confirmLabel: 'Revert',
      confirmColor: _kAmber,
    );
    if (confirmed != true) return;
    try {
      await _supabase.from('profile_edit_requests').update({
        'status': 'pending',
        'reviewed_at': null,
      }).inFilter('id', req.ids);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Reverted to pending'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, 72),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: _kRose, behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<bool?> _confirm(BuildContext ctx, {required String title, required String body, required String confirmLabel, required Color confirmColor}) {
    final s = _S.of(ctx);
    return showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: _kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(20))),
        title: Text(title, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: s.f(15))),
        content: Text(body, style: TextStyle(color: _kInkFaint, fontSize: s.f(13), height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: Text('Cancel', style: TextStyle(color: _kInkFaint, fontSize: s.f(13)))),
          TextButton(onPressed: () => Navigator.pop(_, true), child: Text(confirmLabel, style: TextStyle(color: confirmColor, fontWeight: FontWeight.w800, fontSize: s.f(13)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        elevation: 0,
        title: Text('Edit Requests', style: TextStyle(color: Colors.white, fontSize: s.f(17), fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _load,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(s.d(100)),
          child: Padding(
            padding: EdgeInsets.fromLTRB(s.s(16), 0, s.s(16), s.s(10)),
            child: Column(children: [
              Row(children: [
                _FilterChip(label: 'Applied', selected: _filter == 'applied', s: s, onTap: () { setState(() { _filter = 'applied'; _search = ''; _searchCtrl.clear(); }); _load(); }),
                SizedBox(width: s.s(8)),
                _FilterChip(label: 'Reverted', selected: _filter == 'reverted', s: s, onTap: () { setState(() { _filter = 'applied'; _search = ''; _searchCtrl.clear(); }); _load(); }),
                SizedBox(width: s.s(8)),
                _FilterChip(label: 'Rejected', selected: _filter == 'rejected', s: s, onTap: () { setState(() { _filter = 'rejected'; _search = ''; _searchCtrl.clear(); }); _load(); }),
              ]),
              SizedBox(height: s.s(10)),
              Container(
                height: s.d(40),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(s.s(12)),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v),
                  style: TextStyle(color: Colors.white, fontSize: s.f(13)),
                  decoration: InputDecoration(
                    hintText: 'Search by name, CNIC or #number...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: s.f(12.5)),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.35), size: s.d(18)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: s.s(11)),
                    suffixIcon: _search.isNotEmpty
                        ? GestureDetector(
                            onTap: () => setState(() { _search = ''; _searchCtrl.clear(); }),
                            child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.4), size: s.d(16)),
                          )
                        : null,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPurple))
          : _filtered.isEmpty
              ? const SizedBox.shrink()
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(s.s(16), s.s(12), s.s(16), s.s(40)),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _RequestCard(
                    req: _filtered[i], s: s,
                    onApprove: _filter == 'applied' ? () => _revert(_filtered[i]) : null,
                    onReject: null,
                  ),
                ),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final _S s;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.s, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(6)),
      decoration: BoxDecoration(
        color: selected ? _kPurple : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(s.s(20)),
      ),
      child: Text(label, style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w700,
          color: selected ? Colors.white : _kInkFaint)),
    ),
  );
}

// ── Request card ──────────────────────────────────────────────────────────
class _RequestCard extends StatefulWidget {
  final EditRequest req;
  final _S s;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  const _RequestCard({required this.req, required this.s, this.onApprove, this.onReject});
  @override State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final req = widget.req;
    final s = widget.s;

    return Container(
      margin: EdgeInsets.only(bottom: s.s(12)),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(s.s(16)),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: EdgeInsets.all(s.s(14)),
          child: Row(children: [
            Container(
              width: s.d(40), height: s.d(40),
              decoration: BoxDecoration(color: _kPurple.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(12))),
              child: Center(child: Text(req.proposalName.isNotEmpty ? req.proposalName[0] : '?',
                  style: TextStyle(color: _kPurple, fontWeight: FontWeight.w800, fontSize: s.f(16)))),
            ),
            SizedBox(width: s.s(10)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(req.proposalName, style: TextStyle(color: Colors.white, fontSize: s.f(14), fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                  SizedBox(width: s.s(6)),
                  _StatusBadge(status: req.status, s: s),
                ])),
                SizedBox(width: s.s(8)),
                Text('${req.changes.length} change${req.changes.length > 1 ? 's' : ''} · ${_timeAgo(req.submittedAt)}',
                    style: TextStyle(color: _kInkFaint, fontSize: s.f(10))),
              ]),
              SizedBox(height: s.s(2)),
              Row(children: [
                if (req.proposalCnic.isNotEmpty)
                  Text(req.proposalCnic, style: TextStyle(color: _kInkFaint, fontSize: s.f(12))),
                if (req.proposalCnic.isNotEmpty && req.proposalNumber > 0)
                  Text('  ·  ', style: TextStyle(color: _kInkFaint, fontSize: s.f(12))),
                if (req.proposalNumber > 0)
                  Text('#${req.proposalNumber}', style: TextStyle(color: _kInkFaint, fontSize: s.f(12))),
              ]),
            ])),
          ]),
        ),

        // Changes diff
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: EdgeInsets.fromLTRB(s.s(14), 0, s.s(14), s.s(10)),
            child: Row(children: [
              Text('View changes', style: TextStyle(color: _kPurple, fontSize: s.f(12), fontWeight: FontWeight.w700)),
              SizedBox(width: s.s(4)),
              Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: _kPurple, size: s.d(16)),
            ]),
          ),
        ),

        if (_expanded) ...[
          Divider(height: 1, color: Colors.white.withOpacity(0.06)),
          Padding(
            padding: EdgeInsets.all(s.s(14)),
            child: Column(children: req.changes.entries.map((e) {
              // Use stored old_values first (accurate even after approval), fallback to currentData
              final oldVal = req.oldValues.containsKey(e.key) ? req.oldValues[e.key] : req.currentData[e.key];
              final isPhoto = e.key == 'profile_photo_url';
              return Padding(
                padding: EdgeInsets.only(bottom: s.s(8)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: s.s(110), child: Text(_fieldLabel(e.key),
                      style: TextStyle(fontSize: s.f(11.5), color: _kInkFaint))),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (isPhoto) ...[
                      if (oldVal != null && oldVal.toString().isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(bottom: s.s(4)),
                          child: GestureDetector(
                            onTap: () => _showFullPhoto(context, oldVal.toString()),
                            child: Stack(children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(s.s(8)),
                                child: Image.network(oldVal.toString(), width: s.d(60), height: s.d(60), fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                              ),
                              Positioned.fill(child: Container(
                                decoration: BoxDecoration(color: _kRose.withOpacity(0.3), borderRadius: BorderRadius.circular(s.s(8))),
                              )),
                            ]),
                          ),
                        ),
                      GestureDetector(
                        onTap: () => _showFullPhoto(context, e.value.toString()),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(s.s(8)),
                          child: Image.network(e.value.toString(), width: s.d(60), height: s.d(60), fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: s.d(60), height: s.d(60),
                                decoration: BoxDecoration(color: _kGreen.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(8))),
                                child: Icon(Icons.broken_image_rounded, color: _kGreen, size: s.d(24)),
                              )),
                        ),
                      ),
                    ] else ...[
                      if (oldVal != null)
                        Text(_formatValue(e.key, oldVal), style: TextStyle(fontSize: s.f(11.5), color: _kRose,
                            decoration: TextDecoration.lineThrough)),
                      Text(_formatValue(e.key, e.value), style: TextStyle(fontSize: s.f(12), color: _kGreen, fontWeight: FontWeight.w700)),
                    ],
                  ])),
                ]),
              );
            }).toList()),
          ),
        ],

        // Action buttons (only for pending)
        if (widget.onApprove != null || widget.onReject != null) ...[
          Divider(height: 1, color: Colors.white.withOpacity(0.06)),
          Padding(
            padding: EdgeInsets.all(s.s(12)),
            child: Row(children: [
              Expanded(child: GestureDetector(
                onTap: () { HapticFeedback.mediumImpact(); widget.onReject?.call(); },
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: s.s(10)),
                  decoration: BoxDecoration(
                    color: _kRose.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(s.s(12)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.close_rounded, color: _kRose, size: s.d(16)),
                    SizedBox(width: s.s(6)),
                    Text('Reject', style: TextStyle(color: _kRose, fontWeight: FontWeight.w800, fontSize: s.f(13))),
                  ]),
                ),
              )),
              SizedBox(width: s.s(10)),
              Expanded(child: GestureDetector(
                onTap: () { HapticFeedback.mediumImpact(); widget.onApprove?.call(); },
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: s.s(10)),
                  decoration: BoxDecoration(
                    color: _kGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(s.s(12)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.check_rounded, color: _kGreen, size: s.d(16)),
                    SizedBox(width: s.s(6)),
                    Text('Approve', style: TextStyle(color: _kGreen, fontWeight: FontWeight.w800, fontSize: s.f(13))),
                  ]),
                ),
              )),
            ]),
          ),
        ],
      ]),
    );
  }

  void _showFullPhoto(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(children: [
            Center(child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 60)),
            )),
            Positioned(top: 48, right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatValue(String key, dynamic value) {
    if (value == null) return '—';
    // Height: convert inches to feet'inches"
    if (key == 'height_inches') {
      final inches = (value as num).toDouble();
      final ft = inches ~/ 12;
      final inch = (inches % 12).round();
      return "$ft'$inch\"";
    }
    // Weight: append kg
    if (key == 'weight_kg') return '${value} kg';
    // Booleans
    if (value is bool) return value ? 'Yes' : 'No';
    // Lists (languages)
    if (value is List) return value.join(', ');
    return '$value';
  }

  String _fieldLabel(String key) {
    const labels = {
      'name': 'Name', 'age': 'Age', 'city': 'City', 'country': 'Country',
      'contact_phone': 'Phone', 'contact_phone_2': 'Phone 2',
      'about': 'About', 'looking_for': 'Looking For',
      'profession': 'Occupation', 'education': 'Education',
      'degree_title': 'Degree', 'institute': 'Institute',
      'marital_status': 'Marital Status', 'complexion': 'Complexion',
      'practice_level': 'Practice', 'caste': 'Caste', 'sect': 'Sect',
      'height_inches': 'Height', 'weight_kg': 'Weight',
      'profile_photo_url': 'Profile Photo',
      'brothers': 'Brothers', 'sisters': 'Sisters',
      'father_alive': 'Father', 'mother_alive': 'Mother',
      'home_type': 'Home Type', 'has_car': 'Car', 'car_name': 'Car Name',
      'has_generator': 'Generator', 'has_solar': 'Solar', 'has_servant': 'Servant',
      'monthly_income': 'Income', 'employment_type': 'Employment',
    };
    return labels[key] ?? key;
  }
}

// ── Status badge ──────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  final _S s;
  const _StatusBadge({required this.status, required this.s});
  @override
  Widget build(BuildContext context) {
    final color = status == 'approved' ? _kGreen : status == 'rejected' ? _kRose : const Color(0xFFF59E0B);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: s.s(8), vertical: s.s(3)),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(20))),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: s.f(10), fontWeight: FontWeight.w800)),
    );
  }
}
