import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/theme.dart';
import '../services/supabase_service.dart';
import '../utils/realtime_refresh.dart';
import '../models/admin_permissions.dart';
import 'admin_blog_screen.dart';
import 'admin_ads_screen.dart';

SupabaseClient get _db => SupabaseService.instance.client;

// Preset monogram/knot colors — same 5-color rotation used everywhere
// else on the site for avatar initials (ProposalCard.tsx on the
// website), so a color picked here looks consistent, not like a separate
// palette invented just for this screen.
const List<(Color, String)> _kSwatches = [
  (kPurple, '#534AB7'),
  (kTeal, '#0F6E56'),
  (kAmber, '#E8620A'),
  (Color(0xFF0369A1), '#0369A1'),
  (kRose, '#E11D48'),
];

Color _hexToColor(String? hex) {
  if (hex == null || hex.isEmpty) return kPurple;
  final clean = hex.replaceAll('#', '');
  return Color(int.parse('FF$clean', radix: 16));
}

// ─────────────────────────────────────────────────────────────────────────────
//  AdminTestimonialsScreen — the "Content" tab: Stories and Blog Posts, each
//  its own collapsible card, stacked in one scrollable screen. Each card is
//  fully self-contained (its own load/add/edit/delete), so adding further
//  content types later is just another card here.
// ─────────────────────────────────────────────────────────────────────────────
class AdminTestimonialsScreen extends StatefulWidget {
  final void Function(VoidCallback)? onRefreshCallback;
  const AdminTestimonialsScreen({super.key, this.onRefreshCallback});
  @override
  State<AdminTestimonialsScreen> createState() => _AdminTestimonialsScreenState();
}

class _AdminTestimonialsScreenState extends State<AdminTestimonialsScreen> {
  VoidCallback? _refreshStories;
  VoidCallback? _refreshBlog;
  VoidCallback? _refreshData;

  @override
  void initState() {
    super.initState();
    // The dashboard header's refresh button re-syncs all cards from the
    // database at once when tapped on this tab.
    widget.onRefreshCallback?.call(() {
      _refreshStories?.call();
      _refreshBlog?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1E),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const ViewOnlyBanner(pageKey: AdminPageKeys.content),
          _StoriesCard(onRefreshCallback: (cb) => _refreshStories = cb),
          const SizedBox(height: 16),
          AdminBlogCard(onRefreshCallback: (cb) => _refreshBlog = cb),
          const SizedBox(height: 16),
          const DataManagementCard(),
          const SizedBox(height: 16),
          const MessageTemplatesCard(),
        ]),
      ),
    );
  }
}

// ── Stories card ────────────────────────────────────────────────────────────
//  Manages the "Real Rishta Stories" page on the website: add, edit,
//  remove, and drag-reorder entries. Reads/writes the 'testimonials' table
//  directly (same pattern as AdminLocationsScreen's 'jor_centers'), ordered
//  by sort_order.
class _StoriesCard extends StatefulWidget {
  final void Function(VoidCallback)? onRefreshCallback;
  const _StoriesCard({this.onRefreshCallback});
  @override
  State<_StoriesCard> createState() => _StoriesCardState();
}

