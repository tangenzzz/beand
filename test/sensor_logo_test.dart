import 'package:beand/screens/live/espresso/espresso_home.dart';
import 'package:beand/sensors/pressure_sensor.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No Bluetooth at all; the logo test never touches it.
class _NoBle implements FlutterReactiveBle {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// User 2026-11-23: the Pressensor's own logo in the command row — in its
// colours while connected, grey like the other icons otherwise.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the Pressensor brings its logo, and it is a bundled asset', () async {
    final asset = Pressensor(ble: _NoBle()).logoAsset;
    expect(asset, 'assets/pressensor/logo.png');
    final data = await rootBundle.load(asset!);
    expect(data.lengthInBytes, greaterThan(1000));
  });

  Future<void> pump(WidgetTester tester, {required bool colored}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: IconTheme(
            data: const IconThemeData(color: Colors.grey),
            child: SensorLogo(
              asset: 'assets/pressensor/logo.png',
              colored: colored,
            ),
          ),
        ),
      );

  testWidgets('connected: own colours; otherwise one grey', (tester) async {
    await pump(tester, colored: true);
    expect(find.byKey(const ValueKey('sensor-logo-colored')), findsOneWidget);
    expect(find.byType(ColorFiltered), findsNothing);

    await pump(tester, colored: false);
    expect(find.byKey(const ValueKey('sensor-logo-plain')), findsOneWidget);
    final filter = tester.widget<ColorFiltered>(find.byType(ColorFiltered));
    expect(
      filter.colorFilter,
      const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
    );
  });
}
