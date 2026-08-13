import 'dart:typed_data';
// lib/screens/admin/admin_whatsapp_import_screen.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../services/ai_parse_service.dart';
import '../widgets/photo_crop_dialog.dart';
import '../services/admin_service.dart';
import '../utils/theme.dart';
import '../services/supabase_service.dart';
import '../widgets/country_picker.dart' show CountryCode;

// Claude API key — same as ai_parse_service.dart
const _kClaudeKey = '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';

const _kBg   = Color(0xFF16132A);
const _kCard = Color(0xFF1E1A33);
const _kBdr  = Color(0xFF2D2847);

const _kGenders    = ['Male', 'Female'];
const _kMarital    = ['Never married', 'Married', 'Divorced', 'Khula', 'Widowed'];
const _kSects      = ['Sunni', 'Shia', 'Barelvi', 'Deobandi', 'Ahl-e-Hadith', 'Other'];
const _kLanguages  = ['Urdu', 'Punjabi', 'Pashto', 'Sindhi', 'Saraiki', 'Balochi', 'English'];
const _kEducations = ['Matric', 'FSc/FA', 'Diploma', 'Bachelor\'s', 'Master\'s', 'MPhil', 'PhD', 'Other'];
const _kIncomes    = ['Under 30K', '30K – 60K', '60K – 100K', '100K – 200K', '200K – 500K', '500K+'];
const _kComplexion = ['Fair', 'Wheatish', 'Brown', 'Dark'];
const _kPractice   = ['High', 'Moderate', 'Low'];
const _kHijab      = ['Yes', 'No', 'Sometimes'];
const _kBeard      = ['Yes', 'No', 'Light'];
const _kHomeType   = ['Own House', 'Rented House'];
const _kHasCar     = ['Yes', 'No', 'Multiple'];
const _kParent     = ['Alive', 'Deceased'];
const _kEmpType    = ['Full-time', 'Part-time', 'Self-employed', 'Freelance', 'Not employed'];
const _kDisability = ['Yes', 'No'];
const _kLifestyle  = ['Active Living', 'Sedentary Living', 'Moderately Active'];
const _kSmoker     = ['Yes', 'No'];
const _kOtherProp  = ['Residential', 'Commercial', 'Land', 'Multiple'];

class AdminWhatsAppImportScreen extends StatefulWidget {
  final AdminService svc;
  const AdminWhatsAppImportScreen({super.key, required this.svc});
  @override
  State<AdminWhatsAppImportScreen> createState() => _State();
}

class _State extends State<AdminWhatsAppImportScreen> {
  int _step = 0;
  final _msgCtrl = TextEditingController();
  String? _errorMsg;
  bool _saving = false;
  bool _scanning = false;
  String? _discarded;
  bool _scanMode = false;
  String _inputMode = 'paste';

  // Photos
  Uint8List? _profilePhoto;

  // Text controllers
  final _nameCtrl        = TextEditingController();
  final _ageCtrl         = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _phone2Ctrl      = TextEditingController();
  final _heightCtrl      = TextEditingController();
  final _weightCtrl      = TextEditingController();
  final _profCtrl        = TextEditingController();
  final _instCtrl        = TextEditingController();
  final _degreeTitleCtrl = TextEditingController();
  final _brothersCtrl    = TextEditingController();
  final _sistersCtrl     = TextEditingController();
  final _siblingsCtrl    = TextEditingController();
  final _totalKidsCtrl   = TextEditingController();
  final _kidsBoyCtrl     = TextEditingController();
  final _kidsGirlCtrl    = TextEditingController();
  final _fatherOccCtrl   = TextEditingController();
  final _motherOccCtrl   = TextEditingController();
  final _houseSizeCtrl   = TextEditingController();
  final _carCtrl         = TextEditingController();
  final _locationCtrl    = TextEditingController();
  final _countryCtrl     = TextEditingController();
  final _aboutCtrl       = TextEditingController();

  // Dropdowns
  String? _gender, _city, _caste, _sect, _education, _maritalStatus, _familyType;
  List<String> _languages = [];
  String? _monthlyIncome, _complexion, _homeType, _hasCar;
  String? _fatherAlive, _motherAlive, _practiceLevel, _hijab, _beard;
  String? _empType, _disability, _lifestyle, _smoker, _hasOtherProp, _otherProp;

