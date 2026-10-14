import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../database/database.dart';
import 'meticulous_socket_service.dart';
import 'profile_image_cache.dart';
import 'profile_store.dart';

// Keeps a local copy of all the machine's profiles (definition + image), so
// profile cards and the profile view work without a connection too. As with
// shots: what has been stored once stays — even if the machine later
// deletes the profile.
class ProfileSyncService implements ProfileStore {
  ProfileSyncService({
    required this.database,
    required this.socket,
    required this.imageDir,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    _images = ProfileImageCache(
      client: _client,
      imageDir: imageDir,
      hostname: () => socket.hostname,
    );
  }

  @override
  String get machineKey => 'meticulous';

  final AppDatabase database;
  final MeticulousSocketService socket;
  final Directory imageDir;
  final http.Client _client;
  late final ProfileImageCache _images;

  bool _wasConnected = false;
  Future<void>? _running;
  bool _disposed = false;

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
  }

  Future<dynamic> _getJson(String path) async {
    final response = await _client
        .get(Uri.parse('http://${socket.hostname}/api/v1/$path'))
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} for $path');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  // Sync all of the machine's profiles (never runs twice).
  @override
  Future<void> sync() {
    return _running ??= () async {
      try {
        final list = await _getJson('profile/list?full=true');
        if (list is! List) return;
        final known = await database.storedProfilesById(machine: machineKey);
        var position = 0;
        for (final entry in list) {
          if (_disposed) return;
          if (entry is Map) {
            await _store(Map<String, dynamic>.from(entry), position, known);
          }
          position++;
        }
        debugPrint('ProfileSync: ${list.length} profiles on the machine');
      } catch (e) {
        // Machine unreachable or similar: the local copy stays valid.
        debugPrint('Profile sync failed: $e');
      } finally {
        _running = null;
      }
    }();
  }

  // Fetch one profile fresh from the machine (when opening the view).
  // false = machine unreachable or profile no longer there.
  @override
  Future<bool> refresh(String id) async {
    try {
      final json = await _getJson('profile/get/$id');
      if (json is! Map) return false;
      final known = await database.storedProfilesById(machine: machineKey);
      await _store(
        Map<String, dynamic>.from(json),
        known[id]?.position ?? 0,
        known,
      );
      return true;
    } catch (e) {
      debugPrint('Profile refresh failed ($id): $e');
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
    final encoded = jsonEncode(json);
    final existing = known[id];
    final display = json['display'] is Map ? json['display'] as Map : const {};
    final apiImage = display['image'] is String
        ? display['image'] as String
        : null;

    // Only fetch the image if there is no local copy yet.
    var imagePath = existing?.imagePath;
    if (apiImage != null &&
        (imagePath == null || !File(imagePath).existsSync())) {
      imagePath = await _images.cache(apiImage);
    }

    final unchanged =
        existing != null &&
        existing.json == encoded &&
        existing.position == position &&
        existing.imagePath == imagePath;
    if (unchanged) return;
    await database.upsertStoredProfile(
      StoredProfilesCompanion(
        id: Value(id),
        machine: Value(machineKey),
        name: Value((json['name'] ?? '').toString()),
        json: Value(encoded),
        imagePath: Value(imagePath),
        position: Value(position),
        fetchedAt: Value(DateTime.now()),
      ),
    );
  }
}
