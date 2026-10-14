import 'dart:async';
import 'dart:convert';

import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_profile.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/machines/gaggimate/gaggimate_live_shot_service.dart';
import 'package:beand/machines/gaggimate/gaggimate_status.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/models/machine_status.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Fake WebSocket: the test pushes frames in and records what the app sends
// out — without a machine and without a simulator.
class FakeTransport implements GaggiMateTransport {
  final _incoming = StreamController<dynamic>.broadcast();
  final sent = <Map<String, dynamic>>[];
  bool closed = false;

  @override
  Future<void> get ready async {}

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(String data) =>
      sent.add(Map<String, dynamic>.from(jsonDecode(data) as Map));

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }

  void receive(Map<String, dynamic> frame) => _incoming.add(jsonEncode(frame));

  Map<String, dynamic> lastOf(String type) =>
      sent.lastWhere((m) => m['tp'] == type);
}

// Transport whose handshake fails — like a machine whose name doesn't
// resolve.
class UnreachableTransport implements GaggiMateTransport {
  final _incoming = StreamController<dynamic>.broadcast();

  @override
  Future<void> get ready => Future.error(StateError('Failed host lookup'));

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(String data) {}

  @override
  Future<void> close() async => _incoming.close();
}

void main() {
  _meticulousKeepsItsRule();

  group('GaggiMateStatus.merge', () {
    test('missing field keeps the last value', () {
      final first = GaggiMateStatus.empty.merge({
        'tp': 'evt:status',
        'ct': 92.5,
        'tt': 93.0,
      });
      // Slow-state frame without telemetry: the temperature must not drop out.
      final second = first.merge({'tp': 'evt:status', 'p': 'Slay-ish'});

      expect(second.currentTemp, 92.5);
      expect(second.targetTemp, 93.0);
      expect(second.profileLabel, 'Slay-ish');
    });

    test('explicit null clears the value', () {
      final first = GaggiMateStatus.empty.merge({
        'tp': 'evt:status',
        'ct': 92.5,
      });
      final second = first.merge({'tp': 'evt:status', 'ct': null});

      expect(second.currentTemp, isNull);
    });

    test('sys is merged field by field', () {
      final first = GaggiMateStatus.empty.merge({
        'tp': 'evt:status',
        'sys': {'s': 'starting', 'm': 'Heating up', 'c': 0},
      });
      final second = first.merge({
        'tp': 'evt:status',
        'sys': {'s': 'ready', 'm': ''},
      });

      expect(second.systemState, 'ready');
      expect(second.systemMessage, '');
      expect(second.controllerError, 0);
      expect(second.systemStatus, MachineSystemStatus.ready);
    });

    test('warnings: only active and severity 2 blocks', () {
      final status = GaggiMateStatus.empty.merge({
        'tp': 'evt:status',
        'warn': [
          {'k': 'water', 'l': 2, 'a': true},
          {'k': 'flush', 'l': 1, 'a': true},
          {'k': 'switch', 'l': 2, 'a': false},
        ],
      });

      expect(status.warnings.length, 3);
      expect(status.warnings.where((w) => w.isBlocking).map((w) => w.key), [
        'water',
      ]);
      expect(status.warnings.where((w) => w.isVisible).map((w) => w.key), [
        'water',
        'flush',
      ]);
    });

    test('process: 0/1 counts as bool, null clears it', () {
      final running = GaggiMateStatus.empty.merge({
        'tp': 'evt:status',
        'process': {'a': 1, 's': 'brew', 'l': 'Extraction', 'e': 12500, 'u': 0},
      });
      expect(running.process!.active, isTrue);
      expect(running.process!.utility, isFalse);
      expect(running.process!.elapsed, const Duration(milliseconds: 12500));
      expect(running.systemStatus, MachineSystemStatus.busy);

      final cleared = running.merge({'tp': 'evt:status', 'process': null});
      expect(cleared.process, isNull);
    });

    test('machine mode comes from the firmware constants', () {
      final status = GaggiMateStatus.empty.merge({'tp': 'evt:status', 'm': 2});
      expect(status.mode, GaggiMateMode.steam);
      expect(GaggiMateMode.fromCode(9), isNull);
    });
  });

  group('GaggiMateProfile', () {
    test('target weight comes from the volumetric target of the phases', () {
      final profile = GaggiMateProfile.fromJson({
        'id': 'p1',
        'label': 'Londinium',
        'description': '',
        'temperature': 93,
        'favorite': true,
        'phases': [
          {
            'name': 'Pre-infusion',
            'duration': 10,
            'targets': [
              {'type': 'pressure', 'value': 3},
            ],
          },
          {
            'name': 'Brew',
            'duration': 25,
            'targets': [
              {'type': 'volumetric', 'value': 36},
            ],
          },
        ],
      });

      expect(profile.label, 'Londinium');
      expect(profile.targetWeight, 36);
      expect(profile.phaseCount, 2);
      expect(profile.totalDuration, const Duration(seconds: 35));
      expect(profile.favorite, isTrue);
    });
  });

  group('GaggiMateService', () {
    late FakeTransport transport;
    late GaggiMateService service;

    setUp(() {
      transport = FakeTransport();
      service = GaggiMateService(
        host: 'gaggimate.local',
        transportFactory: (_) => transport,
        autoReconnect: false,
      )..connect();
    });

    tearDown(() => service.dispose());

    test('connects and requests the profile list', () async {
      await pumpEventQueue();
      expect(service.connectionState, MachineConnectionState.connected);
      expect(transport.sent.single['tp'], 'req:profiles:list');
      expect(transport.sent.single['rid'], isNotEmpty);
    });

    // Found on the simulator: the app showed a green dot and "Connected to
    // gaggimate.local" while in reality every connection attempt failed at
    // the hostname — WebSocketChannel.connect returns immediately, the
    // handshake only runs afterwards.
    test('failed handshake does NOT report connected', () async {
      final broken = GaggiMateService(
        host: 'gibtsnicht.local',
        transportFactory: (_) => UnreachableTransport(),
        autoReconnect: false,
      )..connect();
      addTearDown(broken.dispose);

      expect(broken.connectionState, MachineConnectionState.connecting);
      await pumpEventQueue();
      expect(broken.connectionState, MachineConnectionState.error);
      expect(broken.lastError, contains('Failed host lookup'));
    });

    test('status frames land in the normalized live state', () async {
      transport.receive({
        'tp': 'evt:status',
        'ct': 91.8,
        'tt': 93.0,
        'cp': true,
        'pr': 8.4,
        'bc': true,
        'cw': 21.5,
        'p': 'Slay-ish',
        'process': {'a': 1, 's': 'brew', 'l': 'Extraction', 'e': 9000, 'u': 0},
      });
      await pumpEventQueue();

      final live = service.liveState;
      expect(live.temperature, 91.8);
      expect(live.targetTemperature, 93.0);
      expect(live.pressure, 8.4);
      expect(live.weight, 21.5);
      expect(live.extracting, isTrue);
      expect(live.shotTime, const Duration(seconds: 9));
      expect(live.activeProfileName, 'Slay-ish');
      expect(service.capabilities.pressure, isTrue);
      expect(service.capabilities.weight, isTrue);
    });

    test('without pressure control, pressure and flow stay empty', () async {
      transport.receive({'tp': 'evt:status', 'ct': 90.0, 'pr': 0.0, 'fl': 0.0});
      await pumpEventQueue();

      expect(service.liveState.pressure, isNull);
      expect(service.liveState.flow, isNull);
      expect(service.capabilities.pressure, isFalse);
    });

    test('response is matched via the mirrored rid', () async {
      final future = service.fetchProfiles();
      final rid = transport.lastOf('req:profiles:list')['rid'];

      // A foreign rid must not resolve the request.
      transport.receive({
        'tp': 'res:profiles:list',
        'rid': 'fremd',
        'profiles': [],
      });
      transport.receive({
        'tp': 'res:profiles:list',
        'rid': rid,
        'profiles': [
          {'id': 'a', 'label': 'Espresso', 'phases': [], 'temperature': 93},
          {'id': 'b', 'label': 'Backflush', 'phases': [], 'utility': true},
        ],
      });

      final profiles = await future;
      // Utility profiles (backflush) don't belong in the shot selection.
      expect(profiles.map((p) => p.name), ['Espresso']);
      expect(service.profiles.length, 2);
    });

    test('start/stop and flush use the real message types', () async {
      await service.sendCommand(MachineCommand.start);
      expect(transport.sent.last['tp'], 'req:process:activate');

      await service.sendCommand(MachineCommand.stop);
      expect(transport.sent.last['tp'], 'req:process:deactivate');

      unawaited(service.sendCommand(MachineCommand.flushStart));
      await pumpEventQueue();
      expect(transport.lastOf('req:flush:start')['rid'], isNotEmpty);

      // Cancelling does NOT go via req:flush:stop: in the firmware that
      // means "button released" (onFlushRelease) and only ends the hold
      // phase of a flush without a fixed duration. With a configured flush
      // duration it would run to completion (measured on the simulator).
      await service.sendCommand(MachineCommand.flushStop);
      expect(transport.sent.last['tp'], 'req:process:deactivate');
    });

    test('blocked start asks for confirmation', () async {
      transport.receive({
        'tp': 'evt:brew:confirm',
        'warn': [
          {'k': 'water', 'l': 2},
        ],
      });
      await pumpEventQueue();

      // evt:brew:confirm lacks the `a` field — the warnings are active.
      expect(service.pendingBrewConfirmation!.single.key, 'water');
      expect(service.pendingBrewConfirmation!.single.isBlocking, isTrue);

      service.confirmBrew();
      expect(service.pendingBrewConfirmation, isNull);
      expect(transport.sent.last, {
        'tp': 'req:process:activate',
        'ignoreWarnings': true,
      });
    });

    test('dismissal by another client closes our own dialog', () async {
      transport.receive({
        'tp': 'evt:brew:confirm',
        'warn': [
          {'k': 'water', 'l': 2},
        ],
      });
      await pumpEventQueue();
      expect(service.pendingBrewConfirmation, isNotNull);

      transport.receive({'tp': 'evt:brew:confirm:cancel'});
      await pumpEventQueue();
      expect(service.pendingBrewConfirmation, isNull);
    });
  });

  // The three cards are the same as for the Meticulous — only the state
  // driving them comes from the GaggiMate's process block here.
  group('GaggiMateLiveShotService', () {
    late FakeTransport transport;
    late GaggiMateService machine;
    late GaggiMateLiveShotService live;

    setUp(() {
      transport = FakeTransport();
      machine = GaggiMateService(
        host: 'gaggimate.local',
        transportFactory: (_) => transport,
        autoReconnect: false,
      )..connect();
      live = GaggiMateLiveShotService(machine)..start();
    });

    tearDown(() {
      live.dispose();
      machine.dispose();
    });

    Future<void> status(Map<String, dynamic> frame) async {
      transport.receive({'tp': 'evt:status', ...frame});
      await pumpEventQueue();
    }

    test('mode and temperature yield idle / heating / ready', () async {
      await status({'m': 0, 'ct': 92.0, 'tt': 93.0});
      expect(live.stage, ShotStage.idle);

      // Brew mode, but still cold.
      await status({'m': 1, 'ct': 60.0});
      expect(live.stage, ShotStage.heating);
      expect(live.activeCard, ActiveCard.pre);

      await status({'ct': 92.0});
      expect(live.stage, ShotStage.ready);
      expect(live.targetTemperature, 93.0);
    });

    // Regression: the profile could never be selected and the start button
    // pulsed constantly. The reason was the Meticulous rule "locked once no
    // longer idle" — but the GaggiMate is permanently "ready" in Brew mode.
    test('profile stays selectable while no brew is running', () async {
      await status({'m': 0, 'ct': 92.0, 'tt': 93.0});
      expect(live.stage, ShotStage.idle);
      expect(live.profileLocked, isFalse);

      // Brew mode, heating: for the Meticulous this would be the end.
      await status({'m': 1, 'ct': 60.0});
      expect(live.stage, ShotStage.heating);
      expect(live.profileLocked, isFalse);

      await status({'ct': 92.0});
      expect(live.stage, ShotStage.ready);
      expect(live.profileLocked, isFalse, reason: 'steady state, no run');

      // Only the brew itself locks.
      await status({
        'process': {'a': 1, 's': 'brew', 'l': 'Extraction', 'e': 2000, 'u': 0},
      });
      expect(live.stage, ShotStage.running);
      expect(live.profileLocked, isTrue);

      // And stays locked as long as the result is on the Post card.
      await status({
        'process': {'a': 0, 's': 'brew', 'l': 'Finished', 'e': 27000, 'u': 0},
      });
      expect(live.stage, ShotStage.purging);
      expect(live.profileLocked, isTrue);

      // Free again after saving.
      live.confirmPostShot();
      await status({'process': null});
      expect(live.profileLocked, isFalse);
    });

    test('the start button does not pulse constantly here', () async {
      await status({'m': 1, 'ct': 93.0, 'tt': 93.0});
      expect(live.stage, ShotStage.ready);
      expect(live.pulsesWhenReady, isFalse);
    });

    // Auto Start waits for the moment the machine becomes ready — that
    // doesn't exist here, so it would be an immediate start.
    test('no Auto Start, and it triggers nothing', () async {
      expect(live.supportsAutoStart, isFalse);

      live.setAutoStart(true);
      await status({'m': 1, 'ct': 93.0, 'tt': 93.0});
      expect(live.stage, ShotStage.ready);
      // If it were supported, there would be a start here after the hold time.
      expect(
        transport.sent.any((m) => m['tp'] == 'req:process:activate'),
        isFalse,
      );
    });

    test(
      'steam mode: dual boiler shows the steam boiler, single boiler does not',
      () async {
        // Dual boiler (db=1): in steam mode `tt` stays the brew target, the
        // steam target is only in `tst` — exactly as in the machine's UI
        // (DefaultUI.cpp). Verified on the simulator.
        await status({
          'db': true,
          'm': 1,
          'ct': 93.0,
          'tt': 93.0,
          'cst': 133.0,
          'tst': 135.0,
        });
        expect(machine.liveState.temperature, 93.0);
        expect(machine.liveState.targetTemperature, 93.0);

        await status({'m': 2});
        expect(machine.liveState.temperature, 133.0);
        expect(machine.liveState.targetTemperature, 135.0);

        // Back in brew mode, the brew boiler again.
        await status({'m': 1});
        expect(machine.liveState.temperature, 93.0);
        expect(machine.liveState.targetTemperature, 93.0);

        // Single boiler: there the firmware already delivers the steam target
        // in `tt`; switching would be wrong.
        await status({'db': false, 'm': 2, 'tt': 135.0});
        expect(machine.liveState.temperature, 93.0);
        expect(machine.liveState.targetTemperature, 135.0);
      },
    );

    test('steam and water runs are not a shot: no card, no curve', () async {
      // The firmware only fills the process block for Brew and Grind — a
      // steam or water run only reports {"a": 1}, without `u`. Verified on
      // the simulator.
      await status({'m': 1, 'ct': 93.0, 'tt': 93.0, 'cp': true});
      await status({
        'process': {'a': 1, 's': 'brew', 'l': 'Extraction', 'e': 4000, 'u': 0},
        'pr': 8.0,
      });
      expect(live.stage, ShotStage.running);
      expect(live.liveReadings, isNotEmpty);

      // Brew finished, result waiting on the Post card.
      await status({
        'process': {'a': 0, 's': 'brew', 'l': 'Finished', 'e': 26000, 'u': 0},
      });
      expect(live.stage, ShotStage.purging);

      // Cleared: the brew's curve is done.
      await status({'process': null});
      expect(live.liveReadings, isEmpty);

      // Now steam: empty process block. Neither Live card nor curve.
      await status({'m': 2});
      await status({
        'process': {'a': 1},
        'pr': 2.0,
        'fl': 1.0,
      });
      expect(live.stage, isNot(ShotStage.running));
      expect(live.liveReadings, isEmpty);

      // Same for water.
      await status({'process': null});
      await status({'m': 3});
      await status({
        'process': {'a': 1},
        'fl': 4.0,
      });
      expect(live.stage, isNot(ShotStage.running));
      expect(live.liveReadings, isEmpty);

      // And the machine reports no extraction meanwhile.
      expect(machine.liveState.extracting, isFalse);
    });

    test('running brew fills the live curve, flushing does not', () async {
      await status({'m': 1, 'ct': 93.0, 'tt': 93.0, 'cp': true, 'bc': true});

      // A flush is marked as a utility and doesn't belong in the shot
      // card.
      await status({
        'process': {'a': 1, 's': 'brew', 'l': 'Flush', 'e': 500, 'u': 1},
      });
      expect(live.stage, ShotStage.ready);
      expect(live.liveReadings, isEmpty);

      await status({'process': null});
      await status({
        'process': {
          'a': 1,
          's': 'infusion',
          'l': 'Pre-infusion',
          'e': 1000,
          'u': 0,
        },
        'pr': 3.0,
        'fl': 2.0,
        'cw': 0.0,
      });
      expect(live.stage, ShotStage.running);
      expect(live.activeCard, ActiveCard.live);

      await status({
        'process': {'a': 1, 's': 'brew', 'l': 'Extraction', 'e': 12000, 'u': 0},
        'pr': 8.6,
        'cw': 18.0,
      });
      expect(live.liveReadings.length, 2);
      expect(live.liveReadings.last.timeMs, 12000);
      expect(live.liveReadings.last.pressure, 8.6);
      expect(live.liveReadings.last.weight, 18.0);
      expect(live.liveReadings.last.stage, 'Extraction');
    });

    test('finished brew holds on POST, saving clears it', () async {
      await status({'m': 1, 'ct': 93.0, 'tt': 93.0});
      await status({
        'process': {'a': 1, 's': 'brew', 'l': 'Extraction', 'e': 8000, 'u': 0},
      });
      expect(live.activeCard, ActiveCard.live);

      // The firmware leaves the finished process in place until someone
      // clears it — exactly the hold point for the Post card.
      await status({
        'process': {'a': 0, 's': 'brew', 'l': 'Finished', 'e': 27000, 'u': 0},
      });
      expect(live.stage, ShotStage.purging);
      expect(live.activeCard, ActiveCard.post);

      live.confirmPostShot();
      expect(live.activeCard, ActiveCard.pre);
      expect(transport.sent.last['tp'], 'req:process:clear');
    });

    test('start and stop go to the process of the machine', () async {
      await live.startShot();
      expect(transport.sent.last['tp'], 'req:process:activate');
      await live.stopShot();
      expect(transport.sent.last['tp'], 'req:process:deactivate');
    });
  });
}

// Counter-check: the Meticulous keeps its behavior — there "heating for
// this profile" is a real step from which the profile is locked in.
void _meticulousKeepsItsRule() {
  test('Meticulous still locks the profile from preheat on', () {
    final socket = MeticulousSocketService(hostname: 'unreachable.local');
    final live = MeticulousLiveShotService(socket);

    expect(live.stage, ShotStage.idle);
    expect(live.profileLocked, isFalse);
    expect(live.pulsesWhenReady, isTrue);

    socket.latestStatus = MachineStatus.fromJson({
      'name': 'heating',
      'state': 'brewing',
    });
    live.start();
    expect(live.stage, ShotStage.heating);
    expect(live.profileLocked, isTrue);
    expect(live.supportsAutoStart, isTrue);

    live.dispose();
    socket.dispose();
  });
}
