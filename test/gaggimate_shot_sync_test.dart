import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beand/database/database.dart';
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/machines/gaggimate/gaggimate_shot_sync_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeTransport implements GaggiMateTransport {
  final _incoming = StreamController<dynamic>.broadcast();

  @override
  Future<void> get ready async {}

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(String data) {}

  @override
  Future<void> close() async => _incoming.close();

  void receive(Map<String, dynamic> frame) => _incoming.add(jsonEncode(frame));
}

// Plays the machine's HTTP history: index.bin and the .slog files are real
// files from the simulator. Every id gets the same data series — for the
// sync only which ids get imported matters, not their content.
class FakeHistoryServer {
  FakeHistoryServer();

  int indexRequests = 0;
  bool offline = false;
  // The machine serves only these ids; the index lists three.
  Set<int> availableLogs = {0, 1, 2};

  late final Uint8List _index = File(
    'test/fixtures/gaggimate_history_index.bin',
  ).readAsBytesSync();
  late final Uint8List _log = File('test/fixtures/gaggimate_shot_000002.slog')
      .readAsBytesSync();

  http.Client client() => MockClient((request) async {
    if (offline) throw const SocketException('unreachable');
    final path = request.url.path;
    if (path == '/api/history/index.bin') {
      indexRequests++;
      return http.Response.bytes(_index, 200);
    }
    final match = RegExp(r'^/api/history/(\d{6})\.slog$').firstMatch(path);
    if (match != null && availableLogs.contains(int.parse(match.group(1)!))) {
      return http.Response.bytes(_log, 200);
    }
    return http.Response('not found', 404);
  });
}

Future<void> until(Future<bool> Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Condition not met in time');
}

