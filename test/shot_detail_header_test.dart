import 'package:beand/database/database.dart';
import 'package:beand/screens/beans/bean_widgets.dart';
import 'package:beand/screens/history/history_widgets.dart';
import 'package:beand/screens/history/shot_detail_screen.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Shot detail header: name with "12 d off roast" in its row, roaster and
// profile under the name, the stars in the profile's line (the line is switchable in
// Settings → History).

Widget _app(AppDatabase db, AppSettings settings, int shotId) => MultiProvider(
  providers: [
    Provider<AppDatabase>.value(value: db),
    ChangeNotifierProvider<AppSettings>.value(value: settings),
    ChangeNotifierProvider<AiSettings>.value(
      value: AiSettings(keyStore: InMemoryAiKeyStore()),
    ),
  ],
  child: MaterialApp(
    theme: buildAppTheme(),
    home: ShotDetailScreen(shotId: shotId),
  ),
);

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  Future<void> teardownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await tester.runAsync(db.close);
  }

  // A phone-sized screen (Pixel, logical pixels).
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<int> shotWith(
    WidgetTester tester, {
    required String name,
    String? roaster,
    DateTime? roastDate,
    required DateTime at,
  }) async {
    late int id;
    await tester.runAsync(() async {
      final bean = await db.insertBean(
        BeansCompanion.insert(
          name: name,
          roaster: Value(roaster),
          roastDate: Value(roastDate),
        ),
      );
      id = await db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: at,
          beanId: Value(bean.id),
          profileName: const Value("Damian's LRv2"),
          doseGrams: const Value(18),
          finalWeight: const Value(38.4),
          durationMs: const Value(34000),
        ),
        const [],
      );
    });
    return id;
  }

  RenderParagraph paragraphOf(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(
        find.descendant(of: find.text(text), matching: find.byType(RichText)),
      );

  testWidgets('off-roast line beside the name, stars by the profile, in days', (
    tester,
  ) async {
    phone(tester);
    final id = await shotWith(
      tester,
      name: 'Guji Natural',
      roaster: 'La Cabra',
      roastDate: DateTime(2026, 9, 9),
      at: DateTime(2026, 9, 21, 8, 12),
    );
    await tester.pumpWidget(_app(db, AppSettings(), id));
    await settle(tester);

    final line = find.text('12 d off roast');
    expect(line, findsOneWidget);
    // In the row of the bean name, the stars below it.
    final off = tester.getRect(line);
    final stars = tester.getRect(find.byType(StarRating));
    final name = tester.getRect(find.text('Guji Natural'));
    expect(off.top, lessThan(name.bottom));
    expect(off.bottom, greaterThan(name.top));
    expect(off.left, greaterThan(name.left));
    expect(stars.top, greaterThanOrEqualTo(off.bottom));
    // The stars in the line of the profile.
    final profile = tester.getRect(find.text("Damian's LRv2"));
    expect(stars.top, lessThan(profile.bottom));
    expect(stars.bottom, greaterThan(profile.top));
    expect(stars.left, greaterThan(profile.right));

    await teardownApp(tester);
  });

  testWidgets('no roast date: no off-roast line', (tester) async {
    phone(tester);
    final id = await shotWith(
      tester,
      name: 'Guji Natural',
      at: DateTime(2026, 9, 21, 8, 12),
    );
    await tester.pumpWidget(_app(db, AppSettings(), id));
    await settle(tester);

    expect(find.byKey(const ValueKey('shot-days-off-roast')), findsNothing);
    expect(find.textContaining('off roast'), findsNothing);

    await teardownApp(tester);
  });

  testWidgets('switched off in the settings: the line goes away', (
    tester,
  ) async {
    phone(tester);
    final id = await shotWith(
      tester,
      name: 'Guji Natural',
      roastDate: DateTime(2026, 8, 31),
      at: DateTime(2026, 9, 21, 8, 12),
    );
    final settings = AppSettings();
    await tester.pumpWidget(_app(db, settings, id));
    await settle(tester);
    expect(find.text('3 w off roast'), findsOneWidget);

    await tester.runAsync(() => settings.setShowDaysOffRoast(false));
    await tester.pump();
    expect(find.textContaining('off roast'), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        AppSettings.showDaysOffRoastPrefKey,
      ),
      isFalse,
    );
    // The stars stay.
    expect(find.byType(StarRating), findsOneWidget);

    await teardownApp(tester);
  });

  // The test font draws every glyph one em wide, so the check is on the
  // width the names get, not on a given name fitting: before, name and
  // roaster split one line beside chevron and stars (~66 px each on a
  // phone); now each has its own line, the name up to two. Without a roast
  // date, so the (in the test font very wide) off-roast line doesn't set
  // the width of the stars' column.
  testWidgets('long bean and roaster names are not cut early', (tester) async {
    phone(tester);
    const name = 'Finca La Esperanza Gesha Washed Lot 7';
    const roaster = 'Onyx Coffee Lab Roasters';
    final id = await shotWith(
      tester,
      name: name,
      roaster: roaster,
      at: DateTime(2026, 9, 21, 8, 12),
    );
    await tester.pumpWidget(_app(db, AppSettings(), id));
    await settle(tester);

    expect(tester.widget<Text>(find.text(name)).maxLines, 2);
    expect(paragraphOf(tester, name).constraints.maxWidth, greaterThan(135));
    expect(paragraphOf(tester, roaster).constraints.maxWidth, greaterThan(150));
    // The names take all the width up to the stars.
    final stars = tester.getRect(find.byType(StarRating));
    expect(
      tester.getRect(find.text(roaster)).left +
          paragraphOf(tester, roaster).constraints.maxWidth,
      moreOrLessEquals(stars.left - 8),
    );
    // Roaster on its own line, below the name.
    expect(
      tester.getRect(find.text(roaster)).top,
      greaterThanOrEqualTo(tester.getRect(find.text(name)).bottom),
    );

    await teardownApp(tester);
  });

  testWidgets('an extremely long name ends with an ellipsis', (tester) async {
    phone(tester);
    final name = 'Very Long Coffee Name ' * 6;
    final id = await shotWith(
      tester,
      name: name,
      at: DateTime(2026, 9, 21, 8, 12),
    );
    await tester.pumpWidget(_app(db, AppSettings(), id));
    await settle(tester);

    expect(paragraphOf(tester, name).didExceedMaxLines, isTrue);
    expect(tester.takeException(), isNull);

    await teardownApp(tester);
  });

  group('daysOffRoastAt', () {
    Future<Bean> bag({
      DateTime? roast,
      DateTime? frozen,
      DateTime? thawed,
      bool isFrozen = false,
      int frozenDays = 0,
    }) async {
      final test = AppDatabase(NativeDatabase.memory());
      addTearDown(test.close);
      return test.insertBean(
        BeansCompanion.insert(
          name: 'Bag',
          roastDate: Value(roast),
          frozenDate: Value(frozen),
          thawedDate: Value(thawed),
          isFrozen: Value(isFrozen),
          frozenDays: Value(frozenDays),
        ),
      );
    }

    test('no roast date: null', () async {
      expect(daysOffRoastAt(await bag(), DateTime(2026, 9, 21)), isNull);
    });

    test('calendar days since roasting', () async {
      final b = await bag(roast: DateTime(2026, 9, 9));
      expect(daysOffRoastAt(b, DateTime(2026, 9, 21, 23, 50)), 12);
    });

    test('thawed bag: only freezer days before the shot count', () async {
      // Roasted 1 Sep, frozen 5 Sep, thawed 25 Sep: 19 days paused.
      final b = await bag(
        roast: DateTime(2026, 9, 1),
        frozen: DateTime(2026, 9, 5),
        thawed: DateTime(2026, 9, 25),
        frozenDays: pausedDays(DateTime(2026, 9, 5), DateTime(2026, 9, 25)),
      );
      // Before freezing: all days.
      expect(daysOffRoastAt(b, DateTime(2026, 9, 3)), 2);
      // After thawing: like the freshness ring.
      expect(
        daysOffRoastAt(b, DateTime(2026, 9, 30)),
        daysSinceFreshnessStart(b, DateTime(2026, 9, 30)),
      );
      expect(daysOffRoastAt(b, DateTime(2026, 9, 30)), 10);
    });

    test('still frozen: the days in the freezer up to the shot', () async {
      final b = await bag(
        roast: DateTime(2026, 9, 1),
        frozen: DateTime(2026, 9, 5),
        isFrozen: true,
      );
      expect(daysOffRoastAt(b, DateTime(2026, 9, 10)), 5);
    });

    test('labels: days, then weeks', () {
      expect(daysOffRoastLabel(0), '0 d off roast');
      expect(daysOffRoastLabel(13), '13 d off roast');
      expect(daysOffRoastLabel(14), '2 w off roast');
      expect(daysOffRoastLabel(23), '3 w off roast');
    });
  });
}
