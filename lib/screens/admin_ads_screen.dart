import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/theme.dart';
import '../services/supabase_service.dart';
import '../utils/realtime_refresh.dart';

SupabaseClient get _adsDb => SupabaseService.instance.client;

// ─────────────────────────────────────────────────────────────────────────────
//  AdminAdsCard — manage the website's advertisement slots. Same
//  collapsible-card shape as Stories and Blog. Reads/writes the 'ads'
//  table; media (image or video) uploads straight to Cloudflare R2, same
//  as every other photo in this app — never stored as base64.
// ─────────────────────────────────────────────────────────────────────────────
class AdminAdsCard extends StatefulWidget {
  final void Function(VoidCallback)? onRefreshCallback;
  const AdminAdsCard({super.key, this.onRefreshCallback});
  @override
  State<AdminAdsCard> createState() => _AdminAdsCardState();
}

class _AdminAdsCardState extends State<AdminAdsCard> {
  List<Map<String, dynamic>> _ads = [];
  bool _loading = true;
  String? _error;
  final Set<String> _expandedIds = {};
  AutoRefreshSync? _sync;

  @override
  void initState() {
    super.initState();
    widget.onRefreshCallback?.call(_load);
    _load();
    _sync = subscribeAutoRefresh(
      client: _adsDb,
      channelName: 'admin-sync-ads',
      tables: const ['ads'],
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
      final res = await _adsDb.from('ads').select().order('sort_order').order('created_at', ascending: false);
      setState(() { _ads = List<Map<String, dynamic>>.from(res); _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _showForm({Map<String, dynamic>? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdForm(existing: existing, onSaved: _load),
    );
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A35),
        title: const Text('Delete ad?', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        content: const Text('This will permanently remove it from the website.', style: TextStyle(color: Colors.white54, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: kRose, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm != true) return;
    await _adsDb.from('ads').delete().eq('id', id);
    _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> ad) async {
    final current = ad['is_active'] as bool? ?? true;
    setState(() {
      final idx = _ads.indexWhere((a) => a['id'] == ad['id']);
      if (idx != -1) _ads[idx] = {..._ads[idx], 'is_active': !current};
    });
    try {
      await _adsDb.from('ads').update({'is_active': !current}).eq('id', ad['id']);
    } catch (e) {
      setState(() {
        final idx = _ads.indexWhere((a) => a['id'] == ad['id']);
        if (idx != -1) _ads[idx] = {..._ads[idx], 'is_active': current};
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.campaign_rounded, color: kPurple, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Ads', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white))),
                GestureDetector(
                  onTap: () => _showForm(),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(9)),
                    child: Icon(Icons.add_rounded, color: kPurple, size: 18),
                  ),
                ),
              ]),
            ),
          ),
          Container(height: 1, color: Colors.white.withOpacity(0.08)),
          _loading
            ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: kPurple)))
            : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.error_outline_rounded, size: 40, color: kRose.withOpacity(0.6)),
                    const SizedBox(height: 10),
                    Text(
                      "Couldn't load ads from the database. Pull to retry, or check your connection.\n\n$_error",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.5),
                    ),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Retry', style: TextStyle(color: kPurple, fontWeight: FontWeight.w700))),
                  ]),
                )
              : _ads.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Center(child: Text('No ads yet — tap + above to add one', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13))),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: _ads.length,
                    itemBuilder: (_, i) {
                      final ad = _ads[i];
                      final id = ad['id'] as String;
                      final expanded = _expandedIds.contains(id);
                      final active = ad['is_active'] as bool? ?? true;
                      final isVideo = ad['media_type'] == 'video';
                      final impressions = (ad['impressions'] as num?)?.toInt() ?? 0;
                      final clicks = (ad['clicks'] as num?)?.toInt() ?? 0;
                      final ctr = impressions > 0 ? (clicks / impressions * 100).toStringAsFixed(1) : '—';
                      final isLast = i == _ads.length - 1;
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
                                  decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                                  alignment: Alignment.center,
                                  child: Icon(isVideo ? Icons.videocam_rounded : Icons.image_rounded, color: kPurple, size: 16),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(ad['title'] ?? '',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: active ? Colors.white : Colors.white38, fontSize: 13.5, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text('$impressions views · $clicks clicks · $ctr% CTR · ${active ? 'Live' : 'Hidden'}',
                                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35), fontWeight: FontWeight.w600)),
                                ])),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => _toggleActive(ad),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 36, height: 20,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: active ? kPurple : Colors.white.withOpacity(0.15),
                                    ),
                                    child: AnimatedAlign(
                                      duration: const Duration(milliseconds: 200),
                                      alignment: active ? Alignment.centerRight : Alignment.centerLeft,
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
                                if (!isVideo && (ad['media_url'] as String?)?.isNotEmpty == true)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(ad['media_url'], height: 100, width: double.infinity, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(height: 100, color: Colors.white.withOpacity(0.05))),
                                  ),
                                const SizedBox(height: 8),
                                Text('Links to: ${ad['cta_url'] ?? ''}',
                                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
                                const SizedBox(height: 2),
                                Text('Button says: "${ad['cta_text'] ?? ''}"',
                                  style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.4), fontStyle: FontStyle.italic)),
                                const SizedBox(height: 12),
                                Row(children: [
                                  GestureDetector(
                                    onTap: () => _showForm(existing: ad),
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
      ),
    );
  }
}

// ── Add / Edit Form ────────────────────────────────────────────────────────────
class _AdForm extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final VoidCallback onSaved;
  const _AdForm({this.existing, required this.onSaved});
  @override
  State<_AdForm> createState() => _AdFormState();
}

