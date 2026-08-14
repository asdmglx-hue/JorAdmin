// ── Admin Models for Jor — Supabase Edition ───────────────────────────

class _Unset { const _Unset(); }
const _unset = _Unset();

enum ProposalStatus { pending, approved, active, paused, expired, deleted }
enum SubscriptionTier { none, basic, featured }
enum SubscriptionStatus { inactive, active, expired, refunded }

// ── Activation Code ───────────────────────────────────────────────────────────
class ActivationCode {
  final String id;
  final String code;
  final SubscriptionTier tier;
  final double price;
  final bool isUsed;
  final String? usedByUserId;
  final DateTime createdAt;
  final DateTime? usedAt;

  ActivationCode({
    String? id,          // optional so old AdminService constructor still works
    required this.code,
    required this.tier,
    required this.price,
    this.isUsed = false,
    this.usedByUserId,
    required this.createdAt,
    this.usedAt,
  }) : id = id ?? code; // fallback: use code itself as id when not from DB

  factory ActivationCode.fromJson(Map<String, dynamic> json) => ActivationCode(
        id: json['id'] as String,
        code: json['code'] as String,
        tier: _parseTier(json['tier'] as String? ?? 'none'),
        price: double.tryParse(json['price'].toString()) ?? 0,
        isUsed: json['is_used'] as bool? ?? false,
        usedByUserId: json['used_by_user_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        usedAt: json['used_at'] != null ? DateTime.parse(json['used_at'] as String) : null,
      );

  static SubscriptionTier _parseTier(String s) {
    switch (s) {
      case 'featured': return SubscriptionTier.featured;
      case 'basic': return SubscriptionTier.basic;
      default: return SubscriptionTier.none;
    }
  }

  ActivationCode copyWith({bool? isUsed, String? usedByUserId, DateTime? usedAt}) =>
      ActivationCode(
        id: id, code: code, tier: tier, price: price,
        isUsed: isUsed ?? this.isUsed,
        usedByUserId: usedByUserId ?? this.usedByUserId,
        createdAt: createdAt,
        usedAt: usedAt ?? this.usedAt,
      );
}

// ── Admin Account ────────────────────────────────────────────────────────────
// A CNIC + password login created from Dashboard → Settings → Create Admin.
// Logging in with these credentials on the regular login screen unlocks
// full (unblurred / unmasked) viewing of all profiles in the app — it does
// NOT grant access to this Admin Panel itself (that's the separate 6-digit
// PIN on the panel's own login screen).
class AdminAccount {
  final String id;
  final String name;
  final String cnic;
  final String password;
  final DateTime createdAt;

  const AdminAccount({
    required this.id,
    required this.name,
    required this.cnic,
    required this.password,
    required this.createdAt,
  });

