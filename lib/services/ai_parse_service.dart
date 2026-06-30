// lib/services/ai_parse_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// Get your key from: https://console.anthropic.com
const _kClaudeKey = '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';

class ParsedProposal {
  final String? name;
  final String? age;
  final String? phone;
  final String? phone2;
  final String? gender;
  final String? city;
  final String? caste;
  final String? sect;
  final String? education;
  final String? degreeTitle;
  final String? institute;
  final String? profession;
  final String? employmentType;
  final String? monthlyIncome;
  final String? height;
  final String? weight;
  final String? complexion;
  final String? maritalStatus;
  final String? fatherAlive;
  final String? fatherOccupation;
  final String? motherAlive;
  final String? motherOccupation;
  final String? brothers;
  final String? sisters;
  final String? homeType;
  final String? houseSize;
  final String? hasCar;
  final String? carName;
  final String? practiceLevel;
  final String? hijab;
  final String? beard;
  final String? about;
  final String? lookingFor;
  final String? country;
  final String? location;
  final String? siblings;
  final String? totalKids;
  final String? kidsBoys;
  final String? kidsGirls;
  final String? disability;
  final String? discarded;
  final String? suggestedInfo; // NEW: paragraph-form extra info

  const ParsedProposal({
    this.name, this.age, this.phone, this.phone2, this.gender, this.city,
    this.caste, this.sect, this.education, this.degreeTitle,
    this.institute, this.profession, this.employmentType,
    this.monthlyIncome, this.height, this.weight, this.complexion,
    this.maritalStatus, this.fatherAlive, this.fatherOccupation,
    this.motherAlive, this.motherOccupation, this.brothers,
    this.sisters, this.homeType, this.houseSize, this.hasCar,
    this.carName, this.practiceLevel, this.hijab, this.beard,
    this.about, this.lookingFor, this.country, this.location,
    this.siblings, this.totalKids, this.kidsBoys, this.kidsGirls,
    this.disability, this.discarded, this.suggestedInfo,
  });

  factory ParsedProposal.fromJson(Map<String, dynamic> j) => ParsedProposal(
    name: j['name'], age: j['age']?.toString(), phone: j['phone'], phone2: j['phone_2'],
    gender: j['gender'], city: j['city'], caste: j['caste'],
    sect: j['sect'], education: j['education'], degreeTitle: j['degree_title'],
    institute: j['institute'], profession: j['profession'],
    employmentType: j['employment_type'], monthlyIncome: j['monthly_income'],
    height: j['height'], weight: j['weight']?.toString(),
    complexion: j['complexion'], maritalStatus: j['marital_status'],
    fatherAlive: j['father_alive'], fatherOccupation: j['father_occupation'],
    motherAlive: j['mother_alive'], motherOccupation: j['mother_occupation'],
    brothers: j['brothers']?.toString(), sisters: j['sisters']?.toString(),
    homeType: j['home_type'], houseSize: j['house_size'],
    hasCar: j['has_car'], carName: j['car_name'],
    practiceLevel: j['practice_level'], hijab: j['hijab'], beard: j['beard'],
    about: j['about'], lookingFor: j['looking_for'],
    country: j['country'], location: j['location'],
    siblings: j['siblings']?.toString(),
    totalKids: j['total_kids']?.toString(),
    kidsBoys: j['kids_boys']?.toString(),
    kidsGirls: j['kids_girls']?.toString(),
    disability: j['has_disability'] == null ? null : (j['has_disability'].toString().toLowerCase() == 'true' || j['has_disability'].toString().toLowerCase() == 'yes') ? 'Yes' : 'No',
    discarded: j['discarded'],
    suggestedInfo: j['suggested_info'],
  );
}

