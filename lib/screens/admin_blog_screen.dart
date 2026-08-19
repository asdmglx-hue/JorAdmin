import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/theme.dart';
import '../services/supabase_service.dart';
import '../models/admin_permissions.dart';
import '../utils/realtime_refresh.dart';

SupabaseClient get _blogDb => SupabaseService.instance.client;

// Blog's own accent color — purple, matching the site's overall theme.
const Color _kBlogAccent = kPurple;

// ── Auto-SEO helpers ─────────────────────────────────────────────────────
// Everything below turns a plain title + content into the metadata a
// search engine actually cares about, with zero extra input from the
// admin — this is the "every post gets optimized automatically" part.

// Common English + Urdu-context stopwords, skipped when picking keywords
// out of the title so what's left is the words actually worth ranking
// for (e.g. "rishta", "wedding", "lahore" survive; "the", "a", "for" don't).
const Set<String> _kStopwords = {
  'a', 'an', 'the', 'is', 'are', 'was', 'were', 'be', 'been', 'to', 'of',
  'in', 'on', 'at', 'for', 'and', 'or', 'but', 'with', 'your', 'you',
  'how', 'why', 'what', 'when', 'this', 'that', 'it', 'its', 'from',
  'by', 'as', 'their', 'my', 'our', 'we', 'i', 'do', 'does', 'did',
};

String slugify(String title) {
  var s = title.toLowerCase().trim();
  s = s.replaceAll(RegExp(r"['\u2018\u2019]"), ''); // drop apostrophes rather than turning them into hyphens
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  s = s.replaceAll(RegExp(r'-+'), '-');
  s = s.replaceAll(RegExp(r'^-|-$'), '');
  return s.isEmpty ? 'post' : s;
}

/// Finds a slug based on [title] that isn't already taken, by checking
/// the database and appending -2, -3, ... only if the plain version
/// collides with an existing post.
Future<String> uniqueSlug(String title) async {
  final base = slugify(title);
  final res = await _blogDb.from('blog_posts').select('slug').ilike('slug', '$base%');
  final taken = (res as List).map((r) => r['slug'] as String).toSet();
  if (!taken.contains(base)) return base;
  var i = 2;
  while (taken.contains('$base-$i')) {
    i++;
  }
  return '$base-$i';
}

/// Strips the lightweight formatting syntax the blog content field
/// supports (## / ### headings, **bold**, [text](url), - bullets) down to
/// plain readable text — used for the excerpt/meta description, which
/// should never show raw "##" or "**" characters even if the post body
/// uses them for structure.
String _stripLightFormatting(String text) {
  var s = text;
  s = s.replaceAll(RegExp(r'^#{2,3}\s+', multiLine: true), '');
  s = s.replaceAll(RegExp(r'^[-*]\s+', multiLine: true), '');
  s = s.replaceAllMapped(RegExp(r'\*\*(.+?)\*\*'), (m) => m.group(1) ?? '');
  s = s.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1) ?? '');
  return s;
}

/// First ~155 characters of [content] (the length Google typically shows
/// in a search snippet), cut at a word boundary rather than mid-word.
String autoExcerpt(String content, {int maxLen = 155}) {
  final flat = _stripLightFormatting(content).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= maxLen) return flat;
  final cut = flat.substring(0, maxLen);
  final lastSpace = cut.lastIndexOf(' ');
  return '${cut.substring(0, lastSpace > 0 ? lastSpace : maxLen).trimRight()}\u2026';
}

int autoReadTimeMinutes(String content) {
  final wordCount = content.trim().isEmpty ? 0 : content.trim().split(RegExp(r'\s+')).length;
  return (wordCount / 200).ceil().clamp(1, 999);
}

