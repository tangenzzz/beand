import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';

// The switchable home views (pills at the top left of the Home tab).
enum HomeMode {
  meticulous('Meticulous'),
  pourOver('Pour Over'),
  gaggimate('GaggiMate');

  const HomeMode(this.label);

  final String label;
}

// Configurable fields of the bean form (photo, name and roastery are
// fixed). The order of the values is the default order.
enum BeanFormField {
  country('Country'),
  producer('Producer'),
  variety('Variety'),
  processing('Processing'),
  type('Type'),
  roastedFor('Roasted for'),
  roastDate('Roast date'),
  weight('Weight'),
  cost('Cost'),
  taste('Taste');

  const BeanFormField(this.label);

  final String label;
}

// Which photo is shown in the circle on the shot in the history (and in the
// post-shot card): the profile's or the bean's that was used.
enum HistoryAvatar {
  profile('Profile photo'),
  bean('Bean photo');

  const HistoryAvatar(this.label);

  final String label;
}

// App-wide settings (Settings menu), stored locally in shared_preferences.
class AppSettings extends ChangeNotifier {
  AppSettings({
    bool showFreshnessRing = true,
    bool showBeanStock = true,
    Set<HomeMode> enabledHomeModes = defaultEnabledHomeModes,
    HomeMode homeMode = HomeMode.meticulous,
    List<HomeMode> homeModeOrder = HomeMode.values,
    List<BeanFormField> beanFormOrder = BeanFormField.values,
    Set<BeanFormField> hiddenBeanFormFields = const {},
    HistoryAvatar historyAvatar = HistoryAvatar.profile,
    AppThemeMode themeMode = AppThemeMode.system,
    AppAccent accent = AppAccent.teal,
    bool showStageDetails = true,
    bool showShotFacts = true,
    bool expandAiAnalysis = true,
  }) {
    _showFreshnessRing = showFreshnessRing;
    _showBeanStock = showBeanStock;
    _showStageDetails = showStageDetails;
    _showShotFacts = showShotFacts;
    _expandAiAnalysis = expandAiAnalysis;
    _enabledHomeModes = {...enabledHomeModes};
    _homeMode = homeMode;
    _homeModeOrder = normalizeHomeModeOrder(homeModeOrder);
    _beanFormOrder = normalizeBeanFormOrder(beanFormOrder);
    _hiddenBeanFormFields = {...hiddenBeanFormFields};
    _historyAvatar = historyAvatar;
    _themeMode = themeMode;
    _accent = accent;
  }

  static const showFreshnessRingPrefKey = 'beans_show_freshness_ring';
  static const showBeanStockPrefKey = 'beans_show_stock';
  static const showStageDetailsPrefKey = 'history_show_stage_details';
  static const showShotFactsPrefKey = 'history_show_shot_facts';
  static const expandAiAnalysisPrefKey = 'history_expand_ai_analysis';
  static const homeModePrefKey = 'home_mode_selected';
  static const homeModeOrderPrefKey = 'home_mode_order';
  static const beanFormOrderPrefKey = 'beans_form_order';
  static const beanFormHiddenPrefKey = 'beans_form_hidden';
  static const historyAvatarPrefKey = 'history_avatar';
  static const themeModePrefKey = 'appearance_theme_mode';
  static const accentPrefKey = 'appearance_accent';
  static String homeModeEnabledPrefKey(HomeMode mode) =>
      'home_mode_enabled_${mode.name}';

