import 'package:flutter/material.dart';

enum SubscriptionType { none, basic, boosted }

class RishtaProposal {
  final String id;
  final String name;
  final int age;
  final String gender;
  final String city;
  final String caste;
  final String sect;
  final String education;
  final String? degreeTitle;
  final String? institute;
  final String? degreeTitle2;
  final String? institute2;
  final String? degreeTitle3;
  final String? institute3;
  final String profession;
  final String? employmentType;
  final double? salaryStart;
  final double? salaryEnd;
  final String? monthlyIncome;
  final double heightInches;
  final double? weightKg;
  final String? complexion;
  final String maritalStatus;
  final int? boys;
  final int? girls;
  final String? practiceLevel;
  final String? hijab;
  final String? beard;
  final String? familyType;
  final bool? fatherAlive;
  final String? fatherOccupation;
  final bool? motherAlive;
  final String? motherOccupation;
  final int sisters;
  final int brothers;
  final String? homeType;
  final String? location;
  final String? country;
  final String? disabilityDetails;
  final String? houseSize;
  final String? hasCar;
  final String? hasOtherProperty;
  final String? otherProperty;
  final String? carName;
  final bool? hasGenerator;
  final bool? hasSolar;
  final bool? hasServant;
  final String? lookingFor;
  final int? proposalNumber;
  final String? marriageNumber;
  final String? about;
  final String? suggestedInfo;
  final String contactPhone;
  final String? contactPhone2;
  final bool phoneVerified;
  final bool emailVerified;
  final bool cnicVerified;
  final bool? smokes;
  final bool? drinks;
  final String? physicallyActive;
  final bool? hasDisability;
  final DateTime postedAt;
  final SubscriptionType subscription;
  final bool isBoosted;
  final String? photoUrl;
  final List<String> photoUrls;
  final List<String> languages;

  const RishtaProposal({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.city,
    required this.caste,
    required this.sect,
    required this.education,
    this.degreeTitle,
    this.institute,
    this.degreeTitle2,
    this.institute2,
    this.degreeTitle3,
    this.institute3,
    required this.profession,
    this.employmentType,
    this.salaryStart,
    this.salaryEnd,
    this.monthlyIncome,
    required this.heightInches,
    this.weightKg,
    this.complexion,
    required this.maritalStatus,
    this.boys,
    this.girls,
    this.practiceLevel,
    this.hijab,
    this.beard,
    this.familyType,
    this.fatherAlive,
    this.fatherOccupation,
    this.motherAlive,
    this.motherOccupation,
    this.sisters = 0,
    this.brothers = 0,
    this.homeType,
    this.location,
    this.country,
    this.disabilityDetails,
    this.houseSize,
    this.hasCar,
    this.hasOtherProperty,
    this.otherProperty,
    this.carName,
    this.hasGenerator,
    this.hasSolar,
    this.hasServant,
    this.lookingFor,
    this.proposalNumber,
    this.marriageNumber,
    this.suggestedInfo,
    this.about,
    required this.contactPhone,
    this.contactPhone2,
    this.phoneVerified = false,
    this.emailVerified = false,
    this.cnicVerified = false,
    this.smokes,
    this.drinks,
    this.physicallyActive,
    this.hasDisability,
    required this.postedAt,
    this.subscription = SubscriptionType.none,
    this.isBoosted = false,
    this.photoUrl,
    this.photoUrls = const [],
    this.languages = const [],
  });

