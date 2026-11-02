import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../models/shot_file_import.dart';
import '../../theme/app_theme.dart';
import '../../widgets/value_select_row.dart';
import 'history_logic.dart';
import 'shot_detail_screen.dart';

// "+" in the History header: a shot that didn't come in by itself — brewed
// elsewhere, before bean'd, on a machine that was offline. Brew method,
// time and the numbers here; a shot file (GaggiMate, Meticulous,
// visualizer.coffee, Decent) fills them and brings the curve along. Bean,
// rating, taste and notes follow in the shot detail, which opens on save.
class NewShotScreen extends StatefulWidget {
  const NewShotScreen({super.key, this.pickFile, this.onSaved});

  /// Tests hand in the file; otherwise the system file picker.
  final Future<Uint8List?> Function()? pickFile;

  /// After saving; by default the new shot's detail replaces this screen.
  final void Function(BuildContext context, int shotId)? onSaved;

  @override
  State<NewShotScreen> createState() => _NewShotScreenState();
}

class _NewShotScreenState extends State<NewShotScreen> {
  static const _labelWidth = 92.0;

  ShotMachine _machine = ShotMachine.values.first;
  DateTime _time = DateTime.now();
  final _profile = TextEditingController();
  final _dose = TextEditingController();
  final _yield = TextEditingController();
  final _seconds = TextEditingController();
  final _grind = TextEditingController();
  final _temp = TextEditingController();
  ImportedShot? _file;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_profile, _dose, _yield, _seconds, _grind, _temp]) {
      c.dispose();
    }
    super.dispose();
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
    final Uint8List? bytes;
    try {
      bytes = await _readPickedFile();
    } catch (_) {
      _say('Could not open the file.');
      return;
    }
    if (bytes == null || !mounted) return;
    final ImportedShot shot;
    try {
      shot = parseShotFile(bytes);
    } on ShotFileException catch (e) {
      _say(e.message);
      return;
    }
    setState(() {
      _file = shot;
      if (shot.machine case final key?) _machine = ShotMachine.fromKey(key);
      if (shot.timestamp case final t?) _time = t;
      _fill(_profile, shot.profileName);
      _fill(_dose, _number(shot.doseGrams));
      _fill(_yield, _number(shot.finalWeight));
      _fill(
        _seconds,
        _number(shot.durationMs == null ? null : shot.durationMs! / 1000),
      );
      _fill(_grind, shot.grind);
      _fill(_temp, _number(shot.profileTemp ?? shot.brewTemp));
    });
  }

  // What the file knows replaces what is typed; what it doesn't know stays.
  static void _fill(TextEditingController c, String? value) {
    if (value != null) c.text = value;
  }

  static String? _number(double? v) {
    if (v == null) return null;
    final rounded = (v * 10).round() / 10;
    return rounded % 1 == 0
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
  }

  static double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  static String? _textOrNull(String text) =>
      text.trim().isEmpty ? null : text.trim();

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(2010),
      lastDate: now,
    );
    if (day == null || !mounted) return;
    final clock = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (!mounted) return;
    final t = clock ?? TimeOfDay.fromDateTime(_time);
    setState(() {
      _time = DateTime(day.year, day.month, day.day, t.hour, t.minute);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final db = context.read<AppDatabase>();
    final file = _file;
    final externalId = file?.externalId;
    if (externalId != null &&
        (await db.knownExternalIds()).contains(externalId)) {
      _say('This shot is already in your history.');
      return;
    }
    setState(() => _saving = true);
    final seconds = _parse(_seconds.text);
    final id = await db.insertShotWithReadings(
      ShotsCompanion.insert(
        timestamp: _time,
        machine: Value(_machine.key),
        externalId: Value(externalId),
        profileName: Value(_textOrNull(_profile.text)),
        profileColor: Value(file?.profileColor),
        profileJson: Value(file?.profileJson),
        stageExits: Value(file?.stageExits),
        doseGrams: Value(_parse(_dose.text)),
        finalWeight: Value(_parse(_yield.text)),
        durationMs: Value(seconds == null ? null : (seconds * 1000).round()),
        grindSize: Value(_textOrNull(_grind.text)),
        profileTemp: Value(_parse(_temp.text)),
        brewTemp: Value(file?.brewTemp),
      ),
      file?.readings ?? const [],
    );
    if (!mounted) return;
    if (widget.onSaved case final saved?) return saved(context, id);
    // On to the detail for bean, rating, taste, notes.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => ShotDetailScreen(shotId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final file = _file;
    final pourOver = _machine == ShotMachine.pourOver;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('New shot'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
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
            Container(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(AppRadii.tile),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  // Every brew method bean'd knows — a new one shows up here
                  // by itself.
                  ValueSelectRow<ShotMachine>(
                    label: 'Brew method',
                    labelWidth: _labelWidth,
                    labelSize: 12,
                    horizontalPadding: AppSpacing.dividerInset,
                    isLast: true,
                    value: _machine,
                    options: [
                      for (final m in ShotMachine.values)
                        ValueOption(value: m, title: m.label),
                    ],
                    onChanged: (m) => setState(() => _machine = m),
                  ),
                  _divider(context),
                  _row(
                    'Date',
                    onTap: _pickTime,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        dateTimeLabel(_time),
                        style: _valueStyle(context),
                      ),
                    ),
                  ),
                  _divider(context),
                  _row(
                    'Curve',
                    onTap: _loadFile,
                    trailing: file == null
                        ? Icon(
                            Icons.upload_file,
                            color: colors.textSecondary,
                            size: 20,
                          )
                        : IconButton(
                            tooltip: 'Remove file',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              Icons.close,
                              color: colors.textSecondary,
                              size: 18,
                            ),
                            onPressed: () => setState(() => _file = null),
                          ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        file == null
                            ? 'Load shot file'
                            : '${file.format} · ${file.readings.length} points',
                        style: file == null
                            ? _valueStyle(context)
                                  .copyWith(color: colors.textTertiary)
                            : _valueStyle(context),
                      ),
                    ),
                  ),
                  _divider(context),
                  _row(
                    pourOver ? 'Recipe' : 'Profile',
                    child: _field(_profile),
                  ),
                  _divider(context),
                  _row(
                    'Dose',
                    child: _field(_dose, suffix: 'g', numeric: true),
                  ),
                  _divider(context),
                  _row(
                    pourOver ? 'Water' : 'Yield',
                    child: _field(_yield, suffix: 'g', numeric: true),
                  ),
                  _divider(context),
                  _row(
                    'Time',
                    child: _field(_seconds, suffix: 's', numeric: true),
                  ),
                  _divider(context),
                  _row('Grind', child: _field(_grind)),
                  _divider(context),
                  _row(
                    'Temp',
                    child: _field(_temp, suffix: '°C', numeric: true),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.dividerInset,
                10,
                AppSpacing.dividerInset,
                24,
              ),
              child: Text(
                'Bean, rating and notes come next, in the shot.',
                style: TextStyle(color: colors.textTertiary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _valueStyle(BuildContext context) => TextStyle(
    color: context.colors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  Widget _row(
    String label, {
    required Widget child,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.dividerInset,
        ),
        child: Row(
          children: [
            SizedBox(
              width: _labelWidth,
              child: Text(
                label,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            // Same gap as the Brew method dropdown, so the values line up.
            const SizedBox(width: 12),
            Expanded(child: child),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller, {
    String? suffix,
    bool numeric = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
          : null,
      style: _valueStyle(context),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        suffixText: suffix,
        suffixStyle: TextStyle(color: context.colors.textSecondary),
      ),
    );
  }

  static Widget _divider(BuildContext context) => Divider(
    height: 1,
    indent: AppSpacing.dividerInset,
    endIndent: AppSpacing.dividerInset,
    color: context.colors.divider,
  );
}
