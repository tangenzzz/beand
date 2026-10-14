// Sends a profile built like the editor does to a GaggiMate (or the
// simulator) and reads it back. Proves that the codec produces a format the
// real firmware accepts and stores unchanged, which unit tests against
// fixtures cannot.
//
//   GAGGIMATE_HOST=<host:port> flutter test tool/gaggimate_profile_roundtrip.dart
//
// (A test because the service builds on Flutter classes that `dart run`
// cannot compile. Lives in tool/ on purpose so the normal test run does not
// need a running machine.)
//
// Default host is the GaggiMate simulator on localhost:8080. The profile is
// deleted again at the end.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:beand/machines/gaggimate/gaggimate_profile_codec.dart';
import 'package:beand/machines/espresso_machine.dart';
import 'package:beand/machines/gaggimate/gaggimate_service.dart';

void main() {
  test(
    'GaggiMate accepts a profile from the editor',
    _roundTrip,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

Future<void> _roundTrip() async {
  final host = Platform.environment['GAGGIMATE_HOST'] ?? 'localhost:8080';
  final machine = GaggiMateService(host: host, autoReconnect: false);

  stdout.writeln('Connecting to $host …');
  machine.connect();

  for (var i = 0; i < 50; i++) {
    if (machine.connectionState == MachineConnectionState.connected) break;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  if (machine.connectionState != MachineConnectionState.connected) {
    fail('No connection to $host: ${machine.lastError}');
  }
  stdout.writeln('verbunden.');

  // Build a profile the way the editor would.
  final draft = machine.emptyDraft()
    ..name = 'Codec-Probe'
    ..description = 'Von bean\'d erzeugt';
  final sent = machine.profileFromDraft(draft);
  stdout.writeln(
    '\nGeschickt:\n${const JsonEncoder.withIndent('  ').convert(sent)}',
  );

  final result = await machine.uploadProfile(sent);
  if (!result.isOk) {
    machine.disconnect();
    fail('The machine rejected the profile: ${result.error}');
  }
  stdout.writeln('\nAngenommen, id = ${result.id}');

  // Read back and compare.
  await machine.refreshProfiles();
  final stored = await machine.fetchProfileDetail(result.id!);
  if (stored == null) {
    machine.disconnect();
    fail('Profile not found after saving.');
  }
  stdout.writeln(
    '\nRead back:\n${const JsonEncoder.withIndent('  ').convert(stored)}',
  );

  // Back through the codec and out again: if it stays the same, the profile
  // also survives editing.
  final again = gaggiMateJsonFromDraft(gaggiMateDraftFromJson(stored));
  final same = _norm(again).toString() == _norm(stored).toString();
  stdout.writeln(
    '\nRound-Trip durch den Codec: ${same ? "identisch" : "ABWEICHUNG"}',
  );
  if (!same) {
    stdout.writeln('  vorher:  ${jsonEncode(_norm(stored))}');
    stdout.writeln('  nachher: ${jsonEncode(_norm(again))}');
  }

  final deleted = await machine.deleteProfile(result.id!);
  stdout.writeln(
    '\nTest profile deleted: ${deleted.isOk ? "yes" : deleted.error}',
  );

  machine.disconnect();
  expect(same, isTrue, reason: 'codec round trip against the real firmware');
}

Object? _norm(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _norm(v[k])};
  }
  if (v is List) return [for (final e in v) _norm(e)];
  if (v is num) return v.toDouble();
  return v;
}