class _StoriesCardState extends State<_StoriesCard> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  // Collapsed by default — same idea as the collapsible sections on the
  // Pricing screen. Empty set = everything collapsed; tapping a card's
  // header toggles just that one.
  final Set<String> _expandedIds = {};
  // Whether the whole Stories card is expanded — same chevron pattern as
  // the Pricing screen's collapsible sections, just applied to the entire
  // card here rather than per-row.
  bool _cardExpanded = false;
  AutoRefreshSync? _sync;

  @override
  void initState() {
    super.initState();
    widget.onRefreshCallback?.call(_load);
    _load();
    _sync = subscribeAutoRefresh(
      client: _db,
      channelName: 'admin-sync-testimonials',
      tables: const ['testimonials'],
      onChange: () { if (mounted) _load(); },
    );
  }

  @override
  void dispose() {
    _sync?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _db.from('testimonials').select().order('sort_order');
      setState(() { _items = List<Map<String, dynamic>>.from(res); _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _showForm({Map<String, dynamic>? existing}) {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.content, what: 'adding or editing stories')) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TestimonialForm(existing: existing, nextSortOrder: _items.length, onSaved: _load),
    );
  }

  Future<void> _delete(String id) async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.content, what: 'deleting stories')) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A35),
        title: const Text('Delete story?', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        content: const Text('This will permanently remove it from the website.', style: TextStyle(color: Colors.white54, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: kRose, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true) return;
    await _db.from('testimonials').delete().eq('id', id);
    _load();
  }

  Future<void> _togglePublished(Map<String, dynamic> item) async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.content, what: 'publishing stories')) return;
    final current = item['is_published'] as bool? ?? true;
    setState(() {
      final idx = _items.indexWhere((c) => c['id'] == item['id']);
      if (idx != -1) _items[idx] = {..._items[idx], 'is_published': !current};
    });
    try {
      await _db.from('testimonials').update({'is_published': !current}).eq('id', item['id']);
    } catch (e) {
      setState(() {
        final idx = _items.indexWhere((c) => c['id'] == item['id']);
        if (idx != -1) _items[idx] = {..._items[idx], 'is_published': current};
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e', style: const TextStyle(color: Colors.white, fontSize: 12)),
          backgroundColor: kRose, behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.content, what: 'reordering stories')) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = _items.removeAt(oldIndex);
      _items.insert(newIndex, moved);
    });
    // Persist the new order — each row's sort_order becomes its new index.
    // Small list (testimonials rarely run into the hundreds), so plain
    // sequential updates are fine; no need for a bulk RPC.
    try {
      for (var i = 0; i < _items.length; i++) {
        if ((_items[i]['sort_order'] as num?)?.toInt() != i) {
          await _db.from('testimonials').update({'sort_order': i}).eq('id', _items[i]['id']);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save new order: $e', style: const TextStyle(color: Colors.white, fontSize: 12)),
          backgroundColor: kRose, behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      // Always shrink-wraps to whatever it's actually showing — just the
      // header when collapsed, header + exactly as many rows as there are
      // when expanded — rather than stretching to fill the whole screen
      // regardless of how much content there is. The page itself scrolls
      // (via the outer SingleChildScrollView) if the list ever gets
      // taller than the screen.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
        // — Card header: title, the "+" to add, and a chevron that
        //    collapses/expands the whole card (tap anywhere on the
        //    header except the + button) —
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _cardExpanded = !_cardExpanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.format_quote_rounded, color: kPurple, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Stories', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white))),
              GestureDetector(
                onTap: () => _showForm(),
                child: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(9)),
                  child: Icon(Icons.add_rounded, color: kPurple, size: 18),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedRotation(
                turns: _cardExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.4), size: 22),
              ),
            ]),
          ),
        ),
        if (_cardExpanded) ...[
        Container(height: 1, color: Colors.white.withOpacity(0.08)),
        // — Body: loading / error / empty / the list, all inside this one card —
        _loading
          ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: kPurple)))
          : _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline_rounded, size: 40, color: kRose.withOpacity(0.6)),
                  const SizedBox(height: 10),
                  Text(
                    "Couldn't load stories from the database. Pull to retry, or check your connection.\n\n$_error",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  TextButton(onPressed: _load, child: const Text('Retry', style: TextStyle(color: kPurple, fontWeight: FontWeight.w700))),
                ]),
              )
            : _items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(28),
                  child: Center(child: Text('No stories yet — tap + above to add one', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13))),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _items.length,
                  onReorder: _onReorder,
                  // ReorderableListView's default drag proxy wraps the
                  // dragged item in an opaque white Material surface —
                  // fine on a light theme, but it shows as a stray
                  // white card behind everything on this dark one.
                  // Rendering it on a transparent Material instead
                  // keeps this card's own dark background visible
                  // while a row is being dragged.
                    proxyDecorator: (child, index, animation) => Material(
                      color: Colors.transparent,
                      child: child,
                    ),
                    itemBuilder: (_, i) {
                      final item = _items[i];
                      final id = item['id'] as String;
                      final expanded = _expandedIds.contains(id);
                      final published = item['is_published'] as bool? ?? true;
                      final color = _hexToColor(item['color'] as String?);
                      final isLast = i == _items.length - 1;
                      return Column(
                        key: ValueKey(id),
                        children: [
                          // — Collapsed header row — always visible, tap to expand/collapse —
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() {
                              if (expanded) { _expandedIds.remove(id); } else { _expandedIds.add(id); }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
                              child: Row(children: [
                                Container(
                                  width: 34, height: 34,
                                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                                  alignment: Alignment.center,
                                  child: Text(item['initials'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(item['names'] ?? '',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: published ? Colors.white : Colors.white38, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text('${item['city'] ?? ''} · ${published ? 'Live' : 'Hidden'}',
                                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35), fontWeight: FontWeight.w600)),
                                ])),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => _togglePublished(item),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 36, height: 20,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: published ? kPurple : Colors.white.withOpacity(0.15),
                                    ),
                                    child: AnimatedAlign(
                                      duration: const Duration(milliseconds: 200),
                                      alignment: published ? Alignment.centerRight : Alignment.centerLeft,
                                      child: Container(
                                        width: 16, height: 16,
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 6),
                                ReorderableDragStartListener(
                                  index: i,
                                  child: Icon(Icons.drag_handle_rounded, size: 18, color: Colors.white.withOpacity(0.3)),
                                ),
                                AnimatedRotation(
                                  turns: expanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.4), size: 22),
                                ),
                              ]),
                            ),
                          ),
                          // — Expanded body — quote, date, edit/delete —
                          if (expanded) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(
                                  item['quote'] ?? '',
                                  style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.5, fontStyle: FontStyle.italic),
                                ),
                                const SizedBox(height: 8),
                                Text(item['when_label'] ?? '', style: TextStyle(fontSize: 11.5, color: kTeal.withOpacity(0.9), fontWeight: FontWeight.w600)),
                                const SizedBox(height: 12),
                                Row(children: [
                                  GestureDetector(
                                    onTap: () => _showForm(existing: item),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                                      ),
                                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.edit_rounded, size: 11, color: Colors.white70),
                                        SizedBox(width: 4),
                                        Text('Edit', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70)),
                                      ]),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _delete(id),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: kRose.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(color: kRose.withOpacity(0.2)),
                                      ),
                                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.delete_outline_rounded, size: 11, color: kRose),
                                        SizedBox(width: 4),
                                        Text('Delete', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kRose)),
                                      ]),
                                    ),
                                  ),
                                ]),
                              ]),
                            ),
                          ],
                          if (!isLast) Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Container(height: 1, color: Colors.white.withOpacity(0.06)),
                          ),
                        ],
                      );
                    },
                  ),
        ],
      ]),
    );
  }
}

