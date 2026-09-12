import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';
import '../models/admin_permissions.dart';
import '../services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminFormEditorScreen
// Full proposal form editor with:
//   - Toggle required/optional per field
//   - Edit dropdown options (add, remove, reorder, rename)
//   - Edit range min/max
//   - Remove / restore fields
//   - Save as named template
//   - View all saved templates (like profile view cards)
//   - Restore all defaults
// ─────────────────────────────────────────────────────────────────────────────

// ── Default field definitions ─────────────────────────────────────────────────

const _kDefaultFields = <Map<String, dynamic>>[
  {'key':'gender',          'label':'Gender',               'type':'dropdown', 'required':true,  'options':['Male','Female']},
  {'key':'marital_status',  'label':'Marital Status',       'type':'dropdown', 'required':false, 'options':['Never married','Married','Divorced','Khula','Widowed']},
  {'key':'sect',            'label':'Sect / Maslak',        'type':'dropdown', 'required':false, 'options':['Sunni','Shia','Barelvi','Deobandi','Ahl-e-Hadith','Other']},
  {'key':'language',        'label':'Native Language',      'type':'dropdown', 'required':false, 'options':['Urdu','Punjabi','Pashto','Sindhi','Saraiki','Balochi','English']},
  {'key':'education',       'label':'Education Level',      'type':'dropdown', 'required':false, 'options':['Matric','FSc/FA','Diploma',"Bachelor's","Master's",'MPhil','PhD','Other']},
  {'key':'family_type',     'label':'Family Type',          'type':'dropdown', 'required':false, 'options':['Joint family','Separate Family']},
  {'key':'home_type',       'label':'House',                'type':'dropdown', 'required':false, 'options':['Own House','Rented House']},
  {'key':'practice_level',  'label':'Practice Level',       'type':'dropdown', 'required':false, 'options':['Very Religious','Moderate','Liberal','Prefer not to say']},
  {'key':'complexion',      'label':'Complexion',           'type':'dropdown', 'required':false, 'options':['Fair','Wheatish','Brown','Dark']},
  {'key':'monthly_income',  'label':'Monthly Income',       'type':'dropdown', 'required':false, 'options':['Under 30K','30K – 60K','60K – 100K','100K – 200K','200K – 500K','500K+']},
  {'key':'employment_type', 'label':'Employment Type',      'type':'dropdown', 'required':false, 'options':['Full-time','Part-time','Self-employed','Business','Freelance','Not employed']},
  {'key':'father_alive',    'label':'Father',               'type':'dropdown', 'required':false, 'options':['Alive','Deceased']},
  {'key':'mother_alive',    'label':'Mother',               'type':'dropdown', 'required':false, 'options':['Alive','Deceased']},
  {'key':'has_siblings',    'label':'Has Siblings',         'type':'dropdown', 'required':false, 'options':['Yes','No']},
  {'key':'has_kids',        'label':'Has Kids',             'type':'dropdown', 'required':false, 'options':['Yes','No']},
  {'key':'has_car',         'label':'Has Car',              'type':'dropdown', 'required':false, 'options':['Yes','No']},
  {'key':'has_generator',   'label':'Has Generator',        'type':'dropdown', 'required':false, 'options':['Yes','No']},
  {'key':'has_solar',       'label':'Has Solar',            'type':'dropdown', 'required':false, 'options':['Yes','No']},
  {'key':'has_servant',     'label':'Has Servant',          'type':'dropdown', 'required':false, 'options':['Yes','No']},
  {'key':'smokes',          'label':'Smokes',               'type':'dropdown', 'required':false, 'options':['Yes','No']},
  {'key':'physically_active','label':'Physically Active',   'type':'dropdown', 'required':false, 'options':['Yes','No']},
  {'key':'age',             'label':'Age',                  'type':'range',    'required':false, 'min':18, 'max':70, 'unit':'years'},
  {'key':'height',          'label':'Height',               'type':'range',    'required':false, 'min':48, 'max':84, 'unit':'inches', 'hint':"e.g. 5'6\" = 66 inches"},
  {'key':'weight',          'label':'Weight',               'type':'range',    'required':false, 'min':30, 'max':200,'unit':'kg'},
  {'key':'salary_range',    'label':'Salary Range',         'type':'range',    'required':false, 'min':0,  'max':5000000,'unit':'PKR'},
  {'key':'name',            'label':'Full Name',            'type':'text',     'required':true},
  {'key':'phone',           'label':'Contact Phone',        'type':'text',     'required':true},
  {'key':'cnic',            'label':'CNIC Number',          'type':'text',     'required':true},
  {'key':'about',           'label':'About',                'type':'textarea', 'required':false},
  {'key':'looking_for',     'label':'Looking For',          'type':'textarea', 'required':false},
];

