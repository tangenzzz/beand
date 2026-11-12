import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/database.dart';
import '../../models/coffee.dart';
import '../../models/machine_profile.dart' show profilePlaceholderColor;
import '../../models/profile_draft.dart' show newUuid;
import '../../services/ai/ai_prompt.dart';
import '../../services/ai/ai_service.dart';
import '../settings/ai_consent_dialog.dart';
import '../../services/ai/ai_settings.dart';
import '../../services/ai/bean_extraction.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import 'bean_stock.dart';
import 'bean_suggestions.dart';
import 'bean_widgets.dart';
import 'freshness.dart';
import '../../widgets/underline_select.dart';
import '../../widgets/app_button.dart';

// The card of a coffee: one tile with its photo and details, below it a
// carousel with its bags. A saved coffee opens for reading; the pencil turns
// the same page into a form, with Save in its place. Only the name of the
// page, the arrows and the fill row tell the two apart (user 2026-11-06).
//
// [bean] is any bag of the coffee, null = a new coffee. The pop result of a new
// coffee is its saved bag.
class BeanFormScreen extends StatefulWidget {
  const BeanFormScreen({super.key, this.bean});

  final Bean? bean;

  @override
  State<BeanFormScreen> createState() => _BeanFormScreenState();
}

// A bag while the form is open. [bean] null = not saved yet.
class _BagDraft {
  _BagDraft({
    this.bean,
    DateTime? roastDate,
    DateTime? openedAt,
    double? weight,
    double? cost,
  }) : roastDate = roastDate ?? bean?.roastDate,
       openedAt = openedAt ?? bean?.openedAt,
       isFrozen = bean?.isFrozen ?? false,
       frozenDate = bean?.frozenDate,
       thawedDate = bean?.thawedDate,
       weight = TextEditingController(
         text: _BeanFormScreenState._formatNumber(weight ?? bean?.weightGrams),
       ),
       cost = TextEditingController(
         text: _BeanFormScreenState._formatNumber(cost ?? bean?.cost),
       );

  final Bean? bean;
  DateTime? roastDate;
  DateTime? openedAt;
  bool isFrozen;
  DateTime? frozenDate;
  DateTime? thawedDate;

  /// A freezer date was picked in the timeline: the ring then counts that
  /// stay alone, whatever was stored before.
  bool freezerEdited = false;
  final TextEditingController weight;
  final TextEditingController cost;

  void dispose() {
    weight.dispose();
    cost.dispose();
  }
}

enum _SelectField { type, roastLevel, roastedFor }

class _BeanFormScreenState extends State<BeanFormScreen> {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  late final TextEditingController _name;
  late final TextEditingController _roaster;
  late final TextEditingController _country;
  late final TextEditingController _region;
  late final TextEditingController _altitude;
  late final TextEditingController _processing;
  late final TextEditingController _variety;
  late final TextEditingController _producer;
  late final TextEditingController _taste;

  bool? _isBlend;
  String? _roastedFor;
  String? _roastLevel;
  String? _photoPath;
  // Photos newly added in this session, deleted again on cancel.
  final _addedPhotos = <String>{};
  BeanSuggestions _suggestions = const BeanSuggestions();

  late bool _editing;
  _SelectField? _openMenu;

  // Everything from the database, kept current: the bags change right away
  // (open, freeze, empty), also while reading.
  List<Bean> _beans = const [];
  Map<int, double> _usage = const {};
  StreamSubscription<List<Bean>>? _beansSub;
  StreamSubscription<Map<int, double>>? _usageSub;
  String? _key;

  final _drafts = <int, _BagDraft>{};
  final _newBags = <_BagDraft>[];
  final _pages = PageController(viewportFraction: 0.94);
  final _scroll = ScrollController();

  // One switch for all bags: the carousel has a single height.
  static const _timelineOpenPrefKey = 'bean_card_timeline_open';
  bool _timelineOpen = false;

