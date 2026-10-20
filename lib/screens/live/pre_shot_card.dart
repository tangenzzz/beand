import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../models/grind_scale.dart';
import '../../models/grinder.dart';
import '../../machines/espresso_machine.dart';
import '../../models/machine_profile.dart';
import '../../services/app_settings.dart';
import '../../services/live_shot_service.dart';
import '../../services/shot_setup.dart';
import '../../theme/app_theme.dart';
import '../beans/bean_form_screen.dart';
import '../beans/bean_stock.dart';
import '../beans/bean_widgets.dart';
import '../../widgets/app_button.dart';
import 'add_profile_dialog.dart';
import 'brew_control_button.dart';
import 'ruler_picker.dart';
import 'tile_title.dart';
import 'chain_choice.dart';
import 'grind_from_zero.dart';
import 'grind_panel.dart';
import '../../widgets/value_select_row.dart';

// Pre-Shot card. "Bean" is real: picks from the beans created in the Beans
// tab (purely local, not sent to the machine). "Profile" is real: picks from
// the machine's actual profile list, highlighted on the machine display
// where the machine supports it (EspressoMachine.highlightProfile —
// deliberately NOT selectProfile, which triggers real heating). Dose/grind
// size open a numeric input field (system keyboard) but only change the
// local display value.
//
// The card only talks to the shared machine interface and therefore runs
// unchanged on Meticulous and GaggiMate — which machine is meant is decided
// by the Provider<EspressoMachine> of the respective Home screen.
class PreShotCard extends StatefulWidget {
  const PreShotCard({super.key, this.onExtraHeight});

  // Reports how much extra height the expanded list (Bean or Profile)
  // needs (0 = closed), so the surrounding PageView grows with it.
  final ValueChanged<double>? onExtraHeight;

  @override
  State<PreShotCard> createState() => _PreShotCardState();
}

enum _OpenList { bean, profile, dose, grind, chain }

// Value ranges of the two rulers (also the bounds for values carried over
// from an earlier shot).
const _doseMin = 5.0;
const _doseMax = 30.0;

class _PreShotCardState extends State<PreShotCard> {
  // Profile only as ID + name: that way it can be restored from ShotSetup at
  // app start without waiting for the machine's profile list.
  String? _selectedProfileId;
  String? _selectedProfileName;
  int? _selectedBeanId;
  // At most one dropdown list at a time.
  _OpenList? _open;
  List<Bean> _beanList = const [];
  Map<int, double> _beanUsage = const {};
  late final StreamSubscription<Map<int, double>> _usageSub;
  List<MachineProfile>? _profiles;
  String? _profilesError;
  late final StreamSubscription<List<Bean>> _beansSub;
  // Empty as long as nothing has been brewed with the selected profile —
  // then the row shows a dash instead of a made-up value, and the shot
  // won't get one later either.
  double? _doseGrams;
  double? _grindSize;

  // "Heating..." lets the dots breathe — a rise and fall instead of an
  // abrupt 0..3 cycle.
  static const _dotPattern = [0, 1, 2, 3, 2, 1];
  Timer? _dotsTimer;
  int _dotsIndex = 0;

  @override
  void initState() {
    super.initState();
    // Profile/bean/dose/grind size live in ShotSetup (persist across app
    // restarts, are updated to the last shot there on start and assigned to
    // the saved shot when the shot starts).
    final setup = context.read<ShotSetup>();
    _selectedProfileId = setup.profileId;
    _selectedProfileName = setup.profileName;
    _selectedBeanId = setup.beanId;
    _doseGrams = setup.doseGrams;
    _grindSize = setup.grindSize;
    _beansSub = context.read<AppDatabase>().watchBeans().listen((beans) {
      if (!mounted) return;
      setState(() => _beanList = beans);
      _reportExtraHeight();
    });
    _usageSub = context.read<AppDatabase>().watchBeanUsage().listen((usage) {
      if (!mounted) return;
      setState(() => _beanUsage = usage);
      _reportExtraHeight();
    });
  }

