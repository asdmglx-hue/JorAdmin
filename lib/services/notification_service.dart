// ── notification_service.dart ─────────────────────────────────────────────
// DB-backed notification history (notification_log table) + local system
// tray display.
//
// All backend/DB-trigger-driven notifications (approved, rejected, paused,
// resumed, featured, etc.) are logged server-side by the notify-status-change
// edge function itself, BEFORE it sends the push — this class never writes
// those rows. It only:
//   - Shows the tray notification when the OS won't do it automatically
//     (foreground FCM messages — background/terminated ones are shown by
//     the OS directly from the push payload, no app code needed)
//   - Reads notification_log for the bell / history screen
//   - Writes exactly ONE type of row directly: "Profile Submitted", which
//     is a same-device confirmation that never goes through the backend
//
// This design also sidesteps the local-storage race conditions and stale
// in-memory caching this file used to have — Postgres is now the single
// source of truth, and every screen just re-reads it.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kAndroidChannelId = 'rishta_v2';
const _kAndroidChannelName = 'Rishta Notifications';
const _kHistoryLimit = 50;

class AppNotification {
  final String id; // notification_log row id (uuid)
  final String title;
  final String body;
  final DateTime time;
  bool read;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    this.read = false,
  });

  factory AppNotification.fromRow(Map<String, dynamic> row) => AppNotification(
        id: row['id'] as String,
        title: row['title'] as String,
        body: row['body'] as String,
        time: DateTime.parse(row['created_at'] as String),
        read: row['read_at'] != null,
      );
}

class NotificationService extends ChangeNotifier with WidgetsBindingObserver {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  List<AppNotification> _history = [];
  List<AppNotification> get history => List.unmodifiable(_history);
  bool get hasUnread => _history.any((n) => !n.read);

  Future<void> init() async {
    if (_initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        // Permission is already requested by FCMService.init() — don't
        // trigger a second native permission prompt here.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      _initialized = true;
      await refresh();
      // Keep the visible history in sync with the DB whenever the app
      // returns to the foreground — e.g. after a background push was
      // logged server-side while the app wasn't running.
      WidgetsBinding.instance.addObserver(this);
      debugPrint('[NOTIF] NotificationService initialized — '
          '${_history.length} item(s) in history');
    } catch (e) {
      debugPrint('[NOTIF] init error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[NOTIF] app resumed — refreshing history from DB');
      refresh();
    }
  }

  Future<String?> _currentProposalId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('user_proposal_id');
    return (id != null && id.isNotEmpty) ? id : null;
  }

  /// Reloads the visible history from notification_log for whichever
  /// profile is currently active on this device. Safe to call anytime —
  /// it's a plain read, no local write races possible.
  Future<void> refresh() async {
    try {
      final proposalId = await _currentProposalId();
      if (proposalId == null) {
        _history = [];
        return;
      }
      final rows = await Supabase.instance.client
          .from('notification_log')
          .select()
          .eq('proposal_id', proposalId)
          .order('created_at', ascending: false)
          .limit(_kHistoryLimit);
      _history = (rows as List)
          .map((r) => AppNotification.fromRow(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[NOTIF] refresh error: $e');
    } finally {
      notifyListeners();
    }
  }

  Future<void> _showTray(String title, String body) async {
    if (!_initialized) {
      debugPrint('[NOTIF] _showTray — service not initialized, skipping '
          'system tray notification for "$title"');
      return;
    }
    const androidDetails = AndroidNotificationDetails(
      _kAndroidChannelId,
      _kAndroidChannelName,
      channelDescription: 'Profile and proposal updates',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final systemId = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    await _plugin.show(
      systemId,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
    debugPrint('[NOTIF] tray shown — id=$systemId title="$title"');
  }

  // ── Notification: profile submitted ─────────────────────────────────────
  // The one notification type that never goes through the backend — this
  // is a same-device confirmation of the user's own just-taken action, so
  // it's logged directly here rather than round-tripping through an edge
  // function for no benefit.
  Future<void> notifyProposalSubmitted(String proposalId) async {
    const title = 'Profile Submitted ✅';
    const body = "Your profile is pending admin approval. It may take up to "
        "24 hours. You'll be notified once it's approved.";
    try {
      await Supabase.instance.client.from('notification_log').insert({
        'proposal_id': proposalId,
        'type': 'proposal_submitted',
        'title': title,
        'body': body,
        'status': 'local',
      });
    } catch (e) {
      debugPrint('[NOTIF] notifyProposalSubmitted log error: $e');
    }
    await _showTray(title, body);
    await refresh();
  }

  // ── Incoming push (foreground) ──────────────────────────────────────────
  // The backend already wrote this notification to notification_log before
  // sending it — all this needs to do is show the tray banner (the OS
  // won't do that automatically for foreground messages) and pull the
  // fresh row into view.
  Future<void> notifyFromPush(String title, String body) async {
    await _showTray(title, body);
    await refresh();
  }

  // ── Bell / history maintenance ───────────────────────────────────────────
  Future<void> markAllRead() async {
    final unread = _history.where((n) => !n.read).toList();
    if (unread.isEmpty) return;
    try {
      await Supabase.instance.client
          .from('notification_log')
          .update({'read_at': DateTime.now().toIso8601String()})
          .inFilter('id', unread.map((n) => n.id).toList());
      for (final n in unread) {
        n.read = true;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[NOTIF] markAllRead error: $e');
    }
  }
}
