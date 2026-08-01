import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/photo_crop_dialog.dart';
import '../widgets/country_picker.dart';
import '../utils/theme.dart';
import '../services/admin_service.dart';

// ── Responsive scale helper ────────────────────────────────────────────────
class _S {
  final double scale;
  const _S(this.scale);
  double f(double size) => size * scale;
  double s(double size) => size * scale;
  double d(double size) => size * scale;
  static _S of(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final scale = (w / 390.0).clamp(0.72, 1.0);
    return _S(scale);
  }
}

const _kBg2 = Color(0xFF16132A);
const _kCard2 = Color(0xFF1E1A33);

// Same dash placement as the Edit Profile / Submit Proposal forms:
// XXXXX-XXXXXXX-X. Kept as its own copy here (private, so it can't be
// imported from admin_edit_user_screen.dart) — same pattern already used
// for _HeightDropdowns across this app's screens.
class _AdminCnicFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('-', '');
    if (digits.length > 13) return oldValue;
    final buf = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 5 || i == 12) buf.write('-');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class AdminAddUserScreen extends StatefulWidget {
  final AdminService svc;
  const AdminAddUserScreen({super.key, required this.svc});
  @override
  State<AdminAddUserScreen> createState() => _AdminAddUserScreenState();
}

class _AdminAddUserScreenState extends State<AdminAddUserScreen> {
  bool _saving = false;

  CountryCode _selectedCountry = CountryCode.pakistan;
  CountryCode _selectedCountry2 = CountryCode.pakistan;

  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _phone2Ctrl = TextEditingController();
  final _cnicCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _aboutCtrl = TextEditingController();
  final _lookingForCtrl = TextEditingController();
  final _instCtrl = TextEditingController();
  final _degreeTitleCtrl = TextEditingController();
  final _inst2Ctrl = TextEditingController();
  final _degreeTitle2Ctrl = TextEditingController();
  final _inst3Ctrl = TextEditingController();
  final _degreeTitle3Ctrl = TextEditingController();
  final _profCtrl = TextEditingController();
  final _brothersCtrl = TextEditingController();
  final _sistersCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _houseSizeCtrl = TextEditingController();
  final _carCtrl = TextEditingController();
  final _boysCtrl = TextEditingController();
  final _girlsCtrl = TextEditingController();
  final _fatherOccCtrl = TextEditingController();
  final _motherOccCtrl = TextEditingController();
  final _disabilityCtrl = TextEditingController();
  final _adminNotesCtrl = TextEditingController();

  String _gender = '';
  String _city = '';
  String _caste = '';
  String _sect = '';
  String? _language;
  String _education = '';
  String _maritalStatus = '';
  String? _marriageNumber;
  String _familyType = '';
  String _openToPolygamy = '';
  String _homeType = '';
  String _hasCar = '';
  String _hasOtherProperty = '';
  String _otherProperty = '';
  String _fatherAlive = '';
  String _motherAlive = '';
  String _hasSiblings = '';
  String _hasDisability = '';
  String _practiceLevel = '';
  String _hijab = '';
  String _beard = '';
  String _physActive = '';
  String _smokes = '';
  String _complexion = '';
  String _empType = '';
  String _monthlyIncome = '';
  String _hasKids = '';

  File? _profilePhoto;
  File? _cnicFront;
  File? _cnicBack;
  File? _degreeCert;
  File? _degreeCert2;
  File? _degreeCert3;