  // ── Supabase deserialization ──────────────────────────────────────────────
  factory RishtaProposal.fromJson(Map<String, dynamic> json) {
    // Resolve subscription type
    final tierStr = json['subscription_tier'] as String? ?? 'none';
    final sub = tierStr == 'featured'
        ? SubscriptionType.boosted
        : tierStr == 'basic'
            ? SubscriptionType.basic
            : SubscriptionType.none;

    // Resolve photo URLs from nested proposal_photos list
    final photos = (json['proposal_photos'] as List? ?? []);
    final profilePhoto = photos
        .where((p) => p['photo_type'] == 'profile')
        .map((p) => p['storage_path'] as String)
        .firstOrNull;

    return RishtaProposal(
      id: json['id'] as String,
      name: json['name'] as String,
      age: (json['age'] as num).toInt(),
      gender: json['gender'] as String,
      city: json['city'] as String,
      caste: json['caste'] as String,
      sect: json['sect'] as String,
      education: json['education'] as String,
      degreeTitle: json['degree_title'] as String?,
      institute: json['institute'] as String?,
      degreeTitle2: json['degree_title_2'] as String?,
      institute2: json['institute_2'] as String?,
      degreeTitle3: json['degree_title_3'] as String?,
      institute3: json['institute_3'] as String?,
      profession: json['profession'] as String,
      employmentType: json['employment_type'] as String?,
      salaryStart: (json['salary_start'] as num?)?.toDouble(),
      salaryEnd: (json['salary_end'] as num?)?.toDouble(),
      monthlyIncome: json['monthly_income'] as String?,
      heightInches: (json['height_inches'] as num).toDouble(),
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      complexion: json['complexion'] as String?,
      maritalStatus: json['marital_status'] as String,
      boys: (json['boys'] as num?)?.toInt(),
      girls: (json['girls'] as num?)?.toInt(),
      practiceLevel: json['practice_level'] as String?,
      hijab: json['hijab'] as String?,
      beard: json['beard'] as String?,
      familyType: json['family_type'] as String?,
      fatherAlive: json['father_alive'] as bool?,
      fatherOccupation: json['father_occupation'] as String?,
      motherAlive: json['mother_alive'] as bool?,
      motherOccupation: json['mother_occupation'] as String?,
      sisters: (json['sisters'] as num?)?.toInt() ?? 0,
      brothers: (json['brothers'] as num?)?.toInt() ?? 0,
      homeType: json['home_type'] as String?,
      location: json['location'] as String?,
      country: json['country'] as String?,
      disabilityDetails: json['disability_details'] as String?,
      houseSize: json['house_size'] as String?,
      hasCar: json['has_car'] as String?,
      hasOtherProperty: json['has_other_property'] as String?,
      otherProperty: json['other_property'] as String?,
      carName: json['car_name'] as String?,
      hasGenerator: json['has_generator'] as bool?,
      hasSolar: json['has_solar'] as bool?,
      hasServant: json['has_servant'] as bool?,
      lookingFor: json['looking_for'] as String?,
      proposalNumber: json['proposal_number'] as int?,
      marriageNumber: json['marriage_number'] as String?,
      about: json['about'] as String?,
      suggestedInfo: json['suggested_info'] as String?,
      contactPhone: json['contact_phone'] as String,
      contactPhone2: json['contact_phone_2'] as String?,
      phoneVerified: json['phone_verified'] as bool? ?? false,
      emailVerified: json['email_verified'] as bool? ?? false,
      cnicVerified: json['cnic_verified'] as bool? ?? false,
      smokes: json['smokes'] as bool?,
      drinks: json['drinks'] as bool?,
      physicallyActive: json['physically_active'] as String?,
      hasDisability: json['has_disability'] as bool?,
      postedAt: DateTime.parse(json['posted_at'] as String),
      subscription: sub,
      isBoosted: json['is_boosted'] as bool? ?? false,
      photoUrl: profilePhoto ?? json['profile_photo_url'] as String?,
      photoUrls: photos.map<String>((e) => e['photo_url'] as String? ?? '').where((e) => e.isNotEmpty).toList(),
      languages: (json['languages'] as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
    );
  }

  // ── Supabase serialization (for proposal submission) ──────────────────────
  Map<String, dynamic> toInsertJson() => {
        'name': name,
        'age': age,
        'gender': gender,
        'city': city,
        'caste': caste,
        'sect': sect,
        'languages': languages,
        'education': education,
        'degree_title': degreeTitle,
        'institute': institute,
        'degree_title_2': degreeTitle2,
        'institute_2': institute2,
        'degree_title_3': degreeTitle3,
        'institute_3': institute3,
        'profession': profession,
        'employment_type': employmentType,
        'salary_start': salaryStart,
        'salary_end': salaryEnd,
        'monthly_income': monthlyIncome,
        'height_inches': heightInches,
        'weight_kg': weightKg,
        'complexion': complexion,
        'marital_status': maritalStatus,
        'boys': boys,
        'girls': girls,
        'practice_level': practiceLevel,
        'hijab': hijab,
        'beard': beard,
        'family_type': familyType,
        'father_alive': fatherAlive,
        'father_occupation': fatherOccupation,
        'mother_alive': motherAlive,
        'mother_occupation': motherOccupation,
        'sisters': sisters,
        'brothers': brothers,
        'home_type': homeType,
        'house_size': houseSize,
        'has_car': hasCar,
        'has_other_property': hasOtherProperty,
        'other_property': otherProperty,
        'car_name': carName,
        'has_generator': hasGenerator,
        'has_solar': hasSolar,
        'has_servant': hasServant,
        'looking_for': lookingFor,
      'proposal_number': proposalNumber,
      'marriage_number': marriageNumber,
        'about': about,
        'contact_phone': contactPhone,
        if (contactPhone2 != null && contactPhone2!.isNotEmpty) 'contact_phone_2': contactPhone2,
        'phone_verified': phoneVerified,
        'email_verified': emailVerified,
        'cnic_verified': cnicVerified,
        'smokes': smokes,
        'drinks': drinks,
        'physically_active': physicallyActive,
        'has_disability': hasDisability,
      };

  // ── Computed properties (unchanged from original) ─────────────────────────
  static String _maskPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    String cc = '92';
    String rest = '';
    if (digits.startsWith('92') && digits.length >= 3) {
      rest = digits.substring(2);
    } else if (digits.startsWith('03') && digits.length >= 2) {
      rest = digits.substring(1);
    } else if (raw.trim().startsWith('+')) {
      final match = RegExp(r'^\+(\d{1,4})').firstMatch(raw.trim());
      if (match != null) {
        cc = match.group(1)!;
        rest = digits.substring(cc.length);
      }
    } else {
      rest = digits;
    }
    if (rest.length >= 5) {
      final first = rest.substring(0, 1);
      final last4 = rest.substring(rest.length - 4);
      return '+$cc $first** *** $last4';
    }
    return '+$cc ${'*' * rest.length}';
  }

