import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../database/sync_ids.dart';
import '../../models/brew_recipe.dart';
import '../../models/history_import.dart';
import '../../models/shot_file_import.dart';
import '../../services/brew_recipe_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/value_select_row.dart';
import '../beans/bean_widgets.dart';
import 'history_logic.dart';

// Top of the shot detail for a shot added by hand ("+" in the History
// header): what an imported shot brings by itself — brew method, time,
// profile, curve. Everything below (bean, rating, dose, grind, ratio, chain,
// taste, notes) is the normal shot detail. Each choice is written to the
// shot right away, like everything else in the detail.
class NewShotHeader extends StatefulWidget {
  const NewShotHeader({
    super.key,
    required this.shot,
    required this.openList,
    required this.onToggle,
    required this.onClose,
    required this.onCurveLoaded,
    this.pickFile,
  });

  final Shot shot;

  /// Which of the two lists is open ('method', 'profile'), shared with the
  /// detail so only one list is open at a time.
  final String? openList;
  final ValueChanged<String> onToggle;
  final VoidCallback onClose;

  /// After a shot file replaced the curve: the detail reloads it.
  final VoidCallback onCurveLoaded;

  /// Tests hand in the file; otherwise the system file picker.
  final Future<Uint8List?> Function()? pickFile;

  @override
  State<NewShotHeader> createState() => _NewShotHeaderState();
}

class _NewShotHeaderState extends State<NewShotHeader> {
  late final AppDatabase _db = context.read<AppDatabase>();
  StreamSubscription<List<StoredProfile>>? _profilesSub;
  List<StoredProfile> _profiles = const [];
  String? _profilesOf;
  String? _fileNote;

  Shot get _shot => widget.shot;
  bool get _pourOver => _shot.machine == ShotMachine.pourOver.key;

  @override
  void initState() {
    super.initState();
    _watchProfiles();
  }

  @override
  void didUpdateWidget(NewShotHeader old) {
    super.didUpdateWidget(old);
    if (old.shot.machine != _shot.machine) _watchProfiles();
  }

  @override
  void dispose() {
    _profilesSub?.cancel();
    super.dispose();
  }

  // The profiles stored for this brew method (a machine's own list, kept
  // locally); pour over has its recipes instead.
  void _watchProfiles() {
    if (_profilesOf == _shot.machine) return;
    _profilesOf = _shot.machine;
    _profilesSub?.cancel();
    _profiles = const [];
    if (_pourOver) return;
    _profilesSub = _db.watchStoredProfiles(machine: _shot.machine).listen((p) {
      if (mounted) setState(() => _profiles = p);
    });
  }

  List<BrewRecipe> get _recipes {
    try {
      // Only the own profiles (as in Pre Brew), not the whole collection.
      return context.watch<BrewRecipeStore>().ownRecipes;
    } on ProviderNotFoundException {
      return const [];
    }
  }

  void _write(ShotsCompanion c) => _db.updateShotFields(_shot.id, c);

  void _setMachine(ShotMachine m) {
    widget.onClose();
    if (m.key == _shot.machine) return;
    // Another method's profile makes no sense on this one.
    _write(
      ShotsCompanion(
        machine: Value(m.key),
        profileName: const Value(null),
        profileJson: const Value(null),
        profileColor: const Value(null),
        profileImagePath: const Value(null),
      ),
    );
  }

  void _setProfile(StoredProfile p) {
    widget.onClose();
    Map<String, dynamic>? json;
    try {
      final decoded = jsonDecode(p.json);
      if (decoded is Map) json = Map<String, dynamic>.from(decoded);
    } on FormatException {
      json = null;
    }
    final temp = json?['temperature'];
    _write(
      ShotsCompanion(
        profileName: Value(p.name),
        profileImagePath: Value(p.imagePath),
        // As the imports store it: the Meticulous one compacted, the
        // GaggiMate one as is.
        profileJson: Value(
          _shot.machine == ShotMachine.meticulous.key
              ? compactShotProfile(json)
              : p.json,
        ),
        profileTemp: temp is num && _shot.profileTemp == null
            ? Value(temp.toDouble())
            : const Value.absent(),
      ),
    );
  }

  void _setRecipe(BrewRecipe r) {
    widget.onClose();
    // The recipe's numbers as a start where nothing is set yet.
    _write(
      ShotsCompanion(
        profileName: Value(r.name),
        doseGrams: _shot.doseGrams == null
            ? Value(r.doseG)
            : const Value.absent(),
        finalWeight: _shot.finalWeight == null
            ? Value(r.waterMl)
            : const Value.absent(),
        profileTemp: _shot.profileTemp == null && r.waterTempC != null
            ? Value(r.waterTempC)
            : const Value.absent(),
      ),
    );
  }

