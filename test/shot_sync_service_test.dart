import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/models/machine_status.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/services/shot_sync_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeMachine extends MeticulousSocketService {
  FakeMachine() : super(hostname: 'machine.local');

  void setConnection(MachineConnectionState state) {
    connectionState = state;
    notifyListeners();
  }

  void setExtracting(bool value) {
    latestStatus = MachineStatus.fromJson({
      'name': value ? 'Percolation' : 'idle',
      'state': value ? 'brewing' : 'idle',
      'extracting': value,
    });
    notifyListeners();
  }
}

// Behaves like the machine's history (GET /api/v1/history with
// dump_data=false or ids=...), fed from the real shot in the fixture.
class FakeHistory {
  final shots = <String, Map<String, dynamic>>{};
  int imageDownloads = 0;
  bool offline = false;

  // Counter of short-list queries: lets a test tell that a sync pass really
  // happened — more reliable than waiting.
  int listings = 0;

  // Shots that exist but that the machine doesn't list yet (it saves the
  // entry only shortly after the shot).
  final _unsaved = <String>{};

  void add(String id, double time) {
    final base = Map<String, dynamic>.from(
      jsonDecode(
        File('test/fixtures/history_entry_bailey.json').readAsStringSync(),
      ) as Map,
    );
    shots[id] = {...base, 'id': id, 'time': time};
  }

  /// Like [add], but the machine only hands out the shot after [reveal].
  void addUnsaved(String id, double time) {
    add(id, time);
    _unsaved.add(id);
  }

  void reveal(String id) => _unsaved.remove(id);

