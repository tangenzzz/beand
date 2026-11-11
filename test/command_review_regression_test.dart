// Findings of the review of machine commands and outside input (2026-11).
// Each test describes the safe state. No discovery, Bluetooth or network
// beyond loopback servers on this computer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beand/database/database.dart';
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_profile_codec.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/models/machine_profile.dart';
import 'package:beand/models/machine_sensors.dart';
import 'package:beand/models/machine_status.dart';
import 'package:beand/models/pourover_draft.dart';
import 'package:beand/models/profile_draft.dart';
import 'package:beand/models/profile_rules.dart';
import 'package:beand/models/shot_file_import.dart';
import 'package:beand/scale/acaia_driver.dart';
import 'package:beand/scale/brew_scale.dart';
import 'package:beand/screens/live/add_profile_dialog.dart';
import 'package:beand/screens/live/command_buttons_row.dart';
import 'package:beand/services/ai/ai_client.dart';
import 'package:beand/services/ai/ai_key_store.dart';
import 'package:beand/services/ai/ai_provider.dart';
import 'package:beand/services/ai/ai_service.dart';
import 'package:beand/services/ai/ai_settings.dart';
import 'package:beand/services/brew_recipe_store.dart';
import 'package:beand/services/connection_log.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/machine_address_fallback.dart';
import 'package:beand/services/machine_discovery.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/pourover_brew_service.dart';
import 'package:beand/services/profile_image_cache.dart';
import 'package:beand/services/profile_store.dart';
import 'package:beand/services/profile_sync_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Machine extends MeticulousSocketService {
  _Machine() : super(hostname: 'machine.invalid');
  final actions = <String>[];
  final uploaded = <Map<String, dynamic>>[];
  Completer<bool>? actionReply;

  @override
  void connect() => throw StateError('No real connection in tests');

  @override
  String get confirmedSessionState => 'brewing';

  @override
  Future<bool> triggerAction(String action) {
    actions.add(action);
    return actionReply?.future ?? Future.value(true);
  }

  @override
  Future<ProfileSaveResult> uploadProfile(Map<String, dynamic> json) async {
    uploaded.add(json);
    return const ProfileSaveResult.failed('not stored in tests');
  }

  void phase(String phase) {
    latestStatus = MachineStatus.fromJson({'state': 'brewing', 'name': phase});
    notifyListeners();
  }
}

class _Store implements ProfileStore {
  @override
  String get machineKey => 'meticulous';
  @override
  Future<void> sync() async {}
  @override
  Future<bool> refresh(String id) async => true;
  @override
  Future<void> forget(String id) async {}
}

class _SlowKeys extends InMemoryAiKeyStore {
  final reply = Completer<String?>();
  @override
  Future<String?> read(AiProvider provider) => reply.future;
}

class _Discovery extends MachineDiscovery {
  _Discovery(this.found);
  final DiscoveredMachine found;
  @override
  Stream<DiscoveredMachine> browse(
    String serviceType, {
    Duration timeout = const Duration(seconds: 4),
  }) => Stream.value(found);
}

