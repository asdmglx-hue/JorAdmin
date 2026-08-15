import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';

// ── Country + dial code list, phone formatter, and phone field ──────────────
// This is a public, standalone copy of the same country list / phone
// formatting / picker UI used by the Submit Proposal form. It's kept as its
// own copy (rather than importing submit_proposal_screen.dart's versions)
// because those are private (underscore-prefixed) to that file — this lets
// other screens (Edit Profile, etc.) show the exact same phone field style
// and produce the exact same stored format ("{dialCode} {digits}") without
// touching the already-working submission flow.

class CountryCode {
  final String flag, name, dialCode;
  const CountryCode({required this.flag, required this.name, required this.dialCode});

  static const pakistan = CountryCode(flag: '🇵🇰', name: 'Pakistan', dialCode: '+92');

  static const all = <CountryCode>[
    CountryCode(flag: '🇵🇰', name: 'Pakistan',                dialCode: '+92'),
    CountryCode(flag: '🇦🇫', name: 'Afghanistan',             dialCode: '+93'),
    CountryCode(flag: '🇦🇱', name: 'Albania',                 dialCode: '+355'),
    CountryCode(flag: '🇩🇿', name: 'Algeria',                 dialCode: '+213'),
    CountryCode(flag: '🇦🇩', name: 'Andorra',                 dialCode: '+376'),
    CountryCode(flag: '🇦🇴', name: 'Angola',                  dialCode: '+244'),
    CountryCode(flag: '🇦🇬', name: 'Antigua & Barbuda',       dialCode: '+1268'),
    CountryCode(flag: '🇦🇷', name: 'Argentina',               dialCode: '+54'),
    CountryCode(flag: '🇦🇲', name: 'Armenia',                 dialCode: '+374'),
    CountryCode(flag: '🇦🇺', name: 'Australia',               dialCode: '+61'),
    CountryCode(flag: '🇦🇹', name: 'Austria',                 dialCode: '+43'),
    CountryCode(flag: '🇦🇿', name: 'Azerbaijan',              dialCode: '+994'),
    CountryCode(flag: '🇧🇸', name: 'Bahamas',                 dialCode: '+1242'),
    CountryCode(flag: '🇧🇭', name: 'Bahrain',                 dialCode: '+973'),
    CountryCode(flag: '🇧🇩', name: 'Bangladesh',              dialCode: '+880'),
    CountryCode(flag: '🇧🇧', name: 'Barbados',                dialCode: '+1246'),
    CountryCode(flag: '🇧🇾', name: 'Belarus',                 dialCode: '+375'),
    CountryCode(flag: '🇧🇪', name: 'Belgium',                 dialCode: '+32'),
    CountryCode(flag: '🇧🇿', name: 'Belize',                  dialCode: '+501'),
    CountryCode(flag: '🇧🇯', name: 'Benin',                   dialCode: '+229'),
    CountryCode(flag: '🇧🇹', name: 'Bhutan',                  dialCode: '+975'),
    CountryCode(flag: '🇧🇴', name: 'Bolivia',                 dialCode: '+591'),
    CountryCode(flag: '🇧🇦', name: 'Bosnia & Herzegovina',    dialCode: '+387'),
    CountryCode(flag: '🇧🇼', name: 'Botswana',                dialCode: '+267'),
    CountryCode(flag: '🇧🇷', name: 'Brazil',                  dialCode: '+55'),
    CountryCode(flag: '🇧🇳', name: 'Brunei',                  dialCode: '+673'),
    CountryCode(flag: '🇧🇬', name: 'Bulgaria',                dialCode: '+359'),
    CountryCode(flag: '🇧🇫', name: 'Burkina Faso',            dialCode: '+226'),
    CountryCode(flag: '🇧🇮', name: 'Burundi',                 dialCode: '+257'),
    CountryCode(flag: '🇨🇻', name: 'Cabo Verde',              dialCode: '+238'),
    CountryCode(flag: '🇰🇭', name: 'Cambodia',                dialCode: '+855'),
    CountryCode(flag: '🇨🇲', name: 'Cameroon',                dialCode: '+237'),
    CountryCode(flag: '🇨🇦', name: 'Canada',                  dialCode: '+1'),
    CountryCode(flag: '🇨🇫', name: 'Central African Republic',dialCode: '+236'),
    CountryCode(flag: '🇹🇩', name: 'Chad',                    dialCode: '+235'),
    CountryCode(flag: '🇨🇱', name: 'Chile',                   dialCode: '+56'),
    CountryCode(flag: '🇨🇳', name: 'China',                   dialCode: '+86'),
    CountryCode(flag: '🇨🇴', name: 'Colombia',                dialCode: '+57'),
    CountryCode(flag: '🇰🇲', name: 'Comoros',                 dialCode: '+269'),
    CountryCode(flag: '🇨🇬', name: 'Congo',                   dialCode: '+242'),
    CountryCode(flag: '🇨🇩', name: 'Congo (DR)',              dialCode: '+243'),
    CountryCode(flag: '🇨🇷', name: 'Costa Rica',              dialCode: '+506'),
    CountryCode(flag: '🇭🇷', name: 'Croatia',                 dialCode: '+385'),
    CountryCode(flag: '🇨🇺', name: 'Cuba',                    dialCode: '+53'),
    CountryCode(flag: '🇨🇾', name: 'Cyprus',                  dialCode: '+357'),
    CountryCode(flag: '🇨🇿', name: 'Czech Republic',          dialCode: '+420'),
    CountryCode(flag: '🇩🇰', name: 'Denmark',                 dialCode: '+45'),
    CountryCode(flag: '🇩🇯', name: 'Djibouti',                dialCode: '+253'),
    CountryCode(flag: '🇩🇲', name: 'Dominica',                dialCode: '+1767'),
    CountryCode(flag: '🇩🇴', name: 'Dominican Republic',      dialCode: '+1809'),
    CountryCode(flag: '🇪🇨', name: 'Ecuador',                 dialCode: '+593'),
    CountryCode(flag: '🇪🇬', name: 'Egypt',                   dialCode: '+20'),
    CountryCode(flag: '🇸🇻', name: 'El Salvador',             dialCode: '+503'),
    CountryCode(flag: '🇬🇶', name: 'Equatorial Guinea',       dialCode: '+240'),
    CountryCode(flag: '🇪🇷', name: 'Eritrea',                 dialCode: '+291'),
    CountryCode(flag: '🇪🇪', name: 'Estonia',                 dialCode: '+372'),
    CountryCode(flag: '🇸🇿', name: 'Eswatini',                dialCode: '+268'),
    CountryCode(flag: '🇪🇹', name: 'Ethiopia',                dialCode: '+251'),
    CountryCode(flag: '🇫🇯', name: 'Fiji',                    dialCode: '+679'),
    CountryCode(flag: '🇫🇮', name: 'Finland',                 dialCode: '+358'),
    CountryCode(flag: '🇫🇷', name: 'France',                  dialCode: '+33'),
    CountryCode(flag: '🇬🇦', name: 'Gabon',                   dialCode: '+241'),
    CountryCode(flag: '🇬🇲', name: 'Gambia',                  dialCode: '+220'),
    CountryCode(flag: '🇬🇪', name: 'Georgia',                 dialCode: '+995'),
    CountryCode(flag: '🇩🇪', name: 'Germany',                 dialCode: '+49'),
    CountryCode(flag: '🇬🇭', name: 'Ghana',                   dialCode: '+233'),
    CountryCode(flag: '🇬🇷', name: 'Greece',                  dialCode: '+30'),
    CountryCode(flag: '🇬🇩', name: 'Grenada',                 dialCode: '+1473'),
    CountryCode(flag: '🇬🇹', name: 'Guatemala',               dialCode: '+502'),
    CountryCode(flag: '🇬🇳', name: 'Guinea',                  dialCode: '+224'),
    CountryCode(flag: '🇬🇼', name: 'Guinea-Bissau',           dialCode: '+245'),
    CountryCode(flag: '🇬🇾', name: 'Guyana',                  dialCode: '+592'),
    CountryCode(flag: '🇭🇹', name: 'Haiti',                   dialCode: '+509'),
    CountryCode(flag: '🇭🇳', name: 'Honduras',                dialCode: '+504'),
    CountryCode(flag: '🇭🇺', name: 'Hungary',                 dialCode: '+36'),
    CountryCode(flag: '🇮🇸', name: 'Iceland',                 dialCode: '+354'),
    CountryCode(flag: '🇮🇳', name: 'India',                   dialCode: '+91'),
    CountryCode(flag: '🇮🇩', name: 'Indonesia',               dialCode: '+62'),
    CountryCode(flag: '🇮🇷', name: 'Iran',                    dialCode: '+98'),
    CountryCode(flag: '🇮🇶', name: 'Iraq',                    dialCode: '+964'),
    CountryCode(flag: '🇮🇪', name: 'Ireland',                 dialCode: '+353'),
    CountryCode(flag: '🇮🇹', name: 'Italy',                   dialCode: '+39'),
    CountryCode(flag: '🇯🇲', name: 'Jamaica',                 dialCode: '+1876'),
    CountryCode(flag: '🇯🇵', name: 'Japan',                   dialCode: '+81'),
    CountryCode(flag: '🇯🇴', name: 'Jordan',                  dialCode: '+962'),
    CountryCode(flag: '🇰🇿', name: 'Kazakhstan',              dialCode: '+7'),
    CountryCode(flag: '🇰🇪', name: 'Kenya',                   dialCode: '+254'),
    CountryCode(flag: '🇰🇮', name: 'Kiribati',                dialCode: '+686'),
    CountryCode(flag: '🇽🇰', name: 'Kosovo',                  dialCode: '+383'),
    CountryCode(flag: '🇰🇼', name: 'Kuwait',                  dialCode: '+965'),
    CountryCode(flag: '🇰🇬', name: 'Kyrgyzstan',              dialCode: '+996'),
    CountryCode(flag: '🇱🇦', name: 'Laos',                    dialCode: '+856'),
    CountryCode(flag: '🇱🇻', name: 'Latvia',                  dialCode: '+371'),
    CountryCode(flag: '🇱🇧', name: 'Lebanon',                 dialCode: '+961'),
    CountryCode(flag: '🇱🇸', name: 'Lesotho',                 dialCode: '+266'),
    CountryCode(flag: '🇱🇷', name: 'Liberia',                 dialCode: '+231'),
    CountryCode(flag: '🇱🇾', name: 'Libya',                   dialCode: '+218'),
    CountryCode(flag: '🇱🇮', name: 'Liechtenstein',           dialCode: '+423'),
    CountryCode(flag: '🇱🇹', name: 'Lithuania',               dialCode: '+370'),
    CountryCode(flag: '🇱🇺', name: 'Luxembourg',              dialCode: '+352'),
    CountryCode(flag: '🇲🇬', name: 'Madagascar',              dialCode: '+261'),
    CountryCode(flag: '🇲🇼', name: 'Malawi',                  dialCode: '+265'),
    CountryCode(flag: '🇲🇾', name: 'Malaysia',                dialCode: '+60'),
    CountryCode(flag: '🇲🇻', name: 'Maldives',                dialCode: '+960'),
    CountryCode(flag: '🇲🇱', name: 'Mali',                    dialCode: '+223'),
    CountryCode(flag: '🇲🇹', name: 'Malta',                   dialCode: '+356'),
    CountryCode(flag: '🇲🇭', name: 'Marshall Islands',        dialCode: '+692'),
    CountryCode(flag: '🇲🇷', name: 'Mauritania',              dialCode: '+222'),
    CountryCode(flag: '🇲🇺', name: 'Mauritius',               dialCode: '+230'),
    CountryCode(flag: '🇲🇽', name: 'Mexico',                  dialCode: '+52'),
    CountryCode(flag: '🇫🇲', name: 'Micronesia',              dialCode: '+691'),
    CountryCode(flag: '🇲🇩', name: 'Moldova',                 dialCode: '+373'),
    CountryCode(flag: '🇲🇨', name: 'Monaco',                  dialCode: '+377'),
    CountryCode(flag: '🇲🇳', name: 'Mongolia',                dialCode: '+976'),
    CountryCode(flag: '🇲🇪', name: 'Montenegro',              dialCode: '+382'),
    CountryCode(flag: '🇲🇦', name: 'Morocco',                 dialCode: '+212'),
    CountryCode(flag: '🇲🇿', name: 'Mozambique',              dialCode: '+258'),
    CountryCode(flag: '🇲🇲', name: 'Myanmar',                 dialCode: '+95'),
    CountryCode(flag: '🇳🇦', name: 'Namibia',                 dialCode: '+264'),
    CountryCode(flag: '🇳🇷', name: 'Nauru',                   dialCode: '+674'),
    CountryCode(flag: '🇳🇵', name: 'Nepal',                   dialCode: '+977'),
    CountryCode(flag: '🇳🇱', name: 'Netherlands',             dialCode: '+31'),
    CountryCode(flag: '🇳🇿', name: 'New Zealand',             dialCode: '+64'),
    CountryCode(flag: '🇳🇮', name: 'Nicaragua',               dialCode: '+505'),
    CountryCode(flag: '🇳🇪', name: 'Niger',                   dialCode: '+227'),
    CountryCode(flag: '🇳🇬', name: 'Nigeria',                 dialCode: '+234'),
    CountryCode(flag: '🇲🇰', name: 'North Macedonia',         dialCode: '+389'),
    CountryCode(flag: '🇳🇴', name: 'Norway',                  dialCode: '+47'),
    CountryCode(flag: '🇴🇲', name: 'Oman',                    dialCode: '+968'),
    CountryCode(flag: '🇵🇼', name: 'Palau',                   dialCode: '+680'),
    CountryCode(flag: '🇵🇸', name: 'Palestine',               dialCode: '+970'),
    CountryCode(flag: '🇵🇦', name: 'Panama',                  dialCode: '+507'),
    CountryCode(flag: '🇵🇬', name: 'Papua New Guinea',        dialCode: '+675'),
    CountryCode(flag: '🇵🇾', name: 'Paraguay',                dialCode: '+595'),
    CountryCode(flag: '🇵🇪', name: 'Peru',                    dialCode: '+51'),
    CountryCode(flag: '🇵🇭', name: 'Philippines',             dialCode: '+63'),
    CountryCode(flag: '🇵🇱', name: 'Poland',                  dialCode: '+48'),
    CountryCode(flag: '🇵🇹', name: 'Portugal',                dialCode: '+351'),
    CountryCode(flag: '🇶🇦', name: 'Qatar',                   dialCode: '+974'),
    CountryCode(flag: '🇷🇴', name: 'Romania',                 dialCode: '+40'),
    CountryCode(flag: '🇷🇺', name: 'Russia',                  dialCode: '+7'),
    CountryCode(flag: '🇷🇼', name: 'Rwanda',                  dialCode: '+250'),
    CountryCode(flag: '🇰🇳', name: 'Saint Kitts & Nevis',     dialCode: '+1869'),
    CountryCode(flag: '🇱🇨', name: 'Saint Lucia',             dialCode: '+1758'),
    CountryCode(flag: '🇻🇨', name: 'Saint Vincent',           dialCode: '+1784'),
    CountryCode(flag: '🇼🇸', name: 'Samoa',                   dialCode: '+685'),
    CountryCode(flag: '🇸🇲', name: 'San Marino',              dialCode: '+378'),
    CountryCode(flag: '🇸🇹', name: 'Sao Tome & Principe',     dialCode: '+239'),
    CountryCode(flag: '🇸🇦', name: 'Saudi Arabia',            dialCode: '+966'),
    CountryCode(flag: '🇸🇳', name: 'Senegal',                 dialCode: '+221'),
    CountryCode(flag: '🇷🇸', name: 'Serbia',                  dialCode: '+381'),
    CountryCode(flag: '🇸🇨', name: 'Seychelles',              dialCode: '+248'),
    CountryCode(flag: '🇸🇱', name: 'Sierra Leone',            dialCode: '+232'),
    CountryCode(flag: '🇸🇬', name: 'Singapore',               dialCode: '+65'),
    CountryCode(flag: '🇸🇰', name: 'Slovakia',                dialCode: '+421'),
    CountryCode(flag: '🇸🇮', name: 'Slovenia',                dialCode: '+386'),
    CountryCode(flag: '🇸🇧', name: 'Solomon Islands',         dialCode: '+677'),
    CountryCode(flag: '🇸🇴', name: 'Somalia',                 dialCode: '+252'),
    CountryCode(flag: '🇿🇦', name: 'South Africa',            dialCode: '+27'),
    CountryCode(flag: '🇸🇸', name: 'South Sudan',             dialCode: '+211'),
    CountryCode(flag: '🇪🇸', name: 'Spain',                   dialCode: '+34'),
    CountryCode(flag: '🇱🇰', name: 'Sri Lanka',               dialCode: '+94'),
    CountryCode(flag: '🇸🇩', name: 'Sudan',                   dialCode: '+249'),
    CountryCode(flag: '🇸🇷', name: 'Suriname',                dialCode: '+597'),
    CountryCode(flag: '🇸🇪', name: 'Sweden',                  dialCode: '+46'),
    CountryCode(flag: '🇨🇭', name: 'Switzerland',             dialCode: '+41'),
    CountryCode(flag: '🇸🇾', name: 'Syria',                   dialCode: '+963'),
    CountryCode(flag: '🇹🇼', name: 'Taiwan',                  dialCode: '+886'),
    CountryCode(flag: '🇹🇯', name: 'Tajikistan',              dialCode: '+992'),
    CountryCode(flag: '🇹🇿', name: 'Tanzania',                dialCode: '+255'),
    CountryCode(flag: '🇹🇭', name: 'Thailand',                dialCode: '+66'),
    CountryCode(flag: '🇹🇱', name: 'Timor-Leste',             dialCode: '+670'),
    CountryCode(flag: '🇹🇬', name: 'Togo',                    dialCode: '+228'),
    CountryCode(flag: '🇹🇴', name: 'Tonga',                   dialCode: '+676'),
    CountryCode(flag: '🇹🇹', name: 'Trinidad & Tobago',       dialCode: '+1868'),
    CountryCode(flag: '🇹🇳', name: 'Tunisia',                 dialCode: '+216'),
    CountryCode(flag: '🇹🇷', name: 'Turkey',                  dialCode: '+90'),
    CountryCode(flag: '🇹🇲', name: 'Turkmenistan',            dialCode: '+993'),
    CountryCode(flag: '🇹🇻', name: 'Tuvalu',                  dialCode: '+688'),
    CountryCode(flag: '🇺🇬', name: 'Uganda',                  dialCode: '+256'),
    CountryCode(flag: '🇺🇦', name: 'Ukraine',                 dialCode: '+380'),
    CountryCode(flag: '🇦🇪', name: 'UAE',                     dialCode: '+971'),
    CountryCode(flag: '🇬🇧', name: 'United Kingdom',          dialCode: '+44'),
    CountryCode(flag: '🇺🇸', name: 'USA',                     dialCode: '+1'),
    CountryCode(flag: '🇺🇾', name: 'Uruguay',                 dialCode: '+598'),
    CountryCode(flag: '🇺🇿', name: 'Uzbekistan',              dialCode: '+998'),
    CountryCode(flag: '🇻🇺', name: 'Vanuatu',                 dialCode: '+678'),
    CountryCode(flag: '🇻🇦', name: 'Vatican City',            dialCode: '+39'),
    CountryCode(flag: '🇻🇪', name: 'Venezuela',               dialCode: '+58'),
    CountryCode(flag: '🇻🇳', name: 'Vietnam',                 dialCode: '+84'),
    CountryCode(flag: '🇾🇪', name: 'Yemen',                   dialCode: '+967'),
    CountryCode(flag: '🇿🇲', name: 'Zambia',                  dialCode: '+260'),
    CountryCode(flag: '🇿🇼', name: 'Zimbabwe',                dialCode: '+263'),
  ];
}

