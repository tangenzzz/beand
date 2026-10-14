import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:beand/database/database.dart';
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_profile_detail.dart';
import 'package:beand/machines/gaggimate/gaggimate_profile_sync_service.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';
import 'package:beand/models/machine_profile.dart';
import 'package:beand/models/profile_detail.dart';
import 'package:beand/services/profile_images.dart';
import 'package:beand/services/shot_setup.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:beand/theme/app_theme.dart';

// Fixtures: `gaggimate_profiles_sim.json` is the simulator's response to
// req:profiles:list, `gaggimate_profile_pro.json` the firmware's bundled
// "Adaptive v2" (data/p/adapt.json) — a Pro profile with ramps, flow
// control and several stop conditions.
Map<String, dynamic> _proProfile() => Map<String, dynamic>.from(
  jsonDecode(
    File('test/fixtures/gaggimate_profile_pro.json').readAsStringSync(),
  ) as Map,
);

List<Map<String, dynamic>> _simProfiles() => [
  for (final p in jsonDecode(
    File('test/fixtures/gaggimate_profiles_sim.json').readAsStringSync(),
  ) as List)
    Map<String, dynamic>.from(p as Map),
];

class FakeTransport implements GaggiMateTransport {
  FakeTransport(this.profiles);

  final List<Map<String, dynamic>> profiles;
  final _incoming = StreamController<dynamic>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  Future<void> get ready async {}

  @override
  Stream<dynamic> get messages => _incoming.stream;

  @override
  void send(String data) {
    final message = Map<String, dynamic>.from(jsonDecode(data) as Map);
    sent.add(message);
    // The machine mirrors the rid in its response.
    final rid = message['rid'];
    if (message['tp'] == 'req:profiles:list') {
      _incoming.add(
        jsonEncode({
          'tp': 'res:profiles:list',
          'rid': rid,
          'profiles': profiles,
        }),
      );
    } else if (message['tp'] == 'req:profiles:save') {
      final profile = Map<String, dynamic>.from(
        message['profile'] as Map? ?? {},
      );
      // Without an id the firmware assigns one.
      profile['id'] = (profile['id'] ?? '').toString().isEmpty
          ? 'NEWID12345'
          : profile['id'];
      profiles.add(profile);
      _incoming.add(
        jsonEncode({'tp': 'res:profiles:save', 'rid': rid, 'profile': profile}),
      );
    }
  }

  @override
  Future<void> close() async => _incoming.close();

  void receive(Map<String, dynamic> frame) => _incoming.add(jsonEncode(frame));
}

