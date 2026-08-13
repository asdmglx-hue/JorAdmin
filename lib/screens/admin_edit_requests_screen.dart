// lib/screens/admin/admin_edit_requests_screen.dart
// Shows every profile edit ever made, with the current live diff (each
// field individually revertible via an X icon) and a full chronological
// history of every change and revert.
//
// Edits apply instantly on the user's side — there is no approve/reject
// gate. status is constrained by the DB to exactly 'applied' or 'reverted'
// (see profile_edit_requests_status_check) — no other value is valid.
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

// ── One row from profile_edit_requests, as-is ───────────────────────────────
class EditEvent {
  final String id;
  final Map<String, dynamic> changes;
  final Map<String, dynamic> oldValues;
  final String status; // 'applied' | 'reverted' — only two valid values
  final DateTime submittedAt;
  final DateTime? reviewedAt;

  const EditEvent({
    required this.id, required this.changes, required this.oldValues,
    required this.status, required this.submittedAt, this.reviewedAt,
  });

  factory EditEvent.fromJson(Map<String, dynamic> json) => EditEvent(
    id: json['id'] as String,
    changes: Map<String, dynamic>.from((json['changes'] as Map?) ?? {}),
    oldValues: Map<String, dynamic>.from((json['old_values'] as Map?) ?? {}),
    status: json['status'] as String,
    submittedAt: DateTime.parse(json['submitted_at'] as String),
    reviewedAt: json['reviewed_at'] != null ? DateTime.parse(json['reviewed_at'] as String) : null,
  );
}

// ── One field's change, whatever its current resolution ────────────────────
class FieldChange {
  final String key;
  final dynamic oldValue;
  final dynamic newValue;
  final String resolution; // 'pending' | 'kept' | 'reverted'
  const FieldChange({required this.key, required this.oldValue, required this.newValue, required this.resolution});
}

// ── All edit activity for one profile ───────────────────────────────────────
class EditRequest {
  final String proposalId;
  final String proposalName;
  final String proposalCnic;
  final int proposalNumber;
  final Map<String, dynamic> currentData;
  final List<EditEvent> events; // chronological ascending — full history
  final List<FieldChange> fieldChanges; // every field ever touched, current resolution

  const EditRequest({
    required this.proposalId, required this.proposalName, required this.proposalCnic,
    required this.proposalNumber, required this.currentData, required this.events,
    required this.fieldChanges,
  });

  DateTime get latestEventAt => events.last.submittedAt;

  List<FieldChange> get pendingFields => fieldChanges.where((f) => f.resolution == 'pending').toList();
  bool get hasPending => fieldChanges.any((f) => f.resolution == 'pending');

  /// Builds an EditRequest from all raw rows for one proposal (any order).
  ///
  /// Walks the chronological history to determine each field's CURRENT
  /// resolution. Three kinds of events exist for a given field:
  ///   - a genuine edit ('applied' with oldValue != newValue) → 'pending'
  ///   - a "keep" confirmation ('applied' with oldValue == newValue, written
  ///     when admin taps the tick — a real persisted event, not local-only
  ///     state, so it survives reloads) → 'kept'
  ///   - a revert ('reverted') → 'reverted'
  /// Whichever of these happened LAST for a field is its current state. A
  /// fresh genuine edit after a kept/reverted resolution correctly resets
  /// that field back to 'pending'. The "before" value shown is always
  /// whichever value immediately preceded the current one — e.g. if age
  /// went 56→28→30→45→46→42 across several edits, "before" shows 46 (the
  /// value right before the latest change), not 56 (the deep original).
  factory EditRequest.build({
    required String proposalId,
    required List<Map<String, dynamic>> rows,
    required Map<String, dynamic> proposalMeta,
  }) {
    final events = rows.map((r) => EditEvent.fromJson(r)).toList()
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));

    final Map<String, FieldChange> fieldMap = {};

    for (final e in events) {
      if (e.status == 'applied') {
        for (final k in e.changes.keys) {
          final oldV = e.oldValues[k];
          final newV = e.changes[k];
          if (oldV == newV) {
            // Keep confirmation — field stays at whatever value it already had.
            final prev = fieldMap[k];
            fieldMap[k] = FieldChange(
              key: k,
              oldValue: prev?.oldValue,
              newValue: prev?.newValue ?? newV,
              resolution: 'kept',
            );
          } else {
            fieldMap[k] = FieldChange(key: k, oldValue: oldV, newValue: newV, resolution: 'pending');
          }
        }
      } else if (e.status == 'reverted') {
        for (final k in e.changes.keys) {
          fieldMap[k] = FieldChange(key: k, oldValue: e.oldValues[k], newValue: e.changes[k], resolution: 'reverted');
        }
      }
    }

    return EditRequest(
      proposalId: proposalId,
      proposalName: proposalMeta['name'] as String? ?? 'Unknown',
      proposalCnic: proposalMeta['cnic'] as String? ?? '',
      proposalNumber: proposalMeta['proposal_number'] as int? ?? 0,
      currentData: proposalMeta,
      events: events,
      fieldChanges: _sortedByProfileOrder(fieldMap.values.toList()),
    );
  }
}