  Future<void> _uploadFile() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Choose File Type', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ListTile(
            leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: kPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.image_rounded, color: kPurple)),
            title: const Text('Image / Screenshot', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('JPG, PNG, WebP', style: TextStyle(color: Colors.white38, fontSize: 12)),
            onTap: () => Navigator.pop(context, 'image'),
          ),
          ListTile(
            leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.picture_as_pdf_rounded, color: Colors.orange)),
            title: const Text('PDF Document', style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text('PDF file', style: TextStyle(color: Colors.white38, fontSize: 12)),
            onTap: () => Navigator.pop(context, 'pdf'),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ]),
      ),
    );

    if (choice == null) { setState(() => _inputMode = 'paste'); return; }

    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 600, maxHeight: 600);
    if (picked == null) { setState(() => _inputMode = 'paste'); return; }

    setState(() { _step = 1; _errorMsg = null; _scanning = true; });

    try {
      final bytes = await picked.readAsBytes();
      final base64Data = base64Encode(bytes);
      final mediaType = choice == 'pdf' ? 'application/pdf' : 'image/jpeg';
      final msgType  = choice == 'pdf' ? 'document' : 'image';

      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _kClaudeKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-haiku-4-5',
          'max_tokens': 1000,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': msgType, 'source': {'type': 'base64', 'media_type': mediaType, 'data': base64Data}},
                {'type': 'text', 'text': 'Extract ALL the text from this file exactly as written. Return only the raw text, nothing else.'}
              ]
            }
          ],
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) throw Exception('Upload failed: \${response.body}');
      final json = jsonDecode(response.body);
      final extractedText = json['content'][0]['text'] as String;
      setState(() => _msgCtrl.text = extractedText);
      final result = await parseWhatsAppProposal(message: extractedText);
      _fillForm(result);
      setState(() { _step = 2; _scanning = false; });
    } catch (e) {
      setState(() { _step = 0; _errorMsg = 'Upload failed: \$e'; _scanning = false; _inputMode = 'paste'; });
    }
  }

  Future<void> _captureAndScan() async {
    // Use image_picker camera — no extra package needed
    final picked = await ImagePicker().pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (picked == null) {
      setState(() => _scanMode = false);
      return;
    }

    setState(() { _step = 1; _errorMsg = null; _scanning = true; _scanMode = false; });

    try {
      final bytes = await picked.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _kClaudeKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-haiku-4-5',
          'max_tokens': 1000,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image',
                  'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': base64Image}
                },
                {
                  'type': 'text',
                  'text': 'Extract ALL the text from this image exactly as written. Return only the raw text, nothing else.',
                }
              ]
            }
          ],
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) throw Exception('Scan failed: ${response.body}');

      final json = jsonDecode(response.body);
      final extractedText = json['content'][0]['text'] as String;
      setState(() => _msgCtrl.text = extractedText);

      final result = await parseWhatsAppProposal(message: extractedText);
      _fillForm(result);
      setState(() { _step = 2; _scanning = false; });
    } catch (e) {
      setState(() { _step = 0; _errorMsg = 'Scan failed: $e'; _scanning = false; });
    }
  }

  @override
  void dispose() {
    for (final c in [_msgCtrl, _nameCtrl, _ageCtrl, _phoneCtrl,
        _heightCtrl, _weightCtrl, _profCtrl, _instCtrl, _degreeTitleCtrl,
        _brothersCtrl, _sistersCtrl, _fatherOccCtrl, _motherOccCtrl,
        _houseSizeCtrl, _carCtrl, _locationCtrl, _countryCtrl, _aboutCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto(String type) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery, imageQuality: 75, maxWidth: 600, maxHeight: 600);
    if (picked == null) return;

    if (type == 'profile') {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final cropped = await showPhotoCropDialog(context, bytes);
      if (cropped == null) return;
      setState(() => _profilePhoto = cropped);
    } else {
      setState(() {
      });
    }
  }

  Future<void> _parse() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty) { setState(() => _errorMsg = 'Please paste the message or document first'); return; }
    setState(() { _step = 1; _errorMsg = null; });
    try {
      final r = await parseWhatsAppProposal(message: msg, photoBytes: _profilePhoto);
      _fillForm(r);
      setState(() => _step = 2);
    } catch (e) {
      setState(() { _step = 0; _errorMsg = 'Parsing failed: $e'; });
    }
  }

  String? _m(String? v, List<String> opts) {
    if (v == null || v.isEmpty) return null;
    final lower = v.toLowerCase().trim();
    for (final o in opts) { if (o.toLowerCase() == lower) return o; }
    for (final o in opts) { if (o.toLowerCase().contains(lower) || lower.contains(o.toLowerCase())) return o; }
    return null;
  }

  void _fillForm(ParsedProposal p) {
    _nameCtrl.text        = p.name        ?? '';
    _ageCtrl.text         = p.age         ?? '';
    _phoneCtrl.text       = p.phone       ?? '';
    _phone2Ctrl.text      = p.phone2      ?? '';
    _heightCtrl.text      = p.height      ?? '';
    _weightCtrl.text      = p.weight      ?? '';
    _profCtrl.text        = p.profession  ?? '';
    _instCtrl.text        = p.institute   ?? '';
    _degreeTitleCtrl.text = p.degreeTitle ?? '';
    _brothersCtrl.text    = p.brothers    ?? '';
    _sistersCtrl.text     = p.sisters     ?? '';
    _siblingsCtrl.text    = p.siblings    ?? '';
    _totalKidsCtrl.text   = p.totalKids   ?? '';
    _kidsBoyCtrl.text     = p.kidsBoys    ?? '';
    _kidsGirlCtrl.text    = p.kidsGirls   ?? '';
    _fatherOccCtrl.text   = p.fatherOccupation ?? '';
    _motherOccCtrl.text   = p.motherOccupation ?? '';
    _houseSizeCtrl.text   = p.houseSize   ?? '';
    _carCtrl.text         = p.carName     ?? '';
    _locationCtrl.text    = p.location    ?? '';
    _countryCtrl.text     = p.country     ?? 'Pakistan';
    final parts = [p.about, p.lookingFor].where((s) => s != null && s.isNotEmpty).toList();
    _aboutCtrl.text = parts.join(' | ');
    _discarded = p.discarded;

    setState(() {
      _gender        = p.gender != null ? (p.gender!.toLowerCase() == 'male' ? 'Male' : 'Female') : null;
      _city          = _m(p.city,           SupabaseService.instance.citiesList);
      _caste         = _m(p.caste,          SupabaseService.instance.castesList);
      _sect          = _m(p.sect,           _kSects);
      _languages     = [];
      _education     = _m(p.education,      _kEducations);
      _maritalStatus = _m(p.maritalStatus,  _kMarital);
      _monthlyIncome = _m(p.monthlyIncome,  _kIncomes);
      _complexion    = _m(p.complexion,     _kComplexion);
      _homeType      = _m(p.homeType,       _kHomeType);
      _hasCar        = _m(p.hasCar,         _kHasCar);
      _fatherAlive   = _fatherVal(p.fatherAlive, p.fatherOccupation);
      _motherAlive   = _m(p.motherAlive,    _kParent);
      _practiceLevel = _m(p.practiceLevel,  _kPractice);
      _hijab         = _m(p.hijab,          _kHijab);
      _beard         = _m(p.beard,          _kBeard);
      _empType       = _m(p.employmentType, _kEmpType);
      _disability    = p.disability;
    });
  }

  String? _fatherVal(String? alive, String? occ) {
    final o = (occ ?? '').toLowerCase();
    if (o.contains('deceas') || o.contains('decreas') || o.contains('expired') ||
        o.contains('died') || o.contains('late') || o.contains('intiqal')) return 'Deceased';
    if (alive == null) return null;
    return alive.toLowerCase() == 'yes' ? 'Alive' : 'Deceased';
  }

  // Normalizes a raw phone number (however the AI extraction happened to
  // format it) into the "+CC digits" format the rest of the app expects
  // (proposals_feed's mask_phone() and RishtaProposal.maskedPhone both
  // assume this shape — anything else falls back to a default +92 country
  // code regardless of the person's actual country, which is exactly the
  // bug that caused 100 AI-imported overseas profiles to show the wrong
  // country code on their masked number).
  //
  // The number's OWN shape decides the format — NOT the Country field.
  // An overseas Pakistani very often keeps and shares their original
  // Pakistani number, so this never forces a foreign dial code onto a
  // number that already looks Pakistani just because Country says
  // "abroad". The Country field is only consulted when the digits
  // themselves don't already look Pakistani.
  String _normalizePhone(String raw, String country) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;

    // Already in "+CC ..." form — trust it, just tidy the spacing.
    if (trimmed.startsWith('+')) {
      final digits = trimmed.replaceAll(RegExp(r'[^\d]'), '');
      return '+$digits'.isNotEmpty ? _spaceOutPhone(digits) : trimmed;
    }

    final digits = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return trimmed;

    // STEP 1 — does the number ITSELF look Pakistani, regardless of what
    // Country says? Covers 03XXXXXXXXX (11 digits), 92/0092 + 3XX
    // mobile prefix, or a bare 10-digit number starting with 3.
    final looksPakistani =
        (digits.startsWith('03') && digits.length == 11) ||
        (digits.startsWith('923') && digits.length == 12) ||
        (digits.startsWith('00923') && digits.length == 14) ||
        (digits.startsWith('3') && digits.length == 10);

    final countryIsPakistan = country.trim().isEmpty || country.trim().toLowerCase() == 'pakistan';

    if (looksPakistani || countryIsPakistan) {
      // Pakistani mobile: normalize 0300..., 92300..., 0092300..., or
      // bare 300... all to +92 3XXXXXXXXX.
      var local = digits;
      if (local.startsWith('0092')) {
        local = local.substring(4);
      } else if (local.startsWith('92')) {
        local = local.substring(2);
      } else if (local.startsWith('0')) {
        local = local.substring(1);
      }
      return _spaceOutPhone('92$local');
    }

    // STEP 2 — number doesn't look Pakistani; use the stated country to
    // pick the right dial code, stripping any leading 0/00 trunk digits
    // from the local number first (those are meaningless once a country
    // code is added).
    final dialDigits = _dialCodeForCountry(country);
    if (dialDigits == null) {
      // Unknown/unmapped country name — can't safely guess a dial code,
      // so leave the digits as extracted rather than silently mislabeling
      // them as Pakistani (the old bug). Flagged for manual review via
      // the missing '+' prefix, same signal used to find the original 100.
      return digits;
    }
    var local = digits;
    if (local.startsWith(dialDigits)) {
      local = local.substring(dialDigits.length);
    }
    local = local.replaceFirst(RegExp(r'^0+'), '');
    return _spaceOutPhone('$dialDigits$local');
  }

  String _spaceOutPhone(String digitsWithCc) => '+$digitsWithCc';

  // CountryCode.all entries are "Country Name" -> "+123" — build a
  // lowercase-name -> digits-only-dial-code lookup once per call (this
  // form is only submitted a handful of times per session, so there's no
  // need to cache it as a field). A few common aliases are checked first
  // since the AI extraction prompt's country names don't always match
  // CountryCode.all's naming exactly (e.g. it outputs "United States" /
  // "United Arab Emirates", while the picker list uses "USA" and doesn't
  // list UAE at all — a separate gap worth fixing in the picker list
  // itself, but this keeps phone normalization correct regardless).
  static const _kCountryAliasDialCodes = <String, String>{
    'united states': '1',
    'united states of america': '1',
    'usa': '1',
    'us': '1',
    'united arab emirates': '971',
    'uae': '971',
    'u.a.e': '971',
    'u.a.e.': '971',
  };

  String? _dialCodeForCountry(String countryName) {
    final needle = countryName.trim().toLowerCase();
    if (needle.isEmpty) return null;
    if (_kCountryAliasDialCodes.containsKey(needle)) {
      return _kCountryAliasDialCodes[needle];
    }
    for (final c in CountryCode.all) {
      if (c.name.toLowerCase() == needle) {
        return c.dialCode.replaceAll(RegExp(r'[^\d]'), '');
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty)  { _err('Name is required');   return; }
    if (_ageCtrl.text.trim().isEmpty)   { _err('Age is required');    return; }
    if (_phoneCtrl.text.trim().isEmpty) { _err('Phone is required');  return; }
    if (_gender == null)                { _err('Gender is required'); return; }

    setState(() => _saving = true);
    try {
      double heightInches = 63.0;
      final hm = RegExp(r"(\d+)'(\d+)").firstMatch(_heightCtrl.text.trim());
      if (hm != null) {
        heightInches = double.parse(hm.group(1)!) * 12 + double.parse(hm.group(2)!);
      } else {
        final hd = double.tryParse(_heightCtrl.text.trim());
        if (hd != null) heightInches = hd * 12;
      }


      final data = <String, dynamic>{
        'name'           : _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim() : 'Unknown',
        'age'            : int.tryParse(_ageCtrl.text.trim()) ?? 0,
        'gender'         : _gender ?? 'Female',
        'contact_phone'  : _phoneCtrl.text.trim().isNotEmpty ? _normalizePhone(_phoneCtrl.text.trim(), _countryCtrl.text.trim()) : '0000000000',
        if (_phone2Ctrl.text.trim().isNotEmpty) 'contact_phone_2' : _normalizePhone(_phone2Ctrl.text.trim(), _countryCtrl.text.trim()),
        'height_inches'  : heightInches,
        'city'           : _city           ?? 'Other',
        'caste'          : _caste          ?? 'Other',
        'sect'           : _sect           ?? 'Other',
        if (_languages.isNotEmpty) 'languages': _languages,
        'education'      : _education      ?? 'Other',
        'profession'     : _profCtrl.text.trim().isNotEmpty ? _profCtrl.text.trim() : 'Not specified',
        'marital_status' : _maritalStatus  ?? 'Never married',
        if (_familyType != null) 'family_type' : _familyType,
        'brothers'       : int.tryParse(_brothersCtrl.text.trim()) ?? 0,
        'sisters'        : int.tryParse(_sistersCtrl.text.trim()) ?? 0,
        if (_siblingsCtrl.text.trim().isNotEmpty)  'total_siblings' : int.tryParse(_siblingsCtrl.text.trim()),
        if (_totalKidsCtrl.text.trim().isNotEmpty)  'total_kids'     : int.tryParse(_totalKidsCtrl.text.trim()),
        if (_kidsBoyCtrl.text.trim().isNotEmpty)    'kids_boys'      : int.tryParse(_kidsBoyCtrl.text.trim()),
        if (_kidsGirlCtrl.text.trim().isNotEmpty)   'kids_girls'     : int.tryParse(_kidsGirlCtrl.text.trim()),
        'status'         : 'pending',
        'admin_notes'    : 'AI_IMPORTED',
        'amount_paid'    : 0,
        'posted_at'      : DateTime.now().toIso8601String(),
        if (_weightCtrl.text.trim().isNotEmpty)      'weight_kg'         : double.tryParse(_weightCtrl.text.trim()),
        if (_instCtrl.text.trim().isNotEmpty)        'institute'         : _instCtrl.text.trim(),
        if (_degreeTitleCtrl.text.trim().isNotEmpty) 'degree_title'      : _degreeTitleCtrl.text.trim(),
        if (_homeType != null)                       'home_type'         : _homeType,
        if (_houseSizeCtrl.text.trim().isNotEmpty)   'house_size'        : _houseSizeCtrl.text.trim(),
        if (_locationCtrl.text.trim().isNotEmpty)    'location'          : _locationCtrl.text.trim(),
        if (_countryCtrl.text.trim().isNotEmpty)     'country'           : _countryCtrl.text.trim(),
        if (_hasCar != null)                         'has_car'           : _hasCar,
        if (_carCtrl.text.trim().isNotEmpty)         'car_name'          : _carCtrl.text.trim(),
        if (_fatherAlive != null)                    'father_alive'      : _fatherAlive == 'Alive',
        if (_fatherOccCtrl.text.trim().isNotEmpty)   'father_occupation' : _fatherOccCtrl.text.trim(),
        if (_motherAlive != null)                    'mother_alive'      : _motherAlive == 'Alive',
        if (_motherOccCtrl.text.trim().isNotEmpty)   'mother_occupation' : _motherOccCtrl.text.trim(),
        if (_practiceLevel != null)                  'practice_level'    : _practiceLevel,
        if (_hijab != null)                          'hijab'             : _hijab,
        if (_beard != null)                          'beard'             : _beard,
        if (_complexion != null)                     'complexion'        : _complexion,
        if (_empType != null)                        'employment_type'   : _empType,
        if (_monthlyIncome != null)                  'monthly_income'    : _monthlyIncome,
        if (_disability != null)                     'has_disability'    : _disability == 'Yes',
        if (_lifestyle != null)                      'physically_active' : _lifestyle,
        if (_smoker != null)                         'smokes'            : _smoker == 'Yes',
        if (_hasOtherProp != null)                   'has_other_property': _hasOtherProp,
        if (_otherProp != null && _hasOtherProp == 'Yes') 'other_property'   : _otherProp,
        if (_aboutCtrl.text.trim().isNotEmpty)       'about'             : _aboutCtrl.text.trim(),
      };

      await widget.svc.addUserWithPhotos(
        data: data,
        profilePhoto: _profilePhoto,
      );

      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context);
      }
    } catch (e) {
      _err('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kCard,
        title: const Text('Generate with AI', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_step == 2)
            TextButton(
              onPressed: () => setState(() { _step = 0; _msgCtrl.clear(); _profilePhoto = null; _discarded = null; }),
              child: const Text('Start Over', style: TextStyle(color: Colors.white54, fontSize: 13)),
            ),
        ],
      ),
      body: _step == 0 ? _buildPaste() : _step == 1 ? _buildLoading() : _buildForm(),
    );
  }

  // ── STEP 0 ────────────────────────────────────────────────
  Widget _buildMessageBox() => Container(
    key: const ValueKey('msg'),
    decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: _kBdr)),
    child: TextField(
      controller: _msgCtrl, maxLines: 12,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: const InputDecoration(
        hintText: 'Paste proposal message or text here...',
        hintStyle: TextStyle(color: Colors.white24),
        border: InputBorder.none, contentPadding: EdgeInsets.all(12),
      ),
    ),
  );

  Widget _buildScanBox() => GestureDetector(
    key: const ValueKey('scan'),
    onTap: _captureAndScan,
    child: Container(
      height: 220,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kPurple.withOpacity(0.5), width: 1.5),
      ),
      child: Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: _ScanLineAnimation(),
        ),
        Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: kPurple,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: kPurple.withOpacity(0.4), blurRadius: 16)],
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 14),
            const Text('Tap to open camera', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Point at message or document', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
        ..._scanCorners(),
      ]),
    ),
  );

  List<Widget> _scanCorners() {
    const c = kPurple;
    const w = 18.0;
    const t = 2.5;
    return [
      Positioned(top: 10, left: 10, child: _corner(c, w, t, true, true)),
      Positioned(top: 10, right: 10, child: _corner(c, w, t, true, false)),
      Positioned(bottom: 10, left: 10, child: _corner(c, w, t, false, true)),
      Positioned(bottom: 10, right: 10, child: _corner(c, w, t, false, false)),
    ];
  }

  Widget _corner(Color c, double w, double t, bool top, bool left) => SizedBox(
    width: w, height: w,
    child: CustomPaint(painter: _CornerPainter(color: c, thickness: t, top: top, left: left)),
  );

  Widget _buildPaste() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: kPurple.withOpacity(0.3))),
        child: const Row(children: [
          Icon(Icons.auto_awesome, color: kPurple, size: 18),
          SizedBox(width: 10),
          Expanded(child: Text('Paste or scan — AI will fill the form.', style: TextStyle(color: Colors.white70, fontSize: 13))),
        ]),
      ),
      const SizedBox(height: 16),
      // Three visible buttons: Paste | Upload | Scan
      Row(children: [
        Expanded(child: _modeBtn('Paste', Icons.keyboard_rounded, 'paste',
          () => setState(() { _inputMode = 'paste'; _scanMode = false; }))),
        const SizedBox(width: 8),
        Expanded(child: _modeBtn('Upload', Icons.upload_file_rounded, 'upload',
          () async { setState(() => _inputMode = 'upload'); await _uploadFile(); })),
        const SizedBox(width: 8),
        if (!kIsWeb) Expanded(child: _modeBtn('Scan', Icons.document_scanner_rounded, 'scan',
          () => setState(() { _inputMode = 'scan'; _scanMode = true; }))),
      ]),
      const SizedBox(height: 8),
      // Message box OR live camera
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _inputMode == 'scan' ? _buildScanBox() : _buildMessageBox(),
      ),
      if (_errorMsg != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.withOpacity(0.3))),
          child: Text(_errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ),
      ],
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _parse,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('Parse & Fill Form', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: kPurple, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    ]),
  );

  // ── STEP 1 ────────────────────────────────────────────────
  Widget _buildLoading() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const CircularProgressIndicator(color: kPurple),
      const SizedBox(height: 20),
      Text(_scanning ? 'Scanning message...' : 'Reading proposal...', style: const TextStyle(color: Colors.white70, fontSize: 16)),
      const SizedBox(height: 6),
      Text(_scanning ? 'Extracting text from image' : 'AI is extracting all fields', style: const TextStyle(color: Colors.white38, fontSize: 13)),
    ]),
  );

  // ── STEP 2 ────────────────────────────────────────────────
  Widget _buildForm() => Stack(children: [
    SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Photos section ──────────────────────────────────
        _sec('Photos'),
        SizedBox(
          width: 100, height: 100,
          child: _photoBox('Profile', _profilePhoto, () => _pickPhoto('profile'), Icons.person_rounded),
        ),

        // ── Basic Info ──────────────────────────────────────
        _sec('Basic Info'),
        _row2(_tf('Full Name *', _nameCtrl), _tf('Age *', _ageCtrl, kb: TextInputType.number)),
        _row2(_tf('Phone *', _phoneCtrl, kb: TextInputType.phone), const SizedBox()),
        _HeightDropdowns(controller: _heightCtrl, darkTheme: true, label: 'Height'),
        _tf('Second Phone (optional)', _phone2Ctrl, kb: TextInputType.phone),
        _row2(_dd('Gender *', _gender, _kGenders, (v) => setState(() => _gender = v)),
              _dd('Marital Status', _maritalStatus, _kMarital, (v) => setState(() => _maritalStatus = v))),

        _row2(_dd('Complexion', _complexion, _kComplexion, (v) => setState(() => _complexion = v)),
              _tf('Weight (kg)', _weightCtrl, kb: TextInputType.number)),

        _sec('Location'),
        _row2(_dd('City', _city, SupabaseService.instance.citiesList, (v) => setState(() => _city = v)),
              _tf('Area / Neighbourhood', _locationCtrl)),
        _row2(_tf('Country', _countryCtrl), const SizedBox()),

        _sec('Religion'),
        _row2(_dd('Caste', _caste, SupabaseService.instance.castesList, (v) => setState(() => _caste = v)),
              _dd('Sect / Maslak', _sect, _kSects, (v) => setState(() => _sect = v))),
        _multiSelect('Language(s)', _languages, _kLanguages, (v) => setState(() => _languages = v)),
        _row2(
          _dd('Practice Level', _practiceLevel, _kPractice, (v) => setState(() => _practiceLevel = v)),
          _gender == 'Female'
            ? _dd('Wears Hijab', _hijab, _kHijab, (v) => setState(() => _hijab = v))
            : _dd('Have Beard', _beard, _kBeard, (v) => setState(() => _beard = v)),
        ),

        _sec('Education & Work'),
        _row2(_dd('Education Level (Highest)', _education, _kEducations, (v) => setState(() => _education = v)),
              _tf('Degree Title', _degreeTitleCtrl)),
        _row2(_tf('Institute / University', _instCtrl), const SizedBox()),
        _row2(_tf('Occupation', _profCtrl),
              _dd('Employment Type', _empType, _kEmpType, (v) => setState(() => _empType = v))),
        _dd('Monthly Income', _monthlyIncome, _kIncomes, (v) => setState(() => _monthlyIncome = v)),

        _sec('Family'),
        _row2(_dd('Family Type', _familyType, const ['Joint family', 'Separated Family'], (v) => setState(() => _familyType = v)),
              const SizedBox()),
        _row2(_dd('Father', _fatherAlive, _kParent, (v) => setState(() => _fatherAlive = v)),
              _tf('Father Occupation', _fatherOccCtrl)),
        _row2(_dd('Mother', _motherAlive, _kParent, (v) => setState(() => _motherAlive = v)),
              _tf('Mother Occupation', _motherOccCtrl)),
        // Siblings — show total or breakdown
        if (_siblingsCtrl.text.isNotEmpty && _brothersCtrl.text.isEmpty && _sistersCtrl.text.isEmpty)
          _tf('Siblings (total)', _siblingsCtrl, kb: TextInputType.number)
        else
          _row2(_tf('Brothers', _brothersCtrl, kb: TextInputType.number),
                _tf('Sisters', _sistersCtrl, kb: TextInputType.number)),
        if (_siblingsCtrl.text.isNotEmpty && (_brothersCtrl.text.isNotEmpty || _sistersCtrl.text.isNotEmpty))
          _tf('Total Siblings', _siblingsCtrl, kb: TextInputType.number),

        // Kids — only show if divorced/widowed/khula
        if (_maritalStatus != null &&
            (_maritalStatus == 'Divorced' || _maritalStatus == 'Widowed' || _maritalStatus == 'Khula' || _maritalStatus == 'Married')) ...[
          _sec('Children'),
          if (_totalKidsCtrl.text.isNotEmpty && _kidsBoyCtrl.text.isEmpty && _kidsGirlCtrl.text.isEmpty)
            _tf('Total Children', _totalKidsCtrl, kb: TextInputType.number)
          else
            _row2(_tf('Sons', _kidsBoyCtrl, kb: TextInputType.number),
                  _tf('Daughters', _kidsGirlCtrl, kb: TextInputType.number)),
          if (_totalKidsCtrl.text.isNotEmpty && (_kidsBoyCtrl.text.isNotEmpty || _kidsGirlCtrl.text.isNotEmpty))
            _tf('Total Children', _totalKidsCtrl, kb: TextInputType.number),
        ],

        _sec('Property'),
        _row2(_dd('Home Type', _homeType, _kHomeType, (v) => setState(() => _homeType = v)),
              _tf('House Size', _houseSizeCtrl)),
        _dd('Car', _hasCar, _kHasCar, (v) => setState(() => _hasCar = v)),
        _dd('Other Property', _hasOtherProp, ['Yes', 'No'], (v) => setState(() { _hasOtherProp = v; if (v == 'No') _otherProp = null; })),
        if (_hasOtherProp == 'Yes')
          _dd('Property Type', _otherProp, _kOtherProp, (v) => setState(() => _otherProp = v)),

        _sec('Lifestyle'),
        _row2(_dd('Lifestyle', _lifestyle, _kLifestyle, (v) => setState(() => _lifestyle = v)),
              _dd('Smoker', _smoker, _kSmoker, (v) => setState(() => _smoker = v))),
        _dd('Disability / Chronic Illness', _disability, _kDisability, (v) => setState(() => _disability = v)),

        _sec('About'),
        _tf('About Yourself / Looking For', _aboutCtrl, lines: 4),

        // Discarded info box
        if (_discarded != null && _discarded!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kAmber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kAmber.withOpacity(0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.info_outline_rounded, color: kAmber, size: 16),
                const SizedBox(width: 6),
                const Text('Discarded Info', style: TextStyle(color: kAmber, fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                const Text('Not saved — add manually if needed', style: TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
              const SizedBox(height: 8),
              ..._discarded!.split('|').where((s) => s.trim().isNotEmpty).map((item) =>
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('• ', style: TextStyle(color: kAmber, fontSize: 13, fontWeight: FontWeight.w600)),
                    Expanded(child: Text(item.trim(), style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4))),
                  ]),
                )
              ).toList(),
            ]),
          ),
        ],
      ]),
    ),

    Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
        color: _kBg,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_rounded),
          label: Text(_saving ? 'Saving...' : 'Save Proposal', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: kGreen, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    ),
  ]);

  // ── Photo box widget ──────────────────────────────────────
  Widget _photoBox(String label, Uint8List? file, VoidCallback onTap, IconData icon) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        color: file != null ? Colors.transparent : _kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: file != null ? kPurple.withOpacity(0.6) : Colors.white.withOpacity(0.08),
          width: file != null ? 1.5 : 1,
        ),
      ),
      child: file == null
          ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white38, size: 18),
              ),
              const SizedBox(height: 6),
              const Text('Add Photo', style: TextStyle(color: Colors.white38, fontSize: 10)),
            ])
          : ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(fit: StackFit.expand, children: [
                Image.memory(file!, fit: BoxFit.cover),
                Positioned(top: 4, right: 4,
                  child: Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(5)),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 12),
                  ),
                ),
              ]),
            ),
    ),
  );

  Widget _modeBtn(String label, IconData icon, String mode, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: _inputMode == mode ? kPurple : _kCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _inputMode == mode ? kPurple : Colors.white.withOpacity(0.12),
          width: 1.5,
        ),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 18, color: _inputMode == mode ? Colors.white : Colors.white54),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
          color: _inputMode == mode ? Colors.white : Colors.white54)),
      ]),
    ),
  );

  Widget _multiSelect(String label, List<String> selected, List<String> options, ValueChanged<List<String>> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: options.map((opt) {
          final sel = selected.contains(opt);
          return GestureDetector(
            onTap: () { final u = List<String>.from(selected); if (sel) u.remove(opt); else u.add(opt); onChanged(u); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: sel ? kPurpleLight : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: sel ? kPurple : const Color(0xFFDDDDEE).withOpacity(0.3), width: sel ? 1.5 : 1),
              ),
              child: Text(opt, style: TextStyle(
                fontSize: 13,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel ? kPurple : Colors.white70,
              )),
            ),
          );
        }).toList()),
      ]),
    );
  }

  Widget _sec(String t) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 8),
    child: Text(t, style: const TextStyle(color: kPurple, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
  );

  Widget _row2(Widget a, Widget b) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: a), const SizedBox(width: 8), Expanded(child: b),
    ]),
  );

  Widget _tf(String label, TextEditingController ctrl, {TextInputType? kb, int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      const SizedBox(height: 3),
      Container(
        decoration: BoxDecoration(color: _kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: _kBdr)),
        child: TextField(controller: ctrl, keyboardType: kb, maxLines: lines,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8))),
      ),
    ]),
  );

  Widget _dd(String label, String? value, List<String> items, ValueChanged<String?> onChanged, {String? infoText}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Row(children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          if (infoText != null) ...[
            const SizedBox(width: 5),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: _kCard,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                  content: Text(infoText, style: const TextStyle(fontSize: 13.5, color: Colors.white70, height: 1.5)),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
                ),
              ),
              child: const Icon(Icons.info_outline_rounded, color: Colors.white38, size: 14),
            ),
          ],
        ])),
        if (value != null)
          GestureDetector(
            onTap: () => onChanged(null),
            child: const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Icon(Icons.close_rounded, size: 14, color: kRose),
            ),
          ),
      ]),
      const SizedBox(height: 3),
      GestureDetector(
        onTap: () {
          showModalBottomSheet(
            context: context,
            backgroundColor: _kCard,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
            builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600))),
                  if (value != null) GestureDetector(
                    onTap: () { Navigator.pop(context); onChanged(null); },
                    child: const Text('Clear', style: TextStyle(color: kRose, fontSize: 13)),
                  ),
                ]),
              ),
              const Divider(color: Colors.white12, height: 1),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(shrinkWrap: true, children: items.map((o) => ListTile(
                  title: Text(o, style: TextStyle(
                    color: o == value ? kPurple : Colors.white,
                    fontSize: 14,
                    fontWeight: o == value ? FontWeight.w700 : FontWeight.w400,
                  )),
                  trailing: o == value ? const Icon(Icons.check_rounded, color: kPurple, size: 18) : null,
                  onTap: () { Navigator.pop(context); onChanged(o); },
                )).toList()),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ]),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _kCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBdr),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                value ?? 'Select',
                style: TextStyle(
                  color: value != null ? Colors.white : Colors.white24,
                  fontSize: 13,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: 18),
          ]),
        ),
      ),
    ]),
  );
}

