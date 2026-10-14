import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beand/machines/gaggimate/gaggimate_live_shot_service.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Plays a REAL recording of the GaggiMate simulator through the client
// (test/fixtures/gaggimate_sim_brew.jsonl, recorded with
// tool/gaggimate_ws_capture.py against `pio run -e display-sim -t run`).
//
// The recording contains a complete brew: preheat, start via
// `req:process:activate`, 27.5 s brew, then the finished process that
// stays put. So this test checks the assumptions against the real firmware
// instead of made-up frames — above all, that the deliberately incomplete
// status frames are merged correctly.

class ReplayTransport implements GaggiMateTransport {
  final _controller = StreamController<dynamic>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  Future<void> get ready async {}

  @override
  Stream<dynamic> get messages => _controller.stream;

  @override
  void send(String data) =>
      sent.add(Map<String, dynamic>.from(jsonDecode(data) as Map));

  @override
  Future<void> close() async => _controller.close();

  void push(Map<String, dynamic> frame) => _controller.add(jsonEncode(frame));
}

void main() {
  late List<Map<String, dynamic>> frames;

  setUpAll(() {
    frames = [
      for (final line in File(
        'test/fixtures/gaggimate_sim_brew.jsonl',
      ).readAsLinesSync())
        if (line.trim().isNotEmpty)
          Map<String, dynamic>.from((jsonDecode(line) as Map)['msg'] as Map),
    ];
  });

  test('recording contains exactly the expected structure', () {
    expect(frames.length, greaterThan(100));
    final types = frames.map((f) => f['tp']).toSet();
    expect(types, contains('evt:status'));
    // Two events at shot end that appear neither in the AsyncAPI spec nor
    // in the web UI — they are the hook for a later shot import.
    expect(types, contains('evt:shot-finished-stats'));
    expect(types, contains('evt:history-shot-saved'));
  });

  test('partial frames: temperature survives every slow-state frame', () async {
    final transport = ReplayTransport();
    final machine = GaggiMateService(
      host: 'sim',
      transportFactory: (_) => transport,
      autoReconnect: false,
    )..connect();
    addTearDown(machine.dispose);

    var sawTelemetry = false;
    var temperatureGaps = 0;
    var slowFrames = 0;

    for (final frame in frames) {
      transport.push(frame);
      await pumpEventQueue(times: 1);
      if (frame['tp'] != 'evt:status') continue;
      if (frame.containsKey('ct')) {
        sawTelemetry = true;
      } else {
        slowFrames++;
      }
      // Once a temperature has arrived, it must never disappear again —
      // exactly the bug a replace store would have.
      if (sawTelemetry && machine.status.currentTemp == null) temperatureGaps++;
    }

    expect(sawTelemetry, isTrue);
    expect(
      slowFrames,
      greaterThan(0),
      reason: 'the recording must contain frames without telemetry',
    );
    expect(temperatureGaps, 0);

    // The slow values come from the first (complete) frame, the telemetry
    // from the fast ones — at the end both must be present.
    expect(machine.status.profileLabel, isNotNull);
    expect(machine.status.systemState, 'ready');
    expect(machine.status.hasPressureControl, isTrue);
    expect(machine.status.currentTemp, greaterThan(80));
  });

  test('card states follow the real brew', () async {
    final transport = ReplayTransport();
    final machine = GaggiMateService(
      host: 'sim',
      transportFactory: (_) => transport,
      autoReconnect: false,
    )..connect();
    final live = GaggiMateLiveShotService(machine)..start();
    addTearDown(() {
      live.dispose();
      machine.dispose();
    });

    final stages = <ShotStage>[];
    final cards = <ActiveCard>[];
    live.addListener(() {
      if (stages.isEmpty || stages.last != live.stage) stages.add(live.stage);
      if (cards.isEmpty || cards.last != live.activeCard) {
        cards.add(live.activeCard);
      }
    });

    for (final frame in frames) {
      transport.push(frame);
      await pumpEventQueue(times: 1);
    }

    // The recording starts with the running brew and ends with the
    // finished one waiting to be cleared.
    expect(stages, contains(ShotStage.running));
    expect(stages.last, ShotStage.purging);
    expect(cards.last, ActiveCard.post);

    // The live card's curve is filled and ends just before the duration
    // that is also in the machine's shot index (27500 ms): the last point
    // comes from the last frame in which the process was still running —
    // the "Finished" frame after it is no longer a data point.
    expect(live.liveReadings, isNotEmpty);
    expect(live.liveReadings.last.timeMs, closeTo(27500, 600));
    final maxPressure = live.liveReadings
        .map((r) => r.pressure ?? 0)
        .reduce((a, b) => a > b ? a : b);
    // The machine's shot index reports 10.0 bar for the same brew.
    expect(maxPressure, closeTo(10, 0.5));
  });
}
