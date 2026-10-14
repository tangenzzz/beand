import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/models/history_import.dart';
import 'package:beand/screens/history/history_tab.dart';
import 'package:beand/screens/history/shot_detail_screen.dart';
import 'package:beand/screens/live/inline_picker.dart';
import 'package:beand/screens/beans/beans_tab.dart';
import 'package:beand/screens/history/history_widgets.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/widgets/app_button.dart';
import 'package:beand/widgets/header_icon_button.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/models/taste_profile.dart';
import 'package:beand/screens/live/post_shot_card.dart';
import 'package:beand/screens/live/shot_cards_carousel.dart';
import 'package:beand/widgets/taste_chips.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';

import 'support/offline_gaggimate.dart';

import 'dart:convert';
import 'dart:io';

Widget _app(AppDatabase db, Widget home) => MultiProvider(
  providers: [
    Provider<AppDatabase>.value(value: db),
    // The filter sheet derives its machine options from the Home switches
    // (see HistoryFilter).
    ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
    // Shot detail and Post-Shot card ask whether shot analysis is on (not
    // here: no AI set up).
    ChangeNotifierProvider<AiSettings>.value(
      value: AiSettings(keyStore: InMemoryAiKeyStore()),
    ),
    // The Post-Shot card reads from this whether it is the active card.
    ChangeNotifierProvider<LiveShotService>.value(
      value: MeticulousLiveShotService(
        MeticulousSocketService(hostname: 'unreachable.local'),
      ),
    ),
  ],
  child: MaterialApp(theme: buildAppTheme(), home: home),
);

// The second history row is a RichText of icon+value pairs (Grind, Dose,
// Yield) — reduced here to the plain text without icons.
Finder metricsLine(String text) => find.byWidgetPredicate(
  (w) =>
      w is RichText &&
      w.text
              .toPlainText(includePlaceholders: false)
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim() ==
          text,
);

