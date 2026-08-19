import '../services/supabase_service.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/theme.dart';
import '../services/admin_service.dart';
import '../models/admin_models.dart';
import '../models/admin_permissions.dart';
import 'admin_edit_user_screen.dart';
import 'admin_trash_screen.dart';
import 'admin_edit_requests_screen.dart';

// Shared by both the "Featured" filter chip (_AdminUsersScreenState) and
// the "Featured" badge label on each card (_UserCard) — was previously
// duplicated as a private method on _UserCard only, which meant the filter
// chip couldn't see it and had to fall back to checking the wrong field.
bool hasFeaturedBoostToday(AdminUser u) {
  final now = DateTime.now();
  return u.featuredSchedule.any((b) =>
    !b.isUsed &&
    now.isAfter(b.scheduledDate) &&
    now.isBefore(b.scheduledDate.add(const Duration(hours: 24)))
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

class AdminUsersScreen extends StatefulWidget {
  final AdminService svc;
  const AdminUsersScreen({super.key, required this.svc});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _filter = 'All';
  String _aiSort = 'All'; // 'All', 'Permitted', 'Not Permitted'
  String _timeFilter = 'Any time';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  String _search = '';
  final _searchCtrl = TextEditingController();
  int _featuredCreditPrice = 200; // loaded from app_settings

  @override
  void initState() {
    super.initState();
    SupabaseService.instance.fetchAppSettings().then((s) {
      if (mounted) setState(() {
        _featuredCreditPrice = int.tryParse(s['featured_post_price'] ?? '200') ?? 200;
      });
    });
  }

  void _showDeleteByNumberDialog(BuildContext context) {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.users, what: 'deleting profiles')) return;
    final s = _S.of(context);
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF16132A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(16))),
      title: Text('Delete by Proposal #', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(15))),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        style: TextStyle(color: Colors.white, fontSize: s.f(14)),
        decoration: InputDecoration(
          hintText: 'Enter proposal number e.g. 12',
          hintStyle: TextStyle(color: Colors.white38, fontSize: s.f(13)),
          prefixText: '# ',
          prefixStyle: TextStyle(color: kPurple, fontWeight: FontWeight.w700),
          filled: true,
          fillColor: Colors.white.withOpacity(0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide.none),
          contentPadding: EdgeInsets.symmetric(horizontal: s.s(12), vertical: s.s(12)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: Colors.white38, fontSize: s.f(13)))),
        TextButton(
          onPressed: () async {
            final num = int.tryParse(ctrl.text.trim());
            if (num == null) return;
            final user = widget.svc.findUserByNumber(num);
            Navigator.pop(ctx);
            if (user == null) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('No proposal found with #$num'),
                backgroundColor: kRose, behavior: SnackBarBehavior.floating,
              ));
              return;
            }
            final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF16132A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(s.s(16))),
              title: Text('Delete #$num?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(15))),
              content: Text('Permanently delete "${user.name}" (Proposal #$num)? This cannot be undone.', style: TextStyle(color: Colors.white60, fontSize: s.f(13))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: Colors.white38, fontSize: s.f(13)))),
                TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete Forever', style: TextStyle(color: kRose, fontWeight: FontWeight.w700, fontSize: s.f(13)))),
              ],
            ));
            if (confirm == true) {
              await widget.svc.deleteUserByNumber(num);
            }
          },
          child: Text('Find & Delete', style: TextStyle(color: kRose, fontWeight: FontWeight.w700, fontSize: s.f(13))),
        ),
      ],
    ));
  }

  List<AdminUser> get _filtered {
    var list = widget.svc.users.where((u) => u.status != ProposalStatus.deleted && u.status != ProposalStatus.pending).toList();
    // 'Inactive' matches the same definition used for the badge label
    // elsewhere on this screen (see _getBadgeLabel): expired counts as
    // inactive too. Checking only SubscriptionStatus.inactive matched
    // almost nothing, since real expired subscriptions parse to
    // SubscriptionStatus.expired — .inactive is only ever the fallback
    // for missing/unparseable data, not what real expired users have.
    if (_filter == 'Inactive') list = list.where((u) =>
        u.subscriptionStatus == SubscriptionStatus.expired ||
        u.subscriptionStatus == SubscriptionStatus.inactive).toList();
    if (_filter == 'Active') list = list.where((u) => u.subscriptionStatus == SubscriptionStatus.active).toList();
    if (_filter == 'Expired') list = list.where((u) => u.subscriptionStatus == SubscriptionStatus.expired).toList();
    if (_filter == 'Paused') list = list.where((u) => u.status == ProposalStatus.paused).toList();
    // 'Featured' means "currently has a live featured boost" (the actual
    // feature admins use from the Users screen), not subscriptionTier ==
    // featured — that's a separate, unused permanent-tier field nothing in
    // the app ever actually sets. Matches the same check the "Featured"
    // badge label on each card uses (hasFeaturedBoostToday).
    if (_filter == 'Featured') list = list.where((u) => hasFeaturedBoostToday(u)).toList();
    if (_filter == 'AI') list = list.where((u) => u.adminNotes == 'AI_IMPORTED').toList();
    if (_filter == 'AI' && _aiSort == 'Permitted') list = list.where((u) => u.registrationAllowed).toList();
    if (_filter == 'AI' && _aiSort == 'Not Permitted') list = list.where((u) => !u.registrationAllowed).toList();
    if (_filter == 'Refunded') list = list.where((u) => u.subscriptionStatus == SubscriptionStatus.refunded).toList();
    final now = DateTime.now();
    if (_dateFrom != null && _dateTo != null) {
      list = list.where((u) => !u.postedAt.isBefore(_dateFrom!) && !u.postedAt.isAfter(_dateTo!.add(const Duration(days: 1)))).toList();
    }
    if (_search.isNotEmpty) {
      final numSearch = _search.startsWith('#') ? int.tryParse(_search.substring(1)) : int.tryParse(_search);
      list = list.where((u) =>
        u.name.toLowerCase().contains(_search.toLowerCase()) ||
        u.city.toLowerCase().contains(_search.toLowerCase()) ||
        u.contactPhone.contains(_search) ||
        (u.cnic != null && u.cnic!.contains(_search)) ||
        (numSearch != null && u.proposalNumber == numSearch)
      ).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final canEdit = AdminPerms.i.canEdit(AdminPageKeys.users);
    return Column(
      children: [
        const ViewOnlyBanner(pageKey: AdminPageKeys.users),
        _buildSearchBar(),
        SizedBox(height: s.s(8)),
        _buildFilterRow(),
        SizedBox(height: s.s(4)),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(s.s(16), s.s(8), s.s(16), s.s(20)),
            itemCount: _filtered.length,
            itemBuilder: (_, i) => _UserCard(
              user: _filtered[i],
              svc: widget.svc,
              featuredCreditPrice: _featuredCreditPrice,
              onEdit: () async {
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AdminEditUserScreen(user: _filtered[i], svc: widget.svc, readOnly: !canEdit)));
                if (mounted) setState(() {});
              },
              onView: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => AdminEditUserScreen(user: _filtered[i], svc: widget.svc, readOnly: true))),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showTimeFilter(BuildContext context) async {
    final now = DateTime.now();
    DateTime? tempFrom = _dateFrom;
    DateTime? tempTo = _dateTo;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: const Color(0xFF1E1A33),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: EdgeInsets.all(_S.of(ctx).s(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filter by Date', style: TextStyle(fontSize: _S.of(ctx).f(15), fontWeight: FontWeight.w800, color: Colors.white)),
                SizedBox(height: _S.of(ctx).s(4)),
                Text('Select a date range to filter proposals', style: TextStyle(fontSize: _S.of(ctx).f(11.5), color: Colors.white.withOpacity(0.5))),
                SizedBox(height: _S.of(ctx).s(12)),
                // From date
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: tempFrom ?? now,
                      firstDate: DateTime(2020),
                      lastDate: now,
                      builder: (ctx, child) => Theme(
                        data: ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(primary: kPurple, onPrimary: Colors.white, surface: Color(0xFF2A2545), onSurface: Colors.white),
                          textTheme: const TextTheme(
                            titleLarge: TextStyle(fontWeight: FontWeight.w800),
                            bodyLarge: TextStyle(fontWeight: FontWeight.w700),
                            bodyMedium: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (d != null) setS(() { tempFrom = d; if (tempTo != null && tempTo!.isBefore(d)) tempTo = null; });
                  },
                  child: _datePickerBtn('From', tempFrom),
                ),
                SizedBox(height: _S.of(ctx).s(8)),
                // To date
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: tempTo ?? tempFrom ?? now,
                      firstDate: tempFrom ?? DateTime(2020),
                      lastDate: now,
                      builder: (ctx, child) => Theme(
                        data: ThemeData.dark().copyWith(
                          colorScheme: const ColorScheme.dark(primary: kPurple, onPrimary: Colors.white, surface: Color(0xFF2A2545), onSurface: Colors.white),
                          textTheme: const TextTheme(
                            titleLarge: TextStyle(fontWeight: FontWeight.w800),
                            bodyLarge: TextStyle(fontWeight: FontWeight.w700),
                            bodyMedium: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (d != null) setS(() => tempTo = d);
                  },
                  child: _datePickerBtn('To', tempTo),
                ),
                SizedBox(height: _S.of(ctx).s(12)),
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () {
                      setState(() { _dateFrom = null; _dateTo = null; _timeFilter = 'Any time'; });
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: _S.of(ctx).s(10)),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(_S.of(ctx).s(10))),
                      child: Center(child: Text('Clear', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: _S.of(ctx).f(13)))),
                    ),
                  )),
                  SizedBox(width: _S.of(ctx).s(10)),
                  Expanded(child: GestureDetector(
                    onTap: () {
                      if (tempFrom != null) {
                        setState(() {
                          _dateFrom = tempFrom;
                          _dateTo = tempTo ?? tempFrom;
                          _timeFilter = '${_dateStr(_dateFrom!)} – ${_dateStr(_dateTo!)}';
                        });
                      }
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: _S.of(ctx).s(10)),
                      decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(_S.of(ctx).s(10))),
                      child: Center(child: Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: _S.of(ctx).f(13)))),
                    ),
                  )),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _dateStr(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Widget _datePickerBtn(String label, DateTime? date) {
    // Can't use _S.of(context) here since this is called from a dialog ctx
    // so we use fixed values — dialog is rare admin-only flow
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: date != null ? kPurple.withOpacity(0.1) : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: date != null ? kPurple.withOpacity(0.4) : Colors.white.withOpacity(0.1)),
      ),
      child: Row(children: [
        Icon(Icons.calendar_today_rounded, size: 14, color: date != null ? kPurple : Colors.white38),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(date != null ? _dateStr(date) : 'Select', style: TextStyle(fontSize: 13, color: date != null ? Colors.white : Colors.white38, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _buildSearchBar() {
    final s = _S.of(context);
    final timeActive = _dateFrom != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(s.s(16), s.s(12), s.s(16), 0),
      child: Row(
        children: [
          Expanded(
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
                  hintText: 'Search by name, city, phone, cnic, #number...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: s.f(13)),
                  prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.3), size: s.d(20)),
                  prefixIconConstraints: BoxConstraints(minWidth: s.d(44), minHeight: s.d(44)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: s.s(12)),
                ),
              ),
            ),
          ),
          SizedBox(width: s.s(8)),
          GestureDetector(
            onTap: () => _showTimeFilter(context),
            child: Container(
              width: s.d(44), height: s.d(44),
              decoration: BoxDecoration(
                color: timeActive ? kPurple.withOpacity(0.15) : const Color(0xFF16132A),
                borderRadius: BorderRadius.circular(s.s(14)),
                border: Border.all(color: timeActive ? kPurple.withOpacity(0.4) : Colors.white.withOpacity(0.08)),
              ),
              child: Icon(Icons.calendar_today_rounded, size: s.d(18), color: timeActive ? kPurple : Colors.white.withOpacity(0.4)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    final s = _S.of(context);
    final filters = ['All', 'AI', 'Active', 'Inactive', 'Refunded', 'Paused', 'Featured'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: s.d(44),
      child: ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: s.s(16), vertical: s.s(6)),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (_, i) {
          final f = filters[i];
          final sel = _filter == f;
          return GestureDetector(
            onTap: () => setState(() { _filter = f; if (f != 'AI') _aiSort = 'All'; }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: s.s(8)),
              padding: EdgeInsets.symmetric(horizontal: s.s(14)),
              decoration: BoxDecoration(
                color: sel ? kPurple : const Color(0xFF16132A),
                borderRadius: BorderRadius.circular(s.s(20)),
                border: Border.all(color: sel ? kPurple : Colors.white.withOpacity(0.1)),
              ),
              child: Center(
                child: Text(f, style: TextStyle(fontSize: s.f(12.5), fontWeight: FontWeight.w600, color: sel ? Colors.white : Colors.white.withOpacity(0.4))),
              ),
            ),
          );
        },
      ),
        ),
        // AI sub-sort chips — only show when AI filter is active
        if (_filter == 'AI') ...[
          SizedBox(height: s.s(6)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: s.s(16)),
            child: DropdownButtonHideUnderline(
              child: Container(
                height: s.d(34),
                padding: EdgeInsets.symmetric(horizontal: s.s(12)),
                decoration: BoxDecoration(
                  color: const Color(0xFF16132A),
                  borderRadius: BorderRadius.circular(s.s(8)),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: DropdownButton<String>(
                  value: _aiSort,
                  dropdownColor: const Color(0xFF1E1A35),
                  style: TextStyle(fontSize: s.f(12), color: Colors.white, fontWeight: FontWeight.w600),
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.5), size: s.d(18)),
                  items: [
                    DropdownMenuItem(value: 'All', child: Text('All', style: TextStyle(fontSize: s.f(12), color: Colors.white))),
                    DropdownMenuItem(value: 'Permitted', child: Text('Permitted', style: TextStyle(fontSize: s.f(12), color: kGreen))),
                    DropdownMenuItem(value: 'Not Permitted', child: Text('Not Permitted', style: TextStyle(fontSize: s.f(12), color: kRose))),
                  ],
                  onChanged: (v) => setState(() => _aiSort = v ?? 'All'),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _UserCard extends StatefulWidget {
  final AdminUser user;
  final AdminService svc;
  final VoidCallback onEdit;
  final VoidCallback onView;
  final int featuredCreditPrice;
  const _UserCard({required this.user, required this.svc, required this.onEdit, required this.onView, this.featuredCreditPrice = 200});
  @override State<_UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<_UserCard> {
  late bool _allowed;

  @override
  void initState() {
    super.initState();
    _allowed = widget.user.registrationAllowed;
  }

  @override
  void didUpdateWidget(_UserCard old) {
    super.didUpdateWidget(old);
    if (old.user.registrationAllowed != widget.user.registrationAllowed) {
      _allowed = widget.user.registrationAllowed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final user = widget.user;
    final svc = widget.svc;
    final onEdit = widget.onEdit;
    final onView = widget.onView;
    final featuredCreditPrice = widget.featuredCreditPrice;
    return GestureDetector(
      onLongPress: user.adminNotes == 'AI_IMPORTED' ? () => _showAiApprovalMenu(context) : null,
      child: Container(
      margin: EdgeInsets.only(bottom: s.s(10)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(s.s(18)),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          // Top row
          Padding(
            padding: EdgeInsets.fromLTRB(s.s(14), s.s(14), s.s(14), s.s(10)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(user: user),
                SizedBox(width: s.s(12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(user.name,
                              style: TextStyle(fontSize: s.f(14), fontWeight: FontWeight.w700, color: Colors.white),
                              overflow: TextOverflow.ellipsis),
                          ),
                          if (_badgeLabel(user).isNotEmpty) ...[
                            SizedBox(width: s.s(6)),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: s.s(7), vertical: s.s(2)),
                              decoration: BoxDecoration(color: _badgeColor(user).withOpacity(0.12), borderRadius: BorderRadius.circular(s.s(7))),
                              child: Text(_badgeLabel(user), style: TextStyle(fontSize: s.f(10), fontWeight: FontWeight.w700, color: _badgeColor(user))),
                            ),
                          ],
                          if (user.adminNotes == 'AI_IMPORTED') ...[
                            SizedBox(width: s.s(4)),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: s.s(7), vertical: s.s(2)),
                              decoration: BoxDecoration(color: kRose.withOpacity(0.12), borderRadius: BorderRadius.circular(s.s(7))),
                              child: Text('Not Approved', style: TextStyle(fontSize: s.f(10), fontWeight: FontWeight.w700, color: kRose)),
                            ),
                            SizedBox(width: s.s(4)),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: s.s(6), vertical: s.s(2)),
                              decoration: BoxDecoration(
                                color: kPurple.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(s.s(7)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome, size: s.d(9), color: kPurple),
                                  SizedBox(width: s.s(3)),
                                  Text('AI', style: TextStyle(fontSize: s.f(10), fontWeight: FontWeight.w700, color: kPurple)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: s.s(3)),
                      Row(
                        children: [
                          Text(
                            (user.cnic != null && user.cnic!.isNotEmpty)
                                ? formatCnicDisplay(user.cnic!)
                                : (user.adminNotes == 'AI_IMPORTED' && user.proposalNumber != null)
                                    ? '#${user.proposalNumber}'
                                    : 'CNIC not set',
                            style: TextStyle(fontSize: s.f(11), fontWeight: FontWeight.w500,
                              color: (user.cnic != null && user.cnic!.isNotEmpty) ? Colors.white.withOpacity(0.45) : Colors.white.withOpacity(0.35)),
                          ),
                          // Registration allowed checkbox inline — only for AI imported profiles
                          if (user.adminNotes == 'AI_IMPORTED') ...[
                            SizedBox(width: s.s(8)),
                            GestureDetector(
                              onTap: () async {
                                if (!AdminPerms.i.guardEdit(AdminPageKeys.users, what: 'changing permission status')) return;
                                final newVal = !_allowed;
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              backgroundColor: const Color(0xFF1E1A35),
                              title: Text(
                                newVal ? 'Mark as Permitted?' : 'Mark as Not Permitted?',
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                              ),
                              content: Text(
                                newVal
                                    ? 'Mark that this person has given you permission to create their profile.'
                                    : 'Mark that this person has NOT given you permission to create their profile.',
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text('Confirm', style: TextStyle(color: newVal ? kGreen : kRose, fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          setState(() => _allowed = newVal);
                          await SupabaseService.instance.client.from('proposals').update({'registration_allowed': newVal}).eq('id', user.id);
                          svc.loadData();
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _allowed ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                              size: s.d(14),
                              color: _allowed ? kGreen : Colors.white.withOpacity(0.3),
                            ),
                            SizedBox(width: s.s(4)),
                            Text(
                              _allowed ? 'Permission' : 'Permission',
                              style: TextStyle(
                                fontSize: s.f(10),
                                fontWeight: FontWeight.w600,
                                color: _allowed ? kGreen : Colors.white.withOpacity(0.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: s.s(8)),
                Padding(
                  padding: EdgeInsets.only(top: s.s(2)),
                  child: GestureDetector(
                    onTap: onView,
                    child: Container(
                      width: s.d(28), height: s.d(28),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(s.s(8))),
                      child: Icon(Icons.remove_red_eye_outlined, size: s.d(16), color: Colors.white.withOpacity(0.5)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Subscription details row
          Container(
            margin: EdgeInsets.symmetric(horizontal: s.s(14)),
            padding: EdgeInsets.all(s.s(12)),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(12))),
            child: Row(
              children: [
                _InfoChip(
                  label: 'Start',
                  value: user.subscriptionStatus != SubscriptionStatus.inactive && user.subscriptionStart != null
                      ? _date(user.subscriptionStart!)
                      : '—',
                  color: kTeal,
                ),
                _divider(context),
                _InfoChip(
                  label: 'Days Left',
                  value: user.adminNotes == 'AI_IMPORTED'
                      ? '—'
                      : user.subscriptionStatus != SubscriptionStatus.inactive
                          ? user.subscriptionDaysLeft
                          : '—',
                  color: kPurple,
                  onTap: () => _showSetDaysDialog(context),
                ),
                _divider(context),
                _InfoChip(
                  label: 'Featured',
                  value: user.featuredPointsPurchased > 0
                      ? '${user.featuredPointsUsed}/${user.featuredPointsPurchased}'
                      : '—',
                  color: kAmber,
                ),
                _divider(context),
                _InfoChip(
                  label: 'Spent',
                  value: 'Rs.${user.totalSpending.toInt()}',
                  color: kGreen,
                ),
              ],
            ),
          ),
          // Action buttons
          Padding(
            padding: EdgeInsets.fromLTRB(_S.of(context).s(14), _S.of(context).s(10), _S.of(context).s(14), _S.of(context).s(14)),
            child: Row(
              children: [
                _ActionBtn(
                  icon: AdminPerms.i.canEdit(AdminPageKeys.users) ? Icons.edit_rounded : Icons.visibility_rounded,
                  label: AdminPerms.i.canEdit(AdminPageKeys.users) ? 'Edit' : 'View',
                  color: kPurple, onTap: onEdit),
                SizedBox(width: _S.of(context).s(8)),
                if (AdminPerms.i.canEdit(AdminPageKeys.users) && user.subscriptionStatus == SubscriptionStatus.expired)
                  _ActionBtn(
                    icon: Icons.refresh_rounded,
                    label: 'Renew',
                    color: kGreen,
                    onTap: () async {
                      HapticFeedback.mediumImpact();
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF16132A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Confirm Renewal',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                          content: const Text(
                            'User has made a payment for subscription renewal.',
                            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('No', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Yes', style: TextStyle(color: kGreen, fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      await SupabaseService.instance.renewSubscription(user.id);
                      svc.restoreUser(user.id, 'users');
                      // Renewal notification sent automatically by edge function
                    },
                  )
                else if (AdminPerms.i.canEdit(AdminPageKeys.users) && user.status != ProposalStatus.paused)
                  _ActionBtn(
                    icon: Icons.pause_rounded,
                    label: 'Pause',
                    color: kTeal,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF16132A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          title: const Text('Pause Profile?',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                          content: Text(
                            '${user.name}\'s profile will be hidden from the feed. You can resume it anytime.',
                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                            ),
                            TextButton(
                              onPressed: () { Navigator.pop(context); HapticFeedback.heavyImpact(); svc.pauseUser(user.id); },
                              child: const Text('Pause', style: TextStyle(color: kTeal, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                else if (AdminPerms.i.canEdit(AdminPageKeys.users))
                  _ActionBtn(
                    icon: Icons.play_arrow_rounded,
                    label: 'Resume',
                    color: kGreen,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF16132A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          title: const Text('Resume Profile?',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                          content: Text(
                            '${user.name}\'s profile will be visible in the feed again.',
                            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                            ),
                            TextButton(
                              onPressed: () { Navigator.pop(context); HapticFeedback.heavyImpact(); svc.activateUser(user.id); },
                              child: const Text('Resume', style: TextStyle(color: kGreen, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                else
                  const SizedBox.shrink(),
                const SizedBox(width: 8),
                if (AdminPerms.i.canEdit(AdminPageKeys.users)) ...[
                  _ActionBtn(
                    icon: Icons.star_rounded,
                    label: 'Featured',
                    color: kAmber,
                    disabled: user.subscriptionStatus == SubscriptionStatus.expired,
                    onTap: () => _showFeaturedSheet(context),
                  ),
                  const SizedBox(width: 8),
                  _ActionBtn(icon: Icons.delete_outline_rounded, label: 'Trash', color: kRose, onTap: () => _confirmDelete(context)),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.users, what: 'deleting profiles')) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF16132A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Move to Trash?',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        content: Text(
          '${widget.user.name}\'s profile will be moved to trash. You can restore it later.',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              HapticFeedback.heavyImpact();
              widget.svc.deleteUser(widget.user.id, from: 'users');
            },
            child: const Text('Move to Trash', style: TextStyle(color: kRose, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showFeaturedSheet(BuildContext context) {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.users, what: 'featured posts')) return;
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeaturedManageSheet(user: widget.user, svc: widget.svc, featuredCreditPrice: widget.featuredCreditPrice, messenger: messenger),
    );
  }

  Widget _divider(BuildContext context) {
    final s = _S.of(context);
    return Container(width: 1, height: s.d(28), color: Colors.white.withOpacity(0.1), margin: EdgeInsets.symmetric(horizontal: s.s(8)));
  }

  Color _badgeColor(AdminUser u) {
    if (u.subscriptionStatus == SubscriptionStatus.refunded) return kRose;
    if (u.status == ProposalStatus.paused) return kTeal;
    if (u.subscriptionStatus == SubscriptionStatus.expired || u.subscriptionStatus == SubscriptionStatus.inactive) return const Color(0xFF6B7280);
    if (hasFeaturedBoostToday(u)) return kAmber;
    if (u.subscriptionTier == SubscriptionTier.featured &&
        u.subscriptionStatus == SubscriptionStatus.active) return kAmber;
    switch (u.subscriptionStatus) {
      case SubscriptionStatus.active: return kGreen;
      case SubscriptionStatus.expired: return const Color(0xFF6B7280);
      case SubscriptionStatus.inactive: return Colors.white38;
      case SubscriptionStatus.refunded: return kRose;
    }
  }

  String _badgeLabel(AdminUser u) {
    if (u.subscriptionStatus == SubscriptionStatus.refunded) return 'Refunded';
    if (u.status == ProposalStatus.paused) return 'Paused';
    if (u.status == ProposalStatus.approved) return 'Active';
    if (u.subscriptionStatus == SubscriptionStatus.expired || u.subscriptionStatus == SubscriptionStatus.inactive) return 'Inactive';
    if (hasFeaturedBoostToday(u)) return 'Featured';
    if (u.subscriptionTier == SubscriptionTier.featured &&
        u.subscriptionStatus == SubscriptionStatus.active) return 'Featured';
    switch (u.subscriptionStatus) {
      case SubscriptionStatus.active: return 'Active';
      case SubscriptionStatus.expired: return 'Inactive';
      case SubscriptionStatus.inactive: return '';
      case SubscriptionStatus.refunded: return 'Refunded';
    }
  }

  String _date(DateTime d) => '${d.day}/${d.month}/${d.year % 100}';

  void _showSetDaysDialog(BuildContext context) {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.users, what: 'changing subscription days')) return;
    final daysCtrl = TextEditingController();
    bool saving = false;
    String? error;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dlgCtx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF16132A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.event_available_rounded, color: kPurple, size: 20),
            const SizedBox(width: 8),
            const Text('Set Usage', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Add expiry for proposals manually',
              style: TextStyle(fontSize: 12.5, color: Colors.white.withOpacity(0.5)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: daysCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setDlg(() {}),
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'e.g. 90',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                suffixText: 'days',
                suffixStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                filled: true,
                fillColor: Colors.black.withOpacity(0.25),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: kPurple)),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(fontSize: 12, color: kRose)),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dlgCtx),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4))),
            ),
            Builder(builder: (context) {
              final days = int.tryParse(daysCtrl.text.trim());
              final enabled = days != null && days > 0 && !saving;
              return GestureDetector(
                onTap: !enabled ? null : () async {
                  setDlg(() { saving = true; error = null; });
                  try {
                    await SupabaseService.instance.setCustomSubscriptionDays(widget.user.id, days!);
                    if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                  } catch (e) {
                    setDlg(() { saving = false; error = 'Failed to save'; });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: enabled ? kPurple : kPurple.withOpacity(0.35), borderRadius: BorderRadius.circular(8)),
                  child: saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Save', style: TextStyle(color: Colors.white.withOpacity(enabled ? 1 : 0.6), fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // Long-press entry point on AI-imported cards only — offers to approve
  // (which opens the full form below) or explicitly leave it unapproved.
  void _showAiApprovalMenu(BuildContext context) {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.users, what: 'approving profiles')) return;
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1A33),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.check_circle_rounded, color: kGreen),
          title: const Text('Approve Profile', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          subtitle: Text('Requires CNIC, password, and expiry to be set first',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11.5)),
          onTap: () { Navigator.pop(sheetCtx); _showApproveAiDialog(context); },
        ),
        const SizedBox(height: 8),
      ])),
    );
  }

  // The actual approval form. CNIC, password, and expiry days are all
  // required — the Approve button stays disabled (matching the same
  // muted-until-ready pattern used everywhere else in this app) until all
  // three have valid values. Rs. Spent is the one optional field. On
  // success this calls approve_ai_proposal(), which atomically sets
  // everything AND flips admin_notes away from 'AI_IMPORTED' — that's
  // what makes the card leave the AI filter and show under Active,
  // exactly like an ordinary profile, with the persistent "Approved" tag
  // now showing next to its status.
  void _showApproveAiDialog(BuildContext context) {
    final cnicCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final daysCtrl = TextEditingController();
    final spentCtrl = TextEditingController();
    bool saving = false;
    bool generatingCnic = false;
    String? error;

    InputDecoration deco(String hint, {String? suffix}) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
      suffixText: suffix,
      suffixStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
      filled: true,
      fillColor: Colors.black.withOpacity(0.25),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: kPurple)),
    );

    Widget genButton(bool loading, VoidCallback onTap) => GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
        child: loading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: kPurple, strokeWidth: 2))
            : Icon(Icons.auto_fix_high_rounded, color: kPurple, size: 18),
      ),
    );

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dlgCtx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF16132A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.check_circle_rounded, color: kGreen, size: 20),
            const SizedBox(width: 8),
            const Text('Approve Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CNIC, password, and expiry are all required before this profile can be approved.',
                style: TextStyle(fontSize: 12.5, color: Colors.white.withOpacity(0.5))),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(child: TextField(
                  controller: cnicCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d-]')), _AiCnicFormatter()],
                  onChanged: (_) => setDlg(() {}),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: deco('CNIC'),
                )),
                const SizedBox(width: 8),
                genButton(generatingCnic, () async {
                  setDlg(() => generatingCnic = true);
                  try {
                    final cnic = await SupabaseService.instance.generateNextAiCnic();
                    cnicCtrl.text = cnic;
                  } catch (_) {}
                  setDlg(() => generatingCnic = false);
                }),
              ]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(child: TextField(
                  controller: passwordCtrl,
                  onChanged: (_) => setDlg(() {}),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: deco('Password'),
                )),
                const SizedBox(width: 8),
                genButton(false, () {
                  passwordCtrl.text = _generateAiPassword();
                  setDlg(() {});
                }),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: daysCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setDlg(() {}),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: deco('Expiry', suffix: 'days'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: spentCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: deco('Rs. Spent (optional)'),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(fontSize: 12, color: kRose)),
              ],
            ]),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            Builder(builder: (context) {
              final copyEnabled = cnicCtrl.text.trim().isNotEmpty && passwordCtrl.text.trim().isNotEmpty && (int.tryParse(daysCtrl.text.trim()) ?? 0) > 0;
              return GestureDetector(
                onTap: !copyEnabled ? null : () {
                  final days = int.parse(daysCtrl.text.trim());
                  final validUntil = DateTime.now().add(Duration(days: days));
                  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
                  final validUntilStr = '${validUntil.day} ${months[validUntil.month - 1]} ${validUntil.year}';
                  final message = '''
*Your Login Details*

*CNIC:* ${cnicCtrl.text.trim()}
*Password:* ${passwordCtrl.text.trim()}

*View Your Profile:*
https://joronline.com/profile/${widget.user.proposalNumber}

You can change your password and update your profile after logging in.

*Website:*
joronline.com

*Android App:*
joronline.com/get-android

Your *Free Plan* is valid until: *$validUntilStr*

We're available 24/7 on WhatsApp to assist you, and we wish you success in finding the right rishta on Jor!

Jor Team 🤗'''.trim();
                  Clipboard.setData(ClipboardData(text: message));
                  HapticFeedback.lightImpact();
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.copy_rounded, size: 14, color: copyEnabled ? kPurple : Colors.white.withOpacity(0.2)),
                  const SizedBox(width: 5),
                  Text('Copy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: copyEnabled ? kPurple : Colors.white.withOpacity(0.2))),
                ]),
              );
            }),
            Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(
                onPressed: () => Navigator.pop(dlgCtx),
                child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4))),
              ),
              Builder(builder: (context) {
              final cnicValid = cnicCtrl.text.replaceAll('-', '').length == 13;
              final passwordValid = passwordCtrl.text.trim().isNotEmpty;
              final days = int.tryParse(daysCtrl.text.trim());
              final daysValid = days != null && days > 0;
              final enabled = cnicValid && passwordValid && daysValid && !saving;
              return GestureDetector(
                onTap: !enabled ? null : () async {
                  setDlg(() { saving = true; error = null; });
                  try {
                    final spent = double.tryParse(spentCtrl.text.trim());
                    await SupabaseService.instance.approveAiProposalWithDetails(
                      userId: widget.user.id,
                      cnic: cnicCtrl.text.trim(),
                      password: passwordCtrl.text.trim(),
                      days: days!,
                      amountPaid: spent,
                    );
                    if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                  } catch (e) {
                    setDlg(() { saving = false; error = 'Failed to approve: $e'; });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: enabled ? kGreen : kGreen.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                  child: saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Approve', style: TextStyle(color: Colors.white.withOpacity(enabled ? 1 : 0.6), fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              );
            }),
            ]),
          ],
        ),
      ),
    );
  }

  // Random password for the auto-generate button — deliberately excludes
  // visually-confusable characters (0/O, 1/l/I) so a typed-out password
  // is easy to read back correctly if it ever needs to be shared.
  String _generateAiPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final rand = Random.secure();
    return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}

