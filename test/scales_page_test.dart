import 'dart:async';

import 'package:beand/scale/brew_scale.dart';
import 'package:beand/scale/simulated_scale.dart';
import 'package:beand/screens/settings/scale_settings_screen.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Scale extends SimulatedScale {
  var scans = 0;
  var asked = 0;
  var off = false;
  ScaleConnection state = ScaleConnection.disconnected;
  final connects = <String>[];
  final forgotten = <String>[];
  List<ScaleCandidate> nearby = const [];
  final offChanges = StreamController<bool>.broadcast();

  @override
  ScaleConnection get connection => state;
  @override
  String? get rememberedId => 'a';
  @override
  List<KnownScale> get knownScales => const [
    KnownScale(id: 'a', name: 'PROCHBT001'),
    KnownScale(id: 'b', name: 'Decent Scale'),
  ];
  @override
  Future<void> forgetScale(String id) async => forgotten.add(id);
  @override
  Future<bool> get bluetoothOff async => off;
  @override
  Stream<bool> get bluetoothOffChanges => offChanges.stream;
  @override
  Future<bool> requestBluetoothOn() async {
    asked++;
    return false;
  }

  @override
  Stream<ScaleCandidate> scan({
    Duration timeout = const Duration(seconds: 10),
  }) {
    scans++;
    return Stream.fromIterable(nearby);
  }

  @override
  Future<void> connectTo(ScaleCandidate candidate) async =>
      connects.add(candidate.id);
}

// Lets the page's chain of futures run through.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

void main() {
  Future<void> pump(WidgetTester tester, _Scale scale) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<BrewScale>.value(
        value: scale,
        child: MaterialApp(
          theme: ThemeData(
            extensions: [
              AppColors.forVariant(AppThemeVariant.dark, AppAccent.teal),
            ],
          ),
          home: const ScaleSettingsScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('known scales stay listed: nearby, offline, tap connects', (
    tester,
  ) async {
    final scale = _Scale()
      ..nearby = const [
        ScaleCandidate(id: 'b', name: 'Decent Scale', rssi: -40),
        ScaleCandidate(id: 'c', name: 'BOOKOO_1', rssi: -60),
      ];
    await pump(tester, scale);
    expect(find.text('MY SCALES'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Nearby'), findsOneWidget);
    expect(find.text('NEW SCALES'), findsOneWidget);
    expect(find.text('BOOKOO_1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('known-scale-a')));
    await settle(tester);
    expect(scale.connects, ['a']);
  });

  testWidgets('Scan and switching work while the scale is busy', (
    tester,
  ) async {
    final scale = _Scale()..state = ScaleConnection.scanning;
    await pump(tester, scale);
    final before = scale.scans;
    await tester.tap(find.byKey(const ValueKey('scale-scan')));
    await settle(tester);
    expect(scale.scans, before + 1);

    await tester.tap(find.byKey(const ValueKey('known-scale-b')));
    await settle(tester);
    expect(scale.connects, ['b']);
  });

  testWidgets('a scale can be forgotten', (tester) async {
    final scale = _Scale();
    await pump(tester, scale);
    await tester.tap(find.byTooltip('More').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forget'));
    await tester.pumpAndSettle();
    expect(scale.forgotten, ['b']);
  });

  testWidgets('Bluetooth off: reminder, Scan asks, coming on scans', (
    tester,
  ) async {
    final scale = _Scale()..off = true;
    await pump(tester, scale);
    scale.offChanges.add(true);
    await settle(tester);
    expect(find.text('Bluetooth is off.'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);
    expect(find.text('PROCHBT001'), findsWidgets);
    expect(scale.scans, 0);

    await tester.tap(find.byKey(const ValueKey('scale-scan')));
    await settle(tester);
    expect(scale.asked, 1);
    expect(scale.scans, 0);

    scale.off = false;
    scale.offChanges.add(false);
    await settle(tester);
    expect(find.text('Turn on'), findsNothing);
    expect(scale.scans, 1);
  });
}
