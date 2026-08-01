// notification_bell_widget.dart - ADMIN APP
// Just the unread-count helper for the bell icon's badge now — tapping the
// bell navigates to AdminNotificationScreen (a full screen, matching the
// user app's notification screen style) instead of a bottom sheet.

import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationBellWidget {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Number of new-order notifications the admin hasn't opened yet. Used to
  /// show a badge on the bell icon itself.
  static Future<int> unreadCount() async {
    try {
      final res = await _client
          .from('notification_log')
          .select('id, read_at')
          .eq('type', 'new_order');
      return (res as List).where((e) => e['read_at'] == null).length;
    } catch (_) {
      return 0;
    }
  }
}
