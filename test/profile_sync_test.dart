import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/profile_sync_service.dart';
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
}

List<Map<String, dynamic>> _profiles() => [
  for (final p in jsonDecode(
    File('test/fixtures/profiles_sample.json').readAsStringSync(),
  ) as List)
    Map<String, dynamic>.from(p as Map),
];

Future<void> until(Future<bool> Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not met in time');
}

void main() {
  late AppDatabase db;
  late FakeMachine machine;
  late Directory imageDir;
  late ProfileSyncService service;
  late List<Map<String, dynamic>> onMachine;
  var offline = false;
  var imageDownloads = 0;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    machine = FakeMachine();
    imageDir = Directory.systemTemp.createTempSync('profile_sync_imgs');
    onMachine = _profiles();
    offline = false;
    imageDownloads = 0;
    service = ProfileSyncService(
      database: db,
      socket: machine,
      imageDir: imageDir,
      client: MockClient((request) async {
        if (offline) throw const SocketException('unreachable');
        final path = request.url.path;
        if (path == '/api/v1/profile/list') {
          expect(request.url.queryParameters['full'], 'true');
          return http.Response(jsonEncode(onMachine), 200);
        }
        if (path.startsWith('/api/v1/profile/get/')) {
          final id = path.split('/').last;
          final match = onMachine.where((p) => p['id'] == id);
          return match.isEmpty
              ? http.Response('nope', 404)
              : http.Response(jsonEncode(match.first), 200);
        }
        if (path.startsWith('/api/v1/profile/image/')) {
          imageDownloads++;
          return http.Response.bytes([9, 9, 9], 200);
        }
        return http.Response('not found', 404);
      }),
    );
  });

  tearDown(() async {
    service.dispose();
    await db.close();
    imageDir.deleteSync(recursive: true);
  });

  test(
    'on connect all profiles with images are stored locally, in machine order',
    () async {
      service.start();
      machine.setConnection(MachineConnectionState.connected);
      await until(() async => (await db.storedProfilesById()).length == 3);

      final stored = await db.watchStoredProfiles().first;
      expect(stored.map((p) => p.name), [
        "Damian's LRv2",
        'Bailey - PSPH / Soup',
        'Turbo',
      ]);
      expect(stored.map((p) => p.position), [0, 1, 2]);
      // Full definition (stages, variables, description) is stored.
      final turbo = jsonDecode(stored.last.json) as Map;
      expect(turbo['stages'], isNotEmpty);
      expect(
        (turbo['display'] as Map)['description'],
        contains('Immediately ramps-up'),
      );
      // Images are stored locally.
      for (final p in stored) {
        expect(p.imagePath, isNotNull);
        expect(File(p.imagePath!).existsSync(), isTrue);
      }
      expect(imageDownloads, 3);
    },
  );

  test(
    'a repeated sync does not rewrite unchanged data or reload images',
    () async {
      await service.sync();
      final first = (await db.storedProfilesById()).map(
        (k, v) => MapEntry(k, v.fetchedAt),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await service.sync();
      final second = (await db.storedProfilesById()).map(
        (k, v) => MapEntry(k, v.fetchedAt),
      );
      expect(second, first, reason: 'nothing changed -> no new rows');
      expect(imageDownloads, 3);
    },
  );

  test('changed profiles are updated, order follows the machine', () async {
    await service.sync();
    onMachine[2]['name'] = 'Turbo v2';
    (onMachine[2]['display'] as Map)['description'] = 'New text';
    onMachine = onMachine.reversed.toList();
    await service.sync();

    final stored = await db.watchStoredProfiles().first;
    expect(stored.map((p) => p.name), [
      'Turbo v2',
      'Bailey - PSPH / Soup',
      "Damian's LRv2",
    ]);
    expect(jsonDecode(stored.first.json)['display']['description'], 'New text');
    expect(stored, hasLength(3), reason: 'same IDs: updated, not duplicated');
  });

  test(
    'profiles stay local when the machine deletes them or is unreachable',
    () async {
      await service.sync();
      onMachine.removeAt(1);
      await service.sync();
      offline = true;
      await service.sync();
      final names = (await db.watchStoredProfiles().first)
          .map((p) => p.name)
          .toList();
      expect(
        names,
        containsAll(["Damian's LRv2", 'Bailey - PSPH / Soup', 'Turbo']),
      );
    },
  );

  test(
    'refresh(id) updates a profile and returns false without the machine',
    () async {
      await service.sync();
      final id = onMachine[2]['id'] as String;
      onMachine[2]['temperature'] = 88;
      expect(await service.refresh(id), isTrue);
      expect(
        jsonDecode((await db.storedProfilesById())[id]!.json)['temperature'],
        88,
      );

      offline = true;
      expect(await service.refresh(id), isFalse);
      expect(await service.refresh('unknown'), isFalse);
      expect(
        (await db.storedProfilesById())[id],
        isNotNull,
        reason: 'copy stays',
      );
    },
  );

  test('refreshing a profile unknown on the machine changes nothing', () async {
    expect(await service.refresh('does-not-exist'), isFalse);
    expect(await db.storedProfilesById(), isEmpty);
  });

  test(
    'image that cannot be loaded: profile is still stored without an image',
    () async {
      final failing = ProfileSyncService(
        database: db,
        socket: machine,
        imageDir: imageDir,
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/profile/list') {
            return http.Response(jsonEncode(onMachine), 200);
          }
          return http.Response('boom', 500);
        }),
      );
      await failing.sync();
      final stored = await db.watchStoredProfiles().first;
      expect(stored, hasLength(3));
      expect(stored.every((p) => p.imagePath == null), isTrue);
      failing.dispose();
    },
  );
}