// Same dash placement as elsewhere in this app (XXXXX-XXXXXXX-X). Kept as
// its own copy here since Dart privacy means it can't be imported from
// admin_edit_user_screen.dart / admin_add_user_screen.dart — matches the
// established pattern already used for other small private helpers.
class _AiCnicFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('-', '');
    if (digits.length > 13) return oldValue;
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 5 || i == 12) buf.write('-');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class _Avatar extends StatelessWidget {
  final AdminUser user;
  const _Avatar({required this.user});

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
    final s = _S.of(context);
    final isFemale = user.gender.trim().toLowerCase() == 'female';
    final initial = user.name.isNotEmpty ? user.name.substring(0, 1) : '?';
    final fallback = Center(child: Text(initial, style: TextStyle(fontSize: s.f(20), fontWeight: FontWeight.w800, color: Colors.white)));
    final photoUrl = user.profilePhoto;
    return GestureDetector(
      onTap: () => _showFullScreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(s.s(13)),
        child: Container(
          width: s.d(46), height: s.d(46),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isFemale ? [kRose.withOpacity(0.8), kRose] : [kPurple.withOpacity(0.8), kPurpleDeep],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(s.s(13)),
          ),
          child: photoUrl != null && photoUrl.isNotEmpty
              ? CachedNetworkImage(imageUrl: photoUrl, fit: BoxFit.cover, errorWidget: (_, __, ___) => fallback)
              : fallback,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;
  const _InfoChip({required this.label, required this.value, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final content = Column(
      children: [
        Text(value, style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w700, color: color), textAlign: TextAlign.center),
        SizedBox(height: s.s(2)),
        Text(label, style: TextStyle(fontSize: s.f(9.5), color: Colors.white.withOpacity(0.35)), textAlign: TextAlign.center),
      ],
    );
    return Expanded(
      child: onTap == null ? content : GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: content),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool disabled;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap, this.disabled = false});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final effectiveColor = disabled ? Colors.white : color;
    final bgOpacity = disabled ? 0.03 : 0.1;
    final iconOpacity = disabled ? 0.15 : 1.0;
    return Expanded(
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Container(
          height: s.d(36),
          decoration: BoxDecoration(color: effectiveColor.withOpacity(bgOpacity), borderRadius: BorderRadius.circular(s.s(10))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: effectiveColor.withOpacity(iconOpacity), size: s.d(14)),
              SizedBox(width: s.s(4)),
              Text(label, style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w700, color: effectiveColor.withOpacity(iconOpacity))),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Featured Manage Sheet ──────────────────────────────────────────────────────
class _FeaturedManageSheet extends StatefulWidget {
  final AdminUser user;
  final AdminService svc;
  final int featuredCreditPrice;
  final ScaffoldMessengerState? messenger;
  const _FeaturedManageSheet({required this.user, required this.svc, this.featuredCreditPrice = 200, this.messenger});

  @override
  State<_FeaturedManageSheet> createState() => _FeaturedManageSheetState();
}

class _FeaturedManageSheetState extends State<_FeaturedManageSheet> {
  int _credits = 0;
  DateTime _scheduleDate = DateTime.now();
  String _scheduleCity = '';
  bool _scheduling = false;

  AdminUser get _user => widget.svc.users.firstWhere((u) => u.id == widget.user.id);

  int get _available => _user.featuredPointsPurchased - _user.featuredPointsUsed;

  @override
  void initState() {
    super.initState();
    _scheduleCity = widget.user.city;
    widget.svc.addListener(_onUpdate);
  }

  @override
  void dispose() {
    widget.svc.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() => setState(() {});

  Future<void> _applyCredits() async {
    if (_credits == 0) return;
    if (_credits > 0) {
      await widget.svc.addFeaturedCredits(_user.id, _credits, pricePerCredit: widget.featuredCreditPrice);
    } else {
      final canRemove = _user.featuredPointsPurchased - _user.featuredPointsUsed;
      final toRemove = (-_credits).clamp(0, canRemove);
      if (toRemove <= 0) return;
      widget.svc.removeFeaturedCredits(_user.id, toRemove);
    }
    HapticFeedback.mediumImpact();
    if (mounted) setState(() => _credits = 0);
  }

  Future<void> _schedulePost() async {
    if (_scheduling) return;
    setState(() => _scheduling = true);
    final city = _scheduleCity.isNotEmpty ? _scheduleCity : (SupabaseService.instance.citiesList.isNotEmpty ? SupabaseService.instance.citiesList.first : 'Lahore');
    final messenger = widget.messenger ?? ScaffoldMessenger.of(context);
    final err = await widget.svc.scheduleFeaturedPost(_user.id, _scheduleDate, city);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    setState(() => _scheduling = false);
    if (err == null) {
    } else {
      final maxPerCity = int.tryParse(SupabaseService.instance.cachedSettings['max_featured_per_city'] ?? '5') ?? 5;
      final msg = err == 'no_credits'
          ? 'No credits available. Add credits first.'
          : err == 'duplicate_city'
              ? 'Already scheduled in $city. Remove it first.'
              : err == 'city_limit'
                  ? '$city already has $maxPerCity featured post${maxPerCity == 1 ? '' : 's'} on that date. Wait for one to expire or pick another date.'
                  : 'Failed: $err';
      messenger.showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: kRose,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ));
    }
  }

  String _fmt(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final schedule = user.featuredSchedule;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F0D1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: kAmber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.star_rounded, color: kAmber, size: 22),
                  ),
                  SizedBox(width: _S.of(context).s(12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Featured Credits',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                        Text(user.name,
                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.45))),
                      ],
                    ),
                  ),
                  // Balance badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _available > 0 ? kAmber.withOpacity(0.12) : kRose.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _available > 0 ? kAmber.withOpacity(0.3) : kRose.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      '$_available available',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _available > 0 ? kAmber : kRose,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: _S.of(context).s(4)),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(_S.of(context).s(20), _S.of(context).s(12), _S.of(context).s(20), _S.of(context).s(30)),
                children: [
                  // ── Credits Box ──
                  Container(
                    padding: EdgeInsets.all(_S.of(context).s(16)),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16132A),
                      borderRadius: BorderRadius.circular(_S.of(context).s(16)),
                      border: Border.all(color: kAmber.withOpacity(0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Each credit = Rs. ${widget.featuredCreditPrice}  •  Available: $_available',
                          style: TextStyle(fontSize: _S.of(context).f(12), color: Colors.white.withOpacity(0.4)),
                        ),
                        SizedBox(height: _S.of(context).s(14)),
                        Row(
                          children: [
                            _CircleBtn(
                              icon: Icons.remove_rounded,
                              color: kRose,
                              onTap: () => setState(() {
                                if (_credits > -20) _credits--;
                              }),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    _credits == 0 ? '0' : (_credits > 0 ? '+$_credits' : '$_credits'),
                                    style: TextStyle(
                                      fontSize: _S.of(context).f(32),
                                      fontWeight: FontWeight.w900,
                                      color: _credits > 0 ? kAmber : _credits < 0 ? kRose : Colors.white.withOpacity(0.3),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  Text(
                                    _credits == 0
                                        ? 'no change'
                                        : _credits > 0
                                            ? 'add ${_credits} credit${_credits > 1 ? "s" : ""}  •  Rs.${_credits * widget.featuredCreditPrice}'
                                            : 'remove ${-_credits} credit${-_credits > 1 ? "s" : ""}  •  Rs.${-_credits * widget.featuredCreditPrice}',
                                    style: TextStyle(
                                      fontSize: _S.of(context).f(12),
                                      color: _credits > 0
                                          ? kAmber.withOpacity(0.8)
                                          : _credits < 0
                                              ? kRose.withOpacity(0.8)
                                              : Colors.white.withOpacity(0.25),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            _CircleBtn(
                              icon: Icons.add_rounded,
                              color: kGreen,
                              onTap: () => setState(() {
                                if (_credits < 20) _credits++;
                              }),
                            ),
                          ],
                        ),
                        SizedBox(height: _S.of(context).s(14)),
                        _ConfirmCreditButton(
                          label: 'Apply',
                          icon: _credits >= 0 ? Icons.add_rounded : Icons.remove_rounded,
                          colors: _credits != 0
                              ? const [kPurple, kPurpleDeep]
                              : [Colors.white12, Colors.white10],
                          disabled: _credits == 0,
                          onTap: _applyCredits,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: _S.of(context).s(20)),

                  // ── Schedule Post Box ──
                  _sectionLabel('Schedule Featured Post', Icons.calendar_month_rounded, kPurple),
                  SizedBox(height: _S.of(context).s(10)),
                  Container(
                    padding: EdgeInsets.all(_S.of(context).s(16)),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16132A),
                      borderRadius: BorderRadius.circular(_S.of(context).s(16)),
                      border: Border.all(
                        color: _available > 0 ? kPurple.withOpacity(0.15) : kRose.withOpacity(0.15),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_available <= 0)
                          Container(
                            padding: EdgeInsets.all(_S.of(context).s(10)),
                            margin: EdgeInsets.only(bottom: _S.of(context).s(12)),
                            decoration: BoxDecoration(
                              color: kRose.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(_S.of(context).s(10)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: kRose, size: _S.of(context).d(16)),
                                SizedBox(width: _S.of(context).s(8)),
                                Text(
                                  'Add credits above to schedule a post',
                                  style: TextStyle(fontSize: _S.of(context).f(12), color: kRose.withOpacity(0.8)),
                                ),
                              ],
                            ),
                          ),
                        // Location selector (Pakistan / Overseas, searchable)
                        _AdminLocationPicker(
                          value: _scheduleCity.isNotEmpty ? _scheduleCity : null,
                          onChanged: (v) { if (v != null) setState(() => _scheduleCity = v); },
                        ),
                        SizedBox(height: _S.of(context).s(12)),
                        // Date field
                        _AdminDateField(
                          date: _scheduleDate,
                          onTap: _available > 0 ? () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _scheduleDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              builder: (ctx, child) => Theme(
                                data: ThemeData.dark().copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: kPurple,
                                    surface: Color(0xFF16132A),
                                  ),
                                ),
                                child: child!,
                              ),
                            );
                            if (picked != null) {
                              final now = DateTime.now();
                              final isToday = picked.year == now.year &&
                                  picked.month == now.month &&
                                  picked.day == now.day;
                              if (mounted) setState(() => _scheduleDate = isToday
                                ? now // today = start now
                                : DateTime(picked.year, picked.month, picked.day, 0, 0) // future = midnight
                              );
                            }
                          } : null,
                        ),
                        SizedBox(height: _S.of(context).s(14)),
                        // Schedule button
                        GestureDetector(
                          onTap: (_scheduling || _available <= 0) ? null : _schedulePost,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: double.infinity,
                            height: _S.of(context).d(44),
                            decoration: BoxDecoration(
                              gradient: (_scheduling || _available <= 0)
                                ? LinearGradient(colors: [kPurple.withOpacity(0.35), kPurpleDeep.withOpacity(0.35)])
                                : LinearGradient(colors: [kPurple, kPurpleDeep]),
                              borderRadius: BorderRadius.circular(_S.of(context).s(12)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_scheduling)
                                  SizedBox(width: _S.of(context).d(18), height: _S.of(context).d(18), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                else
                                  Icon(Icons.check_rounded, color: Colors.white.withOpacity(_available <= 0 ? 0.5 : 1), size: _S.of(context).d(18)),
                                SizedBox(width: _S.of(context).s(8)),
                                Text(
                                  _scheduling ? 'Scheduling...' : 'Schedule',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(_available <= 0 ? 0.5 : 1),
                                    fontWeight: FontWeight.w800,
                                    fontSize: _S.of(context).f(14),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: _S.of(context).s(20)),

                  // ── Schedule List ──
                  if (schedule.isNotEmpty) ...[
                    _sectionLabel('Scheduled Posts (${schedule.length})', Icons.list_rounded, kTeal),
                    SizedBox(height: _S.of(context).s(10)),
                    // Sort: live first, then upcoming, then completed
                    ...(() {
                      final indexed = schedule.asMap().entries.toList();
                      indexed.sort((a, b) {
                        int rank(FeaturedBoost boost) {
                          if (boost.isActive) return 0;
                          if (!boost.isCompleted) return 1;
                          return 2;
                        }
                        return rank(a.value).compareTo(rank(b.value));
                      });
                      return indexed.map((e) {
                        final i = e.key;
                        final boost = e.value;
                        return _BoostListItem(
                          boost: boost,
                          fallbackCity: user.city,
                          onRemove: () {
                            HapticFeedback.lightImpact();
                            widget.svc.removeFeaturedSchedule(user.id, i);
                          },
                        );
                      });
                    })(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: _S.of(context).d(16)),
        SizedBox(width: _S.of(context).s(8)),
        Text(title, style: TextStyle(fontSize: _S.of(context).f(14), fontWeight: FontWeight.w700, color: Colors.white)),
      ],
    );
  }

  Widget _vDivider() {
    final s = _S.of(context);
    return Container(width: 1, height: s.d(28), color: Colors.white.withOpacity(0.1), margin: EdgeInsets.symmetric(horizontal: s.s(8)));
  }
}

class _SheetStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SheetStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: s.f(13), fontWeight: FontWeight.w800, color: color), textAlign: TextAlign.center),
          SizedBox(height: s.s(2)),
          Text(label, style: TextStyle(fontSize: s.f(9.5), color: Colors.white.withOpacity(0.35)), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: s.d(44), height: s.d(44),
        decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle, border: Border.all(color: color.withOpacity(0.3))),
        child: Icon(icon, color: color, size: s.d(22)),
      ),
    );
  }
}

