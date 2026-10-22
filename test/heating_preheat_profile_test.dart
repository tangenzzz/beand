import 'package:beand/models/machine_sensors.dart';
import 'package:beand/models/machine_status.dart';
import 'package:beand/services/heating_estimator.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

// A profile started while a plain preheat still runs: the ETA must be the
// profile's, not the preheat countdown (to ~70°, ~10 min).
class _Machine extends MeticulousSocketService {
  _Machine() : super(hostname: 'unreachable.local');

  String session = 'idle';
  bool preheat = true;

  @override
  String get confirmedSessionState => session;
  @override
  bool get isPreheatActive => preheat;
  @override
  double? get preheatCountdownSeconds => preheat ? 500 : null;

  void feed(String phase, double temp) {
    latestStatus = MachineStatus.fromJson({
      'name': phase,
      'state': session,
      'sensors': {'p': 0.0, 'f': 0.0, 'w': 0.0, 't': temp, 'g': 0.0},
      'time': 0,
      'profile_time': 0,
      'extracting': false,
      'loaded_profile': 'Soup',
      'id': '',
    });
    latestSensors = MachineSensors.fromJson({
      't_bar_up': temp,
      't_bar_mu': temp,
      't_bar_md': temp,
      't_bar_down': temp,
    });
    notifyListeners();
  }
}

void main() {
  testWidgets('plain preheat shows its countdown, a profile its own ETA', (
    tester,
  ) async {
    final machine = _Machine()..targetTemperature = 90;
    final model = HeatingEstimator(machine)..start();
    addTearDown(model.dispose);

    machine.feed('idle', 50);
    await tester.pump(const Duration(milliseconds: 500));
    expect(model.etaSeconds, 500, reason: 'plain preheat: the countdown');

    machine.session = 'brewing';
    for (var i = 0; i < 120; i++) {
      machine.feed('heating', 50 + i * 0.2);
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(model.etaSeconds, isNot(500));
  });
}
