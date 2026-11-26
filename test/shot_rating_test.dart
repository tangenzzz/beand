import 'package:beand/database/database.dart';
import 'package:beand/models/shot_rating.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:beand/widgets/taste_rater.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RateAxis', () {
    test('order: first sip, mouth, aftertaste, extraction last', () {
      expect(RateAxis.values.map((a) => a.shortLabel), [
        'Ac',
        'Sw',
        'Fl',
        'Bo',
        'Mo',
        'Af',
        'Ex',
      ]);
    });

    test('balance axes show −5…+5, the others 0…10', () {
      expect(RateAxis.body.display(0), '−5');
      expect(RateAxis.body.display(5), '0');
      expect(RateAxis.body.display(7), '+2');
      expect(RateAxis.flavor.display(7), '7');
      expect(RateAxis.body.start, 5);
      expect(RateAxis.flavor.start, 5);
    });

    test('goodness: distance from the middle on balance axes', () {
      expect(RateAxis.acidity.goodness(5), 1);
      expect(RateAxis.acidity.goodness(0), 0);
      expect(RateAxis.acidity.goodness(10), 0);
      expect(RateAxis.acidity.goodness(7), closeTo(0.6, 1e-9));
      expect(RateAxis.sweetness.goodness(10), 1);
      expect(RateAxis.sweetness.goodness(3), closeTo(0.3, 1e-9));
    });
  });

  group('score and stars', () {
    test('nothing rated: no score, no stars', () {
      expect(<RateAxis, int>{}.score, isNull);
      expect(<RateAxis, int>{}.stars, isNull);
    });

    test('extraction counts double', () {
      // Extraction ideal (1.0 × 2) and flavor 0 (0 × 1): 2/3.
      final v = {RateAxis.extraction: 5, RateAxis.flavor: 0};
      expect(v.score, 67);
      expect(v.stars, 3);
    });

    test('stars are a fifth of the range each, at least one', () {
      expect({RateAxis.flavor: 10}.stars, 5);
      expect({RateAxis.flavor: 0}.stars, 1);
      expect({RateAxis.flavor: 5}.stars, 3); // 50 → 2.5 rounds up
    });
  });

  group('database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<Shot> shot(int id) =>
        (db.select(db.shots)..where((s) => s.id.equals(id))).getSingle();

    Future<int> newShot({int? rating}) => db.insertShotWithReadings(
      ShotsCompanion.insert(
        timestamp: DateTime(2026, 11, 26, 8),
        rating: Value(rating),
      ),
      const [],
    );

    test('stars follow the rating until they are tapped by hand', () async {
      final id = await newShot();
      await db.setShotRate(id, RateAxis.flavor, 10);
      expect((await shot(id)).rating, 5);
      await db.setShotRate(id, RateAxis.extraction, 0);
      expect((await shot(id)).rating, 2); // (1 + 0×2) / 3 = 33
      await db.setShotStars(id, 4);
      await db.setShotRate(id, RateAxis.extraction, 5);
      expect((await shot(id)).rating, 4);
      expect((await shot(id)).starsManual, isTrue);
      // Clearing the stars hands them back: recalculated at once.
      await db.setShotStars(id, 0);
      final back = await shot(id);
      expect(back.starsManual, isFalse);
      expect(back.rating, 5);
    });

    test('stars from before the drag rating are kept', () async {
      final id = await newShot(rating: 2);
      await db.setShotRate(id, RateAxis.flavor, 10);
      final s = await shot(id);
      expect(s.rating, 2);
      expect(s.starsManual, isTrue);
      expect(s.rateValues, {RateAxis.flavor: 10});
    });

    test('clearing an axis removes it from the values', () async {
      final id = await newShot();
      await db.setShotRate(id, RateAxis.body, 3);
      await db.setShotRate(id, RateAxis.body, null);
      final s = await shot(id);
      expect(s.rateValues, isEmpty);
      expect(s.rating, isNull);
    });

    test('clear: all values go, auto stars with them; undo restores', () async {
      final id = await newShot();
      await db.setShotRate(id, RateAxis.flavor, 10);
      await db.setShotRate(id, RateAxis.body, 5);
      final before = await shot(id);
      await db.clearShotRate(id);
      final cleared = await shot(id);
      expect(cleared.rateValues, isEmpty);
      expect(cleared.rating, isNull);
      await db.restoreShotRate(before);
      final back = await shot(id);
      expect(back.rateValues, before.rateValues);
      expect(back.rating, before.rating);
    });

    test('clear keeps stars set by hand', () async {
      final id = await newShot();
      await db.setShotRate(id, RateAxis.flavor, 10);
      await db.setShotStars(id, 2);
      await db.clearShotRate(id);
      final s = await shot(id);
      expect(s.rateValues, isEmpty);
      expect(s.rating, 2);
    });

    test('previous values: last earlier shot with the same bean', () async {
      final bean = await db.insertBean(BeansCompanion.insert(name: 'Guji'));
      Future<int> at(int hour) => db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 11, 26, hour),
          beanId: Value(bean.id),
        ),
        const [],
      );
      final first = await at(7);
      await at(8); // not rated: skipped
      final now = await at(9);
      await db.setShotRate(first, RateAxis.body, 3);
      expect(await db.previousRateValues(await shot(now)), {RateAxis.body: 3});
      expect(await db.previousRateValues(await shot(first)), isNull);
    });
  });

  group('TasteRater', () {
    Widget host(
      void Function(RateAxis, int?) onChanged, {
      RateValues values = const {},
      bool summary = false,
    }) => MaterialApp(
      theme: buildAppTheme(
        variant: AppThemeVariant.dark,
        accent: AppAccent.teal,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: TasteRater(
              values: values,
              onChanged: onChanged,
              startWithSummary: summary,
            ),
          ),
        ),
      ),
    );

    Offset onLine(WidgetTester tester, double fraction) {
      final r = tester.getRect(find.byType(TasteRater));
      return Offset(r.left + 12 + (r.width - 24) * fraction, r.top + 38);
    }

    testWidgets('drag, let go, next axis — snapping to whole steps', (
      tester,
    ) async {
      final got = <RateAxis, int?>{};
      await tester.pumpWidget(host((a, v) => got[a] = v));
      expect(find.text('Acidity'), findsOneWidget);
      // Balance axis: the dot starts in the middle.
      final gesture = await tester.startGesture(onLine(tester, 0.5));
      await gesture.moveTo(onLine(tester, 0.62));
      await gesture.moveTo(onLine(tester, 0.71));
      await tester.pump();
      expect(find.text('+2'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(got[RateAxis.acidity], 7);
      expect(find.text('Sweetness'), findsOneWidget);
    });

    testWidgets('after the last axis: the row of values; tap asks again', (
      tester,
    ) async {
      final got = <RateAxis, int?>{};
      await tester.pumpWidget(host((a, v) => got[a] = v));
      for (var i = 0; i < RateAxis.values.length; i++) {
        await tester.tapAt(onLine(tester, 1));
        await tester.pumpAndSettle();
      }
      expect(got.length, 7);
      expect(find.text('Tap a value to change it'), findsOneWidget);
      expect(find.text('Ex'), findsOneWidget);
      await tester.tap(find.text('Bo'));
      await tester.pumpAndSettle();
      expect(find.text('Body'), findsOneWidget);
      await tester.tapAt(onLine(tester, 0.5));
      await tester.pumpAndSettle();
      expect(got[RateAxis.body], 5);
      // Asked again on its own: straight back to the row.
      expect(find.text('Tap a value to change it'), findsOneWidget);
    });

    testWidgets('skip moves on without a value', (tester) async {
      final got = <RateAxis, int?>{};
      await tester.pumpWidget(host((a, v) => got[a] = v));
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('Sweetness'), findsOneWidget);
      expect(got, isEmpty);
    });

    testWidgets('× next to the name clears only this axis', (tester) async {
      final got = <RateAxis, int?>{RateAxis.body: 3, RateAxis.flavor: 6};
      await tester.pumpWidget(
        host(
          (a, v) => got[a] = v,
          values: {RateAxis.body: 3, RateAxis.flavor: 6},
          summary: true,
        ),
      );
      await tester.tap(find.text('Bo'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(got[RateAxis.body], isNull);
      expect(got[RateAxis.flavor], 6);
      // The question stays, without its value now.
      expect(find.text('Body'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('cleared from outside: back to the first question', (
      tester,
    ) async {
      await tester.pumpWidget(
        host((_, _) {}, values: {RateAxis.body: 3}, summary: true),
      );
      expect(find.text('Bo'), findsOneWidget);
      await tester.pumpWidget(host((_, _) {}, summary: true));
      await tester.pumpAndSettle();
      expect(find.text('Acidity'), findsOneWidget);
      // Undo brings the row back.
      await tester.pumpWidget(
        host((_, _) {}, values: {RateAxis.body: 3}, summary: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bo'), findsOneWidget);
    });

    testWidgets('detail without a rating opens the first question', (
      tester,
    ) async {
      await tester.pumpWidget(host((_, _) {}, summary: true));
      expect(find.text('Acidity'), findsOneWidget);
    });

    testWidgets('long press on the row calls back', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(
            variant: AppThemeVariant.dark,
            accent: AppAccent.teal,
          ),
          home: Scaffold(
            body: TasteRater(
              values: const {RateAxis.body: 3},
              onChanged: (_, _) {},
              startWithSummary: true,
              onLongPressSummary: () => pressed++,
            ),
          ),
        ),
      );
      await tester.longPress(find.text('Bo'));
      expect(pressed, 1);
    });

    testWidgets('detail starts with the row', (tester) async {
      await tester.pumpWidget(
        host((_, _) {}, values: {RateAxis.extraction: 3}, summary: true),
      );
      expect(find.text('Ex'), findsOneWidget);
      expect(find.text('−2'), findsOneWidget);
    });
  });
}
