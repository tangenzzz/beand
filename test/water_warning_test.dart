import 'package:beand/models/machine_status.dart';
import 'package:beand/screens/live/temperature_tile.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// The Meticulous checks for water before heating (meticulous-backend head
// stage "water detection"). Without water it waits and asks to "Pour water
// and click to continue"; the hero ring then warns in red.
void main() {
  MeticulousSocketService service({
    required String phase,
    String state = 'brewing',
    bool? water,
  }) {
    final s = MeticulousSocketService(hostname: 'unreachable.local');
    s.latestStatus = MachineStatus.fromJson({'name': phase, 'state': state});
    s.lastWaterStatus = water;
    return s;
  }

  group('isWaterMissing', () {
    test('the machine asks for water', () {
      expect(
        service(phase: 'Pour water and click to continue').isWaterMissing,
        true,
      );
    });

    test('water detection stage with the detector off', () {
      expect(
        service(phase: 'water detection', water: false).isWaterMissing,
        true,
      );
    });

    test('water detection stage with water present', () {
      expect(
        service(phase: 'water detection', water: true).isWaterMissing,
        false,
      );
    });

    // Outside the stage `w_stat` is not trusted (idle value unverified),
    // and a missing field is no alarm.
    test('no alarm outside the stage or without a reading', () {
      expect(
        service(phase: 'idle', state: 'idle', water: false).isWaterMissing,
        false,
      );
      expect(service(phase: 'heating', water: false).isWaterMissing, false);
      expect(service(phase: 'water detection').isWaterMissing, false);
    });
  });

  testWidgets('hero ring shows "No water" in red instead of the temperature', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = service(phase: 'Pour water and click to continue');
    await tester.pumpWidget(
      ChangeNotifierProvider<MeticulousSocketService>.value(
        value: s,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: TemperatureTile()),
          ),
        ),
      ),
    );
    await tester.pump();

    final label = tester.widget<Text>(find.text('No water'));
    final context = tester.element(find.text('No water'));
    expect(label.style?.color, context.colors.danger);
    expect(find.text('Fill, then press the dial'), findsOneWidget);

    // Water poured: the temperature view is back.
    s.latestStatus = MachineStatus.fromJson({
      'name': 'heating',
      'state': 'brewing',
    });
    s.lastWaterStatus = true;
    s.notifyListeners();
    await tester.pump();
    expect(find.text('No water'), findsNothing);
  });
}