/// Finds a country by exact dial code match (first match wins for the rare
/// dial codes shared by more than one country, e.g. +1). Returns null if
/// nothing matches.
CountryCode? countryCodeForDial(String dialCode) {
  for (final c in CountryCode.all) {
    if (c.dialCode == dialCode) return c;
  }
  return null;
}

/// Formats a raw phone entry + selected dial code into the single stored
/// Formats a dialed phone using country-aware grouping — same table as
/// phoneDisplay() in supabase.ts and _formatPK() in rishta_proposal.dart.
const _kPhoneFormats = <(String, List<int>)>[
  ('+353', [2, 3, 4]), ('+966', [2, 3, 4]), ('+971', [2, 3, 4]),
  ('+968', [4, 4]),    ('+974', [4, 4]),    ('+973', [4, 4]),    ('+965', [4, 4]),
  ('+92',  [3, 7]),    ('+64',  [2, 3, 4]), ('+61',  [3, 3, 3]),
  ('+49',  [3, 7]),    ('+47',  [3, 2, 3]), ('+46',  [3, 3, 3]),
  ('+45',  [2, 2, 2, 2]), ('+44', [4, 6]), ('+39', [3, 7]),
  ('+34',  [3, 6]),    ('+33',  [1, 2, 2, 2, 2]), ('+31', [1, 4, 4]),
  ('+30',  [3, 7]),    ('+90',  [3, 3, 4]), ('+60', [2, 4, 4]),
  ('+1',   [3, 3, 4]),
];

