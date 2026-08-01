// ── notification_screen.dart ──────────────────────────────────────────────
// Shows the in-app notification history from NotificationService.
// Minimal by design — one notification type wired up so far
// (see notification_service.dart notifyProposalSubmitted()).
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../utils/theme.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});
  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _svc = NotificationService.instance;

  @override
  void initState() {
    super.initState();
    _svc.addListener(_onChanged);
    // Always show what's actually on disk, then mark it read.
    _svc.refresh().then((_) {
      _svc.markAllRead();
    });
  }

  @override
  void dispose() {
    _svc.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final history = _svc.history;
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kCardBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: kInk),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Notifications',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: kInk)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kBorder),
        ),
      ),
      body: history.isEmpty ? _buildEmpty() : _buildList(history),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none_rounded,
              size: 56, color: kInkFaint.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text('No notifications yet',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: kInkFaint)),
          const SizedBox(height: 4),
          Text('Updates about your profile will appear here',
              style:
                  TextStyle(fontSize: 12, color: kInkFaint.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _buildList(List<AppNotification> history) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: history.length,
      separatorBuilder: (_, __) => Container(
        height: 1,
        color: kBorder,
        margin: const EdgeInsets.symmetric(horizontal: 16),
      ),
      itemBuilder: (_, i) => _buildItem(history[i]),
    );
  }

  Widget _buildItem(AppNotification n) {
    return Container(
      color: n.read ? Colors.transparent : kPurple.withOpacity(0.04),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: kPurple.withOpacity(0.12),
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
                        color: kInk,
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
                    style:
                        TextStyle(fontSize: 12, color: kInkLight, height: 1.4)),
                const SizedBox(height: 5),
                Text(_timeAgo(n.time),
                    style: TextStyle(fontSize: 11, color: kInkFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
