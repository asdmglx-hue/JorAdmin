import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/theme.dart';
import '../widgets/country_picker.dart';
import '../models/admin_permissions.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AdminMarketingScreen — Contact Number Directory
// ─────────────────────────────────────────────────────────────────────────────

class AdminMarketingScreen extends StatefulWidget {
  final VoidCallback? onRefreshCallback;
  const AdminMarketingScreen({super.key, this.onRefreshCallback});

  @override
  State<AdminMarketingScreen> createState() => AdminMarketingScreenState();
}

class AdminMarketingScreenState extends State<AdminMarketingScreen> {
  final _client = Supabase.instance.client;
  // Single unified input controller — used for both search and add
  final _inputCtrl = TextEditingController();
  CountryCode _addCountry = CountryCode.pakistan;
  bool _hasInput = false; // true when user has typed something
  String _statusFilter = 'all'; // 'all' | 'done' | 'pending'
  final Set<String> _selectedIds = {}; // multi-select

  List<_Contact> _contacts = [];
  List<_Contact> _filtered = [];
  bool _loading = true;
  String? _error;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(() {
      final v = _inputCtrl.text;
      setState(() => _hasInput = v.isNotEmpty);
      _applyFilter();
    });
    _init();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  // Public refresh — called from dashboard header button
  Future<void> refresh() => _refresh();