  bool get _showKids {
    final s = _maritalStatus.toLowerCase();
    return s == 'divorced' || s == 'khula' || s == 'widowed';
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _ageCtrl, _phoneCtrl, _phone2Ctrl, _cnicCtrl, _passwordCtrl, _heightCtrl, _weightCtrl,
      _aboutCtrl, _lookingForCtrl, _instCtrl, _degreeTitleCtrl, _inst2Ctrl, _degreeTitle2Ctrl,
      _inst3Ctrl, _degreeTitle3Ctrl, _profCtrl, _brothersCtrl, _sistersCtrl, _locationCtrl, _countryCtrl,
      _houseSizeCtrl, _carCtrl, _boysCtrl, _girlsCtrl, _fatherOccCtrl, _motherOccCtrl, _disabilityCtrl,
      _adminNotesCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) { _err('Name is required'); return; }
    if (_ageCtrl.text.trim().isEmpty) { _err('Age is required'); return; }
    if (_phoneCtrl.text.trim().isEmpty) { _err('Phone is required'); return; }
    if (_gender.isEmpty) { _err('Gender is required'); return; }
    setState(() => _saving = true);
    try {
      double heightInches = 65;
      final hm = RegExp(r"(\d+)'(\d+)").firstMatch(_heightCtrl.text.trim());
      if (hm != null) {
        heightInches = double.parse(hm.group(1)!) * 12 + double.parse(hm.group(2)!);
      } else {
        heightInches = double.tryParse(_heightCtrl.text.trim()) ?? 65;
      }

      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'age': int.tryParse(_ageCtrl.text.trim()) ?? 0,
        'gender': _gender,
        'contact_phone': formatDialedPhone(_selectedCountry.dialCode, _phoneCtrl.text),
        if (_phone2Ctrl.text.trim().isNotEmpty)
          'contact_phone_2': formatDialedPhone(_selectedCountry2.dialCode, _phone2Ctrl.text),
        if (_cnicCtrl.text.trim().isNotEmpty) 'cnic': _cnicCtrl.text.trim(),
        if (_passwordCtrl.text.trim().isNotEmpty) 'password': _passwordCtrl.text.trim(),
        'height_inches': heightInches,
        if (_weightCtrl.text.trim().isNotEmpty) 'weight_kg': double.tryParse(_weightCtrl.text.trim()),
        if (_city.isNotEmpty) 'city': _city,
        if (_caste.isNotEmpty) 'caste': _caste,
        if (_sect.isNotEmpty) 'sect': _sect,
        if (_language != null && _language!.isNotEmpty) 'languages': [_language!],
        if (_education.isNotEmpty) 'education': _education,
        if (_instCtrl.text.trim().isNotEmpty) 'institute': _instCtrl.text.trim(),
        if (_degreeTitleCtrl.text.trim().isNotEmpty) 'degree_title': _degreeTitleCtrl.text.trim(),
        if (_inst2Ctrl.text.trim().isNotEmpty) 'institute_2': _inst2Ctrl.text.trim(),
        if (_degreeTitle2Ctrl.text.trim().isNotEmpty) 'degree_title_2': _degreeTitle2Ctrl.text.trim(),
        if (_inst3Ctrl.text.trim().isNotEmpty) 'institute_3': _inst3Ctrl.text.trim(),
        if (_degreeTitle3Ctrl.text.trim().isNotEmpty) 'degree_title_3': _degreeTitle3Ctrl.text.trim(),
        if (_profCtrl.text.trim().isNotEmpty) 'profession': _profCtrl.text.trim(),
        if (_maritalStatus.isNotEmpty) 'marital_status': _maritalStatus,
        if (_marriageNumber != null && _marriageNumber!.isNotEmpty) 'marriage_number': _marriageNumber,
        if (_openToPolygamy.isNotEmpty) 'open_to_polygamy': _openToPolygamy,
        if (_familyType.isNotEmpty) 'family_type': _familyType,
        if (_homeType.isNotEmpty) 'home_type': _homeType,
        if (_houseSizeCtrl.text.trim().isNotEmpty) 'house_size': _houseSizeCtrl.text.trim(),
        if (_locationCtrl.text.trim().isNotEmpty) 'location': _locationCtrl.text.trim(),
        if (_countryCtrl.text.trim().isNotEmpty) 'country': _countryCtrl.text.trim(),
        if (_hasCar.isNotEmpty) 'has_car': _hasCar,
        if (_carCtrl.text.trim().isNotEmpty) 'car_name': _carCtrl.text.trim(),
        if (_hasOtherProperty.isNotEmpty) 'has_other_property': _hasOtherProperty,
        if (_otherProperty.isNotEmpty && _hasOtherProperty == 'Yes') 'other_property': _otherProperty,
        if (_fatherAlive.isNotEmpty) 'father_alive': _fatherAlive == 'Alive',
        if (_fatherOccCtrl.text.trim().isNotEmpty) 'father_occupation': _fatherOccCtrl.text.trim(),
        if (_motherAlive.isNotEmpty) 'mother_alive': _motherAlive == 'Alive',
        if (_motherOccCtrl.text.trim().isNotEmpty) 'mother_occupation': _motherOccCtrl.text.trim(),
        if (_hasSiblings.isNotEmpty) 'has_siblings': _hasSiblings == 'Yes',
        if (_brothersCtrl.text.trim().isNotEmpty) 'brothers': int.tryParse(_brothersCtrl.text.trim()),
        if (_sistersCtrl.text.trim().isNotEmpty) 'sisters': int.tryParse(_sistersCtrl.text.trim()),
        if (_hasKids.isNotEmpty) 'has_kids': _hasKids == 'Yes',
        if (_boysCtrl.text.trim().isNotEmpty) 'boys': int.tryParse(_boysCtrl.text.trim()),
        if (_girlsCtrl.text.trim().isNotEmpty) 'girls': int.tryParse(_girlsCtrl.text.trim()),
        if (_practiceLevel.isNotEmpty) 'practice_level': _practiceLevel,
        if (_hijab.isNotEmpty) 'hijab': _hijab,
        if (_beard.isNotEmpty) 'beard': _beard,
        if (_complexion.isNotEmpty) 'complexion': _complexion,
        if (_empType.isNotEmpty) 'employment_type': _empType,
        if (_monthlyIncome.isNotEmpty) 'salary_start': _monthlyIncome,
        if (_physActive.isNotEmpty) 'physically_active': _physActive,
        if (_smokes.isNotEmpty) 'smokes': _smokes == 'Yes',
        if (_hasDisability.isNotEmpty) 'has_disability': _hasDisability,
        if (_disabilityCtrl.text.trim().isNotEmpty) 'disability_details': _disabilityCtrl.text.trim(),
        if (_aboutCtrl.text.trim().isNotEmpty) 'about': _aboutCtrl.text.trim(),
        if (_lookingForCtrl.text.trim().isNotEmpty) 'looking_for': _lookingForCtrl.text.trim(),
        if (_adminNotesCtrl.text.trim().isNotEmpty) 'admin_notes': _adminNotesCtrl.text.trim(),
        'status': 'pending',
        'posted_at': DateTime.now().toIso8601String(),
      };

