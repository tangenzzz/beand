import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../machines/espresso_machine.dart';
import '../../../models/profile_draft.dart';
import '../../../models/profile_rules.dart';
import '../../../services/profile_store.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_button.dart';
import 'editor_widgets.dart';
import 'stage_editor_screen.dart';

// Create and edit a profile — the editor's entry page.
//
// Layout follows the Meticulous app: header data, configuration,
// variables, stage list, a fixed save button at the bottom. Each stage
// opens its own page ([StageEditorScreen]).
//
// Saving goes through POST /api/v1/profile/save — that stores the profile
// permanently and does NOT heat (unlike /profile/load).

// The image is sent along as a data URI in the profile JSON; the machine
// stores it and later returns its own path. Nothing bigger fits into a
// request, so it is downscaled first.
const _maxImageBase64 = 700000;

class ProfileEditorScreen extends StatefulWidget {
  const ProfileEditorScreen({
    super.key,
    required this.machine,
    required this.store,
    this.initial,
    this.pickPhoto,
  });

  final EspressoMachine machine;
  final ProfileStore store;

  // For editing an existing profile; null creates a new one.
  final ProfileDraft? initial;

  // Returns the chosen image file ('camera' | 'gallery'). Replaceable only
  // for tests.
  final Future<File?> Function(String source)? pickPhoto;

  @override
  State<ProfileEditorScreen> createState() => _ProfileEditorScreenState();
}

class _ProfileEditorScreenState extends State<ProfileEditorScreen> {
  late ProfileDraft _draft;
  late final TextEditingController _name;
  late final TextEditingController _tagline;
  late final TextEditingController _description;

  bool _saving = false;
  bool _dirty = false;

  // The photo while it is not on the machine yet — for the preview.
  File? _photo;