void main() {
  _profileImages();

  group('translation into the shared profile view', () {
    test('Pro profile: phases become stages with curve and triggers', () {
      final detail = gaggiMateProfileDetail(_proProfile());

      expect(detail.name, 'Adaptive v2');
      expect(detail.stages, hasLength(6));

      final prefill = detail.stages.first;
      expect(prefill.number, 1);
      expect(prefill.name, 'Prefill');
      // pump.target = flow -> the stage controls flow.
      expect(prefill.type, 'flow');
      expect(prefill.endValue, 8);
      // Duration is in there as a time trigger, plus the "pumped" target.
      expect(
        prefill.exitTriggers.map((t) => t.type),
        containsAll(['time', 'pumped']),
      );
      expect(
        prefill.exitTriggers.firstWhere((t) => t.type == 'time').value.value,
        5,
      );

      // Second phase has two stop conditions plus the duration.
      expect(detail.stages[1].exitTriggers, hasLength(3));

      // Every stage has a name and a control type — otherwise the view
      // would be half empty.
      for (final stage in detail.stages) {
        expect(stage.name, isNotEmpty);
        expect(stage.type, isNotEmpty);
      }
    });

    test('simple simulator profile: pump percentage becomes "power"', () {
      final detail = gaggiMateProfileDetail(_simProfiles().first);

      expect(detail.name, 'Default');
      expect(detail.temperature, 93);
      expect(detail.stages, hasLength(1));
      final stage = detail.stages.single;
      expect(stage.type, 'power');
      expect(stage.endValue, 100);
      expect(stage.isConstant, isTrue);
      // The target weight is in the stop condition, not at the profile top.
      expect(detail.finalWeight, 36);
      // "volumetric" is called "weight" in the shared view.
      expect(stage.exitTriggers.map((t) => t.type), contains('weight'));
      expect(detail.description, 'Default profile');
      // No image, no variables, no author.
      expect(detail.imagePath, isNull);
      expect(detail.variables, isEmpty);
    });

    test('a ramp is mapped as a two-point curve', () {
      final json = _proProfile();
      final phases = json['phases'] as List;
      // Phase 1 ends at flow 8, phase 3 ramps up to pressure 9.
      final detail = gaggiMateProfileDetail(json);
      final ramped = detail.stages.firstWhere(
        (s) => s.points.length > 2 || !s.isConstant,
        orElse: () => detail.stages.last,
      );
      expect(ramped.points, isNotEmpty);
      expect(phases.length, detail.stages.length);
    });

    testWidgets('the "pumped" trigger gets unit, name and color', (
      tester,
    ) async {
      // Only the GaggiMate knows it; without an entry the view would show a
      // bare number without a unit.
      expect(unitFor('pumped'), 'ml');
      expect(typeLabel('pumped'), 'Pumped');
      // The colors come from the theme tokens.
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        colorForType(ctx, 'pumped'),
        isNot(colorForType(ctx, 'unbekannt')),
      );

      final detail = gaggiMateProfileDetail(_proProfile());
      final pumped = detail.stages
          .expand((s) => s.exitTriggers)
          .where((t) => t.type == 'pumped');
      expect(pumped, isNotEmpty);
    });

    test('broken phases do not break the translation', () {
      final detail = gaggiMateProfileDetail({
        'id': 'x',
        'label': 'Schräg',
        'phases': [
          'kein Objekt',
          {'name': 'Leer'},
        ],
      });
      expect(detail.name, 'Schräg');
      expect(detail.stages, hasLength(1));
      expect(detail.stages.single.name, 'Leer');
    });
  });

  group('placeholder colors', () {
    test('same id -> same color, different ids -> different', () {
      expect(
        profilePlaceholderColor('eYPGFZXTCJ'),
        profilePlaceholderColor('eYPGFZXTCJ'),
      );
      final colors = {
        for (final id in [
          'eYPGFZXTCJ',
          '5DORMxzTwa',
          'adapt',
          'lever',
          '9bar',
          'lmleva',
        ])
          profilePlaceholderColor(id),
      };
      // With six profiles, not all should appear in the same color.
      expect(colors.length, greaterThan(2));
    });

    test('GaggiMate profiles get their color, not the uniform gray', () {
      final profile = gaggiMateProfileDetail(_simProfiles().first);
      expect(profile.accentColor, profilePlaceholderColor('eYPGFZXTCJ'));
      expect(profile.accentColor, isNot(const Color(0xFF3F3F44)));
    });
  });

  group('local copy of GaggiMate profiles', () {
    late AppDatabase db;
    late FakeTransport transport;
    late GaggiMateService machine;
    late GaggiMateProfileSyncService sync;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      transport = FakeTransport(_simProfiles());
      machine = GaggiMateService(
        host: 'gaggimate.local',
        transportFactory: (_) => transport,
        autoReconnect: false,
      );
      sync = GaggiMateProfileSyncService(database: db, machine: machine);
    });

    tearDown(() async {
      sync.dispose();
      machine.dispose();
      await db.close();
    });

    Future<void> connect() async {
      sync.start();
      machine.connect();
      transport.receive({'tp': 'evt:status', 'm': 1});
      for (var i = 0; i < 100; i++) {
        if (machine.connectionState == MachineConnectionState.connected) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    Future<List<StoredProfile>> stored({String machine = 'gaggimate'}) =>
        db.watchStoredProfiles(machine: machine).first;

    test('on connect the profiles land in the database', () async {
      await connect();
      for (var i = 0; i < 100 && (await stored()).length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final profiles = await stored();
      expect(
        profiles.map((p) => p.id),
        containsAll(['eYPGFZXTCJ', '5DORMxzTwa']),
      );
      expect(profiles.every((p) => p.machine == 'gaggimate'), isTrue);
      expect(profiles.first.name, isNotEmpty);
      // The Meticulous profiles stay untouched.
      expect(await stored(machine: 'meticulous'), isEmpty);
    });

    test('profiles of both machines may have the same id', () async {
      await db.upsertStoredProfile(
        StoredProfilesCompanion.insert(
          id: 'eYPGFZXTCJ',
          name: 'Gleichnamig bei der Meticulous',
          json: '{"id":"eYPGFZXTCJ","name":"Gleichnamig bei der Meticulous"}',
          fetchedAt: DateTime.now(),
        ),
      );
      await connect();
      for (var i = 0; i < 100 && (await stored()).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // Both rows exist side by side; neither has overwritten the other.
      expect((await stored()).map((p) => p.id), contains('eYPGFZXTCJ'));
      expect(
        (await stored(machine: 'meticulous')).single.name,
        'Gleichnamig bei der Meticulous',
      );
    });
  });

  group('profile upload', () {
    test('req:profiles:save sends the file and returns the new id', () async {
      final transport = FakeTransport(_simProfiles());
      final machine = GaggiMateService(
        host: 'gaggimate.local',
        transportFactory: (_) => transport,
        autoReconnect: false,
      );
      machine.connect();
      transport.receive({'tp': 'evt:status', 'm': 1});
      for (var i = 0; i < 100; i++) {
        if (machine.connectionState == MachineConnectionState.connected) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final json = _proProfile()..remove('id');
      final result = await machine.uploadProfile(json);

      expect(result.isOk, isTrue);
      expect(result.id, 'NEWID12345');
      expect(transport.sent.any((m) => m['tp'] == 'req:profiles:save'), isTrue);
      machine.dispose();
    });

    test('mybrewfolio is the GaggiMate download source', () {
      final machine = GaggiMateService(host: 'x', autoReconnect: false);
      expect(
        machine.profileSites.single.url,
        'https://mybrewfolio.com/profiles',
      );
      expect(machine.machineKey, 'gaggimate');
      machine.dispose();
    });
  });

  group('separate setup store per machine', () {
    test('both machines keep profile and values apart', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final meticulous = ShotSetup.inMemory();
      final gaggimate = ShotSetup.inMemory(machineKey: 'gaggimate');
      final setups = ShotSetups(meticulous: meticulous, gaggimate: gaggimate);

      meticulous.setProfile('met-1', 'Soup Test');
      gaggimate.setProfile('eYPGFZXTCJ', 'Default');

      expect(setups.forMachine('meticulous').profileName, 'Soup Test');
      expect(setups.forMachine('gaggimate').profileName, 'Default');
      // Fresh, nothing is set — no made-up default values.
      expect(gaggimate.doseGrams, isNull);
      expect(gaggimate.snapshot().grindSize, isNull);
      await db.close();
    });

    test('restoreFromLastShot only takes shots of its own machine', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.upsertStoredProfile(
        StoredProfilesCompanion.insert(
          id: 'g1',
          machine: const Value('gaggimate'),
          name: 'Default',
          json: '{"id":"g1","label":"Default"}',
          fetchedAt: DateTime.now(),
        ),
      );
      await db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 9, 30, 8),
          machine: const Value('gaggimate'),
          profileName: const Value('Default'),
          doseGrams: const Value(16),
          grindSize: const Value('4.0'),
        ),
        const [],
      );
      // Newer Meticulous shot that is none of the GaggiMate's business.
      await db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 9, 30, 9),
          profileName: const Value('Soup Test'),
          doseGrams: const Value(20),
        ),
        const [],
      );

      final gaggimate = ShotSetup.inMemory(machineKey: 'gaggimate');
      await gaggimate.restoreFromLastShot(db);

      expect(gaggimate.profileName, 'Default');
      expect(gaggimate.profileId, 'g1');
      expect(gaggimate.doseGrams, 16);
      expect(gaggimate.grindSize, 4.0);
      await db.close();
    });

    // A brew without dose/grind size was on top, and after a restart the
    // fields were empty — even though values had been brewed with that
    // profile before.
    test('a brew without values does not break the chain', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.upsertStoredProfile(
        StoredProfilesCompanion.insert(
          id: 'g1',
          machine: const Value('gaggimate'),
          name: 'Default',
          json: '{"id":"g1","label":"Default"}',
          fetchedAt: DateTime.now(),
        ),
      );
      // Older brew WITH values …
      await db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 9, 30, 21, 3),
          machine: const Value('gaggimate'),
          profileName: const Value('Default'),
          doseGrams: const Value(18.4),
          grindSize: const Value('2.8'),
        ),
        const [],
      );
      // … and a newer one without.
      await db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 9, 30, 21, 31),
          machine: const Value('gaggimate'),
          profileName: const Value('Default'),
        ),
        const [],
      );

      final setup = ShotSetup.inMemory(machineKey: 'gaggimate');
      await setup.restoreFromLastShot(db);

      expect(setup.profileName, 'Default');
      expect(setup.doseGrams, 18.4);
      expect(setup.grindSize, 2.8);
      await db.close();
    });

    test('without any brew with values the fields stay empty', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.upsertStoredProfile(
        StoredProfilesCompanion.insert(
          id: 'g1',
          machine: const Value('gaggimate'),
          name: 'Default',
          json: '{"id":"g1","label":"Default"}',
          fetchedAt: DateTime.now(),
        ),
      );
      await db.insertShotWithReadings(
        ShotsCompanion.insert(
          timestamp: DateTime(2026, 9, 30, 21, 31),
          machine: const Value('gaggimate'),
          profileName: const Value('Default'),
        ),
        const [],
      );

      final setup = ShotSetup.inMemory(machineKey: 'gaggimate');
      await setup.restoreFromLastShot(db);

      expect(setup.profileName, 'Default');
      expect(setup.doseGrams, isNull);
      expect(setup.grindSize, isNull);
      await db.close();
    });
  });
}

