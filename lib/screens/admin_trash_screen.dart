import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../services/admin_service.dart';
import '../services/supabase_service.dart';
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

  String get _title => widget.source == 'orders' ? 'Rejected Proposals' : widget.source == 'affiliates' ? 'Deleted Affiliates' : 'Deleted Users';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Affiliate trash support ───────────────────────────────────────────────
  List<Map<String, dynamic>> _deletedAffiliates = [];
  bool _loadingAffiliates = false;

  @override
  void initState() {
    super.initState();
    if (widget.source == 'affiliates') _loadDeletedAffiliates();
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

  Future<void> _deleteAllAffiliates() async {
    try {
      await _db.client.from('affiliates').delete().eq('deleted', true);
      _loadDeletedAffiliates();
    } catch (_) {}
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
            actions: allDeleted.isNotEmpty ? [
              GestureDetector(
                onTap: () => _confirmDeleteAll(context, () {
                  for (final u in allDeleted) widget.svc.permanentlyDeleteUser(u.id);
                }, allDeleted.length),
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
            ] : null,
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
        actions: _deletedAffiliates.isNotEmpty ? [
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
        ] : null,
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
                          return Container(
                            margin: EdgeInsets.only(bottom: s.s(12)),
                            padding: EdgeInsets.all(s.s(14)),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16132A),
                              borderRadius: BorderRadius.circular(s.s(12)),
                              border: Border.all(color: kPurple.withOpacity(0.25)),
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(a['name'] ?? '', style: TextStyle(color: Colors.white, fontSize: s.f(14), fontWeight: FontWeight.w700)),
                                SizedBox(height: s.s(4)),
                                Text(a['phone'] ?? '', style: TextStyle(color: Colors.white54, fontSize: s.f(12))),
                                Text('Code: ${a["code"] ?? ""}', style: TextStyle(color: Colors.white38, fontSize: s.f(11))),
                              ])),
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                TextButton(
                                  style: TextButton.styleFrom(
                                    minimumSize: Size.zero,
                                    padding: EdgeInsets.symmetric(horizontal: s.s(10), vertical: s.s(4)),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => _restoreAffiliate(a['id']),
                                  child: Text('Restore', style: TextStyle(color: kGreen, fontSize: s.f(12), fontWeight: FontWeight.w700)),
                                ),
                                SizedBox(width: s.s(4)),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    minimumSize: Size.zero,
                                    padding: EdgeInsets.symmetric(horizontal: s.s(10), vertical: s.s(4)),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => _permanentDeleteAffiliate(a['id']),
                                  child: Text('Delete', style: TextStyle(color: kRose, fontSize: s.f(12), fontWeight: FontWeight.w700)),
                                ),
                              ]),
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
    return Container(
      margin: EdgeInsets.only(bottom: s.s(10)),
      padding: EdgeInsets.fromLTRB(s.s(14), s.s(12), s.s(14), s.s(12)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(s.s(16)),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(user.name,
                          style: TextStyle(fontSize: s.f(14), fontWeight: FontWeight.w700,
                              color: Colors.white.withOpacity(0.6))),
                    ),
                  ],
                ),
                SizedBox(height: s.s(2)),
                Text(
                  (user.cnic != null && user.cnic!.isNotEmpty)
                      ? user.cnic!
                      : user.contactPhone,
                  style: TextStyle(fontSize: s.f(11.5), color: Colors.white.withOpacity(0.3)),
                ),
              ],
            ),
          ),
          if (user.deletionReason != null && user.deletionReason!.isNotEmpty) ...[
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
                padding: EdgeInsets.symmetric(horizontal: s.s(10), vertical: s.s(6)),
                decoration: BoxDecoration(
                  color: kPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(s.s(8)),
                  border: Border.all(color: kPurple.withOpacity(0.2)),
                ),
                child: Text('Reason', style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w700, color: kPurple)),
              ),
            ),
            SizedBox(width: s.s(8)),
          ],
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              svc.restoreUser(user.id, user.deletedFrom);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('${user.name} restored'),
                backgroundColor: kGreen,
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.fromLTRB(s.s(16), 0, s.s(16), s.s(72)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(12))),
                duration: const Duration(milliseconds: 1500),
              ));
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: s.s(10), vertical: s.s(6)),
              decoration: BoxDecoration(
                color: kTeal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(s.s(8)),
                border: Border.all(color: kTeal.withOpacity(0.2)),
              ),
              child: Text('Restore',
                  style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w700, color: kTeal)),
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
