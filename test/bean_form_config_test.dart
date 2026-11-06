import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/screens/beans/bean_widgets.dart';
import 'package:beand/screens/beans/freshness.dart';
import 'package:beand/screens/settings/beans_form_settings_screen.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'support/legacy_shot_tables.dart';

Widget app(AppDatabase db, AppSettings settings, Widget home) => MultiProvider(
  providers: [
    Provider<AppDatabase>.value(value: db),
    ChangeNotifierProvider<AppSettings>.value(value: settings),
    // The bean form asks the AI settings to decide whether the
    // "Fill from packaging or link" row is shown at all.
    ChangeNotifierProvider<AiSettings>.value(
      value: AiSettings(keyStore: InMemoryAiKeyStore()),
    ),
    ChangeNotifierProvider<MeticulousSocketService>.value(
      value: MeticulousSocketService(hostname: 'unreachable.local'),
    ),
    // The same machine again under the common interface: the pre-shot card
    // talks to it through that.
    ChangeNotifierProvider<EspressoMachine>.value(
      value: MeticulousSocketService(hostname: 'unreachable.local'),
    ),
    ChangeNotifierProvider<GaggiMateService>.value(value: offlineGaggiMate()),
  ],
  child: MaterialApp(theme: buildAppTheme(), home: home),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('form fields: default order, reorder, hide, save', () async {
    final settings = await AppSettings.load();
    expect(settings.beanFormFields, BeanFormField.values);
    expect(settings.visibleBeanFormFields, BeanFormField.values);

    // The first field to the end (index depends on the field count, not hardcoded 8).
    await settings.reorderBeanFormFields(0, BeanFormField.values.length - 1);
    await settings.setBeanFormFieldVisible(BeanFormField.variety, false);
    expect(settings.beanFormFields.last, BeanFormField.processing);
    expect(
      settings.visibleBeanFormFields,
      isNot(contains(BeanFormField.variety)),
    );

    final reloaded = await AppSettings.load();
    expect(reloaded.beanFormFields, settings.beanFormFields);
    expect(reloaded.isBeanFormFieldVisible(BeanFormField.variety), false);
  });

  test('form fields: missing/unknown fields in saved order', () async {
    SharedPreferences.setMockInitialValues({
      AppSettings.beanFormOrderPrefKey: [
        'taste',
        'gibtsNicht',
        'taste',
        'cost',
      ],
    });
    final settings = await AppSettings.load();
    expect(settings.beanFormFields.first, BeanFormField.taste);
    expect(settings.beanFormFields, contains(BeanFormField.cost));
    expect(settings.beanFormFields.toSet(), BeanFormField.values.toSet());
    expect(settings.beanFormFields, hasLength(BeanFormField.values.length));
  });

  testWidgets('form settings: switches and dragging change the settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final settings = AppSettings();
    await tester.pumpWidget(app(db, settings, const BeansFormSettingsScreen()));
    // One card, one line: between "Always shown" and the movable fields.
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('ALWAYS SHOWN'), findsOneWidget);

    for (final fixed in ['Photo', 'Name', 'Roastery']) {
      expect(find.text(fixed), findsOneWidget);
    }
    expect(find.byType(Switch), findsNWidgets(BeanFormField.values.length));

    // Turn off Variety.
    await tester.tap(
      find
          .byType(Switch)
          .at(BeanFormField.values.indexOf(BeanFormField.variety)),
    );
    await tester.pump();
    expect(settings.isBeanFormFieldVisible(BeanFormField.variety), false);

    // Drag Processing (first row) down by its handle.
    await tester.drag(
      find.byIcon(Icons.drag_handle).first,
      const Offset(0, 130),
    );
    await tester.pumpAndSettle();
    expect(settings.beanFormFields.first, isNot(BeanFormField.processing));
    expect(
      settings.beanFormFields.indexOf(BeanFormField.country),
      greaterThan(0),
    );
    await db.close();
  });

  testWidgets(
    'list: frozen = ice ring with snowflake, without ring only the icon',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final frozen = Bean(
        frozenDays: 0,
        syncId: 'test',
        updatedAt: 0,
        syncState: SyncState.pending,
        deleted: false,
        id: 1,
        name: 'Frozen',
        isBlend: false,
        isFrozen: true,
        roastDate: DateTime.now().subtract(const Duration(days: 90)),
        createdAt: DateTime(2026, 9, 1),
      );
      Widget row(AppSettings s) => app(
        db,
        s,
        Scaffold(
          body: BeanRow(bean: frozen, onTap: () {}),
        ),
      );

      await tester.pumpWidget(row(AppSettings()));
      expect(find.byType(FrozenRing), findsOneWidget);
      expect(find.byType(FreshnessRing), findsNothing);

      await tester.pumpWidget(row(AppSettings(showFreshnessRing: false)));
      expect(find.byType(FrozenRing), findsNothing);
      expect(find.byIcon(Icons.ac_unit), findsOneWidget);

      // Thawed 5 days ago, freeze date unknown (from before it was
      // recorded): normal ring from thaw date, not from roast date.
      final thawed = Bean(
        frozenDays: 0,
        syncId: 'test',
        updatedAt: 0,
        syncState: SyncState.pending,
        deleted: false,
        id: 2,
        name: 'Thawed',
        isBlend: false,
        isFrozen: false,
        roastDate: DateTime.now().subtract(const Duration(days: 90)),
        thawedDate: DateTime.now().subtract(const Duration(days: 5)),
        createdAt: DateTime(2026, 9, 1),
      );
      await tester.pumpWidget(
        app(
          db,
          AppSettings(),
          Scaffold(
            body: BeanRow(bean: thawed, onTap: () {}),
          ),
        ),
      );
      expect(find.byType(FrozenRing), findsNothing);
      expect(tester.widget<FreshnessRing>(find.byType(FreshnessRing)).days, 5);
      await db.close();
    },
  );

  test('migration v2 -> v3 adds variety, producer, freezing', () async {
    final raw = sql.sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE beans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        roaster TEXT NULL,
        roast_date INTEGER NULL,
        is_blend INTEGER NOT NULL DEFAULT 0,
        country TEXT NULL,
        processing TEXT NULL,
        weight_grams REAL NULL,
        taste TEXT NULL,
        cost REAL NULL,
        photo_path TEXT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', CURRENT_TIMESTAMP))
      );
    ''');
    raw.execute(legacyShotTables);
    raw.execute(
      "INSERT INTO beans (name, country) VALUES ('Guji', 'Ethiopia')",
    );
    raw.execute('PRAGMA user_version = 2');

    final db = AppDatabase(NativeDatabase.opened(raw));
    final beans = await db.select(db.beans).get();
    expect(beans.single.country, 'Ethiopia');
    expect(beans.single.variety, isNull);
    expect(beans.single.producer, isNull);
    expect(beans.single.isFrozen, false);
    expect(beans.single.thawedDate, isNull);
    await db.close();
  });
}