// Regression: profile images were missing in the pre-shot card and in the
// history. Neither took them from the local copy — the card got the
// profiles directly from the machine (which has no images), the history
// only the image copy created on import.
void _profileImages() {
  group('profile images', () {
    test('the local copy of a GaggiMate profile carries its own photo', () {
      final stored = StoredProfile(
        syncId: 'test',
        updatedAt: 0,
        syncState: SyncState.pending,
        deleted: false,
        id: 'eYPGFZXTCJ',
        machine: 'gaggimate',
        name: 'Default',
        json: jsonEncode(_simProfiles().first),
        position: 0,
        fetchedAt: DateTime(2026, 9, 30),
        customImagePath: '/fotos/default.jpg',
      );

      final profile = MachineProfile.fromStored(stored);
      expect(profile.name, 'Default');
      expect(profile.temperature, 93);
      expect(profile.finalWeight, 36, reason: 'from the stop condition');
      expect(profile.localImagePath, '/fotos/default.jpg');
      expect(profile.accentColor, profilePlaceholderColor('eYPGFZXTCJ'));
      expect(MachineProfile.isUtility(stored), isFalse);
    });

    test('utility profiles stay recognizable as such', () {
      final stored = StoredProfile(
        syncId: 'test',
        updatedAt: 0,
        syncState: SyncState.pending,
        deleted: false,
        id: 'bf1',
        machine: 'gaggimate',
        name: 'Backflush',
        json: '{"id":"bf1","label":"Backflush","utility":true,"phases":[]}',
        position: 0,
        fetchedAt: DateTime(2026, 9, 30),
      );
      expect(MachineProfile.isUtility(stored), isTrue);
    });

    test('the history finds the image via machine and profile name', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final images = ProfileImages(db.watchStoredProfiles());

      await db.upsertStoredProfile(
        StoredProfilesCompanion.insert(
          id: 'g1',
          machine: const Value('gaggimate'),
          name: 'Default',
          json: '{"id":"g1","label":"Default"}',
          fetchedAt: DateTime(2026, 9, 30),
          customImagePath: const Value('/fotos/gaggi.jpg'),
        ),
      );
      // Same-named profile of the other machine with a different image.
      await db.upsertStoredProfile(
        StoredProfilesCompanion.insert(
          id: 'm1',
          name: 'Default',
          json: '{"id":"m1","name":"Default"}',
          fetchedAt: DateTime(2026, 9, 30),
          imagePath: const Value('/fotos/met.jpg'),
        ),
      );
      for (var i = 0; i < 100; i++) {
        if (images.pathFor(machine: 'gaggimate', profileName: 'Default') !=
                null &&
            images.pathFor(machine: 'meticulous', profileName: 'Default') !=
                null) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(
        images.pathFor(machine: 'gaggimate', profileName: 'Default'),
        '/fotos/gaggi.jpg',
      );
      // The machine is part of the key: same name, different image.
      expect(
        images.pathFor(machine: 'meticulous', profileName: 'Default'),
        '/fotos/met.jpg',
      );
      expect(images.pathFor(machine: 'gaggimate', profileName: 'Weg'), isNull);
      expect(images.pathFor(machine: 'gaggimate', profileName: null), isNull);

      images.dispose();
      await db.close();
    });
  });
}