// ── Add / Edit Form ────────────────────────────────────────────────────────────
class _TestimonialForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final int nextSortOrder;
  final VoidCallback onSaved;
  const _TestimonialForm({this.existing, required this.nextSortOrder, required this.onSaved});
  @override
  State<_TestimonialForm> createState() => _TestimonialFormState();
}

class _TestimonialFormState extends State<_TestimonialForm> {
  late final TextEditingController _quote, _names, _city, _when, _initials;
  late String _colorHex;
  bool _published = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _quote    = TextEditingController(text: e?['quote']      ?? '');
    _names    = TextEditingController(text: e?['names']      ?? '');
    _city     = TextEditingController(text: e?['city']       ?? '');
    _when     = TextEditingController(text: e?['when_label'] ?? '');
    _initials = TextEditingController(text: e?['initials']   ?? '');
    _colorHex = (e?['color'] as String?) ?? '#534AB7';
    _published = e?['is_published'] as bool? ?? true;
  }

  @override
  void dispose() {
    _quote.dispose(); _names.dispose(); _city.dispose();
    _when.dispose(); _initials.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_quote.text.trim().isEmpty || _names.text.trim().isEmpty ||
        _city.text.trim().isEmpty || _when.text.trim().isEmpty ||
        _initials.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }
    setState(() => _saving = true);
    final data = {
      'quote':       _quote.text.trim(),
      'names':       _names.text.trim(),
      'city':        _city.text.trim(),
      'when_label':  _when.text.trim(),
      'initials':    _initials.text.trim(),
      'color':       _colorHex,
      'is_published': _published,
    };
    try {
      if (widget.existing != null) {
        await _db.from('testimonials').update(data).eq('id', widget.existing!['id']);
      } else {
        await _db.from('testimonials').insert({...data, 'sort_order': widget.nextSortOrder});
      }
      if (mounted) { Navigator.pop(context); widget.onSaved(); }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1A35),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + safeBottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(isEdit ? 'Edit Story' : 'Add Story',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.4), size: 22),
              ),
            ]),
            const SizedBox(height: 16),
            _Field(ctrl: _quote, label: 'Quote', hint: 'What they said, in their own words', maxLines: 4),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _Field(ctrl: _names, label: 'Names', hint: 'Sara & Hamza')),
              const SizedBox(width: 10),
              SizedBox(width: 90, child: _Field(ctrl: _initials, label: 'Initials', hint: 'S+H')),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _Field(ctrl: _city, label: 'City', hint: 'Lahore')),
              const SizedBox(width: 10),
              Expanded(child: _Field(ctrl: _when, label: 'When', hint: 'Nikah · Nov 2025')),
            ]),
            const SizedBox(height: 14),
            Text('Color', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 8),
            Row(children: _kSwatches.map((swatch) {
              final c = swatch.$1;
              final hex = swatch.$2;
              final selected = hex == _colorHex;
              return GestureDetector(
                onTap: () => setState(() => _colorHex = hex),
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: c, shape: BoxShape.circle,
                    border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2.5),
                  ),
                  child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 16) : null,
                ),
              );
            }).toList()),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text('Published on website', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7)))),
              GestureDetector(
                onTap: () => setState(() => _published = !_published),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 36, height: 20,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: _published ? kPurple : Colors.white.withOpacity(0.15),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: _published ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: 16, height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _saving ? null : _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kPurple, kPurpleDeep]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(isEdit ? 'Save Changes' : 'Add Story',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Small helper ───────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final int maxLines;
  const _Field({required this.ctrl, required this.label, required this.hint, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
      const SizedBox(height: 5),
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 13),
          filled: true,
          fillColor: Colors.black.withOpacity(0.25),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPurple)),
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Data Management Card — Castes, Cities, Occupations
//  Lets admin add/delete entries directly from the app. All three apps
//  (user app, admin app, website) fetch from the same DB tables so changes
//  reflect everywhere automatically on next refresh.
// ══════════════════════════════════════════════════════════════════════════════

