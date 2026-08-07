// lib/widgets/occupation_picker.dart  (Admin App)
//
// Dark-themed occupation picker for the admin app.
// Identical logic to the user app version but styled for the admin's
// dark background (Color(0xFF0F0D1A)), white text, and purple accent.
//
// Searching by JOB TITLE finds results across all categories instantly.
// Selecting a result returns BOTH category + profession in one tap.
// "Other (my job isn't listed)" is pinned at the top — selecting it
// shows a free-text field for the job title and a real category dropdown.

import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

// ── Scale helper (matches admin screens) ────────────────────────────────────
class _S {
  final double scale;
  const _S(this.scale);
  double f(double size) => size * scale;
  double s(double size) => size * scale;
  double d(double size) => size * scale;
  static _S of(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return _S((w / 390.0).clamp(0.72, 1.0));
  }
}

// ── Colours (admin dark theme) ───────────────────────────────────────────────
const _kPurple     = Color(0xFF7B61FF);
const _kPurpleLight= Color(0xFF1E1A30);
const _kSheetBg    = Color(0xFF0F0D1A);
const _kInputBg    = Color(0xFF16132A);
const _kDivider    = Color(0x22FFFFFF);

// ════════════════════════════════════════════════════════════════════════════
//  Public widget
// ════════════════════════════════════════════════════════════════════════════
class AdminOccupationPicker extends StatefulWidget {
  final String label;
  final String? category;
  final String? profession;
  final void Function(String category, String profession) onSelect;
  final bool isInvalid;

  const AdminOccupationPicker({
    super.key,
    required this.label,
    this.category,
    this.profession,
    required this.onSelect,
    this.isInvalid = false,
  });

  @override
  State<AdminOccupationPicker> createState() => _AdminOccupationPickerState();
}

