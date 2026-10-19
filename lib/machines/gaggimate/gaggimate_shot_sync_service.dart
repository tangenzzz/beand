import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../database/database.dart';
import '../../services/shot_setup.dart';
import '../espresso_machine.dart';
import 'gaggimate_service.dart';
import 'gaggimate_shot_log.dart';

// Pulls the GaggiMate's shots permanently into the local DB — the same job
// as ShotSyncService for the Meticulous, just over a different interface:
// the GaggiMate keeps its history in binary form in flash and serves it via
// HTTP (index.bin + <id>.slog, see gaggimate_shot_log.dart), while the
// WebSocket only sends the `evt:history-shot-saved` event.
//
// Syncing happens
//  - on (re)connect: everything the app doesn't know yet (including brews
//    pulled without the app),
//  - immediately on `evt:history-shot-saved`.
//
// Bean/dose/grind size are only known to the app: they are captured from
// the pre-shot card when the brew starts and attached to the new entry.
//
// The entry lands with `machine: 'gaggimate'` in the same table as the
// Meticulous shots — the history is ONE list; the machine only shows as a
// badge on the profile image.
class GaggiMateShotSyncService {
  GaggiMateShotSyncService({
    required this.database,
    required this.machine,
    required this.setup,
    http.Client? client,
  }) : _client = client ?? http.Client();

  // Namespace before the id: the GaggiMate numbers its shots from 0, the
  // Meticulous assigns its own identifiers. Without a prefix the two could
  // collide in the (unique) externalId column.
  static const externalIdPrefix = 'gaggimate:';

  final AppDatabase database;
  final GaggiMateService machine;
  final ShotSetup setup;
  final http.Client _client;

  bool _wasConnected = false;
  bool _wasBrewing = false;
  ({ShotSetupSnapshot setup, DateTime endedAt})? _pending;
  StreamSubscription<int>? _savedSubscription;

  Future<void>? _running;
  bool _rerun = false;
  bool _disposed = false;

  // A just-observed brew only counts as "the one just pulled" for a limited
  // time (guards against stale assignment after a long pause).
  static const _pendingMaxAge = Duration(minutes: 5);

  void start() {
    machine.addListener(_onMachine);
    _savedSubscription = machine.historyShotSaved.listen((_) {
      // The machine only reports the shot after it has written it — unlike
      // the Meticulous, no retry is needed here.
      unawaited(sync());
    });
    _onMachine();
  }

  void dispose() {
    _disposed = true;
    machine.removeListener(_onMachine);
    unawaited(_savedSubscription?.cancel());
    _client.close();
  }

  void _onMachine() {
    final connected =
        machine.connectionState == MachineConnectionState.connected;
    if (connected && !_wasConnected) unawaited(sync());
    _wasConnected = connected;

    // Flushes go through the same process block but are not brews.
    final process = machine.status.process;
    final brewing = process != null && process.active && !process.utility;
    if (brewing && !_wasBrewing) {
      // Capture at START already, not at the end: the machine sends
      // `evt:history-shot-saved` at the same moment its process jumps to
      // "finished", and the order of the two messages is not guaranteed. If
      // the import came first, nothing would be here yet and the shot would
      // lose bean, dose and grind size.
      _pending = (setup: setup.snapshot(), endedAt: DateTime.now());
    } else if (!brewing && _wasBrewing && _pending != null) {
      // The end is the reference point for expiry.
      _pending = (setup: _pending!.setup, endedAt: DateTime.now());
    }
    _wasBrewing = brewing;
  }

  // Never runs twice: a request during a run triggers exactly one more
  // pass.
  Future<void> sync() {
    if (_running != null) {
      _rerun = true;
      return _running!;
    }
    return _running = () async {
      try {
        do {
          _rerun = false;
          await _syncOnce();
        } while (_rerun && !_disposed);
      } finally {
        _running = null;
      }
    }();
  }

  Future<Uint8List> _get(String path) async {
    final response = await _client
        .get(Uri.parse('http://${machine.host}/api/history/$path'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} for $path');
    }
    return response.bodyBytes;
  }

