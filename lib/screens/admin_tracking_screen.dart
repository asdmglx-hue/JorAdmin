import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/theme.dart';
import '../services/supabase_service.dart';

// ── AdminTrackingScreen ───────────────────────────────────────────────────────
// Searches Cloudflare R2 for all files associated with a phone number.
// Accepts any format: 03001234567, 3001234567, 923001234567, +923001234567
// Works for both active users and deleted users — files stay in R2 forever.
class AdminTrackingScreen extends StatefulWidget {
  const AdminTrackingScreen({super.key});
  @override State<AdminTrackingScreen> createState() => _AdminTrackingScreenState();
}

class _AdminTrackingScreenState extends State<AdminTrackingScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _searchedPhone;
  List<_R2File> _files = [];

  // Normalise any phone format to the last 10 digits
  String _last10(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
  }

  Future<void> _search() async {
    final input = _ctrl.text.trim();
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) {
      setState(() => _error = 'Enter a valid phone number.');
      return;
    }
    setState(() { _loading = true; _error = null; _files = []; _searchedPhone = input; });
    FocusManager.instance.primaryFocus?.unfocus();

    try {
      final last10 = _last10(input);

      // Look up auth_phone, contact_phone AND id from DB
      final res = await SupabaseService.instance.client
          .from('proposals')
          .select('id, auth_phone, contact_phone')
          .or('auth_phone.like.%$last10,contact_phone.like.%$last10')
          .limit(1)
          .maybeSingle();

      // Also check affiliates table — affiliate CNICs stored under affiliates/ prefix
      final affiliateRes = await SupabaseService.instance.client
          .from('affiliates')
          .select('id, phone')
          .like('phone', '%$last10')
          .limit(1)
          .maybeSingle();

      String storageKey;
      String? uuidKey;
      String? affiliateId;
      if (res != null) {
        final authPhone = res['auth_phone'] as String?;
        final contactPhone = res['contact_phone'] as String?;
        uuidKey = res['id'] as String?; // admin uploads go under UUID folder
        final phone = authPhone ?? contactPhone ?? '';
        storageKey = phone.replaceAll(RegExp(r'\D'), '');
      } else {
        // Fallback — derive key from input
        if (digits.startsWith('92')) {
          storageKey = digits;
        } else if (digits.startsWith('0')) {
          storageKey = '92${digits.substring(1)}';
        } else {
          storageKey = '92$digits';
        }
      }

      if (affiliateRes != null) {
        affiliateId = affiliateRes['id'] as String?;
      }

      // All possible folder keys to search:
      // 1. Full international digits (923001234567) — user app uploads
      // 2. Local with zero (03001234567) — some older uploads
      // 3. Last 10 digits (3001234567) — fallback
      // 4. UUID — admin panel uploads via edit profile screen
      // 5. Affiliate UUID — affiliate CNIC photos stored under affiliates/{id}/
      final keysToTry = <String>{
        storageKey,
        last10,
        if (storageKey.startsWith('92')) '0${storageKey.substring(2)}',
        if (uuidKey != null) uuidKey,
      };

      // Search proposals/ and payment-proofs/ for user files
      // Search affiliates/ for affiliate CNIC photos
      final allFiles = <_R2File>[];
      for (final key in keysToTry) {
        for (final prefix in ['proposals/$key/', 'payment-proofs/$key/', 'forgot-password/$key/']) {
          final objects = await SupabaseService.instance.listR2Objects(prefix);
          for (final obj in objects) {
            if (!allFiles.any((f) => f.key == obj['key'])) {
              allFiles.add(_R2File(
                key: obj['key']!,
                url: obj['url']!,
                date: obj['date'] ?? '',
                size: int.tryParse(obj['size'] ?? '0') ?? 0,
                category: _categoryFromKey(obj['key']!),
              ));
            }
          }
        }
      }

      // Search affiliate CNIC folder — stored flat under affiliates/ (no per-affiliate sub-folder)
      // When phone matches an affiliate, show all affiliate CNIC files
      if (affiliateId != null) {
        final objects = await SupabaseService.instance.listR2Objects('affiliates/');
        for (final obj in objects) {
          if (!allFiles.any((f) => f.key == obj['key'])) {
            allFiles.add(_R2File(
              key: obj['key']!,
              url: obj['url']!,
              date: obj['date'] ?? '',
              size: int.tryParse(obj['size'] ?? '0') ?? 0,
              category: _categoryFromKey(obj['key']!),
            ));
          }
        }
      }

      allFiles.sort((a, b) => b.date.compareTo(a.date));
      setState(() { _files = allFiles; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Failed to fetch files. Check your connection.'; _loading = false; });
    }
  }

  String _categoryFromKey(String key) {
    if (key.startsWith('affiliates/')) return key.contains('back') ? 'Affiliate CNIC Back' : 'Affiliate CNIC Front';
    if (key.contains('profile_')) return 'Profile Photo';
    if (key.contains('guardian_cnic_front') || (key.contains('cnic_front') && key.contains('guardian'))) return 'Parent / Guardian CNIC Front';
    if (key.contains('guardian_cnic_back')  || (key.contains('cnic_back')  && key.contains('guardian'))) return 'Parent / Guardian CNIC Back';
    if (key.contains('cnic_front')) return 'Candidate CNIC Front';
    if (key.contains('cnic_back'))  return 'Candidate CNIC Back';
    if (key.contains('degree_certificate')) return 'Degree Certificate';
    if (key.contains('education_document')) return 'Education Document';
    if (key.contains('proof')) return 'Payment Proof';
    if (key.contains('forgot-password')) return 'Forgot Password CNIC';
    return 'File';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    } catch (_) { return iso; }
  }

  void _clear() {
    setState(() { _files = []; _searchedPhone = null; _error = null; _ctrl.clear(); });
  }

  Future<void> _confirmDelete(_R2File file) async {
    final filename = file.key.split('/').last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete this file?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text(
          'This will permanently delete "$filename" from storage. This cannot be undone.',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: kRose, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => file.deleting = true);
    try {
      await SupabaseService.instance.deleteR2Object(file.key);
      setState(() => _files.removeWhere((f) => f.key == file.key));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('File deleted'), backgroundColor: kGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      setState(() => file.deleting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Failed to delete file'), backgroundColor: kRose,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }

  Color _categoryColor(String cat) {
    if (cat.contains('Affiliate')) return kTeal;
    if (cat.contains('Profile')) return kPurple;
    if (cat.contains('Payment')) return kGreen;
    if (cat.contains('Forgot')) return kAmber;
    if (cat.contains('Guardian') || cat.contains('Parent')) return const Color(0xFF0369A1);
    if (cat.contains('Degree') || cat.contains('Education')) return kTeal;
    return kInkLight;
  }

  IconData _categoryIcon(String cat) {
    if (cat.contains('Affiliate')) return Icons.handshake_rounded;
    if (cat.contains('Profile')) return Icons.person_rounded;
    if (cat.contains('Payment')) return Icons.receipt_rounded;
    if (cat.contains('CNIC')) return Icons.badge_rounded;
    if (cat.contains('Degree') || cat.contains('Education')) return Icons.school_rounded;
    if (cat.contains('Forgot')) return Icons.lock_reset_rounded;
    return Icons.insert_drive_file_rounded;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1E),
      body: Column(children: [

        // ── Search bar ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          color: const Color(0xFF16132A),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Track Files by Phone Number', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 4),
            Text('Find all R2 files for any user — active or deleted', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4))),
            const SizedBox(height: 4),
            Text('Accepts any format: 0301…, 301…, 92301…, +92301…', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.25))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+]'))],
                  onChanged: (_) { if (_error != null) setState(() => _error = null); },
                  onSubmitted: (_) => _search(),
                  style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 1),
                  decoration: InputDecoration(
                    hintText: '03001234567 or +923001234567',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.25), letterSpacing: 0.5),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    prefixIcon: Icon(Icons.phone_rounded, color: Colors.white.withOpacity(0.3), size: 18),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.12))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kPurple, width: 1.5)),
                    errorText: _error,
                    errorStyle: const TextStyle(color: kRose, fontSize: 11.5),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _loading ? null : _search,
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: _loading ? kPurple.withOpacity(0.4) : kPurple,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _loading
                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.search_rounded, color: Colors.white, size: 22),
                ),
              ),
              if (_searchedPhone != null && !_loading) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _clear,
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                  ),
                ),
              ],
            ]),
          ]),
        ),

        // ── Results ─────────────────────────────────────────────────────────
        Expanded(child: _buildResults()),
      ]),
    );
  }

  Widget _buildResults() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: kPurple));

    if (_searchedPhone == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.folder_open_rounded, size: 52, color: Colors.white.withOpacity(0.1)),
        const SizedBox(height: 12),
        Text('Enter a phone number to search files', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.3))),
      ]));
    }

    if (_files.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.find_in_page_rounded, size: 52, color: Colors.white.withOpacity(0.1)),
        const SizedBox(height: 12),
        Text('No files found', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5))),
        const SizedBox(height: 4),
        Text('$_searchedPhone', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.25))),
      ]));
    }

    final grouped = <String, List<_R2File>>{};
    for (final f in _files) {
      grouped.putIfAbsent(f.category, () => []).add(f);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: kPurple.withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: kPurple.withOpacity(0.2))),
          child: Row(children: [
            const Icon(Icons.folder_rounded, color: kPurple, size: 18),
            const SizedBox(width: 10),
            Text('${_files.length} file${_files.length == 1 ? '' : 's'} found for $_searchedPhone',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kPurple)),
          ]),
        ),
        const SizedBox(height: 16),
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Icon(_categoryIcon(entry.key), size: 14, color: _categoryColor(entry.key)),
              const SizedBox(width: 6),
              Text(entry.key, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _categoryColor(entry.key), letterSpacing: 0.5)),
              const SizedBox(width: 8),
              Text('(${entry.value.length})', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.3))),
            ]),
          ),
          ...entry.value.map((f) => _FileCard(file: f, formatDate: _formatDate, formatSize: _formatSize, onDelete: () => _confirmDelete(f))),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _R2File {
  final String key, url, date, category;
  final int size;
  bool deleting;
  _R2File({required this.key, required this.url, required this.date, required this.size, required this.category, this.deleting = false});
}