  static String _formatPK(String raw) {
    String digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('92')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length >= 10) {
      return '+92 ${digits.substring(0, 3)} ${digits.substring(3)}';
    }
    return '+92 $digits';
  }

  String get formattedPhone => _formatPK(contactPhone);
  String? get formattedPhone2 => contactPhone2 != null && contactPhone2!.isNotEmpty ? _formatPK(contactPhone2!) : null;
  String? get maskedPhone2 => contactPhone2 != null && contactPhone2!.isNotEmpty ? _maskPhone(contactPhone2!) : null;

  String get maskedPhone {
    final digits = contactPhone.replaceAll(RegExp(r'[^\d]'), '');
    // Format: +CC X** *** XXXX  (first digit, stars, last 4)
    String cc = '92';
    String rest = '';
    if (digits.startsWith('92') && digits.length >= 3) {
      rest = digits.substring(2);
    } else if (digits.startsWith('03') && digits.length >= 2) {
      rest = digits.substring(1);
    } else if (contactPhone.trim().startsWith('+')) {
      final match = RegExp(r'^\+(\d{1,4})').firstMatch(contactPhone.trim());
      if (match != null) {
        cc = match.group(1)!;
        rest = digits.substring(cc.length);
      }
    } else {
      rest = digits;
    }
    if (rest.length >= 5) {
      final first = rest.substring(0, 1);
      final last4 = rest.substring(rest.length - 4);
      final midStars = '*' * (rest.length - 5);
      return '+$cc $first** *** $last4';
    }
    return '+$cc ${'*' * rest.length}';
  }
  String get heightLabel {
    final totalInches = heightInches.round();
    final ft = totalInches ~/ 12;
    final inch = totalInches % 12;
    return '$ft\'$inch"';
  }

  String get timeAgo {
    final local = postedAt.isUtc ? postedAt.toLocal() : postedAt;
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  String get salaryLabel {
    if (monthlyIncome != null && monthlyIncome!.isNotEmpty) return monthlyIncome!;
    if (salaryStart == null) return 'Not disclosed';
    final s = salaryStart!.toInt();
    final e = salaryEnd?.toInt();
    if (e == null || e == s) return 'Rs. ${s}K/mo';
    return 'Rs. ${s}K – ${e}K/mo';
  }
}

