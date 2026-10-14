import 'package:beand/database/database.dart';
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/screens/beans/bean_stock.dart';
import 'package:beand/screens/beans/bean_widgets.dart';
import 'package:beand/screens/beans/beans_tab.dart';
import 'package:beand/screens/beans/freshness.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

// Bean list: long press on the photo = empty / back again, on the snowflake
// = thaw, each with undo.

void main() {
  late AppDatabase db;

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
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
          ChangeNotifierProvider<MeticulousSocketService>.value(
            value: MeticulousSocketService(hostname: 'unreachable.local'),
          ),
          ChangeNotifierProvider<EspressoMachine>.value(
            value: MeticulousSocketService(hostname: 'unreachable.local'),
          ),
          ChangeNotifierProvider<GaggiMateService>.value(
            value: offlineGaggiMate(),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: BeansTab()),
        ),
      ),
    );
    await settle(tester);
  }

  Future<Bean> beanNamed(WidgetTester tester, String name) async =>
      (await tester.runAsync(
        () async => (await db.allBeans()).firstWhere((b) => b.name == name),
      ))!;

  // Create the DB per test inside the test itself (streams from setUp do not
  // deliver) and close it at the end after tearing down the widgets.
  Future<void> open(WidgetTester tester) async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
  }

  // As in beans_tab_test: tear down the widgets and let drift's timer
  // (stream unsubscription) run while still inside the test.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('long press on the photo marks empty, undo reverts', (
    tester,
  ) async {
    await open(tester);
    await tester.runAsync(
      () => db.insertBean(BeansCompanion.insert(name: 'Kiambu')),
    );
    await pump(tester);

    await tester.longPress(find.byType(BeanThumbnail));
    await settle(tester);
    final emptied = await beanNamed(tester, 'Kiambu');
    expect(emptied.emptiedAt, isNotNull);
    expect(
      emptied.syncState,
      SyncState.pending,
      reason: 'goes to other devices',
    );
    expect(beanUsedUp(emptied, const {}, stock: false), isTrue);
    expect(find.text('Kiambu is used up'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect((await beanNamed(tester, 'Kiambu')).emptiedAt, isNull);

    // Empty again, then release via long press.
    await tester.longPress(find.byType(BeanThumbnail));
    await settle(tester);
    await tester.longPress(find.byType(BeanThumbnail));
    await settle(tester);
    expect((await beanNamed(tester, 'Kiambu')).emptiedAt, isNull);
    expect(find.text('Kiambu is back in stock'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('long press on the snowflake thaws, undo freezes', (
    tester,
  ) async {
    await open(tester);
    await tester.runAsync(
      () => db.insertBean(
        BeansCompanion.insert(
          name: 'Guji',
          roastDate: Value(DateTime(2026, 9, 1)),
          isFrozen: const Value(true),
        ),
      ),
    );
    await pump(tester);

    await tester.longPress(find.byIcon(Icons.ac_unit));
    await settle(tester);
    final thawed = await beanNamed(tester, 'Guji');
    expect(thawed.isFrozen, isFalse);
    expect(thawed.thawedDate, isNotNull);
    expect(find.byIcon(Icons.ac_unit), findsNothing);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    final again = await beanNamed(tester, 'Guji');
    expect(again.isFrozen, isTrue);
    expect(again.thawedDate, isNull);
    await dispose(tester);
  });

  testWidgets('long press on the freshness ring freezes, undo thaws', (
    tester,
  ) async {
    await open(tester);
    await tester.runAsync(
      () => db.insertBean(
        BeansCompanion.insert(
          name: 'Guji',
          roastDate: Value(DateTime.now().subtract(const Duration(days: 9))),
        ),
      ),
    );
    await pump(tester);
    expect(find.byIcon(Icons.ac_unit), findsNothing);

    await tester.longPress(find.byType(FreshnessRing));
    await settle(tester);
    expect((await beanNamed(tester, 'Guji')).isFrozen, isTrue);
    expect(find.byIcon(Icons.ac_unit), findsOneWidget);
    expect(find.text('Frozen – freshness ring paused'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect((await beanNamed(tester, 'Guji')).isFrozen, isFalse);
    expect(find.byType(FreshnessRing), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('undo snackbar disappears by itself after a few seconds', (
    tester,
  ) async {
    await open(tester);
    await tester.runAsync(
      () => db.insertBean(BeansCompanion.insert(name: 'Kiambu')),
    );
    await pump(tester);
    await tester.longPress(find.byType(BeanThumbnail));
    await settle(tester);
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Undo'), findsNothing);
    await dispose(tester);
  });

  testWidgets('short tap on the photo still opens the bean', (tester) async {
    await open(tester);
    await tester.runAsync(
      () => db.insertBean(BeansCompanion.insert(name: 'Kiambu')),
    );
    await pump(tester);
    await tester.tap(find.byType(BeanThumbnail));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect((await beanNamed(tester, 'Kiambu')).emptiedAt, isNull);
    expect(find.byType(BeansTab), findsNothing, reason: 'form open');
    await dispose(tester);
  });
}

// Database streams need real time.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pump();
  // SnackBar: the previous one must leave before the new one comes in.
  await tester.pump(const Duration(milliseconds: 800));
}
