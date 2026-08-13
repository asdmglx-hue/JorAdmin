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

      // Foreground messages — currently just logged. Re-implement display
      // logic here once the new notification system is built.
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('FCM foreground message received (no handler wired up yet): '
            '${message.messageId}');
      });
    } catch (e) {
      debugPrint('FCM init error: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
      // Sync to DB — use activatedCnic first, fall back to user_cnic from SharedPreferences
      final cnic = SupabaseService.instance.activatedCnic
          ?? prefs.getString('user_cnic');
      if (cnic != null && cnic.isNotEmpty) {
        await SupabaseService.instance.client
            .from('proposals')
            .update({'fcm_token': token})
            .eq('cnic', cnic.trim());
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
