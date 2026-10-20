import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../database/database.dart';
import '../../../models/brew_recipe.dart';
import '../../../scale/brew_scale.dart';
import '../../../services/app_settings.dart';
import '../../../services/brew_recipe_store.dart';
import '../../../services/live_shot_service.dart';
import '../../../services/pourover_brew_service.dart';
import '../../../services/shot_setup.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/value_select_row.dart';
import '../../beans/bean_form_screen.dart';
import '../../beans/bean_stock.dart';
import '../../beans/bean_widgets.dart';
import '../ruler_picker.dart';
import '../tile_title.dart';
import 'pourover_profile_row.dart';
import 'recipe_format.dart';
import '../../../models/grind_scale.dart';
import '../chain_choice.dart';
import '../grind_from_zero.dart';
import '../grind_panel.dart';

enum _OpenList { recipe, bean, dose, grind, chain, water, temp }

// Pre-brew card: recipe, bean, dose, grind size, water + ratio (derived
// from recipe and dose, hence with a lock) and temperature. Same rows,
// lists and rulers as the machines' pre-shot card.
class PreBrewCard extends StatefulWidget {
  const PreBrewCard({super.key, this.onExtraHeight});

  final ValueChanged<double>? onExtraHeight;

  @override
  State<PreBrewCard> createState() => _PreBrewCardState();
}

class _PreBrewCardState extends State<PreBrewCard> {
  _OpenList? _open;
  List<Bean> _beanList = const [];
  Map<int, double> _beanUsage = const {};
  late final StreamSubscription<List<Bean>> _beansSub;
  late final StreamSubscription<Map<int, double>> _usageSub;

  @override
  void initState() {
    super.initState();
    final db = context.read<AppDatabase>();
    _beansSub = db.watchBeans().listen((beans) {
      if (!mounted) return;
      setState(() => _beanList = beans);
      _reportExtraHeight();
    });
    _usageSub = db.watchBeanUsage().listen((usage) {
      if (!mounted) return;
      setState(() => _beanUsage = usage);
    });
  }

