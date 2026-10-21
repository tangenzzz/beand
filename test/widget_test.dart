import 'dart:io';

import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/scale/brew_scale.dart';
import 'package:beand/scale/simulated_scale.dart';
import 'package:beand/screens/root_scaffold.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/machines/gaggimate/gaggimate_profile_sync_service.dart';
import 'package:beand/services/profile_sync_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:beand/theme/bean_icon.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

void main() {
  testWidgets('app starts and shows the three main tabs', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final socket = MeticulousSocketService(hostname: 'unreachable.local');
    final gaggimate = offlineGaggiMate();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          Provider<ShotSetups>.value(
            value: ShotSetups(
              meticulous: ShotSetup.inMemory(),
              gaggimate: ShotSetup.inMemory(machineKey: 'gaggimate'),
            ),
          ),
          ChangeNotifierProvider<MeticulousSocketService>.value(value: socket),
          // The same machine again under the shared interface: the
          // Pre-Shot card talks to it through that.
          ChangeNotifierProvider<EspressoMachine>.value(value: socket),
          ChangeNotifierProvider<GaggiMateService>.value(value: gaggimate),
          ChangeNotifierProvider<BrewScale>.value(value: SimulatedScale()),
          Provider<ProfileSyncService>.value(
            value: ProfileSyncService(
              database: db,
              socket: socket,
              imageDir: Directory.systemTemp.createTempSync('beand_images'),
            ),
          ),
          Provider<GaggiMateProfileSyncService>.value(
            value: GaggiMateProfileSyncService(
              database: db,
              machine: gaggimate,
            ),
          ),
          ChangeNotifierProvider<LiveShotService>.value(
            value: MeticulousLiveShotService(socket)..start(),
          ),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const RootScaffold()),
      ),
    );

    // The nav labels (Home, History, Beans) are hidden — the tabs are only
    // recognizable by their icons.
    final nav = find.byType(BottomNavigationBar);
    expect(
      find.descendant(of: nav, matching: find.byIcon(Icons.coffee)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: nav, matching: find.byIcon(Icons.history)),
      findsOneWidget,
    );
    // Beans has no Material icon but the bean from the wordmark.
    expect(
      find.descendant(of: nav, matching: find.byType(BeanIcon)),
      findsOneWidget,
    );

    final items = tester.widget<BottomNavigationBar>(nav).items;
    expect(items.map((i) => i.label), ['Home', 'History', 'Beans']);

    // Tear down widgets so drift runs its stream cleanup timer while still
    // in the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await db.close();
  });

  // Root scaffold with all providers the tabs need.
  Future<AppDatabase> pumpRoot(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final socket = MeticulousSocketService(hostname: 'unreachable.local');
    final gaggimate = offlineGaggiMate();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          Provider<ShotSetups>.value(
            value: ShotSetups(
              meticulous: ShotSetup.inMemory(),
              gaggimate: ShotSetup.inMemory(machineKey: 'gaggimate'),
            ),
          ),
          ChangeNotifierProvider<MeticulousSocketService>.value(value: socket),
          // The same machine again under the shared interface: the
          // Pre-Shot card talks to it through that.
          ChangeNotifierProvider<EspressoMachine>.value(value: socket),
          ChangeNotifierProvider<GaggiMateService>.value(value: gaggimate),
          ChangeNotifierProvider<BrewScale>.value(value: SimulatedScale()),
          Provider<ProfileSyncService>.value(
            value: ProfileSyncService(
              database: db,
              socket: socket,
              imageDir: Directory.systemTemp.createTempSync('beand_images'),
            ),
          ),
          Provider<GaggiMateProfileSyncService>.value(
            value: GaggiMateProfileSyncService(
              database: db,
              machine: gaggimate,
            ),
          ),
          ChangeNotifierProvider<LiveShotService>.value(
            value: MeticulousLiveShotService(socket)..start(),
          ),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const RootScaffold()),
      ),
    );
    return db;
  }

  testWidgets('settings keep the tab bar, back clears '
      'page by page', (tester) async {
    final db = await pumpRoot(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(
      find.byType(BottomNavigationBar),
      findsOneWidget,
      reason: 'The tab bar stays visible below the settings',
    );

    // Open a subpage: tab bar stays there too.
    await tester.ensureVisible(find.text('Backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backup'));
    await tester.pumpAndSettle();
    expect(find.text('Create backup'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    // Back clears the subpage first, then the settings.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
    await db.close();
  });
}