  Future<void> _syncOnce() async {
    try {
      final entries = parseGaggiMateIndex(await _get('index.bin'));
      final known = await database.knownExternalIds();
      // Skip deleted ones: the machine keeps the entry with a flag set;
      // importing it would resurrect it.
      final missing =
          entries
              .where((e) => !e.deleted && !known.contains(_externalId(e.id)))
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      if (missing.isEmpty) return;
      debugPrint(
        'GaggiMateShotSync: ${missing.length} new of ${entries.length}',
      );

      for (var i = 0; i < missing.length; i++) {
        if (_disposed) return;
        // Only the newest shot can be the one just observed.
        final isNewest = i == missing.length - 1;
        final attach = isNewest ? _peekPending() : null;
        try {
          await _importShot(missing[i], attachSetup: attach);
          // Only consumed now: if fetching fails (network hiccup, machine
          // still writing the file), the assignment is kept for the next
          // pass instead of being silently lost.
          if (attach != null) _pending = null;
        } catch (e) {
          debugPrint('GaggiMate shot import failed (${missing[i].id}): $e');
        }
      }
    } catch (e) {
      // Machine unreachable or similar: retry on next connect.
      debugPrint('GaggiMate history sync failed: $e');
    }
  }

  String _externalId(int id) =>
      '$externalIdPrefix${id.toString().padLeft(6, '0')}';

  ShotSetupSnapshot? _peekPending() {
    final pending = _pending;
    if (pending == null) return null;
    if (DateTime.now().difference(pending.endedAt) > _pendingMaxAge) {
      _pending = null;
      return null;
    }
    return pending.setup;
  }

  Future<void> _importShot(
    GaggiMateShotIndexEntry entry, {
    ShotSetupSnapshot? attachSetup,
  }) async {
    final log = parseGaggiMateShotLog(await _get(entry.fileName));
    if (log.samples.isEmpty) return;

    int? beanId;
    final wantedBean = attachSetup?.beanId;
    if (wantedBean != null) {
      if (await database.beanExists(wantedBean)) beanId = wantedBean;
    }

    // The GaggiMate doesn't write the profile into the recording, only its
    // ID. The local copy under that ID is attached to the shot — the import
    // runs right after the brew, so it is practically the version that ran.
    // Later changes to the profile thus don't skew the analysis of old
    // shots (same as for the Meticulous, schema 13).
    final profileId = log.profileId;
    final profile = profileId.isEmpty
        ? null
        : await database.storedProfile(profileId, machine: 'gaggimate');

    // The machine's clock can be far off without network; a shot from 1970
    // would mess up the history. The index is the more reliable source,
    // then the time from the file, then now.
    final timestamp = _plausible(entry.timestamp)
        ? entry.timestamp
        : (_plausible(log.startedAt) ? log.startedAt : DateTime.now());

    await database.insertShotWithReadings(
      ShotsCompanion.insert(
        timestamp: timestamp,
        externalId: Value(_externalId(entry.id)),
        machine: const Value('gaggimate'),
        beanId: Value(beanId),
        // The index carries the profile name; the file has the same one.
        profileName: Value(
          entry.profileName.isNotEmpty ? entry.profileName : log.profileName,
        ),
        // The GaggiMate has neither profile color nor image.
        doseGrams: Value(attachSetup?.doseGrams),
        grindSize: Value(attachSetup?.grindText),
        grindZero: Value(attachSetup?.grindZero),
        grinder: Value(attachSetup?.grinder),
        burrs: Value(attachSetup?.burrs),
        brewedWith: Value(attachSetup?.brewedWith),
        brewChainId: Value(attachSetup?.brewChainId),
        finalWeight: Value(entry.finalWeight ?? log.finalWeight),
        durationMs: Value(
          entry.durationMs > 0 ? entry.durationMs : log.durationMs,
        ),
        brewTemp: Value(entry.avgTemp ?? log.averageTemp),
        profileTemp: Value(log.targetTemp),
        profileJson: Value(profile?.json),
        stageExits: Value(
          log.phaseExits.isEmpty
              ? null
              : jsonEncode([for (final e in log.phaseExits) e.toJson()]),
        ),
      ),
      [
        for (final s in log.samples)
          (shotId) => ShotReadingsCompanion.insert(
            shotId: shotId,
            timeMs: s.timeMs,
            pressure: Value(s.pressure),
            flow: Value(s.pumpFlow),
            weight: Value(s.weight),
            gravimetricFlow: Value(s.scaleConnected ? s.scaleFlow : null),
            // One boiler sensor instead of the four Meticulous sensors: it
            // sits in the same place as the boiler band there, so the
            // temperature curve in the shot detail works for both machines.
            barUp: Value(s.currentTemp),
            stage: Value(s.stage),
          ),
      ],
      // Without bean/dose/grind size from the user, a plain import (sync:
      // doesn't count as a change, see insertShotWithReadings).
      untouchedImport:
          beanId == null &&
          attachSetup?.doseGrams == null &&
          attachSetup?.grindSize == null &&
          attachSetup?.grinder == null,
    );
  }

  // None of these machines pulled a shot before 2020.
  static bool _plausible(DateTime t) =>
      t.isAfter(DateTime(2020)) &&
      t.isBefore(DateTime.now().add(const Duration(days: 1)));
}
