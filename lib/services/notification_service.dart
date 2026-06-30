// ── notification_service.dart ─────────────────────────────────────────────────
// On-device notification system using flutter_local_notifications.
// Handles: expiry warnings, status changes, new proposals digest, toggle.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

// ── Notification IDs (stable, never change) ───────────────────────────────────
const _kIdExpiryWarning    = 1001;
const _kIdStatusChange     = 1002;
const _kIdNewProposals     = 1003;
const _kIdSubmission       = 1005;
const _kIdPendingReminder  = 1006;

// ── SharedPreferences keys ────────────────────────────────────────────────────
const _kNotifEnabled       = 'notif_enabled';
const _kNewProposalCount   = 'notif_new_prop_count';
const _kLastProposalNotif  = 'notif_last_prop_date'; // yyyy-MM-dd

String _historyKey(String cnic) => 'notif_history_$cnic';
String _unreadKey(String cnic)  => 'notif_has_unread_$cnic';

// ── Logging helper ────────────────────────────────────────────────────────────
void _log(String trigger, String screen, String title, String body, {bool vibration = true, String extra = ''}) {
  final ts = DateTime.now().toIso8601String();
  debugPrint('╔══ [NOTIF] ══════════════════════════════════════');
  debugPrint('║ Time     : $ts');
  debugPrint('║ Trigger  : $trigger');
  debugPrint('║ Screen   : $screen');
  debugPrint('║ Title    : $title');
  debugPrint('║ Body     : $body');
  debugPrint('║ Vibration: ${vibration ? "YES ✓" : "NO ✗"}');
  if (extra.isNotEmpty) debugPrint('║ Info     : $extra');
  debugPrint('╚═════════════════════════════════════════════════');
}

// ── In-app notification model ─────────────────────────────────────────────────
class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime time;
  final String type; // 'expiry' | 'status' | 'proposals'
  bool read;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    required this.type,
    this.read = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'body': body,
    'time': time.toIso8601String(), 'type': type, 'read': read,
  };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: j['id'] as String,
    title: j['title'] as String,
    body: j['body'] as String,
    time: DateTime.parse(j['time'] as String),
    type: j['type'] as String,
    read: j['read'] as bool? ?? false,
  );
}