// A button that animates to a checkmark briefly to confirm the action was done
class _ConfirmCreditButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final List<Color> colors;
  final bool disabled;
  final VoidCallback onTap;
  const _ConfirmCreditButton({
    required this.label,
    required this.icon,
    required this.colors,
    required this.disabled,
    required this.onTap,
  });

  @override
  State<_ConfirmCreditButton> createState() => _ConfirmCreditButtonState();
}

class _ConfirmCreditButtonState extends State<_ConfirmCreditButton> {
  bool _confirmed = false;

  void _handleTap() {
    if (widget.disabled || _confirmed) return;
    widget.onTap();
    setState(() => _confirmed = true);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _confirmed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final isDisabled = widget.disabled && !_confirmed;
    final List<Color> activeColors = _confirmed ? [Colors.white10, Colors.white10] : isDisabled ? [Colors.white12, Colors.white10] : widget.colors;

    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity, height: s.d(44),
        decoration: BoxDecoration(gradient: LinearGradient(colors: activeColors), borderRadius: BorderRadius.circular(s.s(12))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(widget.icon, color: isDisabled || _confirmed ? Colors.white24 : Colors.white, size: s.d(18)),
            ),
            SizedBox(width: s.s(6)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(_confirmed ? widget.label : widget.label, key: ValueKey(_confirmed),
                style: TextStyle(color: isDisabled ? Colors.white24 : Colors.white, fontWeight: FontWeight.w800, fontSize: s.f(14))),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Admin City Picker (searchable, dark themed) ────────────────────────────────
// ── Admin Location Picker (Pakistan / Overseas) ─────────────────────────────
// Added alongside the featured-post location choice already live in the
// website and user app: a Pakistan/Overseas toggle, then either qualifying
// Pakistani cities (grouped by province) or qualifying overseas countries,
// both fetched LIVE from the same shared Supabase RPCs the website and user
// app use (get_qualifying_cities / get_qualifying_countries) — not a
// separately hand-maintained list, so all three surfaces can never drift
// out of sync with each other again. This does NOT replace _AdminCityPicker
// below (left fully intact — it's used for the user's home-city field
// elsewhere, unrelated to Featured); this is a new, separate widget used
// only for scheduling a Featured post.
class _AdminLocationPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _AdminLocationPicker({required this.value, required this.onChanged});

  void _open(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _AdminLocationSheet(
        selected: value,
        onSelect: (v) { onChanged(v); Navigator.pop(context); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final hasValue = value != null && value!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Location', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(6)),
        GestureDetector(
          onTap: () => _open(context),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(13)),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(12)), border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: Row(
              children: [
                Expanded(child: Text(hasValue ? value! : 'Select city or country',
                  style: TextStyle(fontSize: s.f(13.5), color: hasValue ? Colors.white : Colors.white38, fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400))),
                Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: s.d(22)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminLocationSheet extends StatefulWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _AdminLocationSheet({required this.selected, required this.onSelect});

  @override
  State<_AdminLocationSheet> createState() => _AdminLocationSheetState();
}

class _AdminLocationSheetState extends State<_AdminLocationSheet> {
  String _query = '';
  final _ctrl = TextEditingController();
  bool _isOverseas = false;
  bool _loading = true;
  String? _error;
  Map<String, List<String>> _cityGroups = {};
  List<String> _countries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final client = SupabaseService.instance.client;
      final cityRows = await client.rpc('get_qualifying_cities') as List;
      final countryRows = await client.rpc('get_qualifying_countries') as List;

      final groups = <String, List<String>>{};
      for (final row in cityRows) {
        final province = row['province'] as String;
        final city = row['city'] as String;
        groups.putIfAbsent(province, () => []).add(city);
      }
      final countries = countryRows.map((r) => r['country'] as String).toList();

      if (!mounted) return;
      setState(() {
        _cityGroups = groups;
        _countries = countries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not load locations. Please try again.'; });
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final q = _query.trim().toLowerCase();

    final filteredCities = <String, List<String>>{};
    _cityGroups.forEach((province, cities) {
      final matches = q.isEmpty ? cities : cities.where((c) => c.toLowerCase().contains(q)).toList();
      if (matches.isNotEmpty) filteredCities[province] = matches;
    });
    final filteredCountries = q.isEmpty ? _countries : _countries.where((c) => c.toLowerCase().contains(q)).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(color: Color(0xFF0F0D1A), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        children: [
          SizedBox(height: s.s(10)),
          Container(width: s.d(40), height: s.d(4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(2)))),
          Padding(
            padding: EdgeInsets.fromLTRB(s.s(20), s.s(14), s.s(20), 0),
            child: Row(
              children: [
                Text('Select Location', style: TextStyle(fontSize: s.f(17), fontWeight: FontWeight.w800, color: Colors.white)),
                const Spacer(),
                if (widget.selected != null)
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(fontSize: s.f(13), color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          SizedBox(height: s.s(12)),
          // Pakistan / Overseas toggle — same two-step pattern as the
          // website and user app. Switching modes clears any in-progress
          // search but keeps the currently-selected value untouched.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: s.s(20)),
            child: Row(children: [
              Expanded(child: _AdminLocationModeButton(label: 'Pakistan', selected: !_isOverseas, onTap: () => setState(() => _isOverseas = false))),
              SizedBox(width: s.s(8)),
              Expanded(child: _AdminLocationModeButton(label: 'Overseas', selected: _isOverseas, onTap: () => setState(() => _isOverseas = true))),
            ]),
          ),
          SizedBox(height: s.s(12)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: s.s(16)),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(2)),
              decoration: BoxDecoration(color: const Color(0xFF16132A), borderRadius: BorderRadius.circular(s.s(14)), border: Border.all(color: Colors.white.withOpacity(0.1))),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: s.d(20), color: Colors.white.withOpacity(0.3)),
                  SizedBox(width: s.s(8)),
                  Expanded(
                    child: TextField(
                      controller: _ctrl, autofocus: false,
                      onChanged: (v) => setState(() => _query = v),
                      style: TextStyle(fontSize: s.f(14), color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _isOverseas ? 'Search country...' : 'Search city...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: s.f(14)),
                        border: InputBorder.none, isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: s.s(12)),
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () { _ctrl.clear(); setState(() => _query = ''); },
                      child: Icon(Icons.close_rounded, size: s.d(18), color: Colors.white.withOpacity(0.3)),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: s.s(8)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kPurple))
                : _error != null
                    ? Center(child: Padding(
                        padding: EdgeInsets.all(s.s(20)),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.5))),
                          SizedBox(height: s.s(12)),
                          TextButton(onPressed: _load, child: const Text('Retry')),
                        ]),
                      ))
                    : _isOverseas
                        ? (filteredCountries.isEmpty
                            ? Center(child: Text('No matching countries', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: s.f(14))))
                            : ListView(
                                padding: EdgeInsets.fromLTRB(s.s(16), s.s(4), s.s(16), s.s(24)),
                                children: filteredCountries.map((country) {
                                  final isSelected = country == widget.selected;
                                  return GestureDetector(
                                    onTap: () => widget.onSelect(country),
                                    child: Container(
                                      margin: EdgeInsets.only(bottom: s.s(4)),
                                      padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(12)),
                                      decoration: BoxDecoration(
                                        color: isSelected ? kPurple.withOpacity(0.15) : const Color(0xFF16132A),
                                        borderRadius: BorderRadius.circular(s.s(12)),
                                        border: Border.all(color: isSelected ? kPurple.withOpacity(0.4) : Colors.white.withOpacity(0.06)),
                                      ),
                                      child: Row(children: [
                                        Expanded(child: Text(country, style: TextStyle(fontSize: s.f(14), color: isSelected ? kPurple : Colors.white.withOpacity(0.85), fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400))),
                                        if (isSelected) Icon(Icons.check_rounded, color: kPurple, size: s.d(18)),
                                      ]),
                                    ),
                                  );
                                }).toList(),
                              ))
                        : (filteredCities.isEmpty
                            ? Center(child: Text('No matching cities', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: s.f(14))))
                            : ListView(
                                padding: EdgeInsets.fromLTRB(s.s(16), s.s(4), s.s(16), s.s(24)),
                                children: [
                                  for (final entry in filteredCities.entries) ...[
                                    Padding(
                                      padding: EdgeInsets.fromLTRB(s.s(4), s.s(12), s.s(4), s.s(6)),
                                      child: Text(entry.key, style: TextStyle(fontSize: s.f(11), fontWeight: FontWeight.w700, color: kPurple.withOpacity(0.8), letterSpacing: 0.5)),
                                    ),
                                    ...entry.value.map((city) {
                                      final isSelected = city == widget.selected;
                                      return GestureDetector(
                                        onTap: () => widget.onSelect(city),
                                        child: Container(
                                          margin: EdgeInsets.only(bottom: s.s(4)),
                                          padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(12)),
                                          decoration: BoxDecoration(
                                            color: isSelected ? kPurple.withOpacity(0.15) : const Color(0xFF16132A),
                                            borderRadius: BorderRadius.circular(s.s(12)),
                                            border: Border.all(color: isSelected ? kPurple.withOpacity(0.4) : Colors.white.withOpacity(0.06)),
                                          ),
                                          child: Row(children: [
                                            Expanded(child: Text(city, style: TextStyle(fontSize: s.f(14), color: isSelected ? kPurple : Colors.white.withOpacity(0.85), fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400))),
                                            if (isSelected) Icon(Icons.check_rounded, color: kPurple, size: s.d(18)),
                                          ]),
                                        ),
                                      );
                                    }),
                                  ],
                                ],
                              )),
          ),
        ],
      ),
    );
  }
}

