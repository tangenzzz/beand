import 'package:beand/models/machine_status.dart';
import 'package:beand/services/live_gap_log.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Gaps in the live curve: the machine sends without gaps, the gap arises
// on the phone. If messages arrive late in a batch, they must still land
// in their place in the curve; and a real gap is logged.
class FakeSocket extends MeticulousSocketService {
  FakeSocket() : super(hostname: 'unreachable.local');

  void push(
    String phase, {
    int timeMs = 0,
    bool extracting = true,
    double w = 0,
  }) {
    latestStatus = MachineStatus.fromJson({
      'name': phase,
      'state': 'brewing',
      'extracting': extracting,
      'time': timeMs,
      'sensors': {'p': 6.0, 'f': 2.0, 'w': w, 't': 92.0, 'g': 0.0},
    });
    notifyListeners();
  }

  // A listener call without a new status message (e.g. a sensor event).
  void pokeWithoutStatus() => notifyListeners();
}

void main() {
  late List<String> logged;
  setUp(() {
    logged = [];
    LiveGapLog.sink = logged.add;
  });
  tearDown(() => LiveGapLog.sink = null);

  test('messages delayed in a batch get the machine time, '
      'not the arrival time', () {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);

    socket.push('click to start', extracting: false);
    socket.push('Percolation', timeMs: 100);
    // Five seconds of machine time arrive at once.
    for (var t = 200; t <= 5100; t += 100) {
      socket.push('Percolation', timeMs: t);
    }

    final times = live.liveReadings.map((r) => r.timeMs).toList();
    expect(times.length, 51);
    // Distance to the first point = distance in machine time.
    expect(times.last - times.first, 5000);
    for (var i = 1; i < times.length; i++) {
      expect(times[i] - times[i - 1], 100);
    }
  });

  test('if the phone hangs at the start, the curve still moves to its '
      'place', () async {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);

    socket.push('click to start', extracting: false);
    socket.push('retracting', extracting: false, w: 80);
    // The machine tares: recording starts here.
    socket.push('closing valve', extracting: false);

    // The phone hangs for 1.5 s; the first 1.5 s of the brew then arrive at
    // once, the rest on time again.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    for (var t = 100; t <= 1500; t += 100) {
      socket.push('Percolation', timeMs: t);
    }
    for (var t = 1600; t <= 2000; t += 100) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      socket.push('Percolation', timeMs: t);
    }

    final times = live.liveReadings.map((r) => r.timeMs).toList();
    // First brew point right after the tare point, not 1.5 s later.
    expect(times[1] - times[0], lessThan(400));
    // The curve is as long as the brew on the machine.
    expect(times.last - times[1], 1900);
    for (var i = 2; i < times.length; i++) {
      expect(times[i] - times[i - 1], 100);
    }
  });

  test('Wi-Fi gap in the lead-in: lead-in and brew both move to their '
      'place', () async {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);

    socket.push('click to start', extracting: false);
    socket.push('retracting', extracting: false, w: 80);
    // Tare on time, then Wi-Fi delivers nothing for 1.5 s.
    socket.push('Water Filling', extracting: false);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    // Backlog: 0.5 s lead-in, then 1 s brew, all at once.
    for (var i = 0; i < 4; i++) {
      socket.push('Water Filling', extracting: false);
    }
    socket.push('closing valve', extracting: false);
    for (var t = 100; t <= 1000; t += 100) {
      socket.push('Percolation', timeMs: t);
    }
    // On time again from here.
    for (var t = 1100; t <= 1500; t += 100) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      socket.push('Percolation', timeMs: t);
    }

    final times = live.liveReadings.map((r) => r.timeMs).toList();
    // 1 tare point + 5 lead-in + 15 brew.
    expect(times.length, 21);
    final firstBrew = times[6];
    // Brew starts ~0.5 s after tare, not only after the gap (~1.5 s).
    expect(firstBrew, inInclusiveRange(400, 900));
    expect(times.last - firstBrew, 1400);
    for (var i = 1; i < times.length; i++) {
      expect(times[i], greaterThan(times[i - 1]));
    }
  });

  test('a listener call without a new status message adds no data point', () {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);

    socket.push('click to start', extracting: false);
    socket.push('Percolation', timeMs: 100);
    socket.pokeWithoutStatus();
    socket.pokeWithoutStatus();
    expect(live.liveReadings.length, 1);
  });

  test(
    'over one second without a status message during the brew is logged',
    () async {
      final socket = FakeSocket();
      final live = MeticulousLiveShotService(socket)..start();
      addTearDown(live.dispose);

      socket.push('click to start', extracting: false);
      socket.push('Percolation', timeMs: 100);
      socket.push('Percolation', timeMs: 200);
      expect(logged.where((l) => l.contains(' status ')), isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      socket.push('Percolation', timeMs: 1300);
      expect(
        logged.where((l) => l.contains(' status ')).single,
        contains('machine time 1300 ms'),
      );

      // After the brew it is quiet: no more messages, no heartbeat.
      socket.push('click to purge', extracting: false);
      final count = logged.length;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      socket.push('click to purge', extracting: false);
      expect(logged.length, count);
    },
  );
}