// ── NotificationService ───────────────────────────────────────────────────────
class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _enabled = true;
  bool _hasUnread = false;
  List<AppNotification> _history = [];
  DateTime? _lastSystemNotifTime; // track when last system notif was shown
  String _currentUserKey = 'guest';

  bool get enabled => _enabled;
  bool get hasUnread => _hasUnread;
  List<AppNotification> get history => List.unmodifiable(_history);

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    debugPrint('[NOTIF] init() — initializing NotificationService');
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Karachi'));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    await _requestPermission();
    final prefs = await SharedPreferences.getInstance();
    String savedKey = prefs.getString('notif_current_user_key') ?? 'guest';
    if (savedKey == 'guest') {
      final cnic = prefs.getString('user_cnic') ?? '';
      if (cnic.isNotEmpty) savedKey = cnic;
    }
    _currentUserKey = savedKey;
    debugPrint('[NOTIF] init() — restored user key: $_currentUserKey');
    await _loadPrefs();
    notifyListeners();
    debugPrint('[NOTIF] init() — complete. enabled=$_enabled hasUnread=$_hasUnread history=${_history.length} items');
  }

  Future<void> _requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled   = prefs.getBool(_kNotifEnabled) ?? true;
    _hasUnread = prefs.getBool(_unreadKey(_currentUserKey)) ?? false;
    final raw  = prefs.getString(_historyKey(_currentUserKey));
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _history = list.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)).toList();
        _history.sort((a, b) => b.time.compareTo(a.time));
      } catch (_) { _history = []; }
    } else {
      _history = [];
    }
    debugPrint('[NOTIF] _loadPrefs() — user=$_currentUserKey enabled=$_enabled hasUnread=$_hasUnread history=${_history.length} items');
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_historyKey(_currentUserKey), jsonEncode(_history.map((n) => n.toJson()).toList()));
    await prefs.setBool(_unreadKey(_currentUserKey), _hasUnread);
  }

  // ── Switch user ───────────────────────────────────────────────────────────
  Future<void> switchUser(String cnic) async {
    debugPrint('[NOTIF] switchUser() — from=$_currentUserKey to=${cnic.isEmpty ? "guest" : cnic}');
    await _saveHistory();
    _currentUserKey = cnic.isEmpty ? 'guest' : cnic;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('notif_current_user_key', _currentUserKey);
    await _loadPrefs();
    notifyListeners();
    debugPrint('[NOTIF] switchUser() — complete. now user=$_currentUserKey');
  }

  // ── Toggle all notifications ──────────────────────────────────────────────
  Future<void> setEnabled(bool value) async {
    debugPrint('[NOTIF] setEnabled($value) — notifications ${value ? "ENABLED" : "DISABLED"}');
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotifEnabled, value);
    if (!value) await _plugin.cancelAll();
    notifyListeners();
  }

  // ── Mark all as read ──────────────────────────────────────────────────────
  Future<void> markAllRead() async {
    for (final n in _history) { n.read = true; }
    _hasUnread = false;
    await _saveHistory();
    notifyListeners();
  }

  // ── Add to in-app history ─────────────────────────────────────────────────
  Future<void> _addToHistory(AppNotification n) async {
    debugPrint('[NOTIF] _addToHistory() — id=${n.id} type=${n.type} title="${n.title}"');
    _history.insert(0, n);
    if (_history.length > 50) _history = _history.sublist(0, 50);
    _hasUnread = true;
    await _saveHistory();
    notifyListeners();
  }

  // ── Show system notification ──────────────────────────────────────────────
  Future<void> _show(int id, String title, String body, {String trigger = 'unknown', String screen = 'unknown'}) async {
    if (!_enabled) {
      debugPrint('[NOTIF] _show() BLOCKED — notifications disabled. trigger=$trigger title="$title"');
      return;
    }
    // Enforce minimum 3s gap between system notifications so Android doesn't suppress vibration
    final now = DateTime.now();
    if (_lastSystemNotifTime != null) {
      final msSinceLast = now.difference(_lastSystemNotifTime!).inMilliseconds;
      if (msSinceLast < 3000) {
        final waitMs = 3000 - msSinceLast;
        debugPrint('[NOTIF] _show() — cooldown: waiting ${waitMs}ms before firing (msSinceLast=$msSinceLast)');
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }
    _lastSystemNotifTime = DateTime.now();
    _log(trigger, screen, title, body, vibration: true, extra: 'systemNotifId=$id');
    final androidDetails = AndroidNotificationDetails(
      'rishta_v2', 'Rishta Notifications',
      channelDescription: 'Profile and proposal updates',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      playSound: true,
      ticker: 'Rishta update',
      styleInformation: const BigTextStyleInformation(''),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true, presentBadge: true, presentSound: true,
    );
    await _plugin.show(id, title, body,
      NotificationDetails(android: androidDetails, iOS: iosDetails));
    debugPrint('[NOTIF] _show() — system notification fired. id=$id');
  }

  // ── 1. Subscription expiry warning ───────────────────────────────────────
  Future<void> scheduleExpiryWarnings(String? expiryDateStr) async {
    debugPrint('[NOTIF] scheduleExpiryWarnings() — expiryDateStr=$expiryDateStr enabled=$_enabled');
    if (!_enabled || expiryDateStr == null) {
      debugPrint('[NOTIF] scheduleExpiryWarnings() — SKIPPED (enabled=$_enabled expiryNull=${expiryDateStr == null})');
      return;
    }
    await _plugin.cancel(_kIdExpiryWarning);

    DateTime? expiry;
    try { expiry = DateTime.parse(expiryDateStr); } catch (_) {
      debugPrint('[NOTIF] scheduleExpiryWarnings() — ERROR: could not parse date "$expiryDateStr"');
      return;
    }

    final now = DateTime.now();
    final daysLeft = expiry.difference(now).inDays;
    debugPrint('[NOTIF] scheduleExpiryWarnings() — daysLeft=$daysLeft expiry=$expiry');

    if (daysLeft <= 0) {
      debugPrint('[NOTIF] scheduleExpiryWarnings() — already expired, skipping');
      return;
    }

    if (daysLeft <= 7) {
      final title = 'Profile Expiring Soon';
      final body = daysLeft == 1
          ? 'Your profile expires tomorrow — renew now to stay visible'
          : 'Your profile expires in $daysLeft days — renew to stay visible';
      await _show(_kIdExpiryWarning, title, body,
          trigger: 'scheduleExpiryWarnings — daysLeft=$daysLeft', screen: 'subscription_screen (login)');
      await _addToHistory(AppNotification(
        id: 'expiry_$daysLeft',
        title: title, body: body,
        time: now, type: 'expiry',
      ));
    }

    final expiryNotifTime = tz.TZDateTime.from(
      expiry.subtract(const Duration(hours: 2)),
      tz.local,
    );
    if (expiryNotifTime.isAfter(tz.TZDateTime.now(tz.local))) {
      _log('scheduleExpiryWarnings — scheduled at expiry', 'system (background)',
          'Subscription Expired ⚠️', 'Your profile is inactive. Please renew your subscription to continue exploring profiles.',
          vibration: true, extra: 'scheduledAt=$expiryNotifTime');
      await _plugin.zonedSchedule(
        _kIdExpiryWarning + 1,
        'Subscription Expired ⚠️',
        'Your profile is inactive. Please renew your subscription to continue exploring profiles.',
        expiryNotifTime,
        NotificationDetails(
          android: AndroidNotificationDetails('rishta_v2', 'Rishta Notifications',
            importance: Importance.high, priority: Priority.high,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 500, 200, 500])),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('[NOTIF] scheduleExpiryWarnings() — at-expiry notification scheduled for $expiryNotifTime');
    }
  }

  // ── 2. Status change notification ────────────────────────────────────────
  Future<void> notifyStatusChange(String newStatus, {String screen = 'subscription_screen'}) async {
    debugPrint('[NOTIF] notifyStatusChange() — newStatus=$newStatus screen=$screen');
    final labels = {
      'active':   ('Profile Approved 🎉', 'Your profile is now live! Start exploring proposals and find your perfect match.'),
      'approved': ('Profile Approved 🎉', 'Your profile is now live! Start exploring proposals and find your perfect match.'),
      'paused':   ('Profile Paused ⏯️', 'Your profile is now hidden from the group.'),
      'resumed':  ('Profile Resumed 👁️', 'Your profile is now visible in the group.'),
      'expired':  ('Subscription Expired ⚠️', 'Your profile is inactive. Please renew your subscription to continue exploring profiles.'),
      'pending':  ('Profile Under Review ⏳', 'Your profile is being reviewed by our team'),
      'rejected': ('Profile Rejected ❌', 'Your profile was not approved. Contact admin for more information'),
      'deleted':  ('Profile Rejected ❌', 'Your profile was not approved. Contact admin for more information'),
    };
    final entry = labels[newStatus.toLowerCase()];
    if (entry == null) {
      debugPrint('[NOTIF] notifyStatusChange() — SKIPPED: no label for status "$newStatus"');
      return;
    }
    final (title, body) = entry;
    // Use a unique ID each time so Android treats it as a NEW notification
    // (not an update to an existing one) and always vibrates
    // Use high base (10000+) with ms remainder to guarantee unique ID
    // far away from fixed IDs (1001-1006) and avoid silent replacements
    final uniqueId = 2000 + (DateTime.now().millisecondsSinceEpoch % 1000);
    await _show(uniqueId, title, body,
        trigger: 'notifyStatusChange(status=$newStatus)', screen: screen);
    await _addToHistory(AppNotification(
      id: 'status_${newStatus}_${DateTime.now().millisecondsSinceEpoch}',
      title: title, body: body,
      time: DateTime.now(), type: 'status',
    ));
    debugPrint('[NOTIF] notifyStatusChange() — complete for status=$newStatus');
  }

  // ── 3. New proposals daily at 6pm ────────────────────────────────────────
  Future<void> trackNewProposal() async {
    if (!_enabled) {
      debugPrint('[NOTIF] trackNewProposal() — SKIPPED (disabled)');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final lastDate = prefs.getString(_kLastProposalNotif) ?? '';
    int count = prefs.getInt(_kNewProposalCount) ?? 0;

    if (lastDate != today) count = 0;
    count++;
    await prefs.setInt(_kNewProposalCount, count);
    debugPrint('[NOTIF] trackNewProposal() — count=$count today=$today lastDate=$lastDate');
    await _scheduleProposalDigest(count, today, prefs);
  }

  Future<void> _scheduleProposalDigest(int count, String today, SharedPreferences prefs) async {
    await _plugin.cancel(_kIdNewProposals);
    if (!_enabled || count < 1) return;

    final now = DateTime.now();
    var sixPm = DateTime(now.year, now.month, now.day, 18, 0, 0);
    if (now.isAfter(sixPm)) sixPm = sixPm.add(const Duration(days: 1));

    final scheduledTime = tz.TZDateTime.from(sixPm, tz.local);
    final title = 'New Proposals Added';
    final body = count == 1
        ? '1 new proposal was added today — check it out'
        : '$count new proposals were added today — see who\'s new';

    _log('trackNewProposal — scheduled digest', 'system (background at 6pm)',
        title, body, vibration: true, extra: 'count=$count scheduledFor=$scheduledTime');

    await _plugin.zonedSchedule(
      _kIdNewProposals,
      title, body,
      scheduledTime,
      NotificationDetails(
        android: AndroidNotificationDetails('rishta_v2', 'Rishta Notifications',
          importance: Importance.defaultImportance, priority: Priority.defaultPriority,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 200, 500])),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
    await prefs.setString(_kLastProposalNotif, today);
    debugPrint('[NOTIF] _scheduleProposalDigest() — scheduled for $scheduledTime (count=$count)');
  }

  // ── Show instant notification (for foreground FCM messages) ──────────────
  Future<void> showInstant(String title, String body) async {
    debugPrint('[NOTIF] showInstant() — trigger=FCM foreground message');
    if (!_enabled) {
      debugPrint('[NOTIF] showInstant() — SKIPPED (disabled)');
      return;
    }
    await _show(1004 + (DateTime.now().millisecondsSinceEpoch % 1000), title, body,
        trigger: 'FCM foreground message', screen: 'fcm_service');
    await _addToHistory(AppNotification(
      id: 'fcm_${DateTime.now().millisecondsSinceEpoch}',
      title: title, body: body,
      time: DateTime.now(), type: 'status',
    ));
    debugPrint('[NOTIF] showInstant() — complete');
  }

  // ── Pending status in-app notification ───────────────────────────────────
  Future<void> notifyPendingStatus() async {
    debugPrint('[NOTIF] notifyPendingStatus() — checking if already shown today');
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final alreadyToday = _history.any((n) =>
      n.type == 'pending_reminder' &&
      n.id.startsWith('pending_status_') &&
      n.id.contains(today));
    if (alreadyToday) {
      debugPrint('[NOTIF] notifyPendingStatus() — SKIPPED: already shown today ($today)');
      return;
    }

    const title = 'Profile Under Review ⏳';
    const body  = 'Your profile is being reviewed by our team. The group will be unlocked once your profile is approved.';
    _log('notifyPendingStatus — app open with pending status', 'group_feed_screen (initAndLoad)',
        title, body, vibration: true, extra: 'firstTimeToday=$today');
    await _addToHistory(AppNotification(
      id: 'pending_status_$today',
      title: title, body: body,
      time: DateTime.now(),
      type: 'pending_reminder',
    ));
    await _show(_kIdPendingReminder, title, body,
        trigger: 'notifyPendingStatus — app open', screen: 'group_feed_screen');
    debugPrint('[NOTIF] notifyPendingStatus() — complete (id=$_kIdPendingReminder)');
  }

  // ── Proposal submitted notification ──────────────────────────────────────
  Future<void> notifyRenewal(String expiryFormatted) async {
    const title = 'Subscription Renewed ✅';
    final body  = 'Your subscription has been renewed and is valid until $expiryFormatted.';
    _log('notifyRenewal', 'admin_trash_screen', title, body, vibration: true);
    final uniqueId = 2000 + (DateTime.now().millisecondsSinceEpoch % 1000);
    await _show(uniqueId, title, body, trigger: 'notifyRenewal', screen: 'admin_trash_screen');
    await _addToHistory(AppNotification(
      id: 'renewal_${DateTime.now().millisecondsSinceEpoch}',
      title: title, body: body,
      time: DateTime.now(), type: 'status',
    ));
  }

  Future<void> notifyProposalSubmitted() async {
    const title = 'Profile Submitted ✅';
    const body  = 'Your profile is pending admin approval. It may take up to 24 hours. You\'ll be notified once it\'s approved.';
    _log('notifyProposalSubmitted — form submitted', 'submit_proposal_screen',
        title, body, vibration: true);
    await _show(_kIdSubmission, title, body,
        trigger: 'notifyProposalSubmitted — form submit', screen: 'submit_proposal_screen');
    await _addToHistory(AppNotification(
      id: 'submission_${DateTime.now().millisecondsSinceEpoch}',
      title: title, body: body,
      time: DateTime.now(), type: 'submission',
    ));
    debugPrint('[NOTIF] notifyProposalSubmitted() — complete (id=$_kIdSubmission)');
  }

  // ── Clear unread badge ────────────────────────────────────────────────────
  Future<void> clearUnread() async {
    debugPrint('[NOTIF] clearUnread() — clearing bell badge for user=$_currentUserKey');
    _hasUnread = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_unreadKey(_currentUserKey), false);
    notifyListeners();
  }
}