class _FileCard extends StatelessWidget {
  final _R2File file;
  final String Function(String) formatDate;
  final String Function(int) formatSize;
  final VoidCallback onDelete;
  const _FileCard({required this.file, required this.formatDate, required this.formatSize, required this.onDelete});

  bool get _isImage {
    final lower = file.key.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    final filename = file.key.split('/').last;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: const Color(0xFF1C1A2E), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.07))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_isImage)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Image.network(
              file.url, height: 160, width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 80, color: Colors.white.withOpacity(0.04),
                child: Center(child: Icon(Icons.broken_image_rounded, color: Colors.white.withOpacity(0.2), size: 28)),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(filename, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: file.deleting ? null : onDelete,
                child: file.deleting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kRose))
                  : Icon(Icons.delete_outline_rounded, size: 18, color: kRose.withOpacity(0.8)),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.access_time_rounded, size: 11, color: Colors.white.withOpacity(0.35)),
              const SizedBox(width: 4),
              Text(formatDate(file.date), style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35))),
              const SizedBox(width: 12),
              Icon(Icons.data_usage_rounded, size: 11, color: Colors.white.withOpacity(0.35)),
              const SizedBox(width: 4),
              Text(formatSize(file.size), style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () async {
                  try { await launchUrl(Uri.parse(file.url), mode: LaunchMode.externalApplication); } catch (_) {}
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.open_in_new_rounded, size: 14, color: kPurple),
                    SizedBox(width: 6),
                    Text('Open', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kPurple)),
                  ]),
                ),
              )),
              const SizedBox(width: 8),
              Expanded(child: GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: file.url));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('URL copied'), backgroundColor: kGreen,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    duration: const Duration(seconds: 2),
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withOpacity(0.1))),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.copy_rounded, size: 14, color: Colors.white54),
                    SizedBox(width: 6),
                    Text('Copy URL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white54)),
                  ]),
                ),
              )),
            ]),
          ]),
        ),
      ]),
    );
  }
}