  // GaggiMate is supported (see lib/machines/gaggimate/), but hidden by
  // default: without such a machine on the network the pill is useless, and
  // the service only connects once it is shown.
  static const defaultEnabledHomeModes = {
    HomeMode.meticulous,
    HomeMode.pourOver,
  };

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      showFreshnessRing: prefs.getBool(showFreshnessRingPrefKey) ?? true,
      showBeanStock: prefs.getBool(showBeanStockPrefKey) ?? true,
      showStageDetails: prefs.getBool(showStageDetailsPrefKey) ?? true,
      showShotFacts: prefs.getBool(showShotFactsPrefKey) ?? true,
      expandAiAnalysis: prefs.getBool(expandAiAnalysisPrefKey) ?? true,
      enabledHomeModes: {
        for (final mode in HomeMode.values)
          if (prefs.getBool(homeModeEnabledPrefKey(mode)) ??
              defaultEnabledHomeModes.contains(mode))
            mode,
      },
      homeMode:
          HomeMode.values.asNameMap()[prefs.getString(homeModePrefKey)] ??
          HomeMode.meticulous,
      homeModeOrder: _modesFromNames(prefs.getStringList(homeModeOrderPrefKey)),
      beanFormOrder: _fieldsFromNames(
        prefs.getStringList(beanFormOrderPrefKey),
      ),
      hiddenBeanFormFields: _fieldsFromNames(
        prefs.getStringList(beanFormHiddenPrefKey),
      ).toSet(),
      historyAvatar:
          HistoryAvatar.values.asNameMap()[prefs.getString(
            historyAvatarPrefKey,
          )] ??
          HistoryAvatar.profile,
      themeMode:
          AppThemeMode.values.asNameMap()[prefs.getString(themeModePrefKey)] ??
          AppThemeMode.system,
      accent:
          AppAccent.values.asNameMap()[prefs.getString(accentPrefKey)] ??
          AppAccent.teal,
    );
  }

  static List<HomeMode> _modesFromNames(List<String>? names) {
    final byName = HomeMode.values.asNameMap();
    return [
      for (final name in names ?? const <String>[])
        if (byName[name] != null) byName[name]!,
    ];
  }

  // Remove duplicates, append modes added later at the end — so a stored
  // order survives an app update.
  static List<HomeMode> normalizeHomeModeOrder(Iterable<HomeMode> order) {
    final result = <HomeMode>[];
    for (final mode in [...order, ...HomeMode.values]) {
      if (!result.contains(mode)) result.add(mode);
    }
    return result;
  }

  static List<BeanFormField> _fieldsFromNames(List<String>? names) {
    final byName = BeanFormField.values.asNameMap();
    return [
      for (final name in names ?? const <String>[])
        if (byName[name] != null) byName[name]!,
    ];
  }

  // Remove duplicates and append missing fields (e.g. ones added later) at
  // the end in default order.
  static List<BeanFormField> normalizeBeanFormOrder(
    Iterable<BeanFormField> order,
  ) {
    final result = <BeanFormField>[];
    for (final field in [...order, ...BeanFormField.values]) {
      if (!result.contains(field)) result.add(field);
    }
    return result;
  }

  /// After adopting data from sync: re-read all values from the prefs.
  Future<void> reload() async {
    final fresh = await load();
    _showFreshnessRing = fresh._showFreshnessRing;
    _showBeanStock = fresh._showBeanStock;
    _showStageDetails = fresh._showStageDetails;
    _showShotFacts = fresh._showShotFacts;
    _expandAiAnalysis = fresh._expandAiAnalysis;
    _enabledHomeModes = fresh._enabledHomeModes;
    _homeMode = fresh._homeMode;
    _homeModeOrder = fresh._homeModeOrder;
    _beanFormOrder = fresh._beanFormOrder;
    _hiddenBeanFormFields = fresh._hiddenBeanFormFields;
    _historyAvatar = fresh._historyAvatar;
    _themeMode = fresh._themeMode;
    _accent = fresh._accent;
    fresh.dispose();
    notifyListeners();
  }

  late bool _showFreshnessRing;
  late bool _showBeanStock;
  late bool _showStageDetails;
  late bool _showShotFacts;
  late bool _expandAiAnalysis;
  late Set<HomeMode> _enabledHomeModes;
  late HomeMode _homeMode;
  late List<HomeMode> _homeModeOrder;
  late List<BeanFormField> _beanFormOrder;
  late Set<BeanFormField> _hiddenBeanFormFields;
  late HistoryAvatar _historyAvatar;
  late AppThemeMode _themeMode;
  late AppAccent _accent;

  // Freshness ring (days since roast) in the bean list and picker; off =
  // only the text "12 d".
  bool get showFreshnessRing => _showFreshnessRing;

  Future<void> setShowFreshnessRing(bool value) async {
    if (value == _showFreshnessRing) return;
    _showFreshnessRing = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(showFreshnessRingPrefKey, value);
  }

  // Remaining amount in the bag: ring around the bean photo plus grams, and
  // the pre-shot card hides empty beans. Only for beans with a bag weight.
  bool get showBeanStock => _showBeanStock;

  Future<void> setShowBeanStock(bool value) async {
    if (value == _showBeanStock) return;
    _showBeanStock = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(showBeanStockPrefKey, value);
  }

  // Shot detail: target and result of the stage at the cursor below the
  // stage bar — expandable/collapsible via the stage name, for a cleaner
  // view. Applies to all shots until toggled again.
  bool get showStageDetails => _showStageDetails;

  Future<void> setShowStageDetails(bool value) async {
    if (value == _showStageDetails) return;
    _showStageDetails = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(showStageDetailsPrefKey, value);
  }

  // Fixed findings without AI below the curve in the shot detail (History
  // settings).
  bool get showShotFacts => _showShotFacts;

  Future<void> setShowShotFacts(bool value) async {
    if (value == _showShotFacts) return;
    _showShotFacts = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(showShotFactsPrefKey, value);
  }

  // AI analysis expanded or collapsed, applies to all shots and is persisted
  // (like the stage details).
  bool get expandAiAnalysis => _expandAiAnalysis;

  Future<void> setExpandAiAnalysis(bool value) async {
    if (value == _expandAiAnalysis) return;
    _expandAiAnalysis = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(expandAiAnalysisPrefKey, value);
  }

  bool isHomeModeEnabled(HomeMode mode) => _enabledHomeModes.contains(mode);

  // Order of the pills, set by the user via drag. Also contains hidden
  // modes so their position is kept when they are shown again.
  List<HomeMode> get homeModeOrder => List.unmodifiable(_homeModeOrder);

  // Visible modes in the order chosen by the user.
  List<HomeMode> get enabledHomeModes => [
    for (final mode in _homeModeOrder)
      if (_enabledHomeModes.contains(mode)) mode,
  ];

  // A pill was moved in the bar. The bar only shows the visible modes — the
  // hidden ones keep their place in between, so they do not jump to the
  // start when shown again.
  Future<void> reorderEnabledHomeModes(int from, int to) async {
    final visible = enabledHomeModes;
    if (from < 0 || from >= visible.length) return;
    final moved = [...visible];
    moved.insert(to.clamp(0, moved.length - 1), moved.removeAt(from));

    var next = 0;
    final merged = [
      for (final mode in _homeModeOrder)
        if (_enabledHomeModes.contains(mode)) moved[next++] else mode,
    ];
    await setHomeModeOrder(merged);
  }

  Future<void> setHomeModeOrder(List<HomeMode> order) async {
    final normalized = normalizeHomeModeOrder(order);
    if (normalized.toString() == _homeModeOrder.toString()) return;
    _homeModeOrder = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(homeModeOrderPrefKey, [
      for (final mode in normalized) mode.name,
    ]);
  }

  // Active view: the selected one as long as it is visible; otherwise the
  // first visible mode. If all are off, it stays on the Meticulous home.
  HomeMode get activeHomeMode {
    if (_enabledHomeModes.contains(_homeMode)) return _homeMode;
    return enabledHomeModes.firstOrNull ?? HomeMode.meticulous;
  }

  Future<void> setHomeMode(HomeMode mode) async {
    if (mode == _homeMode) return;
    _homeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(homeModePrefKey, mode.name);
  }

  Future<void> setHomeModeEnabled(HomeMode mode, bool value) async {
    if (value == _enabledHomeModes.contains(mode)) return;
    if (value) {
      _enabledHomeModes.add(mode);
    } else {
      _enabledHomeModes.remove(mode);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(homeModeEnabledPrefKey(mode), value);
  }

  // All configurable form fields in the chosen order.
  List<BeanFormField> get beanFormFields => List.unmodifiable(_beanFormOrder);

  bool isBeanFormFieldVisible(BeanFormField field) =>
      !_hiddenBeanFormFields.contains(field);

  List<BeanFormField> get visibleBeanFormFields => [
    for (final field in _beanFormOrder)
      if (!_hiddenBeanFormFields.contains(field)) field,
  ];

  Future<void> setBeanFormFieldVisible(
    BeanFormField field,
    bool visible,
  ) async {
    if (visible == isBeanFormFieldVisible(field)) return;
    if (visible) {
      _hiddenBeanFormFields.remove(field);
    } else {
      _hiddenBeanFormFields.add(field);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(beanFormHiddenPrefKey, [
      for (final f in _hiddenBeanFormFields) f.name,
    ]);
  }

  // [newIndex] as in ReorderableListView.onReorderItem (already adjusted
  // for the removal of the moved entry).
  Future<void> reorderBeanFormFields(int oldIndex, int newIndex) async {
    if (newIndex == oldIndex) return;
    _beanFormOrder.insert(newIndex, _beanFormOrder.removeAt(oldIndex));
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(beanFormOrderPrefKey, [
      for (final f in _beanFormOrder) f.name,
    ]);
  }

  // Photo in the circle on the shot: profile (default, as it always was) or
  // bean.
  HistoryAvatar get historyAvatar => _historyAvatar;

  Future<void> setHistoryAvatar(HistoryAvatar value) async {
    if (value == _historyAvatar) return;
    _historyAvatar = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(historyAvatarPrefKey, value.name);
  }

  // Appearance (Settings → Appearance). Both are loaded at app start before
  // the first frame (main.dart), so nothing flickers.
  AppThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(AppThemeMode value) async {
    if (value == _themeMode) return;
    _themeMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(themeModePrefKey, value.name);
  }

  AppAccent get accent => _accent;

  Future<void> setAccent(AppAccent value) async {
    if (value == _accent) return;
    _accent = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(accentPrefKey, value.name);
  }
}
