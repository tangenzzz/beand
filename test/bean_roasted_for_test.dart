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

import 'package:beand/widgets/value_select_row.dart';

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

// Type and Roasted for are the app's dropdown (ValueSelectRow): the row
// shows the chosen title; opening lists the options, the chosen one ticked.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

String rowValue(WidgetTester tester, String label) => tester
    .widget<ValueSelectRow<dynamic>>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ValueSelectRow),
      ),
    )
    .let((row) => '${row.value}');

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

void main() {
  test('filter and list: Roasted for', () {
    Bean bean(String name, String? roastedFor) => Bean(
      frozenDays: 0,
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
