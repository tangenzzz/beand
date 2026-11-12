import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../models/coffee.dart';
import '../../models/shot_phases.dart';
import '../../models/taste_profile.dart';
import '../../models/gear.dart';
import '../../models/grind_scale.dart';
import '../../models/grinder.dart';
import '../../services/app_settings.dart';
import '../../services/gear_store.dart';
import '../../services/shot_setup.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/taste_chips.dart';
import '../beans/bean_form_screen.dart';
import '../beans/bean_widgets.dart';
import '../../widgets/value_select_row.dart';
import '../live/grind_from_zero.dart';
import '../live/grind_panel.dart';
import '../live/ruler_picker.dart';
import '../settings/gear_dialogs.dart';
import 'history_logic.dart';
import 'history_widgets.dart';
import 'new_shot_header.dart';
import 'temperature_chart.dart';
import 'shot_analysis_section.dart';
import 'shot_facts_section.dart';
import 'shot_chart.dart';
import 'shot_share_screen.dart';

// Expandable list below the card: Compare, Bean, Dose or Grind — never more
// than one at a time (as in the pre-shot card).
enum _Open {
  compare,
  bean,
  dose,
  grind,
  chain,
  // Only for a shot added by hand (NewShotHeader and its numbers).
  method,
  profile,
  time,
  yield,
  ratio,
  temp,
}

// All stored data of a shot in one card: header with rating (tappable) and
// bean (tappable, editable afterwards), metrics (dose/grind editable by tap,
// ratio is always recomputed from them), chart with stage bar, rating, notes
// (editable), and below that the AI analysis.
class ShotDetailScreen extends StatefulWidget {
  const ShotDetailScreen({
    super.key,
    required this.shotId,
    this.analyse = false,
    this.isNew = false,
    this.pickFile,
  });

  final int shotId;

  /// A shot just added by hand ("+" in the History header): brew method,
  /// date, profile and curve on top, time/yield/ratio/temp editable too;
  /// "Save" keeps it, the cross discards it.
  final bool isNew;

  /// Tests hand in the shot file for [isNew]; otherwise the file picker.
  final Future<Uint8List?> Function()? pickFile;

  /// Opened from the post-shot card: start the analysis right away (if there
  /// is none yet) and scroll the section into view.
  final bool analyse;

  @override
  State<ShotDetailScreen> createState() => _ShotDetailScreenState();
}

class _ShotDetailScreenState extends State<ShotDetailScreen> {
  late final AppDatabase _db = context.read<AppDatabase>();
  late final StreamSubscription<ShotEntry?> _sub;
  ShotEntry? _entry;
  List<ShotReading>? _readings;
  List<ShotPhase> _phases = const [];

  ShotEntry? _other;
  List<ShotReading>? _otherReadings;

  _Open? _open;
  List<ShotEntry>? _allShots;
  List<Bean> _beanList = const [];
  late final StreamSubscription<List<Bean>> _beansSub;

  int? _cursorMs;
  double? _doseDraft;
  double? _grindDraft;
  String? _markerDraft;
  Timer? _writeDebounce;
  // Shot added by hand: the numbers an import would bring.
  double? _secondsDraft;
  double? _yieldDraft;
  double? _tempDraft;
  Timer? _numbersDebounce;
  // The temperature chart of Decent files: folded away by default.
  bool _temperatureOpen = false;

  @override
  void initState() {
    super.initState();
    _sub = _db.watchShotEntry(widget.shotId).listen((entry) {
      if (!mounted) return;
      setState(() => _entry = entry);
    });
    _loadReadings();
    _beansSub = _db.watchBeans().listen((beans) {
      if (!mounted) return;
      setState(() => _beanList = beans);
    });
  }