      await widget.svc.addUserWithPhotos(
        data: data,
        profilePhoto: _profilePhoto,
        cnicFront: _cnicFront,
        cnicBack: _cnicBack,
        degreeCertificate: _degreeCert,
        degreeCertificate2: _degreeCert2,
        degreeCertificate3: _degreeCert3,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
    } catch (e) {
      _err('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _err(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: kRose, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return Scaffold(
      backgroundColor: _kBg2,
      appBar: AppBar(
        backgroundColor: _kBg2,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('Add New Profile', style: TextStyle(fontSize: s.f(16), fontWeight: FontWeight.w800, color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: s.s(16), vertical: s.s(6)),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [kPurple, kPurpleDeep]), borderRadius: BorderRadius.circular(s.s(10))),
              child: _saving
                  ? SizedBox(width: s.d(16), height: s.d(16), child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(13))),
            ),
          ),
          SizedBox(width: s.s(8)),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: Colors.white.withOpacity(0.07))),
      ),
      body: ListView(
        padding: EdgeInsets.all(s.s(16)),
        children: [
          // ── BASIC INFORMATION ──
          _mainHeader('Basic Information'),
          _field('Full Name *', _nameCtrl),
          _field('Age *', _ageCtrl, type: TextInputType.number),
          _HeightDropdowns(controller: _heightCtrl, darkTheme: true, label: 'Height'),
          _phoneField('Phone Number *', _phoneCtrl, _selectedCountry, (c) => setState(() => _selectedCountry = c)),
          _phoneField('Second Phone Number (optional)', _phone2Ctrl, _selectedCountry2, (c) => setState(() => _selectedCountry2 = c), required: false),
          _field('CNIC Number', _cnicCtrl, type: TextInputType.number, formatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
            _AdminCnicFormatter(),
          ]),
          _field('Password', _passwordCtrl),
          _drop('Gender *', _gender, ['Male', 'Female'], (v) => setState(() => _gender = v)),
          _field('Country', _countryCtrl),
          _cityPicker(),
          _drop('House', _homeType, ['Own House', 'Rented House'], (v) => setState(() => _homeType = v)),
          if (_homeType.isNotEmpty) ...[
            _subField('Location', _locationCtrl),
            _subField('House Size', _houseSizeCtrl),
          ],
          _drop('Caste', _caste, kCastes, (v) => setState(() => _caste = v)),
          _drop('Sect / Maslak', _sect, kSects, (v) => setState(() => _sect = v)),
          _drop('Native Language', _language ?? '', kLanguages, (v) => setState(() => _language = v.isEmpty ? null : v)),
          _field('Occupation', _profCtrl),
          _drop('Marital Status', _maritalStatus, ['Never Married', 'Married', 'Divorced', 'Khula', 'Widowed'],
              (v) => setState(() { _maritalStatus = v; if (v != 'Married') _marriageNumber = null; })),
          if (_maritalStatus == 'Married')
            _subDrop('Looking for', _marriageNumber ?? '', ['Second marriage', 'Third marriage', 'Fourth marriage'],
                (v) => setState(() => _marriageNumber = v.isEmpty ? null : v)),
          if (_showKids) ...[
            _drop('Has Kids', _hasKids, ['Yes', 'No'], (v) => setState(() => _hasKids = v)),
            if (_hasKids == 'Yes')
              _row([
                _subField('Sons', _boysCtrl, type: TextInputType.number),
                _subField('Daughters', _girlsCtrl, type: TextInputType.number),
              ]),
          ],
          _drop('Open to Polygamy?', _openToPolygamy, ['Yes', 'No'], (v) => setState(() => _openToPolygamy = v),
              infoText: 'Polygamy means having more than one wife or marrying a man who already has a wife.'),
          _multiField('About Yourself', _aboutCtrl, maxLength: 200),
          _multiField('Looking For', _lookingForCtrl, maxLength: 200),

          // ── Photos ──
          SizedBox(height: s.s(12)),
          Text('Photos', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
          SizedBox(height: s.s(8)),
          Row(children: [
            Expanded(
              child: _NewPhotoSlot(
                label: 'Profile Photo',
                file: _profilePhoto,
                crop: true,
                onChanged: (f) => setState(() => _profilePhoto = f),
              ),
            ),
          ]),
          SizedBox(height: s.s(16)),
          _mainHeader('Verification'),
          SizedBox(height: s.s(8)),
          Row(children: [
            Expanded(
              child: _NewPhotoSlot(
                label: 'CNIC Front',
                file: _cnicFront,
                onChanged: (f) => setState(() => _cnicFront = f),
              ),
            ),
            SizedBox(width: s.s(10)),
            Expanded(
              child: _NewPhotoSlot(
                label: 'CNIC Back',
                file: _cnicBack,
                onChanged: (f) => setState(() => _cnicBack = f),
              ),
            ),
          ]),
          SizedBox(height: s.s(4)),

          _mainHeader('Additional Information'),

          // ── FAMILY ──
          _subHeader('Family'),
          _drop('Family Type', _familyType, ['Joint family', 'Separated Family'], (v) => setState(() => _familyType = v)),
          _row([
            _drop('Father', _fatherAlive, ['Alive', 'Deceased'], (v) => setState(() => _fatherAlive = v)),
            _drop('Mother', _motherAlive, ['Alive', 'Deceased'], (v) => setState(() => _motherAlive = v)),
          ]),
          if (_fatherAlive.isNotEmpty) _subField('Father Occupation', _fatherOccCtrl),
          if (_motherAlive.isNotEmpty) _subField('Mother Occupation', _motherOccCtrl),
          _drop('Siblings', _hasSiblings, ['Yes', 'No'], (v) => setState(() => _hasSiblings = v)),
          if (_hasSiblings == 'Yes') ...[
            _subField('Brothers', _brothersCtrl, type: TextInputType.number),
            _subField('Sisters', _sistersCtrl, type: TextInputType.number),
          ],

          // ── EDUCATION ──
          _subHeader('Education'),
          _drop('Education Level (Highest)', _education, kEducations, (v) => setState(() => _education = v)),
          _subHeader('Degree'),
          _field('Title', _degreeTitleCtrl),
          _field('Institute', _instCtrl),
          _NewPhotoSlot(label: 'Degree Certificate', file: _degreeCert, onChanged: (f) => setState(() => _degreeCert = f)),
          _subHeader('Degree 2'),
          _field('Title', _degreeTitle2Ctrl),
          _field('Institute 2', _inst2Ctrl),
          _NewPhotoSlot(label: 'Degree 2 Certificate', file: _degreeCert2, onChanged: (f) => setState(() => _degreeCert2 = f)),
          _subHeader('Degree 3'),
          _field('Title', _degreeTitle3Ctrl),
          _field('Institute 3', _inst3Ctrl),
          _NewPhotoSlot(label: 'Degree 3 Certificate', file: _degreeCert3, onChanged: (f) => setState(() => _degreeCert3 = f)),

          // ── CAREER ──
          _subHeader('Career'),
          _drop('Monthly Income', _monthlyIncome, kMonthlyIncomes, (v) => setState(() => _monthlyIncome = v)),
          _drop('Employment Type', _empType, ['Full-time', 'Part-time', 'Self-employed', 'Business', 'Freelance', 'Not employed'],
              (v) => setState(() => _empType = v)),

          // ── PHYSICAL ──
          _subHeader('Physical'),
          _field('Weight (kg)', _weightCtrl, type: TextInputType.number),
          _drop('Complexion', _complexion, ['Fair', 'Wheatish', 'Brown', 'Dark'], (v) => setState(() => _complexion = v)),

          // ── RELIGION ──
          _subHeader('Religion'),
          _drop('Practice Level', _practiceLevel, ['High', 'Moderate', 'Low'], (v) => setState(() => _practiceLevel = v)),
          if (_gender == 'Female')
            _drop('Wears Hijab', _hijab, ['Yes', 'No', 'Sometimes'], (v) => setState(() => _hijab = v))
          else
            _drop('Has Beard', _beard, ['Yes', 'No', 'Trimmed'], (v) => setState(() => _beard = v)),

          // ── OTHER ASSETS ──
          _subHeader('Other Assets'),
          _drop('Has Car', _hasCar, ['Yes', 'No', 'Multiple'], (v) => setState(() => _hasCar = v)),
          _drop('Other Property', _hasOtherProperty, ['Yes', 'No'],
              (v) => setState(() { _hasOtherProperty = v; if (v == 'No') _otherProperty = ''; })),
          if (_hasOtherProperty == 'Yes')
            _drop('Property Type', _otherProperty, ['Residential', 'Commercial', 'Land', 'Multiple'], (v) => setState(() => _otherProperty = v)),

          // ── HEALTH ──
          _subHeader('Health'),
          _drop('Disability / Chronic Illness', _hasDisability, ['Yes', 'No'], (v) => setState(() => _hasDisability = v)),
          if (_hasDisability == 'Yes') _subField('Disability Details', _disabilityCtrl),
          _drop('Lifestyle', _physActive, ['Active Living', 'Sedentary Living', 'Balance'], (v) => setState(() => _physActive = v)),
          _drop('Smoker', _smokes, ['Yes', 'No'], (v) => setState(() => _smokes = v)),

          // ── ADMIN ──
          const SizedBox(height: 8),
          _mainHeader('Admin Notes'),
          _multiField('Internal notes (not shown to users)', _adminNotesCtrl),

          SizedBox(height: s.s(40)),
        ],
      ),
    );
  }

  // ── Field helpers (mirror admin_edit_user_screen.dart exactly) ────────────

  Widget _mainHeader(String title) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(top: s.s(28), bottom: s.s(12)),
      child: Row(children: [
        Container(width: s.d(3), height: s.d(16), decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(s.s(2)))),
        SizedBox(width: s.s(10)),
        Text(title, style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w800, color: Colors.white)),
      ]),
    );
  }

  Widget _subHeader(String title) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(top: s.s(20), bottom: s.s(8)),
      child: Text(title.toUpperCase(), style: TextStyle(fontSize: s.f(11), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.35), letterSpacing: 1.0)),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {TextInputType? type, List<TextInputFormatter>? formatters}) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(5)),
        TextField(
          controller: ctrl, keyboardType: type, inputFormatters: formatters,
          style: TextStyle(color: Colors.white, fontSize: s.f(13.5)),
          decoration: _inputDeco(),
        ),
      ]),
    );
  }

  Widget _phoneField(String label, TextEditingController ctrl, CountryCode country, ValueChanged<CountryCode> onCountryChanged, {bool required = true}) {
    return Padding(
      padding: EdgeInsets.only(bottom: _S.of(context).s(10)),
      child: PhoneField(label: label, required: required, controller: ctrl, selectedCountry: country, onCountryChanged: onCountryChanged),
    );
  }

  Widget _subField(String label, TextEditingController ctrl, {TextInputType? type}) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(left: s.s(16), bottom: s.s(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.only(top: s.s(12)), child: Text('↳ ', style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w700))),
        Expanded(child: _field(label, ctrl, type: type)),
      ]),
    );
  }

  Widget _subDrop(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(left: s.s(16), bottom: s.s(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.only(top: s.s(12)), child: Text('↳ ', style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w700))),
        Expanded(child: _drop(label, value, options, onChanged)),
      ]),
    );
  }

  Widget _row(List<Widget> children) {
    final s = _S.of(context);
    final items = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) items.add(SizedBox(width: s.s(10)));
      items.add(Expanded(child: children[i]));
    }
    return Padding(padding: EdgeInsets.only(bottom: s.s(10)), child: Row(children: items));
  }

  Widget _multiField(String label, TextEditingController ctrl, {int? maxLength}) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(5)),
        _MultiFieldWithCounter(ctrl: ctrl, maxLength: maxLength, inputDeco: _inputDeco(multiline: true)),
      ]),
    );
  }

  InputDecoration _inputDeco({bool multiline = false}) {
    final s = _S.of(context);
    return InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: s.s(12), vertical: multiline ? s.s(12) : s.s(10)),
      filled: true,
      fillColor: Colors.black.withOpacity(0.2),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: const BorderSide(color: kPurple)),
    );
  }

  Widget _drop(String label, String value, List<String> options, ValueChanged<String> onChanged, {String? infoText}) {
    final hasValue = value.isNotEmpty && options.contains(value);
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
          if (infoText != null) ...[
            SizedBox(width: s.s(5)),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: _kCard2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                  content: Text(infoText, style: TextStyle(fontSize: 13.5, color: Colors.white.withOpacity(0.7), height: 1.5)),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
                ),
              ),
              child: Icon(Icons.info_outline_rounded, color: Colors.white.withOpacity(0.4), size: s.d(15)),
            ),
          ],
        ]),
        SizedBox(height: s.s(5)),
        Container(
          padding: EdgeInsets.symmetric(horizontal: s.s(12)),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(10)), border: Border.all(color: Colors.white.withOpacity(0.1))),
          child: DropdownButton<String?>(
            value: hasValue ? value : null,
            isExpanded: true,
            dropdownColor: _kCard2,
            style: TextStyle(color: Colors.white, fontSize: s.f(13.5)),
            iconEnabledColor: Colors.white38,
            underline: const SizedBox(),
            hint: Text('Select...', style: TextStyle(color: Colors.white38, fontSize: s.f(13.5))),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(hasValue ? '— Clear —' : 'Select...', style: TextStyle(color: Colors.white38, fontSize: s.f(13.5)))),
              ...options.map((o) => DropdownMenuItem<String?>(value: o, child: Text(o, style: TextStyle(color: Colors.white, fontSize: s.f(13.5))))),
            ],
            onChanged: (v) => onChanged(v ?? ''),
          ),
        ),
      ]),
    );
  }

  Widget _cityPicker() {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: _AdminAddCityPicker(
        value: _city.isNotEmpty ? _city : null,
        onChanged: (v) { if (v != null) setState(() => _city = v); },
      ),
    );
  }
}