// ── Verification Settings Card ────────────────────────────────────────────────
// Controls which verification sections are shown in the proposal form
// (user app + website). Each toggle writes to app_settings in Supabase
// so changes sync instantly across all platforms.
class VerificationSettingsCard extends StatefulWidget {
  final void Function(VoidCallback)? onRefreshCallback;
  final String title;
  final String keyCandidateCnic;
  final String keyLatestDegree;
  final String keyParentsCnic;
  final String keyRequireAll;
  final String keyCandidateCnicCompulsory;
  final String keyLatestDegreeCompulsory;
  final String keyParentsCnicCompulsory;

  const VerificationSettingsCard({
    super.key,
    this.onRefreshCallback,
    this.title = 'Verification Settings',
    this.keyCandidateCnic = 'require_candidate_cnic',
    this.keyLatestDegree  = 'require_latest_degree',
    this.keyParentsCnic   = 'require_parents_cnic',
    this.keyRequireAll    = 'require_verification_step',
    this.keyCandidateCnicCompulsory = 'require_candidate_cnic_compulsory',
    this.keyLatestDegreeCompulsory  = 'require_latest_degree_compulsory',
    this.keyParentsCnicCompulsory   = 'require_parents_cnic_compulsory',
  });
  @override State<VerificationSettingsCard> createState() => _VerificationSettingsCardState();
}

class _VerificationSettingsCardState extends State<VerificationSettingsCard> {
  bool _loading = true;
  bool _candidateCnic           = true;
  bool _latestDegree            = true;
  bool _parentsCnic             = true;
  bool _requireVerifStep        = false;
  bool _candidateCnicCompulsory = true;
  bool _latestDegreeCompulsory  = false;
  bool _parentsCnicCompulsory   = true;
  bool _badgeEnabled            = true;

  static const _keySectionLabel = 'verify_now_section_label';
  final _sectionLabelController = TextEditingController();
  bool _savingLabel = false;

  String get _keyCandidateCnic           => widget.keyCandidateCnic;
  String get _keyLatestDegree            => widget.keyLatestDegree;
  String get _keyParentsCnic             => widget.keyParentsCnic;
  String get _keyRequireVerifStep        => widget.keyRequireAll;
  String get _keyCandidateCnicCompulsory => widget.keyCandidateCnicCompulsory;
  String get _keyLatestDegreeCompulsory  => widget.keyLatestDegreeCompulsory;
  String get _keyParentsCnicCompulsory   => widget.keyParentsCnicCompulsory;
  static const _keyBadgeEnabled = 'verification_badge_enabled';

