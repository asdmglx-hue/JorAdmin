import 'package:flutter/foundation.dart';
import '../models/admin_models.dart';
import 'supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AdminSupabaseExtension — admin-only Supabase queries
//
//  These are the ONLY SupabaseService methods that depend on admin_models.dart
//  types (AdminUser, ActivationCode, SubscriptionTier). They're implemented as
//  a Dart `extension` on SupabaseService so the user app's import of
//  shared/services/supabase_service.dart never pulls in admin_models.dart.
//
//  Behavior is byte-for-byte identical to the original methods that used to
//  live directly on SupabaseService — only `_client` -> `client` (the
//  existing public getter) and `notifyListeners()` -> `notify()` (a public
//  passthrough added to SupabaseService) were changed, since extensions
//  cannot access another file's private members.
//
//  Usage: same call sites as before — e.g. SupabaseService.instance.fetchAdminUsers()
//  — as long as this file is imported wherever those methods are called
//  (currently only admin/services/admin_service.dart).
// ─────────────────────────────────────────────────────────────────────────────

extension AdminSupabaseExtension on SupabaseService {
  Future<List<AdminUser>> fetchAdminUsers() async {
    try {
      final List<AdminUser> allUsers = [];
      const int pageSize = 1000;
      int offset = 0;

      debugPrint('[fetchAdminUsers] Starting pagination fetch...');

      while (true) {
        // Fetch in batches of 1000 (Supabase default limit)
        final res = await client
            .from('proposals')
            .select('''
              *,
              featured_credits_purchased,
              featured_credits_used,
              subscriptions(*),
              featured_boosts(*),
              proposal_photos(*)
            ''')
            .order('updated_at', ascending: false)
            .range(offset, offset + pageSize - 1);

        debugPrint('[fetchAdminUsers] Batch at offset=$offset returned ${res.length} records');

        if (res.isEmpty) {
          debugPrint('[fetchAdminUsers] No more records, stopping pagination');
          break;
        }

        // Convert and add to list
        final batch = (res as List).map((row) => AdminUser.fromJson(row)).toList();
        allUsers.addAll(batch);

        // If we got less than pageSize, this was the last batch
        if (res.length < pageSize) {
          debugPrint('[fetchAdminUsers] Last batch (${res.length} < $pageSize), stopping');
          break;
        }

        offset += pageSize;
      }

      debugPrint('[fetchAdminUsers] ✅ Total users fetched: ${allUsers.length}');
      return allUsers;
    } catch (e) {
      debugPrint('❌ fetchAdminUsers error: $e');
      debugPrint('❌ Stack: ${StackTrace.current}');
      return [];
    }
  }

  Future<void> updateUser(AdminUser user) async {
    await client
        .from('proposals')
        .update(user.toUpdateJson())
        .eq('id', user.id);
    notify();
  }

  Future<List<ActivationCode>> fetchActivationCodes() async {
    final res = await client
        .from('activation_codes')
        .select()
        .order('created_at', ascending: false);
    return (res as List).map((row) => ActivationCode.fromJson(row)).toList();
  }

  Future<String> generateCode(SubscriptionTier tier, double price) async {
    // Generate code locally then insert
    final prefix = tier == SubscriptionTier.featured ? 'FEAT' : 'BASC';
    final chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = List.generate(
        6, (_) => chars[(DateTime.now().microsecondsSinceEpoch * 31 % chars.length).abs()]);
    final code = '$prefix-${rand.join()}';

    await client.from('activation_codes').insert({
      'code': code,
      'tier': tier.name,
      'price': price,
    });
    notify();
    return code;
  }
}