// ── One row from profile_reports, joined with the reported profile's
// basic info for display ────────────────────────────────────────────────
class ProfileReport {
  final String id;
  final String proposalId;
  final String proposalName;
  final int proposalNumber;
  final String proposalCity;
  final String? reporterCnic;
  final String reason;
  final String? details;
  final String status; // 'pending' | 'reviewed' | 'dismissed'
  final DateTime createdAt;

  const ProfileReport({
    required this.id, required this.proposalId, required this.proposalName,
    required this.proposalNumber, required this.proposalCity, this.reporterCnic,
    required this.reason, this.details, required this.status, required this.createdAt,
  });

  factory ProfileReport.fromJson(Map<String, dynamic> json) {
    final proposal = json['proposals'] as Map<String, dynamic>?;
    return ProfileReport(
      id: json['id'] as String,
      proposalId: json['reported_proposal_id'] as String,
      proposalName: proposal?['name'] as String? ?? 'Unknown',
      proposalNumber: proposal?['proposal_number'] as int? ?? 0,
      proposalCity: proposal?['city'] as String? ?? '',
      reporterCnic: json['reporter_cnic'] as String?,
      reason: json['reason'] as String,
      details: json['details'] as String?,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
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
  String _search = '';
  final _searchCtrl = TextEditingController();
  RealtimeChannel? _channel;
  // 0 = Review, 1 = Report — CNIC self-service verification requests
  // used to be a third tab here, but that review now happens per-profile
  // from the Edit screen instead (see admin_edit_user_screen.dart), with
  // a red dot on the Users tab's View icon flagging which profiles have
  // a pending submission — see AdminService.pendingVerificationProposalIds.
  int _selectedTab = 0;
  List<ProfileReport> _reports = [];
  bool _reportsLoading = true;
  RealtimeChannel? _reportsChannel;
  // Counts reverts within the CURRENT round of review for each profile —
  // not the same as "how many fields are reverted in this profile's whole
  // history". A field reverted in an earlier, already-closed round (badge
  // already cleared once) shouldn't count toward this round's message.
  // Reset to 0 the moment a round closes (see _maybeNotifyEditsResolved).
  final Map<String, int> _revertedThisRound = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadReports();
    // Auto-refresh whenever a user submits a new edit while this screen is
    // open — otherwise a fresh submission would sit invisible until admin
    // manually hits refresh, since this screen only re-fetches on demand.
    _channel = _supabase
        .channel('profile_edit_requests_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'profile_edit_requests',
          callback: (_) => _load(silent: true),
        )
        .subscribe();
    // Same auto-refresh for new reports coming in while this screen is
    // open, regardless of which tab is currently selected.
    _reportsChannel = _supabase
        .channel('profile_reports_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'profile_reports',
          callback: (_) => _loadReports(silent: true),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _channel?.unsubscribe();
    _reportsChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadReports({bool silent = false}) async {
    if (!silent) setState(() => _reportsLoading = true);
    try {
      final data = await _supabase
          .from('profile_reports')
          .select('*, proposals(name, city, proposal_number)')
          .order('created_at', ascending: false)
          .limit(500);
      final reports = (data as List)
          .map((row) => ProfileReport.fromJson(row as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() { _reports = reports; _reportsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _reportsLoading = false);
    }
  }

  Future<void> _setReportStatus(ProfileReport r, String status) async {
    // Optimistic — update locally first so the tap feels instant, matching
    // the pattern _RequestCard's tick/cross already uses elsewhere in
    // this same screen.
    setState(() {
      _reports = _reports.map((x) => x.id == r.id
          ? ProfileReport(id: x.id, proposalId: x.proposalId, proposalName: x.proposalName,
              proposalNumber: x.proposalNumber, proposalCity: x.proposalCity,
              reporterCnic: x.reporterCnic, reason: x.reason, details: x.details,
              status: status, createdAt: x.createdAt)
          : x).toList();
    });
    try {
      await _supabase.from('profile_reports').update({'status': status}).eq('id', r.id);
    } catch (_) {
      if (mounted) _loadReports(silent: true);
    }
  }

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

  List<ProfileReport> get _filteredReports {
    if (_search.isEmpty) return _reports;
    final q = _search.toLowerCase();
    final numSearch = _search.startsWith('#') ? int.tryParse(_search.substring(1)) : null;
    return _reports.where((r) =>
      r.proposalName.toLowerCase().contains(q) ||
      r.reason.toLowerCase().contains(q) ||
      (numSearch != null && r.proposalNumber == numSearch)
    ).toList();
  }

  Future<void> _load({bool silent = false}) async {
    // silent=true is used for refreshes triggered by an in-place action
    // (tick/cross) or the realtime subscription. Showing the full-screen
    // spinner there would swap the ListView out for a CircularProgressIndicator
    // and back — which fully unmounts every card (not just reorders them),
    // destroying their expanded state regardless of any Key. Only the
    // user-initiated refresh button and the very first load should do that.
    if (!silent) setState(() => _loading = true);
    try {
      // Fetch every edit event ever (both applied + reverted — the only two
      // valid status values) so full history is always available, and the
      // current live diff can be computed client-side.
      final data = await _supabase
          .from('profile_edit_requests')
          .select('*, proposals(name, city, cnic, proposal_number, *)')
          .order('submitted_at', ascending: true)
          .limit(1000);

      final Map<String, List<Map<String, dynamic>>> byProposal = {};
      final Map<String, Map<String, dynamic>> metaByProposal = {};
      for (final row in data as List) {
        final r = row as Map<String, dynamic>;
        final pid = r['proposal_id'] as String;
        byProposal.putIfAbsent(pid, () => []).add(r);
        metaByProposal[pid] = (r['proposals'] as Map<String, dynamic>?) ?? {};
      }

      final built = byProposal.entries.map((entry) => EditRequest.build(
        proposalId: entry.key,
        rows: entry.value,
        proposalMeta: metaByProposal[entry.key] ?? {},
      )).toList()
        ..sort((a, b) => b.latestEventAt.compareTo(a.latestEventAt));

      if (mounted) setState(() { _requests = built; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Call after an action reloads data for a proposal. If that profile now
  /// has zero pending fields AND at least one field was reverted THIS
  /// ROUND (not ever, historically), fires the "Profile Update" push —
  /// this is the moment the red dot / badge for this card would disappear.
  /// Sends the reverted count along so the message correctly says "change"
  /// vs "changes" / "was" vs "were". Resets the round counter either way,
  /// since this round is now closed regardless of the outcome.
  Future<void> _maybeNotifyEditsResolved(String proposalId) async {
    await _load(silent: true);
    if (!mounted) return;
    EditRequest? req;
    for (final r in _requests) {
      if (r.proposalId == proposalId) { req = r; break; }
    }
    if (req == null) return;
    final revertedCount = _revertedThisRound[proposalId] ?? 0;
    if (!req.hasPending) {
      if (revertedCount > 0) {
        _supabase.functions.invoke('notify-status-change', body: {
          'type': 'edit_changes_rejected',
          'proposal_id': proposalId,
          'count': revertedCount,
        }).catchError((_) => null);
      }
      _revertedThisRound.remove(proposalId);
    }
  }

  /// Reverts a single field back to its earliest known original value.
  /// Writes a new 'reverted' event rather than mutating the original
  /// 'applied' rows — keeps history accurate and stays within the DB's
  /// allowed status values.
  Future<void> _revertField(EditRequest req, FieldChange diff) async {
    final confirmed = await _confirm(
      context,
      title: 'Reject this change?',
      body: '${_fieldLabel(diff.key)} will stay as it was for ${req.proposalName} — the submitted change is discarded.',
      confirmLabel: 'Reject',
      confirmColor: _kRose,
    );
    if (confirmed != true) return;

    try {
      // No longer writes anything back to proposals here — a pending
      // field was never applied there in the first place (see
      // update_own_proposal), so there's nothing live to undo. This is
      // purely a bookkeeping event marking the submission as rejected.
      await _supabase.from('profile_edit_requests').insert({
        'proposal_id': req.proposalId,
        'changes': {diff.key: diff.oldValue},
        'old_values': {diff.key: diff.newValue},
        'status': 'reverted',
        // submitted_at intentionally omitted — the DB column defaults to
        // now() (true UTC server time). Setting it client-side via
        // DateTime.now() was the bug: on a Pakistan device that's local
        // time with no UTC conversion, so it got stored 5 hours into the
        // "future" relative to real submissions — which corrupted the
        // chronological ordering the whole resolution algorithm relies on.
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      });
      _revertedThisRound[req.proposalId] = (_revertedThisRound[req.proposalId] ?? 0) + 1;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Rejected ${_fieldLabel(diff.key)} for ${req.proposalName}'),
          backgroundColor: _kRose,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 72),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ));
        await _maybeNotifyEditsResolved(req.proposalId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: _kRose,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 72),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ));
    }
  }

  /// Approves a pending field — this is what actually makes it go live
  /// now (previously it was already live and this was just an
  /// acknowledgment). Writes the value to proposals first, then the same
  /// "keep" confirmation event as before (oldValue == newValue) so the
  /// resolution algorithm correctly reads this field as resolved.
  Future<void> _keepField(EditRequest req, FieldChange field) async {
    try {
      await _supabase.from('proposals')
          .update({field.key: field.newValue}).eq('id', req.proposalId);
      await _supabase.from('profile_edit_requests').insert({
        'proposal_id': req.proposalId,
        'changes': {field.key: field.newValue},
        'old_values': {field.key: field.newValue},
        'status': 'applied',
        // See _revertField for why submitted_at is intentionally omitted.
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Approved ${_fieldLabel(field.key)} for ${req.proposalName} — now live'),
          backgroundColor: _kGreen,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 72),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ));
        await _maybeNotifyEditsResolved(req.proposalId);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      final isNotNullViolation = msg.contains('violates not-null constraint');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isNotNullViolation
            ? "Can't approve ${_fieldLabel(field.key)} — this field can't be left empty. "
                "Edit it manually from the Users screen instead."
            : 'Error: $e'),
        backgroundColor: _kRose,
        behavior: SnackBarBehavior.floating,
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
    final pendingReports = _reports.where((r) => r.status == 'pending').length;
    final pendingReviews = _requests.where((r) => r.hasPending).length;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        elevation: 0,
        title: Text(_selectedTab == 0 ? 'Review Changes' : _selectedTab == 1 ? 'Reported Profiles' : 'CNIC Verification', style: TextStyle(color: Colors.white, fontSize: s.f(17), fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _selectedTab == 0 ? _load : _loadReports,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(s.d(104)),
          child: Column(
            children: [
              // Review / Report toggle — same underlying screen, since
              // both are "things an admin needs to look at and act on"
              // sharing the same header/search chrome, just different
              // content underneath.
              Padding(
                padding: EdgeInsets.fromLTRB(s.s(16), 0, s.s(16), s.s(10)),
                child: Container(
                  height: s.d(40),
                  padding: EdgeInsets.all(s.s(3)),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(s.s(12)),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = 0),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: _selectedTab == 0 ? _kPurple : Colors.transparent,
                            borderRadius: BorderRadius.circular(s.s(9)),
                          ),
                          alignment: Alignment.center,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('Review', style: TextStyle(color: Colors.white, fontSize: s.f(13), fontWeight: FontWeight.w700)),
                            if (pendingReviews > 0) ...[
                              SizedBox(width: s.s(6)),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: s.s(6), vertical: s.s(1)),
                                decoration: BoxDecoration(
                                  color: _selectedTab == 0 ? Colors.white.withOpacity(0.25) : _kPurple,
                                  borderRadius: BorderRadius.circular(s.s(20)),
                                ),
                                child: Text('$pendingReviews', style: TextStyle(color: Colors.white, fontSize: s.f(10.5), fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ]),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = 1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: _selectedTab == 1 ? _kRose : Colors.transparent,
                            borderRadius: BorderRadius.circular(s.s(9)),
                          ),
                          alignment: Alignment.center,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('Report', style: TextStyle(color: Colors.white, fontSize: s.f(13), fontWeight: FontWeight.w700)),
                            if (pendingReports > 0) ...[
                              SizedBox(width: s.s(6)),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: s.s(6), vertical: s.s(1)),
                                decoration: BoxDecoration(
                                  color: _selectedTab == 1 ? Colors.white.withOpacity(0.25) : _kRose,
                                  borderRadius: BorderRadius.circular(s.s(20)),
                                ),
                                child: Text('$pendingReports', style: TextStyle(color: Colors.white, fontSize: s.f(10.5), fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(s.s(16), 0, s.s(16), s.s(10)),
                child: Container(
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
                      hintText: _selectedTab == 0 ? 'Search by name, CNIC or #number...' : _selectedTab == 1 ? 'Search by name, reason or #number...' : 'Search by name or #number...',
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
              ),
            ],
          ),
        ),
      ),
      body: _selectedTab == 0
          ? (_loading
              ? const Center(child: CircularProgressIndicator(color: _kPurple))
              : _filtered.isEmpty
                  ? Center(child: Text('No profile edits yet',
                      style: TextStyle(color: _kInkFaint, fontSize: s.f(13))))
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(s.s(16), s.s(12), s.s(16), s.s(40)),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _RequestCard(
                        // Keyed by proposalId (not list position) — after a
                        // tick/cross, the list reloads and re-sorts by most
                        // recently changed, which can jump this exact card to a
                        // new position. Without this key, Flutter would treat
                        // that as a brand new card and reset _expanded to
                        // false, closing the dropdown right after the action.
                        key: ValueKey(_filtered[i].proposalId),
                        req: _filtered[i], s: s,
                        onRevertField: (diff) => _revertField(_filtered[i], diff),
                        onKeepField: (diff) => _keepField(_filtered[i], diff),
                      ),
                    ))
          : (_reportsLoading
              ? const Center(child: CircularProgressIndicator(color: _kRose))
              : _filteredReports.isEmpty
                  ? Center(child: Text('No reports yet',
                      style: TextStyle(color: _kInkFaint, fontSize: s.f(13))))
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(s.s(16), s.s(12), s.s(16), s.s(40)),
                      itemCount: _filteredReports.length,
                      itemBuilder: (_, i) => _ReportCard(
                        key: ValueKey(_filteredReports[i].id),
                        report: _filteredReports[i],
                        s: s,
                        onSetStatus: (status) => _setReportStatus(_filteredReports[i], status),
                      ),
                    )),
    );
  }
}

// ── Request card ──────────────────────────────────────────────────────────
class _RequestCard extends StatefulWidget {
  final EditRequest req;
  final _S s;
  final Future<void> Function(FieldChange) onRevertField;
  final Future<void> Function(FieldChange) onKeepField;
  const _RequestCard({super.key, required this.req, required this.s, required this.onRevertField, required this.onKeepField});
  @override State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _expanded = false;
  bool _busy = false;

