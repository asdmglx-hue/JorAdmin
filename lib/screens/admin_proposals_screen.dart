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
  bool _showApproved = false;
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.svc,
      builder: (_, __) {
        final q = _search.toLowerCase();
        final allPending = widget.svc.users.where((u) => u.status == ProposalStatus.pending).toList();
        final allApproved = widget.svc.users.where((u) => (u.status == ProposalStatus.approved || u.status == ProposalStatus.active)).toList();
        final numSearch = _search.startsWith('#') ? int.tryParse(_search.substring(1)) : int.tryParse(_search);
        final list = (_showApproved ? allApproved : allPending).where((u) =>
          q.isEmpty ||
          u.name.toLowerCase().contains(q) ||
          u.city.toLowerCase().contains(q) ||
          u.contactPhone.contains(_search) ||
          (u.cnic != null && u.cnic!.contains(_search)) ||
          (numSearch != null && u.proposalNumber == numSearch)
        ).toList();

        final canEdit = AdminPerms.i.canEdit(AdminPageKeys.orders);

        return Column(
          children: [
            const ViewOnlyBanner(pageKey: AdminPageKeys.orders),
            // ── Toggle + Search ──
            Padding(
              padding: EdgeInsets.fromLTRB(_S.of(context).s(16), _S.of(context).s(12), _S.of(context).s(16), 0),
              child: Column(
                children: [
                  // Toggle
                  Row(
                    children: [
                      Expanded(child: GestureDetector(
                        onTap: () => setState(() => _showApproved = false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: EdgeInsets.symmetric(vertical: _S.of(context).s(9)),
                          decoration: BoxDecoration(
                            color: !_showApproved ? kPurple : Colors.transparent,
                            borderRadius: BorderRadius.circular(_S.of(context).s(10)),
                            border: Border.all(color: !_showApproved ? kPurple : Colors.white.withOpacity(0.1)),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [

                            SizedBox(width: _S.of(context).s(6)),
                            Text('Pending (${allPending.length})',
                              style: TextStyle(fontSize: _S.of(context).f(12.5), fontWeight: FontWeight.w700,
                                color: !_showApproved ? Colors.white : Colors.white38)),
                          ]),
                        ),
                      )),
                      SizedBox(width: _S.of(context).s(8)),
                      Expanded(child: GestureDetector(
                        onTap: () => setState(() => _showApproved = true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: EdgeInsets.symmetric(vertical: _S.of(context).s(9)),
                          decoration: BoxDecoration(
                            color: _showApproved ? kPurple : Colors.transparent,
                            borderRadius: BorderRadius.circular(_S.of(context).s(10)),
                            border: Border.all(color: _showApproved ? kPurple : Colors.white.withOpacity(0.1)),
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [

                            SizedBox(width: _S.of(context).s(6)),
                            Text('Approved (${allApproved.length})',
                              style: TextStyle(fontSize: _S.of(context).f(12.5), fontWeight: FontWeight.w700,
                                color: _showApproved ? Colors.white : Colors.white38)),
                          ]),
                        ),
                      )),
                    ],
                  ),
                  SizedBox(height: _S.of(context).s(10)),
                  // Search bar
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
                ],
              ),
            ),
            // ── List ──
            Expanded(
              child: list.isEmpty
                ? Center(
                    child: Text(
                      _search.isNotEmpty ? 'No results found' : (_showApproved ? 'No approved proposals' : 'No pending proposals'),
                      style: TextStyle(fontSize: _S.of(context).f(13), color: Colors.white.withOpacity(0.3)),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(_S.of(context).s(16), _S.of(context).s(12), _S.of(context).s(16), _S.of(context).s(20)),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final u = list[i];
                      if (_showApproved) {
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
                      return _PendingCard(
                        user: u,
                        svc: widget.svc,
                        onEdit: () async {
                          await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => AdminEditUserScreen(user: u, svc: widget.svc, readOnly: !canEdit)));
                          widget.svc.notifyListeners();
                        },
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
                    if (user.cnic != null && user.cnic!.isNotEmpty)
                      Text(formatCnicDisplay(user.cnic!), style: TextStyle(fontSize: _S.of(context).f(11), color: Colors.white.withOpacity(0.4)))
                    else if (user.adminNotes == 'AI_IMPORTED' && user.proposalNumber != null)
                      Text('#${user.proposalNumber}', style: TextStyle(fontSize: _S.of(context).f(11), color: Colors.white.withOpacity(0.35)))
                    else
                      Text('Proposal # not set', style: TextStyle(fontSize: _S.of(context).f(11), color: Colors.white.withOpacity(0.2))),

                  ],
                ),
              ),
              Builder(builder: (ctx) => GestureDetector(
                onTap: onView,
                child: Stack(
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
              )),
            ],
          ),
          SizedBox(height: _S.of(context).s(12)),
          _DetailRow(icon: Icons.phone_rounded, label: user.contactPhone),
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
  const _PendingCard({required this.user, required this.svc, required this.onEdit});

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
                    Row(
                      children: [
                        Flexible(
                          child: Text(user.name,
                              style: TextStyle(fontSize: _S.of(context).f(14), fontWeight: FontWeight.w700, color: Colors.white),
                              overflow: TextOverflow.ellipsis),
                        ),
                        SizedBox(width: _S.of(context).s(6)),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(7), vertical: _S.of(context).s(2)),
                          decoration: BoxDecoration(
                            color: kAmber.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(_S.of(context).s(7)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shopping_cart_rounded, size: _S.of(context).d(10), color: kAmber),
                              SizedBox(width: _S.of(context).s(3)),
                              Text('Pending',
                                  style: TextStyle(fontSize: _S.of(context).f(10), fontWeight: FontWeight.w700, color: kAmber)),
                            ],
                          ),
                        ),
                        // Someone can now pay via Google Play before content
                        // review finishes. Always show one of the two —
                        // Paid or Unpaid — rather than only showing Paid and
                        // leaving Unpaid to be inferred from its absence.
                        SizedBox(width: _S.of(context).s(4)),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(7), vertical: _S.of(context).s(2)),
                          decoration: BoxDecoration(
                            color: (user.subscriptionStatus == SubscriptionStatus.refunded ? kRose : user.subscriptionStatus == SubscriptionStatus.active ? kGreen : kRose).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(_S.of(context).s(7)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                user.subscriptionStatus == SubscriptionStatus.refunded ? Icons.replay_circle_filled_rounded : user.subscriptionStatus == SubscriptionStatus.active ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
                                size: _S.of(context).d(10),
                                color: user.subscriptionStatus == SubscriptionStatus.active ? kGreen : kRose,
                              ),
                              SizedBox(width: _S.of(context).s(3)),
                              Text(
                                user.subscriptionStatus == SubscriptionStatus.refunded ? 'Refunded' : user.subscriptionStatus == SubscriptionStatus.active ? 'Paid' : 'Unpaid',
                                style: TextStyle(fontSize: _S.of(context).f(10), fontWeight: FontWeight.w700, color: user.subscriptionStatus == SubscriptionStatus.active ? kGreen : kRose),
                              ),
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
                      ],
                    ),
                    SizedBox(height: _S.of(context).s(2)),
                    if (user.cnic != null && user.cnic!.isNotEmpty)
                      Text(formatCnicDisplay(user.cnic!), style: TextStyle(fontSize: _S.of(context).f(11), color: Colors.white.withOpacity(0.4)))
                    else if (user.adminNotes == 'AI_IMPORTED' && user.proposalNumber != null)
                      Text('#${user.proposalNumber}', style: TextStyle(fontSize: _S.of(context).f(11), color: Colors.white.withOpacity(0.35)))
                    else
                      Text('CNIC not set', style: TextStyle(fontSize: _S.of(context).f(11), color: Colors.white.withOpacity(0.2))),

                  ],
                ),
              ),
              Builder(builder: (ctx) => GestureDetector(
                onTap: () => Navigator.push(ctx, MaterialPageRoute(
                  builder: (_) => AdminEditUserScreen(user: user, svc: svc, readOnly: true))),
                child: Stack(
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
              )),
            ],
          ),
          SizedBox(height: _S.of(context).s(12)),
          _DetailRow(icon: Icons.phone_rounded, label: user.contactPhone),
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