  @override
  void dispose() {
    _beansSub.cancel();
    _usageSub.cancel();
    final report = widget.onExtraHeight;
    if (_open != null && report != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => report(0));
    }
    super.dispose();
  }

  List<Bean> get _pickableBeans {
    final stock = context.read<AppSettings>().showBeanStock;
    return [
      for (final b in _beanList)
        if (!b.isFrozen && !beanUsedUp(b, _beanUsage, stock: stock)) b,
    ];
  }

  double _extraHeight() => switch (_open) {
    _OpenList.recipe => ValueSelectRow.listHeightFor(
      _recipeOptions(_pickerRecipes()),
      action: true,
    ),
    _OpenList.bean => ValueSelectRow.listHeightFor(
      _beanOptions(context.read<AppSettings>().showBeanStock),
      action: true,
    ),
    _OpenList.dose => RulerPicker.compactHeight,
    _OpenList.water || _OpenList.temp => RulerPicker.height,
    _OpenList.grind => GrindPanel.heightFor(
      context.read<ShotSetup>().grinder?.scale ?? const GrindScale(max: 60),
    ),
    _OpenList.chain => chainListHeight(context),
    null => 0,
  };

  List<BrewRecipe> _pickerRecipes() {
    final store = context.read<BrewRecipeStore>();
    final current = context.read<PourOverBrewService>().recipe;
    return [
      ...store.enabledRecipes,
      if (current != null && !store.isEnabled(current.id)) current,
    ];
  }

  void _reportExtraHeight() => widget.onExtraHeight?.call(_extraHeight());

  void _toggle(_OpenList list) {
    setState(() => _open = _open == list ? null : list);
    _reportExtraHeight();
  }

  void _close() {
    setState(() => _open = null);
    _reportExtraHeight();
  }

  List<ValueOption<String>> _recipeOptions(List<BrewRecipe> recipes) => [
    for (final r in recipes)
      ValueOption(
        value: r.id,
        title: r.name,
        subtitle: recipeDetail(r),
        leading: PourOverProfileAvatar(recipe: r),
      ),
  ];

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
    context.read<ShotSetup>().setBean(created.id);
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final brew = context.watch<PourOverBrewService>();
    final setup = context.watch<ShotSetup>();
    // Only the checked profiles (Settings → Home → Pour Over → Profiles);
    // the selected one stays visible even if it has since been unchecked.
    context.watch<BrewRecipeStore>();
    final recipes = _pickerRecipes();
    final showStock = context.select<AppSettings, bool>((s) => s.showBeanStock);
    final isActiveCard = brew.activeCard == ActiveCard.pre;
    final locked = brew.profileLocked;
    final manual = brew.manual;
    // Manual has no recipe — and no defaults from one either.
    final recipe = manual ? null : brew.recipe;
    final plan = brew.plan;
    final bean = _beanList.where((b) => b.id == setup.beanId).firstOrNull;
    final dose = setup.doseGrams ?? recipe?.doseG;
    final grind = setup.grindSize;
    final grinder = setup.grinder;
    final grindScale = grinder?.scale ?? const GrindScale(max: 60);
    final temp = brew.temperature;

    // Nothing can be changed during the brew.
    if ((locked && _open != null) ||
        (manual && _open == _OpenList.recipe) ||
        (!manual && _open == _OpenList.water)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
    }

    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
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
                    const SizedBox(height: 2),
                    if (!manual)
                      ValueSelectRow<String>(
                        // Nearly the full card width, like Compare.
                        listIndent: 0,
                        icon: Icons.tune,
                        label: 'Profile',
                        valueText: recipe?.name,
                        placeholder: 'Select profile',
                        dimValue: locked,
                        enabled: !locked,
                        open: _open == _OpenList.recipe,
                        onToggle: () => _toggle(_OpenList.recipe),
                        onClose: _close,
                        value: recipe?.id,
                        options: _recipeOptions(recipes),
                        onChanged: (id) {
                          final r = recipes
                              .where((r) => r.id == id)
                              .firstOrNull;
                          if (r != null) brew.selectRecipe(r);
                        },
                        // Fetches more profiles from the settings.
                        action: ValueSelectAction(
                          'Choose profiles',
                          () => PourOverProfileRow.openSettings(context),
                        ),
                        emptyText: 'No profiles selected.',
                      ),
                    ValueSelectRow<int>(
                      // Nearly the full card width, like Compare.
                      listIndent: 0,
                      icon: Icons.coffee_outlined,
                      label: 'Bean',
                      valueText: bean?.name,
                      placeholder: 'Select bean',
                      dimValue: locked,
                      enabled: !locked,
                      open: _open == _OpenList.bean,
                      onToggle: () => _toggle(_OpenList.bean),
                      onClose: _close,
                      value: setup.beanId,
                      options: _beanOptions(showStock),
                      onChanged: setup.setBean,
                      action: ValueSelectAction('New bean', _addBean),
                      emptyText: 'No beans yet.',
                    ),
                    ValueSelectRow<void>.custom(
                      icon: Icons.balance,
                      label: 'Dose',
                      valueText: dose == null ? null : '${formatGrams(dose)} g',
                      dimValue: locked,
                      enabled: !locked,
                      open: _open == _OpenList.dose,
                      onToggle: () => _toggle(_OpenList.dose),
                      onClose: _close,
                      panel: RulerPicker(
                        value: dose ?? 15,
                        min: 5,
                        max: 60,
                        unit: 'g',
                        // Like the grind ruler: no numbers, same height.
                        showLabels: false,
                        onChanged: setup.setDose,
                      ),
                    ),
                    ValueSelectRow<void>.custom(
                      icon: Icons.blur_on,
                      label: 'Grind',
                      // Without an own setting the recipe's grind level is
                      // shown ("Coarse") — dimmed, because it is not a
                      // number on your own grinder.
                      valueText: grind != null
                          ? grindScale.format(grind)
                          : (recipe == null
                                ? null
                                : grindLabel(recipe.grindSize)),
                      dimValue: grind == null || locked,
                      enabled: !locked,
                      open: _open == _OpenList.grind,
                      onToggle: () => _toggle(_OpenList.grind),
                      onClose: _close,
                      valueSuffix: grindMarkerSuffix(
                        grinder,
                        grind,
                        setup.grindMarker,
                      ),
                      trailing: GrindTrailing(
                        grinder: grinder,
                        dial: grind,
                        marker: setup.grindMarker,
                      ),
                      // The chain's grinder's scale; without one as before
                      // (0–60, pour over grinds coarser).
                      panel: GrindPanel(
                        scale: grindScale,
                        value: grindScale.clamp(grind ?? 20),
                        marker: setup.grindMarker,
                        onChanged: (v, marker) {
                          setup.setGrind(v);
                          setup.setGrindMarker(marker);
                        },
                      ),
                    ),
                    ChainSelectRow(
                      enabled: !locked,
                      open: _open == _OpenList.chain,
                      onToggle: () => _toggle(_OpenList.chain),
                      onClose: _close,
                    ),
                    // With a recipe the water follows from recipe and dose
                    // (lock); manual, it is the freely chosen target.
                    ValueSelectRow<void>.custom(
                      icon: Icons.water_drop_outlined,
                      label: 'Water',
                      valueText: plan == null
                          ? null
                          : '${formatGrams(plan.totalWaterG)} g  ·  1:${formatRatio(plan.ratio)}',
                      dimValue: !manual || locked,
                      enabled: manual && !locked,
                      trailing: manual
                          ? null
                          : Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: context.colors.textTertiary,
                            ),
                      open: manual && _open == _OpenList.water,
                      onToggle: () => _toggle(_OpenList.water),
                      onClose: _close,
                      panel: RulerPicker(
                        value: brew.manualWaterG,
                        min: 50,
                        max: 1000,
                        unit: 'g',
                        step: 1,
                        onChanged: brew.setManualWater,
                      ),
                    ),
                    ValueSelectRow<void>.custom(
                      icon: Icons.thermostat_outlined,
                      label: 'Temp',
                      valueText: temp != null
                          ? '${formatGrams(temp)}°C'
                          : (recipe?.brewTemperature != null
                                ? brewTemperatureLabel(recipe!.brewTemperature!)
                                : null),
                      dimValue: temp == null || locked,
                      enabled: !locked,
                      isLast: true,
                      open: _open == _OpenList.temp,
                      onToggle: () => _toggle(_OpenList.temp),
                      onClose: _close,
                      panel: RulerPicker(
                        value: temp ?? 93,
                        min: 80,
                        max: 100,
                        unit: '°',
                        onChanged: brew.setTemperature,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Spacer(),
                    const _StartButton(),
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
}

class _StartButton extends StatelessWidget {
  const _StartButton();

  @override
  Widget build(BuildContext context) {
    final brew = context.watch<PourOverBrewService>();
    final scale = context.watch<BrewScale>();
    if (brew.stage != ShotStage.idle) {
      return const AppButton(label: 'Brewing…', onPressed: null);
    }
    if (!scale.isConnected) {
      final busy = scale.connection != ScaleConnection.disconnected;
      return AppButton(
        label: busy ? 'Connecting scale…' : 'Connect Scale',
        icon: Icons.bluetooth,
        onPressed: busy ? null : scale.connect,
      );
    }
    return AppButton(
      label: 'Start Brew',
      onPressed: brew.plan == null
          ? null
          : () async {
              final ok = await brew.startShot();
              if (!context.mounted || ok) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(brew.lastError ?? 'Could not start the brew'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
    );
  }
}
