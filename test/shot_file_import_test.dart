import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beand/database/database.dart';
import 'package:beand/models/shot_file_import.dart';
import 'package:beand/screens/history/new_shot_screen.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));

// visualizer.coffee download: numbers partly as strings, as served.
const visualizerShot = '''
{
  "profile_title": "Blooming Espresso",
  "start_time": "2026-10-30T08:15:00.000Z",
  "bean_weight": "18.0",
  "drink_weight": "40.2",
  "grinder_setting": "2.4",
  "timeframe": ["0.0", "0.25", "0.5", "30.1"],
  "data": {
    "espresso_pressure": ["0.0", "2.1", "6.0", "8.8"],
    "espresso_flow": [0, 1.2, 2.0, 1.8],
    "espresso_weight": [0, 0, 0.4, 39.8],
    "espresso_flow_weight": [0, 0, 0.6, 1.9],
    "espresso_temperature_basket": [92.1, 92.4, 92.6, 92.0]
  }
}
''';

void main() {
  test('GaggiMate .slog: curve, profile, the machine', () {
    final shot = parseShotFile(
      File('test/fixtures/gaggimate_shot_000002.slog').readAsBytesSync(),
    );
    expect(shot.machine, 'gaggimate');
    expect(shot.format, 'GaggiMate shot');
    expect(shot.readings, isNotEmpty);
    expect(shot.durationMs, greaterThan(0));
  });

  test('Meticulous history entry (also wrapped in "history")', () {
    final entry = File('test/fixtures/history_entry_bailey.json')
        .readAsStringSync();
    for (final json in [entry, '{"history": [$entry]}']) {
      final shot = parseShotFile(text(json));
      expect(shot.machine, 'meticulous');
      expect(shot.externalId, 'c638dc37-dc02-4f63-ab03-92001c201757');
      expect(shot.profileName, 'Bailey - PSPH / Soup');
      expect(shot.readings, hasLength(40));
    }
  });

  test('visualizer.coffee: series in seconds, numbers as strings', () {
    final shot = parseShotFile(text(visualizerShot));
    expect(shot.machine, isNull); // the user's brew method stays
    expect(shot.format, 'visualizer.coffee shot');
    expect(shot.profileName, 'Blooming Espresso');
    expect(shot.doseGrams, 18.0);
    expect(shot.finalWeight, 40.2);
    expect(shot.grind, '2.4');
    expect(shot.durationMs, 30100);
    expect(shot.timestamp, DateTime.utc(2026, 10, 30, 8, 15).toLocal());
    expect(shot.readings, hasLength(4));
    final last = shot.readings.last(1);
    expect(last.timeMs.value, 30100);
    expect(last.pressure.value, 8.8);
    expect(last.weight.value, 39.8);
    expect(last.gravimetricFlow.value, 1.9);
    expect(last.barUp.value, 92.0);
  });

  test('Decent JSON v2 and the Tcl .shot file', () {
    final json = parseShotFile(
      text('''
{"version": 2, "timestamp": 1761811200,
 "elapsed": [0, 0.5, 28.0],
 "pressure": {"pressure": [0, 3.0, 8.5]},
 "flow": {"flow": [0, 1.0, 2.1], "by_weight": [0, 0.2, 1.8]},
 "totals": {"weight": [0, 0.3, 36.0]},
 "temperature": {"basket": [91, 92, 92]},
 "profile": {"title": "Default"},
 "meta": {"in": 18, "out": 36.5, "grinder": {"setting": "11"}}}
'''),
    );
    expect(json.format, 'Decent shot');
    expect(json.profileName, 'Default');
    expect(json.doseGrams, 18);
    expect(json.finalWeight, 36.5);
    expect(json.grind, '11');
    expect(json.durationMs, 28000);
    expect(json.readings, hasLength(3));

    final tcl = parseShotFile(
      text('''
clock 1761811200
espresso_elapsed {0.0 0.25 27.5}
espresso_pressure {0.0 2.0 9.0}
espresso_weight {0.0 0.0 35.1}
espresso_flow {0.0 1.0 2.0}
espresso_flow_weight {0.0 0.0 1.7}
espresso_temperature_basket {90.0 91.5 92.0}
settings {
\tprofile_title {Londinium}
\tdrink_weight 36.0
\tgrinder_dose_weight 18.0
\tgrinder_setting 2.0
}
'''),
    );
    expect(tcl.format, 'Decent shot');
    expect(tcl.profileName, 'Londinium');
    expect(tcl.doseGrams, 18.0);
    expect(tcl.finalWeight, 36.0);
    expect(tcl.grind, '2.0');
    expect(tcl.durationMs, 27500);
    expect(tcl.timestamp, DateTime.fromMillisecondsSinceEpoch(1761811200000));
    expect(tcl.readings.last(1).pressure.value, 9.0);
  });

  test('anything else is refused with a readable message', () {
    expect(
      () => parseShotFile(text('hello')),
      throwsA(isA<ShotFileException>()),
    );
    expect(
      () => parseShotFile(text('{"foo": 1}')),
      throwsA(isA<ShotFileException>()),
    );
  });

  testWidgets('New shot: a file fills the form, Save stores shot and curve', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    int? savedId;
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
          home: NewShotScreen(
            pickFile: () async => text(visualizerShot),
            onSaved: (_, id) => savedId = id,
          ),
        ),
      ),
    );

    // Every brew method is on offer.
    await tester.tap(find.text('Brew method'));
    await tester.pumpAndSettle();
    for (final label in ['Meticulous', 'Pour Over', 'GaggiMate']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('GaggiMate').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Load shot file'));
    await tester.pumpAndSettle();
    expect(find.text('visualizer.coffee shot · 4 points'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Blooming Espresso'), findsOneWidget);
    expect(find.widgetWithText(TextField, '40.2'), findsOneWidget);
    expect(find.widgetWithText(TextField, '30.1'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    final shot = (await tester.runAsync(() => db.select(db.shots).get()))!
        .single;
    expect(shot.machine, 'gaggimate'); // the file didn't say, the choice stays
    expect(shot.profileName, 'Blooming Espresso');
    expect(shot.doseGrams, 18.0);
    expect(shot.finalWeight, 40.2);
    expect(shot.durationMs, 30100);
    expect(shot.grindSize, '2.4');
    expect(shot.externalId, isNull);
    final readings = (await tester.runAsync(
      () => db.select(db.shotReadings).get(),
    ))!;
    expect(readings, hasLength(4));
    // Then on to the shot (detail) with the new ID.
    expect(savedId, shot.id);
  });
}