  Future<void> _handleKeep(FieldChange field) async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    await widget.onKeepField(field);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _handleRevert(FieldChange field) async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    await widget.onRevertField(field);
    if (mounted) setState(() => _busy = false);
  }

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
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: s.d(40), height: s.d(40),
                decoration: BoxDecoration(color: _kPurple.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(12))),
                child: Center(child: Text(req.proposalName.isNotEmpty ? req.proposalName[0] : '?',
                    style: TextStyle(color: _kPurple, fontWeight: FontWeight.w800, fontSize: s.f(16)))),
              ),
              if (req.hasPending)
                Positioned(
                  right: -2, top: -2,
                  child: Container(
                    width: s.d(11), height: s.d(11),
                    decoration: BoxDecoration(
                      color: _kRose,
                      shape: BoxShape.circle,
                      border: Border.all(color: _kCard, width: 1.5),
                    ),
                  ),
                ),
            ]),
            SizedBox(width: s.s(10)),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(req.proposalName, style: TextStyle(color: Colors.white, fontSize: s.f(14), fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                ])),
                SizedBox(width: s.s(8)),
                Text('${req.pendingFields.length} pending · ${_timeAgo(req.latestEventAt)}',
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

        // Current changes toggle
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: EdgeInsets.fromLTRB(s.s(14), 0, s.s(14), s.s(10)),
            child: Row(children: [
              Text(req.fieldChanges.isEmpty ? 'No changes' : 'View changes',
                  style: TextStyle(color: _kPurple, fontSize: s.f(12), fontWeight: FontWeight.w700)),
              SizedBox(width: s.s(4)),
              Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: _kPurple, size: s.d(16)),
            ]),
          ),
        ),

        if (_expanded) ...[
          Divider(height: 1, color: Colors.white.withOpacity(0.06)),
          Padding(
            padding: EdgeInsets.all(s.s(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: () {
              final widgets = <Widget>[];
              String? lastSection;
              for (final diff in req.fieldChanges) {
                final section = _kFieldSection[diff.key] ?? 'Other';
                // profile_photo_url has no heading of its own (matches the
                // edit screen, where the photo sits above "Basic
                // Information" with no label). Every other field's
                // section heading is only shown once, right before the
                // first field belonging to it.
                if (diff.key != 'profile_photo_url' && section != lastSection) {
                  widgets.add(Padding(
                    padding: EdgeInsets.only(top: lastSection == null ? 0 : s.s(6), bottom: s.s(8)),
                    child: Text(section.toUpperCase(),
                        style: TextStyle(fontSize: s.f(10), fontWeight: FontWeight.w800, color: _kPurple, letterSpacing: 0.6)),
                  ));
                  lastSection = section;
                } else if (diff.key == 'profile_photo_url') {
                  lastSection = section;
                }

                final isPhoto = diff.key == 'profile_photo_url';
                final isResolved = diff.resolution != 'pending';
                widgets.add(Padding(
                padding: EdgeInsets.only(bottom: s.s(10)),
                child: Opacity(
                  opacity: isResolved ? 0.8 : 1.0,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: s.s(100), child: Text(_fieldLabel(diff.key),
                        style: TextStyle(fontSize: s.f(11.5), color: _kInkFaint))),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (isPhoto) ...[
                        if (diff.oldValue != null && diff.oldValue.toString().isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(bottom: s.s(4)),
                            child: GestureDetector(
                              onTap: () => _showFullPhoto(context, diff.oldValue.toString()),
                              child: Stack(children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(s.s(8)),
                                  child: Image.network(diff.oldValue.toString(), width: s.d(60), height: s.d(60), fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                                ),
                                Positioned.fill(child: Container(
                                  decoration: BoxDecoration(color: _kRose.withOpacity(0.3), borderRadius: BorderRadius.circular(s.s(8))),
                                )),
                              ]),
                            ),
                          ),
                        GestureDetector(
                          onTap: () => _showFullPhoto(context, diff.newValue.toString()),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(s.s(8)),
                            child: Image.network(diff.newValue.toString(), width: s.d(60), height: s.d(60), fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: s.d(60), height: s.d(60),
                                  decoration: BoxDecoration(color: _kGreen.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(8))),
                                  child: Icon(Icons.broken_image_rounded, color: _kGreen, size: s.d(24)),
                                )),
                          ),
                        ),
                      ] else ...[
                        if (diff.oldValue != null)
                          Text(_formatValue(diff.key, diff.oldValue), style: TextStyle(fontSize: s.f(11.5), color: _kRose,
                              decoration: TextDecoration.lineThrough)),
                        Text(_formatValue(diff.key, diff.newValue), style: TextStyle(fontSize: s.f(12), color: _kGreen, fontWeight: FontWeight.w700)),
                      ],
                    ])),
                    if (isResolved)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: s.s(8), vertical: s.s(5)),
                        margin: EdgeInsets.only(left: s.s(8)),
                        decoration: BoxDecoration(
                          color: (diff.resolution == 'kept' ? _kGreen : _kRose).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(s.s(8)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(diff.resolution == 'kept' ? Icons.check_circle_rounded : Icons.undo_rounded,
                              size: s.d(12), color: diff.resolution == 'kept' ? _kGreen : _kRose),
                          SizedBox(width: s.s(4)),
                          Text(diff.resolution == 'kept' ? 'Approved' : 'Rejected',
                              style: TextStyle(fontSize: s.f(10.5), color: diff.resolution == 'kept' ? _kGreen : _kRose, fontWeight: FontWeight.w700)),
                        ]),
                      )
                    else ...[
                      GestureDetector(
                        onTap: _busy ? null : () => _handleKeep(diff),
                        child: Container(
                          width: s.d(26), height: s.d(26),
                          margin: EdgeInsets.only(left: s.s(8)),
                          decoration: BoxDecoration(
                            color: _kGreen.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(s.s(8)),
                          ),
                          child: Icon(Icons.check_rounded, color: _kGreen, size: s.d(15)),
                        ),
                      ),
                      GestureDetector(
                        onTap: _busy ? null : () => _handleRevert(diff),
                        child: Container(
                          width: s.d(26), height: s.d(26),
                          margin: EdgeInsets.only(left: s.s(6)),
                          decoration: BoxDecoration(
                            color: _kRose.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(s.s(8)),
                          ),
                          child: Icon(Icons.close_rounded, color: _kRose, size: s.d(15)),
                        ),
                      ),
                    ],
                  ]),
                ),
                ));
              }
              return widgets;
            }()),
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
    'degree_title_2': 'Degree 2', 'institute_2': 'Institute 2',
    'degree_title_3': 'Degree 3', 'institute_3': 'Institute 3',
    'marital_status': 'Marital Status', 'marriage_number': 'Looking For (Marriage)',
    'has_kids': 'Has Kids', 'boys': 'Sons', 'girls': 'Daughters',
    'open_to_polygamy': 'Open to Polygamy', 'family_type': 'Family Type', 'complexion': 'Complexion',
    'practice_level': 'Religion Practice Level', 'caste': 'Caste', 'sect': 'Sect / Maslak',
    'hijab': 'Wears Hijab', 'beard': 'Has Beard', 'languages': 'Native Language',
    'height_inches': 'Height', 'weight_kg': 'Weight',
    'profile_photo_url': 'Profile Photo',
    'brothers': 'Brothers', 'sisters': 'Sisters', 'has_siblings': 'Has Siblings',
    'father_alive': 'Father', 'mother_alive': 'Mother',
    'father_occupation': 'Father Occupation', 'mother_occupation': 'Mother Occupation',
    'employment_type': 'Employment Type', 'monthly_income': 'Monthly Income',
    'physically_active': 'Lifestyle', 'smokes': 'Smoker',
    'has_disability': 'Disability / Chronic Illness', 'disability_details': 'Disability Details',
    'home_type': 'Home Type', 'location': 'Location (Area)', 'house_size': 'House Size',
    'has_car': 'Car', 'car_name': 'Car Name',
    'has_other_property': 'Other Property', 'other_property': 'Property Type',
    'has_generator': 'Generator', 'has_solar': 'Solar', 'has_servant': 'Servant',
  };
  return labels[key] ?? key;
}