  void _loadReadings() {
    _db.readingsFor(widget.shotId).then((r) {
      if (!mounted) return;
      setState(() {
        _readings = _withScaleFlow(r);
        _phases = computePhases(r);
        _cursorMs = null;
      });
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _beansSub.cancel();
    _writeDebounce?.cancel();
    _numbersDebounce?.cancel();
    super.dispose();
  }

  // Cross on a shot added by hand: it goes again (it was stored right away,
  // like every change in the detail).
  Future<void> _discard() async {
    await _db.deleteShots([widget.shotId]);
    if (mounted) Navigator.of(context).pop();
  }

  // Time and yield of a shot added by hand, the temp of any shot —
  // debounced like dose/grind.
  void _setNumbers({double? seconds, double? yieldGrams, double? temp}) {
    setState(() {
      _secondsDraft = seconds ?? _secondsDraft;
      _yieldDraft = yieldGrams ?? _yieldDraft;
      _tempDraft = temp ?? _tempDraft;
    });
    _numbersDebounce?.cancel();
    _numbersDebounce = Timer(const Duration(milliseconds: 400), () {
      _db.updateShotFields(
        widget.shotId,
        ShotsCompanion(
          durationMs: _secondsDraft == null
              ? const Value.absent()
              : Value((_secondsDraft! * 1000).round()),
          finalWeight: _yieldDraft == null
              ? const Value.absent()
              : Value(_yieldDraft),
          profileTemp: _tempDraft == null
              ? const Value.absent()
              : Value(_tempDraft),
        ),
      );
    });
  }

  void _toggle(_Open list) {
    setState(() => _open = _open == list ? null : list);
  }

  void _close() => setState(() => _open = null);

  Future<void> _toggleCompare() async {
    if (_open == _Open.compare) {
      _close();
      return;
    }
    _allShots ??= await _db.watchShotEntries().first;
    if (!mounted) return;
    setState(() => _open = _Open.compare);
  }

  Future<void> _selectCompare(ShotEntry picked) async {
    _close();
    final readings = await _db.readingsFor(picked.shot.id);
    if (!mounted) return;
    setState(() {
      _other = picked;
      _otherReadings = _withScaleFlow(readings);
    });
  }

  // Candidates: first shots with the same bean, then with the same profile,
  // then all the rest — newest first in each group. Pour-over brews and
  // espresso shots are only compared among themselves.
  List<ShotEntry> _compareCandidates(ShotEntry current) {
    final pourOver = _isPourOver(current.shot);
    int rank(ShotEntry e) {
      // Via the entry's bean: deleted beans (tombstones) do not count as a
      // shared bean.
      if (current.bean != null && e.bean?.id == current.bean!.id) {
        return 0;
      }
      if (e.shot.profileName == current.shot.profileName) return 1;
      return 2;
    }

    final others = [
      for (final e in _allShots ?? const <ShotEntry>[])
        if (e.shot.id != current.shot.id && _isPourOver(e.shot) == pourOver) e,
    ];
    others.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : b.shot.timestamp.compareTo(a.shot.timestamp);
    });
    return others;
  }

  void _clearCompare() => setState(() {
    _other = null;
    _otherReadings = null;
  });

  Future<void> _delete() async {
    final confirmed = await confirmDeleteShots(context, 1);
    if (!confirmed || !mounted) return;
    await _db.deleteShots([widget.shotId]);
    if (mounted) Navigator.of(context).pop();
  }