String formatDialedPhone(String dialCode, String number) {
  final digits = number.replaceAll(RegExp(r'[^\d]'), '');
  final local = dialCode == '+92' ? digits.replaceFirst(RegExp(r'^0+'), '') : digits;
  final fmt = _kPhoneFormats.where((f) => f.$1 == dialCode).firstOrNull;
  if (fmt == null) return '$dialCode $local';
  final parts = <String>[];
  var pos = 0;
  for (final g in fmt.$2) {
    if (pos >= local.length) break;
    parts.add(local.substring(pos, (pos + g).clamp(0, local.length)));
    pos += g;
  }
  if (pos < local.length) parts.add(local.substring(pos));
  return '$dialCode ${parts.join(' ')}';
}

// ── Pakistani phone formatter: auto-space after 4 digits (0300 1234567) ───
class PakistaniPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return newValue.copyWith(text: '');

    final maxDigits = digits.startsWith('0') ? 11 : 10;
    final trimmed = digits.length > maxDigits ? digits.substring(0, maxDigits) : digits;

    final spaceAt = trimmed.startsWith('0') ? 4 : 3;
    String formatted;
    if (trimmed.length <= spaceAt) {
      formatted = trimmed;
    } else {
      formatted = '${trimmed.substring(0, spaceAt)} ${trimmed.substring(spaceAt)}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ── Dark-themed phone field for the admin panel ─────────────────────────────
// Same country list, formatting rules, and stored format ("{dialCode}
// {digits}") as the user app's Submit Proposal / Edit Profile forms, styled
// to match the admin panel's dark UI instead of the user app's light UI.
class PhoneField extends StatefulWidget {
  final String label;
  final bool required;
  final TextEditingController controller;
  final CountryCode selectedCountry;
  final ValueChanged<CountryCode> onCountryChanged;
  const PhoneField({
    super.key,
    this.label = 'Phone',
    this.required = true,
    required this.controller,
    required this.selectedCountry,
    required this.onCountryChanged,
  });
  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  int _digits = 0;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }
  void _update() => setState(() => _digits = widget.controller.text.replaceAll(RegExp(r'[^\d]'), '').length);
  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _openPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (ctx) => _CountryPickerSheet(
        selected: widget.selectedCountry,
        onSelect: (c) { widget.onCountryChanged(c); Navigator.pop(ctx); },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPak = widget.selectedCountry.dialCode == '+92';
    final int? requiredLen = isPak
        ? (_digits > 0 && widget.controller.text.startsWith('0') ? 11 : 10)
        : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.required ? '${widget.label} *' : widget.label,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.5))),
      const SizedBox(height: 5),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => _openPicker(context),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(widget.selectedCountry.flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text(widget.selectedCountry.dialCode, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.white.withOpacity(0.5)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Stack(children: [
            TextField(
              controller: widget.controller,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                if (isPak)
                  PakistaniPhoneFormatter()
                else
                  LengthLimitingTextInputFormatter(12),
              ],
              style: const TextStyle(fontSize: 13.5, color: Colors.white),
              decoration: InputDecoration(
                hintText: isPak ? '03001234567' : 'Phone number',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 13.5),
                isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(12, 10, 44, 10),
                filled: true,
                fillColor: Colors.black.withOpacity(0.2),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPurple)),
              ),
            ),
            if (isPak && _digits > 0)
              Positioned(right: 10, top: 0, bottom: 0,
                child: Center(
                  child: Text('$_digits/$requiredLen', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
        ),
      ]),
    ]);
  }
}