  Future<void> _pickDate() async {
    widget.onClose();
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _shot.timestamp,
      firstDate: DateTime(2010),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final clock = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_shot.timestamp),
    );
    if (!mounted) return;
    final t = clock ?? TimeOfDay.fromDateTime(_shot.timestamp);
    _write(
      ShotsCompanion(
        timestamp: Value(
          DateTime(day.year, day.month, day.day, t.hour, t.minute),
        ),
      ),
    );
  }

  Future<Uint8List?> _readPickedFile() async {
    final custom = widget.pickFile;
    if (custom != null) return custom();
    // Any type: Android hides .slog/.shot/.json behind extension filters,
    // the content decides what it is.
    final file = await FilePicker.pickFile(dialogTitle: 'Pick a shot file');
    final path = file?.path;
    return path == null ? null : File(path).readAsBytes();
  }

  Future<void> _loadFile() async {
    widget.onClose();
    final Uint8List? bytes;
    try {
      bytes = await _readPickedFile();
    } catch (_) {
      _say('Could not open the file.');
      return;
    }
    if (bytes == null || !mounted) return;
    final ImportedShot file;
    try {
      file = parseShotFile(bytes);
    } on ShotFileException catch (e) {
      _say(e.message);
      return;
    }
    final externalId = file.externalId;
    if (externalId != null &&
        (await _db.knownExternalIds()).contains(externalId)) {
      _say('This shot is already in your history.');
      return;
    }
    final machine = file.machine ?? _shot.machine;
    // A profile file has no curve: an already loaded one stays.
    if (file.readings.isNotEmpty) {
      await _db.replaceShotReadings(_shot.id, file.readings);
    }
    // What the file knows replaces what is set; what it doesn't stays.
    await _db.updateShotFields(
      _shot.id,
      ShotsCompanion(
        machine: Value(machine),
        // Same identity as the automatic import, so it isn't fetched again.
        externalId: externalId == null
            ? const Value.absent()
            : Value(externalId),
        syncId: externalId == null
            ? const Value.absent()
            : Value(machineShotSyncId(machine, externalId)),
        timestamp: _keep(file.timestamp),
        profileName: _keep(file.profileName),
        profileColor: _keep(file.profileColor),
        profileJson: _keep(file.profileJson),
        stageExits: _keep(file.stageExits),
        doseGrams: _keep(file.doseGrams),
        finalWeight: _keep(file.finalWeight),
        durationMs: _keep(file.durationMs),
        grindSize: _keep(file.grind),
        // Without a target in the file, the measured mean stands in — but
        // only where nothing is set yet (a picked profile's stays).
        profileTemp: _keep(
          file.profileTemp ??
              (_shot.profileTemp == null ? file.brewTemp : null),
        ),
        brewTemp: _keep(file.brewTemp),
      ),
    );
    if (!mounted) return;
    setState(
      () => _fileNote = file.readings.isEmpty
          ? file.format
          : '${file.format} · ${file.readings.length} points',
    );
    widget.onCurveLoaded();
  }

  static Value<T> _keep<T>(T? v) => v == null ? const Value.absent() : Value(v);

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final machine = ShotMachine.fromKey(_shot.machine);
    final recipes = _pourOver ? _recipes : const <BrewRecipe>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Every brew method bean'd knows — a new one shows up by itself.
        ValueSelectRow<ShotMachine>(
          icon: Icons.local_cafe_outlined,
          label: 'Method',
          listIndent: 0,
          value: machine,
          open: widget.openList == 'method',
          onToggle: () => widget.onToggle('method'),
          onClose: widget.onClose,
          options: [
            for (final m in ShotMachine.values)
              ValueOption(value: m, title: m.label),
          ],
          onChanged: _setMachine,
        ),
        _tapRow(
          icon: Icons.event_outlined,
          label: 'Date',
          value: dateTimeLabel(_shot.timestamp),
          onTap: _pickDate,
        ),
        if (_pourOver)
          ValueSelectRow<String>(
            icon: Icons.tune,
            label: 'Recipe',
            listIndent: 0,
            placeholder: 'Select recipe',
            valueText: _shot.profileName,
            value: recipes
                .where((r) => r.name == _shot.profileName)
                .firstOrNull
                ?.id,
            open: widget.openList == 'profile',
            onToggle: () => widget.onToggle('profile'),
            onClose: widget.onClose,
            emptyText: 'No recipes yet.',
            options: [
              for (final r in recipes)
                ValueOption(value: r.id, title: r.name, subtitle: r.brewer),
            ],
            onChanged: (id) {
              final r = recipes.where((r) => r.id == id).firstOrNull;
              if (r != null) _setRecipe(r);
            },
          )
        else
          ValueSelectRow<String>(
            icon: Icons.tune,
            label: 'Profile',
            listIndent: 0,
            placeholder: 'Select profile',
            valueText: _shot.profileName,
            value: _profiles
                .where((p) => p.name == _shot.profileName)
                .firstOrNull
                ?.id,
            open: widget.openList == 'profile',
            onToggle: () => widget.onToggle('profile'),
            onClose: widget.onClose,
            emptyText:
                'No ${machine.label} profiles stored yet — they come with '
                'the machine.',
            options: [
              for (final p in _profiles)
                ValueOption(
                  value: p.id,
                  title: p.name,
                  leading: BeanThumbnail(
                    path: p.imagePath,
                    size: 36,
                    circle: true,
                  ),
                ),
            ],
            onChanged: (id) {
              final p = _profiles.where((p) => p.id == id).firstOrNull;
              if (p != null) _setProfile(p);
            },
          ),
        _tapRow(
          icon: Icons.show_chart,
          label: 'Curve',
          value: _fileNote,
          placeholder: 'Load shot file',
          trailing: Icon(
            Icons.upload_file,
            size: 18,
            color: colors.textTertiary,
          ),
          onTap: _loadFile,
          isLast: true,
        ),
      ],
    );
  }

  // A row in the look of the value rows above (icon, label, value), with a
  // tap action instead of a list.
  Widget _tapRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? value,
    String placeholder = '—',
    Widget? trailing,
    bool isLast = false,
  }) {
    return ValueSelectRow<void>.custom(
      icon: icon,
      label: label,
      valueText: value,
      placeholder: placeholder,
      isLast: isLast,
      trailing: trailing,
      showChevron: false,
      open: false,
      onToggle: onTap,
      onClose: () {},
      // Never opens: the tap does the action instead.
      panel: const SizedBox.shrink(),
    );
  }
}