class _Transport implements GaggiMateTransport {
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

class _Scale extends BrewScale {
  final values = StreamController<ScaleReading>.broadcast(sync: true);
  @override
  ScaleConnection get connection => ScaleConnection.connected;
  @override
  String get deviceName => 'Test scale';
  @override
  String? get error => null;
  @override
  double get grams => 0;
  @override
  Stream<ScaleReading> get readings => values.stream;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> tare() async {}
}

class _LocalHttp extends HttpOverrides {}

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConnectionLog.sink = (_) {};
  });
  tearDown(() => ConnectionLog.sink = null);

  group('a value from a profile never turns into another request', () {
    test('an action path as the image is not fetched', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final dir = Directory.systemTemp.createTempSync('images-');
      final machine = _Machine();
      final requests = <Uri>[];
      final sync = ProfileSyncService(
        database: db,
        socket: machine,
        imageDir: dir,
        client: MockClient((r) async {
          requests.add(r.url);
          return http.Response(
            r.url.path.endsWith('/list')
                ? jsonEncode([
                    {
                      'id': 'p',
                      'name': 'Coffee',
                      'display': {'image': '/api/v1/action/preheat'},
                    },
                  ])
                : '{"status":"ok"}',
            200,
          );
        }),
      );
      addTearDown(() async {
        sync.dispose();
        machine.dispose();
        await db.close();
        dir.deleteSync(recursive: true);
      });
      await sync.sync();
      expect(requests.map((u) => u.path), isNot(contains(contains('action'))));
    });

    test('a profile keeps only a real image path', () {
      MachineProfile parse(String image) => MachineProfile.fromJson({
        'id': 'p',
        'name': 'Coffee',
        'display': {'image': image},
      });
      expect(parse('/api/v1/action/preheat').imagePath, isNull);
      expect(parse('@elsewhere.invalid/photo.jpg').imagePath, isNull);
      expect(
        parse('/api/v1/profile/image/../../action/start').imagePath,
        isNull,
      );
      expect(
        parse('/api/v1/profile/image/4ca442f01685f913f5751ee5c04a6cdb.jpeg')
            .imagePath,
        '/api/v1/profile/image/4ca442f01685f913f5751ee5c04a6cdb.jpeg',
      );
    });

    test('a profile ID that leaves its endpoint is refused', () async {
      final machine = MeticulousSocketService(hostname: 'machine.invalid');
      addTearDown(machine.dispose);
      final requests = <Uri>[];
      await http.runWithClient(
        () async {
          await expectLater(
            machine.fetchProfileDetail('../../action/preheat'),
            throwsArgumentError,
          );
          expect(await machine.loadProfile('../action/start'), isFalse);
        },
        () => MockClient((r) async {
          requests.add(r.url);
          return http.Response('{}', 200);
        }),
      );
      expect(requests, isEmpty);
    });

    test('the image cache stays on the machine and within a size', () async {
      final dir = Directory.systemTemp.createTempSync('cache-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final requests = <Uri>[];
      var body = <int>[1, 2, 3];
      final cache = ProfileImageCache(
        imageDir: dir,
        hostname: () => 'machine.invalid',
        client: MockClient((r) async {
          requests.add(r.url);
          return http.Response.bytes(body, 200);
        }),
      );
      expect(await cache.cache('@elsewhere.invalid/photo.jpg'), isNull);
      expect(requests, isEmpty);

      expect(await cache.cache('/api/v1/profile/image/a.png'), isNotNull);
      expect(requests.single.host, 'machine.invalid');

      body = Uint8List(maxImageBytes + 1);
      expect(await cache.cache('/api/v1/profile/image/b.png'), isNull);
    });
  });

  group('the AI request keeps to one connection', () {
    test('provider, key and address belong together', () async {
      final keys = _SlowKeys();
      final settings = AiSettings(
        keyStore: keys,
        provider: AiProvider.claude,
        baseUrl: 'https://other-provider.invalid/v1',
        models: {AiProvider.compatible: 'other-model'},
      );
      final pending = settings.connection();
      await settings.setProvider(AiProvider.compatible);
      keys.reply.complete('test-claude-key');
      final connection = await pending;
      expect(connection.provider, AiProvider.claude);
      expect(connection.baseUrl, AiProvider.claude.defaultBaseUrl);
    });

    test('data goes only to the server that was allowed', () async {
      final keys = InMemoryAiKeyStore();
      await keys.write(AiProvider.compatible, 'test-custom-key');
      final settings = AiSettings(
        keyStore: keys,
        provider: AiProvider.compatible,
        baseUrl: 'https://approved.invalid/v1',
        models: {AiProvider.compatible: 'm'},
        consentedRecipients: {'approved.invalid'},
      );
      final page = Completer<http.Response>();
      final reachedPage = Completer<void>();
      final sent = <http.Request>[];
      final service = AiService(
        settings,
        httpClient: MockClient((r) async {
          if (r.url.host == 'shop.invalid') {
            reachedPage.complete();
            return page.future;
          }
          sent.add(r);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"name":"Coffee"}'},
                },
              ],
            }),
            200,
          );
        }),
      );
      final pending = service.extractBean(
        url: Uri.parse('https://shop.invalid/coffee'),
      );
      await reachedPage.future;
      await settings.setBaseUrl('https://unapproved.invalid/v1');
      page.complete(http.Response('<p>${'Coffee text ' * 10}</p>', 200));
      await pending;
      expect(sent.map((r) => r.url.host), everyElement('approved.invalid'));
    });

    for (final provider in [AiProvider.claude, AiProvider.gemini]) {
      test('a ${provider.name} key does not follow a redirect', () async {
        final destination = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final reached = <String?>[];
        final keyHeader = provider == AiProvider.claude
            ? 'x-api-key'
            : 'x-goog-api-key';
        destination.listen((r) async {
          reached.add(r.headers.value(keyHeader));
          r.response.headers.contentType = ContentType.json;
          r.response.write('{"data":[],"models":[]}');
          await r.response.close();
        });
        source.listen((r) async {
          r.response.statusCode = 302;
          r.response.headers.set(
            'location',
            'http://localhost:${destination.port}/models',
          );
          await r.response.close();
        });
        final raw = HttpOverrides.runWithHttpOverrides(
          () => HttpClient(),
          _LocalHttp(),
        );
        raw.findProxy = (_) => 'DIRECT';
        raw.connectionFactory = (uri, proxyHost, proxyPort) {
          if (!{'127.0.0.1', 'localhost'}.contains(uri.host) ||
              !{source.port, destination.port}.contains(uri.port)) {
            throw StateError('Only loopback in tests');
          }
          return Socket.startConnect(InternetAddress.loopbackIPv4, uri.port);
        };
        final io = IOClient(raw);
        addTearDown(() async {
          io.close();
          await source.close(force: true);
          await destination.close(force: true);
        });
        final client = AiClient.forConnection(
          AiConnection(
            provider: provider,
            apiKey: 'test-only-secret',
            model: 'unused',
            baseUrl: 'http://127.0.0.1:${source.port}',
          ),
          httpClient: io,
        );
        try {
          await client.listModels();
        } catch (_) {}
        expect(reached, isEmpty);
      });
    }
  });

  testWidgets('Purge sends once while its request is on the way', (
    tester,
  ) async {
    final machine = _Machine()..actionReply = Completer<bool>();
    await tester.pumpWidget(
      ChangeNotifierProvider<MeticulousSocketService>.value(
        value: machine,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: CommandButtonsRow()),
        ),
      ),
    );
    await tester.tap(find.text('Purge'));
    await tester.pump();
    await tester.tap(find.text('Purge'));
    final sent = List.of(machine.actions);
    machine.actionReply!.complete(false);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    machine.dispose();
    expect(sent, ['purge']);
  });

  group('an imported profile passes the editor rules', () {
    testWidgets('one the editor blocks does not reach the machine', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('import-');
      final unsafe = ProfileDraft.empty()
        ..name = 'Unsafe'
        ..temperature = 500;
      final file = File('${dir.path}/profile.json')
        ..writeAsStringSync(jsonEncode(unsafe.toJson()));
      final machine = _Machine();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: AddProfileDialog(
              machine: machine,
              store: _Store(),
              pickJsonFile: () async => file.path,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Upload .json file'));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      final uploaded = List.of(machine.uploaded);
      await tester.pumpWidget(const SizedBox());
      machine.dispose();
      dir.deleteSync(recursive: true);
      expect(uploaded, isEmpty);
    });

    test('real profiles still pass', () {
      final meticulous = MeticulousSocketService(hostname: 'machine.invalid');
      final gaggimate = GaggiMateService(
        host: 'machine.invalid',
        autoReconnect: false,
      );
      addTearDown(() {
        meticulous.dispose();
        gaggimate.dispose();
      });
      expect(
        importProblem(meticulous, _fixture('meticulous_example_profile.json')),
        isNull,
      );
      expect(
        importProblem(gaggimate, _fixture('gaggimate_profile_pro.json')),
        isNull,
      );
    });

    test('a GaggiMate profile is held to its setpoints', () {
      final gaggimate = GaggiMateService(
        host: 'machine.invalid',
        autoReconnect: false,
      );
      addTearDown(gaggimate.dispose);
      final hot = _fixture('gaggimate_profile_pro.json')..['temperature'] = 500;
      expect(importProblem(gaggimate, hot), isNotNull);
    });

    test('a pour over profile needs a water temperature water can have', () {
      final draft = PourOverDraft.empty();
      expect(pourOverTemperatureProblem(draft), isNull);
      draft.tempC = 500;
      expect(pourOverTemperatureProblem(draft), isNotNull);
    });
  });

  test('another machine of the same kind is not a new address', () async {
    final other = MachineAddressFallback(
      serviceType: meticulousServiceType,
      discovery: _Discovery(
        const DiscoveredMachine(
          displayName: 'Other machine',
          host: 'other.invalid',
          port: 80,
        ),
      ),
    );
    expect(await other.nextAddress('chosen.invalid'), isNull);

    final moved = MachineAddressFallback(
      serviceType: meticulousServiceType,
      discovery: _Discovery(
        const DiscoveredMachine(
          displayName: 'Mine',
          host: 'Chosen.invalid.',
          port: 80,
          ip: '10.0.0.9',
        ),
      ),
    );
    expect(await moved.nextAddress('chosen.invalid'), '10.0.0.9');
  });

  group('profile rules', () {
    test('a variable without a number is refused', () {
      final raw = (ProfileDraft.empty()..name = 'NaN').toJson();
      raw['variables'] = [
        {'key': 'p', 'name': 'Pressure', 'type': 'pressure', 'value': 'NaN'},
      ];
      final stage = (raw['stages'] as List).first as Map;
      stage['dynamics']['points'] = [
        [0, r'$p'],
        [30, r'$p'],
      ];
      expect(
        checkProfile(ProfileDraft.fromJson(raw)).any((f) => f.blocksSaving),
        isTrue,
      );
    });

    test('a stage cannot heat beyond what the header allows', () {
      final draft = ProfileDraft.empty()..name = 'Delta';
      draft.stages.first.temperatureDelta = 500;
      expect(checkProfile(draft).any((f) => f.blocksSaving), isTrue);
      draft.stages.first.temperatureDelta = -2;
      expect(checkProfile(draft).any((f) => f.blocksSaving), isFalse);
    });
  });

  group('GaggiMate target weight', () {
    test('an edited target weight goes to the machine', () {
      final draft = gaggiMateEmptyDraft()
        ..name = 'Coffee'
        ..finalWeight = 18;
      final phases = gaggiMateJsonFromDraft(draft)['phases'] as List;
      expect((phases.last as Map)['targets'].first['value'], 18);
    });

    test('an untouched one leaves the stage edit alone', () {
      final draft = gaggiMateEmptyDraft()..name = 'Coffee';
      draft.stages.last.exitTriggers
          .firstWhere((t) => t.type == 'weight')
          .value = const DraftValue.number(
        40,
      );
      final phases = gaggiMateJsonFromDraft(draft)['phases'] as List;
      expect((phases.last as Map)['targets'].first['value'], 40);
    });
  });

  group('Acaia packets', () {
    test('a fragment gives no weight', () {
      expect(
        AcaiaDriver().parse([
          0xef,
          0xdd,
          0x0c,
          0x08,
          0x05,
          0xff,
          0xff,
          0xff,
          0xff,
          0,
          0,
        ]).weights,
        isEmpty,
      );
    });

    test('fragments in a row give no weight, a whole message does', () {
      final driver = AcaiaDriver();
      final fragment = [0xef, 0xdd, 0x0c, 0x08, 0x05, 0, 0, 0, 0, 0, 0];
      for (var i = 0; i < 5; i++) {
        expect(driver.parse(fragment).weights, isEmpty);
      }
      final whole = AcaiaDriver().parse([
        0xef, 0xdd, 0x0c, 0x08, 0x05, 0xd2, 0x04, 0, 0, 1, 0, 0, 0, //
      ]);
      expect(whole.weights, [123.4]);
    });

    test('fragments do not end a running brew', () async {
      final dir = Directory.systemTemp.createTempSync('scale-end-');
      final db = AppDatabase(NativeDatabase.memory());
      final scale = _Scale();
      final store = BrewRecipeStore(
        cacheFile: File('${dir.path}/recipes.json'),
        loadBundled: () => File('assets/brew_recipes.json').readAsString(),
      );
      await store.load();
      final service = PourOverBrewService(
        scale: scale,
        recipes: store,
        setup: ShotSetup.inMemory(machineKey: 'pourover'),
        database: db,
      );
      addTearDown(() async {
        service.dispose();
        store.dispose();
        scale.dispose();
        await scale.values.close();
        await db.close();
        dir.deleteSync(recursive: true);
      });
      service.selectRecipe(store.recipes.first);
      service.setAuto(true);
      expect(await service.startShot(), isTrue);
      var at = DateTime(2026, 11, 10);
      void tick(double weight) {
        at = at.add(const Duration(milliseconds: 100));
        scale.values.add(ScaleReading(weight, at));
      }

      tick(0);
      for (var i = 0; i < 10; i++) {
        tick(100);
      }
      final driver = AcaiaDriver();
      for (var i = 0; i < 50; i++) {
        driver
            .parse(
              Uint8List.fromList([0xef, 0xdd, 0x0c, 8, 5, 0, 0, 0, 0, 0, 0]),
            )
            .weights
            .forEach(tick);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.stage, ShotStage.running);
    });
  });

  test('an unreadable GaggiMate status is dropped, not thrown', () async {
    final transport = _Transport();
    final machine = GaggiMateService(
      host: 'fake.invalid',
      autoReconnect: false,
      transportFactory: (_) => transport,
    );
    final errors = <Object>[];
    await runZonedGuarded(() async {
      machine.connect();
      transport.input.add('{"tp":"evt:status","process":{"a":1,"e":"NaN"}}');
      await Future<void>.delayed(Duration.zero);
      machine.dispose();
    }, (e, _) => errors.add(e));
    expect(errors, isEmpty);
  });

  test('shot file numbers that are no numbers are left out', () {
    final parsed = parseShotFile(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'elapsed': [0, 1],
            'pressure': {
              'pressure': ['NaN', 9],
            },
            'totals': {
              'weight': [0, 'Infinity'],
            },
          }),
        ),
      ),
    );
    expect(parsed.finalWeight?.isFinite ?? true, isTrue);
    expect(parsed.readings.first(1).pressure.value?.isFinite ?? true, isTrue);
  });

  test('a machine name the user chose stays out of the log', () {
    expect(ConnectionLog.machineLabel('espresso.alice.example'), '<machine>');
    expect(ConnectionLog.machineLabel('meticulous.local'), 'meticulous.local');
    expect(ConnectionLog.machineLabel('192.168.1.50'), '<ip>');
  });

  group('Auto Start', () {
    test('a short return to heating does not start again', () async {
      final machine = _Machine()..targetTemperature = 93;
      machine.latestSensors = MachineSensors.fromJson({
        't_bar_up': 93,
        't_bar_mu': 93,
        't_bar_md': 93,
        't_bar_down': 93,
      });
      machine.phase('click to start');
      final live = MeticulousLiveShotService(machine)
        ..setAutoStart(true)
        ..start();
      addTearDown(() {
        live.dispose();
        machine.dispose();
      });
      await Future<void>.delayed(const Duration(milliseconds: 10100));
      machine.phase('click to start');
      expect(machine.actions, ['continue']);
      machine.phase('heating');
      machine.phase('click to start');
      expect(machine.actions, ['continue']);

      // Once the shot it started has run, the next cycle starts again.
      machine.phase('preinfusion');
      machine.phase('heating');
      machine.phase('click to start');
      await Future<void>.delayed(const Duration(milliseconds: 10100));
      machine.phase('click to start');
      expect(machine.actions, ['continue', 'continue']);
    });
  });

  test('a profile chosen on one GaggiMate does not heat the next', () async {
    final a = _Transport(), b = _Transport();
    final machine = GaggiMateService(
      host: 'a.invalid',
      autoReconnect: false,
      transportFactory: (u) => u.host == 'a.invalid' ? a : b,
    );
    machine.connect();
    final selecting = machine.selectProfile('profile-on-a');
    final request = a.sent.single;
    a.input.add(
      jsonEncode({'tp': 'res:profiles:select', 'rid': request['rid']}),
    );
    machine.updateHost('b.invalid');
    await selecting;
    final sentToB = List.of(b.sent);
    machine.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(sentToB.where((m) => m['tp'] == 'req:change-mode'), isEmpty);
  });
}