class _CountryPickerSheet extends StatefulWidget {
  final CountryCode selected;
  final ValueChanged<CountryCode> onSelect;
  const _CountryPickerSheet({required this.selected, required this.onSelect});
  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _q = '';
  final _ctrl = TextEditingController();
  List<CountryCode> get _filtered => _q.isEmpty
      ? CountryCode.all
      : CountryCode.all.where((c) => c.name.toLowerCase().contains(_q.toLowerCase()) || c.dialCode.contains(_q)).toList();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(color: Color(0xFF1E1A33), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Align(alignment: Alignment.centerLeft, child: Text('Select Country', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white))),
        ),
        const SizedBox(height: 12),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: Row(children: [
              Icon(Icons.search_rounded, size: 20, color: Colors.white.withOpacity(0.4)), const SizedBox(width: 8),
              Expanded(child: TextField(controller: _ctrl, onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(hintText: 'Search country...', hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14), border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 12)),
                style: const TextStyle(fontSize: 14, color: Colors.white))),
              if (_q.isNotEmpty) GestureDetector(onTap: () { _ctrl.clear(); setState(() => _q = ''); }, child: Icon(Icons.close_rounded, size: 18, color: Colors.white.withOpacity(0.4))),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Divider(height: 1, color: Colors.white.withOpacity(0.08)),
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: _filtered.length,
          itemBuilder: (_, i) {
            final c = _filtered[i];
            final sel = c.dialCode == widget.selected.dialCode && c.name == widget.selected.name;
            return GestureDetector(
              onTap: () => widget.onSelect(c),
              child: Container(
                color: sel ? kPurple.withOpacity(0.15) : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(children: [
                  Text(c.flag, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 14),
                  Expanded(child: Text(c.name, style: TextStyle(fontSize: 14, color: sel ? kPurple : Colors.white, fontWeight: sel ? FontWeight.w700 : FontWeight.w500))),
                  Text(c.dialCode, style: TextStyle(fontSize: 13, color: sel ? kPurple : Colors.white.withOpacity(0.4), fontWeight: FontWeight.w600)),
                  if (sel) ...[const SizedBox(width: 8), const Icon(Icons.check_rounded, size: 18, color: kPurple)],
                ]),
              ),
            );
          },
        )),
      ]),
    );
  }
}