// ── Helpers ───────────────────────────────────────────────────────────────────

String _typeLabel(String t) => t == 'dropdown' ? 'Dropdown' : t == 'range' ? 'Range' : t == 'textarea' ? 'Text Area' : 'Text';
Color  _typeColor(String t) => t == 'dropdown' ? kPurple : t == 'range' ? kTeal : t == 'textarea' ? kAmber : const Color(0xFF6B7280);
IconData _typeIcon(String t) => t == 'dropdown' ? Icons.arrow_drop_down_circle_rounded : t == 'range' ? Icons.tune_rounded : t == 'textarea' ? Icons.notes_rounded : Icons.text_fields_rounded;

// ── Main Screen ───────────────────────────────────────────────────────────────

class AdminFormEditorScreen extends StatefulWidget {
  const AdminFormEditorScreen({super.key});
  @override State<AdminFormEditorScreen> createState() => _AdminFormEditorScreenState();
}

class _AdminFormEditorScreenState extends State<AdminFormEditorScreen> {
  bool _loading = true;
  bool _saving  = false;
  List<Map<String, dynamic>> _fields   = [];
  List<Map<String, dynamic>> _templates = [];
  final Set<String> _removedKeys = {};

  @override
  void initState() { super.initState(); _load(); }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final settings = await SupabaseService.instance.fetchAppSettings();
      final raw = settings['form_field_config'];
      if (raw != null && raw.toString().isNotEmpty) {
        final decoded = jsonDecode(raw.toString()) as List;
        final loaded  = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final existingKeys = loaded.map((f) => f['key'] as String).toSet();
        final removed = <String>{};
        for (final def in _kDefaultFields) {
          if (!existingKeys.contains(def['key'])) removed.add(def['key'] as String);
        }
        setState(() { _fields = loaded; _removedKeys.addAll(removed); });
      } else {
        setState(() { _fields = _kDefaultFields.map((e) => Map<String, dynamic>.from(e)).toList(); });
      }
      await _loadTemplates();
    } catch (_) {
      setState(() { _fields = _kDefaultFields.map((e) => Map<String, dynamic>.from(e)).toList(); });
    }
    setState(() => _loading = false);
  }

  Future<void> _loadTemplates() async {
    try {
      final res = await SupabaseService.instance.client
          .from('form_templates')
          .select('id, name, fields, created_at')
          .order('created_at', ascending: false);
      setState(() => _templates = (res as List).map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (_) {}
  }

  // ── Save current config ───────────────────────────────────────────────────

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      await SupabaseService.instance.client
          .from('app_settings')
          .upsert({'key': 'form_field_config', 'value': jsonEncode(_fields)});
      if (mounted) _snack('Config saved', kGreen);
    } catch (e) {
      if (mounted) _snack('Save failed: $e', kRose);
    }
    setState(() => _saving = false);
  }

  // ── Save as template ──────────────────────────────────────────────────────

  Future<void> _saveAsTemplate() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1730),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Save as Template', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Template name (e.g. Basic Form)',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.07),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(
            onPressed: () {
              final v = nameCtrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(context, v);
            },
            child: const Text('Save', style: TextStyle(color: kPurple, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await SupabaseService.instance.client.from('form_templates').insert({
        'name': name,
        'fields': _fields,
      });
      _snack('Template "$name" saved', kGreen);
      await _loadTemplates();
    } catch (e) {
      _snack('Error: $e', kRose);
    }
  }

  // ── Delete template ───────────────────────────────────────────────────────

  Future<void> _deleteTemplate(String id, String name) async {
    final ok = await _confirm('Delete "$name"?', 'This template will be permanently removed.');
    if (!ok) return;
    try {
      await SupabaseService.instance.client.from('form_templates').delete().eq('id', id);
      _snack('Template deleted', kRose);
      await _loadTemplates();
    } catch (e) {
      _snack('Error: $e', kRose);
    }
  }

  // ── View template ─────────────────────────────────────────────────────────

  void _viewTemplate(Map<String, dynamic> template) {
    final fields = (template['fields'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _TemplateViewScreen(name: template['name'] as String, fields: fields,
        onLoadIntoEditor: () {
          Navigator.pop(context);
          setState(() {
            _fields = fields.map((e) => Map<String, dynamic>.from(e)).toList();
            _removedKeys.clear();
            final existingKeys = _fields.map((f) => f['key'] as String).toSet();
            for (final def in _kDefaultFields) {
              if (!existingKeys.contains(def['key'])) _removedKeys.add(def['key'] as String);
            }
          });
          _snack('Template loaded into editor', kPurple);
        },
      ),
    ));
  }

  // ── Restore all ───────────────────────────────────────────────────────────

  Future<void> _restoreAll() async {
    final ok = await _confirm('Restore All Defaults?', 'All your changes will be lost and the form will go back to its original state.');
    if (!ok) return;
    setState(() {
      _fields = _kDefaultFields.map((e) => Map<String, dynamic>.from(e)).toList();
      _removedKeys.clear();
    });
    await _saveConfig();
  }

  // ── Field actions ─────────────────────────────────────────────────────────

  void _toggleRequired(int index) {
    final field = _fields[index];
    // Prevent unchecking truly system-required fields (name, phone, cnic, gender)
    final systemRequired = const ['name','phone','cnic','gender'].contains(field['key']);
    if (systemRequired && field['required'] == true) {
      _snack('"${field['label']}" must always be required', kAmber);
      return;
    }
    setState(() => _fields[index]['required'] = !(field['required'] == true));
  }

  void _removeField(int index) async {
    final field = _fields[index];
    if (field['required'] == true) {
      _snack('"${field['label']}" is required and cannot be removed', kAmber);
      return;
    }
    final ok = await _confirm('Remove "${field['label']}"?', 'This field will be hidden from the form. You can restore it later.');
    if (!ok) return;
    setState(() { _removedKeys.add(field['key'] as String); _fields.removeAt(index); });
  }

  void _restoreField(String key) {
    final def = _kDefaultFields.firstWhere((f) => f['key'] == key, orElse: () => {});
    if (def.isEmpty) return;
    setState(() { _removedKeys.remove(key); _fields.add(Map<String, dynamic>.from(def)); });
  }

  void _editDropdown(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1730),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DropdownEditor(
        field: Map<String, dynamic>.from(_fields[index]),
        onSave: (updated) => setState(() => _fields[index] = updated),
      ),
    );
  }

  void _editRange(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1730),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RangeEditor(
        field: Map<String, dynamic>.from(_fields[index]),
        onSave: (updated) => setState(() => _fields[index] = updated),
      ),
    );
  }

  void _editLabel(int index) async {
    final ctrl = TextEditingController(text: _fields[index]['label'] as String);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1730),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Label', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true, fillColor: Colors.white.withOpacity(0.07),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save', style: TextStyle(color: kPurple, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) setState(() => _fields[index]['label'] = result);
  }

  // ── Utils ─────────────────────────────────────────────────────────────────

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<bool> _confirm(String title, String msg) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1A1730),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          content: Text(msg, style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 13, height: 1.5)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm', style: TextStyle(color: kRose, fontWeight: FontWeight.w800))),
          ],
        ),
      ) ?? false;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF100E1F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16132A),
        foregroundColor: Colors.white,
        title: const Text('Form Editor', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [
          TextButton.icon(
            onPressed: _restoreAll,
            icon: const Icon(Icons.restore_rounded, size: 16, color: kAmber),
            label: const Text('Restore All', style: TextStyle(color: kAmber, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _saving
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: kPurple, strokeWidth: 2)),
                  )
                : PopupMenuButton<String>(
                    color: const Color(0xFF1E1A33),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: (v) { if (v == 'save') _saveConfig(); else _saveAsTemplate(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(10)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down_rounded, color: Colors.white, size: 18),
                      ]),
                    ),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'save', child: Row(children: [
                        Icon(Icons.save_rounded, color: kPurple, size: 18),
                        SizedBox(width: 10),
                        Text('Save Config', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ])),
                      const PopupMenuItem(value: 'template', child: Row(children: [
                        Icon(Icons.bookmark_add_rounded, color: kGreen, size: 18),
                        SizedBox(width: 10),
                        Text('Save as Template', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ])),
                    ],
                  ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPurple))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [

                // ── Templates section ────────────────────────────────────
                if (_templates.isNotEmpty) ...[
                  _sectionLabel('SAVED TEMPLATES'),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 68,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _templates.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final t = _templates[i];
                        final fields = (t['fields'] as List?) ?? [];
                        return GestureDetector(
                          onTap: () => _viewTemplate(t),
                          child: Container(
                            width: 160,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF16132A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: kPurple.withOpacity(0.3)),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                              Row(children: [
                                const Icon(Icons.bookmark_rounded, color: kPurple, size: 13),
                                const SizedBox(width: 5),
                                Expanded(child: Text(t['name'] as String,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                                    overflow: TextOverflow.ellipsis)),
                              ]),
                              const SizedBox(height: 4),
                              Text('${fields.length} fields  •  tap to view',
                                  style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11)),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Active fields ─────────────────────────────────────────
                _sectionLabel('FORM FIELDS  •  ${_fields.length} active'),
                const SizedBox(height: 10),
                ..._fields.asMap().entries.map((e) => _FieldCard(
                  index: e.key, field: e.value,
                  onEditLabel:   () => _editLabel(e.key),
                  onEditOptions: e.value['type'] == 'dropdown' ? () => _editDropdown(e.key)
                               : e.value['type'] == 'range'    ? () => _editRange(e.key)
                               : null,
                  onToggleRequired: () => _toggleRequired(e.key),
                  onRemove: () => _removeField(e.key),
                )),

                // ── Removed fields ────────────────────────────────────────
                if (_removedKeys.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionLabel('REMOVED FIELDS'),
                  const SizedBox(height: 10),
                  ..._removedKeys.map((key) {
                    final def = _kDefaultFields.firstWhere((f) => f['key'] == key, orElse: () => {'label': key});
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(children: [
                        Icon(Icons.remove_circle_outline_rounded, size: 15, color: Colors.white.withOpacity(0.25)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(def['label'] as String? ?? key,
                            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w600))),
                        GestureDetector(
                          onTap: () => _restoreField(key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: kGreen.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                            child: const Text('Restore', style: TextStyle(fontSize: 12, color: kGreen, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ]),
                    );
                  }),
                ],
              ],
            ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.3), letterSpacing: 1.0));
}