// ── FilterState (unchanged) ───────────────────────────────────────────────────
class FilterState {
  final RangeValues ageRange;
  final RangeValues heightRange;
  final String? gender;
  final List<String> cities;
  final List<String> castes;
  final List<String> sects;
  final List<String> professions;
  final List<String> maritalStatuses;
  final List<String> educations;
  final List<String> monthlyIncomes;
  final List<String> houses;
  final String? religion;
  final bool? cnicVerified;
  final bool? familyInvolvement;
  final String? lookingFor;
  final String? locationFilter; // 'local', 'overseas', or null (both)

  const FilterState({
    this.ageRange = const RangeValues(18, 100),
    this.heightRange = const RangeValues(48, 96),
    this.gender,
    this.cities = const [],
    this.castes = const [],
    this.sects = const [],
    this.professions = const [],
    this.maritalStatuses = const [],
    this.educations = const [],
    this.monthlyIncomes = const [],
    this.houses = const [],
    this.religion,
    this.cnicVerified,
    this.familyInvolvement,
    this.lookingFor,
    this.locationFilter,
  });

  int get activeCount {
    int c = 0;
    if (ageRange.start != 18 || ageRange.end != 100) c++;
    if (heightRange.start != 48 || heightRange.end != 96) c++;
    if (gender != null) c++;
    if (cities.isNotEmpty) c++;
    if (castes.isNotEmpty) c++;
    if (sects.isNotEmpty) c++;
    if (professions.isNotEmpty) c++;
    if (educations.isNotEmpty) c++;
    if (maritalStatuses.isNotEmpty) c++;
    if (monthlyIncomes.isNotEmpty) c++;
    if (houses.isNotEmpty) c++;
    if (religion != null) c++;
    if (cnicVerified != null) c++;
    if (familyInvolvement != null) c++;
    if (lookingFor != null) c++;
    if (locationFilter != null) c++;
    return c;
  }

  FilterState copyWith({
    RangeValues? ageRange,
    RangeValues? heightRange,
    String? Function()? gender,
    List<String>? cities,
    List<String>? castes,
    List<String>? sects,
    List<String>? professions,
    List<String>? maritalStatuses,
    List<String>? educations,
    List<String>? monthlyIncomes,
    List<String>? houses,
    String? Function()? religion,
    bool? Function()? cnicVerified,
    bool? Function()? familyInvolvement,
    String? Function()? lookingFor,
    String? Function()? locationFilter,
  }) {
    return FilterState(
      ageRange: ageRange ?? this.ageRange,
      heightRange: heightRange ?? this.heightRange,
      gender: gender != null ? gender() : this.gender,
      cities: cities ?? this.cities,
      castes: castes ?? this.castes,
      sects: sects ?? this.sects,
      professions: professions ?? this.professions,
      maritalStatuses: maritalStatuses ?? this.maritalStatuses,
      educations: educations ?? this.educations,
      monthlyIncomes: monthlyIncomes ?? this.monthlyIncomes,
      houses: houses ?? this.houses,
      religion: religion != null ? religion() : this.religion,
      cnicVerified: cnicVerified != null ? cnicVerified() : this.cnicVerified,
      familyInvolvement:
          familyInvolvement != null ? familyInvolvement() : this.familyInvolvement,
      lookingFor: lookingFor != null ? lookingFor() : this.lookingFor,
      locationFilter: locationFilter != null ? locationFilter() : this.locationFilter,
    );
  }

  FilterState reset() => const FilterState();
}