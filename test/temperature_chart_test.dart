import 'package:beand/database/database.dart';
import 'package:beand/screens/history/shot_detail_screen.dart';
import 'package:beand/screens/history/temperature_chart.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Future<int> shotWith(AppDatabase db, {required bool decent}) =>
      db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 11, 2, 9),
          machine: const Value('meticulous'),
        ),
        [
          for (var i = 0; i < 20; i++)
            (id) => ShotReadingsCompanion.insert(
              shotId: id,
              timeMs: i * 1000,
              pressure: Value(i / 2),
              flow: const Value(2),
              weight: Value(i.toDouble()),
              barUp: Value(90 + i / 10),
              tempMix: Value(decent ? 92 + i / 40 : null),
              tempGoal: Value(decent ? 93.0 : null),
            ),
        ],
      );

  Widget app(AppDatabase db, int id) => MultiProvider(
    providers: [
      Provider<AppDatabase>.value(value: db),
      ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
      ChangeNotifierProvider<AiSettings>.value(
        value: AiSettings(keyStore: InMemoryAiKeyStore()),
      ),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: ShotDetailScreen(shotId: id),
    ),
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  testWidgets('Decent temperatures: folded chart right above Compare', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final id = (await tester.runAsync(() => shotWith(db, decent: true)))!;
    await tester.pumpWidget(app(db, id));
    await settle(tester);

    // Folded: only the row, no chart yet.
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.byType(TemperatureChart), findsNothing);
    expect(
      tester.getTopLeft(find.text('Temperature')).dy,
      lessThan(tester.getTopLeft(find.text('Compare')).dy),
    );

    await tester.tap(find.text('Temperature'));
    await tester.pump();
    expect(find.byType(TemperatureChart), findsOneWidget);
    // Values at the cursor (end of the shot).
    expect(find.text('BASKET'), findsOneWidget);
    expect(find.text('MIX'), findsOneWidget);
    expect(find.text('GOAL'), findsOneWidget);
    expect(find.textContaining('93.0 °C', findRichText: true), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('no Decent temperatures, no temperature row', (tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final id = (await tester.runAsync(() => shotWith(db, decent: false)))!;
    await tester.pumpWidget(app(db, id));
    await settle(tester);
    expect(find.text('Temperature'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