List<String> autoKeywords(String title, String category) {
  final words = '$title $category'
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .split(RegExp(r'\s+'))
      .where((w) => w.length > 2 && !_kStopwords.contains(w));
  final seen = <String>{};
  final result = <String>[];
  for (final w in words) {
    if (seen.add(w)) result.add(w);
    if (result.length >= 8) break;
  }
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
//  AdminBlogCard — manage the website's Blog. Same collapsible-card shape
//  as the Stories card above it, but sorted newest-first by published_at
//  instead of a manual drag order (blogs read naturally in reverse
//  chronological order, so there's nothing to reorder). Reads/writes the
//  'blog_posts' table.
// ─────────────────────────────────────────────────────────────────────────────
class AdminBlogCard extends StatefulWidget {
  final void Function(VoidCallback)? onRefreshCallback;
  const AdminBlogCard({super.key, this.onRefreshCallback});
  @override
  State<AdminBlogCard> createState() => _AdminBlogCardState();
}

class _AdminBlogCardState extends State<AdminBlogCard> {
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  String? _error;
  final Set<String> _expandedIds = {};
  bool _cardExpanded = false;
  AutoRefreshSync? _sync;

  @override
  void initState() {
    super.initState();
    widget.onRefreshCallback?.call(_load);
    _load();
    _sync = subscribeAutoRefresh(
      client: _blogDb,
      channelName: 'admin-sync-blog',
      tables: const ['blog_posts'],
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
      final res = await _blogDb.from('blog_posts').select().order('published_at', ascending: false);
      setState(() { _posts = List<Map<String, dynamic>>.from(res); _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _showForm({Map<String, dynamic>? existing}) {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.content, what: 'adding or editing posts')) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BlogPostForm(existing: existing, onSaved: _load),
    );
  }

  Future<void> _delete(String id) async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.content, what: 'deleting posts')) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A35),
        title: const Text('Delete post?', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        content: const Text('This will permanently remove it from the website.', style: TextStyle(color: Colors.white54, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: kRose, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true) return;
    await _blogDb.from('blog_posts').delete().eq('id', id);
    _load();
  }

  Future<void> _togglePublished(Map<String, dynamic> post) async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.content, what: 'publishing posts')) return;
    final current = post['is_published'] as bool? ?? true;
    setState(() {
      final idx = _posts.indexWhere((p) => p['id'] == post['id']);
      if (idx != -1) _posts[idx] = {..._posts[idx], 'is_published': !current};
    });
    try {
      await _blogDb.from('blog_posts').update({'is_published': !current}).eq('id', post['id']);
    } catch (e) {
      setState(() {
        final idx = _posts.indexWhere((p) => p['id'] == post['id']);
        if (idx != -1) _posts[idx] = {..._posts[idx], 'is_published': current};
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

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _cardExpanded = !_cardExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: _kBlogAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.article_rounded, color: _kBlogAccent, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Blog', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white))),
                GestureDetector(
                  onTap: () => _showForm(),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(color: _kBlogAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(9)),
                    child: Icon(Icons.add_rounded, color: _kBlogAccent, size: 18),
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
          _loading
            ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: _kBlogAccent)))
            : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.error_outline_rounded, size: 40, color: kRose.withOpacity(0.6)),
                    const SizedBox(height: 10),
                    Text(
                      "Couldn't load posts from the database. Pull to retry, or check your connection.\n\n$_error",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.5),
                    ),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Retry', style: TextStyle(color: _kBlogAccent, fontWeight: FontWeight.w700))),
                  ]),
                )
              : _posts.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Center(child: Text('No posts yet — tap + above to add one', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13))),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: _posts.length,
                    itemBuilder: (_, i) {
                      final post = _posts[i];
                      final id = post['id'] as String;
                      final expanded = _expandedIds.contains(id);
                      final published = post['is_published'] as bool? ?? true;
                      final isLast = i == _posts.length - 1;
                      return Column(
                        key: ValueKey(id),
                        children: [
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
                                  decoration: BoxDecoration(color: _kBlogAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.article_outlined, color: _kBlogAccent, size: 16),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(post['title'] ?? '',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: published ? Colors.white : Colors.white38, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text('${_fmtDate(post['published_at'] as String?)} · ${post['read_time_minutes'] ?? 1} min · ${published ? 'Live' : 'Hidden'}',
                                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35), fontWeight: FontWeight.w600)),
                                ])),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => _togglePublished(post),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 36, height: 20,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: published ? _kBlogAccent : Colors.white.withOpacity(0.15),
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
                                const SizedBox(width: 6),
                                AnimatedRotation(
                                  turns: expanded ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.4), size: 22),
                                ),
                              ]),
                            ),
                          ),
                          if (expanded) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if ((post['category'] as String?)?.isNotEmpty == true) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(color: _kBlogAccent.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                                    child: Text(post['category'], style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: _kBlogAccent)),
                                  ),
                                ],
                                Text(
                                  post['excerpt'] ?? '',
                                  style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.5),
                                ),
                                const SizedBox(height: 6),
                                Text('SEO: slug "${post['slug']}" · ${(post['keywords'] as List?)?.join(', ') ?? ''}',
                                  style: TextStyle(fontSize: 10.5, color: Colors.white.withOpacity(0.3), fontStyle: FontStyle.italic)),
                                const SizedBox(height: 12),
                                Row(children: [
                                  GestureDetector(
                                    onTap: () => _showForm(existing: post),
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
        ],
      ),
    );
  }
}

// ── Add / Edit Form ────────────────────────────────────────────────────────────
class _BlogPostForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const _BlogPostForm({this.existing, required this.onSaved});
  @override
  State<_BlogPostForm> createState() => _BlogPostFormState();
}