  void _setTimelineOpen(bool open) {
    setState(() => _timelineOpen = open);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_timelineOpenPrefKey, open);
    });
  }

  // A bag whose status just changed moves to its place in the order; the
  // carousel goes along with it (null state: whatever it comes back as).
  (int, BagState?)? _followBag;
  int _page = 0;

  // --- Read from packaging/link -------------------------------------------
  //
  // Imported values are NOT saved silently: they appear marked in the form,
  // the user looks at them, and only their normal "Save" makes them real.
  // Marked here means: the field's label carries the accent color until the
  // field is touched.
  final _aiFilled = <String>{};
  bool _aiBusy = false;
  // Owned by the screen, not the dialog: a controller created in the dialog
  // and disposed right after it closes is still in use during the fade-out
  // — "used after being disposed".
  final _link = TextEditingController();
  String? _aiNote;
  _FormSnapshot? _aiUndo;

  bool get _isNew => widget.bean == null;

  Coffee? get _coffee {
    final key = _key;
    if (key == null) return null;
    final stock = context.read<AppSettings>().showBeanStock;
    return groupCoffees(
      _beans.where((b) => coffeeKey(b) == key),
      _usage,
      stock: stock,
    ).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(_timelineOpenPrefKey);
      if (saved != null && mounted) setState(() => _timelineOpen = saved);
    });
    final b = widget.bean;
    // Until the database answers: at least this bag, so the page has no gap.
    _beans = [?b];
    _editing = b == null;
    _key = b == null ? null : coffeeKey(b);
    _name = TextEditingController(text: b?.name)..addListener(_onNameChanged);
    _roaster = TextEditingController(text: b?.roaster);
    _country = TextEditingController(text: b?.country);
    _region = TextEditingController(text: b?.region);
    _altitude = TextEditingController(text: b?.altitude);
    _processing = TextEditingController(text: b?.processing);
    _variety = TextEditingController(text: b?.variety);
    _producer = TextEditingController(text: b?.producer);
    _taste = TextEditingController(text: b?.taste);
    _isBlend = b?.isBlend;
    _roastedFor = b?.roastedFor;
    _roastLevel = b?.roastLevel;
    _photoPath = b?.photoPath;
    if (_isNew) _newBags.add(_newDraft());

    // As soon as the user touches an imported field, it's theirs — the
    // marking disappears by itself without them having to confirm anything.
    for (final entry in _coffeeControllers.entries) {
      entry.value.addListener(() => _clearMark(entry.key));
    }

    final db = context.read<AppDatabase>();
    db.allBeans().then((beans) {
      if (!mounted) return;
      setState(() => _suggestions = BeanSuggestions.fromBeans(beans));
    });
    _beansSub = db.watchBeans().listen((beans) {
      if (!mounted) return;
      setState(() => _beans = beans);
      if (!_editing && _coffee != null) _loadFromCoffee();
    });
    _usageSub = db.watchBeanUsage().listen((usage) {
      if (mounted) setState(() => _usage = usage);
    });
  }

  @override
  void dispose() {
    _beansSub?.cancel();
    _usageSub?.cancel();
    for (final path in _addedPhotos) {
      _deleteFile(path);
    }
    _link.dispose();
    _pages.dispose();
    _scroll.dispose();
    for (final d in [..._drafts.values, ..._newBags]) {
      d.dispose();
    }
    for (final c in _coffeeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  // Name and Roastery are not in BeanFormField (they can't be turned off), but
  // need the same marking.
  Map<String, TextEditingController> get _coffeeControllers => {
    'name': _name,
    'roaster': _roaster,
    BeanFormField.country.name: _country,
    BeanFormField.region.name: _region,
    BeanFormField.altitude.name: _altitude,
    BeanFormField.processing.name: _processing,
    BeanFormField.variety.name: _variety,
    BeanFormField.producer.name: _producer,
    BeanFormField.taste.name: _taste,
  };

  // Which key belongs to which text field, including the bag on screen.
  Map<String, TextEditingController> get _markedControllers {
    final bag = _bagOnScreen;
    return {
      ..._coffeeControllers,
      if (bag != null) ...{
        BeanFormField.weight.name: bag.weight,
        BeanFormField.cost.name: bag.cost,
      },
    };
  }

  void _clearMark(String key) {
    if (!_aiFilled.remove(key)) return;
    if (mounted) setState(() {});
  }

  // "17,50" should show as "17.5" — but 250 g is 250 and not 25. Trimming
  // zeros therefore applies ONLY after a decimal comma; before, it ate the
  // last digit of every round number (250 g, 1000 g, 20 €).
  static String _formatNumber(double? v) {
    if (v == null) return '';
    if (v % 1 == 0) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  static double? _parseNumber(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  static String? _nullIfEmpty(String text) {
    final t = text.trim();
    return t.isEmpty ? null : t;
  }

  static void _deleteFile(String? path) {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  void _loadFromCoffee() {
    final d = _coffee?.details;
    if (d == null) return;
    _name.text = d.name;
    _roaster.text = d.roaster ?? '';
    _country.text = d.country ?? '';
    _region.text = d.region ?? '';
    _altitude.text = d.altitude ?? '';
    _processing.text = d.processing ?? '';
    _variety.text = d.variety ?? '';
    _producer.text = d.producer ?? '';
    _taste.text = d.taste ?? '';
    _isBlend = d.isBlend;
    _roastedFor = d.roastedFor;
    _roastLevel = d.roastLevel;
    _photoPath = d.photoPath;
  }

  void _startEditing() {
    _loadFromCoffee();
    for (final bag in _coffee?.bags ?? const <Bean>[]) {
      _drafts.putIfAbsent(bag.id, () => _BagDraft(bean: bag));
    }
    setState(() => _editing = true);
  }

  void _stopEditing() {
    for (final d in [..._drafts.values, ..._newBags]) {
      d.dispose();
    }
    _drafts.clear();
    _newBags.clear();
    for (final path in _addedPhotos) {
      _deleteFile(path);
    }
    _addedPhotos.clear();
    _aiFilled.clear();
    _aiNote = null;
    _aiUndo = null;
    _openMenu = null;
    _loadFromCoffee();
    setState(() => _editing = false);
  }

  bool get _dirty {
    if (_newBags.isNotEmpty && !_isNew) return true;
    final d = _coffee?.details;
    String t(String? v) => v ?? '';
    if (_isNew) return _name.text.trim().isNotEmpty || _photoPath != null;
    if (d == null) return false;
    return _name.text != d.name ||
        _roaster.text != t(d.roaster) ||
        _country.text != t(d.country) ||
        _region.text != t(d.region) ||
        _altitude.text != t(d.altitude) ||
        _processing.text != t(d.processing) ||
        _variety.text != t(d.variety) ||
        _producer.text != t(d.producer) ||
        _taste.text != t(d.taste) ||
        _isBlend != d.isBlend ||
        _roastedFor != d.roastedFor ||
        _roastLevel != d.roastLevel ||
        _photoPath != d.photoPath ||
        _drafts.values.any(_bagChanged);
  }

  // Freezer dates picked in the timeline of a thawed bag: the ring counts
  // that one stay, nothing else. Clears freezer days left over from bags
  // frozen before freeze dates were kept.
  Value<int> _frozenDaysAfterEdit(_BagDraft d) {
    final now = _beans.where((b) => b.id == d.bean?.id).firstOrNull;
    final (newIn, newOut) = (d.frozenDate, d.thawedDate);
    if (now == null ||
        now.isFrozen ||
        !d.freezerEdited ||
        newIn == null ||
        newOut == null) {
      return const Value.absent();
    }
    return Value(pausedDays(newIn, newOut));
  }

  bool _bagChanged(_BagDraft d) {
    final b = d.bean;
    if (b == null) return true;
    return d.freezerEdited ||
        d.roastDate != b.roastDate ||
        d.openedAt != b.openedAt ||
        d.frozenDate != b.frozenDate ||
        d.thawedDate != b.thawedDate ||
        _parseNumber(d.weight.text) != b.weightGrams ||
        _parseNumber(d.cost.text) != b.cost;
  }

  // Back while editing: leave the form, not the page. Changes are asked about.
  Future<void> _back() async {
    if (_editing && _dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: context.colors.card,
          title: Text(
            'Discard changes?',
            style: TextStyle(color: context.colors.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                'Discard',
                style: TextStyle(color: context.colors.danger),
              ),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (_editing && !_isNew) {
      _stopEditing();
    } else {
      Navigator.of(context).pop();
    }
  }

  // ----- Bags ---------------------------------------------------------------

  _BagDraft _newDraft() {
    final bags = _coffee?.bags ?? const <Bean>[];
    final last = bags.isEmpty
        ? null
        : bags.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
    return _BagDraft(weight: last?.weightGrams);
  }

  void _addBag() {
    if (!_editing) _startEditing();
    final count = (_coffee?.bags.length ?? 0) + _newBags.length;
    setState(() => _newBags.add(_newDraft()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pages.hasClients) {
        _pages.animateToPage(
          count,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      _scrollToEnd();
    });
  }

  // Down to the bags. The list only knows its full length once it has built
  // what lies further down, so it checks again on arrival.
  Future<void> _scrollToEnd() async {
    for (var i = 0; i < 4 && mounted && _scroll.hasClients; i++) {
      final end = _scroll.position.maxScrollExtent;
      if (_scroll.offset >= end) {
        // The list got shorter on the way: no gap below it.
        if (_scroll.offset > end) _scroll.jumpTo(end);
        return;
      }
      await _scroll.animateTo(
        end,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  // The bag whose tile is on screen: there the fill row puts weight and price.
  _BagDraft? get _bagOnScreen {
    final saved = _coffee?.bags ?? const <Bean>[];
    if (_page < saved.length) return _drafts[saved[_page].id];
    final i = _page - saved.length;
    if (i < _newBags.length) return _newBags[i];
    return _newBags.lastOrNull ??
        (saved.isEmpty ? null : _drafts[saved.last.id]);
  }

  // The status symbols of a bag tile. Takes effect at once, also while
  // reading. Tapping Frozen or Empty again goes back to what the bag was.
  Future<void> _setBagState(
    Bean? bag,
    _BagDraft? draft,
    BagState current,
    BagState target,
  ) async {
    // A bag not saved yet: nothing to be empty of.
    if (bag == null) {
      if (draft == null) return;
      setState(() {
        switch (target) {
          case BagState.frozen:
            draft.isFrozen = !draft.isFrozen;
            draft.frozenDate = draft.isFrozen ? DateTime.now() : null;
          case BagState.open:
            draft.isFrozen = false;
            draft.openedAt ??= DateTime.now();
          case BagState.sealed:
            draft.isFrozen = false;
            draft.openedAt = null;
          case BagState.empty:
            break;
        }
      });
      return;
    }
    final again = target == current;
    if (again && target != BagState.frozen && target != BagState.empty) return;
    if (target == BagState.sealed && (_usage[bag.id] ?? 0) > 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('This bag has shots.')));
      return;
    }
    final now = DateTime.now();
    final freeze = target == BagState.frozen && !again;
    final thaw = bag.isFrozen && !freeze;
    final opened = switch (target) {
      BagState.open => bag.openedAt ?? now,
      BagState.sealed => null,
      _ => bag.openedAt,
    };
    if (draft != null) {
      setState(() {
        draft.openedAt = opened;
        draft.isFrozen = freeze;
        if (freeze) draft.frozenDate = now;
        if (thaw) draft.thawedDate = now;
      });
    }
    _followBag = (bag.id, again ? null : target);
    await context.read<AppDatabase>().updateBean(
      bag.id,
      BeansCompanion(
        openedAt: Value(opened),
        emptiedAt: Value(target == BagState.empty && !again ? now : null),
        isFrozen: freeze || thaw ? Value(freeze) : const Value.absent(),
        frozenDate: freeze ? Value(now) : const Value.absent(),
        thawedDate: thaw ? Value(now) : const Value.absent(),
        frozenDays: freeze
            ? Value(frozenDaysWhenFreezing(bag))
            : thaw
            ? Value(frozenDaysWhenThawing(bag))
            : const Value.absent(),
      ),
    );
  }

  Future<void> _toggleEmpty(Bean bag) => context.read<AppDatabase>().updateBean(
    bag.id,
    BeansCompanion(
      emptiedAt: Value(bag.emptiedAt == null ? DateTime.now() : null),
    ),
  );

  Future<DateTime?> _pickDate(
    DateTime? current, {
    DateTime? notBefore,
    DateTime? notAfter,
  }) {
    final now = DateTime.now();
    final first = notBefore ?? DateTime(now.year - 3);
    final last = notAfter ?? now;
    var initial = current ?? now;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
  }

  // A photo may be used by several bags: only the last one takes it along.
  void _deleteFileIfUnused(String? path, Iterable<int> goneIds) {
    if (path == null) return;
    final gone = goneIds.toSet();
    if (_beans.any((b) => b.photoPath == path && !gone.contains(b.id))) return;
    _deleteFile(path);
  }

  Future<void> _deleteBag(Bean bag) async {
    final db = context.read<AppDatabase>();
    final shots = await db.countShotsOfBean(bag.id);
    if (!mounted) return;
    final offerUsedUp = shots > 0 && bag.emptiedAt == null;
    final choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.card,
        title: Text(
          'Delete bag?',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          shots == 0
              ? 'This bag will be removed.'
              : 'This bag is used by $shots ${shots == 1 ? 'shot' : 'shots'}. '
                    'They keep their data but lose the bean.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (offerUsedUp)
            TextButton(
              onPressed: () => Navigator.pop(context, _DeleteChoice.usedUp),
              child: const Text('Mark as used up'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, _DeleteChoice.delete),
            child: Text(
              'Delete',
              style: TextStyle(color: context.colors.danger),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _DeleteChoice.usedUp) {
      await _toggleEmpty(bag);
      return;
    }
    final last = (_coffee?.bags.length ?? 0) <= 1;
    _deleteFileIfUnused(bag.photoPath, [bag.id]);
    _drafts.remove(bag.id)?.dispose();
    await db.deleteBean(bag.id);
    if (last && mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteCoffee() async {
    final bags = _coffee?.bags ?? const <Bean>[];
    if (bags.isEmpty) return;
    final db = context.read<AppDatabase>();
    var shots = 0;
    for (final b in bags) {
      shots += await db.countShotsOfBean(b.id);
    }
    if (!mounted) return;
    final name = bags.first.name;
    final what = bags.length == 1 ? '1 bag' : '${bags.length} bags';
    final choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.card,
        title: Text(
          'Delete coffee?',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          shots == 0
              ? '"$name" and its $what will be removed.'
              : '"$name" and its $what are used by $shots '
                    '${shots == 1 ? 'shot' : 'shots'}. They keep their data but '
                    'lose the bean.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (shots > 0)
            TextButton(
              onPressed: () => Navigator.pop(context, _DeleteChoice.usedUp),
              child: const Text('Mark as used up'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, _DeleteChoice.delete),
            child: Text(
              'Delete',
              style: TextStyle(color: context.colors.danger),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final ids = [for (final b in bags) b.id];
    if (choice == _DeleteChoice.usedUp) {
      await db.updateBeans([
        for (final b in bags)
          if (b.emptiedAt == null) b.id,
      ], BeansCompanion(emptiedAt: Value(DateTime.now())));
    } else {
      for (final b in bags) {
        _deleteFileIfUnused(b.photoPath, ids);
        await db.deleteBean(b.id);
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ----- Save ---------------------------------------------------------------

  // A coffee with this name is already there: a further bag of it, or another
  // coffee (a new harvest under the same name)?
  Future<_ClashChoice?> _askClash(String name) => showDialog<_ClashChoice>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: context.colors.card,
      title: Text(
        '"$name" already exists',
        style: TextStyle(color: context.colors.textPrimary),
      ),
      content: Text(
        'Is this another bag of it, or a new coffee, like a new harvest?',
        style: TextStyle(color: context.colors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ClashChoice.newCoffee),
          child: const Text('New coffee'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ClashChoice.sameCoffee),
          child: Text(
            'Add as bag',
            style: TextStyle(color: context.colors.accent),
          ),
        ),
      ],
    ),
  );

  List<String> _normalizedTaste() {
    final seen = <String>{};
    return [
      for (final t in splitTaste(_taste.text))
        if (seen.add(t.toLowerCase())) t,
    ];
  }

  // Only what changed goes onto the bags: older bags may differ, and looking
  // at a coffee must not overwrite them.
  BeansCompanion _coffeeChanges(Bean? d) {
    final taste = _normalizedTaste();
    final tasteText = taste.isEmpty ? null : taste.join(', ');
    final name = _name.text.trim();
    Value<T> changed<T>(T now, T? before) =>
        d != null && now == before ? const Value.absent() : Value(now);
    String? text(TextEditingController c) => _nullIfEmpty(c.text);
    return BeansCompanion(
      name: changed(name, d?.name),
      roaster: changed(text(_roaster), d?.roaster),
      country: changed(text(_country), d?.country),
      region: changed(text(_region), d?.region),
      altitude: changed(text(_altitude), d?.altitude),
      processing: changed(text(_processing), d?.processing),
      variety: changed(text(_variety), d?.variety),
      producer: changed(text(_producer), d?.producer),
      taste: changed(tasteText, d?.taste),
      isBlend: changed(_isBlend, d?.isBlend),
      roastedFor: changed(_roastedFor, d?.roastedFor),
      roastLevel: changed(_roastLevel, d?.roastLevel),
      photoPath: changed(_photoPath, d?.photoPath),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final db = context.read<AppDatabase>();
    final coffee = _coffee;
    final before = coffee?.details;
    final roaster = _nullIfEmpty(_roaster.text);
    String? coffeeId = before?.coffeeId;

    final wanted = coffeeNameKey(name, roaster);
    if (coffeeId == null && wanted != _key) {
      final taken = _beans.any((b) => coffeeKey(b) == wanted);
      if (taken) {
        final choice = await _askClash(name);
        if (choice == null || !mounted) return;
        if (choice == _ClashChoice.newCoffee) coffeeId = newUuid();
      }
    }

    final changes = _coffeeChanges(before);
    final ids = [for (final b in coffee?.bags ?? const <Bean>[]) b.id];
    if (ids.isNotEmpty) {
      await db.updateBeans(
        ids,
        coffeeId == before?.coffeeId
            ? changes
            : changes.copyWith(coffeeId: Value(coffeeId)),
      );
    }
    for (final d in _drafts.values) {
      if (!_bagChanged(d) || !ids.contains(d.bean!.id)) continue;
      await db.updateBean(
        d.bean!.id,
        BeansCompanion(
          roastDate: Value(d.roastDate),
          openedAt: Value(d.openedAt),
          frozenDate: Value(d.frozenDate),
          thawedDate: Value(d.thawedDate),
          frozenDays: _frozenDaysAfterEdit(d),
          weightGrams: Value(_parseNumber(d.weight.text)),
          cost: Value(_parseNumber(d.cost.text)),
        ),
      );
    }
    // New bags get everything about the coffee.
    final full = _coffeeChanges(null).copyWith(coffeeId: Value(coffeeId));
    Bean? first;
    for (final d in _newBags) {
      final saved = await db.insertBean(
        full.copyWith(
          roastDate: Value(d.roastDate),
          openedAt: Value(d.openedAt),
          isFrozen: Value(d.isFrozen),
          frozenDate: Value(d.isFrozen ? d.frozenDate : null),
          weightGrams: Value(_parseNumber(d.weight.text)),
          cost: Value(_parseNumber(d.cost.text)),
        ),
      );
      first ??= saved;
    }
    // The old photo, if it is gone from every bag now.
    final oldPhoto = before?.photoPath;
    if (oldPhoto != null && oldPhoto != _photoPath) {
      _deleteFileIfUnused(oldPhoto, ids);
    }
    _addedPhotos.clear();
    if (!mounted) return;
    if (_isNew) {
      Navigator.of(context).pop(first);
      return;
    }
    _key = coffeeId ?? wanted;
    _beans = await db.allBeans();
    if (mounted) _stopEditing();
  }

  Future<void> _photoActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.tile),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                Icons.photo_camera_outlined,
                color: context.colors.textSecondary,
              ),
              title: Text(
                'Take photo',
                style: TextStyle(color: context.colors.textPrimary),
              ),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: context.colors.textSecondary,
              ),
              title: Text(
                'Choose from gallery',
                style: TextStyle(color: context.colors.textPrimary),
              ),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (_photoPath != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: context.colors.danger,
                ),
                title: Text(
                  'Remove photo',
                  style: TextStyle(color: context.colors.danger),
                ),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'remove') {
      _replacePhoto(null);
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      // The picker returns a cache file Android may delete at any time — so
      // copy it into the app folder.
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'bean_photos'))
        ..createSync(recursive: true);
      final target = p.join(
        dir.path,
        'bean_${DateTime.now().microsecondsSinceEpoch}${p.extension(picked.path)}',
      );
      await File(picked.path).copy(target);
      if (!mounted) {
        _deleteFile(target);
        return;
      }
      _addedPhotos.add(target);
      _replacePhoto(target);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load photo'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ----- Fill from packaging or link ----------------------------------------

  Future<void> _showFillSheet() async {
    final source = await showModalBottomSheet<_FillSource>(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.tile),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final entry in const [
              (
                _FillSource.camera,
                Icons.photo_camera_outlined,
                'Photo of the packaging',
              ),
              (
                _FillSource.gallery,
                Icons.photo_library_outlined,
                'Picture from gallery',
              ),
              (_FillSource.link, Icons.link, 'From a shop link'),
            ])
              ListTile(
                leading: Icon(entry.$2, color: context.colors.textSecondary),
                title: Text(
                  entry.$3,
                  style: TextStyle(color: context.colors.textPrimary),
                ),
                onTap: () => Navigator.pop(context, entry.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    if (source == _FillSource.link) {
      await _fillFromLink();
    } else {
      await _fillFromPhoto(source);
    }
  }

  Future<void> _fillFromLink() async {
    _link.clear();
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.card,
        title: Text(
          'Shop link',
          style: TextStyle(color: context.colors.textPrimary, fontSize: 17),
        ),
        // StatefulBuilder because the pasted text must become visible in the
        // dialog itself — the screen below doesn't rebuild from it.
        content: StatefulBuilder(
          builder: (context, setDialogState) => TextField(
            controller: _link,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: 'https://…',
              hintStyle: TextStyle(color: context.colors.textTertiary),
              // The link almost always comes from the clipboard — on a phone,
              // pasting via the long-press menu is the fiddliest step of the
              // whole flow.
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: Icon(
                  Icons.content_paste,
                  size: 18,
                  color: context.colors.textSecondary,
                ),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text?.trim();
                  if (text == null || text.isEmpty) return;
                  _link
                    ..text = text
                    ..selection = TextSelection.collapsed(offset: text.length);
                  setDialogState(() {});
                },
              ),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _link.text),
            child: Text('Read', style: TextStyle(color: context.colors.accent)),
          ),
        ],
      ),
    );
    if (entered == null || !mounted) return;

    var raw = entered.trim();
    if (raw.isEmpty) return;
    // Copying from the browser sometimes yields just "roesterei.de/kenia" —
    // without a scheme, fetching fails with a meaningless message.
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      raw = 'https://$raw';
    }
    final url = Uri.tryParse(raw);
    if (url == null || !url.hasAuthority) {
      _toast('That does not look like a web address.');
      return;
    }
    await _read(url: url);
  }

  Future<void> _fillFromPhoto(_FillSource source) async {
    final Uint8List bytes;
    String? storedPath;
    try {
      final picked = await ImagePicker().pickImage(
        source: source == _FillSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      bytes = await picked.readAsBytes();

      // The reading photo only becomes the bean's photo if it has none yet:
      // for reading, people usually show the back with the small print, and
      // that shouldn't replace a good product photo. But no image at all is
      // worse than the back.
      if (_photoPath == null) {
        final docs = await getApplicationDocumentsDirectory();
        final dir = Directory(p.join(docs.path, 'bean_photos'))
          ..createSync(recursive: true);
        final target = p.join(
          dir.path,
          'bean_${DateTime.now().microsecondsSinceEpoch}${p.extension(picked.path)}',
        );
        await File(picked.path).copy(target);
        if (!mounted) {
          _deleteFile(target);
          return;
        }
        storedPath = target;
      }
    } catch (_) {
      if (mounted) _toast('Could not load photo');
      return;
    }

    await _read(
      image: AiImage(
        bytes: bytes,
        mediaType: _mediaTypeOf(storedPath ?? 'photo.jpg'),
      ),
      newPhotoPath: storedPath,
    );
  }

  static String _mediaTypeOf(String path) =>
      p.extension(path).toLowerCase() == '.png' ? 'image/png' : 'image/jpeg';

  Future<void> _read({AiImage? image, Uri? url, String? newPhotoPath}) async {
    if (!await ensureAiConsent(context) || !mounted) {
      if (newPhotoPath != null) _deleteFile(newPhotoPath);
      return;
    }
    setState(() {
      _aiBusy = true;
      _aiNote = null;
    });
    try {
      final result = await context.read<AiService>().extractBean(
        image: image,
        url: url,
      );
      if (!mounted) return;
      _applyDraft(result.draft, newPhotoPath: newPhotoPath);
    } on AiFailure catch (e) {
      if (!mounted) return;
      // The photo was for nothing — but it's already copied, so delete it.
      if (newPhotoPath != null) _deleteFile(newPhotoPath);
      setState(() => _aiNote = e.message);
    } catch (e) {
      if (!mounted) return;
      if (newPhotoPath != null) _deleteFile(newPhotoPath);
      setState(() => _aiNote = '$e');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  void _applyDraft(BeanDraft draft, {String? newPhotoPath}) {
    if (draft.isEmpty) {
      if (newPhotoPath != null) _deleteFile(newPhotoPath);
      setState(() => _aiNote = 'Nothing readable found — nothing was changed.');
      return;
    }

    // Before the first letter: whatever is there now must be restorable. A
    // change to the form that can't be undone is no longer a suggestion.
    final before = _FormSnapshot.of(this);
    final filled = <String>{};

    void setText(String key, TextEditingController c, String? value) {
      if (value == null || value.isEmpty) return;
      c.text = value;
      filled.add(key);
    }

    setText('name', _name, draft.name);
    setText('roaster', _roaster, draft.roaster);
    setText(BeanFormField.country.name, _country, draft.country);
    setText(BeanFormField.region.name, _region, draft.region);
    setText(BeanFormField.altitude.name, _altitude, draft.altitude);
    setText(BeanFormField.processing.name, _processing, draft.processing);
    setText(BeanFormField.variety.name, _variety, draft.variety);
    setText(BeanFormField.producer.name, _producer, draft.producer);
    final bag = _bagOnScreen;
    if (bag != null) {
      setText(
        BeanFormField.weight.name,
        bag.weight,
        _formatNumber(draft.weightGrams),
      );
      setText(
        BeanFormField.cost.name,
        bag.cost,
        _formatNumber(draft.costInEuro),
      );
    }
    setText(
      BeanFormField.taste.name,
      _taste,
      draft.taste.isEmpty ? null : draft.taste.join(', '),
    );

    if (draft.roastDate != null && bag != null) {
      bag.roastDate = draft.roastDate;
      filled.add(BeanFormField.roastDate.name);
    }
    if (draft.isBlend != null) {
      _isBlend = draft.isBlend;
      filled.add(BeanFormField.type.name);
    }
    if (draft.roastedFor != null) {
      _roastedFor = draft.roastedFor;
      filled.add(BeanFormField.roastedFor.name);
    }
    if (draft.roastLevel != null) {
      _roastLevel = draft.roastLevel;
      filled.add(BeanFormField.roastLevel.name);
    }

    if (newPhotoPath != null) {
      _addedPhotos.add(newPhotoPath);
      _photoPath = newPhotoPath;
    }

    setState(() {
      _aiUndo = before;
      // Set the marks only NOW: assigning the texts above triggered the
      // listeners that remove marks.
      _aiFilled
        ..clear()
        ..addAll(filled);
      _aiNote = [
        '${filled.length} field${filled.length == 1 ? '' : 's'} read — '
            'check the highlighted ones.',
        if (draft.hasForeignPrice)
          'The price was not in euro, so it was left out.',
      ].join(' ');
    });
  }

  void _undoFill() {
    final before = _aiUndo;
    if (before == null) return;
    // A photo that only came in with the reading goes back too.
    final photoNow = _photoPath;
    if (photoNow != null &&
        photoNow != before.photoPath &&
        _addedPhotos.remove(photoNow)) {
      _deleteFile(photoNow);
    }
    before.restore(this);
    setState(() {
      _aiFilled.clear();
      _aiUndo = null;
      _aiNote = null;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  void _replacePhoto(String? newPath) {
    final old = _photoPath;
    // Delete only photos added in this session right away; the bean's saved
    // photo only on save.
    if (old != null && _addedPhotos.remove(old)) _deleteFile(old);
    setState(() => _photoPath = newPath);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final coffee = _coffee;
    return PopScope(
      canPop: !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: _back,
          ),
          title: _editing ? Text(_isNew ? 'New coffee' : 'Edit coffee') : null,
          actions: [
            IconButton(
              tooltip: 'Add bag',
              icon: Icon(Icons.add, color: colors.textSecondary),
              onPressed: _addBag,
            ),
            if (_editing)
              TextButton(
                onPressed: _name.text.trim().isEmpty ? null : _save,
                style: TextButton.styleFrom(foregroundColor: colors.accent),
                child: const Text('Save'),
              )
            else
              IconButton(
                tooltip: 'Edit',
                icon: Icon(Icons.edit_outlined, color: colors.textSecondary),
                onPressed: coffee == null ? null : _startEditing,
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: ListView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.tileOuterMargin,
            0,
            AppSpacing.tileOuterMargin,
            AppSpacing.tileOuterMargin * 3,
          ),
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(AppRadii.tile),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _hero(),
                  // Fill from packaging/link — only if AI is set up AND the
                  // feature is turned on, and only while editing.
                  if (_editing &&
                      context.watch<AiSettings>().isEnabled(AiFeature.beanForm))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _fillRow(context),
                    ),
                  _fieldGrid(),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _bagCarousel(coffee),
            if (_editing && !_isNew)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: AppButton(
                  label: 'Delete coffee',
                  icon: Icons.delete_outline,
                  variant: AppButtonVariant.destructive,
                  onPressed: _deleteCoffee,
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _visible(BeanFormField field) =>
      context.watch<AppSettings>().visibleBeanFormFields.contains(field);

  // Photo with name on it, like the header of the profile view: it starts
  // below the app bar.
  Widget _hero() {
    final colors = context.colors;
    final path = _photoPath;
    final file = path == null ? null : File(path);
    final hasPhoto = file != null && file.existsSync();
    final showTaste =
        _visible(BeanFormField.taste) &&
        (_editing || _taste.text.trim().isNotEmpty);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 260),
      child: Stack(
        children: [
          Positioned.fill(
            child: hasPhoto
                ? Image.file(
                    file,
                    fit: BoxFit.cover,
                    cacheWidth: 1000,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  )
                : ColoredBox(
                    color: profilePlaceholderColor(
                      _key ?? (_name.text.isEmpty ? 'new' : _name.text),
                    ),
                  ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.4, 1],
                  colors: [colors.card.withValues(alpha: 0), colors.card],
                ),
              ),
            ),
          ),
          if (_editing)
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black38,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: path == null ? 'Add photo' : 'Change photo',
                  icon: const Icon(
                    Icons.add_a_photo_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: _photoActions,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 170, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _editing
                  ? [
                      _SuggestionRow(
                        label: 'Roastery',
                        hint: 'Roastery',
                        marked: _aiFilled.contains('roaster'),
                        controller: _roaster,
                        suggestions: _suggestions.roasters,
                        capitalization: TextCapitalization.words,
                        showLabel: false,
                        fontSize: 15,
                        weight: FontWeight.w400,
                        color: colors.accent,
                      ),
                      _SuggestionRow(
                        label: 'Name',
                        hint: 'Name',
                        marked: _aiFilled.contains('name'),
                        controller: _name,
                        suggestions: _suggestions.names,
                        capitalization: TextCapitalization.words,
                        showLabel: false,
                        fontSize: 30,
                        weight: FontWeight.w700,
                      ),
                      if (showTaste)
                        _SuggestionRow(
                          label: 'Taste',
                          hint: 'Taste, e.g. blackcurrant, grapefruit',
                          marked: _aiFilled.contains(BeanFormField.taste.name),
                          controller: _taste,
                          suggestions: _suggestions.tastes,
                          tokenMode: true,
                          showLabel: false,
                          fontSize: 15,
                          weight: FontWeight.w400,
                        ),
                    ]
                  : [
                      if (_roaster.text.trim().isNotEmpty)
                        Text(
                          _roaster.text,
                          style: TextStyle(color: colors.accent, fontSize: 15),
                        ),
                      Text(
                        _name.text,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          height: 1.1,
                        ),
                      ),
                      if (showTaste)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            splitTaste(_taste.text).join(', '),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 15,
                              height: 1.3,
                            ),
                          ),
                        ),
                    ],
            ),
          ),
        ],
      ),
    );
  }

  // The fields in two columns, in the order from Settings → Beans → Form.
  // Roast date, weight and cost belong to the bags, taste to the photo.
  Widget _fieldGrid() {
    final fields = [
      for (final f in context.watch<AppSettings>().visibleBeanFormFields)
        if (f != BeanFormField.taste &&
            f != BeanFormField.roastDate &&
            f != BeanFormField.weight &&
            f != BeanFormField.cost &&
            (_editing || _readValue(f) != null))
          f,
    ];
    if (fields.isEmpty) return const SizedBox(height: 12);
    final rows = <Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      final pair = fields.sublist(
        i,
        i + 2 > fields.length ? fields.length : i + 2,
      );
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _fieldCell(pair[0])),
              const SizedBox(width: 18),
              Expanded(
                child: pair.length > 1
                    ? _fieldCell(pair[1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      final open = _openMenu;
      if (open != null && pair.any((f) => _selectOf(f) == open)) {
        rows.add(_menuPanel(open));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }

  static _SelectField? _selectOf(BeanFormField f) => switch (f) {
    BeanFormField.type => _SelectField.type,
    BeanFormField.roastLevel => _SelectField.roastLevel,
    BeanFormField.roastedFor => _SelectField.roastedFor,
    _ => null,
  };

  String? get _typeLabel => switch (_isBlend) {
    null => null,
    true => 'Blend',
    false => 'Single origin',
  };

  String? _readValue(BeanFormField f) {
    String? text(TextEditingController c) => _nullIfEmpty(c.text);
    return switch (f) {
      BeanFormField.processing => text(_processing),
      BeanFormField.roastLevel => roastLevelLabel(_roastLevel),
      BeanFormField.country => text(_country),
      BeanFormField.region => text(_region),
      BeanFormField.variety => text(_variety),
      BeanFormField.producer => text(_producer),
      BeanFormField.altitude => text(_altitude),
      BeanFormField.roastedFor => roastedForLabel(_roastedFor),
      BeanFormField.type => _typeLabel,
      _ => null,
    };
  }

  Widget _fieldCell(BeanFormField f) {
    final colors = context.colors;
    final marked = _aiFilled.contains(f.name);
    final label = f.label;
    final select = _selectOf(f);
    if (!_editing || select != null) {
      final value = _readValue(f);
      final cell = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: marked ? colors.accent : colors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text(
                  value ?? '—',
                  style: TextStyle(
                    color: value == null
                        ? colors.textTertiary
                        : colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (_editing) ...[
                const SizedBox(width: 4),
                Icon(
                  _openMenu == select ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ],
            ],
          ),
        ],
      );
      if (!_editing) return cell;
      return InkWell(
        key: ValueKey('select-${f.name}'),
        onTap: () =>
            setState(() => _openMenu = _openMenu == select ? null : select),
        child: cell,
      );
    }
    final (controller, suggestions) = switch (f) {
      BeanFormField.processing => (_processing, _suggestions.processings),
      BeanFormField.country => (_country, _suggestions.countries),
      BeanFormField.region => (_region, const <String>[]),
      BeanFormField.variety => (_variety, _suggestions.varieties),
      BeanFormField.producer => (_producer, _suggestions.producers),
      _ => (_altitude, const <String>[]),
    };
    return _SuggestionRow(
      label: label,
      marked: marked,
      controller: controller,
      suggestions: suggestions,
      capitalization: TextCapitalization.words,
    );
  }

  // Inline list with a tick, like ValueSelectRow. Tapping the chosen one takes
  // it away again.
  Widget _menuPanel(_SelectField field) {
    final colors = context.colors;
    final List<({Object value, String label})> options = switch (field) {
      _SelectField.type => const [
        (value: false, label: 'Single origin'),
        (value: true, label: 'Blend'),
      ],
      _SelectField.roastLevel => [
        for (final o in roastLevelOptions) (value: o.value, label: o.label),
      ],
      _SelectField.roastedFor => [
        for (final o in roastedForOptions) (value: o.value, label: o.label),
      ],
    };
    final Object? current = switch (field) {
      _SelectField.type => _isBlend,
      _SelectField.roastLevel => _roastLevel,
      _SelectField.roastedFor => _roastedFor,
    };
    void pick(Object? value) {
      final key = switch (field) {
        _SelectField.type => BeanFormField.type,
        _SelectField.roastLevel => BeanFormField.roastLevel,
        _SelectField.roastedFor => BeanFormField.roastedFor,
      };
      _clearMark(key.name);
      setState(() {
        switch (field) {
          case _SelectField.type:
            _isBlend = value as bool?;
          case _SelectField.roastLevel:
            _roastLevel = value as String?;
          case _SelectField.roastedFor:
            _roastedFor = value as String?;
        }
        _openMenu = null;
      });
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border.all(color: colors.divider, width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final o in options)
            InkWell(
              onTap: () => pick(current == o.value ? null : o.value),
              child: SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          o.label,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (current == o.value)
                        Icon(Icons.check, size: 18, color: colors.accent),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ----- Bag carousel -------------------------------------------------------

  Widget _bagCarousel(Coffee? coffee) {
    final colors = context.colors;
    final saved = coffee?.bags ?? const <Bean>[];
    final tiles = <Widget>[
      for (final bag in saved) _bagTile(coffee, bag, _drafts[bag.id]),
      for (var i = 0; i < _newBags.length; i++)
        _bagTile(coffee, null, _newBags[i], newNumber: saved.length + i + 1),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    final current = _page.clamp(0, tiles.length - 1);
    final follow = _followBag;
    if (follow != null) {
      final to = saved.indexWhere((b) => b.id == follow.$1);
      if (to >= 0 &&
          (follow.$2 == null || coffee!.stateOf(saved[to]) == follow.$2)) {
        _followBag = null;
        if (to != _page) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pages.hasClients) _pages.jumpToPage(to);
          });
        }
      }
    }
    return Column(
      children: [
        SizedBox(
          height: (_editing ? 308 : 224) + (_timelineOpen ? 62 : 0),
          child: PageView(
            controller: _pages,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              for (final t in tiles)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: t,
                ),
            ],
          ),
        ),
        if (tiles.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < tiles.length; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == current ? colors.accent : colors.textTertiary,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _bagTile(
    Coffee? coffee,
    Bean? bag,
    _BagDraft? draft, {
    int? newNumber,
  }) {
    final colors = context.colors;
    final state = bag != null
        ? coffee!.stateOf(bag)
        : draft?.isFrozen == true
        ? BagState.frozen
        : (draft?.openedAt == null ? BagState.sealed : BagState.open);
    final number = bag != null ? coffee!.numberOf(bag) : newNumber;
    final remaining = bag == null ? null : beanRemaining(bag, _usage);
    final left = state == BagState.open && remaining != null
        ? '≈ ${_formatNumber(remaining.roundToDouble())} g'
        : null;
    final days = bag == null ? null : daysSinceFreshnessStart(bag);
    return Container(
      key: ValueKey('bag-${bag?.id ?? 'new-$number'}'),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Bag $number',
            style: TextStyle(color: colors.textPrimary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final target in const [
                BagState.open,
                BagState.sealed,
                BagState.frozen,
                BagState.empty,
              ])
                Expanded(
                  child: _BagStateButton(
                    state: target,
                    active: state == target,
                    days: days,
                    roastLevel: bag?.roastLevel,
                    onTap: () => _setBagState(bag, draft, state, target),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: Divider(height: 1, color: colors.divider),
          ),
          if (_editing && draft != null)
            _bagForm(bag, draft, left)
          else if (bag != null)
            _bagFacts(bag, left),
          const Spacer(),
          InkWell(
            key: const ValueKey('bag-timeline-toggle'),
            onTap: () => _setTimelineOpen(!_timelineOpen),
            child: SizedBox(
              height: 36,
              child: Row(
                children: [
                  Text(
                    'Timeline',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                  const Spacer(),
                  Icon(
                    _timelineOpen ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_timelineOpen)
            SizedBox(
              height: 62,
              child: _BagTimeline(steps: _timelineSteps(bag, draft)),
            ),
          if (_editing && draft != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: colors.danger,
                  padding: EdgeInsets.zero,
                ),
                onPressed: bag != null
                    ? () => _deleteBag(bag)
                    : () => setState(() {
                        _newBags.remove(draft);
                        draft.dispose();
                      }),
                child: const Text('Delete bag'),
              ),
            ),
        ],
      ),
    );
  }

  // What happened to a bag, oldest first. On the same day: in the order a bag
  // goes through them. While editing, the dates that have no field of their
  // own can be changed here.
  List<_TimelineStep> _timelineSteps(Bean? bag, _BagDraft? draft) {
    final colors = context.colors;
    final roast = draft != null ? draft.roastDate : bag?.roastDate;
    final frozen = draft != null ? draft.frozenDate : bag?.frozenDate;
    final thawed = draft != null ? draft.thawedDate : bag?.thawedDate;
    final opened = draft != null ? draft.openedAt : bag?.openedAt;
    final empty = bag?.emptiedAt;
    VoidCallback? edit(
      DateTime date,
      void Function(DateTime) apply, {
      DateTime? notBefore,
      DateTime? notAfter,
    }) {
      if (!_editing || draft == null) return null;
      return () async {
        final picked = await _pickDate(
          date,
          notBefore: notBefore,
          notAfter: notAfter,
        );
        if (picked != null && mounted) setState(() => apply(picked));
      };
    }

    _TimelineStep step(
      String label,
      DateTime date,
      Color color, [
      VoidCallback? onTap,
    ]) => _TimelineStep(label, date, _shortDate(date), color, onTap);
    final steps = [
      if (roast != null) step('Roasted', roast, colors.sealed),
      if (frozen != null)
        step(
          'Frozen',
          frozen,
          colors.ice,
          edit(frozen, (v) {
            draft
              ?..frozenDate = v
              ..freezerEdited = true;
          }, notAfter: thawed),
        )
      // Thawed, but frozen before freeze dates were kept: while editing the
      // date can be added, so the days before the freezer count again.
      else if (thawed != null && _editing && draft != null)
        _TimelineStep(
          'Frozen',
          thawed,
          'Add',
          colors.ice,
          edit(thawed, (v) {
            draft
              ..frozenDate = v
              ..freezerEdited = true;
          }, notAfter: thawed),
        ),
      if (thawed != null)
        step(
          'Thawed',
          thawed,
          colors.iceLight,
          edit(thawed, (v) {
            draft
              ?..thawedDate = v
              ..freezerEdited = true;
          }, notBefore: frozen),
        ),
      if (opened != null)
        step(
          'Opened',
          opened,
          colors.success,
          edit(opened, (v) {
            draft?.openedAt = v;
          }),
        ),
      if (empty != null) step('Empty', empty, colors.textSecondary),
    ];
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final order = [...steps];
    steps.sort((a, b) {
      final byDay = day(a.date).compareTo(day(b.date));
      return byDay != 0 ? byDay : order.indexOf(a) - order.indexOf(b);
    });
    return steps;
  }

  String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  // One of the four columns below the status symbols.
  Widget _bagCell(String label, Widget value, {String? mark}) {
    final colors = context.colors;
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: mark != null && _aiFilled.contains(mark)
                ? colors.accent
                : colors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 3),
        value,
      ],
    );
  }

  TextStyle get _bagValueStyle => TextStyle(
    color: context.colors.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w500,
  );

  Widget _bagFacts(Bean bag, String? left) {
    Widget cell(String label, String value) => _bagCell(
      label,
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _bagValueStyle,
      ),
    );
    String day(DateTime? d) => d == null ? '—' : _shortDate(d);
    final grams = bag.weightGrams;
    return _bagColumns([
      if (_visible(BeanFormField.weight))
        cell('Weight', grams == null ? '—' : '${_formatNumber(grams)} g')
      else
        null,
      cell('Left', left ?? '—'),
      if (_visible(BeanFormField.roastDate))
        cell('Roasted', day(bag.roastDate))
      else
        null,
      if (_visible(BeanFormField.cost))
        cell('Cost', bag.cost == null ? '—' : '${_formatNumber(bag.cost)} €')
      else
        null,
    ]);
  }

  // Weight, Left, Roasted, Cost: each below its status symbol, always in the
  // same place, also when one of them is switched off.
  Widget _bagColumns(List<Widget?> cells) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final cell in cells)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: cell ?? const SizedBox.shrink(),
          ),
        ),
    ],
  );

  Widget _bagForm(Bean? bag, _BagDraft d, String? left) {
    final colors = context.colors;
    Widget date(
      DateTime? value,
      String empty,
      ValueChanged<DateTime?> onChanged,
    ) => InkWell(
      onTap: () async {
        final picked = await _pickDate(value);
        if (picked != null && mounted) setState(() => onChanged(picked));
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              value == null ? empty : _shortDate(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: value == null
                  ? _bagValueStyle.copyWith(color: colors.textTertiary)
                  : _bagValueStyle,
            ),
          ),
          if (value != null)
            GestureDetector(
              onTap: () => setState(() => onChanged(null)),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.close, size: 15, color: colors.textTertiary),
              ),
            ),
        ],
      ),
    );
    Widget number(TextEditingController c, String suffix, String key) =>
        TextField(
          key: ValueKey('bag-$key'),
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          onChanged: (_) {
            _clearMark(key);
            setState(() {});
          },
          style: _bagValueStyle,
          textAlign: TextAlign.center,
          decoration: _fieldDecoration(
            context,
            suffix: suffix,
            padding: EdgeInsets.zero,
          ),
        );
    return _bagColumns([
      if (_visible(BeanFormField.weight))
        _bagCell(
          'Weight',
          number(d.weight, 'g', BeanFormField.weight.name),
          mark: BeanFormField.weight.name,
        )
      else
        null,
      _bagCell('Left', Text(left ?? '—', maxLines: 1, style: _bagValueStyle)),
      if (_visible(BeanFormField.roastDate))
        _bagCell(
          'Roast date',
          date(d.roastDate, 'Not set', (v) => d.roastDate = v),
          mark: BeanFormField.roastDate.name,
        )
      else
        null,
      if (_visible(BeanFormField.cost))
        _bagCell(
          'Cost',
          number(d.cost, '€', BeanFormField.cost.name),
          mark: BeanFormField.cost.name,
        )
      else
        null,
    ]);
  }

  static InputDecoration _fieldDecoration(
    BuildContext context, {
    String? hint,
    String? suffix,
    EdgeInsets padding = const EdgeInsets.symmetric(vertical: 2),
  }) {
    return InputDecoration(
      isDense: true,
      border: InputBorder.none,
      contentPadding: padding,
      hintText: hint,
      hintStyle: TextStyle(color: context.colors.textTertiary),
      suffixText: suffix,
      suffixStyle: TextStyle(color: context.colors.textSecondary, fontSize: 14),
    );
  }

  // Subtle and in the form the app already has for this (cf. "Enter address
  // manually" in the connection card): no border, no fill, 13 px in the
  // secondary color. By house rule, only touchable things get a fill.
  Widget _fillRow(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _aiBusy ? null : _showFillSheet,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: _aiBusy
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.textTertiary,
                        )
                      : Icon(
                          Icons.auto_awesome_outlined,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                ),
                const SizedBox(width: 8),
                Text(
                  _aiBusy ? 'Reading…' : 'Fill from packaging or link',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        if (_aiNote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _aiNote!,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                if (_aiUndo != null)
                  GestureDetector(
                    onTap: _undoFill,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        'Undo',
                        style: TextStyle(color: colors.accent, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TimelineStep {
  const _TimelineStep(this.label, this.date, this.text, this.color, this.onTap);

  final String label;
  final DateTime date;
  final String text;
  final Color color;

  /// Set while the date can be changed.
  final VoidCallback? onTap;
}

/// A bag's dates on a line, evenly spaced.
class _BagTimeline extends StatelessWidget {
  const _BagTimeline({required this.steps});

  final List<_TimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (steps.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          'No dates yet.',
          style: TextStyle(color: colors.textTertiary, fontSize: 13),
        ),
      );
    }
    Widget line(bool visible) => Expanded(
      child: Container(height: 2, color: visible ? colors.divider : null),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: 14,
                  child: Row(
                    children: [
                      line(i > 0),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: steps[i].color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      line(i < steps.length - 1),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  steps[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                InkWell(
                  onTap: steps[i].onTap,
                  child: Text(
                    steps[i].text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: steps[i].onTap != null
                          ? colors.accent
                          : colors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One of the four status symbols at the top of a bag tile.
class _BagStateButton extends StatelessWidget {
  const _BagStateButton({
    required this.state,
    required this.active,
    required this.days,
    required this.roastLevel,
    required this.onTap,
  });

  final BagState state;
  final bool active;
  final int? days;
  final String? roastLevel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (label, activeColor) = switch (state) {
      BagState.open => ('Open', colors.success),
      BagState.sealed => ('Sealed', colors.sealed),
      BagState.frozen => ('Frozen', colors.ice),
      BagState.empty => ('Empty', colors.textSecondary),
    };
    final color = active ? activeColor : colors.divider;
    final Widget sign = switch (state) {
      BagState.open when active && days != null => FreshnessRing(
        days: days!,
        roastLevel: roastLevel,
      ),
      BagState.open => PlainFreshnessRing(color: color, days: days),
      BagState.sealed => SealedRing(color: color),
      BagState.frozen => FrozenRing(color: active ? null : color),
      BagState.empty => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
      ),
    };
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 40, child: Center(child: sign)),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Text row with suggestion chips below while the field has focus and letters
// have been typed that match the start of a suggestion.
// [tokenMode]: the field holds a comma list; suggestions apply to the word
// being typed, and a tap appends it to the list.
class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow({
    required this.label,
    required this.controller,
    required this.suggestions,
    this.tokenMode = false,
    this.showLabel = true,
    this.fontSize = 17,
    this.weight = FontWeight.w500,
    this.color,
    this.marked = false,
    this.capitalization = TextCapitalization.none,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final List<String> suggestions;
  final bool tokenMode;

  /// The value came from packaging or a web page and is not confirmed yet:
  /// shown only through the label color (on the photo: the text color).
  final bool marked;

  // On the photo the field stands alone, like its text when reading.
  final bool showLabel;
  final double fontSize;
  final FontWeight weight;
  final Color? color;
  final TextCapitalization capitalization;
  final String? hint;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  // At most this many suggestions at once.
  static const _maxChips = 6;

  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(_SuggestionRow old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  // Words already fully entered (everything before the last comma) and the
  // word currently being typed.
  ({List<String> done, String current}) _split() {
    final text = widget.controller.text;
    if (!widget.tokenMode) return (done: const [], current: text.trim());
    final comma = text.lastIndexOf(',');
    return (
      done: splitTaste(comma < 0 ? '' : text.substring(0, comma)),
      current: text.substring(comma + 1).trim(),
    );
  }

  // Only values starting with the letters already typed; without input (or
  // with an empty current word) there are no suggestions.
  List<String> _matches() {
    if (!_focus.hasFocus) return const [];
    final (:done, :current) = _split();
    final query = current.toLowerCase();
    if (query.isEmpty) return const [];
    final taken = {for (final d in done) d.toLowerCase()};
    return [
      for (final s in widget.suggestions)
        if (!taken.contains(s.toLowerCase()) &&
            s.toLowerCase() != query &&
            s.toLowerCase().startsWith(query))
          s,
    ].take(_maxChips).toList();
  }

  void _apply(String value) {
    final text = widget.tokenMode
        ? '${[..._split().done, value].join(', ')}, '
        : value;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Widget _field() {
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      textCapitalization: widget.capitalization,
      // Room for the chip row below the field so it doesn't end up under the
      // keyboard during autoscroll.
      scrollPadding: const EdgeInsets.only(bottom: 100),
      style: TextStyle(
        color: !widget.showLabel && widget.marked
            ? context.colors.accent
            : widget.color ?? context.colors.textPrimary,
        fontSize: widget.fontSize,
        fontWeight: widget.weight,
      ),
      decoration: _BeanFormScreenState._fieldDecoration(
        context,
        hint: widget.hint,
      ),
    );
  }

  // Words already in a comma list, shown while typing in it.
  List<String> _taken() {
    if (!widget.tokenMode || !_focus.hasFocus) return const [];
    return _split().done;
  }

  void _removeToken(String token) {
    final (:done, :current) = _split();
    final rest = [
      for (final d in done)
        if (d != token) d,
    ];
    final text = [...rest, if (current.isNotEmpty) current].join(', ');
    final withComma = rest.isNotEmpty && current.isEmpty ? '$text, ' : text;
    widget.controller.value = TextEditingValue(
      text: withComma,
      selection: TextSelection.collapsed(offset: withComma.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches();
    final taken = _taken();
    return Column(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showLabel)
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.marked
                      ? context.colors.accent
                      : context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            _field(),
          ],
        ),
        // Suggestions as underline options in a wrap (no chips): not yet
        // taken in textSecondary with a thin divider line, the typed letters
        // in textPrimary. A comma list (taste) also shows the words already
        // taken as chosen items — tapping one removes it again.
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.topCenter,
          child: matches.isEmpty && taken.isEmpty
              ? const SizedBox(width: double.infinity)
              // Without TextFieldTapRegion, a tap on an item counts as
              // "outside" and takes focus from the field.
              : TextFieldTapRegion(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Wrap(
                      spacing: UnderlineSelect.spacing,
                      children: [
                        for (final t in taken)
                          UnderlineItem(
                            label: t,
                            selected: true,
                            onTap: () => _removeToken(t),
                          ),
                        for (final m in matches)
                          UnderlineItem(
                            label: m,
                            selected: false,
                            idleUnderline: true,
                            highlight: _split().current,
                            onTap: () => _apply(m),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// Where the app should read from.
enum _FillSource { camera, gallery, link }

// The state of the form before anything was imported. Only there so that
// "Undo" really restores everything — including a field that was already
// filled before and got overwritten.
class _FormSnapshot {
  _FormSnapshot({
    required this.texts,
    required this.isBlend,
    required this.roastedFor,
    required this.roastLevel,
    required this.roastDate,
    required this.photoPath,
  });

  final Map<String, String> texts;
  final bool? isBlend;
  final String? roastedFor;
  final String? roastLevel;
  final DateTime? roastDate;
  final String? photoPath;

  factory _FormSnapshot.of(_BeanFormScreenState state) => _FormSnapshot(
    texts: {
      for (final entry in state._markedControllers.entries)
        entry.key: entry.value.text,
    },
    isBlend: state._isBlend,
    roastedFor: state._roastedFor,
    roastLevel: state._roastLevel,
    roastDate: state._bagOnScreen?.roastDate,
    photoPath: state._photoPath,
  );

  void restore(_BeanFormScreenState state) {
    state._markedControllers.forEach((key, controller) {
      controller.text = texts[key] ?? '';
    });
    state._isBlend = isBlend;
    state._roastedFor = roastedFor;
    state._roastLevel = roastLevel;
    state._bagOnScreen?.roastDate = roastDate;
    state._photoPath = photoPath;
  }
}

enum _DeleteChoice { usedUp, delete }

enum _ClashChoice { sameCoffee, newCoffee }