  // Public open trash — called from dashboard header button
  void openTrash() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _MarketingTrashScreen(client: _client),
    )).then((_) => _loadContacts());
  }

  // Public import/export — called from dashboard header buttons
  void showImport() => _showImportDialog();
  void showExport() => _showExportDialog();

  void showImportExportMenu(BuildContext _) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1A33),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(ctx).padding.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () { Navigator.pop(ctx); _showImportDialog(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(9)),
                  child: Padding(padding: const EdgeInsets.all(8), child: SvgPicture.asset('assets/icons/ic_upload.svg', colorFilter: const ColorFilter.mode(kPurple, BlendMode.srcIn)))),
                const SizedBox(width: 14),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Import', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('Add contacts from a CSV file', style: TextStyle(color: Color(0x66FFFFFF), fontSize: 12)),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () { Navigator.pop(ctx); _showExportDialog(); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(9)),
                  child: Padding(padding: const EdgeInsets.all(8), child: SvgPicture.asset('assets/icons/ic_download.svg', colorFilter: const ColorFilter.mode(kPurple, BlendMode.srcIn)))),
                const SizedBox(width: 14),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Export', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  Text('Save contacts as CSV file', style: TextStyle(color: Color(0x66FFFFFF), fontSize: 12)),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _init() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _syncFromProposals();
      await _loadContacts();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Sync new numbers from proposals ────────────────────────────────────────
  Future<void> _syncFromProposals() async {
    if (!AdminPerms.i.canEdit(AdminPageKeys.marketing)) return;
    if (mounted) setState(() => _syncing = true);
    try {
      final rows = await _client
          .from('proposals')
          .select('contact_phone, contact_phone_2, name, proposal_number')
          .not('contact_phone', 'is', null)
          .neq('contact_phone', '') as List;

      final existing = await _client
          .from('marketing_contacts')
          .select('phone') as List;
      final existingPhones = existing
          .map((e) => _normalise(e['phone'] as String? ?? ''))
          .toSet();

      final toInsert = <Map<String, dynamic>>[];
      for (final row in rows) {
        final p1 = _normalise(row['contact_phone'] as String? ?? '');
        final p2 = _normalise(row['contact_phone_2'] as String? ?? '');
        final name = row['name'] as String?;
        final pNum = row['proposal_number'] as int?;
        if (p1.isNotEmpty && !existingPhones.contains(p1)) {
          existingPhones.add(p1);
          toInsert.add({'phone': p1, 'name': name, 'proposal_number': pNum, 'marked_done': false});
        }
        if (p2.isNotEmpty && !existingPhones.contains(p2)) {
          existingPhones.add(p2);
          toInsert.add({'phone': p2, 'name': name, 'proposal_number': pNum, 'marked_done': false});
        }
      }

      if (toInsert.isNotEmpty) {
        for (var i = 0; i < toInsert.length; i += 100) {
          final chunk = toInsert.sublist(i, (i + 100).clamp(0, toInsert.length));
          await _client.from('marketing_contacts').upsert(chunk, onConflict: 'phone');
        }
      }
    } catch (e) {
      debugPrint('[Marketing] sync error: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _loadContacts() async {
    final rows = await _client
        .from('marketing_contacts')
        .select()
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: false) as List;
    final contacts = rows.map((r) => _Contact.fromJson(r as Map<String, dynamic>)).toList();
    if (mounted) {
      setState(() {
        _contacts = contacts;
      });
      _applyFilter();
    }
  }

  void _applyFilter() {
    final q = _inputCtrl.text.trim();
    setState(() {
      var base = _contacts.where((c) {
        if (_statusFilter == 'done') return c.markedDone;
        if (_statusFilter == 'pending') return !c.markedDone;
        return true;
      }).toList();
      _filtered = q.isEmpty
          ? base
          : base.where((c) {
              if (q.startsWith('#')) {
                final num = q.substring(1);
                return num.isNotEmpty &&
                    c.proposalNumber != null &&
                    c.proposalNumber.toString().contains(num);
              }
              return c.phone.contains(q);
            }).toList();
    });
  }

  void _setStatusFilter(String f) {
    setState(() => _statusFilter = f);
    _applyFilter();
  }

  String _normalise(String phone) => phone.replaceAll(RegExp(r'[^\d+]'), '');

  String _toIntlDigits(String phone) {
    final t = phone.trim();
    if (t.startsWith('+')) return t.replaceAll(RegExp(r'[^\d]'), '');
    if (t.startsWith('0')) {
      final d = t.substring(1).replaceAll(RegExp(r'[^\d]'), '');
      return '92' + d;
    }
    return t.replaceAll(RegExp(r'[^\d]'), '');
  }


  // ── Add number ─────────────────────────────────────────────────────────────
  Future<void> _addNumber() async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.marketing, what: 'adding numbers')) return;
    final digits = _inputCtrl.text.trim();
    if (digits.isEmpty) return;
    final stored = formatDialedPhone(_addCountry.dialCode, digits);
    final norm = _normalise(stored);

    final exists = _contacts.any((c) => _normalise(c.phone) == norm);
    if (exists) { _showDuplicateDialog(stored); return; }

    try {
      await _client.from('marketing_contacts').insert({'phone': stored, 'marked_done': false});
      _inputCtrl.clear();
      await _loadContacts();
      _toast('Number added');
    } catch (e) {
      if (e.toString().contains('unique') || e.toString().contains('duplicate')) {
        _showDuplicateDialog(stored);
      } else {
        _toast('Error: $e');
      }
    }
  }

  void _showDuplicateDialog(String phone) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.info_rounded, color: kAmber, size: 22),
          SizedBox(width: 10),
          Text('Already Exists', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Text('$phone is already in your contact directory.',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it', style: TextStyle(color: kPurple))),
        ],
      ),
    );
  }

  // ── Remove ─────────────────────────────────────────────────────────────────
  Future<void> _removeNumber(_Contact c) async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.marketing, what: 'removing numbers')) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Contact', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('Remove ${c.phone}?\n\nThis won\'t affect users or orders.',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove', style: TextStyle(color: kRose, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    await _client.from('marketing_contacts').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', c.id);
    await _loadContacts();
    _toast('Moved to trash');
  }

  Future<void> _deleteSelected() async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.marketing, what: 'deleting numbers')) return;
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Selected', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('Delete $count contact${count > 1 ? 's' : ''}? This won\'t affect users or orders.',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: kRose, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in _selectedIds) {
      await _client.from('marketing_contacts').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
    }
    setState(() => _selectedIds.clear());
    await _loadContacts();
    _toast('Moved to trash');
  }

  // ── Mark done ──────────────────────────────────────────────────────────────
  Future<void> _toggleDone(_Contact c) async {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.marketing, what: 'marking contacts')) return;
    final next = !c.markedDone;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(next ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: next ? kGreen : kInkFaint, size: 22),
          const SizedBox(width: 10),
          Text(next ? 'Mark as Done' : 'Mark as Undone',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          next ? 'Mark ${c.phone} as contacted / done?' : 'Mark ${c.phone} as pending again?',
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text(next ? 'Mark Done' : 'Mark Undone',
                  style: TextStyle(color: next ? kGreen : kAmber, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    await _client.from('marketing_contacts').update({'marked_done': next}).eq('id', c.id);
    await _loadContacts();
  }

  // ── WhatsApp bottom sheet ──────────────────────────────────────────────────
  void _openContactSheet(_Contact c) {
    // Build international number: strip leading 0, prepend country code if stored with +XX
    final raw = c.phone;
    String intl;
    if (raw.startsWith('+')) {
      intl = raw.replaceAll(RegExp(r'[^\d]'), '');
    } else if (raw.startsWith('0')) {
      intl = '92${raw.substring(1).replaceAll(RegExp(r'[^\d]'), '')}';
    } else {
      intl = raw.replaceAll(RegExp(r'[^\d]'), '');
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1A33),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(ctx).padding.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          // Phone display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.phone_rounded, color: kPurpleLight, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.phone, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                if (c.hashCode_ != null)
                  Text(c.hashCode_!, style: TextStyle(color: kPurple.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.w600)),
              ])),
            ]),
          ),
          const SizedBox(height: 16),
          // Action buttons
          Row(children: [
            // Copy
            Expanded(child: _SheetAction(
              icon: Icons.copy_rounded,
              label: 'Copy',
              color: kInkLight,
              onTap: () {
                Clipboard.setData(ClipboardData(text: c.phone));
                Navigator.pop(ctx);
                _toast('Copied');
              },
            )),
            const SizedBox(width: 10),
            // Call
            Expanded(child: _SheetAction(
              icon: Icons.call_rounded,
              label: 'Call',
              color: kPurple,
              onTap: () {
                Navigator.pop(ctx);
                _launchUrl('tel:${c.phone}');
              },
            )),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            // WhatsApp
            Expanded(child: _SheetAction(
              icon: Icons.chat_rounded,
              label: 'WhatsApp',
              color: const Color(0xFF25D366),
              onTap: () {
                Navigator.pop(ctx);
                _launchUrl('https://wa.me/$intl');
              },
            )),
            const SizedBox(width: 10),
            // WhatsApp Business
            Expanded(child: _SheetAction(
              icon: Icons.business_center_rounded,
              label: 'WA Business',
              color: const Color(0xFF1D7C4D),
              onTap: () {
                Navigator.pop(ctx);
                // wa.me works for both regular and business
                _launchUrl('https://wa.me/$intl');
              },
            )),
          ]),
        ]),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (url.startsWith('https://wa.me')) {
        // On Android this shows the system chooser when both
        // WhatsApp and WhatsApp Business are installed.
        final launched = await launchUrl(uri,
            mode: kIsWeb
                ? LaunchMode.platformDefault
                : LaunchMode.externalNonBrowserApplication);
        if (!launched) throw Exception('Could not launch');
      } else {
        await launchUrl(uri,
            mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
      }
    } catch (_) {
      Clipboard.setData(ClipboardData(text: url));
      _toast('Link copied — open manually');
    }
  }

  // ── Import ─────────────────────────────────────────────────────────────────
  void _showImportDialog() {
    if (!AdminPerms.i.guardEdit(AdminPageKeys.marketing, what: 'importing contacts')) return;
    showDialog(
      context: context,
      builder: (ctx) => _ImportDialog(
        onImport: _processImport,
      ),
    );
  }

  Future<Map<String, dynamic>> _processImport(String text, bool markDoneIfExists) async {
    // Parse numbers from pasted CSV/text — extract anything that looks like a phone number
    final lines = text.split(RegExp(r'[\n\r]+'));
    final phoneRegex = RegExp(r'[\+]?[\d][\d\s\-\.\(\)]{6,}[\d]');
    final numbers = <String>{};
    for (final line in lines) {
      final matches = phoneRegex.allMatches(line);
      for (final m in matches) {
        final raw = m.group(0)!.replaceAll(RegExp(r'[\s\-\.\(\)]'), '');
        if (raw.length >= 7) numbers.add(raw);
      }
    }

    if (numbers.isEmpty) return {'added': 0, 'marked': 0, 'skipped': 0};

    int added = 0, marked = 0, skipped = 0;

    for (final num in numbers) {
      // Check if exists
      final existing = _contacts.where((c) =>
          _normalise(c.phone) == _normalise(num) ||
          _normalise(c.phone).endsWith(_normalise(num)) ||
          _normalise(num).endsWith(_normalise(c.phone))).toList();

      if (existing.isNotEmpty) {
        if (markDoneIfExists && !existing.first.markedDone) {
          await _client.from('marketing_contacts')
              .update({'marked_done': true})
              .eq('id', existing.first.id);
          marked++;
        } else {
          skipped++;
        }
      } else {
        try {
          await _client.from('marketing_contacts')
              .insert({'phone': num, 'marked_done': false});
          added++;
        } catch (_) { skipped++; }
      }
    }

    await _loadContacts();
    return {'added': added, 'marked': marked, 'skipped': skipped};
  }

  // ── Export ─────────────────────────────────────────────────────────────────
  void _showExportDialog() {
    showDialog(context: context, builder: (ctx) => _ExportDialog(
      contacts: _contacts,
      onExport: _exportFile,
    ));
  }

  Future<void> _exportFile(List<_Contact> contacts, String filter, {bool inclHash = true}) async {
    if (contacts.isEmpty) { _toast('No contacts to export'); return; }

    // Build CSV
    final buf = StringBuffer();
    final header = <String>['Phone'];
    if (inclHash) header.add('Hash Code');
    buf.writeln(header.join(','));
    for (var i = 0; i < contacts.length; i++) {
      final c = contacts[i];
      final row = <String>['"' + c.displayPhone + '"'];
      if (inclHash) row.add(c.hashCode_ ?? '');
      buf.writeln(row.join(','));
    }
    final csv = buf.toString();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'contacts_' + filter + '_' + ts.toString() + '.csv';

    if (kIsWeb) {
      Clipboard.setData(ClipboardData(text: csv));
      _toast('Copied as CSV — paste into Excel or Sheets');
      return;
    }

    // Step 1: Try writing directly to Downloads (works on most Android devices)
    File? savedFile;
    final candidates = [
      '/storage/emulated/0/Downloads/' + fileName,
      '/storage/emulated/0/Download/' + fileName,
      '/sdcard/Downloads/' + fileName,
      '/sdcard/Download/' + fileName,
    ];
    for (final path in candidates) {
      try {
        final f = File(path);
        await f.parent.create(recursive: true);
        await f.writeAsString(csv);
        savedFile = f;
        break;
      } catch (_) {}
    }

    if (savedFile != null) {
      // File saved — show dialog with path and open option
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1A33),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.check_circle_rounded, color: kGreen, size: 22),
              SizedBox(width: 10),
              Text('File Saved!', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Saved to your Downloads folder:', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
                child: Text(fileName, style: const TextStyle(color: kPurpleLight, fontSize: 12, fontFamily: 'monospace')),
              ),
              const SizedBox(height: 12),
              Text('Open with a file manager, or tap below to open directly with Excel or Google Sheets.',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
            ]),
            actions: [

              GestureDetector(
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await launchUrl(
                      Uri.file(savedFile!.path),
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {
                    _toast('Open your Downloads folder and tap the file');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kPurple, kPurpleDeep]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Open File', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
            ],
          ),
        );
      }
      return;
    }

    // Step 2: Fallback — upload to Supabase and open URL
    try {
      final bytes = Uint8List.fromList(csv.codeUnits);
      await _client.storage
          .from('marketing-exports')
          .uploadBinary(fileName, bytes,
              fileOptions: const FileOptions(contentType: 'text/csv', upsert: true));
      final url = _client.storage.from('marketing-exports').getPublicUrl(fileName);

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1A33),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.cloud_done_rounded, color: kGreen, size: 22),
              SizedBox(width: 10),
              Text('Ready to Download', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Tap below to open the file. In Chrome, tap the 3-dot menu → Download to save it.',
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
                child: Text(fileName, style: const TextStyle(color: kPurpleLight, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4)))),
              GestureDetector(
                onTap: () async {
                  Navigator.pop(ctx);
                  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kPurple, kPurpleDeep]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Open Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _toast('Export failed: ' + e.toString());
    }
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      await _syncFromProposals();
      await _loadContacts();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF1E1A33),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final doneCount = _contacts.where((c) => c.markedDone).length;
    final pendingCount = _contacts.length - doneCount;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1A),
      body: Column(children: [
        const ViewOnlyBanner(pageKey: AdminPageKeys.marketing),
        _buildTopBar(doneCount, pendingCount),
        if (AdminPerms.i.canEdit(AdminPageKeys.marketing)) _buildInputBar(),
        if (_error != null) _buildError(),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator(color: kPurple)))
        else
          Expanded(child: _buildList()),
      ]),
    );
  }

  Widget _buildTopBar(int done, int pending) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.07))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Stat chips
          Row(mainAxisSize: MainAxisSize.min, children: [
            _StatChip(label: '${_contacts.length}', sub: 'Total', color: kPurple, selected: _statusFilter == 'all', onTap: () => _setStatusFilter('all')),
            const SizedBox(width: 8),
            _StatChip(label: '$done', sub: 'Done', color: kGreen, selected: _statusFilter == 'done', onTap: () => _setStatusFilter('done')),
            const SizedBox(width: 8),
            _StatChip(label: '$pending', sub: 'Pending', color: kAmber, selected: _statusFilter == 'pending', onTap: () => _setStatusFilter('pending')),
          ]),
          // Right side — delete when selecting
          if (_selectedIds.isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: _deleteSelected,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: kRose.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: kRose.withOpacity(0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    SvgPicture.asset('assets/icons/ic_trash.svg', width: 14, height: 14, colorFilter: const ColorFilter.mode(kRose, BlendMode.srcIn)),
                    const SizedBox(width: 5),
                    Text('Delete ${_selectedIds.length}', style: const TextStyle(color: kRose, fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _selectedIds.clear()),
                child: Container(
                  height: 34, width: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: const Center(child: Icon(Icons.close_rounded, color: Colors.white, size: 17)),
                ),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final hasText = _hasInput;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(children: [
        // Country picker — always visible
        GestureDetector(
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            useSafeArea: true,
            builder: (ctx) => _CountryPickerSheet(
              selected: _addCountry,
              onSelect: (c) { setState(() => _addCountry = c); Navigator.pop(ctx); },
            ),
          ),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1A33),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_addCountry.flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 5),
              Text(_addCountry.dialCode,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 3),
              Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: Colors.white.withOpacity(0.5)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        // Unified input — types numbers to add, types text to search
        Expanded(
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1A33),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasText ? kPurple.withOpacity(0.4) : Colors.white.withOpacity(0.08),
              ),
            ),
            child: TextField(
              controller: _inputCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d#]'))],
              decoration: InputDecoration(
                hintText: 'Type number to search or add…',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                suffixIcon: hasText
                    ? GestureDetector(
                        onTap: () => _inputCtrl.clear(),
                        child: Icon(Icons.close_rounded,
                            color: Colors.white.withOpacity(0.35), size: 18),
                      )
                    : null,
              ),
              onSubmitted: (_) => _addNumber(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Add button — purple when input present, dim when empty
        GestureDetector(
          onTap: hasText ? _addNumber : null,
          child: Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              gradient: hasText
                  ? const LinearGradient(colors: [kPurple, kPurpleDeep])
                  : null,
              color: hasText ? null : const Color(0xFF1E1A33),
              borderRadius: BorderRadius.circular(12),
              border: hasText ? null : Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Center(
              child: Icon(Icons.add_rounded,
                  color: hasText ? Colors.white : Colors.white.withOpacity(0.25), size: 22),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Search button — purple when input present, dim when empty
        GestureDetector(
          onTap: hasText ? _applyFilter : null,
          child: Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              gradient: hasText
                  ? const LinearGradient(colors: [kPurple, kPurpleDeep])
                  : null,
              color: hasText ? null : const Color(0xFF1E1A33),
              borderRadius: BorderRadius.circular(12),
              border: hasText ? null : Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Center(
              child: Icon(Icons.search_rounded,
                  color: hasText ? Colors.white : Colors.white.withOpacity(0.25), size: 20),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildError() {
    final needsTable = _error!.contains('does not exist') || _error!.contains('relation');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kRose.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kRose.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.error_outline_rounded, color: kRose, size: 18),
          SizedBox(width: 8),
          Text('Setup Required', style: TextStyle(color: kRose, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
        if (needsTable) ...[
          const SizedBox(height: 8),
          Text('Run this SQL in your Supabase SQL Editor:',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              const sql = 'CREATE TABLE IF NOT EXISTS marketing_contacts (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  phone text NOT NULL UNIQUE,\n  name text,\n  marked_done boolean NOT NULL DEFAULT false,\n  created_at timestamptz NOT NULL DEFAULT now()\n);';
              Clipboard.setData(const ClipboardData(text: sql));
              _toast('SQL copied');
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'CREATE TABLE IF NOT EXISTS marketing_contacts (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  phone text NOT NULL UNIQUE,\n  name text,\n  marked_done boolean NOT NULL DEFAULT false,\n  created_at timestamptz NOT NULL DEFAULT now()\n);\n\n← Tap to copy',
                style: TextStyle(color: Color(0xFF90D9FF), fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _buildList() {
    if (_filtered.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.contacts_rounded, color: Colors.white.withOpacity(0.12), size: 52),
        const SizedBox(height: 14),
        Text(
          _hasInput ? 'No results for "${_inputCtrl.text}"' : 'No contacts yet',
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 15),
        ),
        const SizedBox(height: 6),
        Text(
          _hasInput ? 'Try a different search' : 'Add a number above or tap sync',
          style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 12),
        ),
      ]));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final c = _filtered[i];
        final intl = _toIntlDigits(c.phone);
        final isSelected = _selectedIds.contains(c.id);
        final isMultiSelect = _selectedIds.isNotEmpty;
        return _ContactTile(
          contact: c,
          isSelected: isSelected,
          isMultiSelect: isMultiSelect,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            setState(() {
              if (_selectedIds.contains(c.id)) _selectedIds.remove(c.id);
              else _selectedIds.add(c.id);
            });
          },
          onTap: isMultiSelect ? () {
            setState(() {
              if (_selectedIds.contains(c.id)) _selectedIds.remove(c.id);
              else _selectedIds.add(c.id);
            });
          } : null,
          onCopy: () {
            Clipboard.setData(ClipboardData(text: c.phone));
            _toast('Copied');
          },
          onCall: () => _launchUrl('tel:' + c.phone),
          onWhatsApp: () => _launchUrl('https://wa.me/' + intl),
          onToggleDone: () => _toggleDone(c),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Contact tile
// ─────────────────────────────────────────────────────────────────────────────
class _ContactTile extends StatelessWidget {
  final _Contact contact;
  final bool isSelected;
  final bool isMultiSelect;
  final VoidCallback onLongPress;
  final VoidCallback? onTap;
  final VoidCallback onCopy;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final VoidCallback onToggleDone;
  const _ContactTile({
    required this.contact,
    required this.isSelected,
    required this.isMultiSelect,
    required this.onLongPress,
    required this.onTap,
    required this.onCopy,
    required this.onCall,
    required this.onWhatsApp,
    required this.onToggleDone,
  });

  @override
  Widget build(BuildContext context) {
    final done = contact.markedDone;
    return GestureDetector(
      onLongPress: onLongPress,
      onTap: isMultiSelect ? onTap : null,
      child: Container(
      decoration: BoxDecoration(
        color: isSelected ? kRose.withOpacity(0.08) : const Color(0xFF1A1730),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isSelected ? kRose.withOpacity(0.7) : done ? kGreen.withOpacity(0.25) : Colors.white.withOpacity(0.07),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Checkbox
          GestureDetector(
            onTap: isMultiSelect ? () {
              if (onTap != null) onTap!();
            } : onToggleDone,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: done ? kGreen : Colors.transparent,
                  border: Border.all(
                    color: done ? kGreen : Colors.white.withOpacity(0.22),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: done ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
              ),
            ),
          ),
          // Phone + hash
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.displayPhone,
                    style: TextStyle(
                      color: done ? Colors.white.withOpacity(0.4) : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.white.withOpacity(0.35),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.hashCode_ ?? '#—',
                    style: TextStyle(
                      color: done
                          ? kPurple.withOpacity(0.3)
                          : contact.hashCode_ != null
                              ? kPurple.withOpacity(0.6)
                              : Colors.white.withOpacity(0.2),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                ],
              ),
            ),
          ),
          // Inline action icons
          _TileIcon(icon: Icons.copy_rounded, color: Colors.white.withOpacity(0.45), onTap: onCopy),
          _TileIcon(icon: Icons.call_rounded, color: kPurple, onTap: onCall),
          // WhatsApp SVG logo
          GestureDetector(
            onTap: onWhatsApp,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
              child: SvgPicture.asset('assets/icons/whatsapp.svg', width: 20, height: 20),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      ), // Container
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sheet action button
// ─────────────────────────────────────────────────────────────────────────────
class _TileIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _TileIcon({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SheetAction({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Country picker sheet (inline copy matching the app's existing style)
// ─────────────────────────────────────────────────────────────────────────────
class _CountryPickerSheet extends StatefulWidget {
  final CountryCode selected;
  final ValueChanged<CountryCode> onSelect;
  const _CountryPickerSheet({required this.selected, required this.onSelect});
  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _q = '';
  final _ctrl = TextEditingController();
  List<CountryCode> get _filtered => _q.isEmpty
      ? CountryCode.all
      : CountryCode.all
          .where((c) =>
              c.name.toLowerCase().contains(_q.toLowerCase()) ||
              c.dialCode.contains(_q))
          .toList();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1A33),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Align(alignment: Alignment.centerLeft,
            child: Text('Select Country',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white))),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(children: [
              Icon(Icons.search_rounded, size: 20, color: Colors.white.withOpacity(0.4)),
              const SizedBox(width: 8),
              Expanded(child: TextField(
                controller: _ctrl,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'Search country…',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
                  border: InputBorder.none, isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                style: const TextStyle(fontSize: 14, color: Colors.white),
              )),
              if (_q.isNotEmpty)
                GestureDetector(
                  onTap: () { _ctrl.clear(); setState(() => _q = ''); },
                  child: Icon(Icons.close_rounded, size: 18, color: Colors.white.withOpacity(0.4)),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Divider(height: 1, color: Colors.white.withOpacity(0.08)),
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: _filtered.length,
          itemBuilder: (_, i) {
            final c = _filtered[i];
            final sel = c.dialCode == widget.selected.dialCode && c.name == widget.selected.name;
            return GestureDetector(
              onTap: () => widget.onSelect(c),
              child: Container(
                color: sel ? kPurple.withOpacity(0.15) : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(children: [
                  Text(c.flag, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 14),
                  Expanded(child: Text(c.name,
                      style: TextStyle(
                          fontSize: 14,
                          color: sel ? kPurple : Colors.white,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500))),
                  Text(c.dialCode,
                      style: TextStyle(
                          fontSize: 13,
                          color: sel ? kPurple : Colors.white.withOpacity(0.4),
                          fontWeight: FontWeight.w600)),
                  if (sel) ...[const SizedBox(width: 8), const Icon(Icons.check_rounded, size: 18, color: kPurple)],
                ]),
              ),
            );
          },
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Import dialog
// ─────────────────────────────────────────────────────────────────────────────
class _ImportDialog extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(String text, bool markDoneIfExists) onImport;
  const _ImportDialog({required this.onImport});
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _ctrl = TextEditingController();
  bool _markDone = false;
  bool _importing = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _pickFile() async {
    // Try to read contacts.csv from Downloads folder
    // User should place their CSV file at Downloads/contacts.csv
    setState(() => _importing = true);
    try {
      final paths = [
        '/storage/emulated/0/Downloads/contacts.csv',
        '/storage/emulated/0/Download/contacts.csv',
        '/sdcard/Downloads/contacts.csv',
        '/sdcard/Download/contacts.csv',
      ];

      String content = '';
      String foundPath = '';
      for (final path in paths) {
        final f = File(path);
        if (await f.exists()) {
          content = await f.readAsString();
          foundPath = path;
          break;
        }
      }

      if (content.isEmpty) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E1A33),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [
                Icon(Icons.info_rounded, color: kAmber, size: 22),
                SizedBox(width: 10),
                Text('How to Import', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Place your CSV file in your Downloads folder with the name:', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                  child: const Text('contacts.csv', style: TextStyle(color: kPurpleLight, fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                ),
                const SizedBox(height: 10),
                Text('The CSV should have one phone number per line or per column. Then tap Upload File again.', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
              ]),
              actions: [
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPurple, kPurpleDeep]), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Got it', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          );
        }
        if (mounted) setState(() => _importing = false);
        return;
      }

      final importResult = await widget.onImport(content, _markDone);
      if (mounted) {
        Navigator.pop(context);
        final added = importResult['added'] as int;
        final marked = importResult['marked'] as int;
        final skipped = importResult['skipped'] as int;
        // Delete the file after successful import
        try { await File(foundPath).delete(); } catch (_) {}
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1A33),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.check_circle_rounded, color: kGreen, size: 22),
              SizedBox(width: 10),
              Text('Import Done', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              _ResultRow(icon: Icons.add_circle_rounded, color: kGreen, label: 'New contacts added', value: added),
              const SizedBox(height: 8),
              _ResultRow(icon: Icons.check_rounded, color: kPurple, label: 'Marked as done', value: marked),
              const SizedBox(height: 8),
              _ResultRow(icon: Icons.skip_next_rounded, color: kInkFaint, label: 'Skipped (already exists)', value: skipped),
            ]),
            actions: [
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPurple, kPurpleDeep]), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: ' + e.toString()),
          backgroundColor: const Color(0xFF1E1A33),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _doImport() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _importing = true);
    try {
      final result = await widget.onImport(text, _markDone);
      if (mounted) {
        Navigator.pop(context);
        final added = result['added'] as int;
        final marked = result['marked'] as int;
        final skipped = result['skipped'] as int;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1A33),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.check_circle_rounded, color: kGreen, size: 22),
              SizedBox(width: 10),
              Text('Import Done', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              _ResultRow(icon: Icons.add_circle_rounded, color: kGreen, label: 'New contacts added', value: added),
              const SizedBox(height: 8),
              _ResultRow(icon: Icons.check_rounded, color: kPurple, label: 'Marked as done', value: marked),
              const SizedBox(height: 8),
              _ResultRow(icon: Icons.skip_next_rounded, color: kInkFaint, label: 'Skipped (already exists)', value: skipped),
            ]),
            actions: [
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kPurple, kPurpleDeep]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1A33),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.upload_rounded, color: kPurple, size: 22),
        SizedBox(width: 10),
        Text('Import Contacts', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Choose how to import numbers:', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13)),
          const SizedBox(height: 14),
          // Upload file option
          GestureDetector(
            onTap: _importing ? null : _pickFile,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: kPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kPurple.withOpacity(0.3)),
              ),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: kPurple.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.folder_open_rounded, color: kPurple, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Upload File', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('CSV, TXT, XLS or XLSX from your device', style: TextStyle(color: Color(0x77FFFFFF), fontSize: 11)),
                ])),
                Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.3)),
              ]),
            ),
          ),

          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => setState(() => _markDone = !_markDone),
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 20, height: 20,
                decoration: BoxDecoration(
                  color: _markDone ? kPurple : Colors.transparent,
                  border: Border.all(color: _markDone ? kPurple : Colors.white.withOpacity(0.25), width: 1.5),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: _markDone ? const Icon(Icons.check_rounded, color: Colors.white, size: 13) : null,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Mark as done for contacts already in directory',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4)))),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int value;
  const _ResultRow({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13))),
      Text(value.toString(), style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Export dialog
// ─────────────────────────────────────────────────────────────────────────────
class _ExportDialog extends StatefulWidget {
  final List<_Contact> contacts;
  final Future<void> Function(List<_Contact>, String, {bool inclHash}) onExport;
  const _ExportDialog({required this.contacts, required this.onExport});
  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  String _filter = 'all';
  bool _inclHash = false;
  bool _exporting = false;

  List<_Contact> get _selected {
    if (_filter == 'done') return widget.contacts.where((c) => c.markedDone).toList();
    if (_filter == 'pending') return widget.contacts.where((c) => !c.markedDone).toList();
    return widget.contacts;
  }

  Future<void> _doExport() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    Navigator.pop(context);
    await widget.onExport(_selected, _filter, inclHash: _inclHash);
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1A33),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.download_rounded, color: kPurple, size: 22),
        SizedBox(width: 10),
        Text('Export Numbers', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Which contacts to export:', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13)),
        const SizedBox(height: 12),
        _FilterOption(label: 'All numbers', sub: '${widget.contacts.length}', value: 'all', group: _filter, onTap: () => setState(() => _filter = 'all')),
        const SizedBox(height: 8),
        _FilterOption(label: 'Done only', sub: '${widget.contacts.where((c) => c.markedDone).length}', value: 'done', group: _filter, onTap: () => setState(() => _filter = 'done')),
        const SizedBox(height: 8),
        _FilterOption(label: 'Pending only', sub: '${widget.contacts.where((c) => !c.markedDone).length}', value: 'pending', group: _filter, onTap: () => setState(() => _filter = 'pending')),
        const SizedBox(height: 16),
        Text('Include columns:', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13)),
        const SizedBox(height: 8),
        _ColToggle(label: 'Hash Code (#1234)', checked: _inclHash, onTap: () => setState(() => _inclHash = !_inclHash)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(8)),
          child: Text('Saves as CSV to Downloads — open with Excel or Google Sheets',
              style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11)),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4)))),
        GestureDetector(
          onTap: (sel.isEmpty || _exporting) ? null : _doExport,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: sel.isEmpty ? null : const LinearGradient(colors: [kPurple, kPurpleDeep]),
              color: sel.isEmpty ? Colors.white.withOpacity(0.06) : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: _exporting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    sel.isEmpty ? 'Nothing to export' : 'Export ' + sel.length.toString() + ' contacts',
                    style: TextStyle(
                      color: sel.isEmpty ? Colors.white.withOpacity(0.3) : Colors.white,
                      fontWeight: FontWeight.w600, fontSize: 13,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ColToggle extends StatelessWidget {
  final String label;
  final bool checked;
  final bool enabled;
  final VoidCallback? onTap;
  const _ColToggle({required this.label, required this.checked, this.enabled = true, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 20, height: 20,
          decoration: BoxDecoration(
            color: checked ? kPurple.withOpacity(enabled ? 1 : 0.4) : Colors.transparent,
            border: Border.all(color: checked ? kPurple : Colors.white.withOpacity(0.25), width: 1.5),
            borderRadius: BorderRadius.circular(5),
          ),
          child: checked ? const Icon(Icons.check_rounded, color: Colors.white, size: 13) : null,
        ),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(
          color: enabled ? Colors.white.withOpacity(0.8) : Colors.white.withOpacity(0.35),
          fontSize: 13,
        )),
        if (!enabled) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(4)),
            child: Text('always', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10)),
          ),
        ],
      ]),
    );
  }
}

