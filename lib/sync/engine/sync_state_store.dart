import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Sync state on THIS device: on/off, relay list, last sync per relay.
// Stored as a separate file in the app support folder — NOT in
// shared_preferences and not in the documents folder, both of which go
// into the backup (Settings → Backup): a restored "last synced at …" would
// keep a device from ever fully fetching the others' data. The file is
// also excluded from Android auto backup (res/xml/backup_rules.xml).

/// Device announcement — applies only to the key [pubkey]; after a key
/// change it starts empty.
class PresenceState {
  PresenceState({
    required this.pubkey,
    Set<String>? relays,
    Map<String, int>? devices,
    this.initialized = false,
    this.lastPublishedAt,
    this.lastResendAt,
  }) : relays = relays ?? {},
       devices = devices ?? {};

  final String pubkey;

  /// Relays that accepted our own announcement. If it is missing there
  /// later, the relay lost data (cleaned up, deleted) → resend everything.
  Set<String> relays;

  /// Other devices: ID → last seen (Unix ms).
  Map<String, int> devices;

  /// First round done: from then on an unknown device counts as new.
  /// (The first time ALL are unknown — no reason to send everything.)
  bool initialized;

  /// Unix ms of the last own announcement or the last full upload.
  int? lastPublishedAt;
  int? lastResendAt;

  Map<String, Object?> toJson() => {
    'pubkey': pubkey,
    'relays': relays.toList(),
    'devices': devices,
    'initialized': initialized,
    'lastPublishedAt': ?lastPublishedAt,
    'lastResendAt': ?lastResendAt,
  };

  static PresenceState? fromJson(Object? json) {
    if (json is! Map || json['pubkey'] is! String) return null;
    return PresenceState(
      pubkey: json['pubkey'] as String,
      relays: {
        for (final r in (json['relays'] as List?) ?? const [])
          if (r is String) r,
      },
      devices: {
        for (final e in ((json['devices'] as Map?) ?? const {}).entries)
          if (e.key is String && e.value is int)
            e.key as String: e.value as int,
      },
      initialized: json['initialized'] == true,
      lastPublishedAt: json['lastPublishedAt'] is int
          ? json['lastPublishedAt'] as int
          : null,
      lastResendAt: json['lastResendAt'] is int
          ? json['lastResendAt'] as int
          : null,
    );
  }
}

class SyncStateData {
  SyncStateData({
    this.enabled = false,
    List<String>? relays,
    Map<String, int>? lastSync,
    this.typesVersion = 0,
    this.lastSuccessAt,
    this.resendAll = false,
    Map<String, String>? pendingLinks,
    List<String>? blobServers,
    this.blobDefaultsApplied = false,
    this.presence,
  }) : relays = relays ?? [],
       blobServers = blobServers ?? [],
       lastSync = lastSync ?? {},
       pendingLinks = pendingLinks ?? {};

  bool enabled;
  List<String> relays;

  /// Photo servers (Blossom), phase 4. Empty = photos stay on the device.
  List<String> blobServers;

  /// The public photo servers were added once. Never again on their own
  /// after that — whoever removes them does not want them.
  bool blobDefaultsApplied;

  /// Unix seconds per relay URL: start of the last complete fetch.
  Map<String, int> lastSync;

  /// Which record types the device already knew at the last fetch (see
  /// SyncEngine.typesVersion). If a type is added, it fetches everything
  /// once, otherwise it would miss the older events of the new type.
  int typesVersion;

  /// Last sync without errors (for display).
  DateTime? lastSuccessAt;

  /// Send everything once on the next start — set after restoring a
  /// backup while the database is closed.
  bool resendAll;

  /// Shots whose bean had not arrived yet: shot syncId → bean syncId.
  /// Filled in as soon as the bean is there.
  Map<String, String> pendingLinks;

  /// Device announcement; null = never.
  PresenceState? presence;

  /// Device announcement state for [pubkey] (fresh after a key change).
  PresenceState presenceFor(String pubkey) {
    final current = presence;
    if (current != null && current.pubkey == pubkey) return current;
    return presence = PresenceState(pubkey: pubkey);
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'relays': relays,
    'lastSync': lastSync,
    'typesVersion': typesVersion,
    'lastSuccessAt': lastSuccessAt?.millisecondsSinceEpoch,
    'resendAll': resendAll,
    'pendingLinks': pendingLinks,
    'blobServers': blobServers,
    'blobDefaultsApplied': blobDefaultsApplied,
    if (presence != null) 'presence': presence!.toJson(),
  };

  factory SyncStateData.fromJson(Map<String, Object?> json) => SyncStateData(
    enabled: json['enabled'] == true,
    relays: [
      for (final r in (json['relays'] as List?) ?? const [])
        if (r is String) r,
    ],
    lastSync: {
      for (final e in ((json['lastSync'] as Map?) ?? const {}).entries)
        if (e.key is String && e.value is int) e.key as String: e.value as int,
    },
    typesVersion: json['typesVersion'] is int ? json['typesVersion'] as int : 0,
    lastSuccessAt: json['lastSuccessAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(json['lastSuccessAt'] as int)
        : null,
    resendAll: json['resendAll'] == true,
    blobDefaultsApplied: json['blobDefaultsApplied'] == true,
    blobServers: [
      for (final r in (json['blobServers'] as List?) ?? const [])
        if (r is String) r,
    ],
    pendingLinks: {
      for (final e in ((json['pendingLinks'] as Map?) ?? const {}).entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
    },
    presence: PresenceState.fromJson(json['presence']),
  );
}

abstract class SyncStateStore {
  Future<SyncStateData> load();
  Future<void> save(SyncStateData data);
}

class FileSyncStateStore implements SyncStateStore {
  FileSyncStateStore({this.directory});

  static const fileName = 'sync_state.json';

  /// Only for tests; otherwise the app support folder.
  final Directory? directory;

  Future<File> _file() async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return File(p.join(dir.path, fileName));
  }

  @override
  Future<SyncStateData> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return SyncStateData();
      final json = jsonDecode(await file.readAsString());
      if (json is Map) return SyncStateData.fromJson(json.cast());
    } catch (e) {
      debugPrint('Sync state unreadable, starting fresh: $e');
    }
    return SyncStateData();
  }

  @override
  Future<void> save(SyncStateData data) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    // Write next to it first, then rename: if the app aborts midway, the
    // old file stays intact.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}

class InMemorySyncStateStore implements SyncStateStore {
  SyncStateData _data = SyncStateData();

  @override
  Future<SyncStateData> load() async => SyncStateData.fromJson(
    jsonDecode(jsonEncode(_data.toJson())) as Map<String, Object?>,
  );

  @override
  Future<void> save(SyncStateData data) async => _data = data;
}
