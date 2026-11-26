import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/models/history_import.dart';
import 'package:beand/screens/history/history_tab.dart';
import 'package:beand/screens/history/shot_detail_screen.dart';
import 'package:beand/screens/live/ruler_picker.dart';
import 'package:beand/widgets/value_select_row.dart';
import 'package:beand/screens/beans/beans_tab.dart';
import 'package:beand/screens/history/history_widgets.dart';
import 'package:beand/models/gear.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/gear_store.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/widgets/app_button.dart';
import 'package:beand/widgets/header_icon_button.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/screens/live/post_shot_card.dart';
import 'package:beand/screens/live/shot_cards_carousel.dart';
import 'package:beand/models/shot_rating.dart';
import 'package:beand/widgets/taste_rater.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';

import 'support/offline_gaggimate.dart';

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

Widget _app(AppDatabase db, Widget home) => MultiProvider(
  providers: [
    Provider<AppDatabase>.value(value: db),
    // The filter sheet derives its machine options from the Home switches
    // (see HistoryFilter).
    ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
    // Shot detail and Post-Shot card ask whether shot analysis is on (not
    // here: no AI set up).
    ChangeNotifierProvider<AiSettings>.value(
      value: AiSettings(keyStore: InMemoryAiKeyStore()),
    ),
    // The Post-Shot card reads from this whether it is the active card.
    ChangeNotifierProvider<LiveShotService>.value(
      value: MeticulousLiveShotService(
        MeticulousSocketService(hostname: 'unreachable.local'),
      ),
    ),
  ],
  child: MaterialApp(theme: buildAppTheme(), home: home),
);

// The second history row is a RichText of icon+value pairs (Grind, Dose,
// Yield) — reduced here to the plain text without icons.
Finder metricsLine(String text) => find.byWidgetPredicate(
  (w) =>
      w is RichText &&
      w.text
              .toPlainText(includePlaceholders: false)
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim() ==
          text,
);

Future<int> _insertShot(
  AppDatabase db, {
  required DateTime at,
  int? beanId,
  String profile = "Damian's LRv2",
  double? dose = 18,
  String grind = '3.2',
  int? rating,
  String? externalId,
  bool withReadings = true,
}) async {
  final raw = Map<String, dynamic>.from(
    jsonDecode(
      File('test/fixtures/history_entry_bailey.json').readAsStringSync(),
    ) as Map,
  );
  final parsed = parseHistoryEntry(raw)!;
  return db.insertShotWithReadings(
    ShotsCompanion.insert(
      timestamp: at,
      externalId: Value(externalId),
      beanId: Value(beanId),
      profileName: Value(profile),
      profileColor: const Value('#C96F4A'),
      doseGrams: Value(dose),
      grindSize: Value(grind),
      finalWeight: const Value(38.4),
      durationMs: const Value(34000),
      profileTemp: const Value(93.1),
      rating: Value(rating),
    ),
    withReadings ? parsed.readings : const [],
  );
}

