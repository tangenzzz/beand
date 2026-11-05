import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../models/gear.dart';
import '../../../models/pourover_draft.dart';
import '../../../services/brew_recipe_store.dart';
import '../../../services/gear_store.dart';
import '../../../services/pourover_brew_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/underline_select.dart';
import '../../../widgets/value_select_row.dart';
import '../../profile/editor/profile_editor_screen.dart' show ProfileColorRow;
import '../../settings/gear_dialogs.dart';
import '../../settings/my_setup_dialogs.dart';
import '../../settings/settings_widgets.dart';
import '../ruler_picker.dart';

// Create or edit a Pour Over profile: ONE page in ONE card (user 2026-11-04:
// no stack of tiles), rows like the bean form, pours fold out in place. Saved
// in the app; with the Meticulous in Machine mode on the machine too.

const _labelWidth = 112.0;
const _labelSize = 14.0;
// Text and fixed values line up with the value of a [ValueSelectRow].
const _plainLabelWidth = _labelWidth + 12;

// The machine takes a JPEG of at most 300 KiB in the profile.
const _maxImageBytes = 290 * 1024;

/// A photo as the machine takes it: JPEG data URI, null if unreadable.
String? pourOverPhotoDataUri(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) return null;
  var image = decoded;
  if (math.max(image.width, image.height) > 720) {
    image = image.width >= image.height
        ? img.copyResize(image, width: 720)
        : img.copyResize(image, height: 720);
  }
  for (var quality = 80; quality >= 30; quality -= 10) {
    final bytes = img.encodeJpg(image, quality: quality);
    if (bytes.length <= _maxImageBytes) {
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }
  }
  return null;
}

class PourOverProfileEditor extends StatefulWidget {
  const PourOverProfileEditor({super.key, this.profile, this.pickPhoto});

  /// The profile as written; null for a new one.
  final Map<String, dynamic>? profile;

  /// Replaceable for tests; normally camera or gallery.
  final Future<String?> Function(String source)? pickPhoto;

  @override
  State<PourOverProfileEditor> createState() => _PourOverProfileEditorState();
}

class _PourOverProfileEditorState extends State<PourOverProfileEditor> {
  late final PourOverDraft _draft = widget.profile == null
      ? PourOverDraft.empty()
      : PourOverDraft.fromJson(widget.profile!);
  late final _name = TextEditingController(text: _draft.name)
    ..addListener(_nameChanged);
  late final _description = TextEditingController(text: _draft.description);
  late final _grind = TextEditingController(text: _draft.grind);
  late final String _saved = _snapshot();

  // A photo chosen here; the saved one stays until Save.
  String? _newPhoto;
  bool _photoRemoved = false;
  int? _openPour;
  bool _saving = false;

  void _nameChanged() => setState(() {});

  void _sync() {
    _draft
      ..name = _name.text
      ..description = _description.text
      ..grind = _grind.text;
  }

  String _snapshot() {
    _sync();
    return jsonEncode(_draft.toJson());
  }

  bool get _dirty =>
      _newPhoto != null || _photoRemoved || _snapshot() != _saved;

  void _edit(VoidCallback change) => setState(change);

