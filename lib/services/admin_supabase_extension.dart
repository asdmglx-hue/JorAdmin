import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

// Explicit column list — matches exactly what AdminUser.fromJson reads.
// Deliberately NOT select('*'): the three largest fields on this table
// (profile_photo_base64, cnic_front_base64, cnic_back_base64) are full
// images encoded as text, and nothing in the app reads them anymore —
// every photo now goes through Cloudflare R2 and is referenced by URL
// instead. Shared as one constant so the bulk list fetch and the
// single-user realtime-sync fetch can never drift out of sync with
// each other or with what AdminUser.fromJson actually expects.
const String _adminUserCols = 'id,proposal_number,name,age,gender,city,country,caste,sect,'
    'languages,education,institute,degree_title,degree_certificate_url,'
    'institute_2,degree_title_2,degree_certificate_2_url,'
    'institute_3,degree_title_3,degree_certificate_3_url,profession,employment_type,salary_start,'
    'salary_end,height_inches,weight_kg,complexion,marital_status,'
    'open_to_polygamy,marriage_number,boys,girls,practice_level,hijab,beard,'
    'family_type,father_alive,mother_alive,father_occupation,mother_occupation,'
    'sisters,brothers,home_type,house_size,location,disability_details,'
    'has_kids,has_siblings,has_car,car_name,has_other_property,other_property,'
    'has_generator,has_solar,has_servant,looking_for,about,contact_phone,'
    'contact_phone_2,phone_verified,email_verified,cnic_verified,cnic,'
    'password,smokes,drinks,monthly_income,has_disability,physically_active,'
    'posted_at,updated_at,status,subscription_tier,subscription_status,'
    'subscription_start,subscription_expiry,amount_paid,'
    'featured_credits_purchased,featured_credits_used,deleted_from,'
    'deletion_reason,admin_notes,discarded,suggested_info,profile_photo_url,'
    'cnic_front_url,cnic_back_url,applied_coupon_code';

extension AdminSupabaseExtension on SupabaseService {
  Future<List<AdminUser>> fetchAdminUsers() async {
    final List<Map<String, dynamic>> allProposals = [];
    const int pageSize = 1000;
    int offset = 0;

    debugPrint('[fetchAdminUsers] Starting pagination fetch...');

    // NOTE: no try/catch around the loop itself — if a page fails partway
    // through, we want that error to propagate to the caller (AdminService
    // .loadData(), which deliberately keeps the previously loaded _users on
    // error) rather than swallow it here and return an empty list, which
    // would wipe out every user the admin currently sees.
    //
    // This used to select proposals with subscriptions/featured_boosts/
    // proposal_photos embedded directly in one nested query. That silently
    // excluded any proposal with zero rows in ALL THREE related tables —
    // a brand new registration, for instance, has no subscription yet, no
    // boost, and often no separately-stored photo row, so it could vanish
    // from this list entirely despite being a completely valid, visible-
    // everywhere-else profile. Fetching the base proposals with a plain,
    // un-joined select (identical in shape to what the public site already
    // uses successfully) and merging the related tables in afterward
    // guarantees a proposal can never be dropped just for lacking optional
    // related data.
    // Explicit column list — matches exactly what AdminUser.fromJson reads.
    // Deliberately NOT select('*'): the three largest fields on this table
    // (profile_photo_base64, cnic_front_base64, cnic_back_base64) are
    // full images encoded as text, and as of this change nothing in the
    // app reads them anymore — every photo now goes through Cloudflare R2
    // and is referenced by URL instead. Downloading them here, for every
    // single user, on every single admin screen load, was pure waste.
    // (Column list itself now lives in the shared _adminUserCols constant
    // above, so this fetch and the single-user realtime sync below always
    // stay identical.)

    while (true) {
      final res = await client
          .from('proposals')
          .select(_adminUserCols)
          .order('updated_at', ascending: false)
          .range(offset, offset + pageSize - 1);

      debugPrint('[fetchAdminUsers] Batch at offset=$offset returned ${res.length} records');

      if (res.isEmpty) {
        debugPrint('[fetchAdminUsers] No more records, stopping pagination');
        break;
      }

      allProposals.addAll((res as List).cast<Map<String, dynamic>>());
      offset += res.length;
    }

    final ids = allProposals.map((p) => p['id'] as String).toList();

    // Related tables are fetched separately, in bulk, using an "in" filter
    // rather than per-row — one query each instead of one per user.
    final subsByUser = <String, List<Map<String, dynamic>>>{};
    final boostsByUser = <String, List<Map<String, dynamic>>>{};
    final photosByProposal = <String, List<Map<String, dynamic>>>{};

    if (ids.isNotEmpty) {
      // Chunked rather than one call with all ~1300+ ids at once — a
      // single inFilter with every id would produce an extremely long
      // URL, which risks silently failing (or being truncated) as the
      // proposals table keeps growing. 200 per batch stays comfortably
      // within normal URL length limits regardless of total row count.
      const chunkSize = 200;
      for (var i = 0; i < ids.length; i += chunkSize) {
        final chunk = ids.sublist(i, i + chunkSize > ids.length ? ids.length : i + chunkSize);

        final subs = await client.from('subscriptions').select('*').inFilter('user_id', chunk);
        for (final row in (subs as List).cast<Map<String, dynamic>>()) {
          subsByUser.putIfAbsent(row['user_id'] as String, () => []).add(row);
        }

        final boosts = await client.from('featured_boosts').select('*').inFilter('user_id', chunk);
        for (final row in (boosts as List).cast<Map<String, dynamic>>()) {
          boostsByUser.putIfAbsent(row['user_id'] as String, () => []).add(row);
        }

        final photos = await client.from('proposal_photos').select('*').inFilter('proposal_id', chunk);
        for (final row in (photos as List).cast<Map<String, dynamic>>()) {
          photosByProposal.putIfAbsent(row['proposal_id'] as String, () => []).add(row);
        }
      }
    }

    final allUsers = allProposals.map((row) {
      final id = row['id'] as String;
      final merged = {
        ...row,
        'subscriptions': subsByUser[id] ?? [],
        'featured_boosts': boostsByUser[id] ?? [],
        'proposal_photos': photosByProposal[id] ?? [],
      };
      return AdminUser.fromJson(merged);
    }).toList();

    debugPrint('[fetchAdminUsers] ✅ Total users fetched: ${allUsers.length}');
    return allUsers;
  }

