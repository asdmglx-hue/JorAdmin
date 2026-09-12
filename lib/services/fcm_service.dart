// ── fcm_service.dart ──────────────────────────────────────────────────────────
// Firebase Cloud Messaging DEVICE REGISTRATION ONLY.
//
// Push-sending logic has been intentionally removed (2026-07) and will be
// freshly re-implemented. This file still handles:
//   - requesting notification permission
//   - obtaining/refreshing the FCM device token
//   - persisting that token to the DB (proposals.fcm_token / app_settings.admin_fcm_token)
// so that whatever we build next has a working token pipeline to send to.
//
// Nothing in this file sends a push notification.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'supabase_service.dart';

// Key used to persist the admin's FCM token locally (set when admin logs in).
const _kAdminFcmToken = 'admin_fcm_token';

// ── Background message handler — required top-level function for FCM ────────
// Currently a no-op placeholder: we don't send push yet, so this just logs.
// Re-implement actual handling here when push is rebuilt.
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('🔔 FCM background message received (no handler wired up yet): '
      '${message.messageId}');
}

class FCMService {
  static final FCMService instance = FCMService._();
  FCMService._();

  final _fcm = FirebaseMessaging.instance;

  Future<void> init() async {
    if (kIsWeb) return; // FCM not needed on web
    try {
      // Register background handler (required even as a placeholder).
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Request permission
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('FCM permission: ${settings.authorizationStatus}');

      // Get FCM token
      final token = await _fcm.getToken();
      debugPrint('FCM token: $token');
      if (token != null) await _saveToken(token);

      // Listen for token refresh
      _fcm.onTokenRefresh.listen(_saveToken);

      // Foreground messages — show tray banner via the already-initialised
      // NotificationService plugin. Background/terminated ones are shown
      // automatically by the OS so no code needed for those.
      FirebaseMessaging.onMessage.listen((message) async {
        debugPrint('FCM foreground message received: ${message.messageId}');
        final title = message.notification?.title ?? message.data['title'] as String? ?? '';
        final body  = message.notification?.body  ?? message.data['body']  as String? ?? '';
        if (title.isEmpty && body.isEmpty) return;
        await NotificationService.instance.showTrayOnly(title, body);
      });
    } catch (e) {
      debugPrint('FCM init error: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
      // Sync to DB — use activatedPhone (auth_phone) to find the proposal
      final phone = SupabaseService.instance.activatedPhone
          ?? prefs.getString('activated_phone');
      if (phone != null && phone.isNotEmpty) {
        await SupabaseService.instance.client
            .from('proposals')
            .update({'fcm_token': token})
            .eq('auth_phone', phone.trim());
        debugPrint('FCM token synced to DB');
      }
    } catch (e) {
      debugPrint('FCM save token error: $e');
    }
  }

  Future<void> syncTokenToDb() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('fcm_token') ?? await _fcm.getToken();
      if (token == null) return;
      await _saveToken(token);
    } catch (e) {
      debugPrint('FCM syncTokenToDb error: $e');
    }
  }

  // ── Admin token management ────────────────────────────────────────────────

  /// Call this right after a successful admin login to persist the current
  /// device's FCM token as the admin token and also store it in app_settings
  /// so other devices (if admin ever switches) can still be targeted later.
  Future<void> saveAdminToken() async {
    try {
      final token = await _fcm.getToken();
      if (token == null) return;

      // Store locally so we have it without a network round-trip.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAdminFcmToken, token);

      // Also persist in app_settings table so it survives app reinstalls.
      await SupabaseService.instance.client
          .from('app_settings')
          .upsert({'key': 'admin_fcm_token', 'value': token});

      debugPrint('Admin FCM token saved: $token');
    } catch (e) {
      debugPrint('FCM saveAdminToken error: $e');
    }
  }
}