// ── Canonical field order + section headings ────────────────────────────────
// Mirrors edit_profile_screen.dart's exact layout (section-by-section, field
// order within each section) so admin sees changes in the same sequence the
// person actually filled the form in, instead of "whichever field happened
// to be edited first across this profile's whole history" (the old
// insertion-order behavior). Fields not listed here (legacy/unknown keys)
// fall into "Other" at the end rather than disappearing.
const _kFieldOrder = <String>[
  'profile_photo_url',
  // Basic Information
  'name', 'age', 'city', 'country', 'weight_kg', 'height_inches', 'complexion',
  'marital_status', 'marriage_number', 'has_kids', 'boys', 'girls',
  'open_to_polygamy', 'caste', 'sect', 'practice_level', 'hijab', 'beard',
  'languages', 'about', 'looking_for',
  // Family
  'family_type', 'father_alive', 'mother_alive', 'father_occupation', 'mother_occupation',
  'has_siblings', 'brothers', 'sisters',
  // Education & Career
  'education', 'degree_title', 'institute', 'degree_title_2', 'institute_2',
  'degree_title_3', 'institute_3', 'profession', 'employment_type', 'monthly_income',
  // Health & Lifestyle
  'physically_active', 'smokes', 'has_disability', 'disability_details',
  // Property & Assets
  'home_type', 'location', 'house_size', 'has_car', 'car_name',
  'has_other_property', 'other_property',
  // Contact
  'contact_phone', 'contact_phone_2',
];

