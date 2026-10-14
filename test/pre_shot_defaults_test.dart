import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/database/database.dart';
import 'package:beand/models/machine_profile.dart';
import 'package:beand/models/machine_status.dart';
import 'package:beand/screens/live/pre_shot_card.dart';
import 'package:beand/services/app_settings.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/offline_gaggimate.dart';

// Profiles of the test machine (two, as in pre_shot_pickers_test).
class FakeService extends MeticulousSocketService {
  FakeService() : super(hostname: 'unreachable.local');

  static const soup = MachineProfile(
    id: 'p1',
    name: 'Soup',
    temperature: 82,
    finalWeight: 36,
    accentColor: Colors.orange,
  );
  static const classic = MachineProfile(
    id: 'p2',
    name: 'Classic',
    temperature: 93,
    finalWeight: 40,
    accentColor: Colors.blue,
  );

  @override
  Future<List<MachineProfile>> fetchProfiles() async => const [soup, classic];

  @override
  void hoverProfile(String id, String name) {}

  void setIdle() => setPhase('idle');

  void setPhase(String phase, {String? profileId, String? profileName}) {
    latestStatus = MachineStatus.fromJson({
      'name': phase,
      'id': ?profileId,
      'loaded_profile': ?profileName,
    });
    notifyListeners();
  }
}

Future<int> insertShot(
  AppDatabase db, {
  required DateTime at,
  String? profile,
  int? beanId,
  double? dose,
  String? grind,
}) => db
    .into(db.shots)
    .insert(
      ShotsCompanion.insert(
        timestamp: at,
        profileName: Value(profile),
        beanId: Value(beanId),
        doseGrams: Value(dose),
        grindSize: Value(grind),
      ),
    );

