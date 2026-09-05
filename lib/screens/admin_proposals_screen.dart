import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../services/admin_service.dart';
import '../services/supabase_service.dart';
import '../models/admin_models.dart';
import '../models/admin_permissions.dart';
import 'admin_edit_user_screen.dart';
import 'admin_trash_screen.dart';

// Verification section — every one of these 5 documents must be uploaded
// (via the edit profile screen's Verification section) before a proposal
// can be approved. Returns the human-readable labels of whatever's still
// missing, so the block message can name exactly what's needed.
List<String> _missingVerificationDocs(AdminUser user, Map<String, String> settings) {
  // Uses verify_now_*_compulsory settings (same keys used by the Verified chip
  // and the approve logic in supabase_service.dart) — NOT the old require_*
  // keys which are all false and never trigger anything.
  final missing = <String>[];
  final cnicShown      = settings['verify_now_candidate_cnic'] != 'false';
  final cnicCompulsory = settings['verify_now_candidate_cnic_compulsory'] != 'false';
  final degreeShown      = settings['verify_now_latest_degree'] != 'false';
  final degreeCompulsory = settings['verify_now_latest_degree_compulsory'] == 'true';
  final parentsShown      = settings['verify_now_parents_cnic'] != 'false';
  final parentsCompulsory = settings['verify_now_parents_cnic_compulsory'] != 'false';

  if (cnicShown && cnicCompulsory) {
    if (user.cnicFront == null || user.cnicFront!.isEmpty) missing.add('CNIC Front');
    if (user.cnicBack  == null || user.cnicBack!.isEmpty)  missing.add('CNIC Back');
  }
  if (degreeShown && degreeCompulsory) {
    if (user.educationDocument == null || user.educationDocument!.isEmpty) missing.add('Education Document');
  }
  if (parentsShown && parentsCompulsory) {
    if (user.guardianCnicFront == null || user.guardianCnicFront!.isEmpty) missing.add('Parent / Guardian CNIC Front');
    if (user.guardianCnicBack  == null || user.guardianCnicBack!.isEmpty)  missing.add('Parent / Guardian CNIC Back');
  }
  return missing;
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

class AdminProposalsScreen extends StatefulWidget {
  final AdminService svc;
  const AdminProposalsScreen({super.key, required this.svc});
  @override State<AdminProposalsScreen> createState() => _AdminProposalsScreenState();
}

class _AdminProposalsScreenState extends State<AdminProposalsScreen> {
  int _tab = 0; // 0=Pending, 1=Approved, 2=Archived
  bool _show30DaysOnly = false;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleArchive(AdminUser u) async {
    final archive = !u.isOrderArchived;
    final s = _S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF1E1A33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(20))),
        child: Padding(
          padding: EdgeInsets.all(s.s(24)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: s.d(56), height: s.d(56),
              decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(16))),
              child: Center(
                child: CustomPaint(size: Size(s.d(26), s.d(26)), painter: _ArchiveIconPainter(kPurple)),
              ),
            ),
            SizedBox(height: s.s(16)),
            Text(archive ? 'Archive Order?' : 'Unarchive Order?',
                style: TextStyle(fontSize: s.f(17), fontWeight: FontWeight.w800, color: Colors.white)),
            SizedBox(height: s.s(8)),
            Text(
              archive
                ? 'Order will move to Archived tab. It returns to Pending automatically if the user submits new documents or payment.'
                : 'Order will move back to Pending tab.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: s.f(13), color: Colors.white60, height: 1.5),
            ),
            SizedBox(height: s.s(24)),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => Navigator.pop(context, false),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: s.s(13)),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(s.s(12)),
                  ),
                  child: Text('Cancel', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: s.f(14), fontWeight: FontWeight.w700, color: Colors.white60)),
                ),
              )),
              SizedBox(width: s.s(12)),
              Expanded(child: GestureDetector(
                onTap: () => Navigator.pop(context, true),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: s.s(13)),
                  decoration: BoxDecoration(
                    color: kPurple,
                    borderRadius: BorderRadius.circular(s.s(12)),
                  ),
                  child: Text(archive ? 'Archive' : 'Unarchive', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: s.f(14), fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              )),
            ]),
          ]),
        ),
      ),
    );
    if (confirmed != true) return;
    await widget.svc.setOrderArchived(u.id, archive);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(archive ? 'Order archived' : 'Order unarchived'),
        backgroundColor: kPurple,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.svc,
      builder: (_, __) {
        final q = _search.toLowerCase();
        final allPending  = widget.svc.users.where((u) => u.status == ProposalStatus.pending && !u.isOrderArchived).toList();
        final allApproved = widget.svc.users.where((u) => (u.status == ProposalStatus.approved || u.status == ProposalStatus.active)).toList();
        final allArchived = widget.svc.users.where((u) => u.status == ProposalStatus.pending && u.isOrderArchived).toList();
        final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
        final archivedFiltered = _show30DaysOnly
            ? allArchived.where((u) => u.archivedAt != null && u.archivedAt!.isBefore(thirtyDaysAgo)).toList()
            : allArchived;
        final numSearch = _search.startsWith('#') ? int.tryParse(_search.substring(1)) : int.tryParse(_search);
        final sourceList = _tab == 0 ? allPending : _tab == 1 ? allApproved : archivedFiltered;
        final list = sourceList.where((u) =>
          q.isEmpty ||
          u.name.toLowerCase().contains(q) ||
          u.city.toLowerCase().contains(q) ||
          u.contactPhone.contains(_search) ||
          (u.cnic != null && u.cnic!.contains(_search)) ||
          (numSearch != null && u.proposalNumber == numSearch)
        ).toList();

        final canEdit = AdminPerms.i.canEdit(AdminPageKeys.orders);

        Widget tabBtn(String label, int idx) => Expanded(child: GestureDetector(
          onTap: () => setState(() => _tab = idx),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(vertical: _S.of(context).s(9)),
            decoration: BoxDecoration(
              color: _tab == idx ? kPurple : Colors.transparent,
              borderRadius: BorderRadius.circular(_S.of(context).s(10)),
              border: Border.all(color: _tab == idx ? kPurple : Colors.white.withOpacity(0.1)),
            ),
            child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: _S.of(context).f(12), fontWeight: FontWeight.w700,
                color: _tab == idx ? Colors.white : Colors.white38)),
          ),
        ));

        return Column(
          children: [
            const ViewOnlyBanner(pageKey: AdminPageKeys.orders),
            Padding(
              padding: EdgeInsets.fromLTRB(_S.of(context).s(16), _S.of(context).s(12), _S.of(context).s(16), 0),
              child: Column(
                children: [
                  Row(children: [
                    tabBtn('Pending (${allPending.length})', 0),
                    SizedBox(width: _S.of(context).s(6)),
                    tabBtn('Archived (${allArchived.length})', 2),
                    SizedBox(width: _S.of(context).s(6)),
                    tabBtn('Approved (${allApproved.length})', 1),
                  ]),
                  SizedBox(height: _S.of(context).s(10)),
                  Container(
                    height: _S.of(context).d(42),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16132A),
                      borderRadius: BorderRadius.circular(_S.of(context).s(12)),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _search = v),
                      style: TextStyle(color: Colors.white, fontSize: _S.of(context).f(13.5)),
                      decoration: InputDecoration(
                        hintText: 'Search by name, city, phone, CNIC or #number...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: _S.of(context).f(13)),
                        prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.3), size: _S.of(context).d(18)),
                        suffixIcon: _search.isNotEmpty
                            ? GestureDetector(
                                onTap: () { _searchCtrl.clear(); setState(() => _search = ''); },
                                child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.3), size: _S.of(context).d(16)),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: _S.of(context).s(11)),
                      ),
                    ),
                  ),
                  if (_tab == 2) ...[
                    Padding(
                      padding: EdgeInsets.only(top: _S.of(context).s(8)),
                      child: Row(children: [
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _show30DaysOnly = !_show30DaysOnly),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(10), vertical: _S.of(context).s(5)),
                            decoration: BoxDecoration(
                              color: _show30DaysOnly ? kPurple : Colors.white.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(_S.of(context).s(8)),
                              border: Border.all(color: _show30DaysOnly ? kPurple : Colors.white.withOpacity(0.1)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.schedule_rounded, size: _S.of(context).d(12),
                                  color: _show30DaysOnly ? Colors.white : Colors.white38),
                              SizedBox(width: _S.of(context).s(4)),
                              Text('30+ days', style: TextStyle(
                                  fontSize: _S.of(context).f(11), fontWeight: FontWeight.w700,
                                  color: _show30DaysOnly ? Colors.white : Colors.white38)),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ],

                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                ? Center(child: Text(
                    _search.isNotEmpty ? 'No results found'
                      : _tab == 2 ? 'No archived orders'
                      : _tab == 1 ? 'No approved proposals'
                      : 'No pending proposals',
                    style: TextStyle(fontSize: _S.of(context).f(13), color: Colors.white.withOpacity(0.3)),
                  ))
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(_S.of(context).s(16), _S.of(context).s(12), _S.of(context).s(16), _S.of(context).s(20)),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final u = list[i];
                      if (_tab == 1) {
                        return _ApprovedCard(
                          user: u,
                          svc: widget.svc,
                          onView: () async {
                            await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => AdminEditUserScreen(user: u, svc: widget.svc, readOnly: true)));
                            widget.svc.notifyListeners();
                          },
                          onEdit: () async {
                            await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => AdminEditUserScreen(user: u, svc: widget.svc, readOnly: !canEdit)));
                            widget.svc.notifyListeners();
                          },
                        );
                      }
                      return GestureDetector(
                        onLongPress: () => _toggleArchive(u),
                        child: _PendingCard(
                          user: u,
                          svc: widget.svc,
                          isArchived: u.isOrderArchived,
                          onEdit: () async {
                            await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => AdminEditUserScreen(user: u, svc: widget.svc, readOnly: !canEdit)));
                            widget.svc.notifyListeners();
                          },
                        ),
                      );
                    },
                  ),
            ),
          ],
        );
      },
    );
  }
}