const _kFieldSection = <String, String>{
  'name': 'Basic Information', 'age': 'Basic Information', 'city': 'Basic Information',
  'country': 'Basic Information', 'weight_kg': 'Basic Information', 'height_inches': 'Basic Information',
  'complexion': 'Basic Information', 'marital_status': 'Basic Information', 'marriage_number': 'Basic Information',
  'has_kids': 'Basic Information', 'boys': 'Basic Information', 'girls': 'Basic Information',
  'open_to_polygamy': 'Basic Information', 'caste': 'Basic Information', 'sect': 'Basic Information',
  'practice_level': 'Basic Information', 'hijab': 'Basic Information', 'beard': 'Basic Information',
  'languages': 'Basic Information', 'about': 'Basic Information', 'looking_for': 'Basic Information',
  'family_type': 'Family', 'father_alive': 'Family', 'mother_alive': 'Family',
  'father_occupation': 'Family', 'mother_occupation': 'Family', 'has_siblings': 'Family',
  'brothers': 'Family', 'sisters': 'Family',
  'education': 'Education & Career', 'degree_title': 'Education & Career', 'institute': 'Education & Career',
  'degree_title_2': 'Education & Career', 'institute_2': 'Education & Career',
  'degree_title_3': 'Education & Career', 'institute_3': 'Education & Career',
  'profession': 'Education & Career', 'employment_type': 'Education & Career', 'monthly_income': 'Education & Career',
  'physically_active': 'Health & Lifestyle', 'smokes': 'Health & Lifestyle',
  'has_disability': 'Health & Lifestyle', 'disability_details': 'Health & Lifestyle',
  'home_type': 'Property & Assets', 'location': 'Property & Assets', 'house_size': 'Property & Assets',
  'has_car': 'Property & Assets', 'car_name': 'Property & Assets',
  'has_other_property': 'Property & Assets', 'other_property': 'Property & Assets',
  'contact_phone': 'Contact', 'contact_phone_2': 'Contact',
};