// ── City Picker (same searchable, province-grouped sheet as Edit Profile) ──
class _AdminAddCityPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _AdminAddCityPicker({required this.value, required this.onChanged});

  void _open(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _AdminAddCitySheet(
        selected: value,
        onSelect: (v) { onChanged(v); Navigator.pop(context); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final hasValue = value != null && value!.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('City', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
      SizedBox(height: s.s(5)),
      GestureDetector(
        onTap: () => _open(context),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(13)),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(10)), border: Border.all(color: Colors.white.withOpacity(0.1))),
          child: Row(children: [
            Expanded(child: Text(hasValue ? value! : 'Select city',
              style: TextStyle(fontSize: s.f(13.5), color: hasValue ? Colors.white : Colors.white38, fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400))),
            Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: s.d(22)),
          ]),
        ),
      ),
    ]);
  }
}

class _AdminAddCitySheet extends StatefulWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _AdminAddCitySheet({required this.selected, required this.onSelect});
  @override
  State<_AdminAddCitySheet> createState() => _AdminAddCitySheetState();
}

class _AdminAddCitySheetState extends State<_AdminAddCitySheet> {
  String _query = '';
  final _ctrl = TextEditingController();

  Map<String, List<String>> get _filtered {
    if (_query.isEmpty) return kCitiesGrouped;
    final q = _query.toLowerCase();
    final result = <String, List<String>>{};
    for (final entry in kCitiesGrouped.entries) {
      final matches = entry.value.where((v) => v.toLowerCase().contains(q)).toList();
      if (matches.isNotEmpty) result[entry.key] = matches;
    }
    return result;
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final filtered = _filtered;
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(color: Color(0xFF0F0D1A), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        SizedBox(height: s.s(10)),
        Container(width: s.d(40), height: s.d(4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(2)))),
        Padding(
          padding: EdgeInsets.fromLTRB(s.s(20), s.s(14), s.s(20), 0),
          child: Row(children: [
            Text('Select City', style: TextStyle(fontSize: s.f(17), fontWeight: FontWeight.w800, color: Colors.white)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(fontSize: s.f(13), color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w600))),
          ]),
        ),
        SizedBox(height: s.s(12)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: s.s(16)),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(2)),
            decoration: BoxDecoration(color: const Color(0xFF16132A), borderRadius: BorderRadius.circular(s.s(14)), border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: Row(children: [
              Icon(Icons.search_rounded, size: s.d(20), color: Colors.white.withOpacity(0.3)),
              SizedBox(width: s.s(8)),
              Expanded(child: TextField(
                controller: _ctrl,
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(fontSize: s.f(14), color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search city...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: s.f(14)),
                  border: InputBorder.none, isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: s.s(12)),
                ),
              )),
              if (_query.isNotEmpty)
                GestureDetector(onTap: () { _ctrl.clear(); setState(() => _query = ''); }, child: Icon(Icons.close_rounded, size: s.d(18), color: Colors.white.withOpacity(0.3))),
            ]),
          ),
        ),
        SizedBox(height: s.s(8)),
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text('No cities found', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: s.f(14))))
              : ListView(
                  padding: EdgeInsets.fromLTRB(s.s(16), s.s(4), s.s(16), s.s(24)),
                  children: [
                    for (final entry in filtered.entries) ...[
                      Padding(
                        padding: EdgeInsets.fromLTRB(s.s(4), s.s(12), s.s(4), s.s(6)),
                        child: Text(entry.key, style: TextStyle(fontSize: s.f(11), fontWeight: FontWeight.w700, color: kPurple.withOpacity(0.8), letterSpacing: 0.5)),
                      ),
                      ...entry.value.map((city) {
                        final isSel = city == widget.selected;
                        return GestureDetector(
                          onTap: () => widget.onSelect(city),
                          child: Container(
                            margin: EdgeInsets.only(bottom: s.s(4)),
                            padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(12)),
                            decoration: BoxDecoration(
                              color: isSel ? kPurple.withOpacity(0.15) : const Color(0xFF16132A),
                              borderRadius: BorderRadius.circular(s.s(12)),
                              border: Border.all(color: isSel ? kPurple.withOpacity(0.4) : Colors.white.withOpacity(0.06)),
                            ),
                            child: Row(children: [
                              Expanded(child: Text(city, style: TextStyle(fontSize: s.f(14), color: isSel ? kPurple : Colors.white.withOpacity(0.85), fontWeight: isSel ? FontWeight.w700 : FontWeight.w400))),
                              if (isSel) Icon(Icons.check_rounded, color: kPurple, size: s.d(18)),
                            ]),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
        ),
      ]),
    );
  }
}