// ── Field Card ────────────────────────────────────────────────────────────────

class _FieldCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> field;
  final VoidCallback onEditLabel;
  final VoidCallback? onEditOptions;
  final VoidCallback onToggleRequired;
  final VoidCallback onRemove;

  const _FieldCard({
    required this.index, required this.field,
    required this.onEditLabel, required this.onEditOptions,
    required this.onToggleRequired, required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final type      = field['type'] as String;
    final label     = field['label'] as String;
    final isReq     = field['required'] == true;
    final tc        = _typeColor(type);
    final systemReq = const ['name','phone','cnic','gender'].contains(field['key']);

    String preview;
    if (type == 'dropdown') {
      final opts = (field['options'] as List?)?.cast<String>() ?? [];
      preview = opts.take(3).join(', ') + (opts.length > 3 ? '  +${opts.length - 3} more' : '');
    } else if (type == 'range') {
      preview = '${field['min']} – ${field['max']} ${field['unit'] ?? ''}';
    } else if (type == 'textarea') {
      preview = 'Long text field';
    } else {
      preview = 'Text input';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isReq ? kPurple.withOpacity(0.25) : Colors.white.withOpacity(0.07)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
          child: Row(children: [
            Icon(_typeIcon(type), size: 15, color: tc),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white))),
            // Required toggle
            GestureDetector(
              onTap: onToggleRequired,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isReq ? kRose.withOpacity(0.15) : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isReq ? kRose.withOpacity(0.4) : Colors.white.withOpacity(0.1)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(isReq ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 11, color: isReq ? kRose : Colors.white.withOpacity(0.3)),
                  const SizedBox(width: 4),
                  Text(isReq ? 'Required' : 'Optional',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: isReq ? kRose : Colors.white.withOpacity(0.3))),
                  if (systemReq) ...[
                    const SizedBox(width: 3),
                    Icon(Icons.lock_rounded, size: 9, color: kRose.withOpacity(0.5)),
                  ],
                ]),
              ),
            ),
            // Edit options
            if (onEditOptions != null)
              IconButton(icon: Icon(Icons.settings_rounded, size: 15, color: tc.withOpacity(0.7)),
                  onPressed: onEditOptions, padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32), tooltip: 'Edit'),
            // Edit label
            IconButton(icon: Icon(Icons.edit_rounded, size: 14, color: Colors.white.withOpacity(0.35)),
                onPressed: onEditLabel, padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32), tooltip: 'Rename'),
            // Remove
            if (!systemReq)
              IconButton(icon: Icon(Icons.delete_outline_rounded, size: 15, color: kRose.withOpacity(0.5)),
                  onPressed: onRemove, padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32), tooltip: 'Remove'),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: tc.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(_typeLabel(type), style: TextStyle(fontSize: 10, color: tc, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(preview,
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.33)), overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ]),
    );
  }
}

