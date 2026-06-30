// ── fcm_service.dart ──────────────────────────────────────────────────────────
// Handles Firebase Cloud Messaging push notifications.

import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_service.dart';
import 'notification_service.dart';

// Key used to persist the admin's FCM token locally (set when admin logs in).
const _kAdminFcmToken = 'admin_fcm_token';

class FCMService {
  static final FCMService instance = FCMService._();
  FCMService._();

  final _fcm = FirebaseMessaging.instance;

  Future<void> init() async {
    try {
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

      // Handle foreground messages — show local notification
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('FCM foreground message: ${message.notification?.title}');
        final title = message.notification?.title;
        final body = message.notification?.body;
        if (title != null && body != null) {
          NotificationService.instance.showInstant(title, body);
        }
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
  /// so other devices (if admin ever switches) can still receive the alert.
  Future<void> saveAdminToken() async {
    try {
      final token = await _fcm.getToken();
      if (token == null) return;

      // Store locally so we can send even without a network round-trip
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAdminFcmToken, token);

      // Also persist in app_settings table so it survives app reinstalls
      await SupabaseService.instance.client
          .from('app_settings')
          .upsert({'key': 'admin_fcm_token', 'value': token});

      debugPrint('Admin FCM token saved: $token');
    } catch (e) {
      debugPrint('FCM saveAdminToken error: $e');
    }
  }

  // ── Send "Order Received" push to admin ───────────────────────────────────

  /// Sends a push notification to the admin's device when a payment completes.
  /// [cnic]   — buyer's CNIC (shown in notification body)
  /// [plan]   — plan name e.g. "Standard" or "Featured"
  /// [amount] — amount in PKR e.g. "1,000"
  ///
  /// Requires the FCM Server Key to be stored in app_settings under the key
  /// 'fcm_server_key'. This is the legacy HTTP API key from your Firebase
  /// project console → Project settings → Cloud Messaging → Server key.
  Future<void> sendOrderReceivedToAdmin({
    required String applicantName,
    required String city,
  }) async {
    try {
      final settings = SupabaseService.instance.cachedSettings;
      String? adminToken = settings['admin_fcm_token'];

      if (adminToken == null || adminToken.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        adminToken = prefs.getString(_kAdminFcmToken);
      }

      if (adminToken == null || adminToken.isEmpty) {
        debugPrint('sendOrderReceivedToAdmin: no admin FCM token found — skipping');
        return;
      }

      final response = await http.post(
        Uri.parse('https://olzfarkfxhwcwabgribo.supabase.co/functions/v1/notify-status-change'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'admin_new_order',
          'fcm_token': adminToken,
          'applicant_name': applicantName,
          'city': city,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('Admin order notification sent ✓');
      } else {
        debugPrint('Admin order notification failed: \${response.statusCode} \${response.body}');
      }
    } catch (e) {
      debugPrint('sendOrderReceivedToAdmin error: \$e');
    }
  }

  // ── Send push notification to a specific user ─────────────────────────────

  /// Calls the notify-status-change edge function to send a push notification
  /// to the user identified by [proposalId] using FCM v1 API.
  Future<void> sendToUser({
    required String proposalId,
    required String messageKey,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://olzfarkfxhwcwabgribo.supabase.co/functions/v1/notify-status-change'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'proposalId': proposalId, 'messageKey': messageKey}),
      );
      if (response.statusCode == 200) {
        debugPrint('sendToUser [$messageKey] sent ✓');
      } else {
        debugPrint('sendToUser [$messageKey] failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('sendToUser error: $e');
    }
  }
}
