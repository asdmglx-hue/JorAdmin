import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const _kBg2    = Color(0xFF16132A);
const _kCard2  = Color(0xFF1E1A33);
const _kBdr2   = Color(0xFF2D2847);

const kCastes2 = ['Syed','Sheikh','Mughal','Pathan','Rajput','Arain','Awan','Butt','Chaudhry','Gujjar','Jutt','Malik','Qureshi','Ansari','Other'];
const kSects2  = ['Sunni','Shia','Deobandi','Barelvi','Ahl-e-Hadith','Other'];
const kEdus2   = ["Matric","Intermediate","Bachelor's","Master's","MPhil","PhD","Hafiz","Other"];
const kMonthlyIncomes2 = ['Under 20k','20k-40k','40k-70k','70k-100k','100k-150k','150k-200k','200k+'];
const kPakCities2 = ['Karachi','Lahore','Islamabad','Rawalpindi','Faisalabad','Multan','Peshawar','Quetta','Sialkot','Gujranwala','Hyderabad','Bahawalpur','Sargodha','Sukkur','Larkana','Sheikhupura','Jhang','Rahim Yar Khan','Gujrat','Abbottabad','Mardan','Kasur','Okara','Sahiwal','Mirpur Khas','Other'];

class AdminAddUserScreen extends StatefulWidget {
  final AdminService svc;
  const AdminAddUserScreen({super.key, required this.svc});
  @override
  State<AdminAddUserScreen> createState() => _AdminAddUserScreenState();
}

class _AdminAddUserScreenState extends State<AdminAddUserScreen> {
  bool _saving = false;

  final _nameCtrl      = TextEditingController();
  final _ageCtrl       = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _cnicCtrl      = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  final _heightCtrl    = TextEditingController();
  final _weightCtrl    = TextEditingController();
  final _aboutCtrl        = TextEditingController();
  final _lookingForCtrl  = TextEditingController();
  final _instCtrl      = TextEditingController();
  final _degreeTitleCtrl = TextEditingController();
  final _profCtrl      = TextEditingController();
  final _brothersCtrl  = TextEditingController();
  final _sistersCtrl   = TextEditingController();
  final _locationCtrl  = TextEditingController();
  final _countryCtrl   = TextEditingController();
  final _houseSizeCtrl = TextEditingController();
  final _carCtrl       = TextEditingController();
  final _boysCtrl      = TextEditingController();
  final _girlsCtrl     = TextEditingController();
  final _fatherOccCtrl = TextEditingController();
  final _motherOccCtrl = TextEditingController();
  final _disabilityCtrl= TextEditingController();
  final _adminNotesCtrl= TextEditingController();

  String _gender        = '';
  String _city          = '';
  String _caste         = '';
  String _sect          = '';
  String? _language;
  String _education     = '';
  String _maritalStatus = '';
  String _homeType      = '';
  String _hasCar        = '';
  String _hasOtherProperty = '';
  String _otherProperty = '';
  String _fatherAlive   = '';
  String _motherAlive   = '';
  String _hasSiblings   = '';
  String _hasDisability = '';
  String _practiceLevel = '';
  String _hijab         = '';
  String _beard         = '';
  String _physActive    = '';
  String _complexion    = '';
  String _empType       = '';
  String _monthlyIncome = '';
  String _hasKids       = '';

