import 'dart:io';

import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/scale/brew_scale.dart';
import 'package:beand/scale/simulated_scale.dart';
import 'package:beand/screens/live/home_mode_bar.dart';
import 'package:beand/screens/settings/home_settings_screen.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/brew_recipe_store.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:beand/widgets/gaggimate_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

import 'package:shared_preferences/shared_preferences.dart';

Widget wrap(AppSettings settings, Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AppSettings>.value(value: settings),
    ChangeNotifierProvider<MeticulousSocketService>.value(
      value: MeticulousSocketService(hostname: 'unreachable.local'),
    ),
    // The same machine once more under the shared interface: the Pre-Shot
    // card addresses it through that.
    ChangeNotifierProvider<EspressoMachine>.value(
      value: MeticulousSocketService(hostname: 'unreachable.local'),
    ),
    ChangeNotifierProvider<GaggiMateService>.value(value: offlineGaggiMate()),
    ChangeNotifierProvider<BrewScale>.value(value: SimulatedScale()),
    ChangeNotifierProvider<BrewRecipeStore>.value(
      value: BrewRecipeStore(
        cacheFile: File('${Directory.systemTemp.path}/no-such-cache.json'),
      ),
    ),
  ],
  child: MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: child),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('activeHomeMode falls back to the first visible mode', () async {
    final settings = AppSettings(homeMode: HomeMode.pourOver);
    expect(settings.activeHomeMode, HomeMode.pourOver);

    await settings.setHomeModeEnabled(HomeMode.pourOver, false);
    expect(settings.activeHomeMode, HomeMode.meticulous);

    await settings.setHomeModeEnabled(HomeMode.meticulous, false);
    expect(settings.enabledHomeModes, isEmpty);
    expect(settings.activeHomeMode, HomeMode.meticulous);
  });

  test('settings persist after load()', () async {
    final settings = await AppSettings.load();
    expect(settings.enabledHomeModes, [HomeMode.meticulous, HomeMode.pourOver]);

    await settings.setHomeModeEnabled(HomeMode.gaggimate, true);
    await settings.setHomeMode(HomeMode.gaggimate);

    final reloaded = await AppSettings.load();
    expect(reloaded.enabledHomeModes, HomeMode.values);
    expect(reloaded.activeHomeMode, HomeMode.gaggimate);
  });

  testWidgets('Settings switches show and hide pills in the bar', (
    tester,
  ) async {
    final settings = AppSettings();
    await tester.pumpWidget(wrap(settings, const HomeModeBar()));
    expect(find.text('Meticulous'), findsOneWidget);
    expect(find.text('Pour Over'), findsOneWidget);
    expect(find.byType(GaggiMateWordmark), findsNothing);
    expect(find.byIcon(Icons.bluetooth), findsOneWidget);

    await tester.pumpWidget(wrap(settings, const HomeSettingsScreen()));
    // Pour Over has its own page instead of a switch.
    final switches = find.byType(Switch);
    expect(switches, findsNWidgets(2));
    await tester.tap(switches.at(1)); // GaggiMate an
    await tester.tap(find.text('Pour Over'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch)); // Pour Over off
    await tester.pump();
    expect(settings.enabledHomeModes, [
      HomeMode.meticulous,
      HomeMode.gaggimate,
    ]);

    // Fresh tree: otherwise the opened Pour Over page would still be on top.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(wrap(settings, const HomeModeBar()));
    // GaggiMate shows its wordmark instead of the text.
    expect(find.byType(GaggiMateWordmark), findsOneWidget);
    expect(find.text('Pour Over'), findsNothing);
  });

  testWidgets('tapping a pill switches the active mode', (tester) async {
    final settings = AppSettings();
    await tester.pumpWidget(wrap(settings, const HomeModeBar()));
    await tester.tap(find.text('Pour Over'));
    await tester.pump();
    expect(settings.activeHomeMode, HomeMode.pourOver);
  });

  group('pill order', () {
    test('moving swaps the visible modes', () async {
      final settings = AppSettings();
      expect(settings.enabledHomeModes, [
        HomeMode.meticulous,
        HomeMode.pourOver,
      ]);

      await settings.reorderEnabledHomeModes(1, 0);
      expect(settings.enabledHomeModes, [
        HomeMode.pourOver,
        HomeMode.meticulous,
      ]);
    });

    // Otherwise hidden modes would jump to the start when shown again.
    test('a hidden mode keeps its place', () async {
      final settings = AppSettings(
        enabledHomeModes: {HomeMode.meticulous, HomeMode.gaggimate},
      );
      expect(settings.enabledHomeModes, [
        HomeMode.meticulous,
        HomeMode.gaggimate,
      ]);

      await settings.reorderEnabledHomeModes(1, 0);
      expect(settings.enabledHomeModes, [
        HomeMode.gaggimate,
        HomeMode.meticulous,
      ]);

      // Pour Over was between the two and still is.
      await settings.setHomeModeEnabled(HomeMode.pourOver, true);
      expect(settings.enabledHomeModes, [
        HomeMode.gaggimate,
        HomeMode.pourOver,
        HomeMode.meticulous,
      ]);
    });

    test('order survives a restart', () async {
      final settings = await AppSettings.load();
      await settings.reorderEnabledHomeModes(1, 0);

      final reloaded = await AppSettings.load();
      expect(reloaded.enabledHomeModes, [
        HomeMode.pourOver,
        HomeMode.meticulous,
      ]);
    });

    // A mode added later must not invalidate a saved order.
    test('unknown and missing modes are cleaned up', () {
      final order = AppSettings.normalizeHomeModeOrder([
        HomeMode.gaggimate,
        HomeMode.gaggimate,
      ]);
      expect(order, hasLength(HomeMode.values.length));
      expect(order.first, HomeMode.gaggimate);
      expect(order.toSet(), HomeMode.values.toSet());
    });

    testWidgets('the bar shows the saved order', (tester) async {
      final settings = AppSettings();
      await settings.reorderEnabledHomeModes(1, 0);

      await tester.pumpWidget(wrap(settings, const HomeModeBar()));
      await tester.pump();

      final pourOver = tester.getRect(find.text('Pour Over'));
      final meticulous = tester.getRect(find.text('Meticulous'));
      expect(
        pourOver.left,
        lessThan(meticulous.left),
        reason: 'Pour Over is now first',
      );
    });
  });
}