// ── Animated scan line ────────────────────────────────────────────────────────
class _ScanLineAnimation extends StatefulWidget {
  @override
  State<_ScanLineAnimation> createState() => _ScanLineAnimationState();
}

class _ScanLineAnimationState extends State<_ScanLineAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.05, end: 0.95).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Stack(children: [
      Positioned(
        top: _anim.value * 200,
        left: 0, right: 0,
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.transparent,
              kPurple.withOpacity(0.8),
              Colors.transparent,
            ]),
          ),
        ),
      ),
    ]),
  );
}

// ── Corner marker painter ─────────────────────────────────────────────────────
class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool top, left;
  const _CornerPainter({required this.color, required this.thickness, required this.top, required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = thickness..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    if (top && left) {
      canvas.drawLine(Offset.zero, Offset(w, 0), paint);
      canvas.drawLine(Offset.zero, Offset(0, h), paint);
    } else if (top && !left) {
      canvas.drawLine(Offset(0, 0), Offset(w, 0), paint);
      canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
    } else if (!top && left) {
      canvas.drawLine(Offset(0, 0), Offset(0, h), paint);
      canvas.drawLine(Offset(0, h), Offset(w, h), paint);
    } else {
      canvas.drawLine(Offset(w, 0), Offset(w, h), paint);
      canvas.drawLine(Offset(0, h), Offset(w, h), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}



// ── Height picker: two dropdowns (feet + inches) ──────────────────────────────
class _HeightDropdowns extends StatefulWidget {
  final TextEditingController controller;
  final bool darkTheme;
  final String label;
  const _HeightDropdowns({required this.controller, this.darkTheme = false, this.label = 'Height'});
  @override State<_HeightDropdowns> createState() => _HeightDropdownsState();
}
class _HeightDropdownsState extends State<_HeightDropdowns> {
  int? _feet;
  int? _inches;

  @override
  void initState() {
    super.initState();
    _parse();
    widget.controller.addListener(_parse);
  }

  void _parse() {
    final m = RegExp(r"(\d+)'(\d+)").firstMatch(widget.controller.text);
    if (m != null) {
      final f = int.parse(m.group(1)!);
      final i = int.parse(m.group(2)!);
      if (f != _feet || i != _inches) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() { _feet = f; _inches = i; });
        });
      }
    }
  }

  void _update(int? feet, int? inches) {
    setState(() { _feet = feet; _inches = inches; });
    if (feet != null && inches != null) {
      final fmt = "$feet'$inches\"";
      if (widget.controller.text != fmt) widget.controller.text = fmt;
    } else {
      if (widget.controller.text.isNotEmpty) widget.controller.clear();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_parse);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const labelColor = Color(0x80FFFFFF);
    const textColor  = Colors.white;
    final fillColor  = Colors.black.withOpacity(0.2);
    const borderColor = Color(0x1EFFFFFF);

    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint, hintStyle: const TextStyle(color: labelColor, fontSize: 13),
      filled: true, fillColor: fillColor, isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: borderColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF534AB7), width: 1.5)),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: labelColor)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            value: _feet,
            hint: const Text('Feet', style: TextStyle(color: labelColor, fontSize: 13)),
            style: const TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w500),
            dropdownColor: const Color(0xFF1E1A33),
            icon: const Icon(Icons.expand_more_rounded, size: 18, color: labelColor),
            decoration: deco('ft'),
            items: List.generate(4, (i) => i + 4).map((f) =>
              DropdownMenuItem(value: f, child: Text("$f ft", style: const TextStyle(color: textColor, fontSize: 13.5)))).toList(),
            onChanged: (v) => _update(v, _inches),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<int>(
            value: _inches,
            hint: const Text('Inches', style: TextStyle(color: labelColor, fontSize: 13)),
            style: const TextStyle(color: textColor, fontSize: 13.5, fontWeight: FontWeight.w500),
            dropdownColor: const Color(0xFF1E1A33),
            icon: const Icon(Icons.expand_more_rounded, size: 18, color: labelColor),
            decoration: deco('in'),
            items: List.generate(12, (i) => i).map((i) =>
              DropdownMenuItem(value: i, child: Text('$i in', style: const TextStyle(color: textColor, fontSize: 13.5)))).toList(),
            onChanged: (v) => _update(_feet, v),
          ),
        ),
      ]),
    ]);
  }
}