class _BlogPostFormState extends State<_BlogPostForm> {
  late final TextEditingController _title, _content, _category, _author;
  bool _published = true;
  bool _saving = false;
  // Cover image: either a freshly-picked file waiting to be uploaded on
  // save, or the URL already stored from a previous save (when editing).
  // At most one of these is meaningful at a time — picking a new image
  // sets _coverFile and clears _existingCoverUrl from consideration.
  Uint8List? _coverBytes;
  String? _existingCoverUrl;
  bool _uploadingCover = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title    = TextEditingController(text: e?['title']    ?? '');
    _content  = TextEditingController(text: e?['content']  ?? '');
    _category = TextEditingController(text: e?['category'] ?? '');
    _author   = TextEditingController(text: e?['author']   ?? 'Jor Team');
    _existingCoverUrl = e?['cover_image_url'] as String?;
    _published = e?['is_published'] as bool? ?? true;
  }

  @override
  void dispose() {
    _title.dispose(); _content.dispose(); _category.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _pickCoverImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1600);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() { _coverBytes = bytes; _existingCoverUrl = null; });
  }

  void _removeCoverImage() {
    setState(() { _coverBytes = null; _existingCoverUrl = null; });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _content.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title and content are required')));
      return;
    }
    setState(() => _saving = true);

    final title = _title.text.trim();
    final content = _content.text.trim();
    final category = _category.text.trim();

    // Only actually hits the network if a new image was picked — editing
    // a post without touching the cover image just keeps the existing
    // URL as-is.
    String? coverUrl = _existingCoverUrl;
    if (_coverBytes != null) {
      setState(() => _uploadingCover = true);
      try {
        coverUrl = await SupabaseService.instance.uploadBlogCoverImage(_coverBytes!, title);
      } catch (e) {
        setState(() { _saving = false; _uploadingCover = false; });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload cover image: $e')));
        return;
      }
      setState(() => _uploadingCover = false);
    }

    // Every SEO field below is derived automatically from what the admin
    // actually typed — nothing extra to fill in for a post to be
    // well-formed for search engines.
    final excerpt = autoExcerpt(content);
    final data = {
      'title': title,
      'content': content,
      'category': category,
      'author': _author.text.trim().isEmpty ? 'Jor Team' : _author.text.trim(),
      'cover_image_url': coverUrl,
      'excerpt': excerpt,
      'meta_title': title,
      'meta_description': excerpt,
      'keywords': autoKeywords(title, category),
      'read_time_minutes': autoReadTimeMinutes(content),
      'is_published': _published,
    };

    try {
      if (widget.existing != null) {
        // Slug is deliberately left untouched on edits — regenerating it
        // from a changed title would break any link to this post that's
        // already been shared or indexed.
        await _blogDb.from('blog_posts').update(data).eq('id', widget.existing!['id']);
      } else {
        final slug = await uniqueSlug(title);
        await _blogDb.from('blog_posts').insert({...data, 'slug': slug});
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
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1A35),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + safeBottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(isEdit ? 'Edit Post' : 'Add Post',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.4), size: 22),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'Just write the title and content — the SEO title, description, URL, keywords, and read time are all generated automatically when you save.\n\nOptional formatting in Content: start a line with ## for a heading, wrap text in **bold** for emphasis, start lines with - for a bullet list.',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11.5, height: 1.4),
            ),
            const SizedBox(height: 16),
            _BlogField(ctrl: _title, label: 'Title', hint: '10 Things to Ask Before Saying Yes to a Rishta'),
            const SizedBox(height: 10),
            _BlogField(ctrl: _content, label: 'Content', hint: 'Write the full post here. Separate paragraphs with a blank line. ## for a heading, **bold** for emphasis.', maxLines: 12),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _BlogField(ctrl: _category, label: 'Category (optional)', hint: 'Wedding Planning')),
              const SizedBox(width: 10),
              Expanded(child: _BlogField(ctrl: _author, label: 'Author', hint: 'Jor Team')),
            ]),
            const SizedBox(height: 10),
            Text('Cover image (optional)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _uploadingCover ? null : _pickCoverImage,
              child: Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  image: _coverBytes != null
                    ? DecorationImage(image: MemoryImage(_coverBytes!), fit: BoxFit.cover)
                    : (_existingCoverUrl != null
                        ? DecorationImage(image: NetworkImage(_existingCoverUrl!), fit: BoxFit.cover)
                        : null),
                ),
                child: (_coverBytes == null && _existingCoverUrl == null)
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_photo_alternate_outlined, color: Colors.white.withOpacity(0.3), size: 28),
                        const SizedBox(height: 6),
                        Text('Tap to add a cover image', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
                      ]),
                    )
                  : Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: GestureDetector(
                          onTap: _removeCoverImage,
                          child: Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ),
              ),
            ),
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
                    color: _published ? _kBlogAccent : Colors.white.withOpacity(0.15),
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
                    gradient: const LinearGradient(colors: [_kBlogAccent, kPurpleDeep]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(isEdit ? 'Save Changes' : 'Publish Post',
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
class _BlogField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final int maxLines;
  const _BlogField({required this.ctrl, required this.label, required this.hint, this.maxLines = 1});

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
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _kBlogAccent)),
        ),
      ),
    ]);
  }
}