// ── Multiline field with a live character counter ──────────────────────────
class _MultiFieldWithCounter extends StatefulWidget {
  final TextEditingController ctrl;
  final int? maxLength;
  final InputDecoration inputDeco;
  const _MultiFieldWithCounter({required this.ctrl, this.maxLength, required this.inputDeco});
  @override
  State<_MultiFieldWithCounter> createState() => _MultiFieldWithCounterState();
}

class _MultiFieldWithCounterState extends State<_MultiFieldWithCounter> {
  int _count = 0;
  @override
  void initState() { super.initState(); _count = widget.ctrl.text.length; widget.ctrl.addListener(_update); }
  void _update() { if (widget.maxLength != null && mounted) setState(() => _count = widget.ctrl.text.length); }
  @override
  void dispose() { widget.ctrl.removeListener(_update); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      TextField(
        controller: widget.ctrl,
        maxLines: 4,
        maxLength: widget.maxLength,
        maxLengthEnforcement: widget.maxLength != null ? MaxLengthEnforcement.enforced : null,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: widget.inputDeco.copyWith(counterText: '', contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 28)),
      ),
      if (widget.maxLength != null)
        Positioned(
          bottom: 8, right: 12,
          child: Text('$_count/${widget.maxLength}', style: TextStyle(fontSize: 10.5, color: _count == widget.maxLength ? kRose : Colors.white.withOpacity(0.35))),
        ),
    ]);
  }
}