  @override
  void initState() {
    super.initState();
    // The empty profile comes from the machine — its format sets the layout.
    _draft = widget.initial?.copy() ?? widget.machine.emptyDraft();
    _name = TextEditingController(text: _draft.name);
    _tagline = TextEditingController(text: _draft.shortDescription ?? '');
    _description = TextEditingController(text: _draft.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _tagline.dispose();
    _description.dispose();
    super.dispose();
  }

  void _touch() => setState(() => _dirty = true);

  // -------------------------------------------------------------- Photo

  Future<File?> _pick(String source) async {
    final custom = widget.pickPhoto;
    if (custom != null) return custom(source);
    // Deliberately small: the image travels as base64 in the profile JSON.
    final picked = await ImagePicker().pickImage(
      source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 900,
      maxHeight: 900,
      imageQuality: 72,
    );
    return picked == null ? null : File(picked.path);
  }

  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.tile),
        ),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.photo_camera_outlined,
                color: context.colors.accent,
              ),
              title: Text(
                'Take a photo',
                style: TextStyle(color: context.colors.textPrimary),
              ),
              onTap: () => Navigator.of(sheet).pop('camera'),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: context.colors.accent,
              ),
              title: Text(
                'Pick from gallery',
                style: TextStyle(color: context.colors.textPrimary),
              ),
              onTap: () => Navigator.of(sheet).pop('gallery'),
            ),
            if (_photo != null || _draft.image != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: context.colors.danger,
                ),
                title: Text(
                  'Remove photo',
                  style: TextStyle(color: context.colors.danger),
                ),
                onTap: () => Navigator.of(sheet).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    if (source == 'remove') {
      setState(() {
        _photo = null;
        _draft.image = null;
        _dirty = true;
      });
      return;
    }

    final file = await _pick(source);
    if (file == null || !mounted) return;

    // Does it fit into a request at all? Better to complain now than when
    // saving.
    final bytes = await file.length();
    if (bytes * 4 / 3 > _maxImageBase64) {
      _say('That photo is too large to travel with the profile.');
      return;
    }
    setState(() {
      _photo = file;
      _dirty = true;
    });
  }

  // The image already on the machine. A freshly chosen photo is a data: URI
  // and does not qualify here.
  String? get _machineImageUrl {
    final path = _draft.image;
    if (path == null || !path.startsWith('/')) return null;
    return 'http://${widget.machine.host}$path';
  }

  // Embed the image the way the machine expects it: as a data URI.
  Future<String?> _imageForSaving() async {
    final file = _photo;
    if (file == null) return _draft.image;
    final bytes = await file.readAsBytes();
    final mime = file.path.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  // ------------------------------------------------------------- Stages

  Future<void> _openStage(int index) async {
    final result = await Navigator.of(context).push<ProfileDraft>(
      MaterialPageRoute(
        builder: (_) => StageEditorScreen(
          draft: _draft,
          stageIndex: index,
          profileName: _draft.name,
        ),
      ),
    );
    // null = discarded.
    if (result != null) {
      setState(() {
        _draft = result;
        _dirty = true;
      });
    }
  }

  Future<void> _addStage() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.tile),
        ),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'Add stage',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final type in stageTypes)
              ListTile(
                leading: Icon(
                  Icons.circle,
                  size: 12,
                  color: colorForStageType(context, type),
                ),
                title: Text(
                  labelForType(type),
                  style: TextStyle(color: context.colors.textPrimary),
                ),
                subtitle: Text(
                  switch (type) {
                    'flow' => 'Water pushed into the puck each second',
                    'pressure' => 'The pressure the extraction follows',
                    _ => 'Force on the piston, as a percentage',
                  },
                  style: TextStyle(
                    color: context.colors.textTertiary,
                    fontSize: 11.5,
                  ),
                ),
                onTap: () => Navigator.of(sheet).pop(type),
              ),
          ],
        ),
      ),
    );
    if (type == null || !mounted) return;

    final number = _draft.stages.length + 1;
    final stage = ProfileDraft.defaultStage(number, type)
      ..key = _draft.freeStageKey();
    setState(() {
      _draft.stages.add(stage);
      _dirty = true;
    });
    await _openStage(_draft.stages.length - 1);
  }

  void _removeStage(int index) {
    setState(() {
      _draft.stages.removeAt(index);
      _dirty = true;
    });
  }

  void _duplicateStage(int index) {
    final copy = _draft.stages[index].copy()
      ..key = _draft.freeStageKey()
      ..name = '${_draft.stages[index].name} copy';
    setState(() {
      _draft.stages.insert(index + 1, copy);
      _dirty = true;
    });
  }

  // --------------------------------------------------------------- Saving

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      _draft
        ..name = _name.text.trim()
        ..shortDescription = _tagline.text.trim().isEmpty
            ? null
            : _tagline.text.trim()
        ..description = _description.text.trim().isEmpty
            ? null
            : _description.text.trim()
        ..image = await _imageForSaving();

      final blocking = checkProfile(_draft).where((f) => f.blocksSaving);
      if (blocking.isNotEmpty) {
        _say(blocking.first.message);
        return;
      }

      if (!mounted) return;
      // The machine translates the draft into its own format; for the
      // Meticulous that is one-to-one, for the GaggiMate the codec.
      final result = await widget.machine.uploadProfile(
        widget.machine.profileFromDraft(_draft),
      );
      if (!result.isOk) {
        _say('The machine refused it — ${result.error}');
        return;
      }
      // Update the local copy so the profile shows up in the row right away.
      if (mounted) await widget.store.sync();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: context.colors.card,
        title: Text(
          'Discard this profile?',
          style: TextStyle(color: context.colors.textPrimary, fontSize: 17),
        ),
        content: Text(
          'Nothing has been sent to the machine yet.',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(
              'Keep editing',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(
              'Discard',
              style: TextStyle(color: context.colors.danger),
            ),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  // ---------------------------------------------------------------- Layout

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The text fields only write back on save; but the check goes by what
    // is currently there.
    final checking = _draft.copy()
      ..name = _name.text.trim()
      ..shortDescription = _tagline.text.trim().isEmpty
          ? null
          : _tagline.text.trim();
    final findings = checkProfile(checking);
    final blocking = findings.where((f) => f.blocksSaving).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Text(
            widget.initial == null ? 'New profile' : 'Edit profile',
            style: TextStyle(color: colors.textPrimary, fontSize: 16),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.tileOuterMargin,
                  0,
                  AppSpacing.tileOuterMargin,
                  AppSpacing.tileOuterMargin,
                ),
                children: [
                  EditorCard(
                    children: [
                      _header(),
                      _configuration(),
                      _variables(),
                      _stages(),
                      if (findings.isNotEmpty)
                        EditorSection(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const EditorSectionLabel('Checks'),
                              const SizedBox(height: 8),
                              FindingsList(findings),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            _footer(blocking.isEmpty),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Header

  Widget _header() {
    final colors = context.colors;
    return EditorSection(
      first: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PhotoButton(
                photo: _photo,
                // When editing, the image is still on the machine; without
                // a preview it would look as if it were gone.
                existingUrl: _photo == null ? _machineImageUrl : null,
                onTap: _choosePhoto,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    EditorField(
                      controller: _name,
                      hint: 'Profile name',
                      onChanged: (_) => _touch(),
                    ),
                    const SizedBox(height: 8),
                    EditorField(
                      controller: _tagline,
                      hint: 'Tagline — one line',
                      maxLength: 100,
                      onChanged: (_) => _touch(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Highlight',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ColorRow(
                  value: _draft.accentColor,
                  onChanged: (hex) {
                    _draft.accentColor = hex;
                    _touch();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          EditorField(
            controller: _description,
            hint: 'What is this profile about?',
            maxLines: 4,
            onChanged: (_) => _touch(),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------- Configuration

  Widget _configuration() => EditorSection(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EditorSectionLabel('Configuration'),
        const SizedBox(height: 6),
        EditorSlider(
          label: 'Temperature',
          value: _draft.temperature,
          min: 80,
          max: 100,
          divisions: 40,
          color: context.colors.danger,
          format: (v) => '${trimNumber(v)} °C',
          onChanged: (v) {
            _draft.temperature = v;
            _touch();
          },
        ),
        const SizedBox(height: 6),
        EditorSlider(
          label: 'Target weight',
          value: _draft.finalWeight,
          min: 0,
          max: 100,
          divisions: 200,
          color: context.colors.star,
          format: (v) => '${trimNumber(v)} g',
          hint: EditorHelp.targetWeight,
          onChanged: (v) {
            _draft.finalWeight = v;
            _touch();
          },
        ),
      ],
    ),
  );

  // ------------------------------------------------------------- Variables

  Widget _variables() {
    final colors = context.colors;
    return EditorSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorSectionLabel(
            'Variables',
            trailing: const HelpButton(
              title: 'Variables',
              body: EditorHelp.variables,
            ),
          ),
          const SizedBox(height: 6),
          if (_draft.variables.isEmpty)
            Text(
              'None yet. Open a stage, select a point, limit or exit condition, '
              'then use its gear button to make one.',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11.5,
                height: 1.35,
              ),
            )
          else
            for (final variable in _draft.variables)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: EditorStepper(
                        label: variable.name,
                        value: variable.value,
                        unit: unitForType(variable.type),
                        step: variable.type == 'power' ? 1 : 0.1,
                        max: maxForType(variable.type),
                        color: colorForStageType(context, variable.type),
                        onChanged: (v) {
                          variable.value = v;
                          _touch();
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove variable',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: colors.textTertiary,
                      ),
                      onPressed: _draft.usesVariable(variable.key)
                          ? null
                          : () {
                              setState(() {
                                _draft.variables.remove(variable);
                                _dirty = true;
                              });
                            },
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- Stages

  Widget _stages() {
    final colors = context.colors;
    return EditorSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorSectionLabel(
            'Stages',
            trailing: const HelpButton(
              title: 'Stages',
              body: EditorHelp.stages,
            ),
          ),
          const SizedBox(height: 8),
          // Change the order via the handle — as in both reference apps.
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _draft.stages.length,
            onReorderItem: (from, to) {
              setState(() {
                _draft.stages.insert(to, _draft.stages.removeAt(from));
                _dirty = true;
              });
            },
            itemBuilder: (context, index) => _StageRow(
              key: ValueKey(_draft.stages[index].key),
              index: index,
              stage: _draft.stages[index],
              variables: _draft.variables,
              onTap: () => _openStage(index),
              onDuplicate: () => _duplicateStage(index),
              onRemove: _draft.stages.length > 1
                  ? () => _removeStage(index)
                  : null,
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addStage,
              icon: Icon(Icons.add, size: 17, color: colors.accent),
              label: Text(
                'Add stage',
                style: TextStyle(color: colors.accent, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- Footer

  Widget _footer(bool canSave) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        10,
        14,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: colors.nav,
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: _saving
          ? SizedBox(
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.accent,
                  ),
                ),
              ),
            )
          : AppButton(
              label: 'Save to machine',
              icon: Icons.save_outlined,
              onPressed: canSave ? _save : null,
            ),
    );
  }
}

// ------------------------------------------------------------ Building blocks

class _PhotoButton extends StatelessWidget {
  const _PhotoButton({
    required this.photo,
    required this.onTap,
    this.existingUrl,
  });

  final File? photo;

  // Image already on the machine (only when editing).
  final String? existingUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 86,
          height: 86,
          child: photo != null
              ? Image.file(photo!, fit: BoxFit.cover)
              : existingUrl != null
              ? Image.network(
                  existingUrl!,
                  fit: BoxFit.cover,
                  cacheWidth: 300,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.photo_camera_outlined,
                      size: 20,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Photo',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// The profile's accent color. No color wheel — a row of colors that look
// good on the cards.
class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _choices = [
    '#C8793F',
    '#B5544B',
    '#4E7D5A',
    '#3F6E8C',
    '#7B5EA7',
    '#B08B2E',
    '#5A5F66',
  ];

  @override
  Widget build(BuildContext context) {
    // If the profile has a color that is not in the row (e.g. from a
    // foreign profile), it is added at the front — otherwise it would look
    // unset.
    final known = _choices.map((c) => c.toUpperCase());
    final choices = [
      if (!known.contains(value.toUpperCase())) value,
      ..._choices,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final hex in choices)
          GestureDetector(
            onTap: () => onChanged(hex),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: _parse(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: hex.toUpperCase() == value.toUpperCase()
                      ? context.colors.textPrimary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // A malformed hex value from a foreign profile must not break the page —
  // the rule check reports it anyway.
  static Color _parse(String hex) {
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return value == null ? const Color(0xFF3F3F44) : Color(0xFF000000 | value);
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    super.key,
    required this.index,
    required this.stage,
    required this.variables,
    required this.onTap,
    required this.onDuplicate,
    required this.onRemove,
  });

  final int index;
  final DraftStage stage;
  final List<DraftVariable> variables;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback? onRemove;

  // One line of plain text on what the stage does — the prose summary from
  // the community app, cut down to the essentials.
  String get _summary {
    final unit = unitForType(stage.type);
    final start = stage.points.isEmpty
        ? null
        : stage.points.first.y.resolve(variables);
    final end = stage.points.isEmpty
        ? null
        : stage.points.last.y.resolve(variables);

    final String shape;
    if (start == null || end == null) {
      shape = labelForType(stage.type);
    } else if ((start - end).abs() < 0.05) {
      shape = '${trimNumber(start)} $unit held';
    } else {
      shape = '${trimNumber(start)} → ${trimNumber(end)} $unit';
    }

    final exit = stage.exitTriggers.isEmpty
        ? 'until target weight'
        : stage.exitTriggers
              .map((t) {
                if (!t.needsValue) return 'dial press';
                final v = t.value.resolve(variables);
                if (v == null) return labelForType(t.type).toLowerCase();
                return '${labelForType(t.type).toLowerCase()} '
                    '${t.comparison == '>=' ? '≥' : '≤'} '
                    '${trimNumber(v)} ${unitForType(t.type)}';
              })
              .join(' or ');

    return '$shape · $exit';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = colorForStageType(context, stage.type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.divider),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.drag_indicator,
                      size: 18,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: tint,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              stage.name.trim().isEmpty
                                  ? labelForType(stage.type)
                                  : stage.name.trim(),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  color: colors.card,
                  icon: Icon(
                    Icons.more_horiz,
                    size: 18,
                    color: colors.textTertiary,
                  ),
                  onSelected: (v) =>
                      v == 'duplicate' ? onDuplicate() : onRemove?.call(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'duplicate',
                      child: Text(
                        'Duplicate',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ),
                    if (onRemove != null)
                      PopupMenuItem(
                        value: 'remove',
                        child: Text(
                          'Remove',
                          style: TextStyle(color: colors.danger),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