Future<ParsedProposal> parseWhatsAppProposal({
  required String message,
  File? photoFile,
}) async {
  const systemPrompt = '''
You are a data extraction assistant for a Pakistani Rishta (marriage proposal) app.
Extract fields from the WhatsApp message and return ONLY valid JSON, nothing else.

Fields to extract:
- name: full name, properly capitalized e.g. "Ahmed Ali". If not mentioned or replaced with placeholder like "xyz", "unknown", "abc", "xxx", "N/A", "name not given" — set to "User"
- age: number as string. If only date of birth given (e.g. 08/1999 or dd/mm/yyyy) calculate approximate age from 2026. Do NOT include dob in suggested_info — it is internal only.
- phone: first/primary phone number if mentioned
- phone_2: second or alternate phone number if mentioned
- gender: exactly "male" or "female" (lowercase)
- city: pick CLOSEST match, fix spelling mistakes. Options:
  Lahore, Faisalabad, Rawalpindi, Multan, Gujranwala, Sialkot, Bahawalpur, Sargodha,
  Karachi, Hyderabad, Sukkur, Larkana, Peshawar, Mardan, Abbottabad, Quetta, Gwadar,
  Islamabad, Gilgit, Skardu, Muzaffarabad, Mirpur, Other
- caste: pick CLOSEST match, fix spelling mistakes (rajpoot=Rajput, jatt=Jatt, syyed=Syed, shiekh=Sheikh, pathaan=Pathan, arrain=Arain, gujjar=Gujjar, qureshi=Qureshi). Options:
  Jatt, Rajput, Arain, Gujjar, Sheikh, Syed, Mughal, Malik, Awan, Bhatti, Khokhar,
  Dogar, Kamboh, Ansari, Qureshi, Butt, Dar, Chaudhry, Raja, Siddiqui, Memon, Other
- sect: pick CLOSEST match. Ahle Sunnat/Ahle-Sunnat/Ahl-e-Sunnat/Sunni/Barelvi all = "Sunni". Options: Sunni, Shia, Barelvi, Deobandi, Ahl-e-Hadith, Other
- education: pick CLOSEST match (ba/bsc=Bachelor's, ma/msc=Master's, inter/fsc/fa=FSc/FA, phd=PhD).
  MBBS, BDS, DPT, PharmD = Bachelor's unless masters or specialization mentioned.
  Any engineering degree (software engineering, civil engineering etc.) = Bachelor's unless masters mentioned.
  Options: Matric, FSc/FA, Diploma, Bachelor's, Master's, MPhil, PhD, Other
- degree_title: the actual degree name, properly capitalized. ALWAYS start with the level prefix: "Bachelor's in ...", "Master's in ...", "PhD in ...", "Diploma in ...". Named medical/professional degrees are exceptions: MBBS, BDS, DPT, PharmD, LLB, CA, ACCA use those titles directly. NEVER use vague words like "Graduate", "Graduate Degree", "Degree", "Certification" as a degree title — if unsure of field, write "Bachelor's" or "Master's" only. For O/A levels write "O Levels / A Levels".
- institute: most recent / last attended institute, properly capitalized e.g. "Punjab University", "LUMS". Return null if not mentioned — NEVER write "Not mentioned", "N/A", "Unknown", or any placeholder.
- profession: properly capitalized e.g. "Software Engineer", "Doctor", "Teacher"
- employment_type: pick CLOSEST (private job/company job/naukri=Full-time, khud ka kaam/business=Self-employed). Options: Full-time, Part-time, Self-employed, Freelance, Not employed. NEVER output 'Private' — map it to Full-time.
- monthly_income: pick CLOSEST. Options: Under 30K, 30K – 60K, 60K – 100K, 100K – 200K, 200K – 500K, 500K+
- height: convert to feet format e.g. "5'6"" — 5.5=5'6", 5.3=5'3"
- weight: kg as number
- complexion: pick CLOSEST (gora/goori/fair=Fair, wheatish/geehwaan=Wheatish, sanwla/brown=Brown, dark/kala=Dark). IMPORTANT: this field MUST use one of these exact dropdown values: Fair, Wheatish, Brown, Dark. Never put complexion in about field.
- marital_status: pick CLOSEST. Options: Never married, Married, Divorced, Khula, Widowed
- father_alive: "yes" or "no" — deceased/expired/died/late/intiqal = "no"
- father_occupation: key occupation only, properly capitalized. If long details given (e.g. "retired army officer who also has a shop and does farming") extract only the primary occupation (e.g. "Retired Army Officer"). Max ~4 words.
- mother_alive: "yes" or "no"
- mother_occupation: key occupation only, properly capitalized e.g. "House Wife". Max ~4 words. If long details given extract only primary role.
SIBLING COUNTING — THIS IS CRITICAL. Before filling brothers/sisters fields, scan the ENTIRE text and count:
  Step 1: Count every male sibling (bhai, brother, Brother 1, Brother 2, "one brother", "do bhai", etc.)
  Step 2: Count every female sibling (behen, sister, Sister 1, "one sister", "teen behnain", etc.)
  Step 3: Fill brothers = total male siblings counted, sisters = total female siblings counted
  
  Examples:
  "One brother is HR Executive, One brother is Manager" → brothers: "2"
  "One sister MA, One sister Double Masters, One sister BS" → sisters: "3"
  "Has 5 siblings: 3 sisters, 2 brothers" → brothers: "2", sisters: "3"
  "do bhai aur teen behnain" → brothers: "2", sisters: "3"
  "Brother 1 lawyer, Brother 2 engineer, Sister 1 doctor" → brothers: "2", sisters: "1"
  NEVER leave brothers/sisters null if siblings are described anywhere in the text.

- brothers: result of sibling count step above (string number)
- sisters: result of sibling count step above (string number)
- siblings: ONLY set if ONLY a total is given without any breakdown (e.g. "3 bhai bahen", "5 siblings total"). Leave null if individual brothers/sisters are described.
- total_kids: ONLY set if total kids mentioned without specifying boys/girls (e.g. "2 kids", "1 child", "bachay 3"). Leave null if boys/girls specified.
- kids_boys: number of boys/sons if specifically mentioned
- kids_girls: number of girls/daughters if specifically mentioned
- home_type: pick CLOSEST (apna/khud ka/own=Own House, kiraye/rented=Rented House). If person describes their house (e.g. "triple story house", "kothi", "5 marla house") without saying it is rented, assume Own House. Options: Own House, Rented House
- house_size: standardized e.g. "5 Marla", "10 Marla", "1 Kanal"
- has_car: ONLY use: Yes, No, Multiple. Say "Yes" if they mention having a car by name or say "we have a car". Say "No" only if they explicitly say no car. If not mentioned at all, return null (do NOT default to false or No).
- car_name: properly capitalized e.g. "Honda City", "Toyota Corolla"
- practice_level: pick CLOSEST (high/very religious=High, moderate=Moderate, low/liberal=Low). Options: High, Moderate, Low
- hijab: Yes, No, or Sometimes
- beard: Yes, No, or Light
- about: clean properly capitalized paragraph summarizing the person. Include complexion naturally if relevant. Do NOT use bullet points. Must be a flowing paragraph. NEVER mention missing or unspecified details (e.g. do NOT say 'details not specified', 'not mentioned', 'fourth sister not specified'). Only state what IS known. For looking_for, do NOT start abruptly — blend it naturally as the closing sentence (e.g. 'She is looking for an educated family' not just 'Well educated caring girl').
- looking_for: ALWAYS write as a clean flowing paragraph (never bullet points or dashes). If given as points, convert to natural readable paragraph. Properly capitalized. Never start abruptly with adjectives — use a proper sentence opener like 'Looking for', 'Seeking', 'She/He is looking for'.
- country: properly capitalized, default "Pakistan"
- location: properly capitalized area e.g. "Allama Iqbal Town", "DHA Phase 5"
- has_disability: return the STRING "Yes" or "No" (not boolean). "Yes" if disability mentioned. "No" if says "No Alhumdulillah", "No disability", healthy, fit, or not mentioned at all.
- suggested_info: Write a meaningful paragraph (or two) containing all useful information from the message that did not fit into the structured fields above. NEVER mention missing, unspecified, or unavailable data (e.g. do NOT write 'not provided', 'not specified', 'breakdown not provided', 'details not mentioned', 'no information given'). Only include what IS explicitly stated. Write in the SAME LANGUAGE the user used (if Roman Urdu, write in Roman Urdu; if English, write in English; if mixed, match that mix). This paragraph should naturally cover details like: brother/sister descriptions (age, jobs, education of siblings), father details (age, background, property), mother details, extended family, career/job details beyond job title, contact person name and relationship, best time to contact, any special circumstances, health details, property beyond main home, any additional requirements not in looking_for. Do NOT mention date of birth (already used for age). Do NOT include group admin instructions like "photo mandatory", group names, ID codes (AMB-XXX etc.) — these are admin metadata not part of the proposal. Return null if nothing meaningful remains.
- discarded: set to null — all useful info goes to suggested_info instead.

Rules:
- Always fix spelling mistakes and match to closest correct option
- Always properly capitalize names, places, degrees, professions
- Return null for any field not found
- Discard only: greetings, emojis, forwarded message labels, irrelevant filler text, group admin instructions (photo mandatory for membership, group name, ID: AMB-XXX or similar codes)
- Return ONLY the JSON object, no explanation, no markdown backticks
''';

  final List<Map<String, dynamic>> contentParts = [];

  if (photoFile != null) {
    try {
      final bytes = await photoFile.readAsBytes();
      contentParts.add({
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/jpeg',
          'data': base64Encode(bytes),
        }
      });
    } catch (_) {}
  }

  contentParts.add({
    'type': 'text',
    'text': 'Extract proposal data:\n\n$message',
  });

  final response = await http.post(
    Uri.parse('https://api.anthropic.com/v1/messages'),
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': _kClaudeKey,
      'anthropic-version': '2023-06-01',
    },
    body: jsonEncode({
      'model': 'claude-haiku-4-5',
      'max_tokens': 1500,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': contentParts}
      ],
    }),
  ).timeout(const Duration(seconds: 30), onTimeout: () {
    throw Exception('Timed out. Check your internet and try again.');
  });

  if (response.statusCode != 200) {
    throw Exception('API error ${response.statusCode}: ${response.body}');
  }

  final json = jsonDecode(response.body);
  final raw = json['content'][0]['text'] as String;
  final cleaned = raw.replaceAll('```json', '').replaceAll('```', '').trim();
  return ParsedProposal.fromJson(jsonDecode(cleaned));
}