  @override
  void initState() {
    super.initState();
    _saved;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _grind.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _choosePhoto(File? current) async {
    final colors = context.colors;
    Widget item(
      IconData icon,
      String label,
      String value, {
      bool bad = false,
    }) => ListTile(
      leading: Icon(icon, color: bad ? colors.danger : colors.textSecondary),
      title: Text(
        label,
        style: TextStyle(color: bad ? colors.danger : colors.textPrimary),
      ),
      onTap: () => Navigator.pop(context, value),
    );
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            item(Icons.photo_camera_outlined, 'Take photo', 'camera'),
            item(
              Icons.photo_library_outlined,
              'Choose from gallery',
              'gallery',
            ),
            if (current != null)
              item(Icons.delete_outline, 'Remove photo', 'remove', bad: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'remove') {
      setState(() {
        _newPhoto = null;
        _photoRemoved = true;
      });
      return;
    }
    final custom = widget.pickPhoto;
    try {
      final path = custom != null
          ? await custom(action)
          : (await ImagePicker().pickImage(
              source: action == 'camera'
                  ? ImageSource.camera
                  : ImageSource.gallery,
              maxWidth: 1200,
              imageQuality: 85,
            ))?.path;
      if (path == null || !mounted) return;
      setState(() {
        _newPhoto = path;
        _photoRemoved = false;
      });
    } catch (_) {
      _say('Could not load photo');
    }
  }

  Future<void> _save() async {
    _sync();
    final problems = _draft.problems;
    if (problems.isNotEmpty) {
      _say(problems.first);
      return;
    }
    setState(() => _saving = true);
    final store = context.read<BrewRecipeStore>();
    final dialLeads = context.read<PourOverBrewService?>()?.dialLeads ?? false;
    final navigator = Navigator.of(context);
    try {
      // The photo travels with the profile; the saved one too, or the
      // machine would lose it when the profile is replaced.
      final photo =
          _newPhoto ?? (_photoRemoved ? null : store.photoFor(_draft.id)?.path);
      final image = photo == null
          ? null
          : await compute(pourOverPhotoDataUri, photo);
      final json = _draft.toJson(imageDataUri: image, dropImage: _photoRemoved);
      if (_newPhoto != null || _photoRemoved) store.setPhoto(_draft.id, null);
      if (_photoRemoved) store.removeImportedPhoto(_draft.id);
      store.importProfile(json);

      final source = store.machineSource;
      if (dialLeads && source != null) {
        try {
          await source.upload(toMachineJson(json));
          await store.refreshMachine();
        } catch (e) {
          // Kept in the app; saving again sends it.
          debugPrint('Pour Over upload: $e');
          _say(
            "Saved in the app, but the Meticulous didn't take it. Save again to retry.",
          );
        }
      }
      if (mounted) navigator.pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    final navigator = Navigator.of(context);
    if (!_dirty) {
      navigator.pop(false);
      return;
    }
    final colors = context.colors;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.card,
        title: const Text('Discard changes?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Discard', style: TextStyle(color: colors.danger)),
          ),
        ],
      ),
    );
    if (discard == true) navigator.pop(false);
  }

  // ------------------------------------------------------------ Rows

  Widget _ruler({
    required String label,
    required Key key,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
    double step = 1,
    String? text,
    Widget? trailing,
  }) => ValueSelectRow<void>.custom(
    key: key,
    label: label,
    labelSize: _labelSize,
    labelWidth: _labelWidth,
    valueText: text ?? '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} $unit',
    trailing: trailing,
    panel: RulerPicker(
      value: value.clamp(min, max),
      min: min,
      max: max,
      step: step,
      unit: unit,
      showLabels: false,
      onChanged: onChanged,
    ),
  );

  Widget _chainRow() {
    final GearStore store;
    try {
      store = context.watch<GearStore>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    final current = store.chains
        .where((c) => c.id == _draft.chainId)
        .firstOrNull;
    return ValueSelectRow<String>(
      key: const ValueKey('profile-chain'),
      label: 'Chain',
      labelSize: _labelSize,
      labelWidth: _labelWidth,
      placeholder: _draft.brewerName ?? 'Select brew chain',
      value: current?.id,
      emptyText: 'No brew chains yet.',
      options: [
        for (final c in store.chains)
          ValueOption(
            value: c.id,
            title: c.name,
            subtitle: [for (final g in store.gearOf(c)) g.displayName]
                .join(', '),
          ),
      ],
      action: ValueSelectAction('Add brew chain', () async {
        final added = await showChainDialog(context);
        if (added != null) _pickChain(store, added);
      }),
      onChanged: (id) {
        final chain = store.chains.where((c) => c.id == id).firstOrNull;
        if (chain != null) _pickChain(store, chain);
      },
    );
  }

  // The profile names the chain's brewer and filter — that's what travels
  // to the machine and other people.
  void _pickChain(GearStore store, BrewChain chain) {
    if (!mounted) return;
    final pieces = store.gearOf(chain);
    String? name(GearType type) =>
        pieces.where((g) => g.type == type).firstOrNull?.displayName;
    _edit(() {
      _draft
        ..chainId = chain.id
        ..brewerName = name(GearType.brewer)
        ..filterName = name(GearType.filter);
    });
  }

  Widget _timeSpan() {
    final from = _draft.timeFromS;
    final to = math.max(_draft.timeMaxS ?? from, from);
    final colors = context.colors;
    // On ten minutes a usual span is a sliver; five are enough for most.
    final scale = to >= 300 ? maxTimeS : 300.0;
    return ValueSelectRow<void>.custom(
      key: const ValueKey('profile-time'),
      label: 'Total time',
      labelSize: _labelSize,
      labelWidth: _labelWidth,
      valueText: to > from ? '${_clock(from)} – ${_clock(to)}' : _clock(from),
      panel: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: colors.accent,
            thumbColor: colors.accent,
            inactiveTrackColor: colors.divider,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: RangeSlider(
            min: 0,
            max: scale,
            divisions: (scale / 5).round(),
            values: RangeValues(from.clamp(0, scale), to.clamp(0, scale)),
            onChanged: (v) => _edit(() => _draft.setTimeSpan(v.start, v.end)),
          ),
        ),
      ),
    );
  }

  Widget _textRow(
    String label,
    TextEditingController controller, {
    required Key key,
    required int maxLength,
    String? hint,
    ValueChanged<String>? onChanged,
  }) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _plainLabelWidth,
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: _labelSize,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              key: key,
              controller: controller,
              minLines: 1,
              maxLines: 4,
              maxLength: maxLength,
              onChanged: onChanged,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: colors.textPrimary, fontSize: _labelSize),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: hint,
                hintStyle: TextStyle(color: colors.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- Pours

  Widget _pour(int i) {
    final p = _draft.pours[i];
    final colors = context.colors;
    final open = _openPour == i;
    final start = _draft.startsS[i];
    final last = i == _draft.pours.length - 1;
    return Column(
      key: ValueKey('pour-${p.key}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('pour-row-$i'),
          onTap: () => setState(() => _openPour = open ? null : i),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.divider, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(color: colors.textTertiary, fontSize: 13),
                  ),
                ),
                Expanded(
                  child: Text(
                    p.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  ),
                ),
                Text(
                  '${_grams(p.waterG)} g',
                  style: TextStyle(color: colors.sensorMid, fontSize: 14),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 40,
                  child: Text(
                    _clock(start),
                    textAlign: TextAlign.end,
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: colors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: open
              ? _PourFields(
                  key: ValueKey('fields-${p.key}'),
                  pour: p,
                  last: last,
                  index: i,
                  draft: _draft,
                  ruler: _ruler,
                  textRow: _textRow,
                  onEdit: _edit,
                  onCopy: _draft.canAddPour
                      ? () => _edit(() {
                          _draft.copyPour(i);
                          _openPour = i + 1;
                        })
                      : null,
                  onDelete: _draft.pours.length > 1
                      ? () => _edit(() {
                          _draft.removePour(i);
                          _openPour = null;
                        })
                      : null,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final draft = _draft;
    final store = context.watch<BrewRecipeStore>();
    final photo = _newPhoto != null
        ? File(_newPhoto!)
        : _photoRemoved
        ? null
        : store.photoFor(draft.id);
    final editing = widget.profile != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _leave,
          ),
          title: Text(editing ? 'Edit profile' : 'New profile'),
          actions: [
            TextButton(
              onPressed: _name.text.trim().isEmpty || _saving ? null : _save,
              style: TextButton.styleFrom(foregroundColor: colors.accent),
              child: const Text('Save'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: ValueSelectGroup(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
            children: [
              SettingsCard(
                dividers: false,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.dividerInset,
                      14,
                      AppSpacing.dividerInset,
                      14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _PhotoButton(
                              photo: photo,
                              color: draft.accentColor,
                              onTap: () => _choosePhoto(photo),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SetupField(
                                    key: const ValueKey('profile-name'),
                                    controller: _name,
                                    label: 'Name',
                                    autofocus: !editing,
                                  ),
                                  const SizedBox(height: 10),
                                  ProfileColorRow(
                                    value: draft.accentColor,
                                    onChanged: (hex) =>
                                        _edit(() => draft.accentColor = hex),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _textRow(
                          'Description',
                          _description,
                          key: const ValueKey('profile-description'),
                          maxLength: maxDescriptionLength,
                          hint: 'What is this recipe about?',
                        ),
                        _ruler(
                          label: 'Dose',
                          key: const ValueKey('profile-dose'),
                          value: draft.doseG,
                          min: minDoseG,
                          max: maxDoseG,
                          step: 0.1,
                          unit: 'g',
                          onChanged: (v) => _edit(() => draft.doseG = v),
                        ),
                        _ruler(
                          label: 'Water',
                          key: const ValueKey('profile-water'),
                          value: draft.totalWaterG,
                          min: draft.pours.length.toDouble(),
                          max: maxTotalWaterG,
                          unit: 'g',
                          onChanged: (v) => _edit(() => draft.setTotalWater(v)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: colors.divider,
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: _plainLabelWidth,
                                child: Text(
                                  'Ratio',
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: _labelSize,
                                  ),
                                ),
                              ),
                              Text(
                                '1:${draft.ratio.toStringAsFixed(1)}',
                                key: const ValueKey('profile-ratio'),
                                style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: _labelSize,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _ruler(
                          label: 'Temperature',
                          key: const ValueKey('profile-temp'),
                          value: draft.tempC,
                          min: minTempC,
                          max: maxTempC,
                          step: 0.5,
                          unit: '°C',
                          onChanged: (v) => _edit(() => draft.tempC = v),
                        ),
                        _timeSpan(),
                        _textRow(
                          'Grind',
                          _grind,
                          key: const ValueKey('profile-grind'),
                          maxLength: 200,
                          hint: 'Medium-fine',
                        ),
                        _chainRow(),
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'POURS',
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 11,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              if (draft.canAddPour)
                                IconButton(
                                  key: const ValueKey('profile-add-pour'),
                                  tooltip: 'Add pour',
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(Icons.add, color: colors.accent),
                                  onPressed: () => _edit(() {
                                    draft.addPour();
                                    _openPour = draft.pours.length - 1;
                                  }),
                                )
                              else
                                Text(
                                  '$maxPours at most',
                                  style: TextStyle(
                                    color: colors.textTertiary,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _PlanChart(
                          draft: draft,
                          open: _openPour,
                          onPour: (i) => setState(
                            () => _openPour = _openPour == i ? null : i,
                          ),
                        ),
                        const SizedBox(height: 4),
                        for (var i = 0; i < draft.pours.length; i++) _pour(i),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// What one pour holds, folded out under its row.
class _PourFields extends StatefulWidget {
  const _PourFields({
    super.key,
    required this.pour,
    required this.last,
    required this.index,
    required this.draft,
    required this.ruler,
    required this.textRow,
    required this.onEdit,
    required this.onCopy,
    required this.onDelete,
  });

  final DraftPour pour;
  final bool last;
  final int index;
  final PourOverDraft draft;
  final Widget Function({
    required String label,
    required Key key,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
    double step,
    String? text,
    Widget? trailing,
  })
  ruler;
  final Widget Function(
    String label,
    TextEditingController controller, {
    required Key key,
    required int maxLength,
    String? hint,
    ValueChanged<String>? onChanged,
  })
  textRow;
  final void Function(VoidCallback) onEdit;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete;

  @override
  State<_PourFields> createState() => _PourFieldsState();
}

class _PourFieldsState extends State<_PourFields> {
  late final _name = TextEditingController(text: widget.pour.name);
  late final _note = TextEditingController(text: widget.pour.note);

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final p = widget.pour;
    final draft = widget.draft;
    final edit = widget.onEdit;
    final i = widget.index;
    return Padding(
      padding: const EdgeInsets.only(left: 22, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.textRow(
            'Name',
            _name,
            key: ValueKey('pour-name-$i'),
            maxLength: 80,
            onChanged: (v) => edit(() => p.name = v),
          ),
          widget.ruler(
            label: 'Water',
            key: ValueKey('pour-water-$i'),
            value: p.waterG,
            min: 1,
            max: maxTotalWaterG,
            unit: 'g',
            text: '${_grams(p.waterG)} g  to ${_grams(_upTo(draft, i))} g',
            onChanged: (v) => edit(() => p.waterG = v),
          ),
          widget.ruler(
            label: 'Pour time',
            key: ValueKey('pour-time-$i'),
            value: p.durationS,
            min: 1,
            max: maxTimeS,
            unit: 's',
            text:
                '${p.durationS.toStringAsFixed(p.durationS % 1 == 0 ? 0 : 1)} s',
            onChanged: (v) => edit(() => p.durationS = v),
          ),
          // Moves the pour time above, the water stays.
          widget.ruler(
            label: 'Flow',
            key: ValueKey('pour-flow-$i'),
            value: p.flowGps,
            min: minFlowGps,
            max: maxFlowGps,
            step: 0.1,
            unit: 'g/s',
            text: '${p.flowGps.toStringAsFixed(1)} g/s',
            onChanged: (v) => edit(() => p.setFlow(v)),
          ),
          if (widget.last)
            widget.ruler(
              label: 'Drawdown',
              key: ValueKey('pour-wait-$i'),
              value: draft.drawdownS,
              min: 0,
              max: maxTimeS,
              unit: 's',
              onChanged: (v) => edit(() {
                final span =
                    (draft.timeMaxS ?? draft.timeFromS) - draft.timeFromS;
                draft.drawdownS = v;
                if (draft.timeMaxS != null) {
                  draft.timeMaxS = draft.timeFromS + span;
                }
              }),
            )
          else
            widget.ruler(
              label: 'Wait after',
              key: ValueKey('pour-wait-$i'),
              value: p.waitS,
              min: 0,
              max: maxTimeS,
              unit: 's',
              onChanged: (v) => edit(() => p.waitS = v),
            ),
          SetupRow(
            label: 'Temperature',
            child: UnderlineSelect<PourTemp>(
              key: ValueKey('pour-temp-$i'),
              options: const [
                UnderlineOption(PourTemp.hold, 'Hold'),
                UnderlineOption(PourTemp.fall, 'Let fall'),
                UnderlineOption(PourTemp.exact, 'Exact'),
              ],
              value: p.tempMode,
              onChanged: (m) => edit(() {
                p.tempMode = m!;
                if (m == PourTemp.exact) p.tempC ??= draft.tempC;
              }),
            ),
          ),
          if (p.tempMode == PourTemp.exact)
            widget.ruler(
              label: 'Exact',
              key: ValueKey('pour-temp-exact-$i'),
              value: p.tempC ?? draft.tempC,
              min: minTempC,
              max: maxTempC,
              step: 0.5,
              unit: '°C',
              onChanged: (v) => edit(() => p.tempC = v),
            ),
          ValueSelectRow<String>(
            key: ValueKey('pour-pattern-$i'),
            label: 'Style',
            labelSize: _labelSize,
            labelWidth: _labelWidth,
            value: p.pattern ?? '',
            options: [
              const ValueOption(value: '', title: 'Not set'),
              for (final e in pourPatterns.entries)
                ValueOption(value: e.key, title: e.value),
            ],
            onChanged: (v) => edit(() => p.pattern = v.isEmpty ? null : v),
          ),
          widget.ruler(
            label: 'Height',
            key: ValueKey('pour-height-$i'),
            value: p.heightCm ?? 10,
            min: 0,
            max: maxHeightCm,
            unit: 'cm',
            text: p.heightCm == null
                ? 'Not set'
                : '${p.heightCm!.toStringAsFixed(0)} cm',
            // 0 is the way back to not set.
            onChanged: (v) => edit(() => p.heightCm = v > 0 ? v : null),
          ),
          widget.textRow(
            'Note',
            _note,
            key: ValueKey('pour-note-$i'),
            maxLength: maxNoteLength,
            hint: 'Agitation, swirl',
            onChanged: (v) => edit(() => p.note = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.onCopy != null)
                TextButton.icon(
                  key: ValueKey('pour-copy-$i'),
                  onPressed: widget.onCopy,
                  icon: Icon(
                    Icons.copy_outlined,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  label: Text(
                    'Copy',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
              if (widget.onDelete != null)
                TextButton.icon(
                  key: ValueKey('pour-delete-$i'),
                  onPressed: widget.onDelete,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: colors.danger,
                  ),
                  label: Text('Delete', style: TextStyle(color: colors.danger)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  double _upTo(PourOverDraft draft, int i) =>
      draft.pours.take(i + 1).fold(0.0, (s, p) => s + p.waterG);
}

class _PhotoButton extends StatelessWidget {
  const _PhotoButton({
    required this.photo,
    required this.color,
    required this.onTap,
  });

  final File? photo;
  final String color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = int.tryParse(color.replaceFirst('#', ''), radix: 16);
    final file = photo;
    return GestureDetector(
      key: const ValueKey('profile-photo'),
      onTap: onTap,
      child: Container(
        width: 84,
        height: 84,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: value == null ? context.colors.bg : Color(0xFF000000 | value),
          borderRadius: BorderRadius.circular(12),
        ),
        child: file != null
            ? Image.file(
                file,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              )
            : const Icon(Icons.photo_camera_outlined, color: Colors.white70),
      ),
    );
  }
}

// The water on the clock like the live chart: rising while pouring, flat
// while waiting, the pours as bands behind it, the open one tinted. Below it
// the gray bar of the shot chart, one piece per pour; tapping one opens it.
class _PlanChart extends StatelessWidget {
  const _PlanChart({
    required this.draft,
    required this.open,
    required this.onPour,
  });

  final PourOverDraft draft;
  final int? open;
  final ValueChanged<int> onPour;

  static const _axisWidth = 28.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final starts = draft.startsS;
    final pours = draft.pours;
    final endS = math.max(math.max(draft.timeMaxS ?? 0, draft.timeFromS), 1.0);
    final total = draft.totalWaterG;
    // Never 0: the chart's grid needs a height.
    final maxY = math.max(10.0, (total * 1.1).ceilToDouble());
    double bandEnd(int i) => i + 1 < starts.length ? starts[i + 1] : endS;

    var cumulative = 0.0;
    final spots = <FlSpot>[const FlSpot(0, 0)];
    for (var i = 0; i < pours.length; i++) {
      spots.add(FlSpot(starts[i], cumulative));
      cumulative += pours[i].waterG;
      spots.add(FlSpot(starts[i] + pours[i].durationS, cumulative));
    }
    spots.add(FlSpot(endS, cumulative));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 130,
          child: LineChart(
            key: const ValueKey('profile-chart'),
            duration: Duration.zero,
            LineChartData(
              minX: 0,
              maxX: endS,
              minY: 0,
              maxY: maxY,
              clipData: const FlClipData.all(),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: maxY / 2,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: colors.divider,
                  strokeWidth: 1,
                  dashArray: v == 0 ? null : const [2, 4],
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: _axisWidth,
                    interval: maxY / 2,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text(
                        v.toStringAsFixed(0),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: endS <= 120 ? 30 : 60,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text(
                        _clock(v),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              rangeAnnotations: RangeAnnotations(
                verticalRangeAnnotations: [
                  for (var i = 0; i < pours.length; i++)
                    VerticalRangeAnnotation(
                      x1: starts[i],
                      x2: bandEnd(i),
                      color: i == open
                          ? colors.accent.withValues(alpha: 0.10)
                          : (i.isEven
                                ? colors.textPrimary.withValues(alpha: 0.028)
                                : Colors.transparent),
                    ),
                ],
              ),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  color: colors.sensorMid,
                  barWidth: 2.4,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Lined up with the plot, not the axis numbers.
        Padding(
          padding: const EdgeInsets.only(left: _axisWidth),
          child: Row(
            children: [
              for (var i = 0; i < pours.length; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  flex: math.max(
                    1,
                    ((bandEnd(i) - starts[i]) * 1000 / endS).round(),
                  ),
                  child: GestureDetector(
                    key: ValueKey('pour-bar-$i'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPour(i),
                    child: Padding(
                      // Easier to hit than the thin bar itself.
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: colors.textPrimary.withValues(
                            alpha: i == open ? 0.55 : 0.16,
                          ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _clock(double seconds) {
  final s = seconds.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String _grams(double g) => g.toStringAsFixed(g % 1 == 0 ? 0 : 1);
