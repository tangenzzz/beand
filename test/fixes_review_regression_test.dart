// Findings of the review of the review fixes (2026-11). Each test describes
// the safe state. No discovery, Bluetooth or network beyond loopback servers
// on this computer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:beand/database/database.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/machines/gaggimate/gaggimate_live_shot_service.dart';
import 'package:beand/models/profile_draft.dart';
import 'package:beand/scale/acaia_driver.dart';
import 'package:beand/screens/live/add_profile_dialog.dart';
import 'package:beand/services/backup_service.dart';
import 'package:beand/services/connection_log.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/meticulous_pourover_profiles.dart';
import 'package:beand/services/machine_address_fallback.dart';
import 'package:beand/services/machine_discovery.dart';
import 'package:beand/sync/nostr/relay_connection.dart';
import 'package:beand/services/profile_image_cache.dart';
import 'package:beand/services/profile_sync_service.dart';
import 'package:beand/sync/engine/event_pager.dart';
import 'package:beand/sync/engine/event_worker.dart';
import 'package:beand/sync/engine/sync_engine.dart';
import 'package:beand/sync/engine/sync_state_store.dart';
import 'package:beand/sync/identity/identity.dart';
import 'package:beand/sync/nostr/event.dart';
import 'package:beand/sync/nostr/relay_pool.dart';
import 'package:beand/sync/records/sync_envelope.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// All requests use an injected fake or a restricted loopback connection.
class FakePool extends RelayPool {
  FakePool(SyncIdentity identity, this.answer) : super(identity: identity);
  final Future<List<NostrEvent>> Function(String, Map<String, Object>) answer;
  final sent = <NostrEvent>[];
  @override
  Future<Map<String, PublishResult>> publish(
    NostrEvent event, {
    bool force = false,
  }) async {
    sent.add(event);
    return {};
  }

  @override
  Future<List<NostrEvent>> queryOne(
    String url,
    Map<String, Object> filter, {
    bool force = false,
  }) => answer(url, filter);
}

class LocalHttp extends HttpOverrides {}

class FakeTransport implements GaggiMateTransport {
  final input = StreamController<dynamic>.broadcast(sync: true);
  final sent = <Map<String, dynamic>>[];
  @override
  Future<void> get ready => Completer<void>().future;
  @override
  Stream<dynamic> get messages => input.stream;
  @override
  void send(String data) => sent.add(jsonDecode(data) as Map<String, dynamic>);
  @override
  Future<void> close() async => input.close();
}

class FakeDiscovery extends MachineDiscovery {
  @override
  Stream<DiscoveredMachine> browse(
    String type, {
    Duration timeout = const Duration(seconds: 4),
  }) => Stream.value(
    const DiscoveredMachine(
      displayName: 'Other',
      host: 'other.invalid',
      port: 80,
      ip: '10.0.0.9',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConnectionLog.sink = (_) {};
  });
  tearDown(() => ConnectionLog.sink = null);