// ── Section Header ─────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _SectionHeader({required this.title, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: TextStyle(fontSize: _S.of(context).f(15), fontWeight: FontWeight.w700, color: Colors.white)),
        SizedBox(width: _S.of(context).s(8)),
        Container(
          padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(8), vertical: _S.of(context).s(2)),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(_S.of(context).s(10)),
          ),
          child: Text(count.toString(), style: TextStyle(fontSize: _S.of(context).f(11), fontWeight: FontWeight.w700, color: color)),
        ),
      ],
    );
  }
}

// ── Pending Review Card ────────────────────────────────────────────────────────
class _ApprovedCard extends StatelessWidget {
  final AdminUser user;
  final AdminService svc;
  final VoidCallback onView;
  final VoidCallback onEdit;
  const _ApprovedCard({required this.user, required this.svc, required this.onView, required this.onEdit});

  String _timeAgo(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    final diff = DateTime.now().difference(local);
    final mins = diff.inMinutes.abs();
    final hours = diff.inHours.abs();
    final days = diff.inDays.abs();
    if (mins < 1) return 'just now';
    if (mins < 60) return '${mins}m ago';
    if (hours < 24) return '${hours}h ago';
    if (days < 30) return '${days}d ago';
    final months = (days / 30).floor();
    if (months < 12) return '${months}mo ago';
    final years = (days / 365).floor();
    return '${years}y ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: _S.of(context).s(10)),
      padding: EdgeInsets.all(_S.of(context).s(14)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(_S.of(context).s(16)),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniAvatar(user: user),
              SizedBox(width: _S.of(context).s(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(user.name,
                            style: TextStyle(fontSize: _S.of(context).f(14), fontWeight: FontWeight.w700, color: Colors.white),
                            overflow: TextOverflow.ellipsis),
                      ),
                      SizedBox(width: _S.of(context).s(6)),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(7), vertical: _S.of(context).s(2)),
                        decoration: BoxDecoration(
                          color: kGreen.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(_S.of(context).s(7)),
                        ),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shopping_cart_rounded, size: _S.of(context).d(10), color: kGreen),
                              SizedBox(width: _S.of(context).s(3)),
                              Text('Approved',
                                  style: TextStyle(fontSize: _S.of(context).f(10), fontWeight: FontWeight.w700, color: kGreen)),
                            ],
                          ),
                      ),
                      if (user.adminNotes == 'AI_IMPORTED') ...[ 
                        SizedBox(width: _S.of(context).s(4)),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(6), vertical: _S.of(context).s(2)),
                          decoration: BoxDecoration(
                            color: kPurple.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(_S.of(context).s(7)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome, size: _S.of(context).d(9), color: kPurple),
                              SizedBox(width: _S.of(context).s(3)),
                              Text('AI', style: TextStyle(fontSize: _S.of(context).f(10), fontWeight: FontWeight.w700, color: kPurple)),
                            ],
                          ),
                        ),
                      ],
                    ]),
                    SizedBox(height: _S.of(context).s(2)),

                  ],
                ),
              ),
              Builder(builder: (ctx) => GestureDetector(
                onTap: onView,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (user.proposalNumber != null) ...[
                    Text('#${user.proposalNumber}',
                      style: TextStyle(fontSize: _S.of(context).f(11), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.4))),
                    SizedBox(width: _S.of(context).s(5)),
                  ],
                  Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: _S.of(context).d(28), height: _S.of(context).d(28),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(_S.of(context).s(8)),
                      ),
                      child: Icon(Icons.remove_red_eye_outlined,
                          size: _S.of(context).d(16), color: Colors.white.withOpacity(0.5)),
                    ),
                    if (() {
                        // Show red dot if any uploaded doc is still pending review
                        final hasAnyDoc = (user.cnicFront?.isNotEmpty ?? false) ||
                            (user.cnicBack?.isNotEmpty ?? false) ||
                            (user.educationDocument?.isNotEmpty ?? false) ||
                            (user.guardianCnicFront?.isNotEmpty ?? false) ||
                            (user.guardianCnicBack?.isNotEmpty ?? false);
                        if (!hasAnyDoc) return false;
                        final dv = user.docVerification;
                        // Check if any uploaded doc is still pending
                        final checks = <MapEntry<String?, String>>[
                          MapEntry(user.cnicFront, 'cnic_front'),
                          MapEntry(user.cnicBack, 'cnic_back'),
                          MapEntry(user.educationDocument, 'education_document'),
                          MapEntry(user.guardianCnicFront, 'guardian_cnic_front'),
                          MapEntry(user.guardianCnicBack, 'guardian_cnic_back'),
                        ];
                        return checks.any((e) =>
                          (e.key?.isNotEmpty ?? false) &&
                          (dv[e.value] ?? 'pending') == 'pending');
                      }())
                      Positioned(
                        top: -2, right: -2,
                        child: Container(
                          width: _S.of(context).d(10), height: _S.of(context).d(10),
                          decoration: BoxDecoration(
                            color: kRose,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF16132A), width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                ]),
              )),
            ],
          ),
          SizedBox(height: _S.of(context).s(12)),
          if (user.cnic != null && user.cnic!.isNotEmpty)
            _DetailRow(icon: Icons.credit_card_rounded, label: formatCnicDisplay(user.cnic!)),
          _DetailRow(icon: Icons.phone_rounded, label: user.contactPhone +
              (user.contactPerson != null && user.contactPerson!.isNotEmpty ? '  ·  ${user.contactPerson}' : '')),
          _DetailRow(
            icon: Icons.calendar_today_rounded,
            label: 'Approved ${_timeAgo(user.subscriptionStart ?? user.postedAt)}'
                '${user.submissionSource == 'android' ? ' · Android App' : user.submissionSource == 'website' ? ' · Website' : ''}',
          ),
          SizedBox(height: _S.of(context).s(12)),
          _ActBtn(
            label: 'Edit Profile',
            icon: Icons.edit_rounded,
            color: kPurple,
            onTap: onEdit,
          ),
        ],
      ),
    );
  }
}
class _PendingCard extends StatelessWidget {
  final AdminUser user;
  final AdminService svc;
  final VoidCallback onEdit;
  final bool isArchived;
  const _PendingCard({required this.user, required this.svc, required this.onEdit, this.isArchived = false});

