import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/photo_crop_dialog.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../services/admin_service.dart';
import '../models/admin_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../models/admin_permissions.dart';
import '../services/admin_supabase_extension.dart';
import '../widgets/country_picker.dart';
import '../widgets/occupation_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';

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

// ── Formatters (mirrors the Submit Proposal form in the user app, so
//    admin-entered numbers/CNICs look and behave the same way) ─────────────

// Same dash placement as the Submit Proposal form's CNIC field: XXXXX-XXXXXXX-X.
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

// Re-applies the CNIC formatter to a value that was set directly on a
// controller (e.g. existing data loaded on screen open), so it looks
// correctly formatted immediately rather than only after the admin edits it.
// Public (no leading underscore) since admin_users_screen.dart's user list
// also needs this same display-time formatting — the cnic column itself is
// always stored as clean digits (enforced by a database trigger), so every
// place that shows it to a human needs to format it, not just this screen.
String formatCnicDisplay(String raw) =>
    _AdminCnicFormatter().formatEditUpdate(const TextEditingValue(text: ''), TextEditingValue(text: raw)).text;

// Re-applies the same Pakistani spacing used on the Submit Proposal form to
// a phone value set directly on a controller, so it displays correctly the
// moment the screen opens.
String _formatPakDisplay(String raw) =>
    PakistaniPhoneFormatter().formatEditUpdate(const TextEditingValue(text: ''), TextEditingValue(text: raw)).text;


class AdminEditUserScreen extends StatefulWidget {
  final AdminUser user;
  final AdminService svc;
  final bool readOnly;
  const AdminEditUserScreen({super.key, required this.user, required this.svc, this.readOnly = false});

  @override
  State<AdminEditUserScreen> createState() => _AdminEditUserScreenState();
}

class _AdminEditUserScreenState extends State<AdminEditUserScreen> {
  late AdminUser _user;
  late AdminUser _baseline; // what we compare against for _hasChanges
  bool _fullDataLoaded = false;
  RealtimeChannel? _proposalSub; // true once background full-row fetch completes

  // Country code for the phone fields (mirrors the Submit Proposal form's
  // country picker in the user app).
  CountryCode _selectedCountry = CountryCode.pakistan;
  CountryCode _selectedCountry2 = CountryCode.pakistan;

  // Text controllers
  late TextEditingController _nameCtrl;
  late TextEditingController _ageCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _phone2Ctrl;
  late TextEditingController _cnicCtrl;
  late TextEditingController _passwordCtrl;
  late TextEditingController _heightCtrl;
  late TextEditingController _weightCtrl;
  late TextEditingController _aboutCtrl;
  late TextEditingController _lookingForCtrl;
  late TextEditingController _instCtrl;
  late TextEditingController _degreeTitleCtrl;
  late TextEditingController _inst2Ctrl;
  late TextEditingController _degreeTitle2Ctrl;
  late TextEditingController _inst3Ctrl;
  late TextEditingController _degreeTitle3Ctrl;
  late TextEditingController _boysCtrl;
  late TextEditingController _girlsCtrl;
  late TextEditingController _houseSizeCtrl;
  late TextEditingController _carCtrl;
  late TextEditingController _brothersCtrl;
  late TextEditingController _sistersCtrl;
  late TextEditingController _adminNotesCtrl;
  late TextEditingController _locationCtrl;
  late TextEditingController _countryCtrl;
  late TextEditingController _disabilityDetailsCtrl;
  late TextEditingController _professionCtrl;
  late TextEditingController _professionCustomCtrl; // used when Other is picked
  late String _professionCategory; // tracks picked category
  late TextEditingController _fatherOccCtrl;
  late TextEditingController _motherOccCtrl;

  // True while a photo removal is mid-write. Blocks the realtime-driven
  // refresh from re-merging the photo back in before all three places are
  // cleared. See _onPhotoChanged.
  bool _photoOpInFlight = false;

  // Local string vars for subfield visibility (mirrors _user fields)
  late String _siblingsVal;
  late String _houseVal;
  late String _fatherVal;
  late String _motherVal;
  late String _disabilityVal;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _baseline = widget.user;
    _refreshCnicStatus();
    // Subscribe to realtime changes on this specific proposal row so that
    // docs submitted via Verify Now (website or app) appear immediately
    // without the admin needing to close and reopen the edit screen.
    final userId = widget.user.id;
    _proposalSub = SupabaseService.instance.client
        .channel('edit_screen_proposal_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'proposals',
          callback: (payload) {
            final id = payload.newRecord['id'] as String?;
            if (id == userId) _refreshCnicStatus();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'cnic_verification_requests',
          callback: (payload) {
            final id = payload.newRecord['proposal_id'] as String?;
            if (id == userId) _refreshCnicStatus();
          },
        )
        .subscribe();
    _nameCtrl     = TextEditingController(text: _user.name);
    _ageCtrl      = TextEditingController(text: _user.age.toString());
    // Phone numbers may be stored as "{dialCode} {digits}" (numbers that
    // came through the Submit Proposal form) or as a bare local number
    // (older admin-entered data). Split off a leading dial code when present
    // so the country selector shows the right flag instead of always
    // defaulting to Pakistan.
    final phoneRaw = _user.contactPhone.trim();
    final phoneSpace = phoneRaw.indexOf(' ');
    if (phoneSpace > 0) {
      final matched = countryCodeForDial(phoneRaw.substring(0, phoneSpace));
      if (matched != null) _selectedCountry = matched;
      _phoneCtrl = TextEditingController(text: phoneRaw.substring(phoneSpace + 1).trim());
    } else {
      _phoneCtrl = TextEditingController(text: phoneRaw);
    }
    if (_selectedCountry.dialCode == '+92') _phoneCtrl.text = _formatPakDisplay(_phoneCtrl.text);

    final phone2Raw = (_user.contactPhone2 ?? '').trim();
    final phone2Space = phone2Raw.indexOf(' ');
    if (phone2Space > 0) {
      final matched2 = countryCodeForDial(phone2Raw.substring(0, phone2Space));
      if (matched2 != null) _selectedCountry2 = matched2;
      _phone2Ctrl = TextEditingController(text: phone2Raw.substring(phone2Space + 1).trim());
    } else {
      _phone2Ctrl = TextEditingController(text: phone2Raw);
    }
    if (_selectedCountry2.dialCode == '+92') _phone2Ctrl.text = _formatPakDisplay(_phone2Ctrl.text);

    _cnicCtrl     = TextEditingController(text: formatCnicDisplay(_user.cnic ?? ''));
    _passwordCtrl = TextEditingController(text: _user.password ?? '');
    // Height: store inches internally, display as feet/inches in read-only
    final h = _user.heightInches.round();
    final ft = h ~/ 12; final inch = h % 12;
    _heightCtrl   = TextEditingController(text: '$ft\'$inch"');
    _weightCtrl   = TextEditingController(text: _user.weightKg?.toString() ?? '');
    _aboutCtrl       = TextEditingController(text: _user.about ?? '');
    _lookingForCtrl  = TextEditingController(text: _user.lookingFor ?? '');
    _instCtrl     = TextEditingController(text: _user.institute ?? '');
    _degreeTitleCtrl = TextEditingController(text: _user.degreeTitle ?? '');
    _inst2Ctrl    = TextEditingController(text: _user.institute2 ?? '');
    _degreeTitle2Ctrl = TextEditingController(text: _user.degreeTitle2 ?? '');
    _inst3Ctrl    = TextEditingController(text: _user.institute3 ?? '');
    _degreeTitle3Ctrl = TextEditingController(text: _user.degreeTitle3 ?? '');
    _boysCtrl     = TextEditingController(text: _user.boys?.toString() ?? '');
    _girlsCtrl    = TextEditingController(text: _user.girls?.toString() ?? '');
    _houseSizeCtrl = TextEditingController(text: _user.houseSize ?? '');
    _carCtrl      = TextEditingController(text: _user.carName ?? '');
    _brothersCtrl = TextEditingController(text: (_user.brothers == 0 || _user.brothers == null) ? '' : _user.brothers.toString());
    _sistersCtrl  = TextEditingController(text: (_user.sisters == 0 || _user.sisters == null) ? '' : _user.sisters.toString());
    _adminNotesCtrl  = TextEditingController(text: _user.adminNotes ?? '');
    _locationCtrl = TextEditingController(text: _user.location ?? '');
    _countryCtrl = TextEditingController(text: _user.country ?? '');
    _disabilityDetailsCtrl = TextEditingController(text: _user.disabilityDetails ?? '');
    _professionCtrl   = TextEditingController(text: _user.profession);
    // If the stored profession is 'Other' (free-typed), pre-fill the custom
    // controller and set the category from the stored professionCategory.
    // Otherwise the picker will restore the grouped selection correctly.
    final _isOther = !SupabaseService.instance.occupationsGrouped.values
        .expand((v) => v).contains(_user.profession) && _user.profession.isNotEmpty;
    _professionCustomCtrl = TextEditingController(
        text: _isOther ? _user.profession : '');
    _professionCategory   = _user.professionCategory ?? '';
    _fatherOccCtrl    = TextEditingController(text: _user.fatherOccupation ?? '');
    _motherOccCtrl    = TextEditingController(text: _user.motherOccupation ?? '');
    _siblingsVal  = _user.hasSiblings == true ? 'Yes' : (_user.hasSiblings == false ? 'No' : '');
    _houseVal     = _user.homeType ?? '';
    _fatherVal    = _user.fatherAlive == true ? 'Alive' : (_user.fatherAlive == false ? 'Deceased' : '');
    _motherVal    = _user.motherAlive == true ? 'Alive' : (_user.motherAlive == false ? 'Deceased' : '');
    _disabilityVal = _user.hasDisability ?? '';

    for (final c in [
      _nameCtrl, _ageCtrl, _phoneCtrl, _phone2Ctrl, _cnicCtrl, _passwordCtrl, _heightCtrl, _weightCtrl,
      _aboutCtrl, _lookingForCtrl, _instCtrl, _degreeTitleCtrl, _inst2Ctrl, _degreeTitle2Ctrl,
      _inst3Ctrl, _degreeTitle3Ctrl, _boysCtrl, _girlsCtrl, _houseSizeCtrl, _carCtrl,
      _brothersCtrl, _sistersCtrl,
      _adminNotesCtrl, _locationCtrl, _disabilityDetailsCtrl, _countryCtrl,
      _professionCtrl, _professionCustomCtrl, _fatherOccCtrl, _motherOccCtrl,
    ]) { c.addListener(_onFieldChanged); }
  }

