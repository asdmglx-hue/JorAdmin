import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/theme.dart';
import '../services/supabase_service.dart';

// ── Usage Stats — proactive monitoring dashboard ────────────────────────────
// Calls the admin-usage-stats edge function (Cloudflare Worker requests /
// CPU time via Cloudflare's GraphQL Analytics API). Built specifically to
// close the "found out via an outage, not a warning" gap from the Error
// 1027 rate-limit incident — a way to actually see traffic trending toward
// a problem, rather than only discovering it after the site goes down.
//
// Deliberately does NOT attempt to show Supabase egress here: there's no
// simple, stable "give me a usage total" Management API endpoint currently
// documented for that (the closest options are experimental log-query
// endpoints), and shipping something built on a shaky foundation felt
// worse than being upfront about the gap. The "Open Supabase Usage
// Dashboard" button below links directly to the real, reliable source
// for that number instead.
// Safely converts a value from an edge function's JSON response to an
// int, regardless of whether it actually arrived as an int, a double, or
// a string (Cloudflare's own APIs have been confirmed to return large
// numbers as strings in some cases — this is what caused a real crash
// here once already). Used everywhere a numeric field from a response is
// displayed, instead of a bare `as int` that would crash the whole
// screen if the type ever doesn't match exactly what's expected.
int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.round() ?? 0;
  return 0;
}

class AdminUsageStatsScreen extends StatefulWidget {
  const AdminUsageStatsScreen({super.key});
  @override
  State<AdminUsageStatsScreen> createState() => _AdminUsageStatsScreenState();
}

class _AdminUsageStatsScreenState extends State<AdminUsageStatsScreen> {
  bool _loading = true;
  String? _error;
  bool _setupNeeded = false;
  List<String> _missingKeys = [];
  Map<String, dynamic>? _stats;

  bool _scanning = false;
  String? _scanError;
  Map<String, dynamic>? _scanResult;