void main() {
  test(
    'restoreFromLastShot: profile, bean, dose, grind size from the last shot',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.upsertStoredProfile(
        StoredProfilesCompanion.insert(
          id: 'p2',
          name: 'Classic',
          json: '{"id":"p2","name":"Classic"}',
          fetchedAt: DateTime(2026, 9, 25),
        ),
      );
      final bean = await db.insertBean(BeansCompanion.insert(name: 'Guji'));
      await insertShot(
        db,
        at: DateTime(2026, 9, 24),
        profile: 'Soup',
        dose: 17,
      );
      await insertShot(
        db,
        at: DateTime(2026, 9, 25),
        profile: 'Classic',
        beanId: bean.id,
        dose: 19.5,
        grind: '4.4',
      );

      final setup = ShotSetup.inMemory();
      await setup.restoreFromLastShot(db);

      expect(setup.profileId, 'p2');
      expect(setup.profileName, 'Classic');
      expect(setup.beanId, bean.id);
      expect(setup.doseGrams, 19.5);
      expect(setup.grindSize, 4.4);
    },
  );

  test(
    'restoreFromLastShot: unknown profile and missing values stay as they are',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      // Profile not stored locally -> no ID available, so don't set it.
      await insertShot(
        db,
        at: DateTime(2026, 9, 25),
        profile: 'Von der Maschine gelöscht',
      );

      final setup = ShotSetup.inMemory(doseGrams: 18, grindSize: 3.2);
      await setup.restoreFromLastShot(db);

      expect(setup.profileId, isNull);
      expect(setup.profileName, isNull);
      expect(setup.doseGrams, 18);
      expect(setup.grindSize, 3.2);
    },
  );

  test(
    'restoreFromLastShot: deleted shots (tombstones) do not count',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await insertShot(
        db,
        at: DateTime(2026, 9, 24),
        profile: 'Soup',
        dose: 17,
      );
      await db
          .into(db.shots)
          .insert(
            ShotsCompanion.insert(
              timestamp: DateTime(2026, 9, 25),
              deletedAt: Value(DateTime(2026, 9, 25)),
            ),
          );

      final setup = ShotSetup.inMemory();
      await setup.restoreFromLastShot(db);
      expect(setup.doseGrams, 17);
    },
  );

  test(
    'lastShotWithSetup: shots without dose AND without grind size are skipped',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await insertShot(
        db,
        at: DateTime(2026, 9, 20),
        profile: 'Soup',
        dose: 16,
        grind: '2.0',
      );
      await insertShot(db, at: DateTime(2026, 9, 21), profile: 'Soup');

      final shot = await db.lastShotWithSetup(profileName: 'Soup');
      expect(shot?.doseGrams, 16);
      expect(shot?.grindSize, '2.0');
    },
  );

  testWidgets(
    'Pre Shot: profile on top, choosing a profile carries dose/grind over, '
    'choosing a bean overrides them with the profile+bean combination',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final db = AppDatabase(NativeDatabase.memory());
      late Bean guji;
      late Bean kiambu;
      await tester.runAsync(() async {
        guji = await db.insertBean(BeansCompanion.insert(name: 'Guji'));
        kiambu = await db.insertBean(BeansCompanion.insert(name: 'Kiambu'));
        // Last shot with "Classic" in general: 20.0 g / 5.5.
        await insertShot(
          db,
          at: DateTime(2026, 9, 22),
          profile: 'Classic',
          beanId: kiambu.id,
          dose: 20,
          grind: '5.5',
        );
        // Older shot with "Classic" + Guji: 17.4 g / 2.8.
        await insertShot(
          db,
          at: DateTime(2026, 9, 20),
          profile: 'Classic',
          beanId: guji.id,
          dose: 17.4,
          grind: '2.8',
        );
      });
      final service = FakeService()..setIdle();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
            ChangeNotifierProvider<ShotSetup>.value(
              value: ShotSetup.inMemory(),
            ),
            ChangeNotifierProvider<MeticulousSocketService>.value(
              value: service,
            ),
            // The same machine again under the common interface: the
            // pre-shot card talks to it through that.
            ChangeNotifierProvider<EspressoMachine>.value(value: service),
            ChangeNotifierProvider<GaggiMateService>.value(
              value: offlineGaggiMate(),
            ),
            ChangeNotifierProvider<LiveShotService>.value(
              value: MeticulousLiveShotService(service)..start(),
            ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(child: PreShotCard()),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();

      // Order: profiles, bean, dose, grind.
      double y(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(y('Profile'), lessThan(y('Bean')));
      expect(y('Bean'), lessThan(y('Dose')));
      expect(y('Dose'), lessThan(y('Grind')));

      // Priority 1: choose profile -> values from the last shot with it.
      await tester.tap(find.text('Select profile'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.textContaining('Classic'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('20 g'), findsOneWidget);
      expect(find.text('5.5'), findsOneWidget);

      // Priority 2: choose a bean already brewed with this profile.
      await tester.tap(find.text('Select bean'));
      await tester.pump();
      await tester.tap(find.textContaining('Guji'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('17.4 g'), findsOneWidget);
      expect(find.text('2.8'), findsOneWidget);

      // Bean without a shot with this profile: values stay.
      await tester.runAsync(() async {
        await db.insertBean(BeansCompanion.insert(name: 'Neu'));
      });
      await tester.pump();
      await tester.tap(find.text('Guji'));
      await tester.pump();
      await tester.tap(find.textContaining('Neu'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('17.4 g'), findsOneWidget);
      expect(find.text('2.8'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      await db.close();
    },
  );

  testWidgets(
    'a profile started on the machine replaces the one last chosen in the '
    'app, including dose/grind',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final db = AppDatabase(NativeDatabase.memory());
      await tester.runAsync(() async {
        await insertShot(
          db,
          at: DateTime(2026, 10, 7),
          profile: 'Classic',
          dose: 20,
          grind: '5.5',
        );
      });
      // Soup was last chosen in the app.
      final setup = ShotSetup.inMemory(profileId: 'p1', profileName: 'Soup');
      final service = FakeService()
        ..setPhase('idle', profileId: 'p1', profileName: 'Soup');
      final live = MeticulousLiveShotService(service)..start();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<AppDatabase>.value(value: db),
            ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
            ChangeNotifierProvider<ShotSetup>.value(value: setup),
            ChangeNotifierProvider<MeticulousSocketService>.value(
              value: service,
            ),
            ChangeNotifierProvider<EspressoMachine>.value(value: service),
            ChangeNotifierProvider<GaggiMateService>.value(
              value: offlineGaggiMate(),
            ),
            ChangeNotifierProvider<LiveShotService>.value(value: live),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const Scaffold(
              body: SingleChildScrollView(child: PreShotCard()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Soup'), findsOneWidget);

      // Only loaded, not started: the choice in the app stays.
      service.setPhase('idle', profileId: 'p2', profileName: 'Classic');
      await tester.pump();
      await tester.pump();
      expect(find.text('Soup'), findsOneWidget);
      expect(setup.profileName, 'Soup');

      // Started on the machine: Classic is heating, so Classic applies.
      service.setPhase('heating', profileId: 'p2', profileName: 'Classic');
      await tester.pump();
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('Classic'), findsOneWidget);
      expect(find.text('Soup'), findsNothing);
      expect(setup.profileId, 'p2');
      expect(setup.profileName, 'Classic');
      expect(find.text('20 g'), findsOneWidget);
      expect(find.text('5.5'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
      live.dispose();
      await db.close();
    },
  );
}
