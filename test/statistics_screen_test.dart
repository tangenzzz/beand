import 'dart:convert';

import 'package:beand/database/database.dart';
import 'package:beand/screens/settings/statistics_screen.dart';
import 'package:beand/models/gear.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/gear_store.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the three tabs with real numbers', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.runAsync(() async {
      final bean = await db.insertBean(
        BeansCompanion.insert(
          name: 'Kiambu AA',
          roaster: const Value('Square Mile'),
          country: const Value('Kenya'),
          processing: const Value('Washed'),
        ),
      );
      final now = DateTime.now();
      for (var i = 0; i < 3; i++) {
        await db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: now.subtract(Duration(days: i, hours: 1)),
            machine: const Value('meticulous'),
            beanId: Value(bean.id),
            profileName: Value(i == 0 ? 'Turbo' : 'Classic'),
            doseGrams: const Value(18),
            finalWeight: const Value(36),
            durationMs: Value(25000 + i * 5000),
          ),
          [],
        );
      }
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const StatisticsScreen(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.text('OVERVIEW'), findsOneWidget);
    expect(find.text('3'), findsWidgets); // shots
    expect(find.text('RECORDS'), findsOneWidget);
    expect(find.text('25.0 s'), findsOneWidget);
    // Earliest and latest coffee are records now.
    expect(find.text('Earliest coffee'), findsOneWidget);
    expect(find.text('Latest coffee'), findsOneWidget);

    // The stacked bar really has height (it once rendered only the legend).
    final bar = find.descendant(
      of: find.byType(ClipRRect),
      matching: find.byType(ColoredBox),
    );
    expect(tester.getSize(bar.first).height, 10);
    expect(find.byIcon(Icons.info_outline), findsNothing);
    // Averages carry a ⌀; the bag numbers live in the overview.
    expect(find.text('BAG LASTS'), findsOneWidget);
    expect(find.text('PER DAY'), findsOneWidget);
    expect(find.textContaining('⌀', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Beans').first);
    await tester.pump();
    expect(find.text('Square Mile'), findsOneWidget);
    // Countries and varieties lead the Beans tab.
    expect(find.text('COFFEE COUNTRIES'), findsOneWidget);
    expect(find.textContaining('profiles unlocked'), findsNothing);
    expect(find.textContaining('Next to try'), findsNothing);
    expect(find.text('BAGS'), findsNothing);
    expect(find.text('VARIETIES'), findsOneWidget);

    // A country opens its sheet with the unlocked profile.
    await tester.tap(find.text('Kenya').first);
    await tester.pumpAndSettle();
    expect(find.text('PROFILE'), findsOneWidget);
    // Overline in the accent above the title, roaster above the bean.
    expect(find.text('AFRICA'), findsOneWidget);
    expect(find.text('SQUARE MILE'), findsOneWidget);
    expect(find.textContaining('UNLOCKED'), findsOneWidget);
    expect(find.textContaining('blackcurrant'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profiles').first);
    await tester.pump();
    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('Turbo'), findsOneWidget);
  });

  testWidgets('the chosen period survives an app restart', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final settings = AppSettings();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const StatisticsScreen(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    await tester.tap(find.text('Year'));
    await tester.pump();
    expect(settings.statisticsPeriod, 'year');
    expect(find.text('last 12 months'), findsOneWidget);

    // A fresh start reads it back.
    final reloaded = await tester.runAsync(AppSettings.load);
    expect(reloaded!.statisticsPeriod, 'year');
  });

  testWidgets('a new shot shows up while the page stays open', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late Bean bean;
    await tester.runAsync(() async {
      bean = await db.insertBean(
        BeansCompanion.insert(
          name: 'Priced',
          cost: const Value(20),
          weightGrams: const Value(250),
        ),
      );
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(
            value: AppSettings(statisticsPeriod: 'all'),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const StatisticsScreen(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('–'), findsWidgets); // no value brewed yet

    // 50 g × 20 € / 250 g = 4 €.
    await tester.runAsync(
      () => db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime.now(),
          machine: const Value('meticulous'),
          beanId: Value(bean.id),
          doseGrams: const Value(50),
        ),
        [],
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.textContaining('4'), findsWidgets);
    expect(find.text('€ 4'), findsOneWidget);
  });

  testWidgets('Gear: grinders by coffee ground, filters with stock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const grinder = Gear(
      id: 'g1',
      type: GearType.grinder,
      brand: 'Zerno',
      model: 'Z1',
      specs: {'activeBurr': 'SSP HU'},
    );
    const filter = Gear(
      id: 'f1',
      type: GearType.filter,
      brand: 'Sibarist',
      model: 'Fast',
      stock: 77,
    );
    SharedPreferences.setMockInitialValues({
      GearStore.gearPrefKey: jsonEncode([
        grinder.toJson(),
        filter.toJson(),
        const Gear(
          id: 'g2',
          type: GearType.grinder,
          brand: 'Niche',
          model: 'Zero',
        ).toJson(),
      ]),
      GearStore.chainsPrefKey: jsonEncode([
        const BrewChain(
          id: 'c1',
          name: 'Light roast',
          gearIds: ['g1', 'f1'],
        ).toJson(),
      ]),
    });
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late GearStore store;
    final settings = AppSettings(statisticsPeriod: 'all');
    await tester.runAsync(() async {
      store = await GearStore.load();
      final bean = await db.insertBean(
        BeansCompanion.insert(
          name: 'Guji Hambela',
          roaster: const Value('April'),
        ),
      );
      for (var i = 0; i < 2; i++) {
        await db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: DateTime.now().subtract(Duration(days: i)),
            machine: const Value('meticulous'),
            doseGrams: const Value(18),
            grinder: const Value('Z1'),
            burrs: const Value('SSP HU'),
            gearIds: const Value('g1,f1'),
            brewChainId: const Value('c1'),
            beanId: Value(bean.id),
            grindSize: const Value('2.5'),
            durationMs: const Value(28000),
          ),
          [],
        );
      }
      // The same bean on the other grinder.
      await db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime.now(),
          machine: const Value('meticulous'),
          doseGrams: const Value(18),
          gearIds: const Value('g2'),
          beanId: Value(bean.id),
          grindSize: const Value('14'),
          durationMs: const Value(32000),
        ),
        [],
      );
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: settings),
          ChangeNotifierProvider<GearStore>.value(value: store),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const StatisticsScreen(),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.tap(find.text('Gear'));
    await tester.pump();

    expect(find.text('GRINDERS'), findsOneWidget);
    expect(find.text('36 g'), findsOneWidget);
    expect(find.text('FILTERS'), findsOneWidget);
    expect(find.text('used 2 · 77 left in stock'), findsOneWidget);
    expect(find.text('LIGHT ROAST'), findsNothing);
    expect(find.text('Light roast'), findsOneWidget);
    // No ratings on gear.
    expect(find.textContaining('★'), findsNothing);

    expect(find.text('NEW'), findsNothing);
    expect(find.text('coffee through'), findsNothing);
    expect(find.text('GRINDER VS. GRINDER'), findsOneWidget);
    // The rules sit behind the ⓘ at the heading.
    await tester.tap(
      find.descendant(
        of: find
            .ancestor(
              of: find.text('GRINDER VS. GRINDER'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byIcon(Icons.info_outline),
      ),
    );
    await tester.pump();
    expect(find.textContaining('same profile'), findsOneWidget);
    await tester.tap(find.text('GRINDER VS. GRINDER'));
    await tester.pump();
    expect(find.text('28 s'), findsOneWidget);
    expect(find.text('32 s'), findsOneWidget);

    await tester.tap(find.text('Z1').first);
    await tester.pumpAndSettle();
    expect(find.text('BURRS'), findsOneWidget);
    expect(find.text('SSP HU'), findsOneWidget);

    // Beans ground folds, and stays folded for the next sheet.
    // (The bean also stands in the grinder comparison behind the sheet.)
    Finder inSheet(String text) => find.descendant(
      of: find.byType(DraggableScrollableSheet),
      matching: find.text(text),
    );
    expect(inSheet('Guji Hambela'), findsOneWidget);
    await tester.tap(find.text('BEANS GROUND'));
    await tester.pumpAndSettle();
    expect(inSheet('Guji Hambela'), findsNothing);
    expect(settings.gearBeansOpen, isFalse);
  });
}