class _AdminLocationModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AdminLocationModeButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: s.s(10)),
        decoration: BoxDecoration(
          color: selected ? kPurple.withOpacity(0.18) : const Color(0xFF16132A),
          borderRadius: BorderRadius.circular(s.s(10)),
          border: Border.all(color: selected ? kPurple.withOpacity(0.5) : Colors.white.withOpacity(0.08)),
        ),
        child: Text(label, textAlign: TextAlign.center,
          style: TextStyle(fontSize: s.f(13), fontWeight: FontWeight.w700, color: selected ? kPurple : Colors.white.withOpacity(0.5))),
      ),
    );
  }
}

class _AdminCityPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _AdminCityPicker({required this.value, required this.onChanged});

  void _open(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _AdminCitySheet(
        selected: value,
        onSelect: (v) { onChanged(v); Navigator.pop(context); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final hasValue = value != null && value!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('City', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(6)),
        GestureDetector(
          onTap: () => _open(context),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(13)),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(12)), border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: Row(
              children: [
                Expanded(child: Text(hasValue ? value! : 'Select city',
                  style: TextStyle(fontSize: s.f(13.5), color: hasValue ? Colors.white : Colors.white38, fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400))),
                Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: s.d(22)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminCitySheet extends StatefulWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _AdminCitySheet({required this.selected, required this.onSelect});

  @override
  State<_AdminCitySheet> createState() => _AdminCitySheetState();
}

class _AdminCitySheetState extends State<_AdminCitySheet> {
  String _query = '';
  final _ctrl = TextEditingController();

  Map<String, List<String>> get _filtered {
    if (_query.isEmpty) return SupabaseService.instance.citiesGrouped;
    final q = _query.toLowerCase();
    final result = <String, List<String>>{};
    for (final entry in SupabaseService.instance.citiesGrouped.entries) {
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
      child: Column(
        children: [
          SizedBox(height: s.s(10)),
          Container(width: s.d(40), height: s.d(4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(2)))),
          Padding(
            padding: EdgeInsets.fromLTRB(s.s(20), s.s(14), s.s(20), 0),
            child: Row(
              children: [
                Text('Select City', style: TextStyle(fontSize: s.f(17), fontWeight: FontWeight.w800, color: Colors.white)),
                const Spacer(),
                if (widget.selected != null)
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(fontSize: s.f(13), color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          SizedBox(height: s.s(12)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: s.s(16)),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(2)),
              decoration: BoxDecoration(color: const Color(0xFF16132A), borderRadius: BorderRadius.circular(s.s(14)), border: Border.all(color: Colors.white.withOpacity(0.1))),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: s.d(20), color: Colors.white.withOpacity(0.3)),
                  SizedBox(width: s.s(8)),
                  Expanded(
                    child: TextField(
                      controller: _ctrl, autofocus: false,
                      onChanged: (v) => setState(() => _query = v),
                      style: TextStyle(fontSize: s.f(14), color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search city...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: s.f(14)),
                        border: InputBorder.none, isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: s.s(12)),
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () { _ctrl.clear(); setState(() => _query = ''); },
                      child: Icon(Icons.close_rounded, size: s.d(18), color: Colors.white.withOpacity(0.3)),
                    ),
                ],
              ),
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
                          final isSelected = city == widget.selected;
                          return GestureDetector(
                            onTap: () => widget.onSelect(city),
                            child: Container(
                              margin: EdgeInsets.only(bottom: s.s(4)),
                              padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(12)),
                              decoration: BoxDecoration(
                                color: isSelected ? kPurple.withOpacity(0.15) : const Color(0xFF16132A),
                                borderRadius: BorderRadius.circular(s.s(12)),
                                border: Border.all(color: isSelected ? kPurple.withOpacity(0.4) : Colors.white.withOpacity(0.06)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(child: Text(city, style: TextStyle(fontSize: s.f(14), color: isSelected ? kPurple : Colors.white.withOpacity(0.85), fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400))),
                                  if (isSelected) Icon(Icons.check_rounded, color: kPurple, size: s.d(18)),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Admin Date Field ───────────────────────────────────────────────────────────
class _AdminDateField extends StatelessWidget {
  final DateTime date;
  final VoidCallback? onTap;
  const _AdminDateField({required this.date, required this.onTap});

  String _fmt(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final enabled = onTap != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Date', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(6)),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(13)),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(12)), border: Border.all(color: Colors.white.withOpacity(enabled ? 0.1 : 0.05))),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: s.d(16), color: enabled ? kPurple.withOpacity(0.8) : Colors.white24),
                SizedBox(width: s.s(10)),
                Expanded(child: Text(_fmt(date), style: TextStyle(fontSize: s.f(13.5), color: enabled ? Colors.white : Colors.white38, fontWeight: FontWeight.w600))),
                Icon(Icons.edit_calendar_rounded, size: s.d(16), color: enabled ? Colors.white38 : Colors.white12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Boost List Item with live countdown ───────────────────────────────────────
class _BoostListItem extends StatefulWidget {
  final FeaturedBoost boost;
  final String fallbackCity;
  final VoidCallback onRemove;
  const _BoostListItem({
    required this.boost,
    required this.fallbackCity,
    required this.onRemove,
  });

  @override
  State<_BoostListItem> createState() => _BoostListItemState();
}

class _BoostListItemState extends State<_BoostListItem> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _remaining = widget.boost.timeRemaining;
    if (widget.boost.isActive) {
      // tick every second while active
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final r = widget.boost.timeRemaining;
        if (mounted) setState(() => _remaining = r);
        if (r == Duration.zero) _timer?.cancel();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmtDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _fmtRemaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${h}h ${m}m ${s}s remaining';
  }

  @override
  Widget build(BuildContext context) {
    final boost = widget.boost;
    final city = boost.city.isNotEmpty ? boost.city : widget.fallbackCity;

    Color borderColor;
    Color iconBg;
    Color iconColor;
    IconData iconData;

    if (boost.isCompleted) {
      borderColor = Colors.white.withOpacity(0.06);
      iconBg = Colors.white.withOpacity(0.06);
      iconColor = Colors.white38;
      iconData = Icons.check_rounded;
    } else if (boost.isActive) {
      borderColor = kGreen.withOpacity(0.3);
      iconBg = kGreen.withOpacity(0.12);
      iconColor = kGreen;
      iconData = Icons.star_rounded;
    } else {
      borderColor = kAmber.withOpacity(0.2);
      iconBg = kAmber.withOpacity(0.12);
      iconColor = kAmber;
      iconData = Icons.schedule_rounded;
    }

    return Container(
      margin: EdgeInsets.only(bottom: _S.of(context).s(8)),
      padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(14), vertical: _S.of(context).s(12)),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(_S.of(context).s(14)),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: _S.of(context).d(38), height: _S.of(context).d(38),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(_S.of(context).s(10)),
                ),
                child: Icon(iconData, color: iconColor, size: _S.of(context).d(18)),
              ),
              SizedBox(width: _S.of(context).s(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fmtDate(boost.scheduledDate),
                      style: TextStyle(
                        fontSize: _S.of(context).f(13.5),
                        fontWeight: FontWeight.w700,
                        color: boost.isCompleted
                            ? Colors.white.withOpacity(0.35)
                            : Colors.white,
                      ),
                    ),
                    Text(
                      '$city  •  24 hrs',
                      style: TextStyle(
                        fontSize: _S.of(context).f(11.5),
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
              ),
              if (boost.isCompleted)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(8), vertical: _S.of(context).s(3)),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(_S.of(context).s(8)),
                  ),
                  child: Text('Completed',
                      style: TextStyle(fontSize: _S.of(context).f(10), color: Colors.white38,
                          fontWeight: FontWeight.w700)),
                )
              else if (boost.isActive)
                Row(children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: _S.of(context).s(8), vertical: _S.of(context).s(3)),
                    decoration: BoxDecoration(
                      color: kGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(_S.of(context).s(8)),
                      border: Border.all(color: kGreen.withOpacity(0.3)),
                    ),
                    child: Text('Live',
                        style: TextStyle(fontSize: _S.of(context).f(10), color: kGreen,
                            fontWeight: FontWeight.w700)),
                  ),
                  SizedBox(width: _S.of(context).s(6)),
                  GestureDetector(
                    onTap: widget.onRemove,
                    child: Container(
                      padding: EdgeInsets.all(_S.of(context).s(6)),
                      decoration: BoxDecoration(
                        color: kRose.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(_S.of(context).s(8)),
                      ),
                      child: Icon(Icons.close_rounded, color: kRose, size: _S.of(context).d(14)),
                    ),
                  ),
                ])
              else
                GestureDetector(
                  onTap: widget.onRemove,
                  child: Container(
                    padding: EdgeInsets.all(_S.of(context).s(6)),
                    decoration: BoxDecoration(
                      color: kRose.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(_S.of(context).s(8)),
                    ),
                    child: Icon(Icons.close_rounded, color: kRose, size: _S.of(context).d(14)),
                  ),
                ),
            ],
          ),
          // Live countdown bar for active boosts
          if (boost.isActive) ...[
            SizedBox(height: _S.of(context).s(10)),
            // Progress bar
            LayoutBuilder(builder: (_, constraints) {
              final total = const Duration(hours: 24).inSeconds.toDouble();
              final elapsed = (total - _remaining.inSeconds.toDouble()).clamp(0.0, total);
              final progress = elapsed / total;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(_S.of(context).s(4)),
                    child: Stack(
                      children: [
                        Container(
                          height: _S.of(context).d(4),
                          width: constraints.maxWidth,
                          color: kGreen.withOpacity(0.15),
                        ),
                        Container(
                          height: _S.of(context).d(4),
                          width: constraints.maxWidth * progress,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [kGreen.withOpacity(0.7), kGreen],
                            ),
                            borderRadius: BorderRadius.circular(_S.of(context).s(4)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: _S.of(context).s(5)),
                  Text(
                    _fmtRemaining(_remaining),
                    style: TextStyle(
                      fontSize: _S.of(context).f(11),
                      fontWeight: FontWeight.w600,
                      color: kGreen.withOpacity(0.8),
                    ),
                  ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }
}