  @override
  void initState() {
    super.initState();
    widget.onRefreshCallback?.call(_load);
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _db.from('app_settings').select('key, value') as List;
      final map = { for (final r in rows) r['key'] as String: r['value'] as String };
      if (mounted) setState(() {
        _candidateCnic           = (map[_keyCandidateCnic]           ?? 'true')  != 'false';
        _latestDegree            = (map[_keyLatestDegree]            ?? 'true')  != 'false';
        _parentsCnic             = (map[_keyParentsCnic]             ?? 'true')  != 'false';
        _requireVerifStep        = (map[_keyRequireVerifStep]        ?? 'false') == 'true';
        _candidateCnicCompulsory = (map[_keyCandidateCnicCompulsory] ?? 'true')  != 'false';
        _latestDegreeCompulsory  = (map[_keyLatestDegreeCompulsory]  ?? 'false') == 'true';
        _parentsCnicCompulsory   = (map[_keyParentsCnicCompulsory]   ?? 'true')  != 'false';
        _badgeEnabled            = (map[_keyBadgeEnabled]            ?? 'true')  != 'false';
        _sectionLabelController.text = map[_keySectionLabel] ?? 'PARENT / GUARDIAN / CANDIDATE';
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _editingLabel = false;

  void _showEditLabelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Section Label', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Shown above CNIC fields on web & user app', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: _sectionLabelController,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'PARENT / GUARDIAN / CANDIDATE',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPurple)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          StatefulBuilder(builder: (ctx2, setSt) => TextButton(
            onPressed: _savingLabel ? null : () async {
              setSt(() {});
              await _saveSectionLabel();
              if (ctx2.mounted) Navigator.pop(ctx2);
            },
            child: _savingLabel
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kPurple))
              : const Text('Save', style: TextStyle(color: kPurple, fontWeight: FontWeight.w800)),
          )),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sectionLabelController.dispose();
    super.dispose();
  }

  Future<void> _toggle(String key, bool value) async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.verification, what: 'changing verification settings')) return;
    try {
      await _db.rpc('admin_upsert_setting', params: {'p_key': key, 'p_value': value.toString()});
      await SupabaseService.instance.fetchAppSettings();
    } catch (_) {}
  }

  Future<void> _saveSectionLabel() async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.verification, what: 'changing verification settings')) return;
    final label = _sectionLabelController.text.trim();
    if (label.isEmpty) return;
    setState(() => _savingLabel = true);
    try {
      await _db.rpc('admin_upsert_setting', params: {'p_key': _keySectionLabel, 'p_value': label});
      await SupabaseService.instance.fetchAppSettings();
    } catch (_) {}
    if (mounted) setState(() => _savingLabel = false);
  }

  Widget _subRow(String label, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 4, top: 2),
      child: Row(children: [
        Container(width: 2, height: 30, color: kPurple.withOpacity(0.3), margin: const EdgeInsets.only(right: 10)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white70)),
          Text(subtitle, style: TextStyle(fontSize: 10.5, color: Colors.white.withOpacity(0.35))),
        ])),
        Switch(value: value, onChanged: onChanged, activeColor: kGreen,
          inactiveThumbColor: Colors.white24, inactiveTrackColor: Colors.white10),
      ]),
    );
  }

  Widget _row(String label, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.45))),
        ])),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: kPurple,
          inactiveThumbColor: Colors.white24,
          inactiveTrackColor: Colors.white10,
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(children: [
        // Header (non-collapsible)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.admin_panel_settings_rounded, color: kPurple, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white))),
          ]),
        ),
        Divider(height: 1, color: Colors.white.withOpacity(0.07)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _loading
            ? const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(strokeWidth: 2, color: kPurple)))
            : Column(children: [
                // Candidate CNIC row with pen icon to edit section label
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Text('Candidate CNIC', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _showEditLabelDialog(context),
                          child: const Icon(Icons.edit_rounded, size: 14, color: kPurple),
                        ),
                      ]),
                      const SizedBox(height: 3),
                      const Text('CNIC front & back of the marriage-seeking person', style: TextStyle(fontSize: 11.5, color: Colors.white54)),
                    ])),
                    Switch(
                      value: _candidateCnic,
                      onChanged: (v) { setState(() => _candidateCnic = v); _toggle(_keyCandidateCnic, v); },
                      activeColor: kPurple,
                      inactiveThumbColor: Colors.white24,
                      inactiveTrackColor: Colors.white10,
                    ),
                  ]),
                ),
                if (_candidateCnic) _subRow('Compulsory', 'Must be uploaded before proceeding',
                  _candidateCnicCompulsory, (v) { setState(() => _candidateCnicCompulsory = v); _toggle(_keyCandidateCnicCompulsory, v); }),
                _row('Education Document', 'Latest degree or certificate of the marriage-seeking person', _latestDegree,
                  (v) { setState(() => _latestDegree = v); _toggle(_keyLatestDegree, v); }),
                if (_latestDegree) _subRow('Compulsory', 'Must be uploaded before proceeding',
                  _latestDegreeCompulsory, (v) { setState(() => _latestDegreeCompulsory = v); _toggle(_keyLatestDegreeCompulsory, v); }),
                _row('Parents / Guardian CNIC', 'CNIC front & back of the parent or guardian submitting this profile', _parentsCnic,
                  (v) { setState(() => _parentsCnic = v); _toggle(_keyParentsCnic, v); }),
                if (_parentsCnic) _subRow('Compulsory', 'Must be uploaded before proceeding',
                  _parentsCnicCompulsory, (v) { setState(() => _parentsCnicCompulsory = v); _toggle(_keyParentsCnicCompulsory, v); }),

              ]),
        ),
      ]),
    );
  }
}

