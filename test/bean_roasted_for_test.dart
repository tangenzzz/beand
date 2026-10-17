import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/screens/beans/bean_form_screen.dart';
import 'package:beand/screens/beans/bean_filter.dart';
import 'package:beand/screens/beans/bean_widgets.dart';
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

import 'package:sqlite3/sqlite3.dart' as sql;

import 'support/legacy_shot_tables.dart';

import 'package:beand/widgets/dot_choice_group.dart';

Widget app(AppDatabase db, Widget home) => MultiProvider(
  providers: [
    Provider<AppDatabase>.value(value: db),
    ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
    // The bean form asks the AI settings to decide whether the row
    // "Fill from packaging or link" is shown at all.
    ChangeNotifierProvider<AiSettings>.value(
      value: AiSettings(keyStore: InMemoryAiKeyStore()),
    ),
    ChangeNotifierProvider<MeticulousSocketService>.value(
      value: MeticulousSocketService(hostname: 'unreachable.local'),
    ),
    // The same machine again under the shared interface: the Pre-Shot card
    // talks to it through that.
    ChangeNotifierProvider<EspressoMachine>.value(
      value: MeticulousSocketService(hostname: 'unreachable.local'),
    ),
    ChangeNotifierProvider<GaggiMateService>.value(value: offlineGaggiMate()),
  ],
  child: MaterialApp(theme: buildAppTheme(), home: home),
);

bool pillSelected(WidgetTester tester, String label) => tester
    .widget<DotChoiceItem>(
      find.ancestor(of: find.text(label), matching: find.byType(DotChoiceItem)),
    )
    .selected;

void main() {
  testWidgets('bean form: Type and Roasted for start without a selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));

    await tester.pumpWidget(app(db, const BeanFormScreen()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.text('Roasted for'), findsOneWidget);
    for (final label in [
      'Single Origin',
      'Blend',
      'Filter',
      'Espresso',
      'Omni',
    ]) {
      expect(
        pillSelected(tester, label),
        false,
        reason: '$label must not be preselected',
      );
    }

    // Tapping selects, tapping again deselects.
    await tester.tap(find.text('Espresso'));
    await tester.pump();
    expect(pillSelected(tester, 'Espresso'), true);
    expect(pillSelected(tester, 'Filter'), false);
    await tester.tap(find.text('Espresso'));
    await tester.pump();
    expect(pillSelected(tester, 'Espresso'), false);

    await tester.tap(find.text('Blend'));
    await tester.pump();
    expect(pillSelected(tester, 'Blend'), true);
    expect(pillSelected(tester, 'Single Origin'), false);
  });

  testWidgets('bean form: selection is saved and shown again', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));

    await tester.pumpWidget(app(db, const BeanFormScreen()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'Guji');
    await tester.tap(find.text('Omni'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    final beans = await tester.runAsync(() => db.select(db.beans).get());
    expect(beans!.single.roastedFor, 'omni');
    // Without a value the type stays empty instead of silently being
    // "Single Origin".
    expect(beans.single.isBlend, isNull);

    await tester.pumpWidget(app(db, BeanFormScreen(bean: beans.single)));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(pillSelected(tester, 'Omni'), true);
    expect(pillSelected(tester, 'Single Origin'), false);
  });

  test('filter and list: Roasted for', () {
    Bean bean(String name, String? roastedFor) => Bean(
      syncId: 'test',
      updatedAt: 0,
      syncState: SyncState.pending,
      deleted: false,
      id: name.hashCode,
      name: name,
      country: 'Kenya',
      processing: 'Washed',
      roastedFor: roastedFor,
      isFrozen: false,
      createdAt: DateTime(2026, 9, 26),
    );
    final espresso = bean('E', 'espresso');
    final filter = bean('F', 'filter');
    final unset = bean('U', null);
    final beans = [espresso, filter, unset];

    // Not in the list row, but the free-text search finds it.
    expect(beanSubtitle(espresso), 'Kenya · Washed');
    expect(beanSubtitle(unset), 'Kenya · Washed');
    expect(beanMatchesQuery(espresso, 'espresso'), true);
    expect(beanMatchesQuery(filter, 'espresso'), false);

    // Filter: one selection, several selections, beans without a value drop
    // out.
    expect(
      filterBeans(beans, filter: const BeanFilter(roastedFor: {'espresso'})),
      [espresso],
    );
    expect(
      filterBeans(
        beans,
        filter: const BeanFilter(roastedFor: {'espresso', 'filter'}),
      ),
      [espresso, filter],
    );
    expect(filterBeans(beans), beans);
    expect(const BeanFilter(roastedFor: {'omni'}).activeCount, 1);
  });

  // Seen 2026-10-14: after changing the taste of an existing bean and saving,
  // "Roasted for" looked empty. Replays exactly that: edit taste (typed and
  // via a suggestion chip), save, reopen.
  testWidgets('editing only the taste keeps Roasted for', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));

    final bean = await tester.runAsync(
      () => db.insertBean(
        const BeansCompanion(
          name: Value('Superfreak'),
          roaster: Value('Some Roaster'),
          isBlend: Value(false),
          roastedFor: Value('filter'),
          taste: Value('cherry'),
        ),
      ),
    );
    // A second bean so the taste field offers a suggestion chip.
    await tester.runAsync(
      () => db.insertBean(
        const BeansCompanion(
          name: Value('Other'),
          taste: Value('blackberry, chocolate'),
        ),
      ),
    );

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }

    await tester.pumpWidget(app(db, BeanFormScreen(bean: bean)));
    await settle();
    expect(pillSelected(tester, 'Filter'), true);

    final taste = find.ancestor(
      of: find.text('e.g. blackcurrant, grapefruit'),
      matching: find.byType(TextField),
    );
    await tester.tap(taste);
    await tester.pump();
    await tester.enterText(taste, 'cherry, bl');
    // Let the chip row finish growing before tapping into it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('blackberry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(pillSelected(tester, 'Filter'), true);

    await tester.tap(find.text('Save'));
    await settle();

    final saved = await tester.runAsync(
      () => (db.select(
        db.beans,
      )..where((b) => b.name.equals('Superfreak'))).getSingle(),
    );
    expect(saved!.taste, 'cherry, blackberry');
    expect(saved.roastedFor, 'filter');
    expect(saved.isBlend, false);

    await tester.pumpWidget(app(db, BeanFormScreen(bean: saved)));
    await settle();
    expect(pillSelected(tester, 'Filter'), true);
  });

  test('migration v7 -> v8: type is kept, Roasted for is empty', () async {
    final raw = sql.sqlite3.openInMemory();
    raw.execute(legacyBeansTable);
    raw.execute(legacyShotTables);
    raw.execute(legacyShotColumnsV5);
    raw.execute('''
      CREATE TABLE stored_profiles (
        id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, json TEXT NOT NULL,
        image_path TEXT NULL, position INTEGER NOT NULL DEFAULT 0,
        fetched_at INTEGER NOT NULL, custom_description TEXT NULL,
        custom_image_path TEXT NULL
      );
    ''');
    raw.execute(
      "INSERT INTO beans (name, is_blend) VALUES ('Blend Bean', 1), ('Single Bean', 0)",
    );
    raw.execute('PRAGMA user_version = 7');

    final db = AppDatabase(NativeDatabase.opened(raw));
    final beans = await db.select(db.beans).get();
    expect(beans.map((b) => b.name), ['Blend Bean', 'Single Bean']);
    expect(beans[0].isBlend, true);
    expect(beans[1].isBlend, false);
    expect(beans.every((b) => b.roastedFor == null), true);
    await db.close();
  });
}
