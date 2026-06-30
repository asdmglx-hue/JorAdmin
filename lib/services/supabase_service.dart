import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/rishta_proposal.dart';
import '../utils/theme.dart';

// ── Cloudflare R2 credentials ─────────────────────────────────────────────────
const _r2AccessKeyId     = '31bb881b23b075a4ab165b09738539ed';
const _r2SecretAccessKey = '3e426b5e9d8d5f84f858fccc47fa78bd9760baa72e773c42cfcbefab1fb45a91';
const _r2Endpoint        = 'https://27fdb7883570e5f6e97e985e183ea7b0.r2.cloudflarestorage.com';
const _r2Bucket          = 'proposal-photos';
const _r2PublicUrl       = 'https://pub-45b25e06fb4b4f448d2ee349c6f55922.r2.dev';

// ─────────────────────────────────────────────────────────────────────────────
//  SupabaseService — single source of truth for all DB operations
//  Replaces the in-memory AdminService mock entirely.
//
//  Usage (singleton):
//    final db = SupabaseService.instance;
// ─────────────────────────────────────────────────────────────────────────────

class SupabaseService extends ChangeNotifier {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  final _client = Supabase.instance.client;
  Map<String, String> _cachedSettings = {};
  Set<String> overLimitCities = {};
  Map<String, String> get cachedSettings => _cachedSettings;

  // ── Convenience getters ───────────────────────────────────────────────────
  SupabaseClient get client => _client;
  bool get isAdminLoggedIn => _client.auth.currentUser != null;

  /// Public passthrough to notifyListeners() — lets extension files (e.g. the
  /// admin-only Supabase extension) trigger rebuilds without depending on the
  /// protected notifyListeners() API directly.
  void notify() => notifyListeners();

  // ══════════════════════════════════════════════════════════════════════════
  //  AUTH — Admin login / logout
  // ══════════════════════════════════════════════════════════════════════════

  /// Tracks a unique device visit — call once on app open.
  Future<void> trackAppVisit(String deviceId) async {
    try {
      await _client.from('app_visitors').upsert(
        {'device_id': deviceId, 'last_seen_at': DateTime.now().toIso8601String()},
        onConflict: 'device_id',
      );
    } catch (_) {}
  }

  /// Returns {total, male, female} counts of active proposals
  /// FIXED: Uses COUNT queries instead of fetching all rows (bypasses 1000-row limit)
  Future<Map<String, int>> fetchProposalCounts() async {
    try {
      // Use COUNT queries instead of fetching all rows
      // This is much faster and doesn't hit Supabase's 1000-row pagination limit
      
      final totalRes = await _client
          .from('proposals')
          .select('id')
          .eq('status', 'active')
          .count(CountOption.exact);
      
      final maleRes = await _client
          .from('proposals')
          .select('id')
          .eq('status', 'active')
          .eq('gender', 'Male')
          .count(CountOption.exact);
      
      final femaleRes = await _client
          .from('proposals')
          .select('id')
          .eq('status', 'active')
          .eq('gender', 'Female')
          .count(CountOption.exact);
      
      debugPrint('[fetchProposalCounts] ✅ Total: ${totalRes.count}, Male: ${maleRes.count}, Female: ${femaleRes.count}');
      
      return {
        'total': totalRes.count,
        'male': maleRes.count,
        'female': femaleRes.count
      };
    } catch (e) {
      debugPrint('❌ fetchProposalCounts error: $e');
      return {'total': 0, 'male': 0, 'female': 0};
    }
  }

  /// Returns total unique app visitors.
  Future<int> fetchTotalVisitors() async {
    try {
      final res = await _client
          .from('app_visitors')
          .select('id')
          .count(CountOption.exact);
      return res.count;
    } catch (_) {
      return 0;
    }
  }