  @override
  void dispose() {
    _beansSub.cancel();
    _usageSub.cancel();
    _dotsTimer?.cancel();
    // Only reset after the frame: the parent must not be rebuilt during
    // teardown.
    final report = widget.onExtraHeight;
    if (_open != null && report != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => report(0));
    }
    super.dispose();
  }

  void _syncDotsTimer(bool heating) {
    if (heating && _dotsTimer == null) {
      _dotsTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
        if (!mounted) return;
        setState(() => _dotsIndex = (_dotsIndex + 1) % _dotPattern.length);
      });
    } else if (!heating && _dotsTimer != null) {
      _dotsTimer?.cancel();
      _dotsTimer = null;
      _dotsIndex = 0;
    }
  }

  double _extraHeight() => switch (_open) {
    _OpenList.bean => ValueSelectRow.listHeightFor(
      _beanOptions(context.read<AppSettings>().showBeanStock),
      action: true,
    ),
    _OpenList.profile => ValueSelectRow.listHeightFor(
      _profileOptions(),
      action: true,
    ),
    _OpenList.dose => RulerPicker.compactHeight,
    _OpenList.grind => GrindPanel.heightFor(
      context.read<ShotSetup>().grinder?.scaleOrStandard ?? GrindScale.standard,
    ),
    _OpenList.chain => chainListHeight(context),
    null => 0,
  };

  void _reportExtraHeight() => widget.onExtraHeight?.call(_extraHeight());

  void _toggle(_OpenList list) {
    setState(() => _open = _open == list ? null : list);
    _reportExtraHeight();
    if (_open == _OpenList.profile) _loadProfiles();
  }

  void _close() {
    setState(() => _open = null);
    _reportExtraHeight();
  }

  // Fetch the profile list from the machine again on every open; until it
  // arrives (or on error) the list shows a hint instead of entries.
  //
  // The machine doesn't deliver images (the GaggiMate has none, the
  // Meticulous only a path on itself) — those come from the local copy,
  // including user-chosen photos. Hence both: fresh from the machine so new
  // profiles show up immediately, and the images on top.
  Future<void> _loadProfiles() async {
    final machine = context.read<EspressoMachine>();
    final database = context.read<AppDatabase>();
    try {
      final profiles = await machine.fetchProfiles();
      final stored = await database.storedProfilesById(
        machine: machine.machineKey,
      );
      if (!mounted) return;
      setState(() {
        _profiles = [
          for (final profile in profiles)
            _withStoredImage(profile, stored[profile.id]),
        ];
        _profilesError = null;
      });
    } catch (_) {
      if (!mounted) return;
      // Machine unreachable: then at least show the local copy instead of
      // nothing (all profiles are in it after all).
      try {
        final stored = await database
            .watchStoredProfiles(machine: machine.machineKey)
            .first;
        if (!mounted) return;
        final offline = [
          for (final p in stored)
            if (!MachineProfile.isUtility(p)) MachineProfile.fromStored(p),
        ];
        setState(() {
          _profiles = offline;
          _profilesError = offline.isEmpty ? 'Could not load profiles' : null;
        });
      } catch (_) {
        if (mounted) setState(() => _profilesError = 'Could not load profiles');
      }
    }
    _reportExtraHeight();
  }

  MachineProfile _withStoredImage(
    MachineProfile profile,
    StoredProfile? stored,
  ) {
    if (stored == null) return profile;
    final local = stored.customImagePath ?? stored.imagePath;
    if (local == null) return profile;
    return MachineProfile(
      id: profile.id,
      name: profile.name,
      temperature: profile.temperature,
      finalWeight: profile.finalWeight,
      accentColor: profile.accentColor,
      imagePath: profile.imagePath,
      localImagePath: local,
    );
  }

  // Until something is picked, the profile currently loaded on the machine
  // applies (status event). `select` only rebuilds on a change, not on
  // every 100 ms status tick.
  String? _profileLabel(String loadedName) =>
      _selectedProfileName ?? (loadedName.isEmpty ? null : loadedName);

  @override
  Widget build(BuildContext context) {
    // The remaining-amount switch changes which beans are available.
    final showStock = context.select<AppSettings, bool>((s) => s.showBeanStock);
    // The grind ruler follows the scale of the chain's grinder.
    final grinder = context.select<ShotSetup, Grinder?>((s) => s.grinder);
    final grindScale = grinder?.scaleOrStandard ?? GrindScale.standard;
    final grindMarker = context.select<ShotSetup, String?>(
      (s) => s.grindMarker,
    );
    final activeProfile = context
        .select<EspressoMachine, ({String id, String loadedName})>(
          (m) => (
            id: m.liveState.activeProfileId ?? '',
            loadedName: m.liveState.activeProfileName ?? '',
          ),
        );
    final stage = context.select<LiveShotService, ShotStage>((s) => s.stage);
    final isActiveCard = context.select<LiveShotService, bool>(
      (s) => s.activeCard == ActiveCard.pre,
    );
    final stabilized = context.select<LiveShotService, bool>(
      (s) => s.stabilized,
    );
    _syncDotsTimer(stage == ShotStage.heating);
    // When a profile is "locked in" is up to the machine — the Meticulous
    // from preheat on, the GaggiMate only during the brew
    // (see LiveShotService.profileLocked).
    final profileLocked = context.select<LiveShotService, bool>(
      (s) => s.profileLocked,
    );
    _adoptMachineProfileIfStarted(
      activeProfile.id,
      activeProfile.loadedName,
      profileLocked,
    );
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      // Horizontal padding is INSIDE (around the column), not on the card:
      // that way the scroll view reaches the card edge and doesn't clip the
      // glow of the pulsing button.
      padding: const EdgeInsets.symmetric(vertical: 14),
      // Checkbox and button should sit at the bottom of the card, but the
      // content must stay fully reachable when it doesn't fit (large system
      // font, small devices): minHeight + IntrinsicHeight give the spacer at
      // the bottom a height when there's room left, and otherwise let the
      // card scroll instead of overflowing.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : 0,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TileTitle(short: 'PRE', active: isActiveCard),
                    const SizedBox(height: 6),
                    ValueSelectRow<String>(
                      // Nearly the full card width, like Compare.
                      listIndent: 0,
                      icon: Icons.tune,
                      label: 'Profile',
                      valueText: _profileLabel(activeProfile.loadedName),
                      placeholder: 'Select profile',
                      dimValue: profileLocked,
                      enabled: !profileLocked,
                      open: _open == _OpenList.profile && !profileLocked,
                      onToggle: () => _toggle(_OpenList.profile),
                      onClose: _close,
                      value: _selectedProfileId ?? activeProfile.id,
                      listPlaceholder: _profiles == null
                          ? (_profilesError ?? 'Loading…')
                          : null,
                      action: ValueSelectAction(
                        'Add profile',
                        () => showAddProfileDialog(context),
                      ),
                      emptyText: 'No profiles on the machine.',
                      options: _profileOptions(),
                      onChanged: (id) {
                        final picked = _profiles
                            ?.where((p) => p.id == id)
                            .firstOrNull;
                        if (picked != null) _selectProfile(picked);
                      },
                    ),
                    // Bean looked up by ID from the list so edits/deletes
                    // in the Beans tab show up here immediately.
                    ValueSelectRow<int>(
                      // Nearly the full card width, like Compare.
                      listIndent: 0,
                      icon: Icons.coffee_outlined,
                      label: 'Bean',
                      valueText: _selectedBean?.name,
                      placeholder: 'Select bean',
                      open: _open == _OpenList.bean,
                      onToggle: () => _toggle(_OpenList.bean),
                      onClose: _close,
                      value: _selectedBeanId,
                      options: _beanOptions(showStock),
                      onChanged: (id) {
                        final bean = _beanList
                            .where((b) => b.id == id)
                            .firstOrNull;
                        if (bean != null) _selectBean(bean);
                      },
                      action: ValueSelectAction('New bean', _addBean),
                      emptyText: 'No beans yet.',
                    ),
                    ValueSelectRow<void>.custom(
                      icon: Icons.balance,
                      label: 'Dose',
                      valueText: _doseGrams == null
                          ? null
                          : '${_doseGrams!.toStringAsFixed(_doseGrams! % 1 == 0 ? 0 : 1)} g',
                      open: _open == _OpenList.dose,
                      onToggle: () => _toggle(_OpenList.dose),
                      onClose: _close,
                      panel: RulerPicker(
                        value: _doseGrams ?? ShotSetup.defaultDose,
                        min: _doseMin,
                        max: _doseMax,
                        unit: 'g',
                        // Like the grind ruler: no numbers, same height.
                        showLabels: false,
                        onChanged: (v) {
                          setState(() => _doseGrams = v);
                          context.read<ShotSetup>().setDose(v);
                        },
                      ),
                    ),
                    ValueSelectRow<void>.custom(
                      icon: Icons.blur_on,
                      label: 'Grind',
                      valueText: _grindSize == null
                          ? null
                          : grindScale.format(_grindSize!),
                      // Away from a set zero point: how far above the
                      // burrs' touch point that is.
                      valueSuffix: grindMarkerSuffix(
                        grinder,
                        _grindSize,
                        grindMarker,
                      ),
                      trailing: GrindTrailing(
                        grinder: grinder,
                        dial: _grindSize,
                        marker: grindMarker,
                      ),
                      open: _open == _OpenList.grind,
                      onToggle: () => _toggle(_OpenList.grind),
                      onClose: _close,
                      panel: GrindPanel(
                        scale: grindScale,
                        value: grindScale.clamp(
                          _grindSize ?? ShotSetup.defaultGrind,
                        ),
                        marker: grindMarker,
                        onChanged: (v, marker) {
                          setState(() => _grindSize = v);
                          final setup = context.read<ShotSetup>();
                          setup.setGrind(v);
                          setup.setGrindMarker(marker);
                        },
                      ),
                    ),
                    ChainSelectRow(
                      isLast: true,
                      open: _open == _OpenList.chain,
                      onToggle: () => _toggle(_OpenList.chain),
                      onClose: _close,
                    ),
                    // Space before the footer: grows/shrinks with the card
                    // height but never gets smaller than this minimum gap.
                    const SizedBox(height: 14),
                    const Spacer(),
                    // Not every machine supports "Auto Start" (see
                    // LiveShotService.supportsAutoStart).
                    if (context.select<LiveShotService, bool>(
                      (s) => s.supportsAutoStart,
                    ))
                      const _AutoStartCheck(),
                    const SizedBox(height: 10),
                    _buildActionButton(context, stage, stabilized),
                    const SizedBox(height: AppSpacing.tileActionBottom),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Bean? get _selectedBean =>
      _beanList.where((b) => b.id == _selectedBeanId).firstOrNull;

  // Only beans you can brew right now are offered: not frozen and — if
  // remaining amount is enabled — not empty. The selected bean stays in the
  // row even if it has since run empty.
  List<Bean> get _pickableBeans {
    final stock = context.read<AppSettings>().showBeanStock;
    return [
      for (final b in _beanList)
        if (!b.isFrozen && !beanUsedUp(b, _beanUsage, stock: stock)) b,
    ];
  }

  List<ValueOption<String>> _profileOptions() => [
    for (final p in _profiles ?? const <MachineProfile>[])
      ValueOption(
        value: p.id,
        title: p.name,
        subtitle:
            '${p.temperature.toStringAsFixed(p.temperature % 1 == 0 ? 0 : 1)}°C · ${p.finalWeight.toStringAsFixed(0)} g',
        leading: _ProfileAvatar(
          profile: p,
          hostname: context.read<EspressoMachine>().host,
        ),
      ),
  ];

  // With remaining amount like in the bean list: the photo stays 36 in
  // size, the ring goes around it.
  List<ValueOption<int>> _beanOptions(bool showStock) => [
    for (final g in groupBeansByRoaster(_pickableBeans))
      for (final b in g.beans)
        ValueOption(
          value: b.id,
          title: b.name,
          subtitle: b.roaster,
          leading: showStock
              ? BeanStockAvatar(
                  photoPath: b.photoPath,
                  remaining: beanRemaining(b, _beanUsage),
                  total: b.weightGrams,
                  size: 40,
                  labelOverhang: 2,
                )
              : BeanThumbnail(path: b.photoPath, size: 36, circle: true),
        ),
  ];

  Future<void> _addBean() async {
    final created = await Navigator.of(context)
        .push<Bean>(MaterialPageRoute(builder: (_) => const BeanFormScreen()));
    if (created == null || !mounted) return;
    _selectBean(created);
  }

  void _selectBean(Bean bean) {
    setState(() => _selectedBeanId = bean.id);
    context.read<ShotSetup>().setBean(bean.id);
    _close();
    // Priority 2: if there is already a shot with this profile AND this
    // bean, its dose/grind size apply (otherwise the values from the profile
    // selection stay).
    final profileName = _selectedProfileName;
    if (profileName != null) {
      unawaited(_applyLastShotSetup(profileName: profileName, beanId: bean.id));
    }
  }

  void _selectProfile(MachineProfile picked) {
    // highlightProfile (on the Meticulous "profileHover") instead of
    // selectProfile — highlights the profile on the machine display WITHOUT
    // heating. selectProfile would immediately trigger real preheating
    // here (verified live) — which is exactly NOT the desired behavior.
    setState(() {
      _selectedProfileId = picked.id;
      _selectedProfileName = picked.name;
    });
    context.read<ShotSetup>().setProfile(picked.id, picked.name);
    context.read<EspressoMachine>().highlightProfile(picked.id, picked.name);
    _close();
    unawaited(_applyProfileDefaults(picked.name));
  }

  // If a different profile was started on the machine itself, that one
  // applies — not whatever was last picked in the app. Only once the
  // profile is locked in: before that the machine merely shows its last
  // loaded profile, and a pick in the app (only highlighted, not loaded)
  // must not be overwritten by it.
  void _adoptMachineProfileIfStarted(String id, String name, bool locked) {
    if (!locked || id.isEmpty || name.isEmpty || id == _selectedProfileId) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || id == _selectedProfileId) return;
      setState(() {
        _selectedProfileId = id;
        _selectedProfileName = name;
      });
      context.read<ShotSetup>().setProfile(id, name);
      if (_open == _OpenList.profile) _close();
      unawaited(_applyProfileDefaults(name));
    });
  }

  // After a profile change: priority 1 is the last shot with this profile,
  // priority 2 (if a bean is already set) the last shot with exactly this
  // profile+bean combination. Deliberately in sequence so the more specific
  // match overwrites the general one and not the other way round.
  Future<void> _applyProfileDefaults(String profileName) async {
    // Never brewed with this profile? Then dose and grind size stay empty
    // instead of carrying over those of the previous profile. Clear first,
    // then fill — otherwise the old value doesn't flash if there is a match
    // after all.
    _clearSetupFields();
    await _applyLastShotSetup(profileName: profileName);
    final beanId = _selectedBeanId;
    if (beanId == null || !mounted) return;
    await _applyLastShotSetup(profileName: profileName, beanId: beanId);
  }

  void _clearSetupFields() {
    setState(() {
      _doseGrams = null;
      _grindSize = null;
    });
    final setup = context.read<ShotSetup>();
    setup.setDose(null);
    setup.setGrind(null);
  }

  // Take dose/grind size from the most recent matching shot. Only fields
  // this shot actually has; if a value is missing, the current one stays.
  // Without a matching shot nothing happens.
  Future<void> _applyLastShotSetup({
    required String profileName,
    int? beanId,
  }) async {
    final machineKey = context.read<EspressoMachine>().machineKey;
    final shot = await context.read<AppDatabase>().lastShotWithSetup(
      profileName: profileName,
      beanId: beanId,
      machine: machineKey,
    );
    if (shot == null || !mounted) return;
    // Changed in the meantime (tapped twice quickly)? Then discard.
    if (_selectedProfileName != profileName) return;
    if (beanId != null && _selectedBeanId != beanId) return;
    final setup = context.read<ShotSetup>();
    final dose = shot.doseGrams;
    final grind = double.tryParse(shot.grindSize ?? '');
    setState(() {
      if (dose != null) _doseGrams = dose.clamp(_doseMin, _doseMax);
      if (grind != null) {
        _grindSize = (setup.grinder?.scaleOrStandard ?? GrindScale.standard)
            .clamp(grind);
      }
    });
    if (dose != null) setup.setDose(_doseGrams);
    if (grind != null) setup.setGrind(_grindSize);
  }

  Widget _buildActionButton(
    BuildContext context,
    ShotStage stage,
    bool stabilized,
  ) {
    if (stage == ShotStage.idle) {
      return AppButton(
        label: 'Start Profile',
        onPressed: () => _startProfile(context),
      );
    }
    return BrewControlButton(
      stage: stage,
      stabilized: stabilized,
      heatingDots: _dotPattern[_dotsIndex],
      pulsesWhenReady: context.read<LiveShotService>().pulsesWhenReady,
      onStartShot: () => _startShot(context),
    );
  }

  Future<void> _startShot(BuildContext context) async {
    final ok = await context.read<LiveShotService>().startShot();
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Failed to start shot'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _startProfile(BuildContext context) async {
    final profileId = _selectedProfileId;
    if (profileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a profile first'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final ok = await context.read<EspressoMachine>().selectProfile(profileId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Heating started' : 'Failed to start'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// Round profile photo from the machine; the profile color stays as the
// background while the image loads or if it's missing.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile, required this.hostname});

  final MachineProfile profile;
  final String hostname;

  static const _size = 36.0;

  // The local copy takes precedence: it's there once profiles have been
  // synced once, it works without the machine, and a user-chosen photo only
  // lives there anyway.
  File? get _localFile {
    final path = profile.localImagePath;
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = profile.imagePath;
    final local = _localFile;
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: profile.accentColor,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: local != null
          ? Image.file(
              local,
              fit: BoxFit.cover,
              cacheWidth: (_size * 3).round(),
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            )
          : imagePath == null
          ? null
          : Image.network(
              'http://$hostname$imagePath',
              fit: BoxFit.cover,
              cacheWidth: (_size * 3).round(),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : const SizedBox.shrink(),
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
    );
  }
}

// "Auto Start" checkbox right above the button: when checked the app starts
// the brew itself as soon as the machine is at the gate AND the temperature
// is within the stability window (see LiveShotService.autoStartEnabled). It
// stays checked until unchecked — still only one start per preheat.
class _AutoStartCheck extends StatelessWidget {
  const _AutoStartCheck();

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<LiveShotService, bool>(
      (s) => s.autoStartEnabled,
    );
    return Align(
      alignment: Alignment.centerRight,
      child: Semantics(
        label: 'Auto Start',
        checked: enabled,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.read<LiveShotService>().setAutoStart(!enabled),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 0, 7),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Deliberately no color change: whether Auto Start is on is
                // shown by the checkbox alone — the accent color is reserved
                // for card titles and buttons.
                Text(
                  'Auto Start',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: const ValueKey('autoStartBox'),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: context.colors.textTertiary,
                      width: 1.4,
                    ),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: enabled
                      ? Icon(
                          Icons.check,
                          size: 11,
                          color: context.colors.textSecondary,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
