import 'package:beand/models/machine_status.dart';
import 'package:beand/services/connection_log.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

// The water check before heating (head stage "water detection"; without
// water: "Pour water and click to continue") is part of the preparation.
// It used to count as a running brew: the carousel jumped to the live card
// and the following 'heating' reset the session (user 2026-11-14).
class FakeSocket extends MeticulousSocketService {
  FakeSocket() : super(hostname: 'unreachable.local');

  void push(String phase, {int timeMs = 0}) {
    latestStatus = MachineStatus.fromJson({
      'name': phase,
      'state': 'brewing',
      'extracting': false,
      'time': timeMs,
      'sensors': {'p': 0.0, 'f': 0.0, 'w': 0.0, 't': 60.0, 'g': 0.0},
    });
    notifyListeners();
  }
}

void main() {
  late List<String> logged;
  setUp(() {
    logged = [];
    ConnectionLog.sink = logged.add;
  });
  tearDown(() => ConnectionLog.sink = null);

  test('no water, refill, dial click: stays in the preparation', () async {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);
    final jumps = <int>[];
    final sub = live.pageJumps.listen(jumps.add);
    addTearDown(sub.cancel);

    socket.push('idle');
    socket.push('starting...');
    socket.push('water detection');
    expect(live.stage, ShotStage.heating);
    socket.push('Pour water and click to continue');
    expect(live.stage, ShotStage.heating);
    expect(live.activeCard, ActiveCard.pre);
    expect(live.profileLocked, isTrue);

    socket.push('heating');
    socket.push('click to start');
    expect(live.stage, ShotStage.ready);
    expect(live.activeCard, ActiveCard.pre);
    await pumpEventQueue();
    expect(jumps, isEmpty, reason: 'no jump to the live card');
    expect(live.liveReadings, isEmpty);
    expect(logged.where((l) => l.contains('phase')), isEmpty);
  });

  test('an unknown phase straight after heating is logged once', () {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);

    socket.push('heating');
    socket.push('mystery check');
    socket.push('heating');
    socket.push('mystery check');
    final lines = logged.where((l) => l.contains('mystery check')).toList();
    expect(lines, hasLength(1));
    expect(lines.single, contains('after heating'));
  });

  test('normal brew stages and the auto-start lead-in are not logged', () {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);

    socket.push('heating');
    // Machine auto start: no 'click to start' gate.
    socket.push('Water Filling');
    socket.push('Preinfusion', timeMs: 100);
    socket.push('heating');
    socket.push('click to start');
    socket.push('Percolation', timeMs: 100);
    expect(logged.where((l) => l.contains('phase')), isEmpty);
  });
}