// ── Template View Screen ──────────────────────────────────────────────────────

class _TemplateViewScreen extends StatelessWidget {
  final String name;
  final List<Map<String, dynamic>> fields;
  final VoidCallback onLoadIntoEditor;

  const _TemplateViewScreen({required this.name, required this.fields, required this.onLoadIntoEditor});

  @override
  Widget build(BuildContext context) {
    final required = fields.where((f) => f['required'] == true).toList();
    final optional = fields.where((f) => f['required'] != true).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF100E1F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16132A),
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text('${fields.length} fields', style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4))),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: onLoadIntoEditor,
              icon: const Icon(Icons.edit_rounded, size: 15),
              label: const Text('Load into Editor', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPurple, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // Summary card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16132A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kPurple.withOpacity(0.25)),
            ),
            child: Row(children: [
              Expanded(child: _statItem('Total', '${fields.length}', Icons.list_rounded, kPurple)),
              _divider(),
              Expanded(child: _statItem('Required', '${required.length}', Icons.star_rounded, kRose)),
              _divider(),
              Expanded(child: _statItem('Optional', '${optional.length}', Icons.star_outline_rounded, kTeal)),
            ]),
          ),
          const SizedBox(height: 20),

          // Required fields
          if (required.isNotEmpty) ...[
            _sectionLabel('REQUIRED FIELDS'),
            const SizedBox(height: 10),
            ...required.map((f) => _TemplateFieldRow(field: f)),
            const SizedBox(height: 20),
          ],

          // Optional fields
          if (optional.isNotEmpty) ...[
            _sectionLabel('OPTIONAL FIELDS'),
            const SizedBox(height: 10),
            ...optional.map((f) => _TemplateFieldRow(field: f)),
          ],
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon, Color color) {
    return Column(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
    ]);
  }

  Widget _divider() => Container(width: 1, height: 50, color: Colors.white.withOpacity(0.07));

  Widget _sectionLabel(String text) => Text(text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.3), letterSpacing: 1.0));
}

