import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Subscribes to INSERT/UPDATE/DELETE on [tables] and calls [onChange]
/// shortly after any of them fire, so a screen's list refreshes on its own
/// instead of requiring a manual pull/refresh-button tap.
///
/// Multiple rapid changes (e.g. "Delete All") are debounced into a single
/// reload rather than one reload per row.
///
/// Usage (in a screen's initState/dispose):
///   _syncChannel = subscribeAutoRefresh(
///     client: SupabaseService.instance.client,
///     channelName: 'admin-sync-ads',
///     tables: const ['ads'],
///     onChange: () { if (mounted) _load(); },
///   );
///   ...
///   @override
///   void dispose() {
///     _syncChannel?.unsubscribe();
///     super.dispose();
///   }
class AutoRefreshSync {
  final RealtimeChannel channel;
  AutoRefreshSync._(this.channel);

  void unsubscribe() => channel.unsubscribe();
}

AutoRefreshSync subscribeAutoRefresh({
  required SupabaseClient client,
  required String channelName,
  required List<String> tables,
  required void Function() onChange,
  Duration debounce = const Duration(milliseconds: 400),
}) {
  Timer? debounceTimer;
  void scheduled(PostgresChangePayload _) {
    debounceTimer?.cancel();
    debounceTimer = Timer(debounce, onChange);
  }

  var channel = client.channel(channelName);
  for (final table in tables) {
    channel = channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: scheduled,
    );
  }
  channel.subscribe();
  return AutoRefreshSync._(channel);
}