// ── Verification Badge on/off card ────────────────────────────────────────
class VerificationBadgeCard extends StatefulWidget {
  const VerificationBadgeCard({super.key});
  @override State<VerificationBadgeCard> createState() => _VerificationBadgeCardState();
}

class _VerificationBadgeCardState extends State<VerificationBadgeCard> {
  bool _enabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = SupabaseService.instance;
    final res = await db.client.from('app_settings').select('key,value')
      .eq('key', 'verification_badge_enabled').maybeSingle();
    if (!mounted) return;
    setState(() {
      _enabled = (res?['value'] ?? 'true') != 'false';
      _loading = false;
    });
  }

  Future<void> _toggle(bool v) async {
    setState(() => _enabled = v);
    await SupabaseService.instance.client.from('app_settings')
      .upsert({'key': 'verification_badge_enabled', 'value': v ? 'true' : 'false'});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1A33),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 3, height: 16, color: kPurple, margin: const EdgeInsets.only(right: 8)),
          const Expanded(child: Text('Verification Badge', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white))),
        ]),
        const SizedBox(height: 12),
        if (_loading) const Center(child: CircularProgressIndicator())
        else Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Show Verified Badge', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 3),
            Text('Display a verified badge next to the user name when all compulsory docs are approved by admin',
              style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.45), height: 1.4)),
          ])),
          Switch(
            value: _enabled,
            onChanged: _toggle,
            activeColor: kGreen,
            inactiveThumbColor: Colors.white24,
            inactiveTrackColor: Colors.white10,
          ),
        ]),
      ]),
    );
  }
}

class DataManagementCard extends StatefulWidget {
  const DataManagementCard({super.key});
  @override State<DataManagementCard> createState() => _DataManagementCardState();
}

class _DataManagementCardState extends State<DataManagementCard> {
  bool _cardExpanded = false;
  int _tab = 0; // 0=Castes 1=Cities 2=Occupations

  // Data
  List<Map<String, dynamic>> _castes      = [];
  List<Map<String, dynamic>> _cities      = [];
  List<Map<String, dynamic>> _occupations = [];
  bool _loading = false;