  // Share: go straight to the image preview; plain text is no longer
  // needed.
  void _share() {
    final e = _entry;
    if (e == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ShotShareScreen(entry: e, readings: _readings ?? const []),
      ),
    );
  }

  Future<void> _addBean() async {
    final created = await Navigator.of(context)
        .push<Bean>(MaterialPageRoute(builder: (_) => const BeanFormScreen()));
    if (created == null || !mounted) return;
    _close();
    await _db.setShotBean(widget.shotId, created.id);
  }

  void _selectBean(Bean bean) {
    _close();
    _db.setShotBean(widget.shotId, bean.id);
  }

  GearStore? get _gear {
    try {
      return context.read<GearStore>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  // Brew chain chosen afterwards: the shot takes what the chain holds now
  // (grinder, burrs, pieces). On the newest shot of its machine the
  // pre-shot card follows, so the next brew starts with it too.
  Future<void> _selectChain(Shot shot, String chainId) async {
    _close();
    final store = _gear;
    final chain = store?.chains.where((c) => c.id == chainId).firstOrNull;
    if (store == null || chain == null) return;
    final pieces = store.gearOf(chain);
    final grinderGear = pieces
        .where((g) => g.type == GearType.grinder)
        .firstOrNull;
    final grinder = grinderGear == null ? null : grinderFromGear(grinderGear);
    await _db.setShotChain(
      shot.id,
      chainId: chain.id,
      grinder: grinder?.name,
      burrs: grinder?.activeBurrs,
      brewedWith: pieces.isEmpty
          ? null
          : [for (final g in pieces) g.label].join('\n'),
      grindZero: grinder?.zeroPoint?.value,
    );
    final newest = await _db.lastShot(machine: shot.machine);
    if (!mounted || newest?.id != shot.id) return;
    try {
      context.read<ShotSetups>().forMachine(shot.machine).setChain(chain.id);
    } on ProviderNotFoundException {
      // Screens built without the setups (tests).
    }
  }

  Future<void> _addChain(Shot shot) async {
    final added = await showChainDialog(context);
    if (added != null && mounted) await _selectChain(shot, added.id);
  }

  // Rulers report every change while dragging: debounce writes (as in
  // ShotSetup._changed / PreShotCard).
  void _setDose(double v) {
    setState(() => _doseDraft = v);
    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(milliseconds: 400), () {
      _db.setShotDose(widget.shotId, v);
    });
  }

  void _setGrind(double v, String? marker) {
    setState(() {
      _grindDraft = v;
      _markerDraft = marker;
    });
    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(milliseconds: 400), () {
      _db.setShotGrind(widget.shotId, grindSizeText(v), marker: marker);
    });
  }

  // The shot's grinder, found by the name it was brewed with — its scale
  // shapes the grind ruler; without one the ruler is as before.
  Grinder? _grinderOf(Shot shot) {
    final name = shot.grinder;
    final store = _gear;
    if (name == null || store == null) return null;
    final g = store
        .ofType(GearType.grinder)
        .where((g) => g.model == name)
        .firstOrNull;
    return g == null ? null : grinderFromGear(g);
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    return Scaffold(
      appBar: widget.isNew
          ? AppBar(
              leading: IconButton(
                tooltip: 'Discard',
                icon: const Icon(Icons.close),
                onPressed: _discard,
              ),
              title: Text(
                entry != null && _isPourOver(entry.shot)
                    ? 'New brew'
                    : 'New shot',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.accent,
                  ),
                  child: const Text('Save'),
                ),
                const SizedBox(width: 8),
              ],
            )
          : AppBar(
              titleSpacing: 0,
              title: Text(
                entry == null ? '' : dateTimeLabel(entry.shot.timestamp),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Share',
                  icon: Icon(
                    Icons.share_outlined,
                    color: context.colors.textSecondary,
                  ),
                  onPressed: entry == null ? null : _share,
                ),
              ],
            ),
      body: entry == null
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.tileOuterMargin,
                0,
                AppSpacing.tileOuterMargin,
                AppSpacing.tileOuterMargin * 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(AppRadii.tile),
                    ),
                    child: _content(entry),
                  ),
                  // Delete at the very end, clearly separated from the
                  // content — the same button as in the profile (instead of
                  // an icon in the title bar). A new shot has the cross.
                  if (!widget.isNew)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 20, 10, 4),
                      child: AppButton(
                        label: _isPourOver(entry.shot)
                            ? 'Delete brew'
                            : 'Delete shot',
                        icon: Icons.delete_outline,
                        variant: AppButtonVariant.destructive,
                        expand: true,
                        onPressed: _delete,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  // Does this machine store a temperature per data point? The GaggiMate
  // import writes its only boiler sensor to barUp
  // (gaggimate_shot_sync_service); on the Meticulous that holds one of four
  // sensors, which have their own temperature card.
  static bool _tracksTemperature(Shot? shot) => shot?.machine == 'gaggimate';

  static bool _isPourOver(Shot shot) => shot.machine == 'pourover';

  // Pour over measures flow only at the scale and stores it as
  // gravimetricFlow (pourover_brew_service); chart and values read `flow`.
  // If the pump flow is missing, the scale flow takes its place.
  static List<ShotReading> _withScaleFlow(List<ShotReading> readings) => [
    for (final r in readings)
      r.flow == null && r.gravimetricFlow != null
          ? r.copyWith(flow: Value(r.gravimetricFlow))
          : r,
  ];

  Widget _ruler(
    String key, {
    required double value,
    required double min,
    required double max,
    required double step,
    required String unit,
    required ValueChanged<double> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: RulerPicker(
      key: ValueKey(key),
      value: value.clamp(min, max),
      min: min,
      max: max,
      step: step,
      unit: unit,
      showLabels: false,
      onChanged: onChanged,
    ),
  );

  // Brewed with (or, for older shots, the grinder) — tappable when there are
  // chains to pick from.
  Widget _chainLine(Shot shot) {
    final colors = context.colors;
    final store = _gear;
    final choosable = store != null;
    final gear = shot.brewedWith;
    final Widget line;
    if (gear != null && gear.isNotEmpty) {
      line = BrewedWith(gear: gear);
    } else if (shot.grinder != null) {
      line = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.blender_outlined, size: 14, color: colors.textTertiary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              [shot.grinder!, ?shot.burrs].join('  ·  '),
              key: const ValueKey('shot-grinder'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      );
    } else if (choosable) {
      line = const BrewedWith(gear: '—');
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        key: const ValueKey('shot-chain'),
        borderRadius: BorderRadius.circular(8),
        onTap: choosable ? () => _toggle(_Open.chain) : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: line),
            if (choosable)
              Icon(
                _open == _Open.chain ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: colors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _chainList(Shot shot) {
    final store = context.watch<GearStore>();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ValueSelectList<String>(
        options: [
          for (final c in store.chains)
            ValueOption(
              value: c.id,
              title: c.name,
              subtitle: [for (final g in store.gearOf(c)) g.displayName]
                  .join(', '),
            ),
        ],
        selected: shot.brewChainId,
        onSelected: (id) {
          HapticFeedback.selectionClick();
          _selectChain(shot, id);
        },
        action: ValueSelectAction('New brew chain', () => _addChain(shot)),
        emptyText: 'No brew chains yet.',
      ),
    );
  }

  Widget _content(ShotEntry entry) {
    final shot = entry.shot;
    final showsTemperature = _tracksTemperature(shot);
    // Pour over: no pressure, no local or AI analysis (both are tailored to
    // espresso), flow in g/s from the scale.
    final isPourOver = _isPourOver(shot);
    // Pour over talks about "brew", the machines about "shot".
    final noun = isPourOver ? 'brew' : 'shot';
    final bean = entry.bean;
    final other = _other?.shot;
    final compare = other != null && _otherReadings != null;
    final otherIsOlder = compare && other.timestamp.isBefore(shot.timestamp);
    final roaster = bean?.roaster?.trim();
    final profile = shot.profileName ?? '';

    String? ratio(Shot s) => ratioLabel(s)?.replaceFirst('1 : ', '');
    // When comparing, both values are always shown side by side, even equal
    // ones (otherwise dose/ratio/grind disappeared as soon as they matched);
    // if the other shot lacks it, a dash is shown.
    String? otherOf(String? theirs) => compare ? (theirs ?? '–') : null;
    String? grindOf(String? raw) {
      final v = double.tryParse(raw ?? '');
      return v?.toStringAsFixed(1) ?? raw;
    }

    // Pour over in minutes (m:ss), espresso in seconds.
    String? t(int? ms) =>
        ms == null ? null : (isPourOver ? clockTime(ms) : seconds(ms));
    String? g(double? v) => v == null ? null : grams(v);
    String? temp(double? v) => v == null ? null : grams(v);

    final readings = _readings;
    final otherReadings = _otherReadings;
    final effectiveCursor = readings == null || readings.isEmpty
        ? 0
        : (_cursorMs ?? extractionEndMs(readings));
    final now = readings == null || readings.isEmpty
        ? null
        : readingNear(readings, effectiveCursor);
    final then =
        readings != null &&
            readings.isNotEmpty &&
            compare &&
            otherReadings != null
        ? readingNear(otherReadings, effectiveCursor)
        : null;
    String? cur(double? v, int decimals) => v?.toStringAsFixed(decimals);

    // The local findings are tailored to espresso (stall, channeling,
    // pressure) — there are none for pour over.
    final showFacts =
        context.select<AppSettings, bool>((s) => s.showShotFacts) &&
        !isPourOver;
    final showStage = context.select<AppSettings, bool>(
      (s) => s.showStageDetails,
    );
    final dose = _doseDraft ?? shot.doseGrams ?? ShotSetup.defaultDose;
    final grindScale = _grinderOf(shot)?.scaleOrStandard ?? GrindScale.standard;
    final grind =
        _grindDraft ??
        double.tryParse(shot.grindSize ?? '') ??
        ShotSetup.defaultGrind;
    // Settings → History: the grind also from the zero point of its day,
    // for this shot and the compared one.
    String? fromZeroNote() {
      if (!context.select<AppSettings, bool>((s) => s.showGrindFromZero)) {
        return null;
      }
      final zero = shot.grindZero;
      final mark = grindScale.hasMarkers
          ? grindScale.markerNamed(_markerDraft ?? shot.grindMarker)
          : null;
      final mine = zero == null
          ? null
          : (mark == null ? grind : grindScale.absolute(grind, mark)) - zero;
      final theirs = compare
          ? shotGrindFromZero(other, _grinderOf(other)?.scale)
          : null;
      if (mine == null && theirs == null) return null;
      String text(double? v) => v == null ? '–' : fromZeroText(v, grindScale);
      return compare
          ? '${text(mine)}  ${text(theirs)} from zero'
          : '${text(mine)} from zero';
    }

    final grindNote = fromZeroNote();

    // Settings → History: how long after roasting, freezer days left out.
    final showOffRoast = context.select<AppSettings, bool>(
      (s) => s.showDaysOffRoast,
    );
    final offRoast = bean != null && showOffRoast
        ? daysOffRoastAt(bean, shot.timestamp)
        : null;

    // Shot added by hand: its numbers can be set like dose and grind.
    final editable = widget.isNew;
    final secs =
        _secondsDraft ??
        (shot.durationMs == null ? null : shot.durationMs! / 1000);
    final yieldGrams = _yieldDraft ?? shot.finalWeight;
    final profileTemp = _tempDraft ?? shot.profileTemp;
    VoidCallback? tapIf(_Open list) => editable ? () => _toggle(list) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (editable) ...[
          NewShotHeader(
            shot: shot,
            pickFile: widget.pickFile,
            openList: switch (_open) {
              _Open.method => 'method',
              _Open.profile => 'profile',
              _ => null,
            },
            onToggle: (list) =>
                _toggle(list == 'method' ? _Open.method : _Open.profile),
            onClose: _close,
            onCurveLoaded: () {
              setState(() {
                _secondsDraft = null;
                _yieldDraft = null;
                _tempDraft = null;
                _doseDraft = null;
                _grindDraft = null;
              });
              _loadReadings();
            },
          ),
          const SizedBox(height: 12),
        ],
        // Header: name (up to two lines) with how long after roasting the
        // shot was made in its row, the stars under that; roaster and profile
        // below the name on their own lines. The right column keeps its own
        // width, the names get all the rest.
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _toggle(_Open.bean),
          child: Row(
            children: [
              ShotAvatar(shot: shot, bean: bean),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // A new shot asks for its bean here until one is
                          // picked (the profile has its own line below). The
                          // chevron follows the name, so it takes no width
                          // from it beside the stars.
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  bean?.name ??
                                      (editable
                                          ? 'Select bean'
                                          : profile.isEmpty
                                          ? (isPourOver ? 'Brew' : 'Shot')
                                          : profile),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: bean == null && editable
                                        ? context.colors.textTertiary
                                        : null,
                                  ),
                                ),
                              ),
                              Icon(
                                _open == _Open.bean
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                color: context.colors.textTertiary,
                                size: 18,
                              ),
                            ],
                          ),
                          if (bean != null &&
                              roaster != null &&
                              roaster.isNotEmpty)
                            Text(
                              roaster,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          if ((bean != null || editable) &&
                              profile.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              profile,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // In the row of the name, the stars below it (a bit
                        // larger than in the list, the shot's main mark).
                        if (offRoast != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              daysOffRoastLabel(offRoast),
                              key: const ValueKey('shot-days-off-roast'),
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        StarRating(
                          rating: shot.rating ?? 0,
                          size: 18,
                          gap: 2,
                          tapPadding: 4,
                          onChanged: (n) => _db.setShotRating(shot.id, n),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_open == _Open.bean)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ValueSelectList<int>(
              options: [
                for (final (bean: b, :searchOnly) in beanPickerOrder(
                  _beanList,
                  selectedId: bean?.id,
                ))
                  ValueOption(
                    value: b.id,
                    searchOnly: searchOnly,
                    title: b.name,
                    subtitle: bagSubtitle(b, _beanList),
                    subtitleIcon: b.openedAt == null
                        ? Icons.lock_outline
                        : null,
                    leading: BeanThumbnail(
                      path: b.photoPath,
                      size: 36,
                      circle: true,
                    ),
                  ),
              ],
              selected: bean?.id,
              onSelected: (id) {
                final picked = _beanList.where((b) => b.id == id).firstOrNull;
                if (picked == null) return;
                HapticFeedback.selectionClick();
                _selectBean(picked);
              },
              action: ValueSelectAction('New bean', _addBean),
              emptyText: 'No beans yet.',
            ),
          ),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: context.colors.divider),
        ),

        // Three columns as one connected, centered block:
        // Time/Dose/Yield(yellow) · Yield/Ratio/Flow(blue) · Temp/Grind/
        // Pressure(green). Dose & grind are tappable (editable), ratio is
        // always recomputed from dose/finalWeight.
        Row(
          children: [
            _Stat(
              'Time',
              secs == null ? null : t((secs * 1000).round()),
              isPourOver ? '' : 's',
              otherOf(t(other?.durationMs)),
              onTap: tapIf(_Open.time),
              active: _open == _Open.time,
            ),
            _Stat(
              isPourOver ? 'Water' : 'Yield',
              g(yieldGrams),
              'g',
              otherOf(g(other?.finalWeight)),
              // Pour over: the yield — the coffee weighed in the server
              // after the brewer came off — small below the water (user
              // 2026-11-04, after trying it as a fourth column); "—"
              // where nothing was weighed.
              note: !isPourOver
                  ? null
                  : shot.beverageGrams != null
                  ? 'Yield ${g(shot.beverageGrams)} g'
                  : 'Yield —',
              onTap: tapIf(_Open.yield),
              active: _open == _Open.yield,
            ),
            _Stat(
              'Temp',
              temp(profileTemp),
              '°C',
              otherOf(temp(other?.profileTemp)),
              // Always editable, like dose and grind (user 2026-11-04): the
              // water temperature is often only known afterwards.
              onTap: () => _toggle(_Open.temp),
              active: _open == _Open.temp,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Stat(
              'Dose',
              g(dose),
              'g',
              otherOf(g(other?.doseGrams)),
              onTap: () => _toggle(_Open.dose),
              active: _open == _Open.dose,
            ),
            _Stat(
              'Ratio',
              '1:${(dose > 0 ? (yieldGrams ?? 0) / dose : 0).toStringAsFixed(1)}',
              '',
              otherOf(other == null ? null : ratio(other)),
              onTap: tapIf(_Open.ratio),
              active: _open == _Open.ratio,
            ),
            _Stat(
              'Grind',
              grindScale.format(grind, withUnit: false),
              grindScale.suffix,
              marker: grindScale.hasMarkers
                  ? grindScale.markerNamed(_markerDraft ?? shot.grindMarker)
                  : null,
              otherOf(grindOf(other?.grindSize)),
              note: grindNote,
              onTap: () => _toggle(_Open.grind),
              active: _open == _Open.grind,
            ),
          ],
        ),
        // The brew chain's gear as it was at brew time: small, two lines at
        // most; tapping it picks another chain, like dose and grind. Older
        // shots without a chain show the grinder and burrs.
        _chainLine(shot),
        if (_open == _Open.chain) _chainList(shot),
        if (_open == _Open.dose)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: RulerPicker(
              key: const ValueKey('dose'),
              value: dose,
              min: 5,
              max: 30,
              unit: 'g',
              showLabels: false,
              onChanged: _setDose,
            ),
          ),
        // Rulers for a shot added by hand, like dose and grind.
        if (_open == _Open.time)
          _ruler(
            'time',
            value: secs ?? (isPourOver ? 180 : 30),
            min: 0,
            max: isPourOver ? 600 : 120,
            step: isPourOver ? 5 : 0.5,
            unit: 's',
            onChanged: (v) => _setNumbers(seconds: v),
          ),
        if (_open == _Open.yield)
          _ruler(
            'yield',
            value: yieldGrams ?? (isPourOver ? 250 : 36),
            min: 0,
            max: isPourOver ? 600 : 100,
            step: isPourOver ? 1 : 0.1,
            unit: 'g',
            onChanged: (v) => _setNumbers(yieldGrams: v),
          ),
        // Ratio sets the yield from the dose.
        if (_open == _Open.ratio)
          _ruler(
            'ratio',
            value: dose > 0 && yieldGrams != null
                ? yieldGrams / dose
                : (isPourOver ? 16 : 2),
            min: 1,
            max: isPourOver ? 20 : 5,
            step: 0.1,
            unit: '',
            onChanged: (v) => _setNumbers(yieldGrams: v * dose),
          ),
        if (_open == _Open.temp)
          _ruler(
            'temp',
            value: profileTemp ?? 93,
            min: 75,
            max: 100,
            step: 0.5,
            unit: '°C',
            onChanged: (v) => _setNumbers(temp: v),
          ),
        if (_open == _Open.grind)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: GrindPanel(
              key: const ValueKey('grind'),
              scale: grindScale,
              value: grindScale.clamp(grind),
              marker: _markerDraft ?? shot.grindMarker,
              onChanged: _setGrind,
            ),
          ),

        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: context.colors.divider),
        ),

        Row(
          children: [
            _Stat(
              // Pour over: the weight curve is the water poured.
              isPourOver ? 'Water' : 'Yield',
              cur(now?.weight, 1),
              'g',
              cur(then?.weight, 1),
              color: context.colors.sensorMid,
            ),
            _Stat(
              'Flow',
              cur(now?.flow, 1),
              isPourOver ? 'g/s' : 'ml/s',
              cur(then?.flow, 1),
              color: context.colors.sensorDown,
            ),
            if (!isPourOver)
              _Stat(
                'Pressure',
                cur(now?.pressure, 1),
                'bar',
                cur(then?.pressure, 1),
                color: context.colors.success,
              ),
            // Fourth column only where there is a temperature curve
            // (GaggiMate): on the Meticulous the temperature is in
            // barUp..barDown and has its own card.
            if (showsTemperature)
              _Stat(
                'Temp',
                cur(now?.barUp, 1),
                '°C',
                cur(then?.barUp, 1),
                color: context.colors.danger,
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (readings == null)
          const SizedBox(height: 260)
        else if (readings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'No curve data for this $noun.',
                style: TextStyle(color: context.colors.textSecondary),
              ),
            ),
          )
        else ...[
          ShotChart(
            readings: readings,
            phases: _phases,
            cursorMs: effectiveCursor,
            onCursorChanged: (ms) => setState(() => _cursorMs = ms),
            other: compare ? _otherReadings : null,
            primaryDashed: compare && !otherIsOlder,
            otherDashed: otherIsOlder,
            showTemperature: showsTemperature,
            otherShowsTemperature: compare && _tracksTemperature(other),
            temperatureTarget: shot.profileTemp,
            stageExpanded: showStage && !isPourOver,
            // The stage details belong to the local analysis: if it is off
            // in the settings, there is no arrow on the stage row either.
            onStageTap: showFacts
                ? () => context.read<AppSettings>().setShowStageDetails(
                    !showStage,
                  )
                : null,
          ),
          // Fixed findings without AI, right below the curve they refer to
          // (stall, channeling, exits, target, target weight).
          // Can be turned off in the History settings.
          if (showFacts)
            ShotFactsSection(
              shot: shot,
              readings: readings,
              phases: _phases,
              cursorMs: effectiveCursor,
              showStage: showStage,
            ),
        ],
        // Decent files: basket, mix and goal temperature in their own chart,
        // folded away until asked for, right above Compare.
        if (readings != null && TemperatureChart.hasData(readings)) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Divider(height: 1, color: context.colors.divider),
          ),
          InkWell(
            key: const ValueKey('temperature-toggle'),
            onTap: () => setState(() => _temperatureOpen = !_temperatureOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.thermostat_outlined,
                    size: 18,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Temperature',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    _temperatureOpen ? Icons.expand_less : Icons.expand_more,
                    size: 22,
                    color: context.colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_temperatureOpen) ...[
            Row(
              children: [
                _Stat(
                  'Basket',
                  cur(now?.barUp, 1),
                  '°C',
                  null,
                  color: TemperatureChart.basketColor(context),
                ),
                _Stat(
                  'Mix',
                  cur(now?.tempMix, 1),
                  '°C',
                  null,
                  color: TemperatureChart.mixColor(context),
                ),
                _Stat(
                  'Goal',
                  cur(now?.tempGoal, 1),
                  '°C',
                  null,
                  color: TemperatureChart.goalColor(context),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TemperatureChart(
              readings: readings,
              cursorMs: effectiveCursor,
              onCursorChanged: (ms) => setState(() => _cursorMs = ms),
            ),
          ],
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: context.colors.divider),
        ),
        // A blank new shot has nothing to compare with yet.
        if (!widget.isNew) ...[
          _CompareRow(
            other: compare ? other : null,
            noun: noun,
            otherIsOlder: otherIsOlder,
            open: _open == _Open.compare,
            onTap: _toggleCompare,
            onClear: _clearCompare,
          ),
          if (_open == _Open.compare)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Builder(
                builder: (context) {
                  final candidates = _compareCandidates(entry);
                  return ValueSelectList<int>(
                    options: [
                      for (final e in candidates)
                        ValueOption(
                          value: e.shot.id,
                          title:
                              e.bean?.name ??
                              (e.shot.profileName ??
                                  (isPourOver ? 'Brew' : 'Shot')),
                          subtitle: dateTimeLabel(e.shot.timestamp),
                          leading: ShotAvatar(
                            shot: e.shot,
                            bean: e.bean,
                            size: 36,
                            badge: 14,
                            ringColor: context.colors.card,
                          ),
                        ),
                    ],
                    selected: _other?.shot.id,
                    onSelected: (id) {
                      final picked = candidates
                          .where((e) => e.shot.id == id)
                          .firstOrNull;
                      if (picked == null) return;
                      HapticFeedback.selectionClick();
                      _selectCompare(picked);
                    },
                    emptyText: 'No other ${noun}s yet.',
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 12),
            child: Divider(height: 1, color: context.colors.divider),
          ),
        ],
        // Rating before the note: you tap the chips first and only then
        // write something, if at all.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TASTE',
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            Text(
              shot.tasteValues.isRated
                  ? '${shot.tasteValues.score} / 100'
                  : 'Tap to rate',
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TasteChips(
          values: shot.tasteValues,
          onAxisChanged: (axis, value) =>
              _db.setShotTaste(shot.id, axis, value),
        ),

        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: Divider(height: 1, color: context.colors.divider),
        ),
        Text(
          'NOTES',
          style: TextStyle(
            color: context.colors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        ShotNotesField(shotId: shot.id, initial: shot.notes),
        if (!isPourOver)
          ShotAnalysisSection(shot: shot, autoStart: widget.analyse),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
    this.label,
    this.value,
    this.unit,
    this.other, {
    this.color,
    this.onTap,
    this.active = false,
    this.marker,
    this.note,
  });

  /// The grinder's index mark the grind was set against: its dot after
  /// the value.
  final GrindMarker? marker;

  /// A small line below the value (the grind from zero).
  final String? note;

  final String label;
  final String? value;
  final String unit;
  // Value of the compared shot (small, dimmed), always when comparing.
  final String? other;
  // Color of the value when the row belongs to a chart line (yield/flow/
  // pressure at the cursor).
  final Color? color;
  // Tappable (dose/grind) — opens a RulerPicker below.
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: active
                    ? context.colors.accent
                    : context.colors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 3),
              Icon(
                Icons.edit_outlined,
                size: 10,
                color: active
                    ? context.colors.accent
                    : context.colors.textTertiary,
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value ?? '–',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color ?? context.colors.textPrimary,
                    ),
                  ),
                  if (value != null && unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  if (other != null)
                    TextSpan(
                      text: '  $other',
                      style: TextStyle(
                        color: (color ?? context.colors.textPrimary).withValues(
                          alpha: 0.45,
                        ),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (marker case final m?) ...[
              const SizedBox(width: 5),
              GrindMarkerDot(
                key: const ValueKey('stat-marker-dot'),
                color: m.color,
              ),
            ],
          ],
        ),
        if (note case final text?)
          Text(
            text,
            key: const ValueKey('stat-note'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.colors.textTertiary,
              fontSize: 10.5,
            ),
          ),
      ],
    );

    return Expanded(
      child: onTap == null
          ? content
          : InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: content,
            ),
    );
  }
}

