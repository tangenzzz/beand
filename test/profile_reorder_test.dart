import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/services/brew_recipe_store.dart';
import 'package:beand/services/brew_recipes_source.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/profile_store.dart';
import 'package:beand/widgets/reorderable_tile_row.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Profile order via long-press and drag: shared widget, local positions,
// command to the machine, own order for Pour Over.

class _ReorderTransport implements GaggiMateTransport {
  final _incoming = StreamController<dynamic>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  Future<void> get ready async {}

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(String data) {
    final message = Map<String, dynamic>.from(jsonDecode(data) as Map);
    sent.add(message);
    final type = message['tp'] as String;
    if (!type.startsWith('req:')) return;
    _incoming.add(
      jsonEncode({
        'tp': 'res:${type.substring(4)}',
        'rid': message['rid'],
        if (type == 'req:profiles:list') 'profiles': <Object>[],
      }),
    );
  }

  @override
  Future<void> close() async => _incoming.close();

  void receive(Map<String, dynamic> frame) => _incoming.add(jsonEncode(frame));
}

class _RealHttp extends HttpOverrides {}

Future<void> _seed(AppDatabase db, String machine, List<String> ids) async {
  for (var i = 0; i < ids.length; i++) {
    await db.upsertStoredProfile(
      StoredProfilesCompanion(
        id: Value(ids[i]),
        machine: Value(machine),
        name: Value(ids[i]),
        json: const Value('{}'),
        position: Value(i),
        fetchedAt: Value(DateTime(2026, 10, 11)),
      ),
    );
  }
}

Future<List<String>> _order(AppDatabase db, String machine) async => [
  for (final p in await db.watchStoredProfiles(machine: machine).first) p.id,
];

void main() {
  group('reorderMachineProfiles', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('GaggiMate: hidden profiles keep their place, machine '
        'gets the whole list', () async {
      await _seed(db, 'gaggimate', ['a', 'hidden', 'b', 'c']);
      final transport = _ReorderTransport();
      final machine = GaggiMateService(
        host: 'gaggimate.local',
        transportFactory: (_) => transport,
        autoReconnect: false,
      );
      machine.connect();
      transport.receive({'tp': 'evt:status', 'm': 1});
      for (var i = 0; i < 100; i++) {
        if (machine.connectionState == MachineConnectionState.connected) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final result = await reorderMachineProfiles(
        database: db,
        machine: machine,
        machineKey: 'gaggimate',
        visible: ['c', 'a', 'b'],
      );

      expect(result.isOk, isTrue);
      expect(await _order(db, 'gaggimate'), ['c', 'hidden', 'a', 'b']);
      final reorder = transport.sent.singleWhere(
        (m) => m['tp'] == 'req:profiles:reorder',
      );
      expect(reorder['order'], ['c', 'hidden', 'a', 'b']);
      machine.dispose();
    });

    test('machine unreachable: old order comes back', () async {
      await _seed(db, 'gaggimate', ['a', 'b']);
      final machine = GaggiMateService(
        host: 'gaggimate.local',
        transportFactory: (_) => _ReorderTransport(),
        autoReconnect: false,
      );

      final result = await reorderMachineProfiles(
        database: db,
        machine: machine,
        machineKey: 'gaggimate',
        visible: ['b', 'a'],
      );

      expect(result.isOk, isFalse);
      expect(await _order(db, 'gaggimate'), ['a', 'b']);
      machine.dispose();
    });

    test('Meticulous: POST /api/v1/settings with profile_order', () async {
      await _seed(db, 'meticulous', ['x', 'y', 'z']);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <(String, String, Object?)>[];
      server.listen((req) async {
        final body = await utf8.decodeStream(req);
        requests.add((
          req.method,
          req.uri.path,
          body.isEmpty ? null : jsonDecode(body),
        ));
        req.response
          ..statusCode = 200
          ..write('{}');
        await req.response.close();
      });
      final machine = MeticulousSocketService(
        hostname: '127.0.0.1:${server.port}',
      );

      // testWidgets further down sets the test binding, which blocks real
      // HTTP (response 400) — this goes to the local server.
      final result = await HttpOverrides.runWithHttpOverrides(
        () => reorderMachineProfiles(
          database: db,
          machine: machine,
          machineKey: 'meticulous',
          visible: ['z', 'x', 'y'],
        ),
        _RealHttp(),
      );

      expect(result.error, isNull);
      expect(await _order(db, 'meticulous'), ['z', 'x', 'y']);
      expect(requests.single.$1, 'POST');
      expect(requests.single.$2, '/api/v1/settings');
      expect(requests.single.$3, {
        'profile_order': ['z', 'x', 'y'],
      });
      await server.close(force: true);
    });
  });

  test('Pour Over: own order, new ones are appended', () async {
    SharedPreferences.setMockInitialValues({
      BrewRecipeStore.enabledPrefKey: ['r1', 'r2', 'r3'],
      BrewRecipeStore.knownPrefKey: ['r1', 'r2', 'r3'],
    });
    final dir = Directory.systemTemp.createTempSync('order');
    addTearDown(() => dir.deleteSync(recursive: true));
    Map<String, dynamic> recipe(String id) => {
      'id': id,
      'name': id,
      'brewer': 'V60',
      'dose_g': 20,
      'water_ml': 300,
      'ratio': '1:15',
      'water_temp_c': 92,
      'grind_size': 'coarse',
      'phases': [
        {'label': 'Bloom', 'water_g': 60, 'wait_seconds': 45},
      ],
      'source': {'name': 'Someone'},
    };
    final store = BrewRecipeStore(
      cacheFile: File('${dir.path}/c.json'),
      loadBundled: () async => jsonEncode(
        BrewRecipeBundle(
          commit: 'a',
          fetchedAt: DateTime(2026, 1, 1),
          raw: [recipe('r1'), recipe('r2'), recipe('r3')],
        ).toJson(),
      ),
    );
    await store.load();
    expect(store.enabledRecipes.map((r) => r.id), ['r1', 'r2', 'r3']);

    store.setOrder(['r3', 'r1']);
    expect(store.enabledRecipes.map((r) => r.id), ['r3', 'r1', 'r2']);

    // Survives a restart.
    await Future<void>.delayed(Duration.zero);
    final again = BrewRecipeStore(
      cacheFile: File('${dir.path}/c.json'),
      loadBundled: () async => jsonEncode(
        BrewRecipeBundle(
          commit: 'a',
          fetchedAt: DateTime(2026, 1, 1),
          raw: [recipe('r1'), recipe('r2'), recipe('r3')],
        ).toJson(),
      ),
    );
    await again.load();
    expect(again.enabledRecipes.map((r) => r.id), ['r3', 'r1', 'r2']);
  });

  testWidgets('ReorderableTileRow: long-press and drag', (tester) async {
    List<String>? reordered;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: ReorderableTileRow<String>(
              items: const ['A', 'B', 'C'],
              idOf: (s) => s,
              onReorder: (list) => reordered = list,
              itemBuilder: (context, s) => InkWell(
                onTap: () => taps++,
                child: SizedBox(width: 80, child: Center(child: Text(s))),
              ),
            ),
          ),
        ),
      ),
    );

    // A tap stays a tap.
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(reordered, isNull);

    // Long-press A and drag it behind C.
    final gesture = await tester.startGesture(tester.getCenter(find.text('A')));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(reordered, ['B', 'C', 'A']);
    expect(
      tester.getCenter(find.text('A')).dx,
      greaterThan(tester.getCenter(find.text('C')).dx),
    );
  });
}
