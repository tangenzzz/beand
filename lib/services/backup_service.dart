import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database.dart';
import '../sync/crypto/backup_cipher.dart';

/// Version of the backup format. Written into manifest.json; a backup with
/// a higher version is rejected on restore instead of being half read.
/// 2: optional sync.json (sync key).
const backupFormatVersion = 2;

/// Name of the database file in the app folder (see comment in database.dart:
/// still called coffee_app.sqlite for compatibility reasons).
const backupDbFileName = 'coffee_app.sqlite';

const _manifestName = 'manifest.json';
const _prefsName = 'prefs.json';
const _syncName = 'sync.json';

/// Extension of a fully encrypted backup (backup_cipher.dart).
const encryptedBackupExtension = 'beandbak';

/// Sync in the backup: the key only encrypted with a password
/// (NIP-49, `ncryptsec1…`), plus the servers, so a new device can sync right
/// after restoring. Never included: device id and "last synced" — those
/// belong to the device (sync_state_store.dart).
class BackupSyncInfo {
  const BackupSyncInfo({
    required this.ncryptsec,
    required this.npub,
    required this.enabled,
    required this.relays,
    required this.blobServers,
  });

  final String ncryptsec;
  final String npub;
  final bool enabled;
  final List<String> relays;
  final List<String> blobServers;

  Map<String, Object?> toJson() => {
    'ncryptsec': ncryptsec,
    'npub': npub,
    'enabled': enabled,
    'relays': relays,
    'blobServers': blobServers,
  };

  static BackupSyncInfo? fromJson(Map<String, Object?> json) {
    final key = json['ncryptsec'];
    if (key is! String || !key.startsWith('ncryptsec1')) return null;
    List<String> list(String name) => [
      for (final v in (json[name] as List?) ?? const [])
        if (v is String) v,
    ];
    return BackupSyncInfo(
      ncryptsec: key,
      npub: json['npub'] as String? ?? '',
      enabled: json['enabled'] == true,
      relays: list('relays'),
      blobServers: list('blobServers'),
    );
  }
}

const _filesPrefix = 'files/';

/// Columns that hold absolute file paths. When restoring onto another device
/// (or after a reinstall with a different app folder) they must be rewritten
/// to the new folder, otherwise bean and profile images point nowhere.
const _pathColumns = <String, List<String>>{
  'beans': ['photo_path'],
  'shots': ['shot_photo_path', 'profile_image_path'],
  'stored_profiles': ['image_path', 'custom_image_path'],
};

/// What a backup contains — for display before restoring.
class BackupManifest {
  const BackupManifest({
    required this.format,
    required this.createdAt,
    required this.schemaVersion,
    required this.docsPath,
    required this.beans,
    required this.shots,
    required this.readings,
    required this.profiles,
    required this.photos,
    required this.settings,
    this.syncNpub,
  });

  final int format;
  final DateTime createdAt;
  final int schemaVersion;

  /// App folder the backup comes from.
  final String docsPath;

  final int beans;
  final int shots;
  final int readings;
  final int profiles;

  /// Number of backed-up files excluding the database itself (photos, images).
  final int photos;
  final int settings;

  /// Public sync key, if the (encrypted) key is included in the backup.
  final String? syncNpub;

  Map<String, Object?> toJson() => {
    'format': format,
    'app': "bean'd",
    'createdAt': createdAt.toIso8601String(),
    'schemaVersion': schemaVersion,
    'dbFileName': backupDbFileName,
    'docsPath': docsPath,
    'counts': {
      'beans': beans,
      'shots': shots,
      'readings': readings,
      'profiles': profiles,
      'photos': photos,
      'settings': settings,
    },
    if (syncNpub != null) 'syncNpub': syncNpub,
  };

