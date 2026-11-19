import 'package:beand/database/database.dart';
import 'package:beand/screens/settings/statistics_screen.dart';
import 'package:beand/services/app_settings.dart';
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
    expect(find.text('HABITS'), findsOneWidget);

    // The stacked bar really has height (it once rendered only the legend).
    final bar = find.descendant(
      of: find.byType(ClipRRect),
      matching: find.byType(ColoredBox),
    );
    expect(tester.getSize(bar.first).height, 10);
    expect(find.text('Value from 0 of 3 shots'), findsOneWidget);

    await tester.tap(find.text('Beans').first);
    await tester.pump();
    expect(find.text('Square Mile'), findsOneWidget);
    expect(find.text('Kenya 100 %'), findsOneWidget);

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
}