  // Groups
  static const _casteGroups = ['Punjab','Sindh','KPK / Pashtun','Kashmir & Northern','Balochistan','Urdu-speaking / Muhajir','General'];
  static const _cityProvinces = ['Punjab','Sindh','KPK','Balochistan','Islamabad','Gilgit Baltistan','Azad Kashmir'];
  static const _occCategories = ['Healthcare','Engineering','IT & Tech','Education','Finance & Law','Business & Management','Government & Forces','Arts & Media','Skilled Trades','Services & Other','Other'];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _db.from('castes').select().order('group_order').order('sort_order'),
        _db.from('cities').select().order('sort_order'),
        _db.from('occupations').select().order('sort_order'),
      ]);
      if (!mounted) return;
      setState(() {
        _castes      = List<Map<String, dynamic>>.from(results[0]);
        _cities      = List<Map<String, dynamic>>.from(results[1]);
        _occupations = List<Map<String, dynamic>>.from(results[2]);
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _delete(String table, dynamic id) async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.content, what: 'deleting list items')) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A35),
        title: const Text('Delete entry?', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        content: const Text('This removes it from the dropdown. Existing profiles with this value are unaffected.', style: TextStyle(color: Colors.white54, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: kRose, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.from(table).delete().eq('id', id);
    _load();
    SupabaseService.instance.fetchCastes();
    SupabaseService.instance.fetchCities();
    SupabaseService.instance.fetchOccupations();
  }

  void _showAddDialog() {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.content, what: 'adding list items')) return;
    final names = ['Castes', 'Cities', 'Occupations'];
    final tables = ['castes', 'cities', 'occupations'];
    final groups = [_casteGroups, _cityProvinces, _occCategories];
    final groupLabels = ['Group', 'Province', 'Category'];
    final table = tables[_tab];
    final groupList = groups[_tab];
    final groupLabel = groupLabels[_tab];

    String name = '';
    String group = groupList.first;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: const Color(0xFF1E1A35),
          title: Text('Add to ${names[_tab]}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
          content: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Name',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.15)), borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: kPurple), borderRadius: BorderRadius.circular(8)),
                  filled: true, fillColor: Colors.white.withOpacity(0.05),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                onChanged: (v) => name = v,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: group,
                dropdownColor: const Color(0xFF1E1A35),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: groupLabel,
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.15)), borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: kPurple), borderRadius: BorderRadius.circular(8)),
                  filled: true, fillColor: Colors.white.withOpacity(0.05),
                ),
                items: groupList.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) { if (v != null) setS(() => group = v); },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
            TextButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(ctx);
                // Confirmation
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1A35),
                    title: Text('Add "${name.trim()}"?', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    content: Text('This will add it to the $group group and make it available in all apps immediately.',
                        style: const TextStyle(color: Colors.white54, fontSize: 13)),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add', style: TextStyle(color: kPurple, fontWeight: FontWeight.w800))),
                    ],
                  ),
                );
                if (confirmed != true) return;
                final Map<String, dynamic> row;
                if (table == 'castes') {
                  row = {'name': name.trim(), 'group_name': group, 'sort_order': 99, 'group_order': _casteGroups.indexOf(group) + 1};
                } else if (table == 'cities') {
                  row = {'name': name.trim(), 'province': group, 'sort_order': 99};
                } else {
                  row = {'name': name.trim(), 'category': group, 'sort_order': 99};
                }
                await _db.from(table).insert(row);
                _load();
                SupabaseService.instance.fetchCastes();
                SupabaseService.instance.fetchCities();
                SupabaseService.instance.fetchOccupations();
              },
              child: const Text('Add', style: TextStyle(color: kPurple, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = [_castes, _cities, _occupations][_tab];
    final groupKey = ['group_name', 'province', 'category'][_tab];
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final g = item[groupKey] as String? ?? 'Other';
      grouped.putIfAbsent(g, () => []).add(item);
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(children: [
        // Header
        InkWell(
          onTap: () => setState(() => _cardExpanded = !_cardExpanded),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.tune_rounded, color: kPurple, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Data Management', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                Text('Castes · Cities · Occupations', style: TextStyle(fontSize: 12, color: Colors.white38)),
              ])),
              Icon(_cardExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: Colors.white38, size: 22),
            ]),
          ),
        ),

        if (_cardExpanded) ...[
          Divider(height: 1, color: Colors.white.withOpacity(0.07)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              // Tab selector
              Container(
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                child: Row(children: ['Castes', 'Cities', 'Occupations'].asMap().entries.map((e) {
                  final selected = _tab == e.key;
                  return Expanded(child: GestureDetector(
                    onTap: () => setState(() => _tab = e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: selected ? kPurple : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(e.value, textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                              color: selected ? Colors.white : Colors.white38)),
                    ),
                  ));
                }).toList()),
              ),
              const SizedBox(height: 14),

              // Add button
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${items.length} entries', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
                TextButton.icon(
                  onPressed: _showAddDialog,
                  icon: const Icon(Icons.add_rounded, size: 16, color: kPurple),
                  label: const Text('Add New', style: TextStyle(color: kPurple, fontWeight: FontWeight.w700, fontSize: 13)),
                  style: TextButton.styleFrom(
                    backgroundColor: kPurple.withOpacity(0.12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ]),
              const SizedBox(height: 10),

              if (_loading)
                const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: kPurple))
              else
                ...grouped.entries.map((group) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 6),
                      child: Text(group.key.toUpperCase(),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800,
                              color: kPurple.withOpacity(0.8), letterSpacing: 0.8)),
                    ),
                    ...group.value.map((item) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(children: [
                        Expanded(child: Text(item['name'] as String? ?? '',
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                        GestureDetector(
                          onTap: () => _delete(
                            ['castes','cities','occupations'][_tab],
                            item['id'],
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: kRose.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                            child: const Icon(Icons.delete_outline_rounded, size: 15, color: kRose),
                          ),
                        ),
                      ]),
                    )),
                  ],
                )),
            ]),
          ),
        ],
      ]),
    );
  }
}


