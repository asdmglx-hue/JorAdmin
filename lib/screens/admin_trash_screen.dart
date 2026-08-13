import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../services/admin_service.dart';
import '../services/supabase_service.dart';
import '../utils/realtime_refresh.dart';
import '../models/admin_models.dart';
import 'admin_edit_user_screen.dart';

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

class AdminTrashScreen extends StatefulWidget {
  final AdminService svc;
  final String source;
  const AdminTrashScreen({super.key, required this.svc, required this.source});
  @override State<AdminTrashScreen> createState() => _AdminTrashScreenState();
}

class _AdminTrashScreenState extends State<AdminTrashScreen> {
  final _db = SupabaseService.instance;
  String _search = '';
  final _searchCtrl = TextEditingController();
  bool _refreshing = false;

  String get _title => widget.source == 'orders' ? 'Rejected Proposals' : widget.source == 'affiliates' ? 'Deleted Affiliates' : 'Deleted Users';

  AutoRefreshSync? _sync;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _sync?.unsubscribe();
    super.dispose();
  }

  // ── Affiliate trash support ───────────────────────────────────────────────
  List<Map<String, dynamic>> _deletedAffiliates = [];
  bool _loadingAffiliates = false;

  @override
  void initState() {
    super.initState();
    if (widget.source == 'affiliates') {
      _loadDeletedAffiliates();
      // The users/orders view above already auto-refreshes via the
      // ListenableBuilder(listenable: widget.svc) wrapping build() below.
      // The affiliates view reads from local state populated by a direct
      // Supabase query instead, so it needs its own realtime subscription.
      _sync = subscribeAutoRefresh(
        client: _db.client,
        channelName: 'admin-sync-affiliate-trash',
        tables: const ['affiliates'],
        onChange: () { if (mounted) _loadDeletedAffiliates(); },
      );
    }
  }

  Future<void> _doRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    if (widget.source == 'affiliates') {
      await _loadDeletedAffiliates();
    } else {
      await widget.svc.loadData();
    }
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _loadDeletedAffiliates() async {
    setState(() => _loadingAffiliates = true);
    try {
      final res = await _db.client.from('affiliates')
          .select().eq('deleted', true).order('deleted_at', ascending: false);
      if (mounted) setState(() { _deletedAffiliates = List<Map<String,dynamic>>.from(res); _loadingAffiliates = false; });
    } catch (_) { if (mounted) setState(() => _loadingAffiliates = false); }
  }

  Future<void> _restoreAffiliate(String id) async {
    try {
      await _db.client.from('affiliates').update({'deleted': false, 'deleted_at': null}).eq('id', id);
      _loadDeletedAffiliates();
    } catch (_) {}
  }

  Future<void> _permanentDeleteAffiliate(String id) async {
    try {
      await _db.client.from('affiliates').delete().eq('id', id);
      _loadDeletedAffiliates();
    } catch (_) {}
  }

  void _confirmDeleteAffiliate(BuildContext context, Map<String, dynamic> a) {
    final s = _S.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16132A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(18))),
        title: Text('Delete Permanently?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(15))),
        content: Text('This will permanently remove ${a['name'] ?? 'this affiliate'}. Cannot be undone.',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: s.f(13))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: s.f(13))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              HapticFeedback.heavyImpact();
              _permanentDeleteAffiliate(a['id']);
            },
            child: Text('Delete Forever', style: TextStyle(color: kRose, fontWeight: FontWeight.w700, fontSize: s.f(13))),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAllAffiliates() async {
    try {
      await _db.client.from('affiliates').delete().eq('deleted', true);
      _loadDeletedAffiliates();
    } catch (_) {}
  }

  // Deletes every given user one at a time, awaiting each so a failure on
  // one row (e.g. a DB constraint) can't be silently lost — the previous
  // version fired all deletes at once without awaiting or catching errors,
  // so any single failure just left that card behind with no indication
  // why. Continues past failures instead of stopping the whole batch, then
  // reports how many actually succeeded.
  Future<void> _deleteAllUsers(BuildContext context, List<AdminUser> users) async {
    final failed = <String>[];
    for (final u in users) {
      try {
        await widget.svc.permanentlyDeleteUser(u.id);
      } catch (e) {
        failed.add(u.name);
        debugPrint('[AdminTrashScreen] failed to delete ${u.name} (${u.id}): $e');
      }
    }
    if (!context.mounted) return;
    final succeeded = users.length - failed.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed.isEmpty
          ? '$succeeded item${succeeded != 1 ? 's' : ''} deleted'
          : '$succeeded deleted, ${failed.length} failed (${failed.join(', ')})'),
      backgroundColor: failed.isEmpty ? kGreen : kRose,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: failed.isEmpty ? 2 : 5),
    ));
  }

  void _confirmDeleteAll(BuildContext context, VoidCallback onConfirm, int count) {
    final s = _S.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16132A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(18))),
        title: Text('Delete All $count Item${count != 1 ? 's' : ''}?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(15))),
        content: Text('This will permanently remove all $count item${count != 1 ? 's' : ''} from trash. This cannot be undone.',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: s.f(13))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: s.f(13))),
          ),
          TextButton(
            onPressed: () { Navigator.pop(context); HapticFeedback.heavyImpact(); onConfirm(); },
            child: Text('Delete All', style: TextStyle(color: kRose, fontWeight: FontWeight.w700, fontSize: s.f(13))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return ListenableBuilder(
      listenable: widget.svc,
      builder: (_, __) {
        if (widget.source == 'affiliates') return _buildAffiliateTrash(s);

        final allDeleted = widget.svc.users
            .where((u) => u.status == ProposalStatus.deleted && u.deletedFrom == widget.source)
            .toList();
        final q = _search.toLowerCase();
        final numSearch = _search.startsWith('#') ? int.tryParse(_search.substring(1)) : null;
        final items = q.isEmpty ? allDeleted : allDeleted.where((u) =>
            u.name.toLowerCase().contains(q) ||
            (u.cnic ?? '').toLowerCase().contains(q) ||
            (numSearch != null && u.proposalNumber == numSearch)).toList();

        return Scaffold(
          backgroundColor: const Color(0xFF0F0D1A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF16132A),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_title, style: TextStyle(fontSize: s.f(16), fontWeight: FontWeight.w800, color: Colors.white)),
                Text('${allDeleted.length} ${allDeleted.length != 1 ? 'users' : 'user'}',
                    style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.4))),
              ],
            ),
            actions: [
              GestureDetector(
                onTap: _doRefresh,
                child: Container(
                  margin: EdgeInsets.only(right: allDeleted.isNotEmpty ? s.s(8) : s.s(16)),
                  padding: EdgeInsets.all(s.s(6)),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(s.s(8)),
                  ),
                  child: _refreshing
                      ? SizedBox(width: s.d(16), height: s.d(16), child: const CircularProgressIndicator(color: Colors.white54, strokeWidth: 2))
                      : Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18)),
                ),
              ),
              if (allDeleted.isNotEmpty)
                GestureDetector(
                  onTap: () => _confirmDeleteAll(context, () => _deleteAllUsers(context, allDeleted), allDeleted.length),
                  child: Container(
                    margin: EdgeInsets.only(right: s.s(16)),
                    padding: EdgeInsets.symmetric(horizontal: s.s(12), vertical: s.s(6)),
                    decoration: BoxDecoration(
                      color: kRose.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(s.s(8)),
                      border: Border.all(color: kRose.withOpacity(0.3)),
                    ),
                    child: Text('Delete All', style: TextStyle(color: kRose, fontSize: s.f(12), fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: Colors.white.withOpacity(0.07)),
            ),
          ),
          body: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(s.s(16), s.s(12), s.s(16), s.s(4)),
                child: Container(
                  height: s.d(44),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16132A),
                    borderRadius: BorderRadius.circular(s.s(14)),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    style: TextStyle(color: Colors.white, fontSize: s.f(14)),
                    decoration: InputDecoration(
                      hintText: 'Search by name, CNIC or #number...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: s.f(13.5)),
                      prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.3), size: s.d(20)),
                      suffixIcon: _search.isNotEmpty
                          ? GestureDetector(
                              onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                              child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.3), size: s.d(18)),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: s.s(12)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_outline_rounded, size: s.d(52), color: Colors.white.withOpacity(0.12)),
                            SizedBox(height: s.s(12)),
                            Text(_search.isEmpty ? 'Nothing here' : 'No results found',
                                style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.25))),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(s.s(16), s.s(8), s.s(16), s.s(20)),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _TrashCard(user: items[i], svc: widget.svc),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAffiliateTrash(_S s) {
    final q = _search.toLowerCase();
    final items = _deletedAffiliates.where((a) =>
        (a['name'] ?? '').toLowerCase().contains(q) ||
        (a['phone'] ?? '').toLowerCase().contains(q)).toList();
    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16132A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Deleted Affiliates', style: TextStyle(fontSize: s.f(16), fontWeight: FontWeight.w700)),
            Text('${_deletedAffiliates.length} item${_deletedAffiliates.length != 1 ? 's' : ''}',
                style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.4))),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: _doRefresh,
            child: Container(
              margin: EdgeInsets.only(right: _deletedAffiliates.isNotEmpty ? s.s(8) : s.s(16)),
              padding: EdgeInsets.all(s.s(6)),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(s.s(8)),
              ),
              child: _refreshing
                  ? SizedBox(width: s.d(16), height: s.d(16), child: const CircularProgressIndicator(color: Colors.white54, strokeWidth: 2))
                  : Icon(Icons.refresh_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18)),
            ),
          ),
          if (_deletedAffiliates.isNotEmpty)
            GestureDetector(
              onTap: () => _confirmDeleteAll(context, _deleteAllAffiliates, _deletedAffiliates.length),
              child: Container(
                margin: EdgeInsets.only(right: s.s(16)),
                padding: EdgeInsets.symmetric(horizontal: s.s(12), vertical: s.s(6)),
                decoration: BoxDecoration(
                  color: kRose.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(s.s(8)),
                  border: Border.all(color: kRose.withOpacity(0.3)),
                ),
                child: Text('Delete All', style: TextStyle(color: kRose, fontSize: s.f(12), fontWeight: FontWeight.w700)),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white.withOpacity(0.07)),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(s.s(16), s.s(12), s.s(16), s.s(4)),
            child: Container(
              height: s.d(44),
              decoration: BoxDecoration(
                color: const Color(0xFF16132A),
                borderRadius: BorderRadius.circular(s.s(14)),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
                style: TextStyle(color: Colors.white, fontSize: s.f(14)),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: s.f(13.5)),
                  prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.3), size: s.d(20)),
                  suffixIcon: _search.isNotEmpty
                      ? GestureDetector(
                          onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                          child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.3), size: s.d(18)),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: s.s(12)),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loadingAffiliates
                ? const Center(child: CircularProgressIndicator(color: kPurple))
                : items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_outline_rounded, size: s.d(52), color: Colors.white.withOpacity(0.12)),
                            SizedBox(height: s.s(12)),
                            Text(_search.isEmpty ? 'Nothing here' : 'No results found',
                                style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.25))),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(s.s(16), s.s(8), s.s(16), s.s(20)),
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final a = items[i];
                          final name = (a['name'] ?? '').toString();
                          return Container(
                            margin: EdgeInsets.only(bottom: s.s(10)),
                            padding: EdgeInsets.fromLTRB(s.s(14), s.s(12), s.s(14), s.s(12)),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16132A),
                              borderRadius: BorderRadius.circular(s.s(16)),
                              border: Border.all(color: Colors.white.withOpacity(0.06)),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              // ── Identity row: avatar, name/code, delete icon ──
                              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(
                                  width: s.d(42), height: s.d(42),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(s.s(12)),
                                  ),
                                  child: Center(
                                    child: Text(name.isNotEmpty ? name.substring(0, 1) : '?',
                                        style: TextStyle(fontSize: s.f(18), fontWeight: FontWeight.w800,
                                            color: Colors.white.withOpacity(0.3))),
                                  ),
                                ),
                                SizedBox(width: s.s(12)),
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(top: s.s(2)),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(name, style: TextStyle(fontSize: s.f(14.5), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.75)),
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                      SizedBox(height: s.s(4)),
                                      Text((a['code'] ?? '').toString(), style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.35)),
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ]),
                                  ),
                                ),
                                SizedBox(width: s.s(8)),
                                GestureDetector(
                                  onTap: () => _confirmDeleteAffiliate(context, a),
                                  child: Container(
                                    padding: EdgeInsets.all(s.s(7)),
                                    decoration: BoxDecoration(color: kRose.withOpacity(0.08), borderRadius: BorderRadius.circular(s.s(8))),
                                    child: Icon(Icons.delete_forever_rounded, size: s.d(16), color: kRose.withOpacity(0.7)),
                                  ),
                                ),
                              ]),

                              SizedBox(height: s.s(12)),
                              Divider(height: 1, color: Colors.white.withOpacity(0.06)),
                              SizedBox(height: s.s(10)),

                              // ── Action row: full-width Restore ──
                              GestureDetector(
                                onTap: () => _restoreAffiliate(a['id']),
                                child: Container(
                                  width: double.infinity,
                                  alignment: Alignment.center,
                                  padding: EdgeInsets.symmetric(vertical: s.s(9)),
                                  decoration: BoxDecoration(
                                    color: kTeal.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(s.s(10)),
                                    border: Border.all(color: kTeal.withOpacity(0.2)),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.restore_rounded, size: s.d(14), color: kTeal),
                                    SizedBox(width: s.s(6)),
                                    Text('Restore', style: TextStyle(fontSize: s.f(12.5), fontWeight: FontWeight.w700, color: kTeal)),
                                  ]),
                                ),
                              ),
                            ]),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _TrashCard extends StatelessWidget {
  final AdminUser user;
  final AdminService svc;
  const _TrashCard({required this.user, required this.svc});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final hasReason = user.deletionReason != null && user.deletionReason!.isNotEmpty;
    return Container(
      margin: EdgeInsets.only(bottom: s.s(10)),
      padding: EdgeInsets.fromLTRB(s.s(14), s.s(12), s.s(14), s.s(12)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(s.s(16)),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Identity row: avatar, name/CNIC, quick view + delete icons ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: s.d(42), height: s.d(42),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(s.s(12)),
                ),
                child: Center(
                  child: Text(user.name.isNotEmpty ? user.name.substring(0, 1) : '?',
                      style: TextStyle(fontSize: s.f(18), fontWeight: FontWeight.w800,
                          color: Colors.white.withOpacity(0.3))),
                ),
              ),
              SizedBox(width: s.s(12)),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: s.s(2)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.name,
                          style: TextStyle(fontSize: s.f(14.5), fontWeight: FontWeight.w700,
                              color: Colors.white.withOpacity(0.75)),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      SizedBox(height: s.s(4)),
                      Text(
                        (user.cnic != null && user.cnic!.isNotEmpty)
                            ? formatCnicDisplay(user.cnic!)
                            : user.contactPhone,
                        style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.35)),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: s.s(8)),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AdminEditUserScreen(user: user, svc: svc, readOnly: true))),
                child: Container(
                  padding: EdgeInsets.all(s.s(7)),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(8))),
                  child: Icon(Icons.remove_red_eye_outlined, size: s.d(16), color: Colors.white.withOpacity(0.5)),
                ),
              ),
              SizedBox(width: s.s(8)),
              GestureDetector(
                onTap: () => _confirmPermanentDelete(context),
                child: Container(
                  padding: EdgeInsets.all(s.s(7)),
                  decoration: BoxDecoration(color: kRose.withOpacity(0.08), borderRadius: BorderRadius.circular(s.s(8))),
                  child: Icon(Icons.delete_forever_rounded, size: s.d(16), color: kRose.withOpacity(0.7)),
                ),
              ),
            ],
          ),

          SizedBox(height: s.s(12)),
          Divider(height: 1, color: Colors.white.withOpacity(0.06)),
          SizedBox(height: s.s(10)),

          // ── Action row: Reason (if any) + Restore, given room to breathe ──
          Row(
            children: [
              if (hasReason) ...[
                GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF16132A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(16))),
                        title: Text('Deletion Reason', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(15))),
                        content: Text(user.deletionReason!, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: s.f(13))),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text('Close', style: TextStyle(color: kPurple, fontWeight: FontWeight.w700, fontSize: s.f(13))),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(9)),
                    decoration: BoxDecoration(
                      color: kPurple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(s.s(10)),
                      border: Border.all(color: kPurple.withOpacity(0.2)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.info_outline_rounded, size: s.d(14), color: kPurple),
                      SizedBox(width: s.s(6)),
                      Text('Reason', style: TextStyle(fontSize: s.f(12.5), fontWeight: FontWeight.w700, color: kPurple)),
                    ]),
                  ),
                ),
                SizedBox(width: s.s(10)),
              ],
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    svc.restoreUser(user.id, user.deletedFrom);
                  },
                  child: Container(
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(vertical: s.s(9)),
                    decoration: BoxDecoration(
                      color: kTeal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(s.s(10)),
                      border: Border.all(color: kTeal.withOpacity(0.2)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.restore_rounded, size: s.d(14), color: kTeal),
                      SizedBox(width: s.s(6)),
                      Text('Restore', style: TextStyle(fontSize: s.f(12.5), fontWeight: FontWeight.w700, color: kTeal)),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmPermanentDelete(BuildContext context) {
    final s = _S.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16132A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(18))),
        title: Text('Delete Permanently?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(15))),
        content: Text('This will permanently remove ${user.name}. Cannot be undone.',
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: s.f(13))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: s.f(13))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              HapticFeedback.heavyImpact();
              svc.permanentlyDeleteUser(user.id);
            },
            child: Text('Delete Forever',
                style: TextStyle(color: kRose, fontWeight: FontWeight.w700, fontSize: s.f(13))),
          ),
        ],
      ),
    );
  }
}