class _TemplateFieldRow extends StatelessWidget {
  final Map<String, dynamic> field;
  const _TemplateFieldRow({required this.field});

  @override
  Widget build(BuildContext context) {
    final type  = field['type'] as String;
    final label = field['label'] as String;
    final isReq = field['required'] == true;
    final tc    = _typeColor(type);

    String detail;
    if (type == 'dropdown') {
      final opts = (field['options'] as List?)?.cast<String>() ?? [];
      detail = opts.join(' · ');
    } else if (type == 'range') {
      detail = '${field['min']} – ${field['max']} ${field['unit'] ?? ''}';
    } else {
      detail = _typeLabel(type);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16132A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(children: [
        Icon(_typeIcon(type), size: 14, color: tc),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            if (isReq) const Icon(Icons.star_rounded, size: 10, color: kRose),
          ]),
          const SizedBox(height: 3),
          Text(detail, style: TextStyle(color: Colors.white.withOpacity(0.33), fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: tc.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
          child: Text(_typeLabel(type), style: TextStyle(fontSize: 9, color: tc, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// ── Dropdown Editor Sheet ─────────────────────────────────────────────────────

class _DropdownEditor extends StatefulWidget {
  final Map<String, dynamic> field;
  final void Function(Map<String, dynamic>) onSave;
  const _DropdownEditor({required this.field, required this.onSave});
  @override State<_DropdownEditor> createState() => _DropdownEditorState();
}

class _DropdownEditorState extends State<_DropdownEditor> {
  late List<String> _options;
  final _newCtrl = TextEditingController();

  @override void initState() { super.initState(); _options = List<String>.from((widget.field['options'] as List?) ?? []); }
  @override void dispose() { _newCtrl.dispose(); super.dispose(); }

  void _add() {
    final v = _newCtrl.text.trim();
    if (v.isEmpty || _options.contains(v)) return;
    setState(() => _options.add(v));
    _newCtrl.clear();
  }

  void _remove(int i) {
    if (_options.length <= 1) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('At least 1 option required'), backgroundColor: kAmber)); return; }
    setState(() => _options.removeAt(i));
  }

  void _edit(int i) async {
    final ctrl = TextEditingController(text: _options[i]);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1730),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Option', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        content: TextField(controller: ctrl, autofocus: true, style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(filled: true, fillColor: Colors.white.withOpacity(0.07),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save', style: TextStyle(color: kPurple, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) setState(() => _options[i] = result);
  }

  void _restoreDefault() {
    final key = widget.field['key'] as String;
    final def = _kDefaultFields.firstWhere((f) => f['key'] == key, orElse: () => {});
    if (def.isEmpty) return;
    setState(() => _options = List<String>.from((def['options'] as List?) ?? []));
  }

  void _save() {
    final updated = Map<String, dynamic>.from(widget.field);
    updated['options'] = _options;
    widget.onSave(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // SafeArea handles notch + bottom bezel
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.72),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(2))),
            // Title row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(children: [
                Expanded(child: Text('Edit: ${widget.field['label']}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
                TextButton(onPressed: _restoreDefault,
                    child: const Text('Restore default', style: TextStyle(color: kAmber, fontSize: 12, fontWeight: FontWeight.w700))),
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(backgroundColor: kPurple, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ]),
            ),
            // Reorderable list
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: _options.length,
                onReorder: (o, n) { setState(() { if (n > o) n--; final item = _options.removeAt(o); _options.insert(n, item); }); },
                itemBuilder: (_, i) => ListTile(
                  key: ValueKey(_options[i]),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: Icon(Icons.drag_handle_rounded, color: Colors.white.withOpacity(0.3), size: 20),
                  title: Text(_options[i], style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.edit_rounded, size: 16, color: kPurple), onPressed: () => _edit(i)),
                    IconButton(icon: Icon(Icons.close_rounded, size: 16, color: kRose.withOpacity(0.7)), onPressed: () => _remove(i)),
                  ]),
                ),
              ),
            ),
            // Add new option
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _newCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Add new option...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                      filled: true, fillColor: Colors.white.withOpacity(0.06),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _add,
                  child: Container(padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: kPurple, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.add_rounded, color: Colors.white, size: 20)),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Range Editor Sheet ────────────────────────────────────────────────────────