// "Compare" row in the style of the pre-shot rows (bean, profile): label,
// selected value, arrow; the triggering row is not highlighted.
class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.other,
    required this.noun,
    required this.otherIsOlder,
    required this.open,
    required this.onTap,
    required this.onClear,
  });

  final Shot? other;
  final String noun;
  final bool otherIsOlder;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final shot = other;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.compare_arrows,
              size: 17,
              color: context.colors.textSecondary,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 62,
              child: Text(
                'Compare',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: shot == null
                  ? Text(
                      'Select $noun',
                      style: TextStyle(
                        color: context.colors.textTertiary,
                        fontSize: 14,
                      ),
                    )
                  : Text.rich(
                      TextSpan(
                        text: dateTimeLabel(shot.timestamp),
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 14,
                        ),
                        children: [
                          TextSpan(
                            text: [
                              if (shot.grindSize != null)
                                '   Grind ${shot.grindSize}',
                              otherIsOlder ? '   older' : '   newer',
                            ].join(),
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            if (shot != null)
              IconButton(
                tooltip: 'Remove comparison',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: context.colors.textSecondary,
                ),
                onPressed: onClear,
              ),
            Icon(
              open ? Icons.expand_less : Icons.expand_more,
              color: context.colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Brewed with" and the pieces of the shot's brew chain, small and
/// centered — the shot detail and the share image.
class BrewedWith extends StatelessWidget {
  const BrewedWith({
    super.key,
    required this.gear,
    this.color,
    this.scale = 1,
    this.align = TextAlign.center,
  });

  /// One piece per line, as stored on the shot (Shots.brewedWith).
  final String gear;
  final Color? color;
  final double scale;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pieces = gear.split('\n').where((l) => l.trim().isNotEmpty);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'BREWED WITH  ',
            style: TextStyle(
              color: color ?? colors.textTertiary,
              fontSize: 9.5 * scale,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.9 * scale,
            ),
          ),
          TextSpan(text: pieces.join('  ·  ')),
        ],
      ),
      key: const ValueKey('shot-brewed-with'),
      textAlign: align,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color ?? colors.textSecondary,
        fontSize: 11.5 * scale,
        height: 1.35,
      ),
    );
  }
}
