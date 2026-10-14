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
import '../../beans/bean_filter.dart';
import '../../beans/bean_form_screen.dart';
import '../../beans/bean_stock.dart';
import '../../beans/bean_widgets.dart';
import '../inline_picker.dart';
import '../pre_shot_card.dart' show PreShotRow;
import '../ruler_picker.dart';
import '../tile_title.dart';
import 'pourover_profile_row.dart';
import 'recipe_format.dart';

enum _OpenList { recipe, bean, dose, grind, water, temp }

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
    _OpenList.recipe => InlinePicker.heightFor(
      context.read<BrewRecipeStore>().recipes.length,
    ),
    _OpenList.bean => InlinePicker.heightFor(_pickableBeans.length),
    _OpenList.dose ||
    _OpenList.grind ||
    _OpenList.water ||
    _OpenList.temp => RulerPicker.height,
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

  IconData _chevron(_OpenList list) =>
      _open == list ? Icons.expand_less : Icons.expand_more;

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
    final temp = brew.temperature;

    // Nothing can be changed during the brew.
    VoidCallback? tap(_OpenList l) => locked ? null : () => _toggle(l);
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
                      PreShotRow(
                        icon: Icons.tune,
                        label: 'Profile',
                        value: recipe?.name ?? 'Select profile',
                        dimValue: recipe == null || locked,
                        trailingIcon: locked
                            ? null
                            : _chevron(_OpenList.recipe),
                        onTap: tap(_OpenList.recipe),
                      ),
                    if (!manual && _open == _OpenList.recipe)
                      InlinePicker<BrewRecipe>(
                        items: recipes,
                        leading: (r) => PourOverProfileAvatar(recipe: r),
                        title: (r) => r.name,
                        detail: recipeDetail,
                        searchText: (r) =>
                            '${r.name} ${r.brewer} ${r.sourceName} ${r.tags.join(' ')}',
                        isSelected: (r) => r.id == recipe?.id,
                        onSelected: (r) {
                          brew.selectRecipe(r);
                          _close();
                        },
                        // "+" fetches more profiles from the settings.
                        onAdd: () => PourOverProfileRow.openSettings(context),
                        addTooltip: 'Choose profiles',
                        emptyText:
                            'No profiles selected. Tap + to choose some.',
                      ),
                    PreShotRow(
                      icon: Icons.coffee_outlined,
                      label: 'Bean',
                      value: bean?.name ?? 'Select bean',
                      dimValue: bean == null || locked,
                      trailingIcon: locked ? null : _chevron(_OpenList.bean),
                      onTap: tap(_OpenList.bean),
                    ),
                    if (_open == _OpenList.bean)
                      InlinePicker<Bean>(
                        items: [
                          for (final g in groupBeansByRoaster(_pickableBeans))
                            ...g.beans,
                        ],
                        leading: (b) => showStock
                            ? BeanStockAvatar(
                                photoPath: b.photoPath,
                                remaining: beanRemaining(b, _beanUsage),
                                total: b.weightGrams,
                                size: 44,
                                labelOverhang: 2,
                              )
                            : BeanThumbnail(
                                path: b.photoPath,
                                size: 36,
                                circle: true,
                              ),
                        title: (b) => b.name,
                        detail: (b) => b.roaster,
                        searchText: (b) => beanSearchText(b),
                        isSelected: (b) => b.id == setup.beanId,
                        onSelected: (b) {
                          setup.setBean(b.id);
                          _close();
                        },
                        onAdd: _addBean,
                        addTooltip: 'Add bean',
                        emptyText: 'No beans yet. Tap + to add one.',
                      ),
                    PreShotRow(
                      icon: Icons.balance,
                      label: 'Dose',
                      value: dose == null ? '—' : '${formatGrams(dose)} g',
                      dimValue: dose == null || locked,
                      trailingIcon: locked ? null : _chevron(_OpenList.dose),
                      onTap: tap(_OpenList.dose),
                    ),
                    if (_open == _OpenList.dose)
                      RulerPicker(
                        value: dose ?? 15,
                        min: 5,
                        max: 60,
                        unit: 'g',
                        onChanged: setup.setDose,
                      ),
                    PreShotRow(
                      icon: Icons.blur_on,
                      label: 'Grind',
                      // Without an own setting the recipe's grind level is
                      // shown ("Coarse") — dimmed, because it is not a
                      // number on your own grinder.
                      value: grind != null
                          ? grind.toStringAsFixed(1)
                          : (recipe == null
                                ? '—'
                                : grindLabel(recipe.grindSize)),
                      dimValue: grind == null || locked,
                      trailingIcon: locked ? null : _chevron(_OpenList.grind),
                      onTap: tap(_OpenList.grind),
                    ),
                    if (_open == _OpenList.grind)
                      RulerPicker(
                        value: grind ?? 20,
                        min: 0,
                        max: 60,
                        unit: '',
                        onChanged: setup.setGrind,
                      ),
                    PreShotRow(
                      icon: Icons.water_drop_outlined,
                      label: 'Water',
                      value: plan == null
                          ? '—'
                          : '${formatGrams(plan.totalWaterG)} g  ·  1:${formatRatio(plan.ratio)}',
                      // With a recipe it follows from recipe and dose
                      // (lock); manual, it is the freely chosen target.
                      dimValue: !manual || locked,
                      trailingIcon: manual
                          ? (locked ? null : _chevron(_OpenList.water))
                          : Icons.lock_outline,
                      onTap: manual ? tap(_OpenList.water) : null,
                    ),
                    if (manual && _open == _OpenList.water)
                      RulerPicker(
                        value: brew.manualWaterG,
                        min: 50,
                        max: 1000,
                        unit: 'g',
                        step: 1,
                        onChanged: brew.setManualWater,
                      ),
                    PreShotRow(
                      icon: Icons.thermostat_outlined,
                      label: 'Temp',
                      value: temp != null
                          ? '${formatGrams(temp)}°C'
                          : (recipe?.brewTemperature != null
                                ? brewTemperatureLabel(recipe!.brewTemperature!)
                                : '—'),
                      dimValue: temp == null || locked,
                      trailingIcon: locked ? null : _chevron(_OpenList.temp),
                      isLast: true,
                      onTap: tap(_OpenList.temp),
                    ),
                    if (_open == _OpenList.temp)
                      RulerPicker(
                        value: temp ?? 93,
                        min: 80,
                        max: 100,
                        unit: '°',
                        onChanged: brew.setTemperature,
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
