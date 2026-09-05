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
    'marriage_number,boys,girls,practice_level,hijab,beard,'
    'family_type,father_alive,mother_alive,father_occupation,mother_occupation,'
    'sisters,brothers,home_type,house_size,location,disability_details,'
    'has_kids,has_siblings,has_car,car_name,has_other_property,other_property,'
    'has_generator,has_solar,has_servant,looking_for,about,contact_phone,'
    'contact_phone_2,contact_person,contact_person_2,phone_verified,email_verified,cnic_verified,cnic,'
    'password,smokes,drinks,monthly_income,has_disability,physically_active,'
    'posted_at,updated_at,status,subscription_tier,subscription_status,'
    'subscription_start,subscription_expiry,amount_paid,'
    'featured_credits_purchased,featured_credits_used,deleted_from,'
    'deletion_reason,admin_notes,discarded,suggested_info,profile_photo_url,'
    'cnic_front_url,cnic_back_url,guardian_cnic_front_url,guardian_cnic_back_url,'
    'education_document_url,applied_coupon_code,profession_category,registration_allowed,ai_contacted,doc_verification,is_doc_verified,'
    'submission_source,last_seen_at,last_seen_source,'
    'payment_proof_url,payment_proof_status,payment_proof_plan,payment_proof_type,'
    'is_order_archived,archived_at';

extension AdminSupabaseExtension on SupabaseService {
  Future<List<AdminUser>> fetchAdminUsers() async {
    debugPrint('[fetchAdminUsers] Starting summary view fetch...');

    // Uses admin_proposals_summary view — only the ~22 columns needed to
    // render the list card, instead of all 109 proposal columns.
    // featured_boosts are joined server-side in the view itself.
    // Result: one single network call, ~5x smaller payload, no pagination
    // loop, no chunk fetches for related tables.
    final res = await client
        .from('admin_proposals_summary')
        .select()
        .order('updated_at', ascending: false);

    final allUsers = (res as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final boostsRaw = map['featured_boosts'];
      map['featured_boosts'] = boostsRaw is List
          ? boostsRaw
          : (boostsRaw != null ? List<dynamic>.from(boostsRaw as Iterable) : []);
      map['subscriptions'] = [];
      map['proposal_photos'] = [];
      return AdminUser.fromJson(map);
    }).toList();

    debugPrint('[fetchAdminUsers] ✅ Total users fetched: ${allUsers.length}');
    return allUsers;
  }

  // Incremental fetch — only rows updated since [since].
  // Returns a small list (typically 0–10 rows) that the caller merges into
  // the existing local list. Same view, same fromJson — just filtered.
  Future<List<AdminUser>> fetchAdminUsersSince(DateTime since) async {
    final sinceIso = since.toUtc().toIso8601String();
    debugPrint('[fetchAdminUsers] Incremental fetch since $sinceIso');

    final res = await client
        .from('admin_proposals_summary')
        .select()
        .gt('updated_at', sinceIso)
        .order('updated_at', ascending: false);

    final changed = (res as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final boostsRaw = map['featured_boosts'];
      map['featured_boosts'] = boostsRaw is List
          ? boostsRaw
          : (boostsRaw != null ? List<dynamic>.from(boostsRaw as Iterable) : []);
      map['subscriptions'] = [];
      map['proposal_photos'] = [];
      return AdminUser.fromJson(map);
    }).toList();

    debugPrint('[fetchAdminUsers] Incremental: ${changed.length} changed rows');
    return changed;
  }

  // Fetches exactly one user's full data — same columns, same related-table
  // joins as fetchAdminUsers() above, just filtered to a single id instead
  // of paginating through everyone. Used to refresh one person after an
  // action (approve/etc.) or after a realtime change notification, so
  // neither path ever needs to re-download the entire table just to learn
  // about one row.
  /// Removes a photo row from proposal_photos so the removal is permanent.
  Future<void> deleteProposalPhoto(String proposalId, String photoType) async {
    await client.from('proposal_photos')
      .delete()
      .eq('proposal_id', proposalId)
      .eq('photo_type', photoType);
  }

  Future<AdminUser?> fetchSingleAdminUser(String id) async {
    final row = await client
        .from('proposals')
        .select(_adminUserCols)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;

    final subs   = await client.from('subscriptions').select('*').eq('user_id', id);
    final boosts = await client.from('featured_boosts').select('*').eq('user_id', id);
    final photos = await client.from('proposal_photos').select('*').eq('proposal_id', id);

    // Also fetch the latest pending verification request — docs submitted via
    // "Verify Now" go into cnic_verification_requests, not into proposals
    // directly. Merge them so the edit/view screen shows them immediately.
    final verif = await client
        .from('cnic_verification_requests')
        .select('cnic_front_url, cnic_back_url, guardian_cnic_front_url, guardian_cnic_back_url, education_document_url')
        .eq('proposal_id', id)
        .eq('status', 'pending')
        .order('submitted_at', ascending: false)
        .limit(1)
        .maybeSingle();

    final merged = Map<String, dynamic>.from(row);
    if (verif != null) {
      // Only fill in fields that are null on the proposals row
      merged['cnic_front_url']          ??= verif['cnic_front_url'];
      merged['cnic_back_url']           ??= verif['cnic_back_url'];
      merged['guardian_cnic_front_url'] ??= verif['guardian_cnic_front_url'];
      merged['guardian_cnic_back_url']  ??= verif['guardian_cnic_back_url'];
      merged['education_document_url']  ??= verif['education_document_url'];
    }

    return AdminUser.fromJson({
      ...merged,
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
    required String type, // 'percentage', 'free_days', or 'free_trial'
    int? discountPercent,
    int? freeDays,
    int? trialDays,
    DateTime? expiresAt,
  }) async {
    await client.from('coupon_codes').insert({
      'code': code.trim().toUpperCase(),
      'coupon_type': type,
      if (type == 'percentage') 'discount_percent': discountPercent,
      if (type == 'free_days') 'free_days': freeDays,
      if (type == 'free_trial') 'trial_days': trialDays,
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
    bool isSuper = false,
    Map<String, String> permissions = const {},
  }) async {
    try {
      await client.from('admin_accounts').insert({
        'name': name,
        // CNIC is always stored digits-only so login matching is consistent.
        'cnic': cnic.replaceAll('-', ''),
        'password': password,
        'is_super': isSuper,
        'permissions': isSuper ? <String, String>{} : permissions,
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
    bool isSuper = false,
    Map<String, String> permissions = const {},
  }) async {
    try {
      await client.from('admin_accounts').update({
        'name': name,
        'cnic': cnic.replaceAll('-', ''),
        'password': password,
        'is_super': isSuper,
        'permissions': isSuper ? <String, String>{} : permissions,
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