  static BackupManifest fromJson(Map<String, Object?> json) {
    final counts = (json['counts'] as Map?)?.cast<String, Object?>() ?? {};
    int count(String key) => (counts[key] as num?)?.toInt() ?? 0;
    return BackupManifest(
      format: (json['format'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
      docsPath: json['docsPath'] as String? ?? '',
      beans: count('beans'),
      shots: count('shots'),
      readings: count('readings'),
      profiles: count('profiles'),
      photos: count('photos'),
      settings: count('settings'),
      syncNpub: json['syncNpub'] as String?,
    );
  }
}

/// Backup is unusable (not a zip, wrong format, from a newer app version).
/// The message is meant for the user.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Full backup: the whole app folder (database + all images) plus the
/// settings from SharedPreferences, together in one zip file.
///
/// Deliberately the whole folder instead of a list of individual subfolders
/// — so anything added in the future automatically ends up in the backup
/// without this class having to be adjusted.
/// Folder of the safety copy before "Replace" (see createSafetyCopy).
Future<Directory> safetyCopyDir() async => Directory(
  p.join((await getApplicationSupportDirectory()).path, 'safety-copy'),
);

class BackupService {
  BackupService({
    required this.db,
    required this.docsDir,
    required this.prefs,
    AppDatabase Function(File dbFile)? openRestoredDb,
  }) : _openRestoredDb =
           openRestoredDb ?? ((file) => AppDatabase(NativeDatabase(file)));

  final AppDatabase db;
  final Directory docsDir;
  final SharedPreferences prefs;
  final AppDatabase Function(File dbFile) _openRestoredDb;

  /// Suggested file name with timestamp, e.g. beand-backup-2026-09-27-1830.zip
  /// (encrypted: .beandbak).
  static String suggestedFileName([DateTime? now, bool encrypted = false]) {
    final t = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'beand-backup-${t.year}-${two(t.month)}-${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}'
        '.${encrypted ? encryptedBackupExtension : 'zip'}';
  }

  /// Safety copy before "Replace" when linking: lives in the app support
  /// folder [dir] — NOT in the documents folder, otherwise it would end up
  /// in the next backup. There is only ever the newest one; without the sync
  /// key (the device's key is exactly what changes during linking).
  Future<File> createSafetyCopy(Directory dir, {DateTime? now}) async {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    final t = now ?? DateTime.now();
    return createBackup(
      targetDir: dir,
      now: t,
      fileName: suggestedFileName(t).replaceFirst('backup', 'before-replace'),
    );
  }

  /// The safety copy in [dir], if there is one.
  static File? safetyCopyIn(Directory dir) {
    if (!dir.existsSync()) return null;
    final files = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.zip'),
    );
    return files.isEmpty ? null : files.first;
  }

  /// Writes the backup to [targetDir] and returns the file. With [sync] the
  /// encrypted sync key is included; with [encryptPassword] the whole file
  /// is encrypted (scrypt in an isolate, takes a few seconds).
  Future<File> createBackup({
    required Directory targetDir,
    String? fileName,
    DateTime? now,
    BackupSyncInfo? sync,
    String? encryptPassword,
  }) async {
    // Write open WAL transactions into the main file, otherwise the copied
    // file misses the latest changes. Fails silently if the DB is not in
    // WAL mode — then everything is in there already anyway.
    try {
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}

    targetDir.createSync(recursive: true);
    final zipFile = File(
      p.join(
        targetDir.path,
        encryptPassword == null
            ? (fileName ?? suggestedFileName(now))
            : '${fileName ?? suggestedFileName(now, true)}.zip.tmp',
      ),
    );
    if (zipFile.existsSync()) zipFile.deleteSync();

    final files = _filesToBackup();
    final prefsJson = _prefsToJson();
    final manifest = BackupManifest(
      format: backupFormatVersion,
      createdAt: now ?? DateTime.now(),
      schemaVersion: db.schemaVersion,
      docsPath: docsDir.path,
      beans: await _count('beans', where: 'deleted = 0'),
      shots: await _count('shots', where: 'deleted_at IS NULL'),
      readings: await _count('shot_readings'),
      profiles: await _count('stored_profiles', where: 'deleted = 0'),
      photos: files.where((f) => p.basename(f.path) != backupDbFileName).length,
      settings: prefsJson.length,
      syncNpub: sync?.npub,
    );

    final encoder = ZipFileEncoder()..create(zipFile.path);
    try {
      _addText(encoder, _manifestName, _pretty(manifest.toJson()));
      _addText(encoder, _prefsName, _pretty(prefsJson));
      if (sync != null) _addText(encoder, _syncName, _pretty(sync.toJson()));
      for (final file in files) {
        final name = p.url.joinAll([
          _filesPrefix,
          ...p.split(p.relative(file.path, from: docsDir.path)),
        ]);
        await encoder.addFile(file, name);
      }
    } finally {
      await encoder.close();
    }
    if (encryptPassword == null) return zipFile;

    final encrypted = File(
      p.join(targetDir.path, fileName ?? suggestedFileName(now, true)),
    );
    try {
      await Isolate.run(
        () => encryptBackupFile(zipFile, encrypted, encryptPassword),
      );
    } finally {
      zipFile.deleteSync();
    }
    return encrypted;
  }

  /// Decrypts a fully encrypted backup into [targetDir]; returns the zip to
  /// continue with as usual. Throws [BackupException] on a wrong password.
  Future<File> decryptBackup(
    File encrypted,
    String password, {
    required Directory targetDir,
  }) async {
    targetDir.createSync(recursive: true);
    final zip = File(p.join(targetDir.path, 'decrypted-backup.zip'));
    try {
      await Isolate.run(() => decryptBackupFile(encrypted, zip, password));
    } on BackupCipherException catch (e) {
      if (zip.existsSync()) zip.deleteSync();
      throw BackupException(e.message);
    }
    return zip;
  }

  /// Sync part of the backup, null without a sync key.
  Future<BackupSyncInfo?> readSyncInfo(File zip) =>
      _withArchive(zip, (archive) {
        final entry = archive.findFile(_syncName);
        if (entry == null) return null;
        try {
          return BackupSyncInfo.fromJson(
            (jsonDecode(utf8.decode(entry.content as List<int>)) as Map)
                .cast<String, Object?>(),
          );
        } catch (_) {
          return null;
        }
      });

  /// Reads only manifest.json without changing anything — for the
  /// confirmation dialog before restoring.
  Future<BackupManifest> readManifest(File zip) =>
      _withArchive(zip, _manifestOf);

  BackupManifest _manifestOf(Archive archive) {
    final entry = archive.findFile(_manifestName);
    if (entry == null) {
      throw const BackupException('No backup manifest in this file.');
    }
    final Map<String, Object?> json;
    try {
      json = (jsonDecode(utf8.decode(entry.content as List<int>)) as Map)
          .cast<String, Object?>();
    } catch (_) {
      throw const BackupException('Backup manifest is damaged.');
    }
    final manifest = BackupManifest.fromJson(json);
    if (manifest.format > backupFormatVersion) {
      throw const BackupException(
        'This backup was made by a newer version of the app.',
      );
    }
    if (manifest.schemaVersion > db.schemaVersion) {
      throw const BackupException(
        'This backup has a newer database version than this app.',
      );
    }
    if (archive.findFile('$_filesPrefix$backupDbFileName') == null) {
      throw const BackupException('This backup contains no database.');
    }
    return manifest;
  }

  /// Replaces database, images and settings with the contents of [zip].
  ///
  /// Closes [db] in the process — the app must be restarted afterwards,
  /// because all services still point to the old, closed connection.
  Future<BackupManifest> restore(File zip) =>
      _withArchive(zip, (archive) => _restoreFrom(archive));

  Future<BackupManifest> _restoreFrom(Archive archive) async {
    final manifest = _manifestOf(archive);

    await db.close();

    // Clear out old content (incl. -wal/-shm of the old DB), so no leftover
    // beans/profiles remain that are not in the backup.
    if (docsDir.existsSync()) {
      for (final entity in docsDir.listSync()) {
        entity.deleteSync(recursive: true);
      }
    } else {
      docsDir.createSync(recursive: true);
    }

    for (final entry in archive.files) {
      if (!entry.isFile || !entry.name.startsWith(_filesPrefix)) continue;
      final relative = entry.name.substring(_filesPrefix.length);
      // Zip entries must not lead outside the target folder.
      final target = File(
        p.join(docsDir.path, p.joinAll(p.url.split(relative))),
      );
      if (!p.isWithin(docsDir.path, target.path)) continue;
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(entry.content as List<int>, flush: true);
    }

    await _restorePrefs(archive);
    await _rewritePaths(manifest.docsPath);
    return manifest;
  }

  List<File> _filesToBackup() {
    if (!docsDir.existsSync()) return const [];
    return docsDir
        .listSync(recursive: true)
        .whereType<File>()
        // -wal/-shm are redundant after the checkpoint and would override
        // the copied main file on restore.
        .where((f) => !f.path.endsWith('-wal') && !f.path.endsWith('-shm'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  Map<String, Object?> _prefsToJson() {
    final out = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value is bool) {
        out[key] = {'type': 'bool', 'value': value};
      } else if (value is int) {
        out[key] = {'type': 'int', 'value': value};
      } else if (value is double) {
        out[key] = {'type': 'double', 'value': value};
      } else if (value is String) {
        out[key] = {'type': 'string', 'value': value};
      } else if (value is List<String>) {
        out[key] = {'type': 'stringList', 'value': value};
      }
    }
    return out;
  }

  Future<void> _restorePrefs(Archive archive) async {
    final entry = archive.findFile(_prefsName);
    if (entry == null) return;
    Map<String, Object?> json;
    try {
      json = (jsonDecode(utf8.decode(entry.content as List<int>)) as Map)
          .cast<String, Object?>();
    } catch (_) {
      return;
    }
    await prefs.clear();
    for (final entry in json.entries) {
      final spec = (entry.value as Map?)?.cast<String, Object?>();
      final value = spec?['value'];
      switch (spec?['type']) {
        case 'bool':
          if (value is bool) await prefs.setBool(entry.key, value);
        case 'int':
          if (value is num) await prefs.setInt(entry.key, value.toInt());
        case 'double':
          if (value is num) await prefs.setDouble(entry.key, value.toDouble());
        case 'string':
          if (value is String) await prefs.setString(entry.key, value);
        case 'stringList':
          if (value is List) {
            await prefs.setStringList(
              entry.key,
              value.whereType<String>().toList(),
            );
          }
      }
    }
  }

  /// Redirects image paths from the backup's app folder to the local one.
  /// Opens the restored file once fresh — which also runs the drift
  /// migration if the backup comes from an older schema version.
  Future<void> _rewritePaths(String oldDocsPath) async {
    final restored = _openRestoredDb(
      File(p.join(docsDir.path, backupDbFileName)),
    );
    try {
      if (oldDocsPath.isNotEmpty && oldDocsPath != docsDir.path) {
        for (final table in _pathColumns.entries) {
          for (final column in table.value) {
            await restored.customStatement(
              'UPDATE ${table.key} SET $column = '
              'replace($column, ?, ?) WHERE $column LIKE ? || \'%\'',
              [oldDocsPath, docsDir.path, oldDocsPath],
            );
          }
        }
      } else {
        // Open once even without a path change, so a pending migration
        // happens here and not only on the next app start.
        await restored.customSelect('SELECT 1').get();
      }
    } finally {
      await restored.close();
    }
  }

  Future<int> _count(String table, {String? where}) async {
    final sql =
        'SELECT COUNT(*) AS c FROM $table'
        '${where == null ? '' : ' WHERE $where'}';
    final row = await db.customSelect(sql).getSingle();
    return row.read<int>('c');
  }

  /// Opens the zip as a stream (not fully into memory) and closes it again
  /// afterwards — a backup can be several hundred MB large.
  Future<T> _withArchive<T>(
    File zip,
    FutureOr<T> Function(Archive) body,
  ) async {
    final stream = InputFileStream(zip.path);
    try {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBuffer(stream);
      } catch (_) {
        throw const BackupException('This file is not a readable backup.');
      }
      return await body(archive);
    } finally {
      await stream.close();
    }
  }

  void _addText(ZipFileEncoder encoder, String name, String content) {
    final bytes = utf8.encode(content);
    encoder.addArchiveFile(ArchiveFile(name, bytes.length, bytes));
  }

  String _pretty(Object? json) =>
      const JsonEncoder.withIndent('  ').convert(json);
}