void main() {
  // The Post-Shot card remembers its last Save in the prefs.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  // Drift delivers stream results asynchronously in real time (like
  // beans_tab_test).
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  Future<void> teardownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    // Pending stream queries need real time to complete.
    await tester.runAsync(db.close);
  }

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('History: empty list shows a hint', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(_app(db, const Scaffold(body: HistoryTab())));
    await settle(tester);
    expect(find.textContaining('No shots recorded yet'), findsOneWidget);
    await teardownApp(tester);
  });

  testWidgets('History row: a long bean name uses the room a short roaster '
      'leaves', (tester) async {
    // User 2026-11-22: bean and roaster had half the line each, so long
    // bean names were cut even next to a short roaster.
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final short = await db.insertBean(
        BeansCompanion.insert(
          name: 'Hambela Natural Lot 7',
          roaster: const Value('Coffea'),
        ),
      );
      final long = await db.insertBean(
        BeansCompanion.insert(
          name: 'Ethiopia Guji Hambela Natural Anaerobic Lot 7',
          roaster: const Value('Very Long Roastery Name Coffee Co'),
        ),
      );
      final now = DateTime.now();
      await _insertShot(db, at: now, beanId: short.id, externalId: 'a');
      await _insertShot(
        db,
        at: now.subtract(const Duration(minutes: 5)),
        beanId: long.id,
        externalId: 'b',
      );
    });
    await tester.pumpWidget(_app(db, const Scaffold(body: HistoryTab())));
    await settle(tester);

    RenderParagraph para(String text) =>
        tester.renderObject<RenderParagraph>(find.text(text));
    expect(para('Hambela Natural Lot 7').didExceedMaxLines, isFalse);
    expect(para('Coffea').didExceedMaxLines, isFalse);
    // Both long: both cut, the roaster keeps about a third of the line.
    expect(
      para('Ethiopia Guji Hambela Natural Anaerobic Lot 7').didExceedMaxLines,
      isTrue,
    );
    final roaster = tester.getSize(
      find.text('Very Long Roastery Name Coffee Co'),
    );
    final bean = tester.getSize(
      find.text('Ethiopia Guji Hambela Natural Anaerobic Lot 7'),
    );
    expect(roaster.width, greaterThan(50));
    expect(bean.width, greaterThan(roaster.width));
    await teardownApp(tester);
  });

  testWidgets('History: rows grouped by day, search finds shots', (
    tester,
  ) async {
    bigScreen(tester);
    await tester.runAsync(() async {
      final bean = await db.insertBean(
        BeansCompanion.insert(
          name: 'Guji Natural',
          roaster: const Value('La Cabra'),
        ),
      );
      final now = DateTime.now();
      await _insertShot(
        db,
        at: now,
        beanId: bean.id,
        rating: 4,
        externalId: 'a',
      );
      await _insertShot(
        db,
        at: now.subtract(const Duration(days: 1)),
        profile: 'Soup',
        externalId: 'b',
      );
    });
    await tester.pumpWidget(_app(db, const Scaffold(body: HistoryTab())));
    await settle(tester);

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    // Row: bean + roaster on top, below it profile and Grind/Dose/Yield.
    expect(find.text('Guji Natural'), findsOneWidget);
    expect(find.text('La Cabra'), findsOneWidget);
    expect(metricsLine('3.2 18 g 38.4 g'), findsNWidgets(2));
    // A shot without a bean shows the profile in the first row.
    expect(find.text('Soup'), findsOneWidget);

    // Search like in the bean list (wanted since 2026-10-17; before, the
    // History tab deliberately had only filter and settings).
    expect(find.byTooltip('Filter'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    // Matches bean, roastery, profile, notes or machine.
    await tester.enterText(find.byType(TextField), 'cabra');
    await tester.pump();
    expect(find.text('Guji Natural'), findsOneWidget);
    expect(find.text('Soup'), findsNothing);
    await tester.enterText(find.byType(TextField), 'soup');
    await tester.pump();
    expect(find.text('Guji Natural'), findsNothing);
    expect(find.text('Soup'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'nothing like this');
    await tester.pump();
    expect(find.text('No matching shots.'), findsOneWidget);
    // Closing the search shows everything again.
    await tester.tap(find.byTooltip('Close search'));
    await tester.pump();
    expect(find.text('Guji Natural'), findsOneWidget);
    expect(find.text('Soup'), findsOneWidget);

    await teardownApp(tester);
  });

  testWidgets('Filter sheet: minimum rating narrows the list', (tester) async {
    bigScreen(tester);
    await tester.runAsync(() async {
      final now = DateTime.now();
      await _insertShot(
        db,
        at: now,
        rating: 5,
        profile: 'Good',
        externalId: 'a',
      );
      await _insertShot(
        db,
        at: now.subtract(const Duration(hours: 1)),
        rating: 2,
        profile: 'Bad',
        externalId: 'b',
      );
    });
    await tester.pumpWidget(_app(db, const Scaffold(body: HistoryTab())));
    await settle(tester);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Bad'), findsOneWidget);

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 ★ +'));
    await tester.pump();
    expect(find.text('Show 1 shot'), findsOneWidget);
    await tester.tap(find.text('Show 1 shot'));
    await tester.pumpAndSettle();
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Bad'), findsNothing);

    await teardownApp(tester);
  });

  Future<T> inDb<T>(WidgetTester tester, Future<T> Function() f) async {
    late T result;
    await tester.runAsync(() async => result = await f());
    return result;
  }

  Finder star(int n) => find
      .descendant(
        of: find.byType(StarRating),
        matching: find.byIcon(Icons.star_rounded),
      )
      .at(n - 1);

  testWidgets('Shot detail: key figures, phases; edit stars and note', (
    tester,
  ) async {
    bigScreen(tester);
    late int id;
    await tester.runAsync(() async {
      final bean = await db.insertBean(
        BeansCompanion.insert(
          name: 'Guji Natural',
          roaster: const Value('La Cabra'),
        ),
      );
      id = await _insertShot(
        db,
        at: DateTime(2026, 9, 21, 8, 12),
        beanId: bean.id,
        rating: 2,
        externalId: 'a',
      );
    });
    await tester.pumpWidget(_app(db, ShotDetailScreen(shotId: id)));
    await settle(tester);

    expect(find.text('Guji Natural'), findsOneWidget);
    expect(find.text('34.0 s'), findsOneWidget);
    expect(find.text('38.4 g'), findsOneWidget);
    expect(find.text('93.1 °C'), findsOneWidget);
    expect(find.text('RATIO'), findsOneWidget);
    expect(metricsLine('1:2.1'), findsOneWidget);
    // Since the redesign the stage bar only names the phase at the cursor;
    // the cursor starts at the end of the brew.
    expect(find.text('Percolation'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'\d+\.\d s / \d+\.\d s')),
      findsOneWidget,
    );
    expect(
      find.text('Compare'),
      findsOneWidget,
      reason: 'row in the style of the Pre-Shot rows',
    );
    expect(find.byTooltip('Share'), findsOneWidget);

    // Stars: 5th star sets 5; tapping the current rating again clears it.
    await tester.tap(star(5));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.rating,
      5,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(star(5));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.rating,
      isNull,
    );

    // Note: saved debounced.
    await tester.enterText(
      find.descendant(
        of: find.byType(ShotNotesField),
        matching: find.byType(TextField),
      ),
      'Sweet, try 0.1 finer',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.notes,
      'Sweet, try 0.1 finer',
    );

    await teardownApp(tester);
  });

  testWidgets('shot detail: the temperature can be changed afterwards', (
    tester,
  ) async {
    bigScreen(tester);
    late int id;
    await tester.runAsync(() async {
      id = await _insertShot(db, at: DateTime(2026, 9, 21, 8), externalId: 't');
    });
    await tester.pumpWidget(_app(db, ShotDetailScreen(shotId: id)));
    await settle(tester);
    expect(find.text('93.1 °C'), findsOneWidget);
    await tester.tap(find.text('93.1 °C'));
    await tester.pump();
    final ruler = tester.widget<RulerPicker>(
      find.byKey(const ValueKey('temp')),
    );
    ruler.onChanged(96);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.profileTemp,
      96,
    );
    await teardownApp(tester);
  });

  testWidgets('shot detail: brew chain changed afterwards', (tester) async {
    bigScreen(tester);
    final id = await inDb(
      tester,
      () => _insertShot(db, at: DateTime(2026, 10, 19), externalId: 'a'),
    );
    final gear = GearStore.inMemory(
      gear: const [
        Gear(
          id: 'g',
          type: GearType.grinder,
          brand: 'Niche',
          model: 'Zero',
          specs: {
            'burrs': ['SSP'],
            'activeBurr': 'SSP',
          },
        ),
        Gear(id: 'b', type: GearType.basket, brand: 'IMS', model: '18'),
      ],
      chains: const [
        BrewChain(id: 'bar', name: 'Espresso bar', gearIds: ['b', 'g']),
        BrewChain(id: 'travel', name: 'Travel', gearIds: ['b']),
      ],
    );
    final setups = ShotSetups(
      meticulous: ShotSetup.inMemory()..gear = gear,
      gaggimate: ShotSetup.inMemory(machineKey: 'gaggimate')..gear = gear,
    );
    await tester.pumpWidget(
      _app(
        db,
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GearStore>.value(value: gear),
            Provider<ShotSetups>.value(value: setups),
          ],
          child: ShotDetailScreen(shotId: id),
        ),
      ),
    );
    await settle(tester);

    // No chain on the shot yet: a dash, tappable.
    await tester.tap(find.byKey(const ValueKey('shot-chain')));
    await tester.pump();
    expect(find.text('Travel'), findsOneWidget);
    await tester.tap(find.text('Espresso bar'));
    await settle(tester);

    final shot = (await inDb(tester, () => db.watchShotEntry(id).first))!.shot;
    expect(shot.brewChainId, 'bar');
    expect(shot.grinder, 'Zero');
    expect(shot.burrs, 'SSP');
    // Desk order: grinder before basket.
    expect(shot.brewedWith, 'Niche Zero (SSP)\nIMS 18');
    expect(
      find.textContaining('Niche Zero (SSP)  ·  IMS 18', findRichText: true),
      findsOneWidget,
    );
    // The newest shot of its machine: the next brew starts with it.
    expect(setups.meticulous.chain?.id, 'bar');

    await teardownApp(tester);
  });

  testWidgets('shot detail: grind marks without a grinder on the shot', (
    tester,
  ) async {
    // User 2026-11-22: grind added afterwards (no chain on the shot) had no
    // marks to pick — now the current chain's grinder gives them, and the
    // shot takes that chain with the grind.
    bigScreen(tester);
    final id = await inDb(
      tester,
      () => _insertShot(db, at: DateTime(2026, 10, 19), externalId: 'a'),
    );
    final gear = GearStore.inMemory(
      gear: const [
        Gear(
          id: 'm',
          type: GearType.grinder,
          brand: 'Kafatek',
          model: 'Monolith',
          specs: {
            'scale': {
              'unit': 'dial',
              'step': 0.1,
              'min': 0,
              'max': 9,
              'markers': [
                {'name': 'Green', 'color': 0xFF5F8A62, 'offset': 0},
                {'name': 'Red', 'color': 0xFFA85A55, 'offset': 6.8},
              ],
            },
          },
        ),
      ],
      chains: const [
        BrewChain(id: 'bar', name: 'Espresso bar', gearIds: ['m']),
      ],
    );
    final setups = ShotSetups(
      meticulous: ShotSetup.inMemory()..gear = gear,
      gaggimate: ShotSetup.inMemory(machineKey: 'gaggimate')..gear = gear,
    );
    setups.meticulous.setChain('bar');
    await tester.pumpWidget(
      _app(
        db,
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GearStore>.value(value: gear),
            Provider<ShotSetups>.value(value: setups),
          ],
          child: ShotDetailScreen(shotId: id),
        ),
      ),
    );
    await settle(tester);

    await tester.tap(find.text('GRIND'));
    await tester.pump();
    expect(find.byKey(const ValueKey('marker-Red')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('marker-Red')));
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);

    final shot = (await inDb(tester, () => db.watchShotEntry(id).first))!.shot;
    expect(shot.grindMarker, 'Red');
    expect(shot.grinder, 'Monolith');
    expect(shot.brewChainId, 'bar');

    await teardownApp(tester);
  });

  // User 2026-11-23: a shot brewed while the app was closed comes in
  // without its setup. Post card suggests it (Save takes it), the history
  // marks it with "Same as last", the shot detail copies from another shot.
  Future<(int, int)> earlierAndBare(WidgetTester tester) async {
    late int earlier, bare;
    await tester.runAsync(() async {
      final b = await db.insertBean(
        BeansCompanion.insert(name: 'Fazenda Matão'),
      );
      earlier = await db
          .into(db.shots)
          .insert(
            ShotsCompanion.insert(
              timestamp: DateTime(2026, 11, 22, 12),
              machine: const Value('meticulous'),
              profileName: const Value('LRv2'),
              beanId: Value(b.id),
              doseGrams: const Value(14),
              grindSize: const Value('3.8'),
            ),
          );
      bare = await db
          .into(db.shots)
          .insert(
            ShotsCompanion.insert(
              timestamp: DateTime(2026, 11, 23, 22),
              machine: const Value('meticulous'),
              profileName: const Value('LRv2'),
            ),
          );
    });
    return (earlier, bare);
  }

  testWidgets('Post Shot: a shot without its setup gets a suggestion, '
      'Save takes it', (tester) async {
    bigScreen(tester);
    final (_, bare) = await earlierAndBare(tester);
    await tester.pumpWidget(
      _app(
        db,
        const Scaffold(
          body: SizedBox(
            height: ShotCardsCarousel.cardHeight,
            child: PostShotCard(),
          ),
        ),
      ),
    );
    // Suggestion, then the bean's name: one real-time round each.
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(find.byKey(const ValueKey('post-suggestion')), findsOneWidget);
    expect(find.text('Last shot'), findsOneWidget);
    expect(find.text('Fazenda Matão · 14 g · 3.8'), findsOneWidget);
    // Only a suggestion until Save.
    expect(
      (await inDb(tester, () => db.watchShotEntry(bare).first))!.shot.beanId,
      isNull,
    );

    await tester.tap(find.text('Save'));
    await settle(tester);
    final shot = (await inDb(
      tester,
      () => db.watchShotEntry(bare).first,
    ))!.shot;
    expect(shot.beanId, isNotNull);
    expect(shot.doseGrams, 14);
    expect(shot.grindSize, '3.8');
    await tester.pump(const Duration(seconds: 2));
    await teardownApp(tester);
  });

  testWidgets('History: "Needs details" filter and "Same as last"', (
    tester,
  ) async {
    bigScreen(tester);
    final (earlier, bare) = await earlierAndBare(tester);
    await tester.pumpWidget(_app(db, const Scaffold(body: HistoryTab())));
    await settle(tester);
    await settle(tester);
    expect(find.text('Needs details · 1'), findsOneWidget);
    expect(find.text('Needs details'), findsOneWidget);

    // The filter shows only the shot without its setup.
    await tester.tap(find.byKey(const ValueKey('needs-details-filter')));
    await tester.pump();
    expect(find.text('Fazenda Matão'), findsNothing);

    await tester.tap(find.text('Same as last'));
    await settle(tester);
    await settle(tester);
    final shot = (await inDb(
      tester,
      () => db.watchShotEntry(bare).first,
    ))!.shot;
    expect(shot.doseGrams, 14);
    expect(shot.grindSize, '3.8');
    expect(find.text('Needs details'), findsNothing);
    expect(earlier, isNot(bare));
    await teardownApp(tester);
  });

  testWidgets('Shot detail: Copy from… takes bean, dose and grind', (
    tester,
  ) async {
    bigScreen(tester);
    final (_, bare) = await earlierAndBare(tester);
    await tester.pumpWidget(_app(db, ShotDetailScreen(shotId: bare)));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('copy-from')));
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('COPY FROM · LRV2'), findsOneWidget);
    await tester.tap(find.text('Fazenda Matão · 14 g · 3.8'));
    await settle(tester);
    await settle(tester);
    final shot = (await inDb(
      tester,
      () => db.watchShotEntry(bare).first,
    ))!.shot;
    expect(shot.beanId, isNotNull);
    expect(shot.doseGrams, 14);
    expect(shot.grindSize, '3.8');
    await tester.pump(const Duration(seconds: 2));
    await teardownApp(tester);
  });

  testWidgets('note is still saved when leaving the screen', (tester) async {
    bigScreen(tester);
    final id = await inDb(
      tester,
      () => _insertShot(db, at: DateTime(2026, 9, 21), externalId: 'a'),
    );
    await tester.pumpWidget(_app(db, ShotDetailScreen(shotId: id)));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(ShotNotesField),
        matching: find.byType(TextField),
      ),
      'quick note',
    );
    await tester.pumpWidget(
      const SizedBox(),
    ); // screen gone before the timer fires
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.notes,
      'quick note',
    );
    await tester.pump(
      Duration.zero,
    ); // drift cleanup timer of the torn-down streams
    await tester.runAsync(db.close);
  });

  testWidgets(
    'comparison in detail: selection, older shot dashed, values dimmed beside',
    (tester) async {
      bigScreen(tester);
      late int newer;
      await tester.runAsync(() async {
        final bean = await db.insertBean(
          BeansCompanion.insert(name: 'Guji Natural'),
        );
        await _insertShot(
          db,
          at: DateTime(2026, 9, 20, 7, 50),
          beanId: bean.id,
          grind: '3.4',
          externalId: 'old',
        );
        newer = await _insertShot(
          db,
          at: DateTime(2026, 9, 21, 8, 12),
          beanId: bean.id,
          grind: '3.2',
          externalId: 'new',
        );
        await _insertShot(
          db,
          at: DateTime(2026, 9, 19),
          profile: 'Other bean shot',
          externalId: 'unrelated',
        );
      });
      await tester.pumpWidget(_app(db, ShotDetailScreen(shotId: newer)));
      await settle(tester);

      // As in the Pre-Shot card: the "Compare" row expands a list.
      expect(find.text('Select shot'), findsOneWidget);
      await tester.tap(find.text('Select shot'));
      await settle(tester); // reads the shots from the DB
      await tester.pump();
      final picker = find.byType(ValueSelectList<int>);
      expect(picker, findsOneWidget);
      // Shots with the same bean first, then the rest; the current one is
      // missing.
      final tiles = tester
          .widgetList<Text>(
            find.descendant(of: picker, matching: find.byType(Text)),
          )
          .map((t) => t.textSpan?.toPlainText() ?? t.data ?? '')
          .toList();
      expect(
        tiles.indexWhere((t) => t.startsWith('Guji Natural')),
        lessThan(tiles.indexWhere((t) => t.startsWith('Other bean shot'))),
      );
      expect(
        tiles.where((t) => t.startsWith('Guji Natural')),
        hasLength(1),
        reason: 'only the other Guji shot, not the open one',
      );
      expect(tiles.any((t) => t.contains('Mon 21 Sep')), isFalse);

      // Selecting closes the list and shows the comparison.
      await tester.tap(
        find.descendant(
          of: picker,
          matching: find.textContaining('Guji Natural'),
        ),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ValueSelectList<int>), findsNothing);

      expect(find.textContaining('Sun 20 Sep · 07:50'), findsOneWidget);
      expect(find.textContaining('older'), findsWidgets);
      // Differing grind: new value plus the older one smaller beside it.
      expect(find.textContaining('3.2  3.4'), findsOneWidget);
      // Equal values (dose 18) also sit side by side.
      expect(find.text('18 g  18'), findsOneWidget);
      expect(find.byTooltip('Remove comparison'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove comparison'));
      await tester.pump();
      expect(find.text('Select shot'), findsOneWidget);
      expect(find.textContaining('Sun 20 Sep · 07:50'), findsNothing);

      await teardownApp(tester);
    },
  );

  testWidgets('Post Shot without shots: hint', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(
      _app(
        db,
        const Scaffold(
          body: SizedBox(
            height: ShotCardsCarousel.cardHeight,
            child: PostShotCard(),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.textContaining('No shot yet'), findsOneWidget);
    await teardownApp(tester);
  });

  testWidgets('Post Shot: Save empties the card until the next shot, Undo '
      'brings it back', (tester) async {
    bigScreen(tester);
    await tester.runAsync(
      () => _insertShot(
        db,
        at: DateTime(2026, 9, 21),
        profile: 'First',
        externalId: 'a',
      ),
    );
    Widget card() => _app(
      db,
      const Scaffold(
        body: SizedBox(
          height: ShotCardsCarousel.cardHeight,
          child: PostShotCard(),
        ),
      ),
    );
    await tester.pumpWidget(card());
    await settle(tester);
    expect(find.text('First'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('First'), findsNothing);
    expect(find.text('Your next shot lands here.'), findsOneWidget);
    expect(find.byKey(const ValueKey('post-saved-check')), findsOneWidget);
    // The Save button has turned into "Open last shot".
    expect(find.text('Save'), findsNothing);
    expect(find.text('Open last shot'), findsOneWidget);
    final prefs = await tester.runAsync(SharedPreferences.getInstance);
    expect(
      prefs!.getInt(postConfirmedPrefKey('meticulous')),
      DateTime(2026, 9, 21).millisecondsSinceEpoch,
    );

    // Undo in the message: the shot is back, the pref cleared.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('First'), findsOneWidget);
    expect(prefs.getInt(postConfirmedPrefKey('meticulous')), isNull);

    // Saved again: still empty after a restart of the card (pref kept).
    await tester.tap(find.text('Save'));
    await settle(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(card());
    await settle(tester);
    expect(find.text('First'), findsNothing);

    // The next shot of the machine shows up again.
    await tester.runAsync(
      () => _insertShot(
        db,
        at: DateTime(2026, 9, 22),
        profile: 'Second',
        externalId: 'b',
      ),
    );
    await settle(tester);
    expect(find.text('Second'), findsOneWidget);

    await teardownApp(tester);
  });

  testWidgets('Post Shot: shows the last shot, rating and note are editable', (
    tester,
  ) async {
    bigScreen(tester);
    late int id;
    await tester.runAsync(() async {
      await _insertShot(
        db,
        at: DateTime(2026, 9, 20),
        profile: 'Old',
        externalId: 'a',
      );
      id = await _insertShot(
        db,
        at: DateTime(2026, 9, 21),
        profile: 'Newest',
        externalId: 'b',
      );
    });
    await tester.pumpWidget(
      _app(
        db,
        const Scaffold(
          body: SizedBox(
            height: ShotCardsCarousel.cardHeight,
            child: PostShotCard(),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Old'), findsNothing);

    await tester.tap(star(3));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.rating,
      3,
    );

    final notesField = find.descendant(
      of: find.byType(ShotNotesField),
      matching: find.byType(TextField),
    );
    await tester.enterText(notesField, 'balanced');
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.notes,
      'balanced',
    );

    // Drag rating: a tap on the line sets the value and moves on to the
    // next axis. The stars were tapped by hand above, so they stay.
    final rater = tester.getRect(find.byType(TasteRater));
    Future<Shot> tapLine(double fraction) async {
      await tester.tapAt(
        Offset(
          rater.left + 12 + (rater.width - 24) * fraction,
          rater.top + 18 + 20,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      return (await inDb(tester, () => db.watchShotEntry(id).first))!.shot;
    }

    expect(find.text('Acidity'), findsOneWidget);
    var rated = await tapLine(0);
    expect(rated.rateValues[RateAxis.acidity], 0);
    expect(find.text('Sweetness'), findsOneWidget);
    rated = await tapLine(1);
    expect(rated.rateValues[RateAxis.sweetness], 10);
    expect(rated.rating, 3);
    expect(rated.starsManual, isTrue);
    expect(find.text('Flavor'), findsOneWidget);

    await teardownApp(tester);
  });

  testWidgets(
    'Detail: delete shot with confirmation, screen closes, shot is gone',
    (tester) async {
      bigScreen(tester);
      final id = await inDb(
        tester,
        () => _insertShot(
          db,
          at: DateTime(2026, 9, 21),
          profile: 'Doomed',
          externalId: 'a',
        ),
      );
      await inDb(
        tester,
        () => _insertShot(
          db,
          at: DateTime(2026, 9, 20),
          profile: 'Survivor',
          externalId: 'b',
        ),
      );
      await tester.pumpWidget(
        _app(
          db,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ShotDetailScreen(shotId: id),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // route transition
      await settle(tester);
      expect(find.byType(ShotDetailScreen), findsOneWidget);

      // The delete button sits below the card at the end of the page.
      final deleteButton = find.widgetWithText(AppButton, 'Delete shot');

      // Cancel deletes nothing.
      await tester.ensureVisible(deleteButton);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(find.text('Delete this shot?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ShotDetailScreen), findsOneWidget);
      expect(
        (await inDb(tester, () => db.watchShotEntries().first)),
        hasLength(2),
      );

      await tester.ensureVisible(deleteButton);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ShotDetailScreen), findsNothing);
      final left = await inDb(tester, () => db.watchShotEntries().first);
      expect(left.map((e) => e.shot.profileName), ['Survivor']);

      await teardownApp(tester);
    },
  );

  testWidgets(
    'List: long press starts selection, delete several, Back ends selection',
    (tester) async {
      bigScreen(tester);
      final now = DateTime.now();
      await tester.runAsync(() async {
        await _insertShot(db, at: now, profile: 'One', externalId: 'a');
        await _insertShot(
          db,
          at: now.subtract(const Duration(hours: 1)),
          profile: 'Two',
          externalId: 'b',
        );
        await _insertShot(
          db,
          at: now.subtract(const Duration(hours: 2)),
          profile: 'Three',
          externalId: 'c',
        );
      });
      await tester.pumpWidget(_app(db, const Scaffold(body: HistoryTab())));
      await settle(tester);

      await tester.longPress(find.text('One'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      // In selection mode tapping doesn't open a detail but selects.
      await tester.tap(find.text('Two'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byType(ShotDetailScreen), findsNothing);
      await tester.tap(find.text('Two')); // deselect again
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      // Back ends the selection (not the app).
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.textContaining('selected'), findsNothing);

      await tester.longPress(find.text('One'));
      await tester.tap(find.text('Three'));
      await tester.pump();
      await tester.tap(find.byTooltip('Delete selected shots'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 shots?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('One'), findsNothing);
      expect(find.text('Three'), findsNothing);
      expect(find.text('Two'), findsOneWidget);
      expect(find.textContaining('selected'), findsNothing);

      await teardownApp(tester);
    },
  );

  testWidgets(
    'headers: search, filter, gear equally small in History and Beans',
    (tester) async {
      bigScreen(tester);
      Widget withProviders(Widget tab) => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          ChangeNotifierProvider<MeticulousSocketService>.value(
            value: MeticulousSocketService(hostname: 'unreachable.local'),
          ),
          // The same machine once more under the shared interface: the
          // Pre-Shot card addresses it through that.
          ChangeNotifierProvider<EspressoMachine>.value(
            value: MeticulousSocketService(hostname: 'unreachable.local'),
          ),
          ChangeNotifierProvider<GaggiMateService>.value(
            value: offlineGaggiMate(),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: tab),
        ),
      );

      // Reference: the button the gear in the Home tab also uses.
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: HeaderIconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      final reference = tester.getSize(find.byType(HeaderIconButton));
      expect(
        reference.width,
        lessThan(48),
        reason: 'more compact than the standard IconButton',
      );

      final tabs = <Widget, List<String>>{
        const HistoryTab(): ['Filter', 'Settings'],
        const BeansTab(): ['Search', 'Filter', 'Settings'],
      };
      for (final MapEntry(key: tab, value: tooltips) in tabs.entries) {
        await tester.pumpWidget(withProviders(tab));
        await settle(tester);
        for (final tooltip in tooltips) {
          final button = find
              .ancestor(
                of: find.byTooltip(tooltip),
                matching: find.byType(HeaderIconButton),
              )
              .first;
          expect(
            tester.getSize(button),
            reference,
            reason: '$tooltip in ${tab.runtimeType}',
          );
        }
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byTooltip('Filter'),
            matching: find.byIcon(Icons.tune),
          ),
        );
        expect(icon.size, isNull, reason: 'size comes from the button (22 px)');
        expect(IconTheme.of(tester.element(find.byIcon(Icons.tune))).size, 22);
      }
      await teardownApp(tester);
    },
  );
}