class _AdFormState extends State<_AdForm> {
  late final TextEditingController _title, _ctaText, _ctaUrl;
  bool _isVideo = false;
  bool _published = true;
  bool _saving = false;
  bool _uploading = false;
  String? _mediaPath;
  Uint8List? _mediaBytes; // local path of a newly-picked file, pending upload
  String? _existingMediaUrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title    = TextEditingController(text: e?['title'] ?? '');
    _ctaText  = TextEditingController(text: e?['cta_text'] ?? 'Learn More');
    _ctaUrl   = TextEditingController(text: e?['cta_url'] ?? '');
    _isVideo  = e?['media_type'] == 'video';
    _published = e?['is_active'] as bool? ?? true;
    _existingMediaUrl = e?['media_url'] as String?;
  }

  @override
  void dispose() {
    _title.dispose(); _ctaText.dispose(); _ctaUrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    final picked = _isVideo
      ? await picker.pickVideo(source: ImageSource.gallery)
      : await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
    if (picked == null) return;
    setState(() { _mediaPath = picked.path; _existingMediaUrl = null; });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _ctaUrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title and link URL are required')));
      return;
    }
    if (_mediaPath == null && _existingMediaUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add an image or video')));
      return;
    }
    setState(() => _saving = true);

    String? mediaUrl = _existingMediaUrl;
    if (_mediaPath != null) {
      setState(() => _uploading = true);
      try {
        final bytes = _mediaBytes!;
        mediaUrl = await SupabaseService.instance.uploadAdMedia(bytes, isVideo: _isVideo);
      } catch (e) {
        setState(() { _saving = false; _uploading = false; });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload media: $e')));
        return;
      }
      setState(() => _uploading = false);
    }

    final data = {
      'title': _title.text.trim(),
      'media_type': _isVideo ? 'video' : 'image',
      'media_url': mediaUrl,
      'cta_text': _ctaText.text.trim().isEmpty ? 'Learn More' : _ctaText.text.trim(),
      'cta_url': _ctaUrl.text.trim(),
      'is_active': _published,
    };

    try {
      if (widget.existing != null) {
        await _adsDb.from('ads').update(data).eq('id', widget.existing!['id']);
      } else {
        await _adsDb.from('ads').insert(data);
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
    final hasMedia = _mediaPath != null || _existingMediaUrl != null;
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
              Text(isEdit ? 'Edit Ad' : 'Add Ad',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.4), size: 22),
              ),
            ]),
            const SizedBox(height: 16),
            _AdFieldLabel('Ad name (for your reference only — not shown publicly)'),
            const SizedBox(height: 5),
            _AdTextField(ctrl: _title, hint: 'e.g. McDonald\'s — July promo'),
            const SizedBox(height: 14),
            _AdFieldLabel('Media type'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => setState(() { _isVideo = false; _mediaPath = null; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: !_isVideo ? kPurple.withOpacity(0.15) : Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: !_isVideo ? kPurple : Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.image_rounded, size: 16, color: !_isVideo ? kPurple : Colors.white54),
                    const SizedBox(width: 6),
                    Text('Image', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: !_isVideo ? kPurple : Colors.white54)),
                  ]),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () => setState(() { _isVideo = true; _mediaPath = null; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _isVideo ? kPurple.withOpacity(0.15) : Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _isVideo ? kPurple : Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.videocam_rounded, size: 16, color: _isVideo ? kPurple : Colors.white54),
                    const SizedBox(width: 6),
                    Text('Video', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _isVideo ? kPurple : Colors.white54)),
                  ]),
                ),
              )),
            ]),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _uploading ? null : _pickMedia,
              child: Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  image: !_isVideo && _mediaPath != null
                    ? DecorationImage(image: _mediaBytes != null ? MemoryImage(_mediaBytes!) : const AssetImage('') as ImageProvider, fit: BoxFit.cover)
                    : (!_isVideo && _existingMediaUrl != null
                        ? DecorationImage(image: NetworkImage(_existingMediaUrl!), fit: BoxFit.cover)
                        : null),
                ),
                child: _uploading
                  ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: kPurple, strokeWidth: 2)))
                  : hasMedia
                    ? (_isVideo
                        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.videocam_rounded, color: kPurple, size: 28),
                            const SizedBox(height: 6),
                            Text(_mediaPath != null ? 'Video selected — tap to change' : 'Video already set — tap to change',
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
                          ]))
                        : Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: GestureDetector(
                                onTap: () => setState(() { _mediaPath = null; _existingMediaUrl = null; }),
                                child: Container(
                                  width: 26, height: 26,
                                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(8)),
                                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ))
                    : Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_isVideo ? Icons.video_call_rounded : Icons.add_photo_alternate_outlined, color: Colors.white.withOpacity(0.3), size: 28),
                          const SizedBox(height: 6),
                          Text('Tap to add ${_isVideo ? 'a video' : 'an image'}', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
                        ]),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            _AdFieldLabel('Button text'),
            const SizedBox(height: 5),
            _AdTextField(ctrl: _ctaText, hint: 'Learn More'),
            const SizedBox(height: 10),
            _AdFieldLabel('Where the button links to'),
            const SizedBox(height: 5),
            _AdTextField(ctrl: _ctaUrl, hint: 'https://...'),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text('Live on website', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.7)))),
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
                    : Text(isEdit ? 'Save Changes' : 'Add Ad',
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

class _AdFieldLabel extends StatelessWidget {
  final String text;
  const _AdFieldLabel(this.text);
  @override
  Widget build(BuildContext context) =>
    Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5)));
}

class _AdTextField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  const _AdTextField({required this.ctrl, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
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
    );
  }
}
