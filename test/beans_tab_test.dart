import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/screens/beans/beans_tab.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

void main() {
  testWidgets('Beans tab: magnifier searches, filter sheet filters, no title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    await tester.runAsync(() async {
      await db.insertBean(
        BeansCompanion.insert(
          name: 'Kiambu',
          roaster: const Value('Bonanza'),
          country: const Value('Kenya'),
        ),
      );
      await db.insertBean(
        BeansCompanion.insert(
          name: 'Perfecto',
          roaster: const Value('Coffee Collective'),
          isBlend: const Value(true),
          country: const Value('Brazil'),
        ),
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          ChangeNotifierProvider<MeticulousSocketService>.value(
            value: MeticulousSocketService(hostname: 'unreachable.local'),
          ),
          // The same machine again under the shared interface: the pre-shot
          // card talks to it through that.
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.text('Beans'), findsNothing, reason: 'title is removed');
    expect(find.text('Kiambu'), findsOneWidget);
    expect(find.text('Perfecto'), findsOneWidget);

    // Search
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'brazil');
    await tester.pump();
    expect(find.text('Kiambu'), findsNothing);
    expect(find.text('Perfecto'), findsOneWidget);
    await tester.tap(find.byTooltip('Close search'));
    await tester.pump();
    expect(find.text('Kiambu'), findsOneWidget);

    // Filter: blends only
    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    expect(find.text('Show 2 beans'), findsOneWidget);
    await tester.tap(find.text('Blend'));
    await tester.pump();
    expect(find.text('Show 1 bean'), findsOneWidget);
    await tester.tap(find.text('Show 1 bean'));
    await tester.pumpAndSettle();
    expect(find.text('Kiambu'), findsNothing);
    expect(find.text('Perfecto'), findsOneWidget);
    expect(
      find.text('1'),
      findsOneWidget,
      reason: 'badge shows 1 active filter',
    );

    // No match -> "Clear filters"
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'kenya');
    await tester.pump();
    expect(find.text('No matching beans.'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pump();
    expect(find.text('Kiambu'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await db.close();
  });

  testWidgets('Beans tab: dividers only between roasters', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    await tester.runAsync(() async {
      // Two roasters, one of them with two beans — only this shows the
      // difference between "per bean" and "per roaster".
      await db.insertBean(
        BeansCompanion.insert(name: 'Kiambu', roaster: const Value('Bonanza')),
      );
      await db.insertBean(
        BeansCompanion.insert(
          name: 'Lekempti',
          roaster: const Value('Bonanza'),
        ),
      );
      await db.insertBean(
        BeansCompanion.insert(
          name: 'Perfecto',
          roaster: const Value('Coffee Collective'),
        ),
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.text('BONANZA'), findsOneWidget);
    expect(find.text('COFFEE COLLECTIVE'), findsOneWidget);

    // One line under All/Open/Frozen/Finished, then two roasters with one
    // line between them — and none between Kiambu and Lekempti, which both
    // belong to Bonanza.
    expect(find.byType(Divider), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await db.close();
  });

  testWidgets('Beans tab: All, Open, Frozen, Finished', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    await tester.runAsync(() async {
      await db.insertBean(BeansCompanion.insert(name: 'Kiambu'));
      await db.insertBean(
        BeansCompanion.insert(name: 'Gesha', isFrozen: const Value(true)),
      );
      await db.insertBean(
        BeansCompanion.insert(
          name: 'Lekempti',
          emptiedAt: Value(DateTime(2026, 10, 1)),
        ),
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
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
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    Future<void> pick(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('bean-status')),
          matching: find.text(label),
        ),
      );
      await tester.pump();
    }

    // All by default.
    for (final name in ['Kiambu', 'Gesha', 'Lekempti']) {
      expect(find.text(name), findsOneWidget);
    }
    await pick('Open');
    expect(find.text('Kiambu'), findsOneWidget);
    expect(find.text('Gesha'), findsNothing);
    expect(find.text('Lekempti'), findsNothing);
    await pick('Frozen');
    expect(find.text('Gesha'), findsOneWidget);
    expect(find.text('Kiambu'), findsNothing);
    await pick('Finished');
    expect(find.text('Lekempti'), findsOneWidget);
    expect(find.text('Gesha'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await db.close();
  });
}