/// Sorts fields into the same order as the Edit Profile screen, section by
/// section. profile_photo_url always leads (it has no section heading of
/// its own, matching the edit screen). Anything not in _kFieldOrder keeps
/// its relative order and is placed after everything recognized.
List<FieldChange> _sortedByProfileOrder(List<FieldChange> fields) {
  final sorted = List<FieldChange>.from(fields);
  sorted.sort((a, b) {
    final ia = _kFieldOrder.indexOf(a.key);
    final ib = _kFieldOrder.indexOf(b.key);
    final ra = ia == -1 ? _kFieldOrder.length : ia;
    final rb = ib == -1 ? _kFieldOrder.length : ib;
    return ra.compareTo(rb);
  });
  return sorted;
}

// ── Report card ──────────────────────────────────────────────────────────
class _ReportCard extends StatelessWidget {
  final ProfileReport report;
  final _S s;
  final void Function(String status) onSetStatus;
  const _ReportCard({super.key, required this.report, required this.s, required this.onSetStatus});

  Color get _reasonColor {
    switch (report.reason) {
      case 'Fake Profile': return _kRose;
      case 'Inappropriate Content': return _kRose;
      case 'Falsified Information': return _kAmber;
      case 'Spam or Scam': return _kAmber;
      default: return _kInkFaint;
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = report.status != 'pending';
    return Container(
      margin: EdgeInsets.only(bottom: s.s(12)),
      padding: EdgeInsets.all(s.s(14)),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(s.s(14)),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${report.proposalName}  #${report.proposalNumber}',
                  style: TextStyle(color: Colors.white, fontSize: s.f(14), fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(_timeAgo(report.createdAt), style: TextStyle(color: _kInkFaint, fontSize: s.f(11))),
            ],
          ),
          if (report.proposalCity.isNotEmpty) ...[
            SizedBox(height: s.s(2)),
            Text(report.proposalCity, style: TextStyle(color: Colors.white54, fontSize: s.f(12))),
          ],
          SizedBox(height: s.s(10)),
          Row(children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: s.s(9), vertical: s.s(4)),
              decoration: BoxDecoration(color: _reasonColor.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(20))),
              child: Text(report.reason, style: TextStyle(color: _reasonColor, fontSize: s.f(11), fontWeight: FontWeight.w700)),
            ),
            SizedBox(width: s.s(8)),
            Container(
              padding: EdgeInsets.symmetric(horizontal: s.s(9), vertical: s.s(4)),
              decoration: BoxDecoration(
                color: report.status == 'pending' ? _kAmber.withOpacity(0.15)
                    : report.status == 'reviewed' ? _kGreen.withOpacity(0.15)
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(s.s(20)),
              ),
              child: Text(
                report.status[0].toUpperCase() + report.status.substring(1),
                style: TextStyle(
                  color: report.status == 'pending' ? _kAmber : report.status == 'reviewed' ? _kGreen : _kInkFaint,
                  fontSize: s.f(11), fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ]),
          if (report.details != null && report.details!.isNotEmpty) ...[
            SizedBox(height: s.s(10)),
            Text(report.details!, style: TextStyle(color: Colors.white70, fontSize: s.f(12.5), height: 1.4)),
          ],
          if (!resolved) ...[
            SizedBox(height: s.s(12)),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => onSetStatus('dismissed'),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: s.s(9)),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(s.s(10)),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Text('Dismiss', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: s.f(12.5), fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              SizedBox(width: s.s(8)),
              Expanded(
                child: GestureDetector(
                  onTap: () => onSetStatus('reviewed'),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: s.s(9)),
                    decoration: BoxDecoration(color: _kGreen, borderRadius: BorderRadius.circular(s.s(10))),
                    child: Text('Mark Reviewed', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: s.f(12.5), fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