  bool _deleting = false;
  String? _deleteError;
  String? _deleteSuccessMsg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _runScan() async {
    setState(() { _scanning = true; _scanError = null; });
    try {
      final res = await SupabaseService.instance.client.functions.invoke('admin-storage-scan');
      final data = res.data as Map<String, dynamic>;
      if (data['error'] != null) {
        setState(() { _scanError = data['error'].toString(); _scanning = false; });
        return;
      }
      setState(() { _scanResult = data; _scanning = false; });
    } catch (e) {
      setState(() { _scanError = 'Scan failed: $e'; _scanning = false; });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1073741824) return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await SupabaseService.instance.client.functions.invoke('admin-usage-stats');
      final data = res.data as Map<String, dynamic>;
      if (data['setup_needed'] == true) {
        setState(() {
          _setupNeeded = true;
          _missingKeys = List<String>.from(data['missing'] ?? []);
          _loading = false;
        });
        return;
      }
      if (data['error'] != null) {
        setState(() { _error = data['error'].toString(); _loading = false; });
        return;
      }
      setState(() { _stats = data; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Could not load usage stats: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF16132A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16132A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Usage & Monitoring', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: kPurple,
        backgroundColor: const Color(0xFF1E1A33),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading && _stats == null && !_setupNeeded && _error == null) ...[
              const SizedBox(height: 120),
              const Center(child: CircularProgressIndicator(color: kPurple)),
            ] else if (_setupNeeded) ...[
              _setupCard(),
            ] else if (_error != null) ...[
              _errorCard(_error!),
            ] else if (_stats != null) ...[
              _cloudflareSection(_stats!),
            ],
            const SizedBox(height: 20),
            _storageScanCard(),
            const SizedBox(height: 20),
            _supabaseLinkCard(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _setupCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF1E1A33), borderRadius: BorderRadius.circular(16), border: Border.all(color: kAmber.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.settings_suggest_rounded, color: kAmber, size: 20),
          const SizedBox(width: 8),
          const Text('One-time setup needed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        const SizedBox(height: 10),
        Text(
          'Cloudflare Worker stats aren\'t connected yet. This needs a Cloudflare API token set up once (by whoever manages the Supabase project directly — not from this app, since it\'s a sensitive credential).',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, height: 1.5),
        ),
        if (_missingKeys.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Missing: ${_missingKeys.join(", ")}', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12, fontFamily: 'monospace')),
        ],
      ]),
    );
  }

  Widget _errorCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFF1E1A33), borderRadius: BorderRadius.circular(16), border: Border.all(color: kRose.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.error_outline_rounded, color: kRose, size: 20),
          const SizedBox(width: 8),
          const Text('Could not load stats', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        const SizedBox(height: 8),
        Text(msg, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.5)),
      ]),
    );
  }

  Widget _cloudflareSection(Map<String, dynamic> s) {
    final requestsToday = s['requestsToday'] ?? 0;
    final requestsLast7Days = s['requestsLast7Days'] ?? 0;
    final avgCpuTimeMs = s['avgCpuTimeMs'];
    final errorsToday = s['errorsToday'] ?? 0;
    final requestsThisMonth = _toInt(s['requestsThisMonth']);
    final cpuMsThisMonth = _toInt(s['estimatedCpuMsThisMonth']);
    final truncated = s['monthDataPossiblyTruncated'] == true;

    final plan = s['plan'] as Map<String, dynamic>?;
    final requestsIncluded = _toInt(plan?['requestsIncludedPerMonth'] ?? 10000000);
    final cpuMsIncluded = _toInt(plan?['cpuMsIncludedPerMonth'] ?? 30000000);

    final requestPct = (requestsThisMonth / requestsIncluded * 100).clamp(0, 999);
    final cpuPct = (cpuMsThisMonth / cpuMsIncluded * 100).clamp(0, 999);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('CLOUDFLARE WORKER — PAID PLAN', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
      const SizedBox(height: 10),

      // Month-to-date, against actual plan allowances — the numbers that
      // actually matter for "are we going to get charged extra / hit a
      // limit", unlike a bare today/7-day count with nothing to compare against.
      _limitCard(
        label: 'Requests this month',
        used: requestsThisMonth,
        included: requestsIncluded,
        pct: requestPct,
        formatValue: (v) => _formatNum(v),
      ),
      const SizedBox(height: 10),
      _limitCard(
        label: 'CPU time this month (estimated)',
        used: cpuMsThisMonth,
        included: cpuMsIncluded,
        pct: cpuPct,
        formatValue: (v) => '${_formatNum(v)} ms',
      ),
      if (truncated) ...[
        const SizedBox(height: 8),
        Text('Note: this month has a lot of data — the CPU-time estimate above may be undercounting slightly.',
          style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11, fontStyle: FontStyle.italic)),
      ],

      const SizedBox(height: 18),
      const Text('TODAY & RECENT', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _statCard('Requests Today', _formatNum(requestsToday), Icons.today_rounded, kPurple)),
        const SizedBox(width: 10),
        Expanded(child: _statCard('Last 7 Days', _formatNum(requestsLast7Days), Icons.calendar_view_week_rounded, kPurple)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _statCard('Avg CPU Time', avgCpuTimeMs != null ? '${avgCpuTimeMs}ms' : '—', Icons.speed_rounded, kAmber)),
        Expanded(child: _statCard('Errors Today', errorsToday.toString(), Icons.warning_amber_rounded, errorsToday > 0 ? kRose : Colors.white38)),
      ]),

      const SizedBox(height: 18),
      _r2StorageCard(s),
    ]);
  }

  Widget _r2StorageCard(Map<String, dynamic> s) {
    if (s['r2Error'] != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kAmber.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: kAmber.withOpacity(0.3))),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, color: kAmber, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(s['r2Error'].toString(), style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, height: 1.4))),
        ]),
      );
    }

    final storageBytes = _toInt(s['r2StorageBytes']);
    final objectCount = s['r2ObjectCount'] ?? 0;
    final freeStorageBytes = _toInt(s['plan']?['r2FreeStorageBytes'] ?? 10737418240);
    final pct = (storageBytes / freeStorageBytes * 100).clamp(0, 999);
    final color = pct > 90 ? kRose : pct > 70 ? kAmber : kPurple;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E1A33), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('R2 Storage', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
          const Spacer(),
          Text('${pct.toStringAsFixed(1)}%', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13.5)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0, 1).toDouble(),
            minHeight: 6,
            backgroundColor: Colors.white.withOpacity(0.08),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 8),
        Text('${_formatBytes(storageBytes)} of ${_formatBytes(freeStorageBytes)} free tier — $objectCount objects',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11.5)),
        if (pct > 100) ...[
          const SizedBox(height: 4),
          Text('Over the free tier — billed at \$0.015/GB beyond this', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10.5)),
        ],
      ]),
    );
  }

  String _formatNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  Widget _limitCard({required String label, required int used, required int included, required num pct, required String Function(int) formatValue}) {
    final color = pct > 90 ? kRose : pct > 70 ? kAmber : kPurple;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E1A33), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5))),
          Text('${pct.toStringAsFixed(1)}%', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13.5)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0, 1).toDouble(),
            minHeight: 6,
            backgroundColor: Colors.white.withOpacity(0.08),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 8),
        Text('${formatValue(used)} of ${formatValue(included)} included this month',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11.5)),
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E1A33), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.06))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 10),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11.5)),
      ]),
    );
  }

  Widget _categoryRow(String label, String description, int count, int sizeBytes, Color color) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 5), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('$count · ${_formatBytes(sizeBytes)}', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 2),
          Text(description, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10.5, height: 1.3)),
        ]),
      ),
    ]);
  }

  Future<void> _confirmAndDelete() async {
    if (_scanResult == null) return;
    final count = _toInt(_scanResult!['safeToDeleteCount']);
    final size = _toInt(_scanResult!['safeToDeleteSizeBytes']);
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1A33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete unused photos?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text(
          'This will permanently delete $count files (${_formatBytes(size)}) — old replaced photos and photos from deleted profiles. This cannot be undone.\n\nFiles from the last 3 days are never touched, regardless of this scan.',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.4)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kRose, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete $count Files'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() { _deleting = true; _deleteError = null; _deleteSuccessMsg = null; });
    try {
      final res = await SupabaseService.instance.client.functions.invoke('admin-storage-delete');
      final data = res.data as Map<String, dynamic>;
      if (data['error'] != null) {
        setState(() { _deleteError = data['error'].toString(); _deleting = false; });
        return;
      }
      final deletedCount = data['deletedCount'] ?? 0;
      final deletedSize = data['deletedSizeBytes'] ?? 0;
      final partialErrors = data['errors'] as List?;
      setState(() {
        _deleting = false;
        _deleteSuccessMsg = partialErrors != null && partialErrors.isNotEmpty
            ? 'Deleted $deletedCount files (${_formatBytes(_toInt(deletedSize))}) — but ${partialErrors.length} batch(es) had errors, see below'
            : 'Deleted $deletedCount files (${_formatBytes(_toInt(deletedSize))})';
        _deleteError = partialErrors != null && partialErrors.isNotEmpty ? partialErrors.first.toString() : null;
        _scanResult = null; // force a fresh scan next time, old numbers are now stale
      });
      // Refresh automatically so the card reflects the new, accurate state.
      await _runScan();
    } catch (e) {
      setState(() { _deleteError = 'Delete failed: $e'; _deleting = false; });
    }
  }

  Widget _storageScanCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF1E1A33), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.06))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.folder_delete_outlined, color: Colors.white38, size: 20),
          const SizedBox(width: 12),
          const Expanded(child: Text('Unused Photo Storage', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14))),
        ]),
        const SizedBox(height: 4),
        Text(
          'Finds photos in storage that no longer belong to any existing profile. Scan only for now — nothing gets deleted here yet.',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11.5, height: 1.4),
        ),
        const SizedBox(height: 12),
        if (_scanResult != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_scanResult!['totalObjects']} total files — ${_formatBytes(_toInt(_scanResult!['totalSizeBytes']))}',
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const Divider(color: Colors.white12, height: 20),
              _categoryRow(
                'Photo was replaced',
                'Old file left behind after a profile uploaded a newer one — profile still exists',
                _toInt(_scanResult!['categories']['replacedPhoto']['count']),
                _toInt(_scanResult!['categories']['replacedPhoto']['sizeBytes']),
                kAmber,
              ),
              const SizedBox(height: 10),
              _categoryRow(
                'Profile no longer exists',
                'The whole profile this belonged to has been deleted',
                _toInt(_scanResult!['categories']['deletedProfile']['count']),
                _toInt(_scanResult!['categories']['deletedProfile']['sizeBytes']),
                kAmber,
              ),
              const SizedBox(height: 10),
              _categoryRow(
                'Too recent to touch',
                'Looks orphaned but under ${_scanResult!['safeAgeDays']} days old — never included in delete',
                _toInt(_scanResult!['categories']['tooRecent']['count']),
                _toInt(_scanResult!['categories']['tooRecent']['sizeBytes']),
                Colors.white38,
              ),
              const Divider(color: Colors.white12, height: 20),
              Text(
                'Safe to delete: ${_scanResult!['safeToDeleteCount']} files — ${_formatBytes(_toInt(_scanResult!['safeToDeleteSizeBytes']))}',
                style: const TextStyle(color: kPurple, fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        if (_scanError != null) ...[
          Text(_scanError!, style: const TextStyle(color: kRose, fontSize: 12)),
          const SizedBox(height: 10),
        ],
        if (_deleteError != null) ...[
          Text(_deleteError!, style: const TextStyle(color: kRose, fontSize: 12)),
          const SizedBox(height: 10),
        ],
        if (_deleteSuccessMsg != null) ...[
          Text(_deleteSuccessMsg!, style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _scanning ? null : _runScan,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: kPurple.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: _scanning
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: kPurple, strokeWidth: 2))
                : Text(_scanResult == null ? 'Scan for Unused Photos' : 'Scan Again', style: const TextStyle(color: kPurple, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ),
        if (_scanResult != null && (_toInt(_scanResult!['safeToDeleteCount'])) > 0) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _deleting ? null : _confirmAndDelete,
              style: ElevatedButton.styleFrom(
                backgroundColor: kRose, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _deleting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Delete ${_scanResult!['safeToDeleteCount']} Safe Files', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _supabaseLinkCard() {
    // Confirmed via Supabase's own documentation: there's no reliable API
    // for egress specifically — even Supabase's docs point people to this
    // exact dashboard page (or Custom Reports) rather than an API, and
    // their Logs Explorer explicitly doesn't include response-byte data.
    // Building something on an experimental/undocumented endpoint for a
    // number you'd actually make decisions from felt worse than being
    // upfront and just making the real source one tap away instead.
    const url = 'https://supabase.com/dashboard/org/kscqrremkytftooljfda/usage#egress';
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(url), mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF1E1A33), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.06))),
        child: Row(children: [
          const Icon(Icons.storage_rounded, color: Colors.white38, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Supabase Egress — tap to view', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          Icon(Icons.open_in_new_rounded, color: Colors.white.withOpacity(0.3), size: 18),
        ]),
      ),
    );
  }
}
