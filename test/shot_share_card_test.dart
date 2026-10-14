import 'package:beand/database/database.dart';
import 'package:beand/models/taste_profile.dart';
import 'package:beand/screens/history/shot_share_screen.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Shot image for sharing (variant C): everything on it, nothing overflows;
// the note only on request.

void main() {
  late AppDatabase db;
  late ShotEntry entry;
  late List<ShotReading> readings;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  // Default surface is only 600 tall, the card 640.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  tearDown(() => db.close());

  Future<void> load(WidgetTester tester, {bool full = true}) =>
      tester.runAsync(() async {
        final bean = await db.insertBean(
          BeansCompanion.insert(
            name: 'Ethiopia Guji Hambela',
            roaster: const Value('Bonanza'),
            processing: const Value('Washed'),
          ),
        );
        final id = await db.insertShotWithReadings(
          ShotsCompanion.insert(
            timestamp: DateTime(2026, 10, 13, 8, 42),
            beanId: Value(full ? bean.id : null),
            profileName: const Value('Londinium'),
            profileTemp: const Value(92),
            doseGrams: const Value(18),
            finalWeight: const Value(40.2),
            durationMs: const Value(28400),
            grindSize: const Value('2.4'),
          ),
          [
            for (var i = 0; i < 285; i++)
              (id) => ShotReadingsCompanion.insert(
                shotId: id,
                timeMs: i * 100,
                pressure: Value(i < 90 ? 3.0 : 9.0),
                flow: Value(i < 90 ? 1.0 : 2.0),
                weight: Value(i * 0.14),
                stage: Value(i < 90 ? 'Preinfusion' : 'Extraction'),
              ),
          ],
        );
        if (full) {
          await db.setShotRating(id, 4);
          await db.setShotTaste(id, TasteAxis.sweetness, 3);
          await db.setShotTaste(id, TasteAxis.bitter, 1);
          await db.setShotNotes(id, 'Sehr süß, nächstes Mal feiner.');
        }
        entry = (await db.watchShotEntry(id).first)!;
        readings = await db.readingsFor(id);
      });

  Widget card({bool notes = false}) => MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Center(
        child: ShotShareCard(
          entry: entry,
          readings: readings,
          photo: null,
          includeNotes: notes,
        ),
      ),
    ),
  );

  testWidgets('everything on it, values labeled individually', (tester) async {
    tall(tester);
    await load(tester);
    await tester.pumpWidget(card());
    expect(tester.takeException(), isNull);
    expect(find.text('Ethiopia Guji Hambela'), findsOneWidget);
    expect(find.text('Bonanza · Washed'), findsOneWidget);
    expect(find.text('13 Oct 2026 · 08:42'), findsOneWidget);
    for (final label in ['TIME', 'YIELD', 'TEMP', 'DOSE', 'RATIO', 'GRIND']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Londinium'), findsOneWidget);
    expect(find.text('92 °C'), findsOneWidget);
    expect(find.text('9.0 bar'), findsNothing, reason: 'no peak pressure');
    expect(
      find.text('Meticulous'),
      findsOneWidget,
      reason: 'next to the profile',
    );
    expect(find.text('Espresso'), findsNothing);
    expect(
      find.textContaining('Preinfusion'),
      findsNothing,
      reason: 'no stage names',
    );
    expect(find.text('Sweet'), findsOneWidget);
    expect(find.text('Bitter'), findsOneWidget);
    expect(find.text('Body'), findsNothing, reason: 'only rated axes');
    expect(find.textContaining('Sehr süß'), findsNothing);
    expect(tester.getSize(find.byType(ShotShareCard)), const Size(360, 640));
  });

  testWidgets('note only on request', (tester) async {
    tall(tester);
    await load(tester);
    await tester.pumpWidget(card(notes: true));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Sehr süß'), findsOneWidget);
  });

  testWidgets('without bean, rating and note: no gap', (tester) async {
    tall(tester);
    await load(tester, full: false);
    await tester.pumpWidget(card(notes: true));
    expect(tester.takeException(), isNull);
    expect(find.text('Londinium'), findsWidgets, reason: 'title = profile');
    expect(find.text('★★★★★'), findsNothing);
  });
}
