import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../services/connection_log.dart';
import '../../database/database.dart';
import '../../services/profile_store.dart';
import '../espresso_machine.dart';
import 'gaggimate_service.dart';

// Keeps a local copy of the GaggiMate profiles — the same job as
// ProfileSyncService for the Meticulous, just over the WebSocket instead of
// REST (`req:profiles:list` for all, `req:profiles:load` for one).
//
// The profiles go into the same table as the Meticulous profiles,
// distinguished by the `machine` column. That way the profile row and
// profile view run on the same code for both machines.
//
// The GaggiMate profile JSON is stored **unchanged**; it is translated into
// the shared representation only when displayed (see
// gaggimate_profile_detail.dart). That keeps the copy valid even when the
// translation improves later.
class GaggiMateProfileSyncService implements ProfileStore {
  GaggiMateProfileSyncService({required this.database, required this.machine});

  final AppDatabase database;
  final GaggiMateService machine;

  @override
  String get machineKey => 'gaggimate';

  bool _wasConnected = false;
  Future<void>? _running;
  bool _disposed = false;

  void start() {
    machine.addListener(_onMachine);
    _onMachine();
  }

  void dispose() {
    _disposed = true;
    machine.removeListener(_onMachine);
  }

  void _onMachine() {
    final connected =
        machine.connectionState == MachineConnectionState.connected;
    if (connected && !_wasConnected) unawaited(sync());
    _wasConnected = connected;
  }

  @override
  Future<void> sync() {
    return _running ??= ConnectionLog.track('GaggiMate profile sync', () async {
      try {
        // The list already carries the full profiles — unlike the
        // Meticulous, no second call per profile is needed.
        final raw = await machine.fetchProfileList();
        if (raw.isEmpty) return;
        final known = await database.storedProfilesById(machine: machineKey);
        for (var i = 0; i < raw.length; i++) {
          if (_disposed) return;
          await _store(raw[i], i, known);
        }
        debugPrint('GaggiMateProfileSync: ${raw.length} profiles');
      } catch (e) {
        // Unreachable: the local copy stays valid.
        debugPrint('GaggiMate profile sync failed: $e');
      } finally {
        _running = null;
      }
    });
  }

  @override
  Future<bool> refresh(String id) async {
    try {
      final json = await machine.fetchProfileDetail(id);
      if (json == null) return false;
      final known = await database.storedProfilesById(machine: machineKey);
      await _store(json, known[id]?.position ?? 0, known);
      return true;
    } catch (e) {
      debugPrint('GaggiMate profile refresh failed ($id): $e');
      return false;
    }
  }

  @override
  Future<void> forget(String id) =>
      database.deleteStoredProfile(id, machine: machineKey);

  Future<void> _store(
    Map<String, dynamic> json,
    int position,
    Map<String, StoredProfile> known,
  ) async {
    final id = (json['id'] ?? '').toString();
    if (id.isEmpty) return;
    // `favorite` and `selected` change on every tap at the machine and say
    // nothing about the profile itself — they would keep triggering the
    // comparison below and rewrite the copy constantly.
    final stable = Map<String, dynamic>.from(json)
      ..remove('favorite')
      ..remove('selected');
    final encoded = jsonEncode(stable);
    final existing = known[id];
    if (existing != null &&
        existing.json == encoded &&
        existing.position == position) {
      return;
    }
    await database.upsertStoredProfile(
      StoredProfilesCompanion(
        id: Value(id),
        machine: Value(machineKey),
        name: Value((json['label'] ?? '').toString()),
        json: Value(encoded),
        position: Value(position),
        fetchedAt: Value(DateTime.now()),
      ),
    );
  }
}
