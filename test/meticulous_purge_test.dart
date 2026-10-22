import 'package:beand/models/machine_status.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSocket extends MeticulousSocketService {
  FakeSocket() : super(hostname: 'unreachable.local');

  final actions = <String>[];

  void phase(String name) {
    latestStatus = MachineStatus.fromJson({
      'name': name,
      'state': 'brewing',
      'extracting': false,
    });
    notifyListeners();
  }

  @override
  Future<bool> triggerAction(String action) async {
    actions.add(action);
    return true;
  }
}

void main() {
  test(
    'Purge at the end of a shot waves the machine on (like the dial)',
    () async {
      final socket = FakeSocket();
      final live = MeticulousLiveShotService(socket)..start();
      addTearDown(live.dispose);

      socket.phase('click to purge');
      expect(live.stage, ShotStage.awaitingPurge);
      await live.purge();
      // Not the separate purge routine: that one stopped early, wet puck.
      expect(socket.actions, ['continue']);
    },
  );

  test('outside a shot it stays the plain purge', () async {
    final socket = FakeSocket();
    final live = MeticulousLiveShotService(socket)..start();
    addTearDown(live.dispose);

    socket.phase('idle');
    await live.purge();
    expect(socket.actions, ['purge']);
  });
}