class _AdminOccupationPickerState extends State<AdminOccupationPicker> {
  void _open() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => _AdminOccupationSheet(
        title: widget.label,
        selectedCategory: widget.category,
        selectedProfession: widget.profession,
        onSelect: (cat, prof) {
          widget.onSelect(cat, prof);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final has = widget.profession != null && widget.profession!.isNotEmpty;
    final hasCategory = widget.category != null && widget.category!.isNotEmpty;
    final displayText = !has
        ? 'Select ${widget.label}'
        : widget.profession == 'Other'
            ? (hasCategory ? 'Other — ${widget.category}' : 'Other — select a category below')
            : '${widget.profession} — ${widget.category}';

    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(widget.label,
              style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(widget.isInvalid ? 0.9 : 0.5))),
          if (widget.isInvalid) ...[
            SizedBox(width: s.s(6)),
            Icon(Icons.error_rounded, color: Colors.redAccent, size: s.d(14)),
          ],
        ]),
        SizedBox(height: s.s(5)),
        GestureDetector(
          onTap: _open,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(13)),
            decoration: BoxDecoration(
              color: widget.isInvalid
                  ? Colors.red.withOpacity(0.1)
                  : Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(s.s(10)),
              border: Border.all(
                color: widget.isInvalid
                    ? Colors.redAccent.withOpacity(0.6)
                    : Colors.white.withOpacity(0.1),
                width: widget.isInvalid ? 1.5 : 1,
              ),
            ),
            child: Row(children: [
              Icon(Icons.work_outline_rounded, size: s.d(18),
                  color: Colors.white.withOpacity(0.35)),
              SizedBox(width: s.s(10)),
              Expanded(
                child: Text(displayText,
                    style: TextStyle(
                        fontSize: s.f(13.5),
                        color: has ? Colors.white : Colors.white38,
                        fontWeight: has ? FontWeight.w600 : FontWeight.w400),
                    overflow: TextOverflow.ellipsis),
              ),
              Icon(Icons.search_rounded, color: Colors.white38, size: s.d(20)),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Bottom-sheet
// ════════════════════════════════════════════════════════════════════════════
class _AdminOccupationSheet extends StatefulWidget {
  final String title;
  final String? selectedCategory;
  final String? selectedProfession;
  final void Function(String category, String profession) onSelect;

  const _AdminOccupationSheet({
    required this.title,
    this.selectedCategory,
    this.selectedProfession,
    required this.onSelect,
  });

  @override
  State<_AdminOccupationSheet> createState() => _AdminOccupationSheetState();
}

class _AdminOccupationSheetState extends State<_AdminOccupationSheet> {
  String _q = '';
  final _ctrl = TextEditingController();

  Map<String, List<String>> get _filtered {
    final source = Map<String, List<String>>.from(
        SupabaseService.instance.occupationsGrouped)..remove('Other');
    if (_q.isEmpty) return source;
    final q = _q.toLowerCase();
    final result = <String, List<String>>{};
    for (final entry in source.entries) {
      final matches = entry.value
          .where((v) => v.toLowerCase().contains(q))
          .toList();
      if (matches.isNotEmpty) result[entry.key] = matches;
    }
    return result;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final groups = _filtered;
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
          color: _kSheetBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        SizedBox(height: s.s(10)),
        Container(
            width: s.d(40), height: s.d(4),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(s.s(2)))),
        Padding(
          padding: EdgeInsets.fromLTRB(s.s(20), s.s(14), s.s(20), 0),
          child: Row(children: [
            Text('Select ${widget.title}',
                style: TextStyle(fontSize: s.f(18), fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ]),
        ),
        SizedBox(height: s.s(12)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: s.s(16)),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(2)),
            decoration: BoxDecoration(
                color: _kInputBg,
                borderRadius: BorderRadius.circular(s.s(14)),
                border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: Row(children: [
              Icon(Icons.search_rounded, size: s.d(20),
                  color: Colors.white38),
              SizedBox(width: s.s(8)),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    hintText: 'Search e.g. Nurse, Teacher, Driver...',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: s.f(14)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: s.s(12)),
                  ),
                  style: TextStyle(fontSize: s.f(14), color: Colors.white),
                ),
              ),
              if (_q.isNotEmpty)
                GestureDetector(
                    onTap: () { _ctrl.clear(); setState(() => _q = ''); },
                    child: Icon(Icons.close_rounded, size: s.d(18),
                        color: Colors.white38)),
            ]),
          ),
        ),
        SizedBox(height: s.s(8)),
        Divider(height: 1, color: _kDivider),
        // Pinned "Other" tile
        InkWell(
          onTap: () => widget.onSelect('', 'Other'),
          child: Container(
            color: widget.selectedProfession == 'Other'
                ? _kPurpleLight
                : Colors.transparent,
            padding: EdgeInsets.symmetric(
                horizontal: s.s(20), vertical: s.s(13)),
            child: Row(children: [
              Icon(Icons.edit_note_rounded, size: s.d(18),
                  color: Colors.white38),
              SizedBox(width: s.s(10)),
              Expanded(
                child: Text(
                  "Other (my job isn't listed)",
                  style: TextStyle(
                    fontSize: s.f(14),
                    fontWeight: widget.selectedProfession == 'Other'
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: widget.selectedProfession == 'Other'
                        ? _kPurple
                        : Colors.white,
                  ),
                ),
              ),
              if (widget.selectedProfession == 'Other')
                Icon(Icons.check_rounded, size: s.d(18), color: _kPurple),
            ]),
          ),
        ),
        Divider(height: 1, color: _kDivider),
        Expanded(
          child: groups.isEmpty
              ? Center(child: Text('No results found',
                  style: TextStyle(color: Colors.white38, fontSize: s.f(14))))
              : ListView(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + s.s(40)),
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                            s.s(20), s.s(16), s.s(20), s.s(6)),
                        child: Text(entry.key,
                            style: TextStyle(
                                fontSize: s.f(12),
                                fontWeight: FontWeight.w800,
                                color: _kPurple,
                                letterSpacing: 0.5)),
                      ),
                      for (final profession in entry.value)
                        _AdminOccupationTile(
                          profession: profession,
                          category: entry.key,
                          selected: widget.selectedCategory == entry.key &&
                              widget.selectedProfession == profession,
                          onTap: () =>
                              widget.onSelect(entry.key, profession),
                        ),
                    ],
                  ],
                ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Individual result tile
// ════════════════════════════════════════════════════════════════════════════
class _AdminOccupationTile extends StatelessWidget {
  final String profession;
  final String category;
  final bool selected;
  final VoidCallback onTap;

  const _AdminOccupationTile({
    required this.profession,
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? _kPurpleLight : Colors.transparent,
        padding: EdgeInsets.symmetric(
            horizontal: s.s(20), vertical: s.s(12)),
        child: Row(children: [
          Expanded(
            child: Text(profession,
                style: TextStyle(
                    fontSize: s.f(14.5),
                    color: selected ? _kPurple : Colors.white,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500)),
          ),
          if (selected)
            Icon(Icons.check_rounded, size: s.d(18), color: _kPurple),
        ]),
      ),
    );
  }
}