Future<int> _insertShot(
  AppDatabase db, {
  required DateTime at,
  int? beanId,
  String profile = "Damian's LRv2",
  double? dose = 18,
  String grind = '3.2',
  int? rating,
  String? externalId,
  bool withReadings = true,
}) async {
  final raw = Map<String, dynamic>.from(
    jsonDecode(
      File('test/fixtures/history_entry_bailey.json').readAsStringSync(),
    ) as Map,
  );
  final parsed = parseHistoryEntry(raw)!;
  return db.insertShotWithReadings(
    ShotsCompanion.insert(
      timestamp: at,
      externalId: Value(externalId),
      beanId: Value(beanId),
      profileName: Value(profile),
      profileColor: const Value('#C96F4A'),
      doseGrams: Value(dose),
      grindSize: Value(grind),
      finalWeight: const Value(38.4),
      durationMs: const Value(34000),
      profileTemp: const Value(93.1),
      rating: Value(rating),
    ),
    withReadings ? parsed.readings : const [],
  );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  // Drift delivers stream results asynchronously in real time (like
  // beans_tab_test).
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  Future<void> teardownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    // Pending stream queries need real time to complete.
    await tester.runAsync(db.close);
  }

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('History: empty list shows a hint', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(_app(db, const Scaffold(body: HistoryTab())));
    await settle(tester);
    expect(find.textContaining('No shots recorded yet'), findsOneWidget);
    await teardownApp(tester);
  });

  testWidgets('History: rows grouped by day, no magnifier', (tester) async {
    bigScreen(tester);
    await tester.runAsync(() async {
      final bean = await db.insertBean(
        BeansCompanion.insert(
          name: 'Guji Natural',
          roaster: const Value('La Cabra'),
        ),
      );
      final now = DateTime.now();
      await _insertShot(
        db,
        at: now,
        beanId: bean.id,
        rating: 4,
        externalId: 'a',
      );
      await _insertShot(
        db,
        at: now.subtract(const Duration(days: 1)),
        profile: 'Soup',
        externalId: 'b',
      );
    });
    await tester.pumpWidget(_app(db, const Scaffold(body: HistoryTab())));
    await settle(tester);

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    // Row: bean + roaster on top, below it profile and Grind/Dose/Yield.
    expect(find.text('Guji Natural'), findsOneWidget);
    expect(find.text('La Cabra'), findsOneWidget);
    expect(metricsLine('3.2 18 g 38.4 g'), findsNWidgets(2));
    // A shot without a bean shows the profile in the first row.
    expect(find.text('Soup'), findsOneWidget);

    // No search in the History tab (only filter and settings).
    expect(find.byTooltip('Search'), findsNothing);
    expect(find.byTooltip('Filter'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await teardownApp(tester);
  });

  testWidgets('Filter sheet: minimum rating narrows the list', (tester) async {
    bigScreen(tester);
    await tester.runAsync(() async {
      final now = DateTime.now();
      await _insertShot(
        db,
        at: now,
        rating: 5,
        profile: 'Good',
        externalId: 'a',
      );
      await _insertShot(
        db,
        at: now.subtract(const Duration(hours: 1)),
        rating: 2,
        profile: 'Bad',
        externalId: 'b',
      );
    });
    await tester.pumpWidget(_app(db, const Scaffold(body: HistoryTab())));
    await settle(tester);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Bad'), findsOneWidget);

    await tester.tap(find.byTooltip('Filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 ★ +'));
    await tester.pump();
    expect(find.text('Show 1 shot'), findsOneWidget);
    await tester.tap(find.text('Show 1 shot'));
    await tester.pumpAndSettle();
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Bad'), findsNothing);

    await teardownApp(tester);
  });

  Future<T> inDb<T>(WidgetTester tester, Future<T> Function() f) async {
    late T result;
    await tester.runAsync(() async => result = await f());
    return result;
  }

  Finder star(int n) => find
      .descendant(
        of: find.byType(StarRating),
        matching: find.byIcon(Icons.star_rounded),
      )
      .at(n - 1);

  testWidgets('Shot detail: key figures, phases; edit stars and note', (
    tester,
  ) async {
    bigScreen(tester);
    late int id;
    await tester.runAsync(() async {
      final bean = await db.insertBean(
        BeansCompanion.insert(
          name: 'Guji Natural',
          roaster: const Value('La Cabra'),
        ),
      );
      id = await _insertShot(
        db,
        at: DateTime(2026, 9, 21, 8, 12),
        beanId: bean.id,
        rating: 2,
        externalId: 'a',
      );
    });
    await tester.pumpWidget(_app(db, ShotDetailScreen(shotId: id)));
    await settle(tester);

    expect(find.text('Guji Natural'), findsOneWidget);
    expect(find.text('34.0 s'), findsOneWidget);
    expect(find.text('38.4 g'), findsOneWidget);
    expect(find.text('93.1 °C'), findsOneWidget);
    expect(find.text('RATIO'), findsOneWidget);
    expect(metricsLine('1:2.1'), findsOneWidget);
    // Since the redesign the stage bar only names the phase at the cursor;
    // the cursor starts at the end of the brew.
    expect(find.text('Percolation'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'\d+\.\d s / \d+\.\d s')),
      findsOneWidget,
    );
    expect(
      find.text('Compare'),
      findsOneWidget,
      reason: 'row in the style of the Pre-Shot rows',
    );
    expect(find.byTooltip('Share'), findsOneWidget);

    // Stars: 5th star sets 5; tapping the current rating again clears it.
    await tester.tap(star(5));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.rating,
      5,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(star(5));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.rating,
      isNull,
    );

    // Note: saved debounced.
    await tester.enterText(
      find.descendant(
        of: find.byType(ShotNotesField),
        matching: find.byType(TextField),
      ),
      'Sweet, try 0.1 finer',
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.notes,
      'Sweet, try 0.1 finer',
    );

    await teardownApp(tester);
  });

  testWidgets('note is still saved when leaving the screen', (tester) async {
    bigScreen(tester);
    final id = await inDb(
      tester,
      () => _insertShot(db, at: DateTime(2026, 9, 21), externalId: 'a'),
    );
    await tester.pumpWidget(_app(db, ShotDetailScreen(shotId: id)));
    await settle(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(ShotNotesField),
        matching: find.byType(TextField),
      ),
      'quick note',
    );
    await tester.pumpWidget(
      const SizedBox(),
    ); // screen gone before the timer fires
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.notes,
      'quick note',
    );
    await tester.pump(
      Duration.zero,
    ); // drift cleanup timer of the torn-down streams
    await tester.runAsync(db.close);
  });

  testWidgets(
    'comparison in detail: selection, older shot dashed, values dimmed beside',
    (tester) async {
      bigScreen(tester);
      late int newer;
      await tester.runAsync(() async {
        final bean = await db.insertBean(
          BeansCompanion.insert(name: 'Guji Natural'),
        );
        await _insertShot(
          db,
          at: DateTime(2026, 9, 20, 7, 50),
          beanId: bean.id,
          grind: '3.4',
          externalId: 'old',
        );
        newer = await _insertShot(
          db,
          at: DateTime(2026, 9, 21, 8, 12),
          beanId: bean.id,
          grind: '3.2',
          externalId: 'new',
        );
        await _insertShot(
          db,
          at: DateTime(2026, 9, 19),
          profile: 'Other bean shot',
          externalId: 'unrelated',
        );
      });
      await tester.pumpWidget(_app(db, ShotDetailScreen(shotId: newer)));
      await settle(tester);

      // As in the Pre-Shot card: the "Compare" row expands a list.
      expect(find.text('Select shot'), findsOneWidget);
      await tester.tap(find.text('Select shot'));
      await settle(tester); // reads the shots from the DB
      await tester.pump();
      final picker = find.byType(InlinePicker<ShotEntry>);
      expect(picker, findsOneWidget);
      // Shots with the same bean first, then the rest; the current one is
      // missing.
      final tiles = tester
          .widgetList<Text>(
            find.descendant(of: picker, matching: find.byType(Text)),
          )
          .map((t) => t.textSpan?.toPlainText() ?? t.data ?? '')
          .toList();
      expect(
        tiles.indexWhere((t) => t.startsWith('Guji Natural')),
        lessThan(tiles.indexWhere((t) => t.startsWith('Other bean shot'))),
      );
      expect(
        tiles.where((t) => t.startsWith('Guji Natural')),
        hasLength(1),
        reason: 'only the other Guji shot, not the open one',
      );
      expect(tiles.any((t) => t.contains('Mon 21 Sep')), isFalse);

      // Selecting closes the list and shows the comparison.
      await tester.tap(
        find.descendant(
          of: picker,
          matching: find.textContaining('Guji Natural'),
        ),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(InlinePicker<ShotEntry>), findsNothing);

      expect(find.textContaining('Sun 20 Sep · 07:50'), findsOneWidget);
      expect(find.textContaining('older'), findsWidgets);
      // Differing grind: new value plus the older one smaller beside it.
      expect(find.textContaining('3.2  3.4'), findsOneWidget);
      // Equal values (dose 18) also sit side by side.
      expect(find.text('18 g  18'), findsOneWidget);
      expect(find.byTooltip('Remove comparison'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove comparison'));
      await tester.pump();
      expect(find.text('Select shot'), findsOneWidget);
      expect(find.textContaining('Sun 20 Sep · 07:50'), findsNothing);

      await teardownApp(tester);
    },
  );

  testWidgets('Post Shot without shots: hint', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(
      _app(
        db,
        const Scaffold(
          body: SizedBox(
            height: ShotCardsCarousel.cardHeight,
            child: PostShotCard(),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.textContaining('No shot yet'), findsOneWidget);
    await teardownApp(tester);
  });

  testWidgets('Post Shot: shows the last shot, rating and note are editable', (
    tester,
  ) async {
    bigScreen(tester);
    late int id;
    await tester.runAsync(() async {
      await _insertShot(
        db,
        at: DateTime(2026, 9, 20),
        profile: 'Old',
        externalId: 'a',
      );
      id = await _insertShot(
        db,
        at: DateTime(2026, 9, 21),
        profile: 'Newest',
        externalId: 'b',
      );
    });
    await tester.pumpWidget(
      _app(
        db,
        const Scaffold(
          body: SizedBox(
            height: ShotCardsCarousel.cardHeight,
            child: PostShotCard(),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Old'), findsNothing);

    await tester.tap(star(3));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.rating,
      3,
    );

    final notesField = find.descendant(
      of: find.byType(ShotNotesField),
      matching: find.byType(TextField),
    );
    await tester.enterText(notesField, 'balanced');
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(
      (await inDb(tester, () => db.watchShotEntry(id).first))!.shot.notes,
      'balanced',
    );

    // Rating chips: each tap on "Finish" increases by one point, the
    // fourth clears the value again.
    Future<Shot> tapFinish() async {
      await tester.tap(
        find.descendant(
          of: find.byType(TasteChips),
          matching: find.text('Finish'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      return (await inDb(tester, () => db.watchShotEntry(id).first))!.shot;
    }

    expect((await tapFinish()).tasteValues[TasteAxis.finish], 1);
    expect((await tapFinish()).tasteValues[TasteAxis.finish], 2);
    expect((await tapFinish()).tasteValues[TasteAxis.finish], 3);
    expect((await tapFinish()).tasteValues[TasteAxis.finish], 0);

    await teardownApp(tester);
  });

  testWidgets(
    'Detail: delete shot with confirmation, screen closes, shot is gone',
    (tester) async {
      bigScreen(tester);
      final id = await inDb(
        tester,
        () => _insertShot(
          db,
          at: DateTime(2026, 9, 21),
          profile: 'Doomed',
          externalId: 'a',
        ),
      );
      await inDb(
        tester,
        () => _insertShot(
          db,
          at: DateTime(2026, 9, 20),
          profile: 'Survivor',
          externalId: 'b',
        ),
      );
      await tester.pumpWidget(
        _app(
          db,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ShotDetailScreen(shotId: id),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // route transition
      await settle(tester);
      expect(find.byType(ShotDetailScreen), findsOneWidget);

      // The delete button sits below the card at the end of the page.
      final deleteButton = find.widgetWithText(AppButton, 'Delete shot');

      // Cancel deletes nothing.
      await tester.ensureVisible(deleteButton);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(find.text('Delete this shot?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ShotDetailScreen), findsOneWidget);
      expect(
        (await inDb(tester, () => db.watchShotEntries().first)),
        hasLength(2),
      );

      await tester.ensureVisible(deleteButton);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ShotDetailScreen), findsNothing);
      final left = await inDb(tester, () => db.watchShotEntries().first);
      expect(left.map((e) => e.shot.profileName), ['Survivor']);

      await teardownApp(tester);
    },
  );

  testWidgets(
    'List: long press starts selection, delete several, Back ends selection',
    (tester) async {
      bigScreen(tester);
      final now = DateTime.now();
      await tester.runAsync(() async {
        await _insertShot(db, at: now, profile: 'One', externalId: 'a');
        await _insertShot(
          db,
          at: now.subtract(const Duration(hours: 1)),
          profile: 'Two',
          externalId: 'b',
        );
        await _insertShot(
          db,
          at: now.subtract(const Duration(hours: 2)),
          profile: 'Three',
          externalId: 'c',
        );
      });
      await tester.pumpWidget(_app(db, const Scaffold(body: HistoryTab())));
      await settle(tester);

      await tester.longPress(find.text('One'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      // In selection mode tapping doesn't open a detail but selects.
      await tester.tap(find.text('Two'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byType(ShotDetailScreen), findsNothing);
      await tester.tap(find.text('Two')); // deselect again
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      // Back ends the selection (not the app).
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.textContaining('selected'), findsNothing);

      await tester.longPress(find.text('One'));
      await tester.tap(find.text('Three'));
      await tester.pump();
      await tester.tap(find.byTooltip('Delete selected shots'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 shots?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('One'), findsNothing);
      expect(find.text('Three'), findsNothing);
      expect(find.text('Two'), findsOneWidget);
      expect(find.textContaining('selected'), findsNothing);

      await teardownApp(tester);
    },
  );

  testWidgets(
    'headers: search, filter, gear equally small in History and Beans',
    (tester) async {
      bigScreen(tester);
      Widget withProviders(Widget tab) => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          ChangeNotifierProvider<MeticulousSocketService>.value(
            value: MeticulousSocketService(hostname: 'unreachable.local'),
          ),
          // The same machine once more under the shared interface: the
          // Pre-Shot card addresses it through that.
          ChangeNotifierProvider<EspressoMachine>.value(
            value: MeticulousSocketService(hostname: 'unreachable.local'),
          ),
          ChangeNotifierProvider<GaggiMateService>.value(
            value: offlineGaggiMate(),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: tab),
        ),
      );

      // Reference: the button the gear in the Home tab also uses.
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: HeaderIconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      final reference = tester.getSize(find.byType(HeaderIconButton));
      expect(
        reference.width,
        lessThan(48),
        reason: 'more compact than the standard IconButton',
      );

      final tabs = <Widget, List<String>>{
        const HistoryTab(): ['Filter', 'Settings'],
        const BeansTab(): ['Search', 'Filter', 'Settings'],
      };
      for (final MapEntry(key: tab, value: tooltips) in tabs.entries) {
        await tester.pumpWidget(withProviders(tab));
        await settle(tester);
        for (final tooltip in tooltips) {
          final button = find
              .ancestor(
                of: find.byTooltip(tooltip),
                matching: find.byType(HeaderIconButton),
              )
              .first;
          expect(
            tester.getSize(button),
            reference,
            reason: '$tooltip in ${tab.runtimeType}',
          );
        }
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byTooltip('Filter'),
            matching: find.byIcon(Icons.tune),
          ),
        );
        expect(icon.size, isNull, reason: 'size comes from the button (22 px)');
        expect(IconTheme.of(tester.element(find.byIcon(Icons.tune))).size, 22);
      }
      await teardownApp(tester);
    },
  );
}