void main() {
  late AppDatabase db;
  late FakeTransport transport;
  late GaggiMateService machine;
  late FakeHistoryServer server;
  late ShotSetup setup;
  late GaggiMateShotSyncService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    transport = FakeTransport();
    machine = GaggiMateService(
      host: 'gaggimate.local',
      transportFactory: (_) => transport,
      autoReconnect: false,
    );
    server = FakeHistoryServer();
    setup = ShotSetup.inMemory();
    service = GaggiMateShotSyncService(
      database: db,
      machine: machine,
      setup: setup,
      client: server.client(),
    );
  });

  tearDown(() async {
    service.dispose();
    machine.dispose();
    await db.close();
  });

  Future<List<ShotEntry>> shotsInDb() => db.watchShotEntries().first;

  // Puts the service into the connected state (a status frame counts as the
  // handshake for the machine).
  Future<void> connect() async {
    service.start();
    machine.connect();
    transport.receive({'tp': 'evt:status', 'm': 1});
    await until(
      () async => machine.connectionState == MachineConnectionState.connected,
    );
  }

  test('on connect all shots of the index land in the DB', () async {
    await connect();
    await until(() async => (await shotsInDb()).length == 3);

    final shots = await shotsInDb();
    expect(shots.map((e) => e.shot.externalId).toSet(), {
      'gaggimate:000000',
      'gaggimate:000001',
      'gaggimate:000002',
    });
    // All carry the machine — the badge in the history depends on it.
    expect(shots.every((e) => e.shot.machine == 'gaggimate'), isTrue);

    final newest = shots.first.shot;
    expect(newest.profileName, 'Copy of Default');
    expect(newest.durationMs, isNotNull);
    expect(newest.brewTemp, closeTo(92.7, 0.5));
    // The data series is attached to the shot.
    final readings = await db.readingsFor(newest.id);
    expect(readings, hasLength(102));
    expect(readings.first.pressure, closeTo(4.7, 0.001));
    // One boiler sensor: the temperature is on the boiler band.
    expect(readings.first.barUp, closeTo(93.0, 0.001));
  });

  test('a second pass imports nothing twice', () async {
    await connect();
    await until(() async => (await shotsInDb()).length == 3);

    await service.sync();
    expect((await shotsInDb()).length, 3);
    expect(server.indexRequests, greaterThanOrEqualTo(2));
  });

  test('evt:history-shot-saved triggers the import', () async {
    // Before the brew the machine knows only two data series.
    server.availableLogs = {0, 1};
    await connect();
    await until(() async => (await shotsInDb()).length == 2);

    server.availableLogs = {0, 1, 2};
    transport.receive({'tp': 'evt:history-shot-saved', 'id': 2});
    await until(() async => (await shotsInDb()).length == 3);
  });

  test(
    'bean, dose and grind size of the brew attach to the new shot',
    () async {
      final beanId = await db
          .into(db.beans)
          .insert(BeansCompanion.insert(name: 'Testbohne'));
      setup
        ..setBean(beanId)
        ..setDose(17.5)
        ..setGrind(3.2);

      // Only the shot currently being pulled may get the setup.
      server.availableLogs = {0, 1};
      await connect();
      await until(() async => (await shotsInDb()).length == 2);

      // Brew running …
      transport.receive({
        'tp': 'evt:status',
        'process': {'a': 1, 's': 'brew', 'l': 'Brew', 'e': 500, 'u': 0},
      });
      // … and over.
      transport.receive({
        'tp': 'evt:status',
        'process': {'a': 0, 's': 'brew', 'l': 'Finished', 'e': 27500, 'u': 0},
      });
      server.availableLogs = {0, 1, 2};
      transport.receive({'tp': 'evt:history-shot-saved', 'id': 2});
      await until(() async => (await shotsInDb()).length == 3);

      final newest = (await shotsInDb()).first.shot;
      expect(newest.externalId, 'gaggimate:000002');
      expect(newest.beanId, beanId);
      expect(newest.doseGrams, 17.5);
      expect(newest.grindSize, '3.2');
      // The older imports stay unassigned.
      final others = (await shotsInDb()).skip(1);
      expect(others.every((e) => e.shot.beanId == null), isTrue);
    },
  );

  // Observed on the simulator: the machine reports the saved shot while its
  // process is still running in the status. Whoever records the assignment
  // only at process end loses it here.
  test('assignment survives when the event comes before process end', () async {
    final beanId = await db
        .into(db.beans)
        .insert(BeansCompanion.insert(name: 'Testbohne'));
    setup
      ..setBean(beanId)
      ..setDose(16)
      ..setGrind(4);

    server.availableLogs = {0, 1};
    await connect();
    await until(() async => (await shotsInDb()).length == 2);

    transport.receive({
      'tp': 'evt:status',
      'process': {'a': 1, 's': 'brew', 'l': 'Brew', 'e': 500, 'u': 0},
    });
    // First the event …
    server.availableLogs = {0, 1, 2};
    transport.receive({'tp': 'evt:history-shot-saved', 'id': 2});
    // … and only then the process switches to "finished".
    transport.receive({
      'tp': 'evt:status',
      'process': {'a': 0, 's': 'brew', 'l': 'Finished', 'e': 27500, 'u': 0},
    });
    await until(() async => (await shotsInDb()).length == 3);

    final newest = (await shotsInDb()).first.shot;
    expect(newest.externalId, 'gaggimate:000002');
    expect(newest.beanId, beanId);
    expect(newest.doseGrams, 16);
    expect(newest.grindSize, '4.0');
  });

  test('a failed fetch does not lose the assignment', () async {
    final beanId = await db
        .into(db.beans)
        .insert(BeansCompanion.insert(name: 'Testbohne'));
    setup
      ..setBean(beanId)
      ..setDose(18)
      ..setGrind(2.5);

    server.availableLogs = {0, 1};
    await connect();
    await until(() async => (await shotsInDb()).length == 2);

    transport.receive({
      'tp': 'evt:status',
      'process': {'a': 1, 's': 'brew', 'l': 'Brew', 'e': 500, 'u': 0},
    });
    transport.receive({
      'tp': 'evt:status',
      'process': {'a': 0, 's': 'brew', 'l': 'Finished', 'e': 27500, 'u': 0},
    });

    // The machine reports the shot but doesn't hand out the file yet.
    transport.receive({'tp': 'evt:history-shot-saved', 'id': 2});
    await until(() async => server.indexRequests >= 2);
    expect((await shotsInDb()).length, 2);

    // Second attempt: the assignment must still be there now.
    server.availableLogs = {0, 1, 2};
    await service.sync();
    await until(() async => (await shotsInDb()).length == 3);
    final newest = (await shotsInDb()).first.shot;
    expect(newest.externalId, 'gaggimate:000002');
    expect(newest.beanId, beanId);
    expect(newest.doseGrams, 18);
  });

  test('an unreachable machine aborts the sync cleanly', () async {
    server.offline = true;
    await connect();
    await service.sync();
    expect(await shotsInDb(), isEmpty);

    server.offline = false;
    await service.sync();
    expect((await shotsInDb()).length, 3);
  });

  test('the Post-Shot card only gets shots of its machine', () async {
    // A Meticulous shot that comes AFTER the GaggiMate shots in time.
    await db.insertShotWithReadings(
      ShotsCompanion.insert(
        timestamp: DateTime.now().add(const Duration(days: 1)),
        externalId: const Value('met-1'),
        profileName: const Value('Soup Test'),
      ),
      const [],
    );
    await connect();
    await until(() async => (await shotsInDb()).length == 4);

    final forGaggimate = await db
        .watchLatestShotEntry(machine: 'gaggimate')
        .first;
    final forMeticulous = await db
        .watchLatestShotEntry(machine: 'meticulous')
        .first;
    expect(forGaggimate!.shot.profileName, 'Copy of Default');
    expect(forMeticulous!.shot.profileName, 'Soup Test');
    // Without a restriction still the most recent shot overall.
    expect((await db.watchLatestShotEntry().first)!.shot.externalId, 'met-1');
  });
}