  // Fetches exactly one user's full data — same columns, same related-table
  // joins as fetchAdminUsers() above, just filtered to a single id instead
  // of paginating through everyone. Used to refresh one person after an
  // action (approve/etc.) or after a realtime change notification, so
  // neither path ever needs to re-download the entire table just to learn
  // about one row.
  Future<AdminUser?> fetchSingleAdminUser(String id) async {
    final row = await client
        .from('proposals')
        .select(_adminUserCols)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;

    final subs = await client.from('subscriptions').select('*').eq('user_id', id);
    final boosts = await client.from('featured_boosts').select('*').eq('user_id', id);
    final photos = await client.from('proposal_photos').select('*').eq('proposal_id', id);

    return AdminUser.fromJson({
      ...row,
      'subscriptions': subs,
      'featured_boosts': boosts,
      'proposal_photos': photos,
    });
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

  // ── Coupon codes (percentage discounts) ─────────────────────────────────
  Future<List<CouponCode>> fetchCouponCodes() async {
    final res = await client
        .from('coupon_codes')
        .select()
        .order('created_at', ascending: false);
    return (res as List).map((row) => CouponCode.fromJson(row)).toList();
  }

  Future<void> createCouponCode(
    String code, {
    required String type, // 'percentage' or 'free_days'
    int? discountPercent,
    int? freeDays,
    DateTime? expiresAt,
  }) async {
    await client.from('coupon_codes').insert({
      'code': code.trim().toUpperCase(),
      'coupon_type': type,
      if (type == 'percentage') 'discount_percent': discountPercent,
      if (type == 'free_days') 'free_days': freeDays,
      if (expiresAt != null) 'expires_at': expiresAt.toUtc().toIso8601String(),
    });
    notify();
  }

  Future<void> setCouponActive(String id, bool active) async {
    await client.from('coupon_codes').update({'active': active}).eq('id', id);
    notify();
  }

  Future<void> deleteCouponCode(String id) async {
    await client.from('coupon_codes').delete().eq('id', id);
    notify();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ADMIN — Admin accounts (Dashboard → Settings → Create Admin)
  //
  //  CNIC + password logins that unlock full profile viewing when used on
  //  the regular login screen. See AdminAccount in admin_models.dart for
  //  the distinction from `admin_users` (Supabase-Auth-linked panel access).
  // ══════════════════════════════════════════════════════════════════════════
  Future<List<AdminAccount>> fetchAdminAccounts() async {
    final res = await client
        .from('admin_accounts')
        .select()
        .order('created_at', ascending: false);
    return (res as List)
        .map((row) => AdminAccount.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Returns null on success, or a user-facing error message on failure.
  Future<String?> createAdminAccount({
    required String name,
    required String cnic,
    required String password,
  }) async {
    try {
      await client.from('admin_accounts').insert({
        'name': name,
        'cnic': cnic,
        'password': password,
      });
      notify();
      return null;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return 'An admin with this CNIC already exists.';
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Returns null on success, or a user-facing error message on failure.
  Future<String?> updateAdminAccount({
    required String id,
    required String name,
    required String cnic,
    required String password,
  }) async {
    try {
      await client.from('admin_accounts').update({
        'name': name,
        'cnic': cnic,
        'password': password,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
      notify();
      return null;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return 'An admin with this CNIC already exists.';
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> deleteAdminAccount(String id) async {
    await client.from('admin_accounts').delete().eq('id', id);
    notify();
  }
}