class _FilterOption extends StatelessWidget {
  final String label, sub, value, group;
  final VoidCallback onTap;
  const _FilterOption({required this.label, required this.sub, required this.value, required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sel = value == group;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: sel ? kPurple.withOpacity(0.14) : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sel ? kPurple.withOpacity(0.4) : Colors.transparent),
        ),
        child: Row(children: [
          Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: sel ? kPurple : Colors.white.withOpacity(0.3), size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(label,
              style: TextStyle(
                  color: sel ? Colors.white : Colors.white.withOpacity(0.7),
                  fontSize: 13, fontWeight: FontWeight.w600))),
          Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Stat chip
// ─────────────────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String label, sub;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  const _StatChip({required this.label, required this.sub, required this.color, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.22) : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color.withOpacity(0.7) : color.withOpacity(0.2), width: selected ? 1.5 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
          Text(sub, style: TextStyle(color: color.withOpacity(selected ? 0.9 : 0.65), fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Phone formatter (top-level so usable from _Contact and _ContactTile)
// ─────────────────────────────────────────────────────────────────────────────
const _kFmts = <(String, List<int>)>[
  ('+353', [2, 3, 4]), ('+966', [2, 3, 4]), ('+971', [2, 3, 4]),
  ('+968', [4, 4]),    ('+974', [4, 4]),    ('+973', [4, 4]),    ('+965', [4, 4]),
  ('+92',  [3, 7]),    ('+64',  [2, 3, 4]), ('+61',  [3, 3, 3]),
  ('+49',  [3, 7]),    ('+47',  [3, 2, 3]), ('+46',  [3, 3, 3]),
  ('+45',  [2, 2, 2, 2]), ('+44', [4, 6]), ('+39',  [3, 7]),
  ('+34',  [3, 6]),    ('+33',  [1, 2, 2, 2, 2]), ('+31', [1, 4, 4]),
  ('+30',  [3, 7]),    ('+90',  [3, 3, 4]), ('+60',  [2, 4, 4]),
  ('+1',   [3, 3, 4]), ('+91',  [5, 5]),   ('+880', [4, 6]),
  ('+94',  [2, 7]),    ('+98',  [3, 8]),   ('+962', [1, 4, 4]),
  ('+964', [3, 4, 4]), ('+963', [2, 4, 4]),
];

String _fmtStoredPhone(String stored) {
  final t = stored.trim();
  if (t.startsWith('+')) {
    final sorted = _kFmts.toList()
      ..sort((a, b) => b.$1.length.compareTo(a.$1.length));
    for (final f in sorted) {
      if (t.startsWith(f.$1)) {
        final raw = t.substring(f.$1.length).replaceAll(RegExp(r'[^\d]'), '');
        return '${f.$1} ${_groupDigits(raw, f.$2)}';
      }
    }
    return t;
  }
  // Legacy: bare digits starting with 0 → treat as Pakistan +92
  if (t.replaceAll(RegExp(r'[^\d]'), '').length >= 10) {
    final digits = t.replaceAll(RegExp(r'[^\d]'), '');
    final local = digits.startsWith('0') ? digits.substring(1) : digits;
    return '+92 ${_groupDigits(local, [3, 7])}';
  }
  return t;
}

String _groupDigits(String digits, List<int> groups) {
  final parts = <String>[];
  var pos = 0;
  for (final g in groups) {
    if (pos >= digits.length) break;
    parts.add(digits.substring(pos, (pos + g).clamp(0, digits.length)));
    pos += g;
  }
  if (pos < digits.length) parts.add(digits.substring(pos));
  return parts.join(' ');
}

// ─────────────────────────────────────────────────────────────────────────────
//  Data model
// ─────────────────────────────────────────────────────────────────────────────
class _Contact {
  final String id;
  final String phone;
  final String? name;
  final int? proposalNumber;
  final bool markedDone;
  final DateTime createdAt;
  final DateTime? deletedAt;

  const _Contact({
    required this.id,
    required this.phone,
    this.name,
    this.proposalNumber,
    required this.markedDone,
    required this.createdAt,
    this.deletedAt,
  });

  String get displayPhone => _fmtStoredPhone(phone);
  String? get hashCode_ => proposalNumber != null ? '#$proposalNumber' : null;
  bool get isDeleted => deletedAt != null;

  factory _Contact.fromJson(Map<String, dynamic> json) => _Contact(
    id: json['id'] as String,
    phone: json['phone'] as String,
    name: json['name'] as String?,
    proposalNumber: (json['proposal_number'] as num?)?.toInt(),
    markedDone: json['marked_done'] as bool? ?? false,
    createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    deletedAt: json['deleted_at'] != null ? DateTime.tryParse(json['deleted_at'] as String) : null,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Marketing Trash Screen
// ─────────────────────────────────────────────────────────────────────────────
class _MarketingTrashScreen extends StatefulWidget {
  final dynamic client;
  const _MarketingTrashScreen({required this.client});
  @override
  State<_MarketingTrashScreen> createState() => _MarketingTrashScreenState();
}

class _MarketingTrashScreenState extends State<_MarketingTrashScreen> {
  List<_Contact> _trashed = [];
  bool _loading = true;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await widget.client
          .from('marketing_contacts')
          .select()
          .not('deleted_at', 'is', null)
          .order('deleted_at', ascending: false) as List;
      setState(() => _trashed = rows.map((r) => _Contact.fromJson(r as Map<String, dynamic>)).toList());
    } catch (e) {
      debugPrint('Trash load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restore(List<String> ids) async {
    for (final id in ids) {
      await widget.client.from('marketing_contacts').update({'deleted_at': null}).eq('id', id);
    }
    setState(() => _selectedIds.clear());
    await _load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Restored ${ids.length} contact${ids.length > 1 ? 's' : ''}'),
      backgroundColor: const Color(0xFF1E1A33),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _permanentDelete(List<String> ids) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Permanently', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('Permanently delete ${ids.length} contact${ids.length > 1 ? 's' : ''}? This cannot be undone.',
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: kRose, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    for (final id in ids) {
      await widget.client.from('marketing_contacts').delete().eq('id', id);
    }
    setState(() => _selectedIds.clear());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16132A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _selectedIds.isEmpty ? 'Trash (${_trashed.length})' : '${_selectedIds.length} selected',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_selectedIds.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => _restore(_selectedIds.toList()),
              icon: const Icon(Icons.restore, color: kGreen, size: 18),
              label: const Text('Restore', style: TextStyle(color: kGreen, fontWeight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: () => _permanentDelete(_selectedIds.toList()),
              icon: const Icon(Icons.delete_forever, color: kRose, size: 18),
              label: const Text('Delete', style: TextStyle(color: kRose, fontWeight: FontWeight.w600)),
            ),
          ] else if (_trashed.isNotEmpty) ...[
            TextButton(
              onPressed: () => _permanentDelete(_trashed.map((c) => c.id).toList()),
              child: const Text('Empty', style: TextStyle(color: kRose, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPurple))
          : _trashed.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.delete_outline_rounded, color: Colors.white.withOpacity(0.12), size: 52),
                  const SizedBox(height: 14),
                  Text('Trash is empty', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 15)),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _trashed.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final c = _trashed[i];
                    final isSelected = _selectedIds.contains(c.id);
                    return GestureDetector(
                      onLongPress: () {
                        HapticFeedback.mediumImpact();
                        setState(() {
                          if (isSelected) _selectedIds.remove(c.id);
                          else _selectedIds.add(c.id);
                        });
                      },
                      onTap: _selectedIds.isNotEmpty ? () {
                        setState(() {
                          if (isSelected) _selectedIds.remove(c.id);
                          else _selectedIds.add(c.id);
                        });
                      } : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? kRose.withOpacity(0.08) : const Color(0xFF1A1730),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: isSelected ? kPurple.withOpacity(0.5) : Colors.white.withOpacity(0.07),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.displayPhone, style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: Colors.white.withOpacity(0.3),
                            )),
                            if (c.hashCode_ != null)
                              Text(c.hashCode_!, style: TextStyle(color: kPurple.withOpacity(0.5), fontSize: 12, fontWeight: FontWeight.w600)),
                          ])),
                          // Restore button
                          GestureDetector(
                            onTap: () => _restore([c.id]),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: kGreen.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: kGreen.withOpacity(0.3)),
                              ),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.restore_rounded, color: kGreen, size: 14),
                                SizedBox(width: 4),
                                Text('Restore', style: TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Permanent delete
                          GestureDetector(
                            onTap: () => _permanentDelete([c.id]),
                            child: const Icon(Icons.delete_forever, color: kRose, size: 20),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
