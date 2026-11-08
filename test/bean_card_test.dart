import 'package:beand/database/database.dart';
import 'package:beand/models/coffee.dart';
import 'package:beand/screens/beans/bean_form_screen.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/sync/records/bean_codec.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

BeansCompanion _bag(
  String name, {
  String? roaster = 'Kaffeelix',
  DateTime? opened,
  String? country,
  double? weight,
}) => BeansCompanion.insert(
  name: name,
  roaster: Value(roaster),
  openedAt: Value(opened),
  country: Value(country),
  weightGrams: Value(weight),
);

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test('picker subtitle: sealed, and the roast date only between twins', () {
    Bean bag(
      int id, {
      String name = 'Guji',
      DateTime? opened,
      DateTime? roast,
    }) => Bean(
      id: id,
      name: name,
      roaster: 'Friedhats',
      isBlend: false,
      isFrozen: false,
      createdAt: DateTime(2026),
      updatedAt: 0,
      syncId: 'bag-$id',
      syncState: 'synced',
      deleted: false,
      frozenDays: 0,
      openedAt: opened,
      roastDate: roast,
    );
    final open = bag(1, opened: DateTime(2026), roast: DateTime(2026, 10, 12));
    final sealed = bag(2, roast: DateTime(2026, 11, 2));
    final other = bag(3, name: 'Kiambu', opened: DateTime(2026));

    expect(bagSubtitle(other, [open, sealed, other]), 'Friedhats');
    expect(bagSubtitle(sealed, [sealed, other]), 'Friedhats · sealed');
    expect(
      bagSubtitle(open, [open, sealed, other]),
      'Friedhats · roasted 12 Oct',
    );
  });

  group('coffee logic', () {
    test('bags group by name and roaster, ignoring case and spaces', () async {
      final a = await db.insertBean(_bag('Matão', opened: DateTime(2026)));
      await db.insertBean(_bag(' matão ', roaster: 'KAFFEELIX'));
      await db.insertBean(_bag('Other'));
      final coffees = groupCoffees(await db.allBeans(), const {}, stock: false);
      expect(coffees, hasLength(2));
      final c = coffees.firstWhere((c) => c.key == coffeeKey(a));
      expect(c.bags, hasLength(2));
      expect(c.lead.id, a.id, reason: 'the open bag stands for the coffee');
      expect(c.moreBags, hasLength(1));
    });

    test('a coffee id keeps a new harvest apart', () async {
      await db.insertBean(_bag('Matão'));
      await db.insertBean(
        _bag('Matão').copyWith(coffeeId: const Value('harvest-2')),
      );
      expect(
        groupCoffees(await db.allBeans(), const {}, stock: false),
        hasLength(2),
      );
    });

    test('state comes from the fields', () async {
      final sealed = await db.insertBean(_bag('A'));
      expect(bagState(sealed, const {}, stock: false), BagState.sealed);
      final open = await db.updateBean(
        sealed.id,
        BeansCompanion(openedAt: Value(DateTime(2026))),
      );
      expect(bagState(open, const {}, stock: false), BagState.open);
      final frozen = await db.updateBean(
        sealed.id,
        const BeansCompanion(isFrozen: Value(true)),
      );
      expect(bagState(frozen, const {}, stock: false), BagState.frozen);
      final empty = await db.updateBean(
        sealed.id,
        BeansCompanion(emptiedAt: Value(DateTime(2026))),
      );
      expect(bagState(empty, const {}, stock: false), BagState.empty);
    });

    test('the picker offers open bags, a sealed one only without', () async {
      final open = await db.insertBean(_bag('A', opened: DateTime(2026)));
      await db.insertBean(_bag('A'));
      final onlySealed = await db.insertBean(_bag('B'));
      await db.insertBean(_bag('C').copyWith(isFrozen: const Value(true)));
      final ids = pickableBags(
        await db.allBeans(),
        const {},
        stock: false,
      ).map((b) => b.id);
      expect(ids, unorderedEquals([open.id, onlySealed.id]));
    });

    test('details of a coffee come from all its bags', () async {
      await db.insertBean(_bag('A', country: 'Brazil'));
      await db.insertBean(_bag('A'));
      final c = groupCoffees(
        await db.allBeans(),
        const {},
        stock: false,
      ).single;
      expect(c.details.country, 'Brazil');
    });

    test('a shot opens a sealed bag, an opened one keeps its date', () async {
      final bag = await db.insertBean(_bag('A'));
      await db.insertShotWithReadings(
        ShotsCompanion.insert(timestamp: DateTime(2026), beanId: Value(bag.id)),
        const [],
      );
      final opened = (await db.allBeans()).single.openedAt;
      expect(opened, isNotNull);
      await db.insertShotWithReadings(
        ShotsCompanion.insert(timestamp: DateTime(2026), beanId: Value(bag.id)),
        const [],
      );
      expect((await db.allBeans()).single.openedAt, opened);
    });

    test(
      'sync carries the new fields and reads records without them',
      () async {
        final bag = await db.insertBean(
          _bag('A', opened: DateTime(2026)).copyWith(
            region: const Value('Mococa'),
            altitude: const Value('800 m'),
            coffeeId: const Value('x'),
          ),
        );
        final data = beanToSyncData(bag);
        final back = beanFromSyncData(data);
        expect(back.region.value, 'Mococa');
        expect(back.altitude.value, '800 m');
        expect(back.coffeeId.value, 'x');
        expect(back.openedAt.value, DateTime(2026));
        final old = beanFromSyncData({'name': 'Old'});
        expect(old.openedAt.present, isFalse);
        expect(old.coffeeId.present, isFalse);
      },
    );
  });

  group('the card', () {
    Future<void> show(WidgetTester tester, Bean? bean) async {
      tester.view.physicalSize = const Size(420, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
            ChangeNotifierProvider<AiSettings>.value(
              value: AiSettings(keyStore: InMemoryAiKeyStore()),
            ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<Bean>(
                      builder: (_) => BeanFormScreen(bean: bean),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    testWidgets('a saved coffee opens for reading, the pencil starts editing', (
      tester,
    ) async {
      late Bean bag;
      await tester.runAsync(() async {
        bag = await db.insertBean(
          _bag('Matão', opened: DateTime(2026), country: 'Brazil'),
        );
      });
      await show(tester, bag);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.text('Brazil'), findsOneWidget);
      expect(
        find.text('Variety'),
        findsNothing,
        reason: 'empty fields are out',
      );

      await tester.tap(find.byTooltip('Edit'));
      await settle(tester);
      expect(find.text('Save'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('Variety'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a changed field goes on all bags, the rest stays', (
      tester,
    ) async {
      late Bean bag;
      await tester.runAsync(() async {
        bag = await db.insertBean(_bag('Matão', country: 'Brazil'));
        await db.insertBean(_bag('Matão', country: 'Older value'));
      });
      await show(tester, bag);
      await tester.tap(find.byTooltip('Edit'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Matão'),
        'New name',
      );
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);
      final rows = await tester.runAsync(db.allBeans);
      expect(rows!.map((b) => b.name), everyElement('New name'));
      expect(rows.map((b) => b.country).toSet(), hasLength(2));
      expect(find.text('Save'), findsNothing, reason: 'back to reading');
      await finish(tester);
    });

    testWidgets('the status symbols work while reading', (tester) async {
      late Bean bag;
      await tester.runAsync(() async => bag = await db.insertBean(_bag('A')));
      await show(tester, bag);
      expect(find.byTooltip('Edit'), findsOneWidget);

      Future<Bean> tap(String label) async {
        await tester.tap(find.text(label).first);
        await settle(tester);
        return (await tester.runAsync(db.allBeans))!.single;
      }

      final opened = await tap('Open');
      expect(opened.openedAt, isNotNull);
      final frozen = await tap('Frozen');
      expect(frozen.isFrozen, isTrue);
      expect(frozen.openedAt, isNotNull, reason: 'freezing keeps it opened');
      final thawed = await tap('Frozen');
      expect(thawed.isFrozen, isFalse, reason: 'again: back to what it was');
      final empty = await tap('Empty');
      expect(empty.emptiedAt, isNotNull);
      final sealed = await tap('Sealed');
      expect(sealed.openedAt, isNull);
      expect(sealed.emptiedAt, isNull);
      await finish(tester);
    });

    testWidgets('the bag tile fits on a phone, reading and editing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late Bean bag;
      await tester.runAsync(() async {
        bag = await db.insertBean(
          _bag('A', opened: DateTime(2026), weight: 1000),
        );
      });
      await show(tester, bag);
      expect(tester.takeException(), isNull);
      expect(find.text('Left'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });

    testWidgets('a new bag can be frozen, and the date can be changed', (
      tester,
    ) async {
      await show(tester, null);
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), 'Cold');
      await settle(tester);
      await tester.tap(find.text('Frozen').first);
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);
      final rows = await tester.runAsync(db.allBeans);
      expect(rows!.single.isFrozen, isTrue);
      expect(rows.single.frozenDate, isNotNull);
      await finish(tester);
    });

    testWidgets('the timeline opens and lists the dates in order', (
      tester,
    ) async {
      late Bean bag;
      await tester.runAsync(() async {
        bag = await db.insertBean(
          _bag('A', opened: DateTime(2026, 3, 5)).copyWith(
            roastDate: Value(DateTime(2026, 2, 1)),
            frozenDate: Value(DateTime(2026, 2, 10)),
            thawedDate: Value(DateTime(2026, 2, 20)),
          ),
        );
      });
      await show(tester, bag);
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Roasted'), findsOneWidget, reason: 'only the fact');
      await tester.tap(find.text('Timeline'));
      await settle(tester);
      final x = [
        for (final t in ['Frozen', 'Thawed', 'Opened'])
          tester.getCenter(find.text(t).last).dx,
      ];
      expect(find.text('Roasted'), findsNWidgets(2));
      expect(x[0], lessThan(x[1]));
      expect(x[1], lessThan(x[2]));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Edit'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });

    testWidgets('a bag with shots cannot go back to sealed', (tester) async {
      late Bean bag;
      await tester.runAsync(() async {
        bag = await db.insertBean(
          _bag('A', opened: DateTime(2026), weight: 250),
        );
        await db
            .into(db.shots)
            .insert(
              ShotsCompanion.insert(
                timestamp: DateTime(2026),
                beanId: Value(bag.id),
                doseGrams: const Value(18),
              ),
            );
      });
      await show(tester, bag);
      await tester.tap(find.text('Sealed'));
      await settle(tester);
      final rows = await tester.runAsync(db.allBeans);
      expect(rows!.single.openedAt, isNotNull);
      await finish(tester);
    });

    testWidgets('Add bag fills in on the card and copies the coffee', (
      tester,
    ) async {
      late Bean bag;
      await tester.runAsync(() async {
        bag = await db.insertBean(
          _bag('A', opened: DateTime(2026), country: 'Brazil', weight: 250),
        );
      });
      await show(tester, bag);
      tester.view.physicalSize = const Size(420, 800);
      await settle(tester);
      await tester.tap(find.byTooltip('Add bag'));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(list.position.pixels, closeTo(list.position.maxScrollExtent, 1));
      expect(find.text('Save'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await settle(tester);
      final rows = await tester.runAsync(db.allBeans);
      expect(rows, hasLength(2));
      final added = rows!.firstWhere((b) => b.id != bag.id);
      expect(added.country, 'Brazil');
      expect(added.weightGrams, 250);
      expect(added.openedAt, isNull, reason: 'a new bag is sealed');
      await finish(tester);
    });

    testWidgets('same name: another bag, or a new coffee', (tester) async {
      await tester.runAsync(
        () async => db.insertBean(_bag('A', roaster: null)),
      );
      await show(tester, null);
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), 'A');
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('"A" already exists'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'New coffee'));
      await settle(tester);
      final rows = await tester.runAsync(db.allBeans);
      expect(rows, hasLength(2));
      expect(rows!.where((b) => b.coffeeId != null), hasLength(1));
      await finish(tester);
    });
  });
}

// Real time for the database, the test's clock pumped in between.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}