// ── Height picker: two dropdowns (feet + inches) ────────────────────────────
class _HeightDropdowns extends StatefulWidget {
  final TextEditingController controller;
  final bool required;
  final bool darkTheme;
  final String label;
  const _HeightDropdowns({required this.controller, this.required = false, this.darkTheme = false, this.label = 'Height'});
  @override
  State<_HeightDropdowns> createState() => _HeightDropdownsState();
}

class _HeightDropdownsState extends State<_HeightDropdowns> {
  int? _feet;
  int? _inches;

  @override
  void initState() { super.initState(); _parseController(); widget.controller.addListener(_parseController); }

  void _parseController() {
    final text = widget.controller.text;
    final m = RegExp(r"(\d+)'(\d+)").firstMatch(text);
    if (m != null) {
      final f = int.parse(m.group(1)!);
      final i = int.parse(m.group(2)!);
      if (f != _feet || i != _inches) {
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() { _feet = f; _inches = i; }); });
      }
    }
  }

  void _update(int? feet, int? inches) {
    setState(() { _feet = feet; _inches = inches; });
    if (feet != null && inches != null) {
      final formatted = "$feet'$inches\"";
      if (widget.controller.text != formatted) widget.controller.text = formatted;
    } else if (widget.controller.text.isNotEmpty) {
      widget.controller.clear();
    }
  }

  @override
  void dispose() { widget.controller.removeListener(_parseController); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final labelColor = widget.darkTheme ? Colors.white.withOpacity(0.5) : const Color(0xFF6B6893);
    final textColor = widget.darkTheme ? Colors.white : const Color(0xFF1A1830);
    final fillColor = widget.darkTheme ? Colors.black.withOpacity(0.2) : Colors.white;
    final borderColor = widget.darkTheme ? Colors.white.withOpacity(0.12) : const Color(0xFFE8E6F5);

    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: labelColor, fontSize: s.f(13)),
      filled: true, fillColor: fillColor, isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: s.s(10), vertical: s.s(10)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide(color: borderColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide(color: borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: const BorderSide(color: Color(0xFF534AB7), width: 1.5)),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.required ? '${widget.label} *' : widget.label, style: TextStyle(fontSize: s.f(12.5), fontWeight: FontWeight.w700, color: labelColor)),
      SizedBox(height: s.s(6)),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            value: _feet,
            hint: Text('Feet', style: TextStyle(color: labelColor, fontSize: s.f(13))),
            style: TextStyle(color: textColor, fontSize: s.f(13.5), fontWeight: FontWeight.w500),
            dropdownColor: widget.darkTheme ? const Color(0xFF1E1A33) : Colors.white,
            icon: Icon(Icons.expand_more_rounded, size: s.d(18), color: labelColor),
            decoration: deco('ft'),
            items: List.generate(4, (i) => i + 4).map((f) => DropdownMenuItem(value: f, child: Text("$f ft", style: TextStyle(color: textColor, fontSize: s.f(13.5))))).toList(),
            onChanged: (v) => _update(v, _inches),
          ),
        ),
        SizedBox(width: s.s(10)),
        Expanded(
          child: DropdownButtonFormField<int>(
            value: _inches,
            hint: Text('Inches', style: TextStyle(color: labelColor, fontSize: s.f(13))),
            style: TextStyle(color: textColor, fontSize: s.f(13.5), fontWeight: FontWeight.w500),
            dropdownColor: widget.darkTheme ? const Color(0xFF1E1A33) : Colors.white,
            icon: Icon(Icons.expand_more_rounded, size: s.d(18), color: labelColor),
            decoration: deco('in'),
            items: List.generate(12, (i) => i).map((i) => DropdownMenuItem(value: i, child: Text('$i in', style: TextStyle(color: textColor, fontSize: s.f(13.5))))).toList(),
            onChanged: (v) => _update(_feet, v),
          ),
        ),
      ]),
    ]);
  }
}