  @override
  void dispose() {
    for (final c in [_nameCtrl,_ageCtrl,_phoneCtrl,_cnicCtrl,_passwordCtrl,_heightCtrl,_weightCtrl,_aboutCtrl,_lookingForCtrl,_instCtrl,_degreeTitleCtrl,_profCtrl,_brothersCtrl,_sistersCtrl,_locationCtrl,_countryCtrl,_houseSizeCtrl,_carCtrl,_boysCtrl,_girlsCtrl,_fatherOccCtrl,_motherOccCtrl,_disabilityCtrl,_adminNotesCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) { _err('Name is required'); return; }
    if (_ageCtrl.text.trim().isEmpty)  { _err('Age is required');  return; }
    if (_phoneCtrl.text.trim().isEmpty){ _err('Phone is required'); return; }
    if (_gender.isEmpty)               { _err('Gender is required'); return; }
    setState(() => _saving = true);
    try {
      double heightInches = 65;
      final hm = RegExp(r"(\d+)'(\d+)").firstMatch(_heightCtrl.text.trim());
      if (hm != null) heightInches = double.parse(hm.group(1)!)*12+double.parse(hm.group(2)!);
      else heightInches = double.tryParse(_heightCtrl.text.trim()) ?? 65;

      final data = <String, dynamic>{
        'name'           : _nameCtrl.text.trim(),
        'age'            : int.tryParse(_ageCtrl.text.trim()) ?? 0,
        'gender'         : _gender,
        'contact_phone'  : _phoneCtrl.text.trim(),
        if (_cnicCtrl.text.trim().isNotEmpty)     'cnic'             : _cnicCtrl.text.trim(),
        if (_passwordCtrl.text.trim().isNotEmpty) 'password'         : _passwordCtrl.text.trim(),
        'height_inches'  : heightInches,
        if (_weightCtrl.text.trim().isNotEmpty)   'weight_kg'        : double.tryParse(_weightCtrl.text.trim()),
        if (_city.isNotEmpty)          'city'             : _city,
        if (_caste.isNotEmpty)         'caste'            : _caste,
        if (_sect.isNotEmpty)          'sect'             : _sect,
        if (_language != null && _language!.isNotEmpty) 'languages': [_language!],
        if (_education.isNotEmpty)     'education'        : _education,
        if (_instCtrl.text.trim().isNotEmpty)     'institute'        : _instCtrl.text.trim(),
        if (_degreeTitleCtrl.text.trim().isNotEmpty) 'degree_title'  : _degreeTitleCtrl.text.trim(),
        if (_profCtrl.text.trim().isNotEmpty)     'profession'       : _profCtrl.text.trim(),
        if (_maritalStatus.isNotEmpty) 'marital_status'   : _maritalStatus,
        if (_homeType.isNotEmpty)      'home_type'        : _homeType,
        if (_houseSizeCtrl.text.trim().isNotEmpty) 'house_size'      : _houseSizeCtrl.text.trim(),
        if (_locationCtrl.text.trim().isNotEmpty) 'location'         : _locationCtrl.text.trim(),
        if (_countryCtrl.text.trim().isNotEmpty)  'country'          : _countryCtrl.text.trim(),
        if (_hasCar.isNotEmpty)        'has_car'          : _hasCar,
        if (_carCtrl.text.trim().isNotEmpty)      'car_name'         : _carCtrl.text.trim(),
        if (_hasOtherProperty.isNotEmpty) 'has_other_property': _hasOtherProperty,
        if (_otherProperty.isNotEmpty && _hasOtherProperty == 'Yes') 'other_property': _otherProperty,
        if (_fatherAlive.isNotEmpty)   'father_alive'     : _fatherAlive == 'Alive',
        if (_fatherOccCtrl.text.trim().isNotEmpty) 'father_occupation': _fatherOccCtrl.text.trim(),
        if (_motherAlive.isNotEmpty)   'mother_alive'     : _motherAlive == 'Alive',
        if (_motherOccCtrl.text.trim().isNotEmpty) 'mother_occupation': _motherOccCtrl.text.trim(),
        if (_hasSiblings.isNotEmpty)   'has_siblings'     : _hasSiblings == 'Yes',
        if (_brothersCtrl.text.trim().isNotEmpty) 'brothers'         : int.tryParse(_brothersCtrl.text.trim()),
        if (_sistersCtrl.text.trim().isNotEmpty)  'sisters'          : int.tryParse(_sistersCtrl.text.trim()),
        if (_hasKids.isNotEmpty)       'has_kids'         : _hasKids == 'Yes',
        if (_boysCtrl.text.trim().isNotEmpty)     'boys'             : int.tryParse(_boysCtrl.text.trim()),
        if (_girlsCtrl.text.trim().isNotEmpty)    'girls'            : int.tryParse(_girlsCtrl.text.trim()),
        if (_practiceLevel.isNotEmpty) 'practice_level'   : _practiceLevel,
        if (_hijab.isNotEmpty)         'hijab'            : _hijab,
        if (_beard.isNotEmpty)         'beard'            : _beard,
        if (_complexion.isNotEmpty)    'complexion'       : _complexion,
        if (_empType.isNotEmpty)       'employment_type'  : _empType,
        if (_monthlyIncome.isNotEmpty) 'salary_start'     : _monthlyIncome,
        if (_physActive.isNotEmpty)    'physically_active': _physActive,
        if (_hasDisability.isNotEmpty) 'has_disability'   : _hasDisability,
        if (_disabilityCtrl.text.trim().isNotEmpty) 'disability_details': _disabilityCtrl.text.trim(),
        if (_aboutCtrl.text.trim().isNotEmpty)    'about'            : _aboutCtrl.text.trim(),
        if (_lookingForCtrl.text.trim().isNotEmpty) 'looking_for'      : _lookingForCtrl.text.trim(),
        if (_adminNotesCtrl.text.trim().isNotEmpty) 'admin_notes'    : _adminNotesCtrl.text.trim(),
        'status'         : 'pending',
        'posted_at'      : DateTime.now().toIso8601String(),
      };

      await widget.svc.addUser(data);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Profile created successfully'),
        backgroundColor: kGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(milliseconds: 2500),
      ));
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

          // ── BASIC ──
          _hdr('Basic Information'),
          _field('Full Name *', _nameCtrl),
          _row2([_field('Age *', _ageCtrl, type: TextInputType.number), _field('Height (5\'6")', _heightCtrl)]),
          _field('Phone Number *', _phoneCtrl, type: TextInputType.phone),
          _field('CNIC Number', _cnicCtrl, type: TextInputType.number),
          _field('Password', _passwordCtrl),
          _drop('Gender *', _gender, ['Male','Female'], (v) => setState(() => _gender = v)),
          _field('Country', _countryCtrl),
          _drop('City', _city, kPakCities2, (v) => setState(() => _city = v)),
          _drop('Caste', _caste, kCastes2, (v) => setState(() => _caste = v)),
          _drop('Sect / Maslak', _sect, kSects2, (v) => setState(() => _sect = v)),
          _drop('Native Language', _language ?? '', kLanguages, (v) => setState(() => _language = v.isEmpty ? null : v)),
          _field('Occupation', _profCtrl),
          _drop('Marital Status', _maritalStatus, ['Never Married','Married','Divorced','Khula','Widowed'], (v) => setState(() => _maritalStatus = v)),
          if (_maritalStatus == 'Married') ...[
            _drop('Has Kids', _hasKids, ['Yes','No'], (v) => setState(() => _hasKids = v)),
            if (_hasKids == 'Yes') _row2([_subField('Boys', _boysCtrl, type: TextInputType.number), _subField('Girls', _girlsCtrl, type: TextInputType.number)]),
          ],

          // ── HOME ──
          _hdr('Home & Property'),
          _drop('House', _homeType, ['Own House','Rented House'], (v) => setState(() => _homeType = v)),
          if (_homeType.isNotEmpty) ...[
            _subField('Location', _locationCtrl),
            _subField('House Size', _houseSizeCtrl),
          ],
          _drop('Has Car', _hasCar, ['Yes','No','Multiple'], (v) => setState(() => _hasCar = v)),

          _drop('Other Property', _hasOtherProperty, ['Yes','No'], (v) => setState(() { _hasOtherProperty = v; if (v == 'No') _otherProperty = ''; })),
          if (_hasOtherProperty == 'Yes') _drop('Property Type', _otherProperty, ['Residential','Commercial','Land','Multiple'], (v) => setState(() => _otherProperty = v)),

          // ── FAMILY ──
          _hdr('Family'),
          _row2([
            _drop('Father', _fatherAlive, ['Alive','Deceased'], (v) => setState(() => _fatherAlive = v)),
            _drop('Mother', _motherAlive, ['Alive','Deceased'], (v) => setState(() => _motherAlive = v)),
          ]),
          if (_fatherAlive.isNotEmpty) _subField('Father Occupation', _fatherOccCtrl),
          if (_motherAlive.isNotEmpty) _subField('Mother Occupation', _motherOccCtrl),
          _drop('Has Siblings', _hasSiblings, ['Yes','No'], (v) => setState(() => _hasSiblings = v)),
          if (_hasSiblings == 'Yes') _row2([
            _subField('Brothers', _brothersCtrl, type: TextInputType.number),
            _subField('Sisters', _sistersCtrl, type: TextInputType.number),
          ]),

          // ── EDUCATION ──
          _hdr('Education'),
          _drop('Education Level (Highest)', _education, kEdus2, (v) => setState(() => _education = v)),
          if (_education.isNotEmpty) ...[
            if (["Bachelor's","Master's","MPhil","PhD","Other"].contains(_education)) _subField('Degree Title', _degreeTitleCtrl),
            _subField('Institute', _instCtrl),
          ],

          // ── CAREER ──
          _hdr('Career'),
          _drop('Monthly Income', _monthlyIncome, kMonthlyIncomes2, (v) => setState(() => _monthlyIncome = v)),
          _drop('Employment Type', _empType, ['Full-time','Part-time','Self-employed','Business','Freelance','Not employed'], (v) => setState(() => _empType = v)),

          // ── PHYSICAL ──
          _hdr('Physical'),
          _row2([_field('Weight (kg)', _weightCtrl, type: TextInputType.number), _drop2('Complexion', _complexion, ['Fair','Wheatish','Brown','Dark'], (v) => setState(() => _complexion = v))]),

          // ── RELIGION ──
          _hdr('Religion'),
          _drop('Practice Level', _practiceLevel, ['High','Moderate','Low'], (v) => setState(() => _practiceLevel = v)),
          if (_gender == 'Female')
            _drop('Wears Hijab', _hijab, ['Yes','No','Sometimes'], (v) => setState(() => _hijab = v))
          else if (_gender == 'Male')
            _drop('Has Beard', _beard, ['Yes','No','Trimmed'], (v) => setState(() => _beard = v)),

          // ── HEALTH ──
          _hdr('Health'),
          _drop('Lifestyle', _physActive, ['Active Living','Sedentary Living','Moderately Active'], (v) => setState(() => _physActive = v)),
          _drop('Disability / Chronic Illness', _hasDisability, ['Yes','No'], (v) => setState(() => _hasDisability = v)),
          if (_hasDisability == 'Yes') _subField('Disability Details', _disabilityCtrl),

          // ── ABOUT ──
          _hdr('About'),
          _multi('About Yourself', _aboutCtrl, maxLength: 200),
          const SizedBox(height: 12),
          _multi('Looking For', _lookingForCtrl, maxLength: 200),

          // ── ADMIN ──
          _hdr('Admin Notes'),
          _multi('Internal notes (not shown to users)', _adminNotesCtrl),

          SizedBox(height: _S.of(context).s(40)),
        ],
      ),
    );
  }

  Widget _multiSelect(String label, List<String> selected, List<String> options, ValueChanged<List<String>> onChanged) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(8)),
        Wrap(spacing: s.s(8), runSpacing: s.s(8), children: options.map((opt) {
          final sel = selected.contains(opt);
          return GestureDetector(
            onTap: () { final u = List<String>.from(selected); if (sel) u.remove(opt); else u.add(opt); onChanged(u); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(horizontal: s.s(16), vertical: s.s(9)),
              decoration: BoxDecoration(
                color: sel ? kPurpleLight : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(s.s(30)),
                border: Border.all(color: sel ? kPurple : const Color(0xFFDDDDEE).withOpacity(0.3), width: sel ? 1.5 : 1),
              ),
              child: Text(opt, style: TextStyle(
                fontSize: s.f(13),
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel ? kPurple : Colors.white70,
              )),
            ),
          );
        }).toList()),
      ]),
    );
  }

  Widget _hdr(String t) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(0, s.s(20), 0, s.s(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: TextStyle(fontSize: s.f(11), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.5), letterSpacing: 0.8)),
        SizedBox(height: s.s(6)),
        Divider(color: Colors.white.withOpacity(0.08), height: 1),
      ]),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {TextInputType? type}) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: s.f(11.5), color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(4)),
        TextField(
          controller: ctrl, keyboardType: type,
          style: TextStyle(fontSize: s.f(14), color: Colors.white),
          decoration: _inputDec(),
        ),
      ]),
    );
  }

  Widget _subField(String label, TextEditingController ctrl, {TextInputType? type}) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(left: s.s(12)),
      child: _field(label, ctrl, type: type),
    );
  }

  Widget _multi(String label, TextEditingController ctrl, {int? maxLength}) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: s.f(11.5), color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(4)),
        TextField(controller: ctrl, maxLines: 4, maxLength: maxLength, style: TextStyle(fontSize: s.f(14), color: Colors.white), decoration: _inputDec()),
      ]),
    );
  }

  Widget _drop(String label, String value, List<String> opts, void Function(String) cb) {
    final s = _S.of(context);
    final hasValue = value.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: s.f(11.5), color: Colors.white.withOpacity(0.5)))),
          if (hasValue)
            GestureDetector(
              onTap: () { setState(() { cb(''); }); },
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Icon(Icons.close_rounded, size: 14, color: kRose),
              ),
            ),
        ]),
        SizedBox(height: s.s(4)),
        GestureDetector(
          onTap: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: _kCard2,
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
                    if (hasValue) GestureDetector(
                      onTap: () { Navigator.pop(context); cb(''); },
                      child: const Text('Clear', style: TextStyle(color: kRose, fontSize: 13)),
                    ),
                  ]),
                ),
                const Divider(color: Colors.white12, height: 1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(shrinkWrap: true, children: opts.map((o) => ListTile(
                    title: Text(o, style: TextStyle(color: o == value ? kPurple : Colors.white, fontSize: 14, fontWeight: o == value ? FontWeight.w700 : FontWeight.w400)),
                    trailing: o == value ? const Icon(Icons.check_rounded, color: kPurple, size: 18) : null,
                    onTap: () { Navigator.pop(context); cb(o); },
                  )).toList()),
                ),
                SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
              ]),
            );
          },
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s.s(12), vertical: s.s(13)),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(s.s(10)),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(children: [
              Expanded(
                child: Text(
                  hasValue ? value : 'Select',
                  style: TextStyle(
                    color: hasValue ? Colors.white : Colors.white.withOpacity(0.3),
                    fontSize: s.f(14),
                  ),
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: s.d(18)),
            ]),
          ),
        ),
      ]),
    );
  }

  // inline drop for row usage
  Widget _drop2(String label, String value, List<String> opts, void Function(String) cb) => _drop(label, value, opts, cb);

  Widget _row2(List<Widget> children) {
    final s = _S.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children.map((c) => Expanded(child: Padding(padding: EdgeInsets.only(right: s.s(8)), child: c))).toList(),
    );
  }

  InputDecoration _inputDec() {
    final s = _S.of(context);
    return InputDecoration(
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      contentPadding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(12)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: const BorderSide(color: kPurple)),
    );
  }
}
