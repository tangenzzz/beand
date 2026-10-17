import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../database/database.dart';
import '../models/history_import.dart';
import 'meticulous_socket_service.dart';
import 'profile_image_cache.dart';
import 'shot_setup.dart';

// Keeps the local DB complete: every shot of the machine ends up permanently
// in the app and stays there, even if the machine is unreachable or deletes
// the shot later (other apps only show shots while connected).
//
// The source is the machine's history (GET /api/v1/history, with time series
// and stage per data point). Syncing happens
//  - on (re)connect: everything the app does not know yet
//    (including shots pulled without the app),
//  - after every shot observed live (`extracting` true -> false), with
//    retries, because the machine only stores the entry shortly afterwards.
// Bean/dose/grind size are only known to the app: they are captured from the
// pre-shot card (ShotSetup) at shot start and assigned to the new entry.
class ShotSyncService {
  ShotSyncService({
    required this.database,
    required this.socket,
    required this.setup,
    required this.imageDir,
    http.Client? client,
    this.retryDelays = const [
      Duration(milliseconds: 1500),
      Duration(seconds: 4),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
  }) : _client = client ?? http.Client();

  final AppDatabase database;
  final MeticulousSocketService socket;
  final ShotSetup setup;
  final Directory imageDir;
  final List<Duration> retryDelays;
  final http.Client _client;
  late final ProfileImageCache _images = ProfileImageCache(
    client: _client,
    imageDir: imageDir,
    hostname: () => socket.hostname,
  );

  bool _wasConnected = false;
  bool _wasExtracting = false;
  ShotSetupSnapshot? _liveSetup;
  ({ShotSetupSnapshot setup, DateTime endedAt})? _pending;

  Future<void>? _running;
  bool _rerun = false;
  bool _disposed = false;

  // A newly finished shot only counts as "the one just observed" for a
  // limited time (protects against a stale assignment after a long pause).
  static const _pendingMaxAge = Duration(minutes: 5);

  void start() {
    socket.addListener(_onSocket);
    _onSocket();
  }

  void dispose() {
    _disposed = true;
    socket.removeListener(_onSocket);
    _client.close();
  }

  void _onSocket() {
    final connected =
        socket.connectionState == MachineConnectionState.connected;
    if (connected && !_wasConnected) unawaited(sync());
    _wasConnected = connected;

    final extracting = socket.latestStatus?.extracting ?? false;
    if (extracting && !_wasExtracting) {
      _liveSetup = setup.snapshot();
    } else if (!extracting && _wasExtracting) {
      final live = _liveSetup;
      if (live != null) {
        _pending = (setup: live, endedAt: DateTime.now());
        unawaited(_syncAfterShot());
      }
    }
    _wasExtracting = extracting;
  }

  Future<void> _syncAfterShot() async {
    for (final delay in retryDelays) {
      await Future<void>.delayed(delay);
      if (_disposed || _pending == null) return;
      await sync(recentOnly: true);
    }
  }

  // Never runs twice: a request during a run triggers exactly one more
  // pass.
  Future<void> sync({bool recentOnly = false}) {
    if (_running != null) {
      _rerun = true;
      return _running!;
    }
    return _running = () async {
      try {
        do {
          _rerun = false;
          await _syncOnce(recentOnly: recentOnly);
        } while (_rerun && !_disposed);
      } finally {
        _running = null;
      }
    }();
  }

  Future<dynamic> _getJson(String path) async {
    final response = await _client
        .get(Uri.parse('http://${socket.hostname}/api/v1/$path'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} for $path');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<void> _syncOnce({required bool recentOnly}) async {
    debugPrint(
      'ShotSync: start (recentOnly=$recentOnly) host=${socket.hostname}',
    );
    try {
      // Short list without time series (281 KB for 103 shots), details
      // afterwards only for the unknown ones.
      final listing = await _getJson(
        'history?dump_data=false&max_results=${recentOnly ? 15 : 100000}',
      );
      final entries = [
        for (final e in (listing['history'] as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e),
      ];
      debugPrint('ShotSync: machine lists ${entries.length} shots');
      // Backfill target temperature (older imports did not have it yet).
      await database.backfillProfileTemps({
        for (final e in entries)
          if (e['id'] is String &&
              e['profile'] is Map &&
              (e['profile'] as Map)['temperature'] is num)
            e['id'] as String: ((e['profile'] as Map)['temperature'] as num)
                .toDouble(),
      });
      // Backfill the profile at brew time (schema 13).
      await database.backfillShotProfiles({
        for (final e in entries)
          if (e['id'] is String)
            e['id'] as String: ?compactShotProfile(e['profile']),
      });
      final known = await database.knownExternalIds();
      final missing = entries.where((e) => !known.contains(e['id'])).toList()
        ..sort(
          (a, b) =>
              ((a['time'] as num?) ?? 0).compareTo((b['time'] as num?) ?? 0),
        );
      debugPrint('ShotSync: ${missing.length} new');
      for (var i = 0; i < missing.length; i++) {
        if (_disposed) return;
        final isNewest = i == missing.length - 1;
        try {
          await _importShot(
            missing[i]['id'] as String,
            attachSetup: isNewest ? _takePending() : null,
          );
        } catch (e) {
          debugPrint('Shot import failed (${missing[i]['id']}): $e');
        }
      }
    } catch (e) {
      // Machine unreachable or similar: retry on next connect.
      debugPrint('History sync failed: $e');
    }
  }

  ShotSetupSnapshot? _takePending() {
    final pending = _pending;
    if (pending == null) return null;
    _pending = null;
    if (DateTime.now().difference(pending.endedAt) > _pendingMaxAge) {
      return null;
    }
    return pending.setup;
  }

  Future<void> _importShot(String id, {ShotSetupSnapshot? attachSetup}) async {
    final full = await _getJson('history?ids=$id');
    final list = full['history'] as List? ?? const [];
    if (list.isEmpty) return;
    final parsed = parseHistoryEntry(
      Map<String, dynamic>.from(list.first as Map),
    );
    if (parsed == null) return;

    final imagePath = await _images.cache(parsed.profileImageApiPath);

    int? beanId;
    final wantedBean = attachSetup?.beanId;
    if (wantedBean != null) {
      if (await database.beanExists(wantedBean)) beanId = wantedBean;
    }

    await database.insertShotWithReadings(
      ShotsCompanion.insert(
        timestamp: parsed.timestamp,
        externalId: Value(parsed.externalId),
        machine: const Value('meticulous'),
        beanId: Value(beanId),
        profileName: Value(parsed.profileName),
        profileColor: Value(parsed.profileColor),
        profileImagePath: Value(imagePath),
        doseGrams: Value(attachSetup?.doseGrams),
        grindSize: Value(attachSetup?.grindSize?.toStringAsFixed(1)),
        grinder: Value(attachSetup?.grinder),
        burrs: Value(attachSetup?.burrs),
        finalWeight: Value(parsed.finalWeight),
        durationMs: Value(parsed.durationMs),
        brewTemp: Value(parsed.brewTemp),
        profileTemp: Value(parsed.profileTemp),
        profileJson: Value(parsed.profileJson),
      ),
      parsed.readings,
      // Without bean/dose/grind size from the user it is a plain import
      // (sync: does not count as a change, see insertShotWithReadings).
      untouchedImport:
          beanId == null &&
          attachSetup?.doseGrams == null &&
          attachSetup?.grindSize == null &&
          attachSetup?.grinder == null,
    );
  }
}