// ── Photo slot for the Add flow ─────────────────────────────────────────────
// Unlike Edit Profile's _EditablePhotoSlot (which uploads immediately on
// pick, since an existing row/id already exists to attach the photo to),
// this holds the picked file locally and defers the actual upload until
// Save — there's no row to attach a photo to until the new profile is
// actually inserted. addUserWithPhotos() (already built, previously unused)
// handles that insert-then-upload sequencing atomically.
class _NewPhotoSlot extends StatelessWidget {
  final String label;
  final File? file;
  final bool crop;
  final ValueChanged<File?> onChanged;
  const _NewPhotoSlot({required this.label, required this.file, required this.onChanged, this.crop = false});

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 75, maxWidth: 800);
    if (picked == null) return;
    if (crop) {
      final bytes = await picked.readAsBytes();
      if (!context.mounted) return;
      final cropped = await showPhotoCropDialog(context, bytes);
      if (cropped == null) return;
      final tempPath = '${picked.path}_cropped.jpg';
      final tempFile = await File(tempPath).writeAsBytes(cropped);
      onChanged(tempFile);
    } else {
      onChanged(File(picked.path));
    }
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _kCard2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.camera_alt_rounded, color: kPurple),
          title: const Text('Take Photo', style: TextStyle(color: Colors.white)),
          onTap: () { Navigator.pop(sheetCtx); _pick(context, ImageSource.camera); },
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_rounded, color: kPurple),
          title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
          onTap: () { Navigator.pop(sheetCtx); _pick(context, ImageSource.gallery); },
        ),
        if (file != null)
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: kRose),
            title: const Text('Remove Photo', style: TextStyle(color: kRose)),
            onTap: () { Navigator.pop(sheetCtx); onChanged(null); },
          ),
        const SizedBox(height: 8),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null;
    return GestureDetector(
      onTap: () => _showOptions(context),
      child: Builder(builder: (context) {
        final s = _S.of(context);
        return Container(
          height: s.d(88),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(s.s(12)),
            border: Border.all(color: hasImage ? kPurple.withOpacity(0.5) : Colors.white.withOpacity(0.1), width: hasImage ? 1.5 : 1),
          ),
          child: hasImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(s.s(11)),
                  child: Stack(fit: StackFit.expand, children: [
                    Image.file(file!, fit: BoxFit.cover),
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: s.s(4)),
                        color: Colors.black.withOpacity(0.5),
                        child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: s.f(9), color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    Positioned(
                      top: s.s(4), right: s.s(4),
                      child: Container(
                        padding: EdgeInsets.all(s.s(3)),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(s.s(6))),
                        child: Icon(Icons.edit_rounded, size: s.d(12), color: Colors.white),
                      ),
                    ),
                  ]),
                )
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.add_photo_alternate_rounded, size: s.d(26), color: Colors.white.withOpacity(0.3)),
                  SizedBox(height: s.s(4)),
                  Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: s.f(10.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.3))),
                  Text('Tap to add', textAlign: TextAlign.center, style: TextStyle(fontSize: s.f(9), color: Colors.white.withOpacity(0.2))),
                ]),
        );
      }),
    );
  }
}
