import 'package:beand/database/database.dart';
import 'package:beand/models/grind_scale.dart';
import 'package:beand/screens/history/history_widgets.dart';
import 'package:beand/screens/live/grind_from_zero.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Settings → History "Grind from zero": the same dial number means another
// grind after re-zeroing, so the list and the comparison can also show how
// far each shot stood from the zero point of its day.
void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<Shot> shot({String? grind, double? zero, String? marker}) async {
    final id = await db
        .into(db.shots)
        .insert(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 10, 21, 9),
            grindSize: Value(grind),
            grindZero: Value(zero),
            grindMarker: Value(marker),
          ),
        );
    return (db.select(db.shots)..where((s) => s.id.equals(id))).getSingle();
  }

  test('same dial, different zero point: different from zero', () async {
    final before = await shot(grind: '3.2', zero: 0);
    final after = await shot(grind: '3.2', zero: 0.5);
    expect(shotGrindFromZero(before), 3.2);
    expect(shotGrindFromZero(after), closeTo(2.7, 1e-9));
    expect(fromZeroText(2.7), '+2.7');
    expect(fromZeroText(-0.3), '-0.3');
  });

  test('older shots without a zero point have none', () async {
    expect(shotGrindFromZero(await shot(grind: '3.2')), isNull);
    expect(shotGrindFromZero(await shot(zero: 0.5)), isNull);
  });

  test('with marks the reading goes on the shared scale first', () async {
    const scale = GrindScale(
      step: 0.1,
      max: 9,
      markers: [
        GrindMarker(name: 'Espresso', color: 0xFF4CAF50),
        GrindMarker(name: 'Soup', color: 0xFFE53935, offset: 6.8),
      ],
    );
    final s = await shot(grind: '2.2', zero: 0.2, marker: 'Soup');
    // Red 2.2 sits at green 9.0; from a zero point of 0.2: +8.8.
    expect(shotGrindFromZero(s, scale), closeTo(8.8, 1e-9));
  });

  testWidgets('history row: only with the setting on', (tester) async {
    late Shot s;
    await tester.runAsync(() async {
      s = await shot(grind: '3.2', zero: 0.5);
    });
    final settings = AppSettings();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettings>.value(
        value: settings,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ShotRow(entry: ShotEntry(s, null), onTap: () {}),
          ),
        ),
      ),
    );
    final row = find.textContaining('3.2', findRichText: true);
    expect(row, findsWidgets);
    expect(find.textContaining('(+2.7)', findRichText: true), findsNothing);

    await tester.runAsync(() => settings.setShowGrindFromZero(true));
    await tester.pump();
    expect(
      find.textContaining('3.2 (+2.7)', findRichText: true),
      findsOneWidget,
    );
  });
}