  String _expiryDate() {
    final expiry = DateTime.now().add(const Duration(days: 90));
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${expiry.day} ${months[expiry.month - 1]} ${expiry.year}';
  }

  String _timeAgo(DateTime d) {
    final local = d.isUtc ? d.toLocal() : d;
    final diff = DateTime.now().difference(local);
    final mins = diff.inMinutes.abs();
    final hours = diff.inHours.abs();
    final days = diff.inDays.abs();
    if (mins < 1) return 'just now';
    if (mins < 60) return '${mins}m ago';
    if (hours < 24) return '${hours}h ago';
    if (days < 30) return '${days}d ago';
    final months = (days / 30).floor();
    if (months < 12) return '${months}mo ago';
    final years = (days / 365).floor();
    return '${years}y ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: _S.of(context).s(10)),
      padding: EdgeInsets.all(_S.of(context).s(14)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(_S.of(context).s(16)),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + status inline
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniAvatar(user: user),
              SizedBox(width: _S.of(context).s(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name,
                            style: TextStyle(fontSize: _S.of(context).f(14), fontWeight: FontWeight.w700, color: Colors.white),
                            overflow: TextOverflow.ellipsis),
                        SizedBox(height: _S.of(context).s(5)),
                        Wrap(spacing: _S.of(context).s(5), runSpacing: _S.of(context).s(4), children: [
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(7), vertical: _S.of(context).s(2)),
                            decoration: BoxDecoration(color: kAmber.withOpacity(0.12), borderRadius: BorderRadius.circular(_S.of(context).s(7))),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.shopping_cart_rounded, size: _S.of(context).d(10), color: kAmber),
                              SizedBox(width: _S.of(context).s(3)),
                              Text('Pending', style: TextStyle(fontSize: _S.of(context).f(10), fontWeight: FontWeight.w700, color: kAmber)),
                            ]),
                          ),
                          Builder(builder: (context) {
                            final isPaid = user.subscriptionStatus == SubscriptionStatus.active;
                            final isRefunded = user.subscriptionStatus == SubscriptionStatus.refunded;
                            final hasValidProof = (user.paymentProofUrl?.isNotEmpty ?? false) &&
                                user.paymentProofStatus != 'rejected';
                            final showGreen = isPaid || hasValidProof;
                            final Color tagColor = isRefunded ? kRose : showGreen ? kGreen : kRose;
                            final IconData tagIcon = isRefunded ? Icons.replay_rounded
                                : showGreen ? Icons.attach_money
                                : Icons.money_off_csred;
                            final String tagLabel = isRefunded ? 'Refunded' : showGreen ? 'Paid' : 'Unpaid';
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(7), vertical: _S.of(context).s(2)),
                              decoration: BoxDecoration(color: tagColor.withOpacity(0.15), borderRadius: BorderRadius.circular(_S.of(context).s(7))),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                isRefunded
                                  ? Icon(tagIcon, size: _S.of(context).d(10), color: tagColor)
                                  : CustomPaint(size: Size(_S.of(context).d(10), _S.of(context).d(10)), painter: _CoinIconPainter(tagColor)),
                                SizedBox(width: _S.of(context).s(3)),
                                Text(tagLabel, style: TextStyle(fontSize: _S.of(context).f(10), fontWeight: FontWeight.w700, color: tagColor)),
                              ]),
                            );
                          }),
                          if (user.adminNotes == 'AI_IMPORTED')
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(6), vertical: _S.of(context).s(2)),
                              decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(_S.of(context).s(7))),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.auto_awesome, size: _S.of(context).d(9), color: kPurple),
                                SizedBox(width: _S.of(context).s(3)),
                                Text('AI', style: TextStyle(fontSize: _S.of(context).f(10), fontWeight: FontWeight.w700, color: kPurple)),
                              ]),
                            ),
                          if (isArchived)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(6), vertical: _S.of(context).s(2)),
                              decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(_S.of(context).s(7))),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                CustomPaint(size: Size(_S.of(context).d(9), _S.of(context).d(9)), painter: _ArchiveIconPainter(kPurple)),
                                SizedBox(width: _S.of(context).s(3)),
                                Text(
                                  user.archivedAt != null
                                    ? '${DateTime.now().difference(user.archivedAt!).inDays}d archived'
                                    : 'Archived',
                                  style: TextStyle(fontSize: _S.of(context).f(10), fontWeight: FontWeight.w700, color: kPurple)),
                              ]),
                            ),
                        ]),
                      ],
                    ),
                    SizedBox(height: _S.of(context).s(2)),

                  ],
                ),
              ),
              Builder(builder: (ctx) => GestureDetector(
                onTap: () => Navigator.push(ctx, MaterialPageRoute(
                  builder: (_) => AdminEditUserScreen(user: user, svc: svc, readOnly: true))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (user.proposalNumber != null) ...[
                    Text('#${user.proposalNumber}',
                      style: TextStyle(fontSize: _S.of(context).f(11), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.4))),
                    SizedBox(width: _S.of(context).s(5)),
                  ],
                  Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: _S.of(context).d(28), height: _S.of(context).d(28),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(_S.of(context).s(8)),
                      ),
                      child: Icon(Icons.remove_red_eye_outlined,
                          size: _S.of(context).d(16), color: Colors.white.withOpacity(0.5)),
                    ),
                    if (() {
                        // Show red dot if any uploaded doc is still pending review
                        final hasAnyDoc = (user.cnicFront?.isNotEmpty ?? false) ||
                            (user.cnicBack?.isNotEmpty ?? false) ||
                            (user.educationDocument?.isNotEmpty ?? false) ||
                            (user.guardianCnicFront?.isNotEmpty ?? false) ||
                            (user.guardianCnicBack?.isNotEmpty ?? false);
                        if (!hasAnyDoc) return false;
                        final dv = user.docVerification;
                        // Check if any uploaded doc is still pending
                        final checks = <MapEntry<String?, String>>[
                          MapEntry(user.cnicFront, 'cnic_front'),
                          MapEntry(user.cnicBack, 'cnic_back'),
                          MapEntry(user.educationDocument, 'education_document'),
                          MapEntry(user.guardianCnicFront, 'guardian_cnic_front'),
                          MapEntry(user.guardianCnicBack, 'guardian_cnic_back'),
                        ];
                        return checks.any((e) =>
                          (e.key?.isNotEmpty ?? false) &&
                          (dv[e.value] ?? 'pending') == 'pending');
                      }())
                      Positioned(
                        top: -2, right: -2,
                        child: Container(
                          width: _S.of(context).d(10), height: _S.of(context).d(10),
                          decoration: BoxDecoration(
                            color: kRose,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF16132A), width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                ]),
              )),
            ],
          ),
          SizedBox(height: _S.of(context).s(12)),
          if (user.cnic != null && user.cnic!.isNotEmpty)
            _DetailRow(icon: Icons.credit_card_rounded, label: formatCnicDisplay(user.cnic!)),
          _DetailRow(icon: Icons.phone_rounded, label: user.contactPhone +
              (user.contactPerson != null && user.contactPerson!.isNotEmpty ? '  ·  ${user.contactPerson}' : '')),
          _DetailRow(
            icon: Icons.calendar_today_rounded,
            label: 'Submitted ${_timeAgo(user.postedAt)}'
                '${user.submissionSource == 'android' ? ' via Android App' : user.submissionSource == 'website' ? ' via Website' : ''}',
          ),
          if (user.appliedCouponCode != null && user.appliedCouponCode!.isNotEmpty) ...[
            SizedBox(height: _S.of(context).s(4)),
            Container(
              padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(8), vertical: _S.of(context).s(4)),
              decoration: BoxDecoration(
                color: kAmber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(_S.of(context).s(7)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.local_offer_rounded, size: _S.of(context).d(12), color: kAmber),
                SizedBox(width: _S.of(context).s(5)),
                Text('Coupon: ${user.appliedCouponCode}', style: TextStyle(fontSize: _S.of(context).f(11), fontWeight: FontWeight.w700, color: kAmber)),
              ]),
            ),
          ],
          SizedBox(height: _S.of(context).s(12)),
          if (AdminPerms.i.canEdit(AdminPageKeys.orders)) Row(
            children: [
              Expanded(child: _ActBtn(
                label: 'Approve', icon: Icons.check_rounded, color: kGreen,
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  // Load verification requirements from app_settings
                  final settings = await SupabaseService.instance.fetchAppSettings();
                  final missingDocs = _missingVerificationDocs(user, settings);
                  if (missingDocs.isNotEmpty) {
                    final approveAnyway = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: const Color(0xFF16132A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_S.of(context).s(20))),
                        title: Row(children: [
                          Icon(Icons.warning_amber_rounded, color: kAmber, size: _S.of(context).d(20)),
                          SizedBox(width: _S.of(context).s(8)),
                          const Text('Verification Incomplete', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                        ]),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Missing: ${missingDocs.join(', ')}.',
                              style: TextStyle(color: kAmber, fontSize: _S.of(context).f(13), fontWeight: FontWeight.w700, height: 1.5),
                            ),
                            SizedBox(height: _S.of(context).s(10)),
                            Text(
                              'Approving without verification documents will make this profile visible in the feed but contacts will stay locked until the user submits and you approve the missing documents.',
                              style: TextStyle(color: Colors.white70, fontSize: _S.of(context).f(13), height: 1.55),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context, true),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(16), vertical: _S.of(context).s(10)),
                              decoration: BoxDecoration(color: kAmber, borderRadius: BorderRadius.circular(_S.of(context).s(10))),
                              child: const Text('Approve Anyway', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (approveAnyway != true) return;
                    // Admin already confirmed intent via "Approve Anyway" —
                    // skip the payment confirmation dialog and approve directly.
                    svc.approveProposal(user.id);
                    return;
                  }
                  // AI imported proposals: skip payment dialog, approve with 0 amount
                  if (user.adminNotes == 'AI_IMPORTED') {
                    svc.approveAiProposal(user.id);
                    return;
                  }
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      backgroundColor: const Color(0xFF16132A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_S.of(context).s(20))),
                      title: const Text('Confirm Approval', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'I hereby confirm that all details have been checked and the payment has been received.',
                            style: TextStyle(color: Colors.white70, fontSize: _S.of(context).f(13.5), height: 1.55),
                          ),
                          if (user.appliedCouponCode != null && user.appliedCouponCode!.isNotEmpty) ...[
                            SizedBox(height: _S.of(context).s(12)),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(10), vertical: _S.of(context).s(8)),
                              decoration: BoxDecoration(
                                color: kAmber.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(_S.of(context).s(8)),
                              ),
                              child: Row(children: [
                                Icon(Icons.local_offer_rounded, size: _S.of(context).d(14), color: kAmber),
                                SizedBox(width: _S.of(context).s(6)),
                                Expanded(child: Text(
                                  'Coupon "${user.appliedCouponCode}" will be validated and applied automatically if it\'s still valid.',
                                  style: TextStyle(fontSize: _S.of(context).f(11.5), color: kAmber, fontWeight: FontWeight.w600),
                                )),
                              ]),
                            ),
                          ],
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
                        GestureDetector(
                          onTap: () { Navigator.pop(context); svc.approveProposal(user.id); },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(16), vertical: _S.of(context).s(10)),
                            decoration: BoxDecoration(color: kGreen, borderRadius: BorderRadius.circular(_S.of(context).s(10))),
                            child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )),
              SizedBox(width: _S.of(context).s(8)),
              Expanded(child: _ActBtn(
                label: 'Edit', icon: Icons.edit_rounded, color: kPurple, onTap: onEdit,
              )),
              SizedBox(width: _S.of(context).s(8)),
              Expanded(child: _ActBtn(
                label: 'Reject', icon: Icons.close_rounded, color: kRose,
                onTap: () { HapticFeedback.heavyImpact(); svc.deleteUser(user.id, from: 'orders'); },
              )),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Featured Token Card ────────────────────────────────────────────────────────
