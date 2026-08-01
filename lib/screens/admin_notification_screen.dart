// ── admin_notification_screen.dart ────────────────────────────────────────
// Full-screen notification history for the admin app — same layout as the
// user app's notification_screen.dart (app bar, empty state, list items with
// icon/title/dot/body/time), but recolored to match the admin app's own dark
// theme instead of the shared light theme.dart used elsewhere.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/theme.dart' show kPurple;

const _kBg = Color(0xFF0F0D1A);
const _kCard = Color(0xFF16132A);
const _kBorder = Color(0x14FFFFFF); // white @ 8%

class AdminNotificationScreen extends StatefulWidget {
  const AdminNotificationScreen({super.key});
  @override
  State<AdminNotificationScreen> createState() => _AdminNotificationScreenState();
}

class _NotifItem {
  final String title;
  final String body;
  final DateTime time;
  final bool read;
  _NotifItem({required this.title, required this.body, required this.time, required this.read});
}

class _AdminNotificationScreenState extends State<AdminNotificationScreen> {
  final _client = Supabase.instance.client;
  List<_NotifItem> _history = [];
  bool _loading = true;

  // Same pagination convention as the user app's notification screen:
  // show a comfortable first page, reveal more via "Load more" instead of
  // dumping the whole (up to 50) history into one long scroll.
  static const _kPageSize = 10;
  int _visibleCount = _kPageSize;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _client
          .from('notification_log')
          .select()
          .eq('type', 'new_order')
          .order('created_at', ascending: false)
          .limit(50);
      final rows = (res as List).cast<Map<String, dynamic>>();
      final history = rows.map((n) {
        final created = DateTime.tryParse(n['created_at'] as String? ?? '') ?? DateTime.now();
        return _NotifItem(
          title: n['title'] as String? ?? '',
          body: n['body'] as String? ?? '',
          time: created.isUtc ? created.toLocal() : created,
          read: n['read_at'] != null,
        );
      }).toList();
      if (mounted) setState(() { _history = history; _loading = false; });

      // Always show what's actually on disk, then mark it read.
      final unreadIds = rows.where((n) => n['read_at'] == null).map((n) => n['id']).toList();
      if (unreadIds.isNotEmpty) {
        await _client
            .from('notification_log')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .inFilter('id', unreadIds);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  static const _kMonths = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  String _dateLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diffDays = today.difference(day).inDays;
    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';
    return '${_kMonths[t.month - 1]} ${t.day}, ${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: Colors.white.withOpacity(0.9)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Notifications',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _kBorder),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPurple))
          : _history.isEmpty
              ? _buildEmpty()
              : _buildList(_history),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none_rounded,
              size: 56, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 12),
          Text('No notifications yet',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withOpacity(0.4))),
          const SizedBox(height: 4),
          Text('New orders will appear here',
              style:
                  TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.25))),
        ],
      ),
    );
  }

  Widget _buildList(List<_NotifItem> history) {
    final visible = history.take(_visibleCount).toList();
    final hasMore = _visibleCount < history.length;

    final items = <Widget>[];
    String? lastLabel;
    for (final n in visible) {
      final label = _dateLabel(n.time);
      if (label != lastLabel) {
        items.add(Padding(
          padding: EdgeInsets.fromLTRB(16, lastLabel == null ? 12 : 18, 16, 8),
          child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.35), letterSpacing: 0.3)),
        ));
        lastLabel = label;
      } else {
        items.add(Container(height: 1, color: _kBorder, margin: const EdgeInsets.symmetric(horizontal: 16)));
      }
      items.add(_buildItem(n));
    }

    if (hasMore) {
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: GestureDetector(
            onTap: () => setState(() => _visibleCount = (_visibleCount + _kPageSize).clamp(0, history.length)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: kPurple.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Load more', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kPurple)),
            ),
          ),
        ),
      ));
    }

    return ListView(
      padding: EdgeInsets.only(bottom: 8 + MediaQuery.of(context).padding.bottom),
      children: items,
    );
  }

  Widget _buildItem(_NotifItem n) {
    return Container(
      color: n.read ? Colors.transparent : kPurple.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: kPurple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.notifications_rounded,
                color: kPurple, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      n.title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            n.read ? FontWeight.w600 : FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (!n.read)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(left: 6, top: 2),
                      decoration: const BoxDecoration(
                          color: kPurple, shape: BoxShape.circle),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(n.body,
                    style: TextStyle(
                        fontSize: 12, color: Colors.white.withOpacity(0.6), height: 1.4)),
                const SizedBox(height: 5),
                Text(_timeAgo(n.time),
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