  test('F01 profile detail refresh cannot become an action GET', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final dir = Directory.systemTemp.createTempSync('fixes-image-');
    final socket = MeticulousSocketService(hostname: 'machine.invalid');
    final paths = <String>[];
    final sync = ProfileSyncService(
      database: db,
      socket: socket,
      imageDir: dir,
      client: MockClient((r) async {
        paths.add(r.url.path);
        return http.Response('{}', 200);
      }),
    );
    addTearDown(() async {
      sync.dispose();
      socket.dispose();
      await db.close();
      dir.deleteSync(recursive: true);
    });
    await sync.refresh('../../action/preheat');
    expect(paths, isNot(contains('/api/v1/action/preheat')));
  });

  test(
    'F02 validated image request cannot redirect to a machine action',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      server.listen((r) async {
        paths.add(r.uri.path);
        if (r.uri.path.startsWith('/api/v1/profile/image/')) {
          r.response.statusCode = 302;
          r.response.headers.set('location', '/api/v1/action/preheat');
        } else {
          r.response.write('ok');
        }
        await r.response.close();
      });
      final raw = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        LocalHttp(),
      );
      raw.findProxy = (_) => 'DIRECT';
      raw.connectionFactory = (uri, proxyHost, proxyPort) {
        if (uri.host != '127.0.0.1' || uri.port != server.port) {
          throw StateError('External networking forbidden');
        }
        return Socket.startConnect(InternetAddress.loopbackIPv4, uri.port);
      };
      final io = IOClient(raw);
      final dir = Directory.systemTemp.createTempSync('fixes-redirect-');
      addTearDown(() async {
        io.close();
        await server.close(force: true);
        dir.deleteSync(recursive: true);
      });
      await ProfileImageCache(
        client: io,
        imageDir: dir,
        hostname: () => '127.0.0.1:${server.port}',
      ).cache('/api/v1/profile/image/valid.jpg');
      expect(paths, isNot(contains('/api/v1/action/preheat')));
    },
  );

  test(
    'F03 Meticulous raw import must reject an invalid stage temperature',
    () {
      final socket = MeticulousSocketService(hostname: 'machine.invalid');
      addTearDown(socket.dispose);
      final profile = (ProfileDraft.empty()..name = 'Coffee').toJson();
      (profile['stages'] as List).first['temperature_delta'] = 'Infinity';
      expect(importProblem(socket, profile), isNotNull);
    },
  );

  test('F04 GaggiMate raw import must reject an extreme phase temperature', () {
    final machine = GaggiMateService(
      host: 'machine.invalid',
      autoReconnect: false,
    );
    addTearDown(machine.dispose);
    final profile = jsonDecode(
      File('test/fixtures/gaggimate_profile_pro.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    (profile['phases'] as List).first['temperature'] = 500;
    expect(importProblem(machine, profile), isNotNull);
  });

  NostrEvent at(String id, int second) => NostrEvent(
    id: id,
    pubkey: '',
    createdAt: second,
    kind: kindAppData,
    tags: const [],
    content: '',
    sig: '',
  );

  test('F05 a crowded second is read by raising the limit', () async {
    final events = List.generate(10, (i) => at('$i', 10));
    final seen = <String>{};
    final complete = await pageThroughEvents(
      pageSize: 2,
      query: (until, limit) async => events
          .where((e) => until == null || e.createdAt <= until)
          .take(limit)
          .toList(),
      onPage: (page) => seen.addAll(page.map((e) => e.id)),
    );
    expect(complete, isTrue);
    expect(seen, hasLength(10));
  });

  test('F05 a relay capping a crowded second still yields older events '
      'and counts as incomplete', () async {
    final events = [
      for (var i = 0; i < 10; i++) at('new$i', 10),
      at('old1', 9),
      at('old2', 8),
    ];
    final seen = <String>{};
    final complete = await pageThroughEvents(
      pageSize: 2,
      query: (until, limit) async => events
          .where((e) => until == null || e.createdAt <= until)
          .take(limit < 2 ? limit : 2)
          .toList(),
      onPage: (page) => seen.addAll(page.map((e) => e.id)),
    );
    expect(complete, isFalse);
    expect(seen, containsAll(['old1', 'old2']));
  });

  test('F05 a relay that ignores until ends the run', () async {
    final events = [at('a', 10)];
    var calls = 0;
    final complete = await pageThroughEvents(
      pageSize: 5,
      query: (until, limit) async {
        calls++;
        return events;
      },
      onPage: (_) {},
    );
    expect(complete, isFalse);
    expect(calls, lessThan(5));
  });

  test('F06 forged tags cannot displace a correctly signed event', () async {
    final identity = SyncIdentity.fromPrivateKey(Uint8List(32)..[31] = 1);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const envelope = SyncEnvelope(
      type: 'bean',
      id: 'record',
      updatedAt: 1,
      deviceId: 'a',
      deleted: false,
      data: {'name': 'real'},
    );
    final good = await sealEvent(
      keys: SyncKeys.of(identity),
      dTag: identity.dTag('bean', 'record'),
      plain: envelope.encode(),
      createdAt: 1,
    );
    final bad = NostrEvent.fromJson({
      ...good.toJson(),
      'tags': [
        ['d', 'forged'],
      ],
    });
    expect(good.isValid, isTrue);
    expect(bad.isValid, isFalse);
    final firstReturned = Completer<void>();
    final pool = FakePool(identity, (url, filter) async {
      if (url.endsWith('bad')) {
        if (!firstReturned.isCompleted) firstReturned.complete();
        return [bad];
      }
      await firstReturned.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return [good];
    })..setUrls(['wss://review.invalid/bad', 'wss://review.invalid/good']);
    addTearDown(pool.dispose);
    await SyncEngine(
      db: db,
      identity: identity,
      pool: pool,
      deviceId: 'b',
      stateStore: InMemorySyncStateStore(),
      devicePresence: false,
    ).pull(SyncReport());
    expect(await db.allBeans(), hasLength(1));
  });

  test(
    'F07 rejected preferences must preserve the original database',
    () async {
      final root = Directory.systemTemp.createTempSync('fixes-restore-');
      final prefs = await SharedPreferences.getInstance();
      final databases = <AppDatabase>[];
      addTearDown(() async {
        for (final db in databases.reversed) {
          await db.close();
        }
        root.deleteSync(recursive: true);
      });
      Future<BackupService> make(String name) async {
        final docs = Directory('${root.path}/$name')..createSync();
        final db = AppDatabase(
          NativeDatabase(File('${docs.path}/$backupDbFileName')),
        );
        databases.add(db);
        await db.insertBean(BeansCompanion.insert(name: name));
        return BackupService(db: db, docsDir: docs, prefs: prefs);
      }

      final source = await make('incoming');
      final target = await make('original');
      final zip = await source.createBackup(
        targetDir: Directory('${root.path}/export'),
      );
      final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
      final changed = Archive();
      for (final entry in archive.files) {
        final bytes = entry.name == 'prefs.json'
            ? utf8.encode('{"broken":17}')
            : entry.content as List<int>;
        changed.addFile(ArchiveFile(entry.name, bytes.length, bytes));
      }
      final hostile = File('${root.path}/bad-prefs.zip')
        ..writeAsBytesSync(ZipEncoder().encode(changed)!);
      await prefs.setString('keep', 'original');
      Object? error;
      try {
        await target.restore(hostile);
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      final raw = sql.sqlite3.open('${target.docsDir.path}/$backupDbFileName');
      final name = raw.select('SELECT name FROM beans').single['name'];
      raw.close();
      expect(
        {
          'bean': name,
          'pref': prefs.getString('keep'),
          'oldCopyExists': Directory('${target.docsDir.path}/.restore-old')
              .existsSync(),
        },
        {'bean': 'original', 'pref': 'original', 'oldCopyExists': false},
      );
    },
  );

  test('F08 a late select answer must not undo Stop standby', () async {
    final transport = FakeTransport();
    final machine = GaggiMateService(
      host: 'machine.invalid',
      transportFactory: (_) => transport,
      autoReconnect: false,
    )..connect();
    final live = GaggiMateLiveShotService(machine)..start();
    addTearDown(() {
      live.dispose();
      machine.dispose();
    });
    transport.input.add(
      jsonEncode({'tp': 'evt:status', 'm': 1, 'ct': 60.0, 'tt': 93.0}),
    );
    final selecting = machine.selectProfile('other-profile');
    final request = transport.sent.singleWhere(
      (r) => r['tp'] == 'req:profiles:select',
    );
    expect(await live.stopShot(), isTrue);
    expect(transport.sent.last, {'tp': 'req:change-mode', 'mode': 0});
    transport.input.add(
      jsonEncode({'tp': 'res:profiles:select', 'rid': request['rid']}),
    );
    await selecting;
    expect(
      transport.sent.where((r) => r['tp'] == 'req:change-mode').last['mode'],
      0,
    );
  });

  test(
    'F09 last-IP fallback must preserve the chosen machine identity',
    () async {
      final fallback = MachineAddressFallback(
        serviceType: meticulousServiceType,
        discovery: FakeDiscovery(),
        lastIp: '10.0.0.8',
      );
      expect(await fallback.nextAddress('chosen.invalid'), '10.0.0.8');
      expect(await fallback.nextAddress('10.0.0.8'), isNull);
    },
  );

  test('F10 pour-over photos must enforce the image byte cap too', () async {
    final dir = Directory.systemTemp.createTempSync('fixes-photo-cap-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final profiles = MeticulousPourOverProfiles(
      host: () => 'machine.invalid',
      photoDir: () => dir,
      client: MockClient(
        (r) async => http.Response.bytes(Uint8List(maxImageBytes + 1), 200),
      ),
    );
    expect(await profiles.fetchPhoto('valid'), isNull);
  });

  test('F11 an old pending Custom AI URL must not be published', () async {
    final identity = SyncIdentity.fromPrivateKey(Uint8List(32)..[31] = 2);
    final db = AppDatabase(NativeDatabase.memory());
    final pool = FakePool(identity, (_, _) async => []);
    addTearDown(() async {
      pool.dispose();
      await db.close();
    });
    await db.syncDao.recordSetting(
      key: 'ai_base_url',
      syncId: 'url-record',
      value: jsonEncode('https://private-ai.invalid'),
      updatedAt: 1,
      deviceId: 'local',
      state: SyncState.pending,
    );
    await SyncEngine(
      db: db,
      identity: identity,
      pool: pool,
      deviceId: 'local',
      stateStore: InMemorySyncStateStore(),
      devicePresence: false,
    ).push(SyncReport());
    final opened = await openEvents(pool.sent, SyncKeys.of(identity));
    expect(opened.where((e) => e?.data['key'] == 'ai_base_url'), isEmpty);
    // Settled without sending, so the status does not show it as waiting.
    expect(await db.syncDao.watchPendingCount().first, 0);
  });

  test('F12 cancellation while sealing must prevent a new publish', () async {
    final identity = SyncIdentity.fromPrivateKey(Uint8List(32)..[31] = 3);
    final db = AppDatabase(NativeDatabase.memory());
    final pool = FakePool(identity, (_, _) async => []);
    addTearDown(() async {
      pool.dispose();
      await db.close();
    });
    await db.insertBean(BeansCompanion.insert(name: 'local edit'));
    late SyncEngine engine;
    engine = SyncEngine(
      db: db,
      identity: identity,
      pool: pool,
      deviceId: 'local',
      stateStore: InMemorySyncStateStore(),
      devicePresence: false,
      now: () {
        // Runs while sealEvent yields to its worker isolate, before publish.
        scheduleMicrotask(engine.cancel);
        return DateTime(2026, 11, 11);
      },
    );
    await engine.push(SyncReport());
    expect(engine.cancelled, isTrue);
    expect(pool.sent, isEmpty);
  });

  test('F13 a fast local clock must not hide the next remote record', () async {
    final identity = SyncIdentity.fromPrivateKey(Uint8List(32)..[31] = 4);
    final db = AppDatabase(NativeDatabase.memory());
    final events = <NostrEvent>[];
    final pool = FakePool(
      identity,
      (_, filter) async => events
          .where(
            (e) =>
                e.createdAt >= (filter['since'] as int? ?? 0) &&
                e.createdAt <= (filter['until'] as int? ?? 100000),
          )
          .toList(),
    )..setUrls(['wss://review.invalid']);
    addTearDown(() async {
      pool.dispose();
      await db.close();
    });
    final state = InMemorySyncStateStore();
    await state.save(SyncStateData(relays: pool.urls));
    final engine = SyncEngine(
      db: db,
      identity: identity,
      pool: pool,
      deviceId: 'local',
      stateStore: state,
      devicePresence: false,
      now: () => DateTime.fromMillisecondsSinceEpoch(10000 * 1000),
    );
    Future<void> append(int time) async {
      final envelope = SyncEnvelope(
        type: 'bean',
        id: 'record-$time',
        updatedAt: time * 1000,
        deviceId: 'remote',
        deleted: false,
        data: {'name': 'bean-$time'},
      );
      events.add(
        await sealEvent(
          keys: SyncKeys.of(identity),
          dTag: identity.dTag('bean', envelope.id),
          plain: envelope.encode(),
          createdAt: time,
        ),
      );
    }

    await append(1000);
    await engine.pull(SyncReport());
    expect(await db.allBeans(), hasLength(1));
    expect((await state.load()).lastSync['wss://review.invalid'], 1000);
    await append(1001);
    await engine.pull(SyncReport());
    expect(await db.allBeans(), hasLength(2));
  });

  test('the receive cursor is the same for a relay that lags behind', () async {
    final identity = SyncIdentity.fromPrivateKey(Uint8List(32)..[31] = 5);
    final db = AppDatabase(NativeDatabase.memory());
    Future<NostrEvent> seal(int time) {
      final envelope = SyncEnvelope(
        type: 'bean',
        id: 'record-$time',
        updatedAt: time * 1000,
        deviceId: 'remote',
        deleted: false,
        data: {'name': 'bean-$time'},
      );
      return sealEvent(
        keys: SyncKeys.of(identity),
        dTag: identity.dTag('bean', envelope.id),
        plain: envelope.encode(),
        createdAt: time,
      );
    }

    final old = await seal(1000);
    final recent = await seal(2000);
    final pool =
        FakePool(
          identity,
          (url, filter) async => [if (!url.endsWith('lagging')) recent, old]
              .where((e) => e.createdAt <= (filter['until'] as int? ?? 100000))
              .toList(),
        )..setUrls([
          'wss://review.invalid/lagging',
          'wss://review.invalid/current',
        ]);
    addTearDown(() async {
      pool.dispose();
      await db.close();
    });
    final state = InMemorySyncStateStore();
    await state.save(SyncStateData(relays: pool.urls));
    await SyncEngine(
      db: db,
      identity: identity,
      pool: pool,
      deviceId: 'local',
      stateStore: state,
      devicePresence: false,
      now: () => DateTime.fromMillisecondsSinceEpoch(10000 * 1000),
    ).pull(SyncReport());
    expect((await state.load()).lastSync, {
      'wss://review.invalid/lagging': 2000,
      'wss://review.invalid/current': 2000,
    });
  });

  test(
    'F14 a complete Acaia weight may contain header bytes in its payload',
    () {
      // raw 0xDDEF = 56815 with two decimal places: 568.15 g, below 5 kg.
      // Length 8 includes itself; the two checksum bytes are F9 and E2.
      final frame = [
        0xef,
        0xdd,
        0x0c,
        8,
        5,
        0xef,
        0xdd,
        0,
        0,
        2,
        0,
        0xf9,
        0xe2,
      ];
      expect(AcaiaDriver().parse(frame).weights, [568.15]);
    },
  );

  test('F04 GaggiMate import also checks phase pressure and power', () {
    final machine = GaggiMateService(
      host: 'machine.invalid',
      autoReconnect: false,
    );
    addTearDown(machine.dispose);
    Map<String, dynamic> load() => jsonDecode(
      File('test/fixtures/gaggimate_profile_pro.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(importProblem(machine, load()), isNull);
    final pressure = load();
    ((pressure['phases'] as List)[2]['pump'] as Map)['pressure'] = 'Infinity';
    expect(importProblem(machine, pressure), isNotNull);
    final power = load();
    (power['phases'] as List)[0]['pump'] = 400;
    expect(importProblem(machine, power), isNotNull);
  });

  test('F03 a top-level temperature that is no number blocks the import', () {
    final socket = MeticulousSocketService(hostname: 'machine.invalid');
    addTearDown(socket.dispose);
    final profile = (ProfileDraft.empty()..name = 'Coffee').toJson();
    profile['temperature'] = 'NaN';
    expect(importProblem(socket, profile), isNotNull);
    profile['temperature'] = 92;
    profile['final_weight'] = 'Infinity';
    expect(importProblem(socket, profile), isNotNull);
  });

  test(
    'F09 a stand-in IP is not remembered and keeps the chosen name',
    () async {
      final fallback = MachineAddressFallback(
        serviceType: meticulousServiceType,
        discovery: FakeDiscovery(),
        lastIp: '10.0.0.8',
      );
      expect(await fallback.nextAddress('chosen.invalid'), '10.0.0.8');
      expect(fallback.isStandIn('10.0.0.8'), isTrue);
      // Connected through the IP, then dropped again.
      fallback.reset();
      expect(await fallback.nextAddress('10.0.0.8'), isNull);
    },
  );

  test('F14 a fragment cut short by a new message is still dropped', () {
    final whole = [0xef, 0xdd, 0x0c, 8, 5, 0xe8, 0x03, 0, 0, 1, 0];
    whole.addAll(_sums(whole));
    final cut = [0xef, 0xdd, 0x0c, 8, 5, 0x10];
    expect(AcaiaDriver().parse([...cut, ...whole]).weights, [100.0]);
  });
}

List<int> _sums(List<int> frame) {
  var even = 0, odd = 0;
  for (var i = 3; i < frame.length; i++) {
    if ((i - 3).isEven) {
      even = (even + frame[i]) & 0xff;
    } else {
      odd = (odd + frame[i]) & 0xff;
    }
  }
  return [even, odd];
}