class _MiniAvatar extends StatelessWidget {
  final AdminUser user;
  const _MiniAvatar({required this.user});

  void _showFullScreen(BuildContext context) {
    final photoUrl = user.profilePhoto;
    if (photoUrl == null || photoUrl.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(_),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.profilePhoto;
    final initial = user.name.isNotEmpty ? user.name.substring(0, 1) : '?';
    final s = _S.of(context);
    final fallback = Center(child: Text(initial, style: TextStyle(fontSize: s.f(18), fontWeight: FontWeight.w800, color: Colors.white)));
    return GestureDetector(
      onTap: () => _showFullScreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(s.s(11)),
        child: Container(
          width: s.d(40), height: s.d(40),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: user.gender.trim().toLowerCase() == 'female'
                  ? [kRose.withOpacity(0.7), kRose]
                  : [kPurple.withOpacity(0.7), kPurpleDeep],
            ),
            borderRadius: BorderRadius.circular(s.s(11)),
          ),
          child: photoUrl != null && photoUrl.isNotEmpty
              ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover, errorWidget: (_, __, ___) => fallback)
              : fallback,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int maxLines;
  const _DetailRow({required this.icon, required this.label, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: _S.of(context).s(5)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: _S.of(context).d(14), color: Colors.white.withOpacity(0.3)),
          SizedBox(width: _S.of(context).s(6)),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: _S.of(context).f(12.5), color: Colors.white.withOpacity(0.55)),
                maxLines: maxLines, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _ActBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActBtn({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: _S.of(context).d(36),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(_S.of(context).s(10)),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: _S.of(context).d(14)),
            SizedBox(width: _S.of(context).s(4)),
            Text(label, style: TextStyle(fontSize: _S.of(context).f(12), fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Archive icon painter (from SVG path) ─────────────────────────────────────
class _ArchiveIconPainter extends CustomPainter {
  final Color color;
  _ArchiveIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final scale = size.width / 16.0;
    canvas.scale(scale, scale);
    final path = Path();
    // Outer box top
    path.moveTo(13.5, 0);
    path.lineTo(2.5, 0);
    path.cubicTo(1.12, 0, 0, 1.12, 0, 2.5);
    path.lineTo(0, 13.5);
    path.cubicTo(0, 14.88, 1.12, 16, 2.5, 16);
    path.lineTo(13.5, 16);
    path.cubicTo(14.88, 16, 16, 14.88, 16, 13.5);
    path.lineTo(16, 2.5);
    path.cubicTo(16, 1.12, 14.88, 0, 13.5, 0);
    path.close();
    // Inner cutout (subpath for the tab notch)
    path.moveTo(2.5, 1);
    path.lineTo(13.5, 1);
    path.cubicTo(14.33, 1, 15, 1.67, 15, 2.5);
    path.lineTo(15, 3);
    path.lineTo(11.5, 3);
    path.cubicTo(10.67, 3, 10, 3.67, 10, 4.5);
    path.cubicTo(10, 4.78, 9.78, 5, 9.5, 5);
    path.lineTo(6.5, 5);
    path.cubicTo(6.22, 5, 6, 4.78, 6, 4.5);
    path.cubicTo(6, 3.67, 5.33, 3, 4.5, 3);
    path.lineTo(1, 3);
    path.lineTo(1, 2.5);
    path.cubicTo(1, 1.67, 1.67, 1, 2.5, 1);
    path.close();
    // Bottom box
    path.moveTo(13.5, 15);
    path.lineTo(2.5, 15);
    path.cubicTo(1.67, 15, 1, 14.33, 1, 13.5);
    path.lineTo(1, 4);
    path.lineTo(4.5, 4);
    path.cubicTo(4.78, 4, 5, 4.22, 5, 4.5);
    path.cubicTo(5, 5.33, 5.67, 6, 6.5, 6);
    path.lineTo(9.5, 6);
    path.cubicTo(10.33, 6, 11, 5.33, 11, 4.5);
    path.cubicTo(11, 4.22, 11.22, 4, 11.5, 4);
    path.lineTo(15, 4);
    path.lineTo(15, 13.5);
    path.cubicTo(15, 14.33, 14.33, 15, 13.5, 15);
    path.close();
    // Down arrow
    path.moveTo(11.35, 9.15);
    path.cubicTo(11.54, 9.34, 11.54, 9.66, 11.35, 9.85);
    path.lineTo(8.35, 12.85);
    path.cubicTo(8.3, 12.9, 8.24, 12.94, 8.19, 12.96);
    path.cubicTo(8.07, 13.01, 7.93, 13.01, 7.81, 12.96);
    path.cubicTo(7.76, 12.94, 7.7, 12.9, 7.65, 12.85);
    path.lineTo(4.65, 9.85);
    path.cubicTo(4.46, 9.66, 4.46, 9.34, 4.65, 9.15);
    path.cubicTo(4.84, 8.96, 5.16, 8.96, 5.35, 9.15);
    path.lineTo(7.5, 11.29);
    path.lineTo(7.5, 8.5);
    path.cubicTo(7.5, 8.22, 7.72, 8, 8, 8);
    path.cubicTo(8.28, 8, 8.5, 8.22, 8.5, 8.5);
    path.lineTo(8.5, 11.29);
    path.lineTo(10.65, 9.15);
    path.cubicTo(10.84, 8.96, 11.16, 8.96, 11.35, 9.15);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ArchiveIconPainter old) => old.color != color;
}

// ── Coin icon painter (from SVG) ──────────────────────────────────────────────
class _CoinIconPainter extends CustomPainter {
  final Color color;
  _CoinIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final s = size.width / 120.0;
    canvas.scale(s, s);

    // Outer ring
    final outerPath = Path()
      ..addOval(Rect.fromCircle(center: const Offset(60, 60), radius: 60));
    final outerHole = Path()
      ..addOval(Rect.fromCircle(center: const Offset(60, 60), radius: 52.5));
    canvas.drawPath(
      Path.combine(PathOperation.difference, outerPath, outerHole), paint);

    // Middle ring
    final midPath = Path()
      ..addOval(Rect.fromCircle(center: const Offset(60, 60), radius: 45));
    final midHole = Path()
      ..addOval(Rect.fromCircle(center: const Offset(60, 60), radius: 41.25));
    canvas.drawPath(
      Path.combine(PathOperation.difference, midPath, midHole), paint);

    // Dollar sign
    final dollar = Path();
    // Top curve of S
    dollar.moveTo(70.17, 48.15);
    dollar.lineTo(62.115, 48.15);
    dollar.cubicTo(61.545, 44.745, 58.68, 42.285, 54.18, 41.775);
    dollar.lineTo(54.18, 35.3925);
    dollar.cubicTo(63.645, 35.865, 69.555, 41.2575, 70.17, 48.15);
    dollar.close();

    dollar.moveTo(42.54, 49.29);
    dollar.cubicTo(42.54, 41.6625, 48.6525, 36.27, 57.615, 35.3925);
    dollar.lineTo(57.615, 41.88);
    dollar.cubicTo(53.34, 42.6525, 50.7525, 45.2925, 50.7525, 48.8175);
    dollar.cubicTo(50.7525, 51.9675, 53.1525, 54.06, 57.5775, 55.0875);
    dollar.lineTo(57.615, 55.08);
    dollar.lineTo(57.615, 41.88);
    dollar.close();

    dollar.moveTo(57.615, 62.8275);
    dollar.lineTo(54.6375, 62.0925);
    dollar.cubicTo(47.085, 60.33, 42.54, 56.04, 42.54, 49.29);
    dollar.close();

    dollar.moveTo(62.115, 56.1525);
    dollar.lineTo(65.6625, 56.9925);
    dollar.cubicTo(74.055, 58.9725, 78.75, 62.79, 78.75, 70.1925);
    dollar.cubicTo(78.75, 78.3375, 72.615, 83.9475, 62.115, 84.6825);
    dollar.lineTo(62.115, 90);
    dollar.lineTo(57.615, 90);
    dollar.lineTo(57.615, 84.72);
    dollar.cubicTo(47.475, 84.06, 41.82, 78.4875, 41.25, 71.3325);
    dollar.lineTo(49.26, 71.3325);
    dollar.cubicTo(49.95, 74.8575, 53.0025, 77.385, 57.615, 78.0825);
    dollar.lineTo(57.615, 62.8275);
    dollar.close();

    dollar.moveTo(62.115, 63.885);
    dollar.lineTo(62.115, 78.225);
    dollar.cubicTo(67.5375, 77.715, 70.6275, 74.925, 70.6275, 70.86);
    dollar.cubicTo(70.6275, 67.2975, 68.145, 65.28, 62.7675, 64.035);
    dollar.lineTo(62.115, 63.885);
    dollar.close();

    // Stem top
    dollar.moveTo(57.615, 30);
    dollar.lineTo(62.115, 30);
    dollar.lineTo(62.115, 35.28);
    dollar.lineTo(57.615, 35.3925);
    dollar.close();

    canvas.drawPath(dollar, paint);
  }

  @override
  bool shouldRepaint(_CoinIconPainter old) => old.color != color;
}