  // The AdminUser object this screen opens with (widget.user) can be
  // stale — it's whatever the Users list had cached at the moment it was
  // fetched, which may be from before a CNIC verification request got
  // approved elsewhere (the Verify tab). That approval updates the
  // database correctly and immediately, but this screen wouldn't know
  // until now. Rather than restructure the whole (synchronous,
  // controller-heavy) initState into an async-loading screen just for
  // this, this quietly re-fetches in the background and patches in just
  // the CNIC fields once they arrive — everything else the person may
  // already be mid-editing stays untouched.
  Future<void> _refreshCnicStatus({bool force = false}) async {
    // A photo removal writes to proposals, which bounces straight back at us
    // as a realtime UPDATE. Re-fetching mid-removal would merge the photo back
    // in from the verification request row that hasn't been cleared yet.
    if (_photoOpInFlight && !force) return;
    try {
      final fresh = await SupabaseService.instance.fetchSingleAdminUser(widget.user.id);
      if (fresh == null || !mounted) return;
      // Patch in the full profile data that wasn't in the summary view.
      // Controllers are only updated if the admin hasn't started editing
      // them yet (_hasChanges is still false at this point on fresh open).
      if (!_fullDataLoaded) {
          // Temporarily remove listeners so controller updates don't trigger
          // _onFieldChanged and falsely activate the Save button.
          final ctrls = [
            _nameCtrl, _ageCtrl, _phoneCtrl, _phone2Ctrl, _cnicCtrl, _passwordCtrl, _heightCtrl, _weightCtrl,
            _aboutCtrl, _lookingForCtrl, _instCtrl, _degreeTitleCtrl, _inst2Ctrl, _degreeTitle2Ctrl,
            _inst3Ctrl, _degreeTitle3Ctrl, _boysCtrl, _girlsCtrl, _houseSizeCtrl, _carCtrl,
            _brothersCtrl, _sistersCtrl, _adminNotesCtrl, _locationCtrl, _disabilityDetailsCtrl,
            _countryCtrl, _professionCtrl, _professionCustomCtrl, _fatherOccCtrl, _motherOccCtrl,
            _passwordCtrl,
          ];
          for (final c in ctrls) c.removeListener(_onFieldChanged);

          // Always update password from fresh data regardless of _fullDataLoaded
          _passwordCtrl.text = fresh.password ?? '';

          _ageCtrl.text = fresh.age.toString();
          _aboutCtrl.text = fresh.about ?? '';
          _lookingForCtrl.text = fresh.lookingFor ?? '';
          _instCtrl.text = fresh.institute ?? '';
          _degreeTitleCtrl.text = fresh.degreeTitle ?? '';
          _inst2Ctrl.text = fresh.institute2 ?? '';
          _degreeTitle2Ctrl.text = fresh.degreeTitle2 ?? '';
          _inst3Ctrl.text = fresh.institute3 ?? '';
          _degreeTitle3Ctrl.text = fresh.degreeTitle3 ?? '';
          _boysCtrl.text = fresh.boys?.toString() ?? '';
          _girlsCtrl.text = fresh.girls?.toString() ?? '';
          _houseSizeCtrl.text = fresh.houseSize ?? '';
          _carCtrl.text = fresh.carName ?? '';
          _brothersCtrl.text = (fresh.brothers == 0 || fresh.brothers == null) ? '' : fresh.brothers.toString();
          _sistersCtrl.text = (fresh.sisters == 0 || fresh.sisters == null) ? '' : fresh.sisters.toString();
          _locationCtrl.text = fresh.location ?? '';
          _countryCtrl.text = fresh.country ?? '';
          _disabilityDetailsCtrl.text = fresh.disabilityDetails ?? '';
          _professionCtrl.text = fresh.profession;
          _fatherOccCtrl.text = fresh.fatherOccupation ?? '';
          _motherOccCtrl.text = fresh.motherOccupation ?? '';
          _weightCtrl.text = fresh.weightKg?.toString() ?? '';
          final h = fresh.heightInches.round();
          final ft = h ~/ 12; final inch = h % 12;
          _heightCtrl.text = "${ft}'${inch}\"";

          // Re-add listeners after all updates are done
          for (final c in ctrls) c.addListener(_onFieldChanged);
        }

      setState(() {
        _user = fresh;
        if (!_fullDataLoaded) {
          _siblingsVal  = fresh.hasSiblings == true ? 'Yes' : (fresh.hasSiblings == false ? 'No' : '');
          _houseVal     = fresh.homeType ?? '';
          _fatherVal    = fresh.fatherAlive == true ? 'Alive' : (fresh.fatherAlive == false ? 'Deceased' : '');
          _motherVal    = fresh.motherAlive == true ? 'Alive' : (fresh.motherAlive == false ? 'Deceased' : '');
          _disabilityVal = fresh.hasDisability ?? '';
          _professionCategory = fresh.professionCategory ?? '';
          _fullDataLoaded = true;
          _baseline = fresh; // update comparison baseline to full data
        }
      });
    } catch (_) {
      // Silent — background freshness load, screen still works with summary data.
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _ageCtrl, _phoneCtrl, _phone2Ctrl, _cnicCtrl, _passwordCtrl, _heightCtrl, _weightCtrl,
      _aboutCtrl, _lookingForCtrl, _instCtrl, _degreeTitleCtrl, _inst2Ctrl, _degreeTitle2Ctrl,
      _inst3Ctrl, _degreeTitle3Ctrl, _boysCtrl, _girlsCtrl, _houseSizeCtrl, _carCtrl,
      _brothersCtrl, _sistersCtrl,
      _adminNotesCtrl, _locationCtrl, _disabilityDetailsCtrl, _countryCtrl,
      _professionCtrl, _professionCustomCtrl, _fatherOccCtrl, _motherOccCtrl,
    ]) { c.dispose(); }
    _proposalSub?.unsubscribe();
    super.dispose();
  }

  bool get _showKids {
    final s = _user.maritalStatus.toLowerCase();
    return s == 'divorced' || s == 'khula' || s == 'widowed';
  }

  AdminUser _buildUpdated() {
    return _user.copyWith(
      name: _nameCtrl.text.trim(),
      age: int.tryParse(_ageCtrl.text) ?? _user.age,
      contactPhone: formatDialedPhone(_selectedCountry.dialCode, _phoneCtrl.text),
      contactPhone2: _phone2Ctrl.text.trim().isEmpty ? null : formatDialedPhone(_selectedCountry2.dialCode, _phone2Ctrl.text),
      cnic: _cnicCtrl.text.trim().isEmpty ? null : _cnicCtrl.text.trim(),
      password: _passwordCtrl.text.trim().isEmpty ? null : _passwordCtrl.text.trim(),
      heightInches: () {
        final t = _heightCtrl.text.trim();
        final m = RegExp(r"(\d+)'(\d+)").firstMatch(t);
        if (m != null) return double.parse(m.group(1)!) * 12 + double.parse(m.group(2)!);
        return double.tryParse(t) ?? _user.heightInches;
      }(),
      weightKg: double.tryParse(_weightCtrl.text),
      about: _aboutCtrl.text.trim().isEmpty ? null : _aboutCtrl.text.trim(),
      lookingFor: _lookingForCtrl.text.trim().isEmpty ? null : _lookingForCtrl.text.trim(),
      institute: _instCtrl.text.trim().isEmpty ? null : _instCtrl.text.trim(),
      degreeTitle: _degreeTitleCtrl.text.trim().isEmpty ? null : _degreeTitleCtrl.text.trim(),
      institute2: _inst2Ctrl.text.trim().isEmpty ? null : _inst2Ctrl.text.trim(),
      degreeTitle2: _degreeTitle2Ctrl.text.trim().isEmpty ? null : _degreeTitle2Ctrl.text.trim(),
      institute3: _inst3Ctrl.text.trim().isEmpty ? null : _inst3Ctrl.text.trim(),
      degreeTitle3: _degreeTitle3Ctrl.text.trim().isEmpty ? null : _degreeTitle3Ctrl.text.trim(),
      boys: int.tryParse(_boysCtrl.text),
      girls: int.tryParse(_girlsCtrl.text),
      houseSize: _houseSizeCtrl.text.trim().isEmpty ? null : _houseSizeCtrl.text.trim(),
      carName: _carCtrl.text.trim().isEmpty ? null : _carCtrl.text.trim(),
      profession: _professionCtrl.text == 'Other'
          ? (_professionCustomCtrl.text.trim().isNotEmpty
              ? _professionCustomCtrl.text.trim()
              : _user.profession)
          : (_professionCtrl.text.trim().isEmpty ? _user.profession : _professionCtrl.text.trim()),
      professionCategory: _professionCategory.isNotEmpty ? _professionCategory : _user.professionCategory,
      fatherOccupation: _fatherOccCtrl.text.trim().isEmpty ? null : _fatherOccCtrl.text.trim(),
      motherOccupation: _motherOccCtrl.text.trim().isEmpty ? null : _motherOccCtrl.text.trim(),
      physicallyActive: _user.physicallyActive,
      brothers: int.tryParse(_brothersCtrl.text) ?? _user.brothers,
      sisters: int.tryParse(_sistersCtrl.text) ?? _user.sisters,
      adminNotes: _adminNotesCtrl.text.trim().isEmpty ? null : _adminNotesCtrl.text.trim(),
      location: _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
      country: _countryCtrl.text.trim().isEmpty ? null : _countryCtrl.text.trim(),
      disabilityDetails: _disabilityDetailsCtrl.text.trim().isEmpty ? null : _disabilityDetailsCtrl.text.trim(),
    );
  }

  // True only when the pending edits actually differ from the original
  // record — drives whether the Save button appears active or inactive.
  // Ignores cosmetic formatting differences when diffing, so reformatting
  // old data on load doesn't itself count as an unsaved change — only real
  // value edits should:
  //  - CNIC: dashes are stripped either way.
  //  - Phone: compares only the significant local digits (last 10), ignoring
  //    country code, a leading trunk "0", and spacing — "03001234567",
  //    "+92 3001234567" and "300 1234567" all normalize to the same value.
  String _phoneCompareKey(String v) {
    var digits = v.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length > 10) digits = digits.substring(digits.length - 10);
    return digits.replaceFirst(RegExp(r'^0+'), '');
  }

  Map<String, dynamic> _normalizedForCompare(Map<String, dynamic> json) {
    final m = Map<String, dynamic>.from(json);
    if (m['cnic'] is String) m['cnic'] = (m['cnic'] as String).replaceAll('-', '');
    for (final k in ['contact_phone', 'contact_phone_2']) {
      if (m[k] is String) m[k] = _phoneCompareKey(m[k] as String);
    }
    return m;
  }

  bool get _hasChanges {
    final a = jsonEncode(_normalizedForCompare(_buildUpdated().toUpdateJson()));
    final b = jsonEncode(_normalizedForCompare(_baseline.toUpdateJson()));
    return a != b;
  }

  void _save() {
    // Extra backstop — the screen is already opened read-only for view-only
    // admins, but never let a save through without edit rights on either tab.
    if (!AdminPerms.i.canEdit(AdminPageKeys.users) &&
        !AdminPerms.i.canEdit(AdminPageKeys.orders)) {
      AdminPerms.i.denied(what: 'saving profile changes');
      return;
    }
    if (!_hasChanges) return;
    final updated = _buildUpdated();
    widget.svc.updateUser(updated);
    HapticFeedback.mediumImpact();
    // Stay on screen — update baseline so Save button goes inactive again
    setState(() => _baseline = updated);
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0F0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16132A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.readOnly ? 'View Profile' : 'Edit Profile',
                style: TextStyle(fontSize: s.f(16), fontWeight: FontWeight.w800, color: Colors.white)),
            Row(children: [
              Text(widget.user.name,
                  style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.4))),
              if (widget.user.proposalNumber != null) ...[
                SizedBox(width: s.s(6)),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: s.s(5), vertical: s.s(1)),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(s.s(5)),
                  ),
                  child: Text('#${widget.user.proposalNumber}', style: TextStyle(fontSize: s.f(10), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.4))),
                ),
              ],
            ]),
          ],
        ),
        actions: [
          if (!widget.readOnly) ...[          TextButton(
            onPressed: _hasChanges ? _save : null,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: s.s(16), vertical: s.s(6)),
              decoration: BoxDecoration(
                gradient: _hasChanges
                    ? const LinearGradient(colors: [kPurple, kPurpleDeep])
                    : null,
                color: _hasChanges ? null : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(s.s(10)),
                border: _hasChanges ? null : Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Text('Save',
                  style: TextStyle(
                    color: _hasChanges ? Colors.white : Colors.white.withOpacity(0.3),
                    fontWeight: FontWeight.w700,
                    fontSize: s.f(13),
                  )),
            ),
          ),
          SizedBox(width: s.s(8)),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white.withOpacity(0.07)),
        ),
      ),
      body: widget.readOnly ? _buildProfileView() : ListView(
        padding: EdgeInsets.all(s.s(16)),
        children: [

          // ── BASIC INFORMATION ──
          _mainHeader('Basic Information'),
          _field('Full Name', _nameCtrl),
          _field('Age', _ageCtrl, type: TextInputType.number),
          _HeightDropdowns(controller: _heightCtrl, darkTheme: true, label: 'Height'),
          _phoneField('Phone Number', _phoneCtrl, _selectedCountry, (c) => setState(() => _selectedCountry = c)),
          _phoneField('Second Phone Number (optional)', _phone2Ctrl, _selectedCountry2, (c) => setState(() => _selectedCountry2 = c), required: false),
          _field('CNIC Number', _cnicCtrl, type: TextInputType.number, formatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d-]')),
            _AdminCnicFormatter(),
          ]),
          _field('Password', _passwordCtrl, suffix: GestureDetector(
            onTap: () {
              const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
              final rand = Random.secure();
              final newPassword = List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
              _passwordCtrl.removeListener(_onFieldChanged);
              _passwordCtrl.text = newPassword;
              _passwordCtrl.addListener(_onFieldChanged);
              setState(() { _user = _user.copyWith(password: newPassword); });
            },
            child: const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.refresh_rounded, size: 18, color: kPurple),
            ),
          )),
          _drop('Gender', _user.gender, ['Male', 'Female'],
              (v) => setState(() => _user = _user.copyWith(gender: v))),
          _field('Country', _countryCtrl),
          _cityPicker(),
          _drop('House', _houseVal, ['Own House', 'Rented House'],
              (v) => setState(() { _houseVal = v; _user = _user.copyWith(homeType: v.isEmpty ? null : v); })),
          if (_houseVal.isNotEmpty) ...[
            _subField('Location', _locationCtrl),
            _subField('House Size', _houseSizeCtrl),
          ],
          _drop('Caste', _user.caste, SupabaseService.instance.castesList,
              (v) => setState(() => _user = _user.copyWith(caste: v))),
          _drop('Sect / Maslak', _user.sect, kSects,
              (v) => setState(() => _user = _user.copyWith(sect: v))),
          _drop('Native Language', _user.languages.isNotEmpty ? _user.languages.first : '', kLanguages,
              (v) => setState(() => _user = _user.copyWith(languages: v.isEmpty ? [] : [v]))),
          if (widget.readOnly)
            _field('Occupation', _professionCtrl)
          else ...[
            AdminOccupationPicker(
              label: 'Occupation',
              category: _professionCategory.isNotEmpty ? _professionCategory : null,
              profession: _professionCtrl.text.isNotEmpty ? _professionCtrl.text : null,
              onSelect: (cat, prof) => setState(() {
                _professionCtrl.text = prof;
                _professionCategory = cat;
                if (prof != 'Other') _professionCustomCtrl.clear();
              }),
            ),
            if (_professionCtrl.text == 'Other') ...[
              _subField('Specify Occupation', _professionCustomCtrl),
              _subDrop('Occupation Category', _professionCategory,
                  SupabaseService.instance.occupationsGrouped.keys
                      .where((k) => k != 'Other').toList(),
                  (v) => setState(() => _professionCategory = v)),
            ],
          ],
          _drop('Marital Status', _user.maritalStatus,
              ['Never married', 'Married', 'Divorced', 'Khula', 'Widowed'],
              (v) => setState(() => _user = _user.copyWith(maritalStatus: v, marriageNumber: v != 'Married' ? null : _user.marriageNumber))),
          if (_user.maritalStatus == 'Married')
            _subDrop('Looking for', _user.marriageNumber ?? '',
              ['Second marriage', 'Third marriage', 'Fourth marriage'],
              (v) => setState(() => _user = _user.copyWith(marriageNumber: v.isEmpty ? null : v))),
          if (!widget.readOnly || _user.hasKids != null)
            _viewValue('Children', _user.hasKids == true ? 'Yes' : (_user.hasKids == false ? 'No' : '')),
          if (_showKids && (_user.hasKids == true || !widget.readOnly))
            _row([
              _subField('Sons', _boysCtrl, type: TextInputType.number),
              _subField('Daughters', _girlsCtrl, type: TextInputType.number),
            ]),

          _multiField('About Yourself', _aboutCtrl, maxLength: 200),
          _multiField('Looking For', _lookingForCtrl, maxLength: 200),

          // ── Photos ──
          SizedBox(height: _S.of(context).s(12)),
          Text('Photos', style: TextStyle(fontSize: _S.of(context).f(11.5), fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.5))),
          SizedBox(height: _S.of(context).s(8)),
          Row(
            children: [
              Expanded(child: _EditablePhotoSlot(
                label: 'Profile Photo',
                icon: Icons.person_rounded,
                photoUrl: _user.profilePhoto,
                cnicOrId: _user.cnic ?? _user.id,
                photoType: 'profile',
                onChanged: (url) => _onPhotoChanged('profile', url, (u) => _user.copyWith(profilePhoto: u)),
                crop: true,
              )),
            ],
          ),
          SizedBox(height: _S.of(context).s(16)),
          _mainHeader('Verification'),
          SizedBox(height: _S.of(context).s(12)),

          // ── Marriage-Seeking Person CNIC ──────────────────────────────────
          _verificationSectionHeader(
            title: 'Marriage Seeking Person CNIC',
            docKeys: ['cnic_front', 'cnic_back'],
            docName: 'Candidate CNIC',
            hasDoc: (_user.cnicFront?.isNotEmpty ?? false) || (_user.cnicBack?.isNotEmpty ?? false),
          ),
          SizedBox(height: _S.of(context).s(8)),
          Row(children: [
            Expanded(child: _EditablePhotoSlot(
              label: 'CNIC Front', icon: Icons.credit_card_rounded,
              photoUrl: _user.cnicFront, cnicOrId: _user.cnic ?? _user.id,
              photoType: 'cnic_front',
              onChanged: (url) => _onPhotoChanged('cnic_front', url, (u) => _user.copyWith(cnicFront: u)),
            )),
            SizedBox(width: _S.of(context).s(10)),
            Expanded(child: _EditablePhotoSlot(
              label: 'CNIC Back', icon: Icons.credit_card_rounded,
              photoUrl: _user.cnicBack, cnicOrId: _user.cnic ?? _user.id,
              photoType: 'cnic_back',
              onChanged: (url) => _onPhotoChanged('cnic_back', url, (u) => _user.copyWith(cnicBack: u)),
            )),
          ]),

          SizedBox(height: _S.of(context).s(14)),

          // ── Most Recent Education Document ────────────────────────────────
          _verificationSectionHeader(
            title: 'Most Recent Education Document',
            docKeys: ['education_document'],
            docName: 'Education Document',
            hasDoc: _user.educationDocument?.isNotEmpty ?? false,
          ),
          SizedBox(height: _S.of(context).s(8)),
          _certField(
            label: 'Education Document',
            url: _user.educationDocument,
            cnicOrId: _user.cnic ?? _user.id,
            photoType: 'education_document',
            onChanged: (url) => _onPhotoChanged('education_document', url, (u) => _user.copyWith(educationDocument: u)),
          ),

          SizedBox(height: _S.of(context).s(6)),

          // ── Parent / Guardian CNIC ────────────────────────────────────────
          _verificationSectionHeader(
            title: 'Parent / Guardian CNIC',
            docKeys: ['guardian_cnic_front', 'guardian_cnic_back'],
            docName: 'Parent CNIC',
            hasDoc: (_user.guardianCnicFront?.isNotEmpty ?? false) || (_user.guardianCnicBack?.isNotEmpty ?? false),
          ),
          SizedBox(height: _S.of(context).s(8)),
          Row(children: [
            Expanded(child: _EditablePhotoSlot(
              label: 'CNIC Front', icon: Icons.credit_card_rounded,
              photoUrl: _user.guardianCnicFront, cnicOrId: _user.cnic ?? _user.id,
              photoType: 'guardian_cnic_front',
              onChanged: (url) => _onPhotoChanged('guardian_cnic_front', url, (u) => _user.copyWith(guardianCnicFront: u)),
            )),
            SizedBox(width: _S.of(context).s(10)),
            Expanded(child: _EditablePhotoSlot(
              label: 'CNIC Back', icon: Icons.credit_card_rounded,
              photoUrl: _user.guardianCnicBack, cnicOrId: _user.cnic ?? _user.id,
              photoType: 'guardian_cnic_back',
              onChanged: (url) => _onPhotoChanged('guardian_cnic_back', url, (u) => _user.copyWith(guardianCnicBack: u)),
            )),
          ]),

          SizedBox(height: _S.of(context).s(4)),

          _mainHeader('Additional Information'),

          // ── FAMILY ──
          if (!widget.readOnly || _user.fatherAlive != null || _user.motherAlive != null ||
              (_user.brothers != null && _user.brothers! > 0) || (_user.sisters != null && _user.sisters! > 0) ||
              _user.hasSiblings != null)
            _subHeader('Family'),
          if (!widget.readOnly || (_user.familyType != null && _user.familyType!.isNotEmpty))
            _drop('Family Type', _user.familyType ?? '', ['Joint family', 'Separated Family'],
                (v) => setState(() => _user = _user.copyWith(familyType: v.isEmpty ? null : v))),
          if (!widget.readOnly || _user.fatherAlive != null || _user.motherAlive != null)
            _row([
              _drop('Father', _fatherVal, ['Alive', 'Deceased'],
                  (v) => setState(() { _fatherVal = v; _user = _user.copyWith(fatherAlive: v.isEmpty ? null : v == 'Alive'); })),
              _drop('Mother', _motherVal, ['Alive', 'Deceased'],
                  (v) => setState(() { _motherVal = v; _user = _user.copyWith(motherAlive: v.isEmpty ? null : v == 'Alive'); })),
            ]),
          if (_fatherVal.isNotEmpty)
            _subField('Father Occupation', _fatherOccCtrl),
          if (_motherVal.isNotEmpty)
            _subField('Mother Occupation', _motherOccCtrl),
          if (!widget.readOnly || _user.hasSiblings != null)
            _drop('Siblings', _siblingsVal, ['Yes', 'No'],
              (v) => setState(() { _siblingsVal = v; _user = _user.copyWith(hasSiblings: v.isEmpty ? null : v == 'Yes'); })),
          if (_siblingsVal == 'Yes') ...[
            _subField('Brothers', _brothersCtrl, type: TextInputType.number),
            _subField('Sisters', _sistersCtrl, type: TextInputType.number),
          ],

          // ── EDUCATION ──
          if (!widget.readOnly || _user.education.isNotEmpty || _instCtrl.text.isNotEmpty)
            _subHeader('Education'),
          if (!widget.readOnly || _user.education.isNotEmpty)
            _drop('Education Level (Highest)', _user.education, kEducations,
              (v) => setState(() => _user = _user.copyWith(education: v))),
          _subHeader('Degree'),
          _field('Title', _degreeTitleCtrl),
          _field('Institute', _instCtrl),
          _certField(label: 'Degree Certificate', url: _user.degreeCertificateUrl, cnicOrId: _user.cnic ?? _user.id,
            photoType: 'degree_certificate', onChanged: (url) => setState(() => _user = _user.copyWith(degreeCertificateUrl: url))),
          _subHeader('Degree 2'),
          _field('Title', _degreeTitle2Ctrl),
          _field('Institute 2', _inst2Ctrl),
          _certField(label: 'Degree 2 Certificate', url: _user.degreeCertificate2Url, cnicOrId: _user.cnic ?? _user.id,
            photoType: 'degree_certificate_2', onChanged: (url) => setState(() => _user = _user.copyWith(degreeCertificate2Url: url))),
          _subHeader('Degree 3'),
          _field('Title', _degreeTitle3Ctrl),
          _field('Institute 3', _inst3Ctrl),
          _certField(label: 'Degree 3 Certificate', url: _user.degreeCertificate3Url, cnicOrId: _user.cnic ?? _user.id,
            photoType: 'degree_certificate_3', onChanged: (url) => setState(() => _user = _user.copyWith(degreeCertificate3Url: url))),

          // ── CAREER ──
          if (!widget.readOnly || _user.monthlyIncome != null || _user.employmentType != null)
            _subHeader('Career'),
          if (!widget.readOnly || _user.monthlyIncome != null)
            _drop('Monthly Income', _user.monthlyIncome ?? '', kMonthlyIncomes,
              (v) => setState(() => _user = _user.copyWith(monthlyIncome: v.isEmpty ? null : v))),
          if (!widget.readOnly || _user.employmentType != null)
            _drop('Employment Type', _user.employmentType ?? '',
              ['Full-time', 'Part-time', 'Self-employed', 'Business', 'Freelance', 'Not employed'],
              (v) => setState(() => _user = _user.copyWith(employmentType: v.isEmpty ? null : v))),

          // ── PHYSICAL ──
          if (!widget.readOnly || _weightCtrl.text.isNotEmpty || _user.complexion != null)
            _subHeader('Physical'),
          if (!widget.readOnly || _weightCtrl.text.isNotEmpty)
            _field('Weight (kg)', _weightCtrl, type: TextInputType.number),
          if (!widget.readOnly || _user.complexion != null)
            _drop('Complexion', _user.complexion ?? '', ['Fair', 'Wheatish', 'Brown', 'Dark'],
              (v) => setState(() => _user = _user.copyWith(complexion: v.isEmpty ? null : v))),

          // ── RELIGION ──
          if (!widget.readOnly || _user.practiceLevel != null || _user.hijab != null || _user.beard != null)
            _subHeader('Religion'),
          if (!widget.readOnly || _user.practiceLevel != null)
            _drop('Practice Level', _user.practiceLevel ?? '',
              ['High', 'Moderate', 'Low'],
              (v) => setState(() => _user = _user.copyWith(practiceLevel: v.isEmpty ? null : v))),
          if (!widget.readOnly)
            if (_user.gender.trim().toLowerCase() == 'female')
              _drop('Wears Hijab', _user.hijab ?? '', ['Yes', 'No', 'Sometimes'],
                  (v) => setState(() => _user = _user.copyWith(hijab: v.isEmpty ? null : v)))
            else
              _drop('Has Beard', _user.beard ?? '', ['Yes', 'No', 'Trimmed'],
                  (v) => setState(() => _user = _user.copyWith(beard: v.isEmpty ? null : v)))
          else if (_user.hijab != null || _user.beard != null)
            if (_user.gender.trim().toLowerCase() == 'female')
              _drop('Wears Hijab', _user.hijab ?? '', ['Yes', 'No', 'Sometimes'],
                  (v) => setState(() => _user = _user.copyWith(hijab: v.isEmpty ? null : v)))
            else
              _drop('Has Beard', _user.beard ?? '', ['Yes', 'No', 'Trimmed'],
                  (v) => setState(() => _user = _user.copyWith(beard: v.isEmpty ? null : v))),

          // ── OTHER ASSETS ──
          if (!widget.readOnly || _user.hasCar != null || _user.hasOtherProperty != null)
            _subHeader('Other Assets'),
          if (!widget.readOnly || _user.hasCar != null)
            _drop('Has Car', _user.hasCar ?? '', ['Yes', 'No', 'Multiple'],
              (v) => setState(() => _user = _user.copyWith(hasCar: v.isEmpty ? null : v))),

          if (!widget.readOnly || _user.hasOtherProperty != null)
            _drop('Other Property', _user.hasOtherProperty ?? '', ['Yes', 'No'],
              (v) => setState(() => _user = _user.copyWith(
                hasOtherProperty: v.isEmpty ? null : v,
                otherProperty: v == 'No' ? null : _user.otherProperty,
              ))),
          if (_user.hasOtherProperty == 'Yes') ...[
            _drop('Property Type', _user.otherProperty ?? '',
              ['Residential', 'Commercial', 'Land', 'Multiple'],
              (v) => setState(() => _user = _user.copyWith(otherProperty: v.isEmpty ? null : v))),
          ],

          // ── HEALTH ──
          if (!widget.readOnly || _user.hasDisability != null || _user.physicallyActive != null || _user.smokes != null)
            _subHeader('Health'),
          if (!widget.readOnly || _user.hasDisability != null)
            _drop('Disability / Chronic Illness', _disabilityVal, ['Yes', 'No'],
                (v) => setState(() { _disabilityVal = v; _user = _user.copyWith(hasDisability: v.isEmpty ? null : v); })),
          if (_disabilityVal == 'Yes')
            _subField('Disability Details', _disabilityDetailsCtrl),
          if (!widget.readOnly || _user.physicallyActive != null)
            _drop('Lifestyle', _user.physicallyActive ?? '',
                ['Active Living', 'Sedentary Living', 'Balance'],
                (v) => setState(() => _user = _user.copyWith(physicallyActive: v.isEmpty ? null : v))),
          if (!widget.readOnly || _user.smokes != null)
            _drop('Smoker', _user.smokes == true ? 'Yes' : (_user.smokes == false ? 'No' : ''),
                ['Yes', 'No'],
                (v) => setState(() => _user = _user.copyWith(smokes: v.isEmpty ? null : v == 'Yes'))),

          // ── NOTES FROM APPLICANT ──
          const SizedBox(height: 8),
          _multiField('Notes from Applicant', _adminNotesCtrl),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────


  // ── Read-only profile view (same style as Review Proposal screen) ──────────

  // Phone row: label | [call] [whatsapp] | number (right)
  Widget _pPhoneRow(String label, String phone) {
    final s = _S.of(context);
    final cleaned = phone.replaceAll(RegExp(r'[\s\-()]'), '');
    final waNumber = cleaned.startsWith('+92')
        ? cleaned.substring(1)
        : cleaned.startsWith('92')
            ? cleaned
            : cleaned.startsWith('0')
                ? '92${cleaned.substring(1)}'
                : '92$cleaned';
    final dialPhone = cleaned.startsWith('+') ? cleaned : '+$cleaned';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: s.s(7)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Label
        SizedBox(width: s.d(90), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: s.f(12.5)))),
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            // Call icon
            GestureDetector(
              onTap: () async {
                try { await launchUrl(Uri(scheme: 'tel', path: dialPhone)); } catch (_) {}
              },
              child: Container(
                padding: EdgeInsets.all(s.s(5)),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.18), borderRadius: BorderRadius.circular(7)),
                child: Icon(Icons.call_rounded, size: s.d(15), color: Colors.greenAccent),
              ),
            ),
            SizedBox(width: s.s(5)),
            // WhatsApp icon
            GestureDetector(
              onTap: () async {
                try {
                  await launchUrl(Uri.parse('https://wa.me/$waNumber'),
                      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
                } catch (_) {}
              },
              child: Container(
                padding: EdgeInsets.all(s.s(5)),
                decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.18), borderRadius: BorderRadius.circular(7)),
                child: SvgPicture.asset('assets/icons/whatsapp.svg',
                    width: s.d(15), height: s.d(15)),
              ),
            ),
            // Copy icon — puts the ready-made "your proposal is listed"
            // WhatsApp message on the clipboard, with this profile's own
            // link. Only for AI-uploaded proposals (the same AI_IMPORTED /
            // ai_batch test the Users screen uses for its AI filter and
            // long-press approve flow), since the "claim or remove" wording
            // only makes sense for a profile the person never submitted
            // themselves. Also hidden when the profile has no number yet,
            // as the link would be broken.
            if (_user.proposalNumber != null &&
                (_user.adminNotes == 'AI_IMPORTED' || _user.submissionSource == 'ai_batch')) ...[
              SizedBox(width: s.s(5)),
              GestureDetector(
                onTap: () {
                  final message = 'Your rishta proposal is currently listed on Jor.\n\n'
                      '\u{1F449} View Your Profile:\n'
                      'https://joronline.com/profile/${_user.proposalNumber}\n\n'
                      'Reply \u201Cclaim\u201D to manage your profile for free or \u201Cremove\u201D to remove it from Jor.';
                  Clipboard.setData(ClipboardData(text: message));
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Message copied'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                child: Container(
                  padding: EdgeInsets.all(s.s(5)),
                  decoration: BoxDecoration(color: kPurple.withOpacity(0.18), borderRadius: BorderRadius.circular(7)),
                  child: Icon(Icons.copy_rounded, size: s.d(15), color: kPurple),
                ),
              ),
            ],
            // Copy icon for doc_pending profiles — "start your rishta search" message
            // template, editable from the Content tab in app_settings.
            if (_user.proposalNumber != null &&
                _user.subscriptionStatus == SubscriptionStatus.docPending) ...[
              SizedBox(width: s.s(5)),
              GestureDetector(
                onTap: () {
                  final template = SupabaseService.instance.cachedSettings['pending_profile_message'] ?? '';
                  final message = template.isNotEmpty
                      ? template.replaceAll('[NUMBER]', '${_user.proposalNumber}')
                      : 'Your marriage proposal is currently listed on Jor\n\n'
                        '\u{1F517} View your profile:\n'
                        'https://joronline.com/profile/${_user.proposalNumber}\n\n'
                        'To start your rishta search and connect with families, please complete the verification process by logging in at:\n'
                        '\u{1F449} https://joronline.com/login\n\n'
                        'Or download our mobile app:\n'
                        '\u{1F449} joronline.com/get-android\n\n'
                        'For any questions, feel free to reply here.\n\n'
                        'Jor Team\n'
                        'joronline.com';
                  Clipboard.setData(ClipboardData(text: message));
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Message copied'),
                    duration: Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                child: Container(
                  padding: EdgeInsets.all(s.s(5)),
                  decoration: BoxDecoration(color: kAmber.withOpacity(0.18), borderRadius: BorderRadius.circular(7)),
                  child: Icon(Icons.copy_rounded, size: s.d(15), color: kAmber),
                ),
              ),
            ],
            SizedBox(width: s.s(6)),
            // Phone number right next to icons
            Flexible(child: Text(phone,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: s.f(13)),
                textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ]),
    );
  }


  Widget _pR(String label, String value, {double? labelWidth}) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: s.s(7)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: s.d(labelWidth ?? 130), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: s.f(12.5)))),
        Expanded(child: Text(value, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: s.f(13)), textAlign: TextAlign.right)),
      ]),
    );
  }


  Widget _pSub(String label, String value, {String? certUrl}) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(left: s.s(16), top: s.s(2), bottom: s.s(6)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('↳ ', style: TextStyle(fontSize: s.f(11), color: Colors.white.withOpacity(0.6))),
        SizedBox(width: s.d(114), child: Text(label, style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w500))),
        Expanded(child: Text(value, style: TextStyle(fontSize: s.f(12.5), color: Colors.white, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
        if (certUrl != null && certUrl.isNotEmpty) ...[
          SizedBox(width: s.s(8)),
          GestureDetector(
            onTap: () => _showCertPopup(certUrl),
            child: Text('View', style: TextStyle(fontSize: s.f(12), color: kPurple, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
          ),
        ],
      ]),
    );
  }

  Widget _pSecDark(String t) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(0, s.s(24), 0, s.s(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: TextStyle(fontSize: s.f(12), fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.8)),
        SizedBox(height: s.s(6)),
        Divider(color: Colors.white.withOpacity(0.1), height: 1),
      ]),
    );
  }

  Widget _pSecLight(String t, {bool first = false}) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(0, first ? s.s(12) : s.s(20), 0, s.s(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!first) Divider(color: Colors.white.withOpacity(0.1), height: 1),
        if (!first) SizedBox(height: s.s(10)),
        Text(t, style: TextStyle(fontSize: s.f(11), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.4), letterSpacing: 0.8)),
      ]),
    );
  }

  Widget _buildProfileView() {
    final u = _user;
    final ft = (u.heightInches / 12).floor();
    final inch = (u.heightInches % 12).round();
    final heightLabel = "$ft\'$inch\"";
    final hasFamilyData = u.fatherAlive != null || u.motherAlive != null || u.hasSiblings != null || (u.familyType != null && u.familyType!.isNotEmpty);
    final hasEducationData = u.education.isNotEmpty || (u.institute != null && u.institute!.isNotEmpty);
    final hasCareerData = u.monthlyIncome != null || u.employmentType != null;
    final hasPhysicalData = _weightCtrl.text.isNotEmpty || u.complexion != null;
    final hasReligionData = u.practiceLevel != null || u.hijab != null || u.beard != null;
    final hasAssetsData = (u.hasCar != null && u.hasCar != 'No' && u.hasCar!.toLowerCase() != 'false') || (u.hasOtherProperty == 'Yes' && u.otherProperty != null);
    final hasHealthData = u.hasDisability != null || u.physicallyActive != null || u.smokes != null;
    // Whichever subsection actually ends up first (some get skipped
    // entirely when a profile has no data for them) shouldn't draw its
    // own leading divider — otherwise it sits right under ADDITIONAL
    // INFO's own divider with nothing in between, looking like a stray
    // double line. Figures out the real first one instead of assuming
    // FAMILY always is.
    final firstSubsection = hasFamilyData
        ? 'family'
        : hasEducationData
            ? 'education'
            : hasCareerData
                ? 'career'
                : hasPhysicalData
                    ? 'physical'
                    : hasReligionData
                        ? 'religion'
                        : hasAssetsData
                            ? 'assets'
                            : hasHealthData
                                ? 'health'
                                : '';
    final hasAdditionalData = hasFamilyData || hasEducationData || hasCareerData ||
        hasPhysicalData || hasReligionData || hasAssetsData || hasHealthData;

    final s = _S.of(context);
    return ListView(padding: EdgeInsets.all(s.s(20)), children: [
      // ── Profile Photo ──
      Center(child: CircleAvatar(
        radius: s.d(44),
        backgroundColor: u.gender.toLowerCase() == 'female' ? kRose : kPurple,
        backgroundImage: (u.profilePhoto != null && u.profilePhoto!.isNotEmpty)
            ? NetworkImage(u.profilePhoto!) as ImageProvider
            : null,
        child: (u.profilePhoto == null || u.profilePhoto!.isEmpty)
            ? Text(u.name.isNotEmpty ? u.name.substring(0, 1) : '?',
                style: TextStyle(fontSize: s.f(28), fontWeight: FontWeight.w800, color: Colors.white))
            : null,
      )),
      SizedBox(height: s.s(16)),

      Container(
        padding: EdgeInsets.all(s.s(16)),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(s.s(16)),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── BASIC INFO ──
          _pSecDark('BASIC INFO'),
          _pR('Name', u.name),
          _pR('Age', u.age.toString()),
          _pR('Gender', u.gender),
          _pR('Height', heightLabel),
          if (!u.contactPhone.startsWith('unknown_'))
            _pPhoneRow('Phone', u.contactPhone),
          if (u.contactPhone2 != null && u.contactPhone2!.isNotEmpty)
            _pPhoneRow('Phone 2', u.contactPhone2!),
          if (u.cnic != null && u.cnic!.isNotEmpty) _pR('CNIC', formatCnicDisplay(u.cnic!)),
          if (u.password != null && u.password!.isNotEmpty) _pR('Password', u.password!),
          if (u.country != null && u.country!.isNotEmpty) _pR('Country', u.country!),
          _pR('City', u.city),
          if (u.homeType != null) _pR('Home Type', u.homeType!),
          if (_houseSizeCtrl.text.isNotEmpty) _pSub('Size', _houseSizeCtrl.text),
          if (_locationCtrl.text.isNotEmpty) _pSub('Location', _locationCtrl.text),
          _pR('Caste', u.caste),
          _pR('Sect', u.sect),
          if (u.languages.isNotEmpty) _pR('Native Language', u.languages.first),
          _pR('Occupation', u.profession),
          _pR('Marital Status', u.maritalStatus),
          if (u.maritalStatus == 'Married' && u.marriageNumber != null) _pSub('Looking for', u.marriageNumber!),
          if (u.hasKids != null) _pR('Has Kids', u.hasKids! ? 'Yes' : 'No'),
          if (u.hasKids == true) ...[
            if (u.boys != null && u.boys! > 0) _pSub('Sons', u.boys.toString()),
            if (u.girls != null && u.girls! > 0) _pSub('Daughters', u.girls.toString()),
          ],

          if (u.about != null && u.about!.isNotEmpty) _pR('About', u.about!),
          if (u.lookingFor != null && u.lookingFor!.isNotEmpty) _pR('Looking For', u.lookingFor!),

          // ── ADDITIONAL INFO ──
          if (hasAdditionalData) _pSecDark('ADDITIONAL INFO'),

          // ── FAMILY ──
          if (hasFamilyData) ...[
            _pSecLight('FAMILY', first: firstSubsection == 'family'),
            if (u.familyType != null && u.familyType!.isNotEmpty) _pR('Family Type', u.familyType!),
            if (u.fatherAlive != null) _pR('Father', u.fatherAlive! ? 'Alive' : 'Deceased'),
            if (u.fatherOccupation != null) _pSub('Occupation', u.fatherOccupation!),
            if (u.motherAlive != null) _pR('Mother', u.motherAlive! ? 'Alive' : 'Deceased'),
            if (u.motherOccupation != null) _pSub('Occupation', u.motherOccupation!),
            if (u.hasSiblings != null) _pR('Siblings', u.hasSiblings! ? 'Yes' : 'No'),
            if (u.brothers != null && u.brothers! > 0) _pSub('Brothers', u.brothers.toString()),
            if (u.sisters != null && u.sisters! > 0) _pSub('Sisters', u.sisters.toString()),
          ],

          // ── EDUCATION ──
          if (hasEducationData) ...[
            _pSecLight('EDUCATION', first: firstSubsection == 'education'),
            if (u.education.isNotEmpty) _pR('Education Level (Highest)', u.education, labelWidth: 185),
            if (u.degreeTitle != null && u.degreeTitle!.isNotEmpty) _pSub('Degree', u.degreeTitle!, certUrl: u.degreeCertificateUrl),
            if (u.institute != null && u.institute!.isNotEmpty) _pSub('Institute', u.institute!),
            if (u.degreeTitle2 != null && u.degreeTitle2!.isNotEmpty) _pSub('Degree 2', u.degreeTitle2!, certUrl: u.degreeCertificate2Url),
            if (u.institute2 != null && u.institute2!.isNotEmpty) _pSub('Institute 2', u.institute2!),
            if (u.degreeTitle3 != null && u.degreeTitle3!.isNotEmpty) _pSub('Degree 3', u.degreeTitle3!, certUrl: u.degreeCertificate3Url),
            if (u.institute3 != null && u.institute3!.isNotEmpty) _pSub('Institute 3', u.institute3!),
          ],

          // ── CAREER ──
          if (hasCareerData) ...[
            _pSecLight('CAREER', first: firstSubsection == 'career'),
            if (u.employmentType != null) _pR('Employment Type', u.employmentType!),
            if (u.monthlyIncome != null) _pR('Monthly Income', u.monthlyIncome!),
          ],

          // ── PHYSICAL ──
          if (hasPhysicalData) ...[
            _pSecLight('PHYSICAL', first: firstSubsection == 'physical'),
            if (_weightCtrl.text.isNotEmpty) _pR('Weight', _weightCtrl.text + ' kg'),
            if (u.complexion != null) _pR('Complexion', u.complexion!),
          ],

          // ── RELIGION ──
          if (hasReligionData) ...[
            _pSecLight('RELIGION', first: firstSubsection == 'religion'),
            if (u.practiceLevel != null) _pR('Practice Level', u.practiceLevel!),
            if (u.gender.toLowerCase() == 'female' && u.hijab != null) _pR('Hijab', u.hijab!),
            if (u.gender.toLowerCase() == 'male' && u.beard != null) _pR('Beard', u.beard!),
          ],

          // ── OTHER ASSETS ──
          if (hasAssetsData) ...[
            _pSecLight('OTHER ASSETS', first: firstSubsection == 'assets'),
            if (u.hasCar != null && u.hasCar != 'No' && u.hasCar!.toLowerCase() != 'false' && u.hasCar!.toLowerCase() != 'no') _pR('Car', u.hasCar!),

            if (u.otherProperty != null) _pR('Property', u.otherProperty!),
          ],

          // ── HEALTH ──
          if (hasHealthData) ...[
            _pSecLight('HEALTH', first: firstSubsection == 'health'),
            if (u.hasDisability != null) _pR('Disability', (u.hasDisability == 'true' || u.hasDisability == 'Yes') ? 'Yes' : (u.hasDisability == 'false' || u.hasDisability == 'No') ? 'No' : u.hasDisability!),
            if ((u.hasDisability == 'Yes' || u.hasDisability == 'true') && u.disabilityDetails != null && u.disabilityDetails!.isNotEmpty)
              _pSub('Details', u.disabilityDetails!),
            if (u.physicallyActive != null) _pR('Lifestyle', u.physicallyActive!),
            if (u.smokes != null) _pR('Smoker', u.smokes! ? 'Yes' : 'No'),
          ],

        ]),
      ),

      // ── CNIC Photos ──
      if (u.cnicFront != null || u.cnicBack != null) ...[
        SizedBox(height: s.s(16)),
        Text('Marriage-seeking Person', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(4)),
        Text('CNIC', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(8)),
        Row(children: [
          if (u.cnicFront != null) Expanded(child: _AdminPhotoSlot(label: 'Front', icon: Icons.credit_card_rounded, photoUrl: u.cnicFront)),
          if (u.cnicFront != null && u.cnicBack != null) SizedBox(width: s.s(10)),
          if (u.cnicBack != null) Expanded(child: _AdminPhotoSlot(label: 'Back', icon: Icons.credit_card_rounded, photoUrl: u.cnicBack)),
        ]),
      ],

      // ── Education Document ──
      if (u.educationDocument != null) ...[
        SizedBox(height: s.s(16)),
        Text('Education Document', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(8)),
        Row(children: [Expanded(child: _AdminPhotoSlot(label: 'Document', icon: Icons.description_outlined, photoUrl: u.educationDocument))]),
      ],

      // ── Guardian CNIC Photos ──
      if (u.guardianCnicFront != null || u.guardianCnicBack != null) ...[
        SizedBox(height: s.s(16)),
        Text('Parent / Guardian CNIC', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(8)),
        Row(children: [
          if (u.guardianCnicFront != null) Expanded(child: _AdminPhotoSlot(label: 'Front', icon: Icons.credit_card_rounded, photoUrl: u.guardianCnicFront)),
          if (u.guardianCnicFront != null && u.guardianCnicBack != null) SizedBox(width: s.s(10)),
          if (u.guardianCnicBack != null) Expanded(child: _AdminPhotoSlot(label: 'Back', icon: Icons.credit_card_rounded, photoUrl: u.guardianCnicBack)),
        ]),
      ],

      // ── Admin Notes ──
      if (u.adminNotes != null && u.adminNotes!.isNotEmpty) ...[
        SizedBox(height: s.s(16)),
        Text('Notes from Applicant', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(8)),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(s.s(14)),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(s.s(12)),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Text(u.adminNotes!, style: TextStyle(fontSize: s.f(13), color: Colors.white.withOpacity(0.8), height: 1.5)),
        ),
      ],

      // ── Raw Proposal ──
      if ((u.suggestedInfo != null && u.suggestedInfo!.isNotEmpty) ||
          (u.discarded != null && u.discarded!.isNotEmpty)) ...[
        SizedBox(height: s.s(16)),
        Builder(builder: (context) {
          final parts = [
            if (u.suggestedInfo != null && u.suggestedInfo!.isNotEmpty) u.suggestedInfo!,
            if (u.discarded != null && u.discarded!.isNotEmpty)
              ...u.discarded!.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty),
          ];
          final combined = parts.join('\n\n');
          return Container(
            width: double.infinity,
            padding: EdgeInsets.all(s.s(14)),
            decoration: BoxDecoration(
              color: kPurple.withOpacity(0.07),
              borderRadius: BorderRadius.circular(s.s(12)),
              border: Border.all(color: kPurple.withOpacity(0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.auto_awesome_rounded, color: kPurple, size: s.d(15)),
                SizedBox(width: s.s(6)),
                Text('Raw Proposal', style: TextStyle(color: kPurple, fontSize: s.f(12), fontWeight: FontWeight.w700)),
              ]),
              SizedBox(height: s.s(10)),
              Text(combined, style: TextStyle(color: Colors.white70, fontSize: s.f(13), height: 1.6)),
            ]),
          );
        }),
      ],

      SizedBox(height: s.s(40)),
    ]);
  }

  Widget _mainHeader(String title) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(top: s.s(28), bottom: s.s(12)),
      child: Row(
        children: [
          Container(width: s.d(3), height: s.d(16),
              decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(s.s(2)))),
          SizedBox(width: s.s(10)),
          Text(title, style: TextStyle(fontSize: s.f(15), fontWeight: FontWeight.w800, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _subHeader(String title) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(top: s.s(20), bottom: s.s(8)),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontSize: s.f(11), fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.35), letterSpacing: 1.0),
      ),
    );
  }

  Widget _subField(String label, TextEditingController ctrl, {TextInputType? type}) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(left: s.s(16), bottom: s.s(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: EdgeInsets.only(top: s.s(12)),
          child: Text('↳ ', style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w700)),
        ),
        Expanded(child: _field(label, ctrl, type: type)),
      ]),
    );
  }

  Widget _subDrop(String label, String value, List<String> options, ValueChanged<String> onChanged) {
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(left: s.s(16), bottom: s.s(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: EdgeInsets.only(top: s.s(12)),
          child: Text('↳ ', style: TextStyle(fontSize: s.f(12), color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w700)),
        ),
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
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Row(children: items),
    );
  }

  Widget _viewValue(String label, String value) {
    if (value.isEmpty || value == '—') return const SizedBox.shrink();
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.35))),
          SizedBox(height: s.s(4)),
          Text(value, style: TextStyle(fontSize: s.f(13.5), color: Colors.white.withOpacity(0.85))),
        ],
      ),
    );
  }

  // Handles both modes this screen already supports: in read-only View
  // mode, shows a tappable "View Certificate" link (matching _viewValue's
  // styling) when one exists and nothing at all when it doesn't; in Edit
  // ── Section heading row: title left, dropdown + status right ─────────────
  // Heading: "Marriage Seeking Person CNIC"   [dropdown ▾]   Approved ✓
  Widget _verificationSectionHeader({
    required String title,
    required List<String> docKeys,
    required String docName,
    required bool hasDoc,
  }) {
    final s = _S.of(context);

    // Derive status
    final String status;
    if (docKeys.every((k) => (_user.docVerification[k] ?? 'pending') == 'approved')) {
      status = 'approved';
    } else if (docKeys.any((k) => (_user.docVerification[k] ?? 'pending') == 'rejected')) {
      status = 'rejected';
    } else {
      status = 'pending';
    }

    final Color statusColor = status == 'approved' ? kGreen
        : status == 'rejected' ? kRose
        : Colors.white.withOpacity(0.4);

    final String statusLabel = status == 'approved' ? 'Approved'
        : status == 'rejected' ? 'Rejected'
        : 'Pending';

    final IconData statusIcon = status == 'approved' ? Icons.verified_rounded
        : status == 'rejected' ? Icons.cancel_rounded
        : Icons.hourglass_empty_rounded;

    // Layout: [Title] [▾]  ............  [Status]
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      // Title + dropdown arrow tight together, no gap between them
      Text(title, style: TextStyle(
        fontSize: s.f(12.5), fontWeight: FontWeight.w700,
        color: Colors.white.withOpacity(0.7))),
            const Spacer(),
      // Status + PopupMenuButton arrow — right side.
      // With no document uploaded there is nothing to approve or reject, so
      // neither the "Pending" label nor the dropdown arrow is shown.
      if (!hasDoc)
        const SizedBox.shrink()
      else if (!widget.readOnly)
        PopupMenuButton<String>(
          color: const Color(0xFF1E1A33),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (val) => _onDocAction(val, docKeys, docName),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'approved', child: Row(children: [
              Icon(Icons.verified_rounded, color: kGreen, size: s.d(16)),
              SizedBox(width: s.s(8)),
              Text('Approve', style: TextStyle(fontSize: s.f(13), fontWeight: FontWeight.w700, color: kGreen)),
            ])),
            PopupMenuItem(value: 'rejected', child: Row(children: [
              Icon(Icons.cancel_rounded, color: kRose, size: s.d(16)),
              SizedBox(width: s.s(8)),
              Text('Reject', style: TextStyle(fontSize: s.f(13), fontWeight: FontWeight.w700, color: kRose)),
            ])),
            PopupMenuItem(value: 'pending', child: Row(children: [
              Icon(Icons.refresh_rounded, color: Colors.white38, size: s.d(16)),
              SizedBox(width: s.s(8)),
              Text('Clear', style: TextStyle(fontSize: s.f(13), fontWeight: FontWeight.w600, color: Colors.white54)),
            ])),
          ],
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(statusIcon, size: s.d(13), color: statusColor),
            SizedBox(width: s.s(4)),
            Text(statusLabel, style: TextStyle(
              fontSize: s.f(12), fontWeight: FontWeight.w700, color: statusColor)),
            SizedBox(width: s.s(2)),
            Icon(Icons.keyboard_arrow_down_rounded,
              size: s.d(16), color: Colors.white.withOpacity(0.45)),
          ]),
        )
      else
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(statusIcon, size: s.d(13), color: statusColor),
          SizedBox(width: s.s(4)),
          Text(statusLabel, style: TextStyle(
            fontSize: s.f(12), fontWeight: FontWeight.w700, color: statusColor)),
        ]),
    ]);
  }

  // ── Doc section status dropdown ─────────────────────────────────────────
  // One dropdown for a CNIC pair (front+back share one decision) or a
  // single doc. Shows current status in colour, options: Approve / Reject.
  Widget _sectionDropdown(List<String> docKeys, String docName) {
    if (widget.readOnly) return const SizedBox.shrink();
    final s = _S.of(context);
    // Derive current status for the section:
    // approved = all keys approved; rejected = any key rejected; else pending
    final String current;
    if (docKeys.every((k) => (_user.docVerification[k] ?? 'pending') == 'approved')) {
      current = 'approved';
    } else if (docKeys.any((k) => (_user.docVerification[k] ?? 'pending') == 'rejected')) {
      current = 'rejected';
    } else {
      current = 'pending';
    }

    final Color statusColor = current == 'approved' ? kGreen
        : current == 'rejected' ? kRose
        : Colors.white.withOpacity(0.4);
    final IconData statusIcon = current == 'approved' ? Icons.verified_rounded
        : current == 'rejected' ? Icons.cancel_rounded
        : Icons.hourglass_empty_rounded;

    return Padding(
      padding: EdgeInsets.only(top: s.s(6), bottom: s.s(10)),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: s.s(12), vertical: s.s(4)),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(s.s(10)),
          border: Border.all(color: statusColor.withOpacity(0.4)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: current == 'pending' ? null : current,
            hint: Row(children: [
              Icon(statusIcon, size: s.d(14), color: statusColor),
              SizedBox(width: s.s(6)),
              Text('Pending Review', style: TextStyle(fontSize: s.f(13), fontWeight: FontWeight.w600, color: statusColor)),
            ]),
            isExpanded: true,
            dropdownColor: const Color(0xFF1E1A33),
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white.withOpacity(0.4), size: s.d(18)),
            items: [
              DropdownMenuItem(value: 'approved', child: Row(children: [
                Icon(Icons.verified_rounded, size: s.d(14), color: kGreen),
                SizedBox(width: s.s(8)),
                Text('Approve', style: TextStyle(fontSize: s.f(13), fontWeight: FontWeight.w700, color: kGreen)),
              ])),
              DropdownMenuItem(value: 'rejected', child: Row(children: [
                Icon(Icons.cancel_rounded, size: s.d(14), color: kRose),
                SizedBox(width: s.s(8)),
                Text('Reject', style: TextStyle(fontSize: s.f(13), fontWeight: FontWeight.w700, color: kRose)),
              ])),
            ],
            selectedItemBuilder: (_) => [
              Row(children: [
                Icon(Icons.verified_rounded, size: s.d(14), color: kGreen),
                SizedBox(width: s.s(6)),
                Text('Approved', style: TextStyle(fontSize: s.f(13), fontWeight: FontWeight.w700, color: kGreen)),
              ]),
              Row(children: [
                Icon(Icons.cancel_rounded, size: s.d(14), color: kRose),
                SizedBox(width: s.s(6)),
                Text('Rejected', style: TextStyle(fontSize: s.f(13), fontWeight: FontWeight.w700, color: kRose)),
              ]),
            ],
            onChanged: (val) async {
              if (val == null) return;
              final actionLabel = val == 'approved' ? 'Approve' : 'Reject';
              final confirmed = await _confirmDialog('$actionLabel $docName?',
                val == 'approved'
                  ? 'This will mark $docName as approved.'
                  : 'The user will be notified and asked to re-upload $docName.');
              if (!confirmed) return;
              for (final k in docKeys) {
                await widget.svc.setDocVerificationStatus(_user.id, k, val);
              }
              final updatedDv = Map<String, String>.from(_user.docVerification)
                ..addAll({for (final k in docKeys) k: val});
              setState(() {
                _user = _user.copyWith(docVerification: updatedDv);
                // Sync _baseline so _hasChanges stays accurate — the dropdown
                // saves directly (setDocVerificationStatus), not through _save(),
                // so _baseline must be updated here to reflect what's now on disk.
                // Without this, any other pending field change would also appear
                // to include the doc-verification change (confusing) and the Save
                // button may incorrectly activate or deactivate.
                _baseline = _baseline.copyWith(docVerification: updatedDv);
              });
              if (val == 'rejected') {
                SupabaseService.instance.notifyDocRejected(_user.id, docName);
              }
              // If user is doc_pending and all compulsory docs are now approved,
              // upgrade subscription_status to 'active' so contacts unlock.
              if (val == 'approved' && _user.subscriptionStatus == SubscriptionStatus.docPending) {
                await SupabaseService.instance.checkAndUpgradeDocPending(_user.id, updatedDv);
              }
              // Let the admin know it saved immediately — the dropdown writes
              // directly to the database (no Save button needed).
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('$docName marked as ${val == 'approved' ? 'Approved ✓' : 'Rejected'} — saved.'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: val == 'approved' ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ));
              }
            },
          ),
        ),
      ),
    );
  }

  // Convenience wrappers kept for call-site compatibility
  Widget _pairApprovalRow(List<String> docKeys, String docName) => _sectionDropdown(docKeys, docName);
  Widget _docApprovalRow(String docKey, String docName) => _sectionDropdown([docKey], docName);

  // ── Doc action bottom sheet (triggered by arrow tap) ────────────────────
  /// Called when admin removes or replaces a verification photo.
  ///
  /// Removal has to clear the photo in THREE places or it comes back the next
  /// time the screen is opened:
  ///   1. proposal_photos          (fromJson prefers this over the column)
  ///   2. cnic_verification_requests, status='pending'
  ///                               (fetchSingleAdminUser merges from here
  ///                                whenever the proposals column is null)
  ///   3. the proposals column itself
  ///
  /// Order matters: (2) must happen BEFORE (3). Writing proposals first fires
  /// the realtime UPDATE this screen listens to, which re-runs
  /// _refreshCnicStatus() and merges the photo straight back in from the
  /// still-untouched request row. The writes are also awaited rather than
  /// fire-and-forget, so a failure is actually surfaced instead of vanishing.
  Future<void> _onPhotoChanged(String photoType, String? url, AdminUser Function(String?) copyFn) async {
    setState(() => _user = copyFn(url));
    if (url != null) return;

    // proposal_photos.photo_type is an enum with only these three values;
    // guardian and education docs live on the proposals row only.
    const inPhotoTable = {'profile', 'cnic_front', 'cnic_back'};
    const colMap = {
      'profile':             'profile_photo_url',
      'cnic_front':          'cnic_front_url',
      'cnic_back':           'cnic_back_url',
      'guardian_cnic_front': 'guardian_cnic_front_url',
      'guardian_cnic_back':  'guardian_cnic_back_url',
      'education_document':  'education_document_url',
    };
    final col = colMap[photoType];
    final client = SupabaseService.instance.client;
    final id = _user.id;

    _photoOpInFlight = true;
    try {
      if (inPhotoTable.contains(photoType)) {
        await client.from('proposal_photos')
            .delete()
            .eq('proposal_id', id)
            .eq('photo_type', photoType);
      }

      if (col != null) {
        // (2) before (3) — see the note above.
        await client.from('cnic_verification_requests')
            .update({col: null})
            .eq('proposal_id', id)
            .eq('status', 'pending');

        await client.from('proposals')
            .update({col: null})
            .eq('id', id);
      }

      // Clear doc_verification for this photo key — no photo means no status.
      // The profile photo isn't a verification document, so it has no key.
      if (photoType != 'profile') {
        await widget.svc.setDocVerificationStatus(id, photoType, 'none');
        if (mounted) {
          final updated = Map<String, String>.from(_user.docVerification)..remove(photoType);
          setState(() => _user = _user.copyWith(docVerification: updated));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove photo: $e')));
        // Put the photo back on screen — the database still has it.
        _photoOpInFlight = false;
        await _refreshCnicStatus(force: true);
        return;
      }
    } finally {
      _photoOpInFlight = false;
    }
  }

  Future<void> _onDocAction(String val, List<String> docKeys, String docName) async {
    if (val == 'pending') {
      for (final k in docKeys) await widget.svc.setDocVerificationStatus(_user.id, k, 'pending');
      setState(() => _user = _user.copyWith(
        docVerification: Map.from(_user.docVerification)..addAll({for (final k in docKeys) k: 'pending'})));
      return;
    }
    final label = val == 'approved' ? 'Approve' : 'Reject';
    final confirmed = await _confirmDialog('$label $docName?',
      val == 'approved'
        ? 'This will mark $docName as approved.'
        : 'The user will be notified and asked to re-upload $docName.');
    if (!confirmed) return;
    for (final k in docKeys) await widget.svc.setDocVerificationStatus(_user.id, k, val);
    setState(() => _user = _user.copyWith(
      docVerification: Map.from(_user.docVerification)..addAll({for (final k in docKeys) k: val})));
    if (val == 'rejected') SupabaseService.instance.notifyDocRejected(_user.id, docName);
  }

  // ── Confirmation dialog ───────────────────────────────────────────────────
  Future<bool> _confirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1830),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        content: Text(message, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.65), height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: kPurple, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // mode, reuses the exact same _EditablePhotoSlot already used for
  // profile/CNIC photos — same R2 upload path, just a different photoType.
  Widget _certField({required String label, required String? url, required String cnicOrId, required String photoType, required ValueChanged<String?> onChanged}) {
    final s = _S.of(context);
    if (widget.readOnly) {
      if (url == null || url.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(bottom: s.s(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.35))),
            SizedBox(height: s.s(4)),
            GestureDetector(
              onTap: () => _showCertPopup(url),
              child: Text('View Certificate', style: TextStyle(fontSize: s.f(13.5), color: kPurple, decoration: TextDecoration.underline)),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: _EditablePhotoSlot(
        label: label,
        icon: Icons.description_outlined,
        photoUrl: url,
        cnicOrId: cnicOrId,
        photoType: photoType,
        onChanged: onChanged,
      ),
    );
  }

  // Same dark-overlay, tap-outside-to-close popup pattern used across the
  // rest of this feature — in-app, not an external browser hand-off.
  void _showCertPopup(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (dialogCtx) => GestureDetector(
        onTap: () => Navigator.pop(dialogCtx),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: GestureDetector(
                  onTap: () {},
                  child: InteractiveViewer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) => progress == null
                            ? child
                            : const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Colors.white)),
                        errorBuilder: (context, error, stack) => const Padding(
                          padding: EdgeInsets.all(40),
                          child: Text('Could not load certificate', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 20, right: 20,
              child: GestureDetector(
                onTap: () => Navigator.pop(dialogCtx),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                  child: const Text('✕ Close', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {TextInputType? type, List<TextInputFormatter>? formatters, Widget? suffix}) {
    if (widget.readOnly) return _viewValue(label, ctrl.text);
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
          SizedBox(height: s.s(5)),
          TextField(
            controller: ctrl,
            keyboardType: type,
            inputFormatters: formatters,
            style: TextStyle(color: Colors.white, fontSize: s.f(13.5)),
            decoration: _inputDeco().copyWith(suffixIcon: suffix),
          ),
        ],
      ),
    );
  }

  Widget _phoneField(String label, TextEditingController ctrl, CountryCode country, ValueChanged<CountryCode> onCountryChanged, {bool required = true}) {
    if (widget.readOnly) {
      final display = ctrl.text.trim().isEmpty ? '' : '${country.dialCode} ${ctrl.text.trim()}';
      return _viewValue(label, display);
    }
    return Padding(
      padding: EdgeInsets.only(bottom: _S.of(context).s(10)),
      child: PhoneField(label: label, required: required, controller: ctrl, selectedCountry: country, onCountryChanged: onCountryChanged),
    );
  }

  Widget _multiField(String label, TextEditingController ctrl, {int? maxLength}) {
    if (widget.readOnly) return _viewValue(label, ctrl.text);
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
          SizedBox(height: s.s(5)),
          _MultiFieldWithCounter(ctrl: ctrl, maxLength: maxLength, inputDeco: _inputDeco(multiline: true)),
        ],
      ),
    );
  }

  InputDecoration _inputDeco({bool multiline = false, BuildContext? ctx}) {
    final scale = ctx != null ? (MediaQuery.of(ctx).size.width / 390.0).clamp(0.72, 1.0) : 1.0;
    return InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: multiline ? 12 * scale : 10 * scale),
      filled: true,
      fillColor: Colors.black.withOpacity(0.2),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10 * scale), borderSide: const BorderSide(color: kPurple)),
    );
  }

  Widget _drop(String label, String value, List<String> options, ValueChanged<String> onChanged, {String? infoText}) {
    if (widget.readOnly) return _viewValue(label, value);
    final hasValue = value.isNotEmpty && options.contains(value);
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
            if (infoText != null) ...[
              SizedBox(width: s.s(5)),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1E1A33),
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
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(s.s(10)),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: DropdownButton<String?>(
              value: hasValue ? value : null,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E1A33),
              style: TextStyle(color: Colors.white, fontSize: s.f(13.5)),
              iconEnabledColor: Colors.white38,
              underline: const SizedBox(),
              hint: Text('Select...', style: TextStyle(color: Colors.white38, fontSize: s.f(13.5))),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(hasValue ? '— Clear —' : 'Select...', style: TextStyle(color: Colors.white38, fontSize: s.f(13.5))),
                ),
                ...options.map((o) => DropdownMenuItem<String?>(
                  value: o,
                  child: Text(o, style: TextStyle(color: Colors.white, fontSize: s.f(13.5))),
                )),
              ],
              onChanged: (v) => onChanged(v ?? ''),
            ),
          ),
        ],
      ),
    );
  }


  Widget _multiSelect(String label, List<String> selected, List<String> options, ValueChanged<List<String>> onChanged) {
    final s = _S.of(context);
    if (widget.readOnly) {
      return selected.isEmpty ? const SizedBox.shrink() : _viewValue(label, selected.join(', '));
    }
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
          SizedBox(height: s.s(8)),
          Wrap(
            spacing: s.s(8), runSpacing: s.s(8),
            children: options.map((opt) {
              final sel = selected.contains(opt);
              return GestureDetector(
                onTap: () {
                  final updated = List<String>.from(selected);
                  if (sel) updated.remove(opt); else updated.add(opt);
                  onChanged(updated);
                },
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
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _cityPicker() {
    if (widget.readOnly) return _viewValue('City', _user.city);
    final s = _S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: s.s(10)),
      child: _AdminEditCityPicker(
        value: _user.city.isNotEmpty ? _user.city : null,
        onChanged: (v) { if (v != null) setState(() => _user = _user.copyWith(city: v)); },
      ),
    );
  }

}


// ── City Picker for Edit Screen (reuses the same dark sheet) ──────────────────
class _AdminEditCityPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _AdminEditCityPicker({required this.value, required this.onChanged});

  void _open(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _AdminEditCitySheet(
        selected: value,
        onSelect: (v) { onChanged(v); Navigator.pop(context); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final hasValue = value != null && value!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('City', style: TextStyle(fontSize: s.f(11.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
        SizedBox(height: s.s(5)),
        GestureDetector(
          onTap: () => _open(context),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: s.s(14), vertical: s.s(13)),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(s.s(10)), border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: Row(
              children: [
                Expanded(child: Text(hasValue ? value! : 'Select city',
                  style: TextStyle(fontSize: s.f(13.5), color: hasValue ? Colors.white : Colors.white38, fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400))),
                Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: s.d(22)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminEditCitySheet extends StatefulWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _AdminEditCitySheet({required this.selected, required this.onSelect});

  @override
  State<_AdminEditCitySheet> createState() => _AdminEditCitySheetState();
}

class _AdminEditCitySheetState extends State<_AdminEditCitySheet> {
  String _query = '';
  final _ctrl = TextEditingController();

  Map<String, List<String>> get _filtered {
    if (_query.isEmpty) return SupabaseService.instance.citiesGrouped;
    final q = _query.toLowerCase();
    final result = <String, List<String>>{};
    for (final entry in SupabaseService.instance.citiesGrouped.entries) {
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
      child: Column(
        children: [
          SizedBox(height: s.s(10)),
          Container(width: s.d(40), height: s.d(4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(s.s(2)))),
          Padding(
            padding: EdgeInsets.fromLTRB(s.s(20), s.s(14), s.s(20), 0),
            child: Row(children: [
              Text('Select City', style: TextStyle(fontSize: s.f(17), fontWeight: FontWeight.w800, color: Colors.white)),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(fontSize: s.f(13), color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w600)),
              ),
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
                  GestureDetector(
                    onTap: () { _ctrl.clear(); setState(() => _query = ''); },
                    child: Icon(Icons.close_rounded, size: s.d(18), color: Colors.white.withOpacity(0.3)),
                  ),
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
        ],
      ),
    );
  }
}

// ── Editable Photo Slot (edit mode) ─────────────────────────────────────────
class _EditablePhotoSlot extends StatefulWidget {
  final String label;
  final IconData icon;
  final String? photoUrl;
  final String cnicOrId;
  final String photoType;
  final ValueChanged<String?> onChanged;
  final bool crop;
  const _EditablePhotoSlot({required this.label, required this.icon, this.photoUrl, required this.cnicOrId, required this.photoType, required this.onChanged, this.crop = false});
  @override State<_EditablePhotoSlot> createState() => _EditablePhotoSlotState();
}
class _EditablePhotoSlotState extends State<_EditablePhotoSlot> {
  final _picker = ImagePicker();
  bool _uploading = false;

  Future<void> _pick(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 75, maxWidth: 600);
    if (picked == null) return;
    Uint8List bytes = await picked.readAsBytes();
    if (widget.crop && mounted) {
      final cropped = await showPhotoCropDialog(context, bytes);
      if (cropped == null) return;
      bytes = cropped;
    }
    setState(() => _uploading = true);
    try {
      // Uploaded straight to Cloudflare R2 — never stored as base64 in
      // the database, matching how every other photo in this app
      // (registration, self-service edits) already works.
      final url = await SupabaseService.instance.uploadUserPhoto(bytes, widget.cnicOrId, widget.photoType);
      widget.onChanged(url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showOptions() {
    final s = _S.of(context);
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1E1A33),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: s.s(8)),
        Container(width: s.d(40), height: s.d(4), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(s.s(2)))),
        SizedBox(height: s.s(16)),
        if (!kIsWeb) ListTile(leading: const Icon(Icons.camera_alt_rounded, color: kPurple),
          title: const Text('Take Photo', style: TextStyle(color: Colors.white)),
          onTap: () { Navigator.pop(context); _pick(ImageSource.camera); }),
        if (!kIsWeb) // camera hidden on web — only shown on mobile
        ListTile(leading: const Icon(Icons.photo_library_rounded, color: kPurple),
          title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
          onTap: () { Navigator.pop(context); _pick(ImageSource.gallery); }),
        if (widget.photoUrl != null)
          ListTile(leading: const Icon(Icons.delete_outline_rounded, color: kRose),
            title: const Text('Remove Photo', style: TextStyle(color: kRose)),
            onTap: () { Navigator.pop(context); widget.onChanged(null); }),
        const SizedBox(height: 8),
      ])),
    );
  }

  void _showFull() {
    final hasUrl = widget.photoUrl != null && widget.photoUrl!.isNotEmpty;
    if (!hasUrl) return;
    final sf = _S.of(context);
    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.all(sf.s(12)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: EdgeInsets.fromLTRB(sf.s(16), sf.s(12), sf.s(8), 0),
          child: Row(children: [
            Text(widget.label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: sf.f(14))),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
          ])),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            child: InteractiveViewer(
              child: Image.network(widget.photoUrl!, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(20),
                  child: Text('Could not load image', style: TextStyle(color: Colors.white)))),
            ),
          ),
        ),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.photoUrl != null && widget.photoUrl!.isNotEmpty;
    return GestureDetector(
      onTap: _uploading ? null : _showOptions,
      onLongPress: hasImage ? _showFull : null,
      child: Builder(builder: (context) {
        final s = _S.of(context);
        return Container(
          height: s.d(88),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(s.s(12)),
            border: Border.all(color: hasImage ? kPurple.withOpacity(0.5) : Colors.white.withOpacity(0.1), width: hasImage ? 1.5 : 1),
          ),
          child: _uploading
            ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: kPurple, strokeWidth: 2)))
            : hasImage
              ? ClipRRect(borderRadius: BorderRadius.circular(s.s(11)),
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(widget.photoUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder()),
                  Positioned(bottom: 0, left: 0, right: 0,
                    child: Container(padding: EdgeInsets.symmetric(vertical: s.s(4)), color: Colors.black.withOpacity(0.5),
                      child: Text(widget.label, textAlign: TextAlign.center,
                        style: TextStyle(fontSize: s.f(9), color: Colors.white, fontWeight: FontWeight.w600)))),
                  Positioned(top: s.s(4), right: s.s(4),
                    child: Container(padding: EdgeInsets.all(s.s(3)),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(s.s(6))),
                      child: Icon(Icons.edit_rounded, size: s.d(12), color: Colors.white))),
                ]))
            : _placeholder(),
        );
      }),
    );
  }

  Widget _placeholder() => LayoutBuilder(builder: (context, _) {
    final s = _S.of(context);
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.add_photo_alternate_rounded, size: s.d(26), color: Colors.white.withOpacity(0.3)),
      SizedBox(height: s.s(4)),
      Text(widget.label, textAlign: TextAlign.center, style: TextStyle(fontSize: s.f(10.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.3))),
      Text('Tap to add', textAlign: TextAlign.center, style: TextStyle(fontSize: s.f(9), color: Colors.white.withOpacity(0.2))),
    ]);
  });
}