  /// Admin signs in with email + password (replaces hardcoded PIN check).
  Future<bool> adminLogin(String email, String password) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final loggedIn = res.user != null;
      if (loggedIn) notifyListeners();
      return loggedIn;
    } on AuthException {
      return false;
    }
  }

  Future<void> adminLogout() async {
    await _client.auth.signOut();
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  FEED — Public proposals (group feed)
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetches active proposals for the public feed.
  /// Uses the `proposals_feed` view which auto-masks phone for non-subscribers.
  Future<List<RishtaProposal>> fetchFeedProposals({
    FilterState? filters,
    bool isPaidUser = false,
    int page = 0,
    int pageSize = 15,
  }) async {
    final from = page * pageSize;
    final to = from + pageSize - 1;
    List<dynamic> res;

    // Build DB-level filter query to ensure accurate pagination
    dynamic buildQuery(dynamic q) {
      if (filters != null) {
        if (filters.gender != null) q = q.eq('gender', filters.gender!);
        if (filters.cities.isNotEmpty) q = q.inFilter('city', filters.cities);
        if (filters.castes.isNotEmpty) q = q.inFilter('caste', filters.castes);
        if (filters.sects.isNotEmpty) q = q.inFilter('sect', filters.sects);
        if (filters.maritalStatuses.isNotEmpty) q = q.inFilter('marital_status', filters.maritalStatuses);
        if (filters.educations.isNotEmpty) q = q.inFilter('education', filters.educations);
        if (filters.professions.isNotEmpty) {
          // Expand category names to individual profession values
          final expanded = filters.professions
              .expand((cat) => kProfessionGroups[cat] ?? [cat])
              .toList();
          q = q.inFilter('profession', expanded);
        }
        // Only apply age/height filters if changed from defaults
        if (filters.ageRange.start != 18 || filters.ageRange.end != 100) {
          q = q.gte('age', filters.ageRange.start.toInt()).lte('age', filters.ageRange.end.toInt());
        }
        if (filters.heightRange.start != 48 || filters.heightRange.end != 96) {
          q = q.gte('height_inches', filters.heightRange.start).lte('height_inches', filters.heightRange.end);
        }
        if (filters.locationFilter == 'local') q = q.or('country.is.null,country.ilike.%pakistan%');
        if (filters.locationFilter == 'overseas') q = q.not('country', 'ilike', '%pakistan%').not('country', 'is', null);
        if (filters.cnicVerified == true) q = q.eq('cnic_verified', true);
      }
      return q;
    }

    if (isPaidUser) {
      // Paid user — fetch directly from proposals table to get real phone/photos
      debugPrint('[FEED] isPaidUser=true — querying proposals table with status=active');
      var q = _client
          .from('proposals')
          .select()
          .eq('status', 'active');
      q = buildQuery(q);
      res = await q
          .order('is_boosted', ascending: false)
          .order('approved_at', ascending: false)
          .range(from, to);
      debugPrint('[FEED] proposals table returned ${(res as List).length} rows');
    } else {
      // Non-paid — use masked view
      debugPrint('[FEED] isPaidUser=false — querying proposals_feed view');
      var q = _client
          .from('proposals_feed')
          .select();
      q = buildQuery(q);
      res = await q
          .order('is_boosted', ascending: false)
          .order('approved_at', ascending: false)
          .range(from, to);
      debugPrint('[FEED] proposals_feed view returned ${(res as List).length} rows');
    }

    var list = (res as List).map((row) => RishtaProposal.fromJson(row)).toList();

    // Get featured proposal IDs for today filtered by city (max 5 per city)
    try {
      final cityFilter = filters?.cities.isNotEmpty == true ? filters!.cities.first : null;
      final featuredRes = await _client.rpc('get_featured_today',
          params: cityFilter != null ? {'p_city': cityFilter} : <String, dynamic>{});
      final rows = featuredRes as List;
      final featuredIds = rows.map((r) => r['proposal_id'].toString()).toSet();
      // Check if any city is over limit
      overLimitCities = rows.where((r) => r['is_over_limit'] == true)
          .map((r) => r['city'].toString()).toSet();
      if (featuredIds.isNotEmpty) {
        final boosted = list.where((p) => featuredIds.contains(p.id))
            .map((p) => _withBoosted(p, true)).toList();
        final rest = list.where((p) => !featuredIds.contains(p.id)).toList();
        list = [...boosted, ...rest];
      }
    } catch (_) {} // silently fail

    // Filters already applied at DB level above — no client-side re-filtering needed
    return list;
  }

  /// Returns a copy of [p] with isBoosted overridden
  RishtaProposal _withBoosted(RishtaProposal p, bool boosted) {
    final json = {
      'id': p.id, 'name': p.name, 'age': p.age, 'gender': p.gender,
      'city': p.city, 'country': p.country, 'caste': p.caste, 'sect': p.sect, 'languages': p.languages,
      'education': p.education, 'degree_title': p.degreeTitle,
      'institute': p.institute, 'profession': p.profession,
      'employment_type': p.employmentType, 'salary_start': p.salaryStart,
      'salary_end': p.salaryEnd, 'monthly_income': p.monthlyIncome,
      'height_inches': p.heightInches, 'weight_kg': p.weightKg,
      'complexion': p.complexion, 'marital_status': p.maritalStatus,
      'boys': p.boys, 'girls': p.girls, 'practice_level': p.practiceLevel,
      'hijab': p.hijab, 'beard': p.beard, 'father_alive': p.fatherAlive,
      'father_occupation': p.fatherOccupation, 'mother_alive': p.motherAlive,
      'mother_occupation': p.motherOccupation, 'sisters': p.sisters, 'brothers': p.brothers,
      'home_type': p.homeType, 'house_size': p.houseSize, 'has_car': p.hasCar,
      'car_name': p.carName, 'has_other_property': p.hasOtherProperty, 'other_property': p.otherProperty,
      'has_generator': p.hasGenerator, 'has_solar': p.hasSolar, 'has_servant': p.hasServant,
      'looking_for': p.lookingFor, 'about': p.about, 'contact_phone': p.contactPhone,
      'phone_verified': p.phoneVerified, 'email_verified': p.emailVerified,
      'cnic_verified': p.cnicVerified, 'smokes': p.smokes, 'drinks': p.drinks,
      'physically_active': p.physicallyActive, 'has_disability': p.hasDisability,
      'posted_at': p.postedAt.toIso8601String(),
      'subscription_tier': p.subscription.name,
      'is_boosted': boosted,
      'profile_photo_url': p.photoUrl,
      'disability_details': p.disabilityDetails, 'location': p.location,
    };
    return RishtaProposal.fromJson(json);
  }

  List<RishtaProposal> _applyFilters(
      List<RishtaProposal> list, FilterState f) {
    if (f.gender != null) {
      list = list.where((p) => p.gender.toLowerCase() == f.gender!.toLowerCase()).toList();
    }
    if (f.cities.isNotEmpty) {
      list = list.where((p) => f.cities.contains(p.city)).toList();
    }
    if (f.castes.isNotEmpty) {
      list = list.where((p) => f.castes.contains(p.caste)).toList();
    }
    if (f.sects.isNotEmpty) {
      list = list.where((p) => f.sects.contains(p.sect)).toList();
    }
    if (f.professions.isNotEmpty) {
      list = list.where((p) => f.professions.contains(p.profession)).toList();
    }
    if (f.maritalStatuses.isNotEmpty) {
      list = list.where((p) => f.maritalStatuses.contains(p.maritalStatus)).toList();
    }
    if (f.educations.isNotEmpty) {
      list = list.where((p) => f.educations.contains(p.education)).toList();
    }
    if (f.cnicVerified == true) {
      list = list.where((p) => p.cnicVerified).toList();
    }
    list = list
        .where((p) => p.age >= f.ageRange.start && p.age <= f.ageRange.end)
        .toList();
    list = list
        .where((p) =>
            p.heightInches >= f.heightRange.start &&
            p.heightInches <= f.heightRange.end)
        .toList();
    return list;
  }

  /// Subscribes to realtime status changes for a specific proposal.
  RealtimeChannel subscribeToProposalStatus(String proposalId, void Function(String status, String? deletedFrom, String? subStatus) onStatusChange, {String? initialStatus, String? initialSubStatus}) {
    final channelName = 'public:proposals:id=eq.$proposalId';
    String? _lastStatus = initialStatus;
    String? _lastSubStatus = initialSubStatus;
    return _client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'proposals',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: proposalId),
          callback: (payload) {
            final newStatus = payload.newRecord['status'] as String?;
            final deletedFrom = payload.newRecord['deleted_from'] as String?;
            final newSubStatus = payload.newRecord['subscription_status'] as String?;
            final newExpiry = payload.newRecord['subscription_expiry'] as String?;
            final newExpiryDate = newExpiry != null ? DateTime.tryParse(newExpiry) : null;
            final statusChanged = newStatus != null && newStatus != _lastStatus;
            final subExpired = newSubStatus == 'expired' && !statusChanged;
            // Only treat as renewal if previously expired AND new expiry is genuinely far in future (>1 day)
            final subRenewed = newSubStatus == 'active' && _lastSubStatus == 'expired' && !statusChanged &&
                newExpiryDate != null && newExpiryDate.isAfter(DateTime.now().add(const Duration(days: 1)));
            // Fire if status changed, subscription expired, or subscription genuinely renewed
            if (statusChanged || subExpired || subRenewed) {
              _lastStatus = newStatus;
              _lastSubStatus = newSubStatus;
              onStatusChange(newStatus ?? _lastStatus ?? '', deletedFrom, newSubStatus);
            } else {
              // Always update tracked subStatus even if we don't fire
              _lastSubStatus = newSubStatus;
            }
          },
        )
        .subscribe((status, [error]) {
        });
  }

  /// Subscribes to realtime inserts on proposals (new approved proposals).
  /// Call this once in GroupFeedScreen.initState().
  RealtimeChannel subscribeToFeed(void Function(RishtaProposal) onNew) {
    return _client
        .channel('public:proposals')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'proposals',
          callback: (payload) {
            if (payload.newRecord['status'] == 'active') {
              final proposal = RishtaProposal.fromJson(payload.newRecord);
              onNew(proposal);
            }
          },
        )
        .subscribe();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SUBMIT PROPOSAL
  // ══════════════════════════════════════════════════════════════════════════

  /// Uploads photos to Storage and inserts a pending proposal.
  /// Returns the new proposal ID, or throws on error.
  Future<String> submitProposal({
    required Map<String, dynamic> proposalData,
    File? profilePhotoFile,
    File? cnicFrontFile,
    File? cnicBackFile,
  }) async {
    // Ensure NOT NULL columns always have a value even if form was skipped
    final safeData = Map<String, dynamic>.from(proposalData);
    safeData['name']           = (safeData['name'] as String?)?.trim().isEmpty == true ? 'Unknown' : safeData['name'] ?? 'Unknown';
    safeData['age']            = safeData['age'] ?? 0;
    safeData['gender']         = safeData['gender'] ?? '';
    safeData['city']           = safeData['city'] ?? '';
    safeData['caste']          = safeData['caste'] ?? '';
    safeData['sect']           = safeData['sect'] ?? '';
    safeData['education']      = safeData['education'] ?? '';
    safeData['profession']     = safeData['profession'] ?? '';
    safeData['height_inches']  = safeData['height_inches'] ?? 64.0;
    safeData['marital_status'] = safeData['marital_status'] ?? 'Never married';
    safeData['contact_phone']  = safeData['contact_phone'] ?? '';
    safeData['sisters']        = safeData['sisters'] ?? 0;
    safeData['brothers']       = safeData['brothers'] ?? 0;

    // Upload photos to Cloudflare R2
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final cnic = (safeData['cnic'] as String? ?? 'unknown').replaceAll('-', '');

    Future<String?> _uploadPhoto(File? file, String type) async {
      if (file == null) return null;
      try {
        final bytes = await file.readAsBytes();
        final path = 'proposals/$cnic/${type}_$timestamp.jpg';
        final url = await _uploadToR2(bytes: bytes, path: path);
        debugPrint('✅ Uploaded $type photo: $url');
        return url;
      } catch (e) {
        debugPrint('❌ Failed to upload $type photo: $e');
        return null;
      }
    }

    final profileUrl   = await _uploadPhoto(profilePhotoFile, 'profile');
    final cnicFrontUrl = await _uploadPhoto(cnicFrontFile, 'cnic_front');
    final cnicBackUrl  = await _uploadPhoto(cnicBackFile, 'cnic_back');

    // Insert row with storage URLs (no base64 in DB)
    final inserted = await _client
        .from('proposals')
        .insert({
          ...safeData,
          'status': 'pending',
          'subscription_tier': 'none',
          'is_boosted': false,
          if (profileUrl   != null) 'profile_photo_url': profileUrl,
          if (cnicFrontUrl != null) 'cnic_front_url': cnicFrontUrl,
          if (cnicBackUrl  != null) 'cnic_back_url':  cnicBackUrl,
        })
        .select('id')
        .single();

    // Store CNIC for subscription check on feed load
    _submittedCnic = safeData['cnic'] as String?;
    return inserted['id'] as String;
  }

  /// Returns the public URL for a profile photo.
  String getProfilePhotoUrl(String storagePath) {
    return _client.storage.from('profile-photos').getPublicUrl(storagePath);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SUBSCRIPTION — Code redemption & status check
  // ══════════════════════════════════════════════════════════════════════════

  /// Checks if the current user (by proposalId) has an active subscription.
  Future<bool> hasActiveSubscription(String proposalId) async {
    final res = await _client
        .from('subscriptions')
        .select('status, expiry_date')
        .eq('user_id', proposalId)
        .maybeSingle();

    if (res == null) return false;
    if (res['status'] != 'active') return false;
    final expiry = DateTime.tryParse(res['expiry_date'] ?? '');
    return expiry != null && expiry.isAfter(DateTime.now());
  }

  /// Atomically redeems an activation code for a given proposalId.
  /// Returns a [CodeRedemptionResult] with success/error info.
  // Stored after successful CNIC activation — persisted via SharedPreferences
  String? _activatedCnic;
  String? get activatedCnic => _activatedCnic;

  void setActivatedCnic(String cnic) {
    _activatedCnic = cnic.trim();
    _submittedCnic = cnic.trim();
    _persistCnic(cnic.trim());
    notifyListeners();
  }

  void clearActivatedCnic() {
    _activatedCnic = null;
    _submittedCnic = null;
    SharedPreferences.getInstance().then((p) {
      p.remove(_kActivatedCnicKey);
      p.remove('user_cnic');
    });
  }

  // Stored after proposal submission
  String? _submittedCnic;
  String? get submittedCnic => _submittedCnic;

  static const _kActivatedCnicKey = 'activated_cnic';

  /// Call once on app start to restore persisted CNIC
  Future<void> restorePersistedCnic() async {
    final prefs = await SharedPreferences.getInstance();
    _activatedCnic = prefs.getString(_kActivatedCnicKey) ?? prefs.getString('user_cnic');
    _submittedCnic = _activatedCnic;
    // Also ensure activated_cnic is written for future restores
    if (_activatedCnic != null) {
      await prefs.setString(_kActivatedCnicKey, _activatedCnic!);
    }
  }

  Future<void> _persistCnic(String cnic) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActivatedCnicKey, cnic);
  }

  /// Returns the gender of the proposal matching this CNIC (for filter locking)
  Future<String?> getUserGenderByCnic(String cnic) async {
    try {
      final res = await _client
          .from('proposals')
          .select('gender, status')
          .eq('cnic', cnic.trim());
      final rows = (res as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return null;
      // Prefer non-deleted row if multiple exist
      const priority = ['pending', 'active', 'approved', 'paused', 'deleted'];
      rows.sort((a, b) {
        final ai = priority.indexOf(a['status'] as String? ?? '');
        final bi = priority.indexOf(b['status'] as String? ?? '');
        return (ai == -1 ? priority.length : ai).compareTo(bi == -1 ? priority.length : bi);
      });
      return rows.first['gender'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasActiveSubscriptionByCnic(String cnic) async {
    try {
      final res = await _client
          .from('proposals')
          .select('status')
          .eq('cnic', cnic.trim())
          .eq('status', 'active')
          .maybeSingle();
      return res != null;
    } catch (e) {
      debugPrint('hasActiveSubscriptionByCnic error: $e');
      return false;
    }
  }

  /// Returns true if a proposal with this CNIC already exists in Supabase.
  Future<bool> checkCnicExists(String cnic) async {
    try {
      final res = await _client
          .from('proposals')
          .select('id')
          .eq('cnic', cnic.trim())
          .inFilter('status', ['active', 'approved'])
          .limit(1);
      return (res as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the full proposal by ID (for self-view).
  Future<RishtaProposal?> fetchProposalById(String id) async {
    try {
      final res = await _client
          .from('proposals')
          .select('*, proposal_photos(*)')
          .eq('id', id)
          .maybeSingle();
      if (res == null) return null;
      return RishtaProposal.fromJson(res as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
  }

  /// Fetches user status fields by CNIC for displaying status tag after login.
  Future<Map<String, dynamic>?> fetchUserStatusByCnic(String cnic) async {
    try {
      final res = await _client
          .from('proposals')
          .select('id, proposal_number, name, age, city, country, profession, education, caste, sect, languages, marital_status, practice_level, hijab, beard, height_inches, home_type, house_size, location, about, looking_for, suggested_info, father_alive, mother_alive, brothers, sisters, status, deleted_from, subscription_tier, subscription_status, subscription_start, subscription_expiry, profile_photo_url, password, featured_boosts!featured_boosts_user_id_fkey(scheduled_date, is_used)')
          .eq('cnic', cnic.trim());
      final rows = (res as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return null;
      if (rows.length == 1) return rows.first;
      // Multiple rows for same CNIC (e.g. pending + deleted) — prefer non-deleted:
      // Priority: pending > active/approved/paused > deleted
      const priority = ['pending', 'active', 'approved', 'paused', 'deleted'];
      rows.sort((a, b) {
        final ai = priority.indexOf(a['status'] as String? ?? '');
        final bi = priority.indexOf(b['status'] as String? ?? '');
        final ai2 = ai == -1 ? priority.length : ai;
        final bi2 = bi == -1 ? priority.length : bi;
        return ai2.compareTo(bi2);
      });
      return rows.first;
    } catch (_) {
      return null;
    }
  }

  /// Returns true if the CNIC exists and password matches.
  Future<Set<String>> fetchNotInterestedIds(String cnic) async {
    try {
      final res = await _client
          .from('proposals')
          .select('not_interested_ids')
          .eq('cnic', cnic.trim())
          .maybeSingle();
      if (res == null) return {};
      final ids = (res['not_interested_ids'] as List?)?.cast<String>() ?? [];
      return ids.toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> addNotInterestedId(String cnic, String proposalId) async {
    try {
      await _client.rpc('append_not_interested', params: {
        'p_cnic': cnic.trim(),
        'p_proposal_id': proposalId,
      });
    } catch (_) {}
  }

  Future<bool> verifyCnicPassword(String cnic, String password) async {
    try {
      final res = await _client
          .from('proposals')
          .select('id')
          .eq('cnic', cnic.trim())
          .eq('password', password.trim())
          .limit(1);
      return (res as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<CodeRedemptionResult> activateByCnic(String cnic) async {
    try {
      final res = await _client.rpc('activate_by_cnic', params: {
        'p_cnic': cnic.trim(),
      });
      final data = res as Map<String, dynamic>;
      if (data['success'] == true) {
        _activatedCnic = cnic.trim();
        _submittedCnic = cnic.trim();
        await _persistCnic(cnic.trim());
        notifyListeners();
        return CodeRedemptionResult(
          success: true,
          tier: 'basic',
          expiry: data['expiry'] != null ? DateTime.parse(data['expiry']) : null,
        );
      } else {
        final error = data['error'] as String? ?? '';
        // Already active = treat as success, store CNIC so feed unlocks
        if (error.toLowerCase().contains('already active')) {
          _activatedCnic = cnic.trim();
          _submittedCnic = cnic.trim();
          await _persistCnic(cnic.trim());
          notifyListeners();
        }
        return CodeRedemptionResult(success: false, error: error);
      }
    } catch (e) {
      return CodeRedemptionResult(success: false, error: e.toString());
    }
  }

  Future<CodeRedemptionResult> redeemCode({
    required String proposalId,
    required String code,
  }) async {
    try {
      final res = await _client.rpc('redeem_activation_code', params: {
        'p_user_id': proposalId,
        'p_code': code.trim().toUpperCase(),
      });

      final data = res as Map<String, dynamic>;
      if (data['success'] == true) {
        notifyListeners();
        return CodeRedemptionResult(
          success: true,
          tier: data['tier'] as String?,
          expiry: data['expiry'] != null
              ? DateTime.parse(data['expiry'])
              : null,
        );
      } else {
        return CodeRedemptionResult(
          success: false,
          error: data['error'] as String? ?? 'Redemption failed',
        );
      }
    } catch (e) {
      return CodeRedemptionResult(success: false, error: e.toString());
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ADMIN — Users / Proposals
  // ══════════════════════════════════════════════════════════════════════════

  /// Fetches all users (admin view) with their subscription and boost data.
  Future<double> fetchMonthlyRevenue() async {
    final now = DateTime.now();
    final res = await _client.rpc('get_monthly_revenue', params: {'p_year': now.year, 'p_month': now.month});
    return (res as num?)?.toDouble() ?? 0.0;
  }

  Future<void> pauseUser(String userId) async {
    await _client.from('proposals').update({'status': 'paused'}).eq('id', userId);
    notifyListeners();
  }

  Future<void> activateUser(String userId) async {
    await _client.from('proposals').update({'status': 'active'}).eq('id', userId);
    notifyListeners();
  }

  Future<String> addUser(Map<String, dynamic> data) async {
    final res = await _client.from('proposals').insert(data).select('id').single();
    notifyListeners();
    return res['id'] as String;
  }

  /// Approves an AI imported proposal with amount_paid = 0
  Future<void> approveAiProposal(String userId) async {
    try {
      final settings = await fetchAppSettings();
      final days = int.tryParse(settings['standard_plan_days'] ?? '90') ?? 90;
      final expiry = DateTime.now().add(Duration(days: days)).toIso8601String();
      await _client.from('proposals').update({
        'status'              : 'active',
        'subscription_tier'   : 'basic',
        'subscription_status' : 'active',
        'amount_paid'         : 0,
        'subscription_days'   : days,
        'subscription_expiry' : expiry,
        'subscription_start'  : DateTime.now().toIso8601String(),
        'approved_at'         : DateTime.now().toIso8601String(),
      }).eq('id', userId);
      debugPrint('🟢 approveAiProposal done for userId=$userId');
      notifyListeners();
    } catch (e) {
      debugPrint('approveAiProposal error: $e');
      rethrow;
    }
  }

  /// Admin import: insert proposal then upload photos to R2
  Future<void> addUserWithPhotos({
    required Map<String, dynamic> data,
    File? profilePhoto,
    File? cnicFront,
    File? cnicBack,
  }) async {
    final res = await _client.from('proposals').insert(data).select('id').single();
    final id = res['id'] as String;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    Future<String?> _up(File? file, String type) async {
      if (file == null) return null;
      try {
        final bytes = await file.readAsBytes();
        final path = 'proposals/$id/${type}_$timestamp.jpg';
        return await _uploadToR2(bytes: bytes, path: path);
      } catch (e) {
        debugPrint('Photo upload failed ($type): $e');
        return null;
      }
    }

    final profileUrl = await _up(profilePhoto, 'profile');
    final frontUrl   = await _up(cnicFront,    'cnic_front');
    final backUrl    = await _up(cnicBack,      'cnic_back');

    final updates = <String, dynamic>{};
    if (profileUrl != null) updates['profile_photo_url'] = profileUrl;
    if (frontUrl   != null) updates['cnic_front_url']    = frontUrl;
    if (backUrl    != null) updates['cnic_back_url']     = backUrl;
    if (updates.isNotEmpty) {
      await _client.from('proposals').update(updates).eq('id', id);
    }
    notifyListeners();
  }

  /// Records payment by CNIC — matches to proposal or stores for admin to match
  Future<void> recordPaymentByCnic({
    required String cnic,
    required double amount,
    required String plan,
  }) async {
    final res = await _client
        .from('proposals')
        .select('id')
        .eq('cnic', cnic)
        .maybeSingle();

    if (res != null) {
      await _client.from('proposals').update({
        'amount_paid'   : amount,
        'payment_status': 'paid',
        'paid_at'       : DateTime.now().toIso8601String(),
      }).eq('id', res['id']);
    } else {
      // Store pending payment for admin to match later
      try {
        await _client.from('pending_payments').insert({
          'cnic'    : cnic,
          'amount'  : amount,
          'plan'    : plan,
          'paid_at' : DateTime.now().toIso8601String(),
          'matched' : false,
        });
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Approves a proposal: sets status=active AND creates a paid subscription
  /// Rs. 1,000 basic plan, 90 days validity — called when admin confirms payment
  Future<void> approveProposal(String userId) async {
    final settings = await fetchAppSettings();
    final isFreeMode = settings['free_mode'] == 'true';
    final price = isFreeMode ? 0 : (int.tryParse(settings['standard_plan_price'] ?? '1000') ?? 1000);
    final days = int.tryParse(settings['standard_plan_days'] ?? '90') ?? 90;
    final expiry = DateTime.now().add(Duration(days: days)).toIso8601String();

    final now = DateTime.now().toIso8601String();
    await _client.from('proposals').update({
      'status': 'active',
      'subscription_tier': 'basic',
      'subscription_status': 'active',
      'amount_paid': price,
      'subscription_days': days,
      'subscription_expiry': expiry,
      'subscription_start': now,
      'approved_at': now,
    }).eq('id', userId);

    notifyListeners();
  }

  Future<Map<String, dynamic>> renewSubscription(String userId) async {
    final settings = await fetchAppSettings();
    final isFreeMode = settings['free_mode'] == 'true';
    final price = isFreeMode ? 0 : (int.tryParse(settings['standard_plan_price'] ?? '1000') ?? 1000);
    final days  = int.tryParse(settings['standard_plan_days'] ?? '90') ?? 90;
    final start  = DateTime.now();
    final expiry = start.add(Duration(days: days));
    // Add price to existing amount_paid (cumulative spent)
    final row = await _client.from('proposals').select('amount_paid').eq('id', userId).single();
    final currentPaid = (row['amount_paid'] as num?)?.toInt() ?? 0;
    await _client.from('proposals').update({
      'status': 'active',
      'deleted_from': null,
      'subscription_tier': 'basic',
      'subscription_status': 'active',
      'amount_paid': currentPaid + price,
      'subscription_days': days,
      'subscription_expiry': expiry.toIso8601String(),
      'subscription_start': start.toIso8601String(),
      'approved_at': start.toIso8601String(),
    }).eq('id', userId);
    notifyListeners();
    return {'price': price, 'days': days, 'expiry': expiry};
  }

  Future<void> deleteUser(String userId, {String from = 'users', String? reason}) async {
    await _client.from('proposals').update({
      'status': 'deleted',
      'deleted_from': from,
      if (reason != null) 'deletion_reason': reason,
    }).eq('id', userId);
    notifyListeners();
  }

  Future<void> restoreUser(String userId, String? deletedFrom) async {
    final status = deletedFrom == 'users' ? 'active' : 'pending';
    await _client.from('proposals').update({
      'status': status,
      'deleted_from': null,
      'deletion_reason': null,
    }).eq('id', userId);
    notifyListeners();
  }

  Future<void> permanentlyDeleteUser(String userId) async {
    // Direct DELETE is blocked by RLS when the admin is not Supabase-Auth'd.
    // Use a SECURITY DEFINER RPC that only deletes rows already soft-deleted.
    await _client.rpc('admin_permanently_delete_proposal', params: {'p_id': userId});
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ADMIN — Activation codes
  // ══════════════════════════════════════════════════════════════════════════

  Future<Map<String, String>> fetchAppSettings() async {
    final res = await _client.from('app_settings').select();
    final map = <String, String>{};
    for (final row in res as List) {
      map[row['key'] as String] = row['value'] as String;
    }
    _cachedSettings = map;
    notifyListeners();
    return map;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ADMIN — Featured boosts & credits
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> addFeaturedCredits(String userId, int credits, {int pricePerCredit = 200}) async {
    await _client.rpc('add_featured_credits', params: {
      'p_user_id': userId,
      'p_credits': credits,
    });
    // Persist the spending increase to amount_paid so it survives relogin
    final row = await _client.from('proposals')
        .select('amount_paid')
        .eq('id', userId)
        .single();
    final current = (row['amount_paid'] as num?)?.toDouble() ?? 0;
    await _client.from('proposals')
        .update({'amount_paid': current + (credits * pricePerCredit)})
        .eq('id', userId);
    notifyListeners();
  }

  Future<void> removeFeaturedCredits(String userId, int credits) async {
    await _client.rpc('remove_featured_credits', params: {
      'p_user_id': userId,
      'p_credits': credits,
    });
    notifyListeners();
  }

  // Returns null on success, or an error key string on failure
  Future<String?> scheduleFeaturedPost(
      String userId, DateTime date, String city) async {
    try {
      // Check credits
      final row = await _client.from('proposals')
          .select('featured_credits_purchased, featured_credits_used')
          .eq('id', userId).single();
      final purchased = (row['featured_credits_purchased'] as num?)?.toInt() ?? 0;
      final used = (row['featured_credits_used'] as num?)?.toInt() ?? 0;
      if (purchased - used <= 0) return 'no_credits';

      // Check duplicate city for this user
      final existing = await _client.from('featured_boosts')
          .select('id').eq('user_id', userId).eq('city', city).eq('is_used', false);
      if ((existing as List).isNotEmpty) return 'duplicate_city';

      // Check city-wide 3-post limit
      final cityCount = await _client.from('featured_boosts').select('id')
          .eq('city', city).eq('is_used', false);
      if ((cityCount as List).length >= 3) return 'city_limit';

      await _client.rpc('admin_insert_featured_boost', params: {
        'p_user_id': userId,
        'p_scheduled_date': date.toUtc().toIso8601String(),
        'p_city': city,
      });
      await _client.rpc('consume_featured_credit', params: {'p_user_id': userId});
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> removeFeaturedSchedule(String boostId, String userId) async {
    await _client.rpc('admin_delete_featured_boost', params: {
      'p_boost_id': boostId,
    });
    // Restore credit
    await _client.rpc('restore_featured_credit', params: {'p_user_id': userId});
    notifyListeners();
  }

  Future<void> confirmFeaturedTokens(String userId) async {
    await _client.rpc('confirm_featured_tokens', params: {'p_user_id': userId});
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ADMIN — Stats dashboard
  // ══════════════════════════════════════════════════════════════════════════

  Future<AdminStats> fetchStats() async {
    final res = await _client.rpc('get_admin_stats');
    return AdminStats.fromJson(res as Map<String, dynamic>);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  ADMIN — Expire subscriptions (manual trigger)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> checkAndExpireSubscriptions() async {
    await _client.rpc('expire_subscriptions');
    notifyListeners();
  }

  // ── Cloudflare R2 Upload (AWS Signature V4) ───────────────────────────────
  Future<String> _uploadToR2({required Uint8List bytes, required String path}) async {
    final uri = Uri.parse('$_r2Endpoint/$_r2Bucket/$path');
    final now = DateTime.now().toUtc();
    final dateStamp = now.year.toString() +
        now.month.toString().padLeft(2, '0') +
        now.day.toString().padLeft(2, '0');
    final amzDate = dateStamp + 'T' +
        now.hour.toString().padLeft(2, '0') +
        now.minute.toString().padLeft(2, '0') +
        now.second.toString().padLeft(2, '0') + 'Z';

    final auth = _buildR2Auth(
      method: 'PUT',
      objectPath: '/$_r2Bucket/$path',
      amzDate: amzDate,
      dateStamp: dateStamp,
    );

    final response = await http.put(uri, headers: {
      'Content-Type': 'image/jpeg',
      'x-amz-date': amzDate,
      'x-amz-content-sha256': 'UNSIGNED-PAYLOAD',
      'Authorization': auth,
    }, body: bytes);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return '$_r2PublicUrl/$path';
    }
    throw Exception('R2 upload failed: \${response.statusCode} \${response.body}');
  }

  String _buildR2Auth({required String method, required String objectPath, required String amzDate, required String dateStamp}) {
    const region = 'auto';
    const service = 's3';
    final scope = '$dateStamp/$region/$service/aws4_request';
    const signedHeaders = 'content-type;x-amz-content-sha256;x-amz-date';
    const payload = 'UNSIGNED-PAYLOAD';
    final canonical = '$method\n$objectPath\n\ncontent-type:image/jpeg\nx-amz-content-sha256:$payload\nx-amz-date:$amzDate\n\n$signedHeaders\n$payload';
    final canonicalHash = _r2Sha256(utf8.encode(canonical));
    final stringToSign = 'AWS4-HMAC-SHA256\n$amzDate\n$scope\n$canonicalHash';
    final signingKey = _r2DeriveKey(dateStamp, region, service);
    final signature = _r2HmacHex(signingKey, stringToSign);
    return 'AWS4-HMAC-SHA256 Credential=$_r2AccessKeyId/$scope, SignedHeaders=$signedHeaders, Signature=$signature';
  }

  List<int> _r2DeriveKey(String date, String region, String service) {
    final kDate    = _r2Hmac(utf8.encode('AWS4$_r2SecretAccessKey'), date);
    final kRegion  = _r2Hmac(kDate, region);
    final kService = _r2Hmac(kRegion, service);
    return _r2Hmac(kService, 'aws4_request');
  }

  List<int> _r2Hmac(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).bytes;

  String _r2HmacHex(List<int> key, String data) =>
      _r2Hmac(key, data).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  String _r2Sha256(List<int> data) =>
      sha256.convert(data).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ─────────────────────────────────────────────────────────────────────────────
//  Result types
// ─────────────────────────────────────────────────────────────────────────────

class CodeRedemptionResult {
  final bool success;
  final String? tier;
  final DateTime? expiry;
  final String? error;

  CodeRedemptionResult({
    required this.success,
    this.tier,
    this.expiry,
    this.error,
  });
}

class AdminStats {
  final int totalSubscribers;
  final int activeUsers;
  final int pendingProposals;
  final double allTimeRevenue;
  final double monthlyRevenue;
  final int activeFeaturedPosts;

  AdminStats({
    required this.totalSubscribers,
    required this.activeUsers,
    required this.pendingProposals,
    required this.allTimeRevenue,
    required this.monthlyRevenue,
    required this.activeFeaturedPosts,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) => AdminStats(
        totalSubscribers: (json['total_subscribers'] ?? 0) as int,
        activeUsers: (json['active_users'] ?? 0) as int,
        pendingProposals: (json['pending_proposals'] ?? 0) as int,
        allTimeRevenue:
            double.tryParse(json['all_time_revenue'].toString()) ?? 0,
        monthlyRevenue:
            double.tryParse(json['monthly_revenue'].toString()) ?? 0,
        activeFeaturedPosts: (json['active_featured_posts'] ?? 0) as int,
      );
}