  http.Client client() => MockClient((request) async {
    if (offline) throw const SocketException('unreachable');
    if (request.url.path == '/api/v1/history') {
      final ids = request.url.queryParameters['ids'];
      if (ids != null) {
        return http.Response(
          jsonEncode({
            'history': [if (shots[ids] != null) shots[ids]],
          }),
          200,
        );
      }
      listings++;
      final light = [
        for (final s
            in shots.values.toList()
              ..sort((a, b) => (b['time'] as num).compareTo(a['time'] as num)))
          if (!_unsaved.contains(s['id'])) {...s, 'data': null},
      ];
      return http.Response(jsonEncode({'history': light}), 200);
    }
    if (request.url.path.startsWith('/api/v1/profile/image/')) {
      imageDownloads++;
      return http.Response.bytes([1, 2, 3, 4], 200);
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
  late FakeMachine machine;
  late FakeHistory history;
  late ShotSetup setup;
  late Directory imageDir;
  late ShotSyncService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    machine = FakeMachine();
    history = FakeHistory();
    setup = ShotSetup.inMemory();
    imageDir = Directory.systemTemp.createTempSync('coffee_images');
    service = ShotSyncService(
      database: db,
      socket: machine,
      setup: setup,
      imageDir: imageDir,
      client: history.client(),
      // Immediately and once more clearly later: the second attempt gives a
      // test enough room to change something between passes without the
      // chain running out first. Tests where the shot is there right away
      // pay nothing for it — the chain stops after a hit.
      retryDelays: const [Duration.zero, Duration(milliseconds: 250)],
    );
  });

  tearDown(() async {
    service.dispose();
    await db.close();
    imageDir.deleteSync(recursive: true);
  });

  Future<List<ShotEntry>> shotsInDb() => db.watchShotEntries().first;

  test(
    'on connect all unknown shots are imported, without duplicates',
    () async {
      history
        ..add('a', 1789900000)
        ..add('b', 1789910000);
      service.start();
      machine.setConnection(MachineConnectionState.connected);
      await until(() async => (await shotsInDb()).length == 2);

      final shots = await shotsInDb();
      // Newest first; profile, image and time series are stored locally.
      expect(shots.first.shot.externalId, 'b');
      expect(shots.first.shot.profileName, 'Bailey - PSPH / Soup');
      expect(shots.first.shot.machine, 'meticulous');
      expect(File(shots.first.shot.profileImagePath!).existsSync(), isTrue);
      expect(
        history.imageDownloads,
        1,
        reason: 'load the same profile image only once',
      );
      expect((await db.readingsFor(shots.first.shot.id)), hasLength(40));
      // Backfilled shots don't know bean/dose/grind size.
      expect(shots.first.shot.doseGrams, isNull);
      expect(shots.first.shot.beanId, isNull);

      await service.sync();
      expect(await shotsInDb(), hasLength(2));
    },
  );

  test('shots stay when the machine drops them or is offline', () async {
    history.add('a', 1789900000);
    service.start();
    machine.setConnection(MachineConnectionState.connected);
    await until(() async => (await shotsInDb()).length == 1);

    history.shots.clear();
    await service.sync();
    history.offline = true;
    await service.sync();
    expect(await shotsInDb(), hasLength(1));
    expect(
      (await db.readingsFor((await shotsInDb()).single.shot.id)),
      isNotEmpty,
    );
  });

  test('rating and note survive another sync', () async {
    history.add('a', 1789900000);
    service.start();
    machine.setConnection(MachineConnectionState.connected);
    await until(() async => (await shotsInDb()).length == 1);
    final id = (await shotsInDb()).single.shot.id;
    await db.setShotRating(id, 5);
    await db.setShotNotes(id, 'great');

    await service.sync();
    final shot = (await shotsInDb()).single.shot;
    expect(shot.rating, 5);
    expect(shot.notes, 'great');
  });

  test(
    'live observed shot gets bean, dose and grind size from shot start',
    () async {
      final bean = await db.insertBean(
        BeansCompanion.insert(name: 'Guji', roaster: const Value('La Cabra')),
      );
      setup
        ..setBean(bean.id)
        ..setDose(18.5)
        ..setGrind(3.4);
      service.start();
      machine.setConnection(MachineConnectionState.connected);
      await service.sync();
      expect(await shotsInDb(), isEmpty);

      machine.setExtracting(true); // shot starts: snapshot of the Pre-Shot card
      setup
        ..setDose(20) // later changes no longer count for this shot
        ..setGrind(9);
      history.add('live', DateTime.now().millisecondsSinceEpoch / 1000);
      machine.setExtracting(false); // shot over -> import with retries

      await until(() async => (await shotsInDb()).length == 1);
      final entry = (await shotsInDb()).single;
      expect(entry.shot.externalId, 'live');
      expect(entry.shot.beanId, bean.id);
      expect(entry.bean!.name, 'Guji');
      expect(entry.shot.doseGrams, 18.5);
      expect(entry.shot.grindSize, '3.4');
    },
  );

  test('machine saves the shot with a delay: retries find it', () async {
    // The shot exists from the start, but the machine doesn't list it yet.
    // Whether it shows up thus depends on state and not on the clock —
    // before, this test failed sporadically when the DB query took longer
    // than the retry chain.
    history.addUnsaved('late', DateTime.now().millisecondsSinceEpoch / 1000);
    service.start();
    machine.setConnection(MachineConnectionState.connected);
    await service.sync();
    expect(await shotsInDb(), isEmpty);

    // Without a set value the dose would stay empty (no default values are
    // invented) — what's checked here is that the assignment survives the
    // retries.
    setup.setDose(17);
    machine.setExtracting(true);
    machine.setExtracting(false); // Shot vorbei -> Wiederholungen laufen an
    final before = history.listings;
    // First retry: the machine doesn't know the shot yet.
    await until(() async => history.listings > before);
    expect(await shotsInDb(), isEmpty);

    history.reveal('late'); // now the machine has saved it
    await until(() async => (await shotsInDb()).length == 1);
    expect((await shotsInDb()).single.shot.doseGrams, 17);
  });

  test('deleted bean in the setup is not linked', () async {
    final bean = await db.insertBean(BeansCompanion.insert(name: 'Weg'));
    setup.setBean(bean.id);
    await db.deleteBean(bean.id);
    service.start();
    machine.setConnection(MachineConnectionState.connected);
    await service.sync();
    machine.setExtracting(true);
    history.add('x', DateTime.now().millisecondsSinceEpoch / 1000);
    machine.setExtracting(false);
    await until(() async => (await shotsInDb()).length == 1);
    expect((await shotsInDb()).single.shot.beanId, isNull);
  });

  test('deleted shots are not imported again', () async {
    history
      ..add('a', 1789900000)
      ..add('b', 1789910000);
    service.start();
    machine.setConnection(MachineConnectionState.connected);
    await until(() async => (await shotsInDb()).length == 2);

    final toDelete = (await shotsInDb())
        .firstWhere((e) => e.shot.externalId == 'b')
        .shot
        .id;
    await db.deleteShots([toDelete]);
    await service.sync();
    await service.sync(recentOnly: true);

    final shots = await shotsInDb();
    expect(shots.map((e) => e.shot.externalId), ['a']);
    expect(history.imageDownloads, 1);
  });

  test(
    'new shots get the target temp; older imports get it backfilled',
    () async {
      // An earlier import (schema v4) didn't know the target temperature yet.
      await db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 9, 1),
          externalId: const Value('old'),
        ),
        const [],
      );
      history
        ..add('old', 1788000000)
        ..add('fresh', 1789900000);
      service.start();
      machine.setConnection(MachineConnectionState.connected);
      await until(() async => (await shotsInDb()).length == 2);

      final shots = {
        for (final e in await shotsInDb()) e.shot.externalId: e.shot,
      };
      expect(shots['fresh']!.profileTemp, 87.5);
      expect(shots['old']!.profileTemp, 87.5);
    },
  );
}