class _RangeEditor extends StatefulWidget {
  final Map<String, dynamic> field;
  final void Function(Map<String, dynamic>) onSave;
  const _RangeEditor({required this.field, required this.onSave});
  @override State<_RangeEditor> createState() => _RangeEditorState();
}

class _RangeEditorState extends State<_RangeEditor> {
  late TextEditingController _minCtrl;
  late TextEditingController _maxCtrl;

  @override void initState() { super.initState(); _minCtrl = TextEditingController(text: '${widget.field['min']}'); _maxCtrl = TextEditingController(text: '${widget.field['max']}'); }
  @override void dispose() { _minCtrl.dispose(); _maxCtrl.dispose(); super.dispose(); }

  void _restoreDefault() {
    final key = widget.field['key'] as String;
    final def = _kDefaultFields.firstWhere((f) => f['key'] == key, orElse: () => {});
    if (def.isEmpty) return;
    setState(() { _minCtrl.text = '${def['min']}'; _maxCtrl.text = '${def['max']}'; });
  }

  void _save() {
    final min = int.tryParse(_minCtrl.text.trim());
    final max = int.tryParse(_maxCtrl.text.trim());
    if (min == null || max == null || min >= max) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Min must be less than Max'), backgroundColor: kAmber));
      return;
    }
    final updated = Map<String, dynamic>.from(widget.field)..['min'] = min..['max'] = max;
    widget.onSave(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.field['label'] as String;
    final unit  = widget.field['unit']  as String? ?? '';
    final hint  = widget.field['hint']  as String?;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Edit range: $label',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
                TextButton(onPressed: _restoreDefault,
                    child: const Text('Restore default', style: TextStyle(color: kAmber, fontSize: 12, fontWeight: FontWeight.w700))),
              ]),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(hint, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12)),
              ],
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: _rangeField('Min ($unit)', _minCtrl)),
                const SizedBox(width: 12),
                Expanded(child: _rangeField('Max ($unit)', _maxCtrl)),
              ]),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(backgroundColor: kPurple, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text('Save Range', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _rangeField(String hint, TextEditingController ctrl) => TextField(
    controller: ctrl,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
    textAlign: TextAlign.center,
    decoration: InputDecoration(
      hintText: hint, hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
      filled: true, fillColor: Colors.white.withOpacity(0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
  );
}