// ── Message Templates Card ───────────────────────────────────────────────────
// Allows admin to edit the WhatsApp message templates used in profile view
// screen copy buttons. Templates are stored in app_settings:
//   ai_profile_message     — copy icon on AI (inactive) profiles
//   pending_profile_message — copy icon on doc_pending profiles (Pending chip)
// Use [NUMBER] as placeholder for the profile number.
class MessageTemplatesCard extends StatefulWidget {
  const MessageTemplatesCard({super.key});
  @override State<MessageTemplatesCard> createState() => _MessageTemplatesCardState();
}

class _MessageTemplatesCardState extends State<MessageTemplatesCard> {
  // Same card background used by Stories/Data Management above it, so
  // this card doesn't look like a slightly different shade in the stack.
  static const _kCard = Color(0xFF16132A);

  // Collapsed by default — same collapsible-card pattern used by the
  // other sections on this tab (Stories, Data Management): tap the
  // header to expand/collapse, chevron flips to show state.
  bool _cardExpanded = false;
  bool _loading = true;
  bool _saving  = false;
  final _aiCtrl      = TextEditingController();
  final _pendingCtrl = TextEditingController();

  static const _aiDefault =
      'Your rishta proposal is currently listed on Jor.\n\n'
      '\u{1F449} View Your Profile:\n'
      'https://joronline.com/profile/[NUMBER]\n\n'
      'Reply \u201Cclaim\u201D to manage your profile for free or \u201Cremove\u201D to remove it from Jor.';

  static const _pendingDefault =
      'Your marriage proposal is currently listed on Jor\n\n'
      '\u{1F517} View your profile:\n'
      'https://joronline.com/profile/[NUMBER]\n\n'
      'To start your rishta search and connect with families, please complete the verification process by logging in at:\n'
      '\u{1F449} https://joronline.com/login\n\n'
      'Or download our mobile app:\n'
      '\u{1F449} joronline.com/get-android\n\n'
      'For any questions, feel free to reply here.\n\n'
      'Jor Team\n'
      'joronline.com';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _aiCtrl.dispose();
    _pendingCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await SupabaseService.instance.fetchAppSettings();
    if (!mounted) return;
    setState(() {
      _aiCtrl.text      = s['ai_profile_message']      ?? _aiDefault;
      _pendingCtrl.text = s['pending_profile_message'] ?? _pendingDefault;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.content, what: 'editing message templates')) return;
    setState(() => _saving = true);
    try {
      final client = SupabaseService.instance.client;
      await client.from('app_settings').upsert({'key': 'ai_profile_message',      'value': _aiCtrl.text.trim()});
      await client.from('app_settings').upsert({'key': 'pending_profile_message', 'value': _pendingCtrl.text.trim()});
      await SupabaseService.instance.fetchAppSettings();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Templates saved ✓'), backgroundColor: Color(0xFF16A34A), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(children: [
        // Header — same collapsible pattern as Data Management: icon,
        // title + subtitle, chevron. Tap anywhere to expand/collapse.
        InkWell(
          onTap: () => setState(() => _cardExpanded = !_cardExpanded),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: SvgPicture.asset('assets/icons/whatsapp.svg', width: 20, height: 20, colorFilter: const ColorFilter.mode(kPurple, BlendMode.srcIn)),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Message Templates', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                Text('AI Profile · Pending Profile', style: TextStyle(fontSize: 12, color: Colors.white38)),
              ])),
              Icon(_cardExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: Colors.white38, size: 22),
            ]),
          ),
        ),

        if (_cardExpanded) ...[
          Divider(height: 1, color: Colors.white.withOpacity(0.07)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Use [NUMBER] as placeholder for profile number.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(height: 16),
                    _label('AI Profile Message (purple copy icon)'),
                    const SizedBox(height: 6),
                    _field(_aiCtrl),
                    const SizedBox(height: 16),
                    _label('Pending Profile Message (amber copy icon)'),
                    const SizedBox(height: 6),
                    _field(_pendingCtrl),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: _saving ? null : _save,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(10)),
                          child: _saving
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Save Templates', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ]),
          ),
        ],
      ]),
    );
  }

  Widget _label(String text) => Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600));

  Widget _field(TextEditingController ctrl) => TextField(
    controller: ctrl,
    maxLines: 6,
    style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.6),
    decoration: InputDecoration(
      fillColor: const Color(0xFF0F0D1E),
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.08))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPurple)),
      contentPadding: const EdgeInsets.all(12),
    ),
  );
}
