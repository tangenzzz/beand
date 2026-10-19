import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
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
import '../live/grind_panel.dart';
import '../live/ruler_picker.dart';
import '../settings/gear_dialogs.dart';
import 'history_logic.dart';
import 'history_widgets.dart';
import 'shot_analysis_section.dart';
import 'shot_facts_section.dart';
import 'shot_chart.dart';
import 'shot_share_screen.dart';

// Expandable list below the card: Compare, Bean, Dose or Grind — never more
// than one at a time (as in the pre-shot card).
enum _Open { compare, bean, dose, grind, chain }

// All stored data of a shot in one card: header with rating (tappable) and
// bean (tappable, editable afterwards), metrics (dose/grind editable by tap,
// ratio is always recomputed from them), chart with stage bar, rating, notes
// (editable), and below that the AI analysis.
class ShotDetailScreen extends StatefulWidget {
  const ShotDetailScreen({
    super.key,
    required this.shotId,
    this.analyse = false,
  });

  final int shotId;

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

  @override
  void initState() {
    super.initState();
    _sub = _db.watchShotEntry(widget.shotId).listen((entry) {
      if (!mounted) return;
      setState(() => _entry = entry);
    });
    _db.readingsFor(widget.shotId).then((r) {
      if (!mounted) return;
      setState(() {
        _readings = _withScaleFlow(r);
        _phases = computePhases(r);
      });
    });
    _beansSub = _db.watchBeans().listen((beans) {
      if (!mounted) return;
      setState(() => _beanList = beans);
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _beansSub.cancel();
    _writeDebounce?.cancel();
    super.dispose();
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
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          entry == null ? '' : dateTimeLabel(entry.shot.timestamp),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                  // an icon in the title bar).
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

    String? t(int? ms) => ms == null ? null : seconds(ms);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _toggle(_Open.bean),
          child: Row(
            children: [
              ShotAvatar(shot: shot, bean: bean),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            bean?.name ??
                                (profile.isEmpty
                                    ? (isPourOver ? 'Brew' : 'Shot')
                                    : profile),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (bean != null &&
                            roaster != null &&
                            roaster.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              roaster,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (bean != null && profile.isNotEmpty) ...[
                      const SizedBox(height: 4),
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
              Icon(
                _open == _Open.bean ? Icons.expand_less : Icons.expand_more,
                color: context.colors.textTertiary,
                size: 18,
              ),
              const SizedBox(width: 8),
              StarRating(
                rating: shot.rating ?? 0,
                size: 14,
                gap: 2,
                onChanged: (n) => _db.setShotRating(shot.id, n),
              ),
            ],
          ),
        ),
        if (_open == _Open.bean)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ValueSelectList<int>(
              options: [
                for (final g in groupBeansByRoaster(_beanList))
                  for (final b in g.beans)
                    ValueOption(
                      value: b.id,
                      title: b.name,
                      subtitle: b.roaster,
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
              t(shot.durationMs),
              's',
              otherOf(t(other?.durationMs)),
            ),
            _Stat(
              'Yield',
              g(shot.finalWeight),
              'g',
              otherOf(g(other?.finalWeight)),
            ),
            _Stat(
              'Temp',
              temp(shot.profileTemp),
              '°C',
              otherOf(temp(other?.profileTemp)),
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
              '1:${(dose > 0 ? (shot.finalWeight ?? 0) / dose : 0).toStringAsFixed(1)}',
              '',
              otherOf(other == null ? null : ratio(other)),
            ),
            _Stat(
              'Grind',
              grindScale.format(grind, withUnit: false),
              grindScale.unit.suffix,
              marker: grindScale.hasMarkers
                  ? grindScale.markerNamed(_markerDraft ?? shot.grindMarker)
                  : null,
              otherOf(grindOf(other?.grindSize)),
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
              onChanged: _setDose,
            ),
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
              'Yield',
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Divider(height: 1, color: context.colors.divider),
        ),
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
  });

  /// The grinder's index mark the grind was set against: its dot after
  /// the value.
  final GrindMarker? marker;

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