  factory AdminAccount.fromMap(Map<String, dynamic> map) => AdminAccount(
        id: map['id'] as String,
        name: map['name'] as String,
        cnic: map['cnic'] as String,
        password: map['password'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

// ── Coupon codes ─────────────────────────────────────────────────────────
// Percentage-discount codes, distinct from ActivationCode (a single-use,
// fixed-price gift code). A coupon can be reused by many users until the
// admin deactivates it.
class CouponCode {
  final String id;
  final String code;
  final String type; // 'percentage', 'free_days', or 'free_trial'
  final int? discountPercent;
  final int? freeDays;
  final int? trialDays;
  final bool active;
  final int timesUsed;
  final DateTime createdAt;
  final DateTime? expiresAt;

  CouponCode({
    required this.id,
    required this.code,
    required this.type,
    this.discountPercent,
    this.freeDays,
    this.trialDays,
    required this.active,
    required this.timesUsed,
    required this.createdAt,
    this.expiresAt,
  });

  bool get isPercentage => type == 'percentage';
  bool get isFreeTrial => type == 'free_trial';
  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());

  factory CouponCode.fromJson(Map<String, dynamic> json) => CouponCode(
        id: json['id'] as String,
        code: json['code'] as String,
        type: json['coupon_type'] as String? ?? 'percentage',
        discountPercent: (json['discount_percent'] as num?)?.toInt(),
        freeDays: (json['free_days'] as num?)?.toInt(),
        trialDays: (json['trial_days'] as num?)?.toInt(),
        active: json['active'] as bool? ?? true,
        timesUsed: (json['times_used'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(json['created_at'] as String),
        expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at'] as String) : null,
      );
}

// ── Featured Boost ────────────────────────────────────────────────────────────
class FeaturedBoost {
  final String? id;
  final DateTime scheduledDate;
  final String city;
  final bool isUsed;

  FeaturedBoost({this.id, required this.scheduledDate, this.city = '', this.isUsed = false});

  factory FeaturedBoost.fromJson(Map<String, dynamic> json) => FeaturedBoost(
        id: json['id'] as String?,
        scheduledDate: DateTime.parse(json['scheduled_date'] as String).toLocal(),
        city: json['city'] as String? ?? '',
        isUsed: json['is_used'] as bool? ?? false,
      );

  bool get isCompleted =>
      isUsed || DateTime.now().isAfter(scheduledDate.add(const Duration(hours: 24)));

  bool get isActive =>
      !isCompleted &&
      DateTime.now().isAfter(scheduledDate) &&
      DateTime.now().isBefore(scheduledDate.add(const Duration(hours: 24)));

  Duration get timeRemaining {
    if (!isActive) return Duration.zero;
    return scheduledDate.add(const Duration(hours: 24)).difference(DateTime.now());
  }
}

// ── AdminUser ─────────────────────────────────────────────────────────────────
class AdminUser {
  final String id;
  final int? proposalNumber;
  final String name;
  final int age;
  final String gender;
  final String city;
  final String? country;
  final String caste;
  final String sect;
  final List<String> languages;
  final String education;
  final String? institute;
  final String? degreeTitle;
  final String? degreeCertificateUrl;
  final String? institute2;
  final String? degreeTitle2;
  final String? degreeCertificate2Url;
  final String? institute3;
  final String? degreeTitle3;
  final String? degreeCertificate3Url;
  final String profession;
  final String? professionCategory;
  final String? employmentType;
  final double? salaryStart;
  final double? salaryEnd;
  final double heightInches;
  final double? weightKg;
  final String? complexion;
  final String maritalStatus;
  final String? openToPolygamy;
  final String? marriageNumber;
  final int? boys;
  final int? girls;
  final String? practiceLevel;
  final String? hijab;
  final String? beard;
  final String? familyType;
  final bool? fatherAlive;
  final bool? motherAlive;
  final String? fatherOccupation;
  final String? motherOccupation;
  final int sisters;
  final int brothers;
  final String? homeType;
  final String? houseSize;
  final String? location;
  final String? disabilityDetails;
  final bool? hasKids;
  final bool? hasSiblings;
  final String? hasCar;
  final String? hasOtherProperty;
  final String? otherProperty;
  final String? carName;
  final bool? hasGenerator;
  final bool? hasSolar;
  final bool? hasServant;
  final String? lookingFor;
  final String? about;
  final String contactPhone;
  final String? contactPhone2;

  static String formatPhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;
    if (trimmed.startsWith('+')) {
      const formats = <(String, List<int>)>[
        ('+353', [2, 3, 4]), ('+966', [2, 3, 4]), ('+971', [2, 3, 4]),
        ('+968', [4, 4]), ('+974', [4, 4]), ('+973', [4, 4]), ('+965', [4, 4]),
        ('+92',  [3, 7]), ('+64',  [2, 3, 4]), ('+61',  [3, 3, 3]),
        ('+49',  [3, 7]), ('+47',  [3, 2, 3]), ('+46',  [3, 3, 3]),
        ('+45',  [2, 2, 2, 2]), ('+44', [4, 6]), ('+39', [3, 7]),
        ('+34',  [3, 6]), ('+33',  [1, 2, 2, 2, 2]), ('+31', [1, 4, 4]),
        ('+30',  [3, 7]), ('+90',  [3, 3, 4]), ('+60',  [2, 4, 4]),
        ('+1',   [3, 3, 4]),
      ];
      for (final fmt in formats) {
        if (trimmed.startsWith(fmt.$1)) {
          final local = trimmed.substring(fmt.$1.length)
              .replaceAll(RegExp(r'[^\d]'), '')
              .replaceFirst(RegExp(r'^0+'), '');
          final parts = <String>[];
          var pos = 0;
          for (final g in fmt.$2) {
            if (pos >= local.length) break;
            parts.add(local.substring(pos, (pos + g).clamp(0, local.length)));
            pos += g;
          }
          if (pos < local.length) parts.add(local.substring(pos));
          return '${fmt.$1} ${parts.join(' ')}';
        }
      }
      return trimmed;
    }
    String digits = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('92')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length >= 10) return '+92 ${digits.substring(0, 3)} ${digits.substring(3)}';
    return '+92 $digits';
  }
  final bool phoneVerified;
  final bool emailVerified;
  final bool cnicVerified;
  final String? cnic;
  final String? password;
  final bool? smokes;
  final bool? drinks;
  final String? monthlyIncome;
  final String? hasDisability;
  final String? physicallyActive;
  final DateTime postedAt;

  final ProposalStatus status;
  final SubscriptionTier subscriptionTier;
  final SubscriptionStatus subscriptionStatus;
  final DateTime? subscriptionStart;
  final DateTime? subscriptionExpiry;
  final double totalSpending;
  final int featuredPointsPurchased;
  final int featuredPointsUsed;
  final List<FeaturedBoost> featuredSchedule;
  final String? activationCode;
  final int pendingFeaturedTokens;
  final String? deletedFrom;
  final String? deletionReason;
  final String? adminNotes;
  final bool registrationAllowed;
  final String? discarded;
  final String? suggestedInfo;
  final String? profilePhoto;
  final String? cnicFront;
  final String? cnicBack;
  final String? guardianCnicFront;
  final String? guardianCnicBack;
  final String? educationDocument;
  final String? appliedCouponCode;
  final String? submissionSource; // 'website' | 'android' | null (legacy/admin-imported)

  AdminUser({this.proposalNumber,
    required this.id, required this.name, required this.age, required this.gender,
    required this.city, this.country, required this.caste, required this.sect, this.languages = const [], required this.education,
    this.institute, this.degreeTitle, this.degreeCertificateUrl,
    this.institute2, this.degreeTitle2, this.degreeCertificate2Url,
    this.institute3, this.degreeTitle3, this.degreeCertificate3Url,
    required this.profession, this.professionCategory, this.employmentType,
    this.salaryStart, this.salaryEnd, required this.heightInches, this.weightKg,
    this.complexion, required this.maritalStatus, this.openToPolygamy, this.marriageNumber, this.boys, this.girls,
    this.practiceLevel, this.hijab, this.beard, this.familyType,
    this.fatherAlive, this.motherAlive, this.fatherOccupation, this.motherOccupation,
    this.sisters = 0, this.brothers = 0, this.homeType, this.houseSize,
    this.location, this.disabilityDetails, this.hasKids, this.hasSiblings,
    this.hasCar, this.hasOtherProperty, this.otherProperty, this.carName, this.hasGenerator, this.hasSolar, this.hasServant,
    this.lookingFor, this.about, required this.contactPhone, this.contactPhone2,
    this.phoneVerified = false, this.emailVerified = false, this.cnicVerified = false,
    this.cnic, this.password, this.smokes, this.drinks, this.monthlyIncome, this.hasDisability,
    this.physicallyActive, required this.postedAt,
    this.status = ProposalStatus.pending,
    this.subscriptionTier = SubscriptionTier.none,
    this.subscriptionStatus = SubscriptionStatus.inactive,
    this.subscriptionStart, this.subscriptionExpiry,
    this.totalSpending = 0, this.featuredPointsPurchased = 0, this.featuredPointsUsed = 0,
    this.featuredSchedule = const [], this.activationCode, this.pendingFeaturedTokens = 0,
    this.deletedFrom, this.deletionReason, this.adminNotes, this.registrationAllowed = false, this.discarded, this.suggestedInfo, this.profilePhoto, this.cnicFront, this.cnicBack,
    this.guardianCnicFront, this.guardianCnicBack, this.educationDocument,
    this.appliedCouponCode, this.submissionSource,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    final subs = (json['subscriptions'] as List?)?.firstOrNull as Map<String, dynamic>?;
    final boosts = (json['featured_boosts'] as List? ?? [])
        .map((b) => FeaturedBoost.fromJson(b as Map<String, dynamic>)).toList();
    final photos = (json['proposal_photos'] as List? ?? []);

    String? profilePhoto = photos.where((p) => (p as Map)['photo_type'] == 'profile').map((p) => (p as Map)['storage_path'] as String).firstOrNull
        ?? json['profile_photo_url'] as String?;
    String? cnicFront = photos.where((p) => (p as Map)['photo_type'] == 'cnic_front').map((p) => (p as Map)['storage_path'] as String).firstOrNull
        ?? json['cnic_front_url'] as String?;
    String? cnicBack = photos.where((p) => (p as Map)['photo_type'] == 'cnic_back').map((p) => (p as Map)['storage_path'] as String).firstOrNull
        ?? json['cnic_back_url'] as String?;

    ProposalStatus status;
    switch (json['status'] as String? ?? 'pending') {
      case 'approved': status = ProposalStatus.approved; break;
      case 'active': status = ProposalStatus.active; break;
      case 'paused': status = ProposalStatus.paused; break;
      case 'expired': status = ProposalStatus.expired; break;
      case 'deleted': status = ProposalStatus.deleted; break;
      default: status = ProposalStatus.pending;
    }

    SubscriptionTier tier;
    switch (json['subscription_tier'] as String? ?? 'none') {
      case 'featured': tier = SubscriptionTier.featured; break;
      case 'basic': tier = SubscriptionTier.basic; break;
      default: tier = SubscriptionTier.none;
    }

    SubscriptionStatus subStatus;
    // Read from proposals.subscription_status first (no RLS), fall back to subscriptions join
    final subStatusStr = json['subscription_status'] as String? ?? subs?['status'] as String? ?? 'inactive';
    switch (subStatusStr) {
      case 'active': subStatus = SubscriptionStatus.active; break;
      case 'expired': subStatus = SubscriptionStatus.expired; break;
      case 'refunded': subStatus = SubscriptionStatus.refunded; break;
      default: subStatus = SubscriptionStatus.inactive;
    }

    // Subscription dates — read from proposals columns first (no RLS issues)
    final subStart = json['subscription_start'] != null
        ? DateTime.parse(json['subscription_start'] as String)
        : (subs?['start_date'] != null ? DateTime.parse(subs!['start_date'] as String) : null);
    final subExpiry = json['subscription_expiry'] != null
        ? DateTime.parse(json['subscription_expiry'] as String)
        : (subs?['expiry_date'] != null ? DateTime.parse(subs!['expiry_date'] as String) : null);

    return AdminUser(
      proposalNumber: (json['proposal_number'] as num?)?.toInt(),
      // id is deliberately left as a hard, non-nullable cast — a proposal
      // with no id at all would indicate a much deeper problem worth
      // failing loudly on. Every other field below now has a defensive
      // fallback, since we found real, legitimate rows in production
      // with an unexpectedly null 'education' — proof that assuming any
      // of these fields is always populated isn't safe, and a single
      // row with one missing field should never be able to take down
      // the entire admin app's data loading the way it just did.
      id: json['id'] as String, name: (json['name'] as String?) ?? '(no name)',
      age: (json['age'] as num?)?.toInt() ?? 0, gender: (json['gender'] as String?) ?? '',
      city: (json['city'] as String?) ?? '', country: json['country'] as String?,
      caste: (json['caste'] as String?) ?? '',
      sect: (json['sect'] as String?) ?? '',
      languages: (json['languages'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      education: (json['education'] as String?) ?? '',
      institute: json['institute'] as String?,
      degreeTitle: json['degree_title'] as String?,
      degreeCertificateUrl: json['degree_certificate_url'] as String?,
      institute2: json['institute_2'] as String?,
      degreeTitle2: json['degree_title_2'] as String?,
      degreeCertificate2Url: json['degree_certificate_2_url'] as String?,
      institute3: json['institute_3'] as String?,
      degreeTitle3: json['degree_title_3'] as String?,
      degreeCertificate3Url: json['degree_certificate_3_url'] as String?,
      profession: (json['profession'] as String?) ?? '',
      professionCategory: json['profession_category'] as String?,
      employmentType: json['employment_type'] as String?,
      salaryStart: (json['salary_start'] as num?)?.toDouble(),
      salaryEnd: (json['salary_end'] as num?)?.toDouble(),
      heightInches: (json['height_inches'] as num?)?.toDouble() ?? 0,
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      complexion: json['complexion'] as String?,
      maritalStatus: (json['marital_status'] as String?) ?? '',
      openToPolygamy: json['open_to_polygamy'] as String?,
      marriageNumber: json['marriage_number'] as String?,
      boys: (json['boys'] as num?)?.toInt(), girls: (json['girls'] as num?)?.toInt(),
      practiceLevel: json['practice_level'] as String?,
      hijab: json['hijab'] as String?, beard: json['beard'] as String?,
      familyType: json['family_type'] as String?,
      fatherAlive: json['father_alive'] as bool?, motherAlive: json['mother_alive'] as bool?,
      fatherOccupation: json['father_occupation'] as String?,
      motherOccupation: json['mother_occupation'] as String?,
      sisters: (json['sisters'] as num?)?.toInt() ?? 0,
      brothers: (json['brothers'] as num?)?.toInt() ?? 0,
      homeType: json['home_type'] as String?, houseSize: json['house_size'] as String?,
      location: json['location'] as String?,
      disabilityDetails: json['disability_details'] as String?,
      hasKids: json['has_kids'] as bool?,
      hasSiblings: json['has_siblings'] as bool?,
      hasCar: json['has_car'] as String?, carName: json['car_name'] as String?,
      hasOtherProperty: json['has_other_property'] as String?,
      otherProperty: json['other_property'] as String?,
      hasGenerator: json['has_generator'] as bool?, hasSolar: json['has_solar'] as bool?,
      hasServant: json['has_servant'] as bool?,
      lookingFor: json['looking_for'] as String?, about: json['about'] as String?,
      contactPhone: (json['contact_phone'] as String?) ?? '',
      contactPhone2: json['contact_phone_2'] as String?,
      phoneVerified: json['phone_verified'] as bool? ?? false,
      emailVerified: json['email_verified'] as bool? ?? false,
      cnicVerified: json['cnic_verified'] as bool? ?? false,
      cnic: json['cnic'] as String?, password: json['password'] as String?, smokes: json['smokes'] as bool?,
      drinks: json['drinks'] as bool?,
      monthlyIncome: json['monthly_income'] as String?,
      hasDisability: json['has_disability'] == null ? null : (json['has_disability'] == true || json['has_disability'] == 'true' || json['has_disability'] == 'Yes' ? 'Yes' : 'No'),
      physicallyActive: json['physically_active']?.toString(),
      postedAt: json['posted_at'] != null ? DateTime.parse(json['posted_at'] as String) : DateTime.fromMillisecondsSinceEpoch(0),
      status: status, subscriptionTier: tier, subscriptionStatus: subStatus,
      subscriptionStart: subStart,
      subscriptionExpiry: subExpiry,
      totalSpending: (json['amount_paid'] as num?)?.toDouble() ?? double.tryParse(subs?['total_spending']?.toString() ?? '0') ?? 0,
      featuredPointsPurchased: (json['featured_credits_purchased'] as num?)?.toInt() ?? (subs?['featured_points_purchased'] as num?)?.toInt() ?? 0,
      featuredPointsUsed: (json['featured_credits_used'] as num?)?.toInt() ?? (subs?['featured_points_used'] as num?)?.toInt() ?? 0,
      pendingFeaturedTokens: (subs?['pending_featured_tokens'] as num?)?.toInt() ?? 0,
      featuredSchedule: boosts,
      activationCode: subs?['activation_code'] as String?,
      deletedFrom: json['deleted_from'] as String?,
      deletionReason: json['deletion_reason'] as String?,
      adminNotes: json['admin_notes'] as String?,
      registrationAllowed: json['registration_allowed'] as bool? ?? false,
      discarded: json['discarded'] as String?,
      suggestedInfo: json['suggested_info'] as String?,
      profilePhoto: profilePhoto, cnicFront: cnicFront, cnicBack: cnicBack,
      guardianCnicFront: json['guardian_cnic_front_url'] as String?,
      guardianCnicBack: json['guardian_cnic_back_url'] as String?,
      educationDocument: json['education_document_url'] as String?,
      appliedCouponCode: json['applied_coupon_code'] as String?,
      submissionSource: json['submission_source'] as String?,
    );
  }

  Map<String, dynamic> toUpdateJson() => {
    'name': name, 'age': age, 'gender': gender, 'city': city, 'caste': caste,
    'sect': sect, 'languages': languages, 'education': education,
    'institute': institute, 'degree_title': degreeTitle, 'degree_certificate_url': degreeCertificateUrl,
    'institute_2': institute2, 'degree_title_2': degreeTitle2, 'degree_certificate_2_url': degreeCertificate2Url,
    'institute_3': institute3, 'degree_title_3': degreeTitle3, 'degree_certificate_3_url': degreeCertificate3Url,
    'profession': profession, if (professionCategory != null) 'profession_category': professionCategory, 'employment_type': employmentType,
    'salary_start': salaryStart, 'salary_end': salaryEnd,
    'height_inches': heightInches, 'weight_kg': weightKg,
    'complexion': complexion, 'marital_status': maritalStatus, 'open_to_polygamy': openToPolygamy,
    'marriage_number': marriageNumber,
    'boys': boys, 'girls': girls, 'practice_level': practiceLevel,
    'hijab': hijab, 'beard': beard, 'family_type': familyType,
    'father_alive': fatherAlive, 'mother_alive': motherAlive,
    'father_occupation': fatherOccupation, 'mother_occupation': motherOccupation,
    'sisters': sisters, 'brothers': brothers, 'home_type': homeType,
    'house_size': houseSize, 'location': location, 'country': country, 'disability_details': disabilityDetails,
      'has_car': hasCar,
      'has_other_property': hasOtherProperty,
      'other_property': otherProperty, 'car_name': carName,
    'has_generator': hasGenerator, 'has_solar': hasSolar, 'has_servant': hasServant,
    'physically_active': physicallyActive, 'smokes': smokes, 'drinks': drinks,
    'has_kids': hasKids, 'has_siblings': hasSiblings,
    'has_disability': hasDisability == null ? null : hasDisability == 'Yes',
    'looking_for': lookingFor, 'about': about, 'contact_phone': contactPhone,
    'monthly_income': monthlyIncome,
    if (contactPhone2 != null) 'contact_phone_2': contactPhone2,
    if (contactPhone2 == null || contactPhone2!.isEmpty) 'contact_phone_2': null,
    'phone_verified': phoneVerified, 'email_verified': emailVerified,
    'cnic_verified': cnicVerified, 'cnic': cnic, 'password': password, 'admin_notes': adminNotes, 'registration_allowed': registrationAllowed,
    'profile_photo_url': profilePhoto,
    'cnic_front_url': cnicFront,
    'cnic_back_url': cnicBack,
    'guardian_cnic_front_url': guardianCnicFront,
    'guardian_cnic_back_url': guardianCnicBack,
    'education_document_url': educationDocument,
    'status': status.name, 'subscription_tier': subscriptionTier.name,
  };

  bool get isSubscriptionExpired {
    if (subscriptionExpiry == null) return false;
    return DateTime.now().isAfter(subscriptionExpiry!);
  }

  String get subscriptionDaysLeft {
    if (subscriptionExpiry == null) return '—';
    final diff = subscriptionExpiry!.difference(DateTime.now()).inDays;
    if (diff < 0) return 'Expired';
    return '$diff days';
  }

  String get heightLabel {
    final totalInches = heightInches.round();
    final ft = totalInches ~/ 12;
    final inch = totalInches % 12;
    return '$ft\'$inch"';
  }

  AdminUser copyWith({
    ProposalStatus? status, SubscriptionTier? subscriptionTier, SubscriptionStatus? subscriptionStatus,
    DateTime? subscriptionStart, DateTime? subscriptionExpiry, double? totalSpending,
    int? featuredPointsPurchased, int? featuredPointsUsed, List<FeaturedBoost>? featuredSchedule,
    String? activationCode, String? name, int? age, String? gender, String? city, String? caste,
    String? sect, List<String>? languages, String? education, String? institute, String? degreeTitle, String? degreeCertificateUrl,
    String? institute2, String? degreeTitle2, String? degreeCertificate2Url, String? institute3, String? degreeTitle3, String? degreeCertificate3Url,
    String? profession, String? professionCategory, Object? employmentType = _unset,
    double? salaryStart, double? salaryEnd, double? heightInches, double? weightKg, Object? complexion = _unset,
    String? maritalStatus, Object? openToPolygamy = _unset, String? marriageNumber, int? boys, int? girls, Object? practiceLevel = _unset, Object? hijab = _unset, Object? beard = _unset, Object? familyType = _unset,
    Object? fatherAlive = _unset, Object? motherAlive = _unset, Object? fatherOccupation = _unset,
    Object? motherOccupation = _unset, int? sisters, int? brothers, Object? homeType = _unset, Object? houseSize = _unset,
    Object? hasCar = _unset, Object? hasOtherProperty = _unset, Object? otherProperty = _unset, Object? carName = _unset, Object? location = _unset, Object? country = _unset, bool? hasGenerator, bool? hasSolar, bool? hasServant,
    Object? lookingFor = _unset, Object? about = _unset, String? contactPhone, String? contactPhone2, bool? phoneVerified,
    bool? emailVerified, bool? cnicVerified, Object? cnic = _unset, Object? smokes = _unset, bool? drinks,
    Object? monthlyIncome = _unset, Object? hasDisability = _unset, Object? physicallyActive = _unset, String? disabilityDetails,
    bool? hasKids, Object? hasSiblings = _unset,
    int? pendingFeaturedTokens, String? deletedFrom, Object? deletionReason = _unset, String? adminNotes, bool? registrationAllowed,
    String? profilePhoto, Object? cnicFront = _unset, Object? cnicBack = _unset, String? password,
    Object? guardianCnicFront = _unset, Object? guardianCnicBack = _unset, Object? educationDocument = _unset,
    String? appliedCouponCode, String? submissionSource,
  }) => AdminUser(
    id: id, name: name ?? this.name, age: age ?? this.age, gender: gender ?? this.gender,
    city: city ?? this.city,
    caste: caste ?? this.caste, sect: sect ?? this.sect, languages: languages ?? this.languages,
    education: education ?? this.education, institute: institute ?? this.institute,
    degreeTitle: degreeTitle ?? this.degreeTitle,
    degreeCertificateUrl: degreeCertificateUrl ?? this.degreeCertificateUrl,
    institute2: institute2 ?? this.institute2, degreeTitle2: degreeTitle2 ?? this.degreeTitle2,
    degreeCertificate2Url: degreeCertificate2Url ?? this.degreeCertificate2Url,
    institute3: institute3 ?? this.institute3, degreeTitle3: degreeTitle3 ?? this.degreeTitle3,
    degreeCertificate3Url: degreeCertificate3Url ?? this.degreeCertificate3Url,
    proposalNumber: proposalNumber ?? this.proposalNumber,
    profession: profession ?? this.profession, professionCategory: professionCategory ?? this.professionCategory, employmentType: employmentType is _Unset ? this.employmentType : employmentType as String?,
    salaryStart: salaryStart ?? this.salaryStart, salaryEnd: salaryEnd ?? this.salaryEnd,
    heightInches: heightInches ?? this.heightInches, weightKg: weightKg ?? this.weightKg,
    complexion: complexion is _Unset ? this.complexion : complexion as String?, maritalStatus: maritalStatus ?? this.maritalStatus,
    openToPolygamy: openToPolygamy is _Unset ? this.openToPolygamy : openToPolygamy as String?,
    boys: boys ?? this.boys, girls: girls ?? this.girls,
    practiceLevel: practiceLevel is _Unset ? this.practiceLevel : practiceLevel as String?, hijab: hijab is _Unset ? this.hijab : hijab as String?,
    beard: beard is _Unset ? this.beard : beard as String?,
    familyType: familyType is _Unset ? this.familyType : familyType as String?,
    fatherAlive: fatherAlive is _Unset ? this.fatherAlive : fatherAlive as bool?, motherAlive: motherAlive is _Unset ? this.motherAlive : motherAlive as bool?,
    fatherOccupation: fatherOccupation is _Unset ? this.fatherOccupation : fatherOccupation as String?,
    motherOccupation: motherOccupation is _Unset ? this.motherOccupation : motherOccupation as String?,
    sisters: sisters ?? this.sisters, brothers: brothers ?? this.brothers,
    homeType: homeType is _Unset ? this.homeType : homeType as String?, houseSize: houseSize is _Unset ? this.houseSize : houseSize as String?,
    hasCar: hasCar is _Unset ? this.hasCar : hasCar as String?, hasOtherProperty: hasOtherProperty is _Unset ? this.hasOtherProperty : hasOtherProperty as String?, otherProperty: otherProperty is _Unset ? this.otherProperty : otherProperty as String?, carName: carName is _Unset ? this.carName : carName as String?,
    location: location is _Unset ? this.location : location as String?,
    country: country is _Unset ? this.country : country as String?,
    hasGenerator: hasGenerator ?? this.hasGenerator, hasSolar: hasSolar ?? this.hasSolar,
    hasServant: hasServant ?? this.hasServant, lookingFor: lookingFor is _Unset ? this.lookingFor : lookingFor as String?,
    about: about is _Unset ? this.about : about as String?, contactPhone: contactPhone ?? this.contactPhone, contactPhone2: contactPhone2 ?? this.contactPhone2,
    phoneVerified: phoneVerified ?? this.phoneVerified, emailVerified: emailVerified ?? this.emailVerified,
    cnicVerified: cnicVerified ?? this.cnicVerified, cnic: cnic is _Unset ? this.cnic : cnic as String?, password: password ?? this.password,
    smokes: smokes is _Unset ? this.smokes : smokes as bool?, drinks: drinks ?? this.drinks,
    monthlyIncome: monthlyIncome is _Unset ? this.monthlyIncome : monthlyIncome as String?, hasDisability: hasDisability is _Unset ? this.hasDisability : hasDisability as String?,
    physicallyActive: physicallyActive is _Unset ? this.physicallyActive : physicallyActive as String?,
    disabilityDetails: disabilityDetails ?? this.disabilityDetails,
    hasKids: hasKids ?? this.hasKids, hasSiblings: hasSiblings is _Unset ? this.hasSiblings : hasSiblings as bool?, postedAt: postedAt,
    status: status ?? this.status, subscriptionTier: subscriptionTier ?? this.subscriptionTier,
    subscriptionStatus: subscriptionStatus ?? this.subscriptionStatus,
    subscriptionStart: subscriptionStart ?? this.subscriptionStart,
    subscriptionExpiry: subscriptionExpiry ?? this.subscriptionExpiry,
    totalSpending: totalSpending ?? this.totalSpending,
    featuredPointsPurchased: featuredPointsPurchased ?? this.featuredPointsPurchased,
    featuredPointsUsed: featuredPointsUsed ?? this.featuredPointsUsed,
    featuredSchedule: featuredSchedule ?? this.featuredSchedule,
    activationCode: activationCode ?? this.activationCode,
    pendingFeaturedTokens: pendingFeaturedTokens ?? this.pendingFeaturedTokens,
    deletedFrom: deletedFrom ?? this.deletedFrom, deletionReason: deletionReason is _Unset ? this.deletionReason : deletionReason as String?, adminNotes: adminNotes ?? this.adminNotes, registrationAllowed: registrationAllowed ?? this.registrationAllowed, discarded: discarded ?? this.discarded, suggestedInfo: suggestedInfo ?? this.suggestedInfo,
    profilePhoto: profilePhoto ?? this.profilePhoto,
    cnicFront: cnicFront is _Unset ? this.cnicFront : cnicFront as String?,
    cnicBack: cnicBack is _Unset ? this.cnicBack : cnicBack as String?,
    guardianCnicFront: guardianCnicFront is _Unset ? this.guardianCnicFront : guardianCnicFront as String?,
    guardianCnicBack: guardianCnicBack is _Unset ? this.guardianCnicBack : guardianCnicBack as String?,
    educationDocument: educationDocument is _Unset ? this.educationDocument : educationDocument as String?,
    appliedCouponCode: appliedCouponCode ?? this.appliedCouponCode,
    submissionSource: submissionSource ?? this.submissionSource,
  );
}

// ── Mock data (kept so old AdminService still compiles) ───────────────────────
List<AdminUser> getMockAdminUsers() {
  final now = DateTime.now();
  return [
    // Active — basic
    AdminUser(id: 'u1', name: 'Fatima Rehman Siddiqui', age: 26, gender: 'Female', city: 'Lahore', caste: 'Syed', sect: 'Sunni', education: "Master's", profession: 'Teacher', heightInches: 63, maritalStatus: 'Never Married', contactPhone: '03001234567', postedAt: now.subtract(const Duration(days: 45)), status: ProposalStatus.active, subscriptionTier: SubscriptionTier.basic, subscriptionStatus: SubscriptionStatus.active, subscriptionStart: now.subtract(const Duration(days: 45)), subscriptionExpiry: now.add(const Duration(days: 45)), totalSpending: 1000, featuredSchedule: []),
    // Active — featured
    AdminUser(id: 'u2', name: 'Ahmad Khan Yousafzai', age: 30, gender: 'Male', city: 'Karachi', caste: 'Yousafzai', sect: 'Deobandi', education: "Bachelor's", profession: 'Software Engineer', heightInches: 70, maritalStatus: 'Never Married', contactPhone: '03211234567', postedAt: now.subtract(const Duration(days: 60)), status: ProposalStatus.active, subscriptionTier: SubscriptionTier.featured, subscriptionStatus: SubscriptionStatus.active, subscriptionStart: now.subtract(const Duration(days: 60)), subscriptionExpiry: now.add(const Duration(days: 30)), totalSpending: 4000, featuredPointsPurchased: 6, featuredPointsUsed: 3, featuredSchedule: []),
    // Expired
    AdminUser(id: 'u3', name: 'Zainab Malik Butt', age: 24, gender: 'Female', city: 'Islamabad', caste: 'Butt', sect: 'Barelvi', education: "Bachelor's", profession: 'Accountant', heightInches: 61, maritalStatus: 'Never Married', contactPhone: '03451234567', postedAt: now.subtract(const Duration(days: 120)), status: ProposalStatus.active, subscriptionTier: SubscriptionTier.basic, subscriptionStatus: SubscriptionStatus.expired, subscriptionStart: now.subtract(const Duration(days: 120)), subscriptionExpiry: now.subtract(const Duration(days: 30)), totalSpending: 1000, featuredSchedule: []),
    // Paused
    AdminUser(id: 'u4', name: 'Hassan Raza Chaudhry', age: 32, gender: 'Male', city: 'Faisalabad', caste: 'Chaudhry', sect: 'Sunni', education: 'Matric', profession: 'Businessman', heightInches: 68, maritalStatus: 'Never Married', contactPhone: '03001239999', postedAt: now.subtract(const Duration(days: 20)), status: ProposalStatus.paused, subscriptionTier: SubscriptionTier.basic, subscriptionStatus: SubscriptionStatus.active, subscriptionStart: now.subtract(const Duration(days: 20)), subscriptionExpiry: now.add(const Duration(days: 70)), totalSpending: 1000, featuredSchedule: []),
    // Active — expiring soon
    AdminUser(id: 'u5', name: 'Ayesha Noor Qureshi', age: 28, gender: 'Female', city: 'Rawalpindi', caste: 'Qureshi', sect: 'Barelvi', education: 'MBBS', profession: 'Doctor', heightInches: 64, maritalStatus: 'Divorced', contactPhone: '03331234567', postedAt: now.subtract(const Duration(days: 85)), status: ProposalStatus.active, subscriptionTier: SubscriptionTier.basic, subscriptionStatus: SubscriptionStatus.active, subscriptionStart: now.subtract(const Duration(days: 85)), subscriptionExpiry: now.add(const Duration(days: 5)), totalSpending: 1000, featuredSchedule: []),
    // Active — recently joined
    AdminUser(id: 'u6', name: 'Usman Tariq Ansari', age: 27, gender: 'Male', city: 'Lahore', caste: 'Ansari', sect: 'Ahl-e-Hadith', education: "Bachelor's", profession: 'Freelancer', heightInches: 71, maritalStatus: 'Never Married', contactPhone: '03121234567', postedAt: now.subtract(const Duration(days: 2)), status: ProposalStatus.active, subscriptionTier: SubscriptionTier.basic, subscriptionStatus: SubscriptionStatus.active, subscriptionStart: now.subtract(const Duration(days: 2)), subscriptionExpiry: now.add(const Duration(days: 88)), totalSpending: 1000, featuredSchedule: []),
    AdminUser(id: 'u7', name: 'Test1234', age: 25, gender: 'Male', city: 'Lahore', caste: 'Sheikh', sect: 'Sunni', education: "Bachelor's", profession: 'Student', heightInches: 68, maritalStatus: 'Never Married', contactPhone: '77777-7777777-7', cnic: '77777-7777777-7', postedAt: now.subtract(const Duration(days: 100)), status: ProposalStatus.active, subscriptionTier: SubscriptionTier.basic, subscriptionStatus: SubscriptionStatus.expired, subscriptionStart: now.subtract(const Duration(days: 100)), subscriptionExpiry: now.subtract(const Duration(days: 10)), totalSpending: 1000, featuredSchedule: []),
  ];
}

List<ActivationCode> getMockCodes() {
  final now = DateTime.now();
  return [
    ActivationCode(code: 'FEAT-A2B3C4', tier: SubscriptionTier.featured, price: 2000, isUsed: true, usedByUserId: 'u1', createdAt: now.subtract(const Duration(days: 50)), usedAt: now.subtract(const Duration(days: 45))),
    ActivationCode(code: 'BASC-D5E6F7', tier: SubscriptionTier.basic, price: 1000, isUsed: true, usedByUserId: 'u2', createdAt: now.subtract(const Duration(days: 65)), usedAt: now.subtract(const Duration(days: 60))),
    ActivationCode(code: 'FEAT-P7Q8R9', tier: SubscriptionTier.featured, price: 2000, isUsed: false, createdAt: now.subtract(const Duration(days: 2))),
    ActivationCode(code: 'BASC-S0T1U2', tier: SubscriptionTier.basic, price: 1000, isUsed: false, createdAt: now.subtract(const Duration(days: 1))),
  ];
}