// ── Admin Photo Slot — read-only display of a proposal's photo ───────────────
class _AdminPhotoSlot extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? photoUrl;

  const _AdminPhotoSlot({
    required this.label,
    required this.icon,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = photoUrl != null && photoUrl!.isNotEmpty;
    return GestureDetector(
      onTap: hasImage ? () => _showFullImage(context) : null,
      child: Builder(builder: (context) {
        final s = _S.of(context);
        return Container(
          height: s.d(88),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(s.s(12)),
            border: Border.all(
              color: hasImage ? kPurple.withOpacity(0.5) : Colors.white.withOpacity(0.1),
              width: hasImage ? 1.5 : 1,
            ),
          ),
          child: hasImage
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(s.s(11)),
                child: Stack(fit: StackFit.expand, children: [
                  Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  ),
                  Positioned(bottom: 0, left: 0, right: 0,
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: s.s(4)),
                      color: Colors.black.withOpacity(0.5),
                      child: Text(label, textAlign: TextAlign.center,
                        style: TextStyle(fontSize: s.f(9), color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              )
              : _placeholder(),
        );
      }),
    );
  }

  Widget _placeholder() {
    return LayoutBuilder(builder: (context, _) {
      final s = _S.of(context);
      return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: s.d(26), color: Colors.white.withOpacity(0.3)),
        SizedBox(height: s.s(6)),
        Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: s.f(10.5), fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.3))),
      ]);
    });
  }

  void _showFullImage(BuildContext context) {
    final s = _S.of(context);
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.all(s.s(12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(s.s(16), s.s(12), s.s(8), 0),
            child: Row(children: [
              Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: s.f(14))),
              const Spacer(),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ]),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              child: InteractiveViewer(
                child: Image.network(
                  photoUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Could not load image', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Multi-line field with inline char counter ─────────────────────────────────
class _MultiFieldWithCounter extends StatefulWidget {
  final TextEditingController ctrl;
  final int? maxLength;
  final InputDecoration inputDeco;
  const _MultiFieldWithCounter({required this.ctrl, this.maxLength, required this.inputDeco});
  @override State<_MultiFieldWithCounter> createState() => _MultiFieldWithCounterState();
}
class _MultiFieldWithCounterState extends State<_MultiFieldWithCounter> {
  int _count = 0;
  @override void initState() { super.initState(); _count = widget.ctrl.text.length; widget.ctrl.addListener(_update); }
  void _update() { if (widget.maxLength != null && mounted) setState(() => _count = widget.ctrl.text.length); }
  @override void dispose() { widget.ctrl.removeListener(_update); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      TextField(
        controller: widget.ctrl,
        maxLines: 4,
        maxLength: widget.maxLength,
        maxLengthEnforcement: widget.maxLength != null ? MaxLengthEnforcement.enforced : null,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: widget.inputDeco.copyWith(
          counterText: '',
          contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        ),
      ),
      if (widget.maxLength != null)
        Positioned(
          bottom: 8, right: 12,
          child: Text(
            '$_count/${widget.maxLength}',
            style: TextStyle(fontSize: 10.5, color: _count == widget.maxLength ? kRose : Colors.white.withOpacity(0.35)),
          ),
        ),
    ]);
  }
}

// ── Height picker: two dropdowns (feet + inches) ──────────────────────────────
class _HeightDropdowns extends StatefulWidget {
  final TextEditingController controller;
  final bool required;
  final bool darkTheme;
  final String label;
  const _HeightDropdowns({
    required this.controller,
    this.required = false,
    this.darkTheme = false,
    this.label = 'Height',
  });
  @override State<_HeightDropdowns> createState() => _HeightDropdownsState();
}
class _HeightDropdownsState extends State<_HeightDropdowns> {
  int? _feet;
  int? _inches;

  @override
  void initState() {
    super.initState();
    _parseController();
    widget.controller.addListener(_parseController);
  }

  void _parseController() {
    final text = widget.controller.text;
    final m = RegExp(r"(\d+)'(\d+)").firstMatch(text);
    if (m != null) {
      final f = int.parse(m.group(1)!);
      final i = int.parse(m.group(2)!);
      // Guard against out-of-range values (e.g. 0 from summary data before
      // full load arrives) — show hint instead of crashing the dropdown.
      final fValid = f >= 4 && f <= 7 ? f : null;
      final iValid = i >= 0 && i <= 11 ? i : null;
      if (fValid != _feet || iValid != _inches) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() { _feet = fValid; _inches = iValid; });
        });
      }
    }
  }

  void _update(int? feet, int? inches) {
    setState(() { _feet = feet; _inches = inches; });
    if (feet != null && inches != null) {
      final formatted = "$feet'$inches\"";
      if (widget.controller.text != formatted) widget.controller.text = formatted;
    } else {
      if (widget.controller.text.isNotEmpty) widget.controller.clear();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_parseController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _S.of(context);
    final labelColor = widget.darkTheme ? Colors.white.withOpacity(0.5) : const Color(0xFF6B6893);
    final textColor  = widget.darkTheme ? Colors.white : const Color(0xFF1A1830);
    final fillColor  = widget.darkTheme ? Colors.black.withOpacity(0.2) : Colors.white;
    final borderColor = widget.darkTheme ? Colors.white.withOpacity(0.12) : const Color(0xFFE8E6F5);

    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: labelColor, fontSize: s.f(13)),
      filled: true, fillColor: fillColor, isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: s.s(10), vertical: s.s(10)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide(color: borderColor)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide(color: borderColor)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(s.s(10)), borderSide: BorderSide(color: const Color(0xFF534AB7), width: 1.5)),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        widget.required ? '${widget.label} *' : widget.label,
        style: TextStyle(fontSize: s.f(12.5), fontWeight: FontWeight.w700, color: labelColor),
      ),
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
            items: List.generate(4, (i) => i + 4).map((f) =>
              DropdownMenuItem(value: f, child: Text("$f ft", style: TextStyle(color: textColor, fontSize: s.f(13.5))))).toList(),
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
            items: List.generate(12, (i) => i).map((i) =>
              DropdownMenuItem(value: i, child: Text('$i in', style: TextStyle(color: textColor, fontSize: s.f(13.5))))).toList(),
            onChanged: (v) => _update(_feet, v),
          ),
        ),
      ]),
    ]);
  }
}
