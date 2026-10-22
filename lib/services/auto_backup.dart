import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:saf_folder/saf_folder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../database/database.dart';
import '../sync/crypto/nip49.dart';
import '../sync/engine/sync_state_store.dart';
import '../sync/identity/key_store.dart';
import 'backup_service.dart';

// Auto backup (Settings → Backup): at set times the app writes a backup on
// its own and overwrites the same file each time, `beand-auto-backup.zip`
// in a folder the user picked once (Storage Access Framework, see
// packages/saf_folder).
//
// Runs through Android's WorkManager: one one-off task, always queued for
// the next slot; each run queues the following one. WorkManager runs it in
// the open app's engine if there is one, otherwise in a background engine
// of its own — the app does not have to be open. Doze may push a run back
// a little; as a fallback the app checks at every start whether a slot was
// missed.
//
// iOS has no exact times: the slot becomes the earliest start of a
// background processing task (BGTaskScheduler), which iOS runs when it
// sees fit, mostly at night while charging. The folder is a document
// picker bookmark (saf_folder's iOS side). The catch-up at app start
// matters more there.
//
// Sync key and encryption need a password, and nobody is there to type
// it: so it is entered once when setting up and kept in the secure key
// store (like the sync key itself), see [AutoBackupPassword]. Each run
// locks the sync key with it and, if chosen, encrypts the whole file. Only
// a restore asks for it again.

enum AutoBackupFrequency {
  off('Off'),
  daily('Daily'),
  weekly('Weekly');

  const AutoBackupFrequency(this.label);
  final String label;
}

@immutable
class AutoBackupConfig {
  const AutoBackupConfig({
    this.frequency = AutoBackupFrequency.off,
    this.weekday = DateTime.sunday,
    this.minuteOfDay = 3 * 60,
    this.folderUri,
    this.folderName,
    this.encrypt = false,
    this.armedAt,
    this.lastAt,
    this.lastBytes,
    this.lastError,
    this.lastErrorAt,
  });

  final AutoBackupFrequency frequency;

  /// For [AutoBackupFrequency.weekly]: DateTime.monday … DateTime.sunday.
  final int weekday;

  /// Time of day, minutes after midnight (local time).
  final int minuteOfDay;

  final String? folderUri;
  final String? folderName;

  /// Encrypt the whole file (.beandbak) with the stored password.
  final bool encrypt;

  /// When the schedule was last set. Slots before that do not count as
  /// missed — otherwise turning it on at 14:00 with 03:00 would back up
  /// right away.
  final DateTime? armedAt;

  /// Last successful backup and its size.
  final DateTime? lastAt;
  final int? lastBytes;

  /// Last failure (cleared by the next success).
  final String? lastError;
  final DateTime? lastErrorAt;

  bool get enabled => frequency != AutoBackupFrequency.off;

  AutoBackupConfig copyWith({
    AutoBackupFrequency? frequency,
    int? weekday,
    int? minuteOfDay,
    String? folderUri,
    String? folderName,
    bool? encrypt,
    DateTime? armedAt,
    DateTime? lastAt,
    int? lastBytes,
    String? lastError,
    DateTime? lastErrorAt,
    bool clearError = false,
  }) => AutoBackupConfig(
    frequency: frequency ?? this.frequency,
    weekday: weekday ?? this.weekday,
    minuteOfDay: minuteOfDay ?? this.minuteOfDay,
    folderUri: folderUri ?? this.folderUri,
    folderName: folderName ?? this.folderName,
    encrypt: encrypt ?? this.encrypt,
    armedAt: armedAt ?? this.armedAt,
    lastAt: lastAt ?? this.lastAt,
    lastBytes: lastBytes ?? this.lastBytes,
    lastError: clearError ? null : (lastError ?? this.lastError),
    lastErrorAt: clearError ? null : (lastErrorAt ?? this.lastErrorAt),
  );

  Map<String, Object?> toJson() => {
    'frequency': frequency.name,
    'weekday': weekday,
    'minuteOfDay': minuteOfDay,
    'folderUri': folderUri,
    'folderName': folderName,
    'encrypt': encrypt,
    'armedAt': armedAt?.toIso8601String(),
    'lastAt': lastAt?.toIso8601String(),
    'lastBytes': lastBytes,
    'lastError': lastError,
    'lastErrorAt': lastErrorAt?.toIso8601String(),
  };

  static AutoBackupConfig fromJson(Map<String, Object?> json) {
    DateTime? time(String key) => DateTime.tryParse(json[key] as String? ?? '');
    return AutoBackupConfig(
      frequency: AutoBackupFrequency.values.firstWhere(
        (f) => f.name == json['frequency'],
        orElse: () => AutoBackupFrequency.off,
      ),
      weekday: (json['weekday'] as num?)?.toInt() ?? DateTime.sunday,
      minuteOfDay: (json['minuteOfDay'] as num?)?.toInt() ?? 3 * 60,
      folderUri: json['folderUri'] as String?,
      folderName: json['folderName'] as String?,
      encrypt: json['encrypt'] == true,
      armedAt: time('armedAt'),
      lastAt: time('lastAt'),
      lastBytes: (json['lastBytes'] as num?)?.toInt(),
      lastError: json['lastError'] as String?,
      lastErrorAt: time('lastErrorAt'),
    );
  }

  // ---- Schedule ----

  DateTime _at(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
    minuteOfDay ~/ 60,
    minuteOfDay % 60,
  );

  /// The latest slot at or before [now]; null when off.
  DateTime? latestSlot(DateTime now) {
    if (!enabled) return null;
    var day = DateTime(now.year, now.month, now.day);
    for (var i = 0; i < 8; i++) {
      final slot = _at(day);
      final dayFits =
          frequency == AutoBackupFrequency.daily || day.weekday == weekday;
      if (dayFits && !slot.isAfter(now)) return slot;
      // Calendar step instead of 24 h, so a DST switch does not shift it.
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return null;
  }

  /// The first slot after [now]; null when off.
  DateTime? nextSlot(DateTime now) {
    if (!enabled) return null;
    var day = DateTime(now.year, now.month, now.day);
    for (var i = 0; i < 8; i++) {
      final slot = _at(day);
      final dayFits =
          frequency == AutoBackupFrequency.daily || day.weekday == weekday;
      if (dayFits && slot.isAfter(now)) return slot;
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return null;
  }

  /// Was a slot missed since the last backup (or since it was set)?
  bool isDue(DateTime now) {
    final slot = latestSlot(now);
    if (slot == null || folderUri == null) return false;
    final since = [lastAt, armedAt].whereType<DateTime>().fold<DateTime?>(
      null,
      (a, b) => a == null || b.isAfter(a) ? b : a,
    );
    return since == null || slot.isAfter(since);
  }
}

/// Lives in the app support folder, not in the prefs: the folder
/// permission belongs to this device, and a restore (which replaces all
/// prefs) must not take the schedule away. Also read fresh from disk each
/// time — the background engine is a separate isolate with its own caches.
class AutoBackupStore {
  AutoBackupStore(this.file);

  final File file;

  static Future<AutoBackupStore> platform() async => AutoBackupStore(
    File(
      p.join((await getApplicationSupportDirectory()).path, 'auto_backup.json'),
    ),
  );

  Future<AutoBackupConfig> load() async {
    try {
      if (!file.existsSync()) return const AutoBackupConfig();
      final json = jsonDecode(await file.readAsString());
      return AutoBackupConfig.fromJson((json as Map).cast<String, Object?>());
    } catch (_) {
      return const AutoBackupConfig();
    }
  }

  Future<void> save(AutoBackupConfig config) async {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(config.toJson()));
    await tmp.rename(file.path);
  }
}

/// The auto backup password: entered once in the settings, read by every
/// run (also in the background engine). Lives in the secure key store, never
/// in a file or a backup.
abstract class AutoBackupPassword {
  Future<String?> read();
  Future<void> write(String password);
  Future<void> delete();
}

class SecureAutoBackupPassword implements AutoBackupPassword {
  SecureAutoBackupPassword([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage(iOptions: _iosOptions);

  // The run may come while the iPhone is locked (at night): readable after
  // the first unlock, like the sync key.
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  static const _key = 'auto_backup_password';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String password) =>
      _storage.write(key: _key, value: password);
  @override
  Future<void> delete() => _storage.delete(key: _key);
}

class InMemoryAutoBackupPassword implements AutoBackupPassword {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String password) async => value = password;
  @override
  Future<void> delete() async => value = null;
}

/// The sync key locked with [password] plus the servers — the same as a
/// backup by hand puts in (SyncService.backupInfo), but read straight from
/// the key store, since the background engine has no SyncService. Null
/// without sync.
Future<BackupSyncInfo?> readSyncInfo(
  String password, {
  SyncKeyStore? keyStore,
  SyncStateStore? stateStore,
}) async {
  final identity = await (keyStore ?? SecureSyncKeyStore()).readIdentity();
  if (identity == null) return null;
  final state = await (stateStore ?? FileSyncStateStore()).load();
  final key = identity.privateKeyBytes;
  return BackupSyncInfo(
    ncryptsec: await Isolate.run(() => nip49Encrypt(key, password)),
    npub: identity.npub,
    enabled: state.enabled,
    relays: [...state.relays],
    blobServers: [...state.blobServers],
  );
}

class AutoBackup {
  AutoBackup({
    required this.store,
    required this.openService,
    required this.workDir,
    required this.password,
    Future<BackupSyncInfo?> Function(String password)? syncInfo,
    Future<void> Function(String uri, String name, String sourcePath)?
    writeToFolder,
    Future<void> Function(Duration? delay)? schedule,
    DateTime Function()? now,
  }) : _syncInfo = syncInfo ?? readSyncInfo,
       _writeToFolder = writeToFolder ?? _writeWithSaf,
       _schedule = schedule ?? _scheduleWithWorkManager,
       _now = now ?? DateTime.now;

  /// With the real platform: the app's database while the app runs (set in
  /// main), otherwise a connection of its own for the background engine.
  static Future<AutoBackup> platform() async {
    return AutoBackup(
      store: await AutoBackupStore.platform(),
      openService: () async {
        final prefs = await SharedPreferences.getInstance();
        // Another isolate may have changed them since this one cached them.
        await prefs.reload();
        return BackupService(
          db: appDatabase ?? AppDatabase(),
          docsDir: await getApplicationDocumentsDirectory(),
          prefs: prefs,
        );
      },
      workDir: () async => Directory(
        p.join((await getTemporaryDirectory()).path, 'auto-backup'),
      ),
      password: SecureAutoBackupPassword(),
    );
  }

  static const fileName = 'beand-auto-backup.zip';
  static const encryptedFileName =
      'beand-auto-backup.$encryptedBackupExtension';
  static const taskName = 'beand.autoBackup';
  static const _uniqueName = 'beand-auto-backup';

  /// iOS: the BGTaskScheduler identifier (Info.plist
  /// BGTaskSchedulerPermittedIdentifiers, AppDelegate). There the task
  /// arrives under this name, not [taskName].
  static const iosTaskId = 'app.beand.autoBackup';

  /// After a failure, try again this much later (if still due).
  static const retryDelay = Duration(hours: 1);

  /// The open app's database (set in main). Null in the background engine.
  static AppDatabase? appDatabase;

  final AutoBackupStore store;
  final Future<BackupService> Function() openService;
  final Future<Directory> Function() workDir;
  final AutoBackupPassword password;
  final Future<BackupSyncInfo?> Function(String password) _syncInfo;
  final Future<void> Function(String uri, String name, String sourcePath)
  _writeToFolder;
  final Future<void> Function(Duration? delay) _schedule;
  final DateTime Function() _now;

  // One run at a time within this isolate (app start check, "Back up now"
  // and an in-process WorkManager run could meet).
  static Future<AutoBackupConfig>? _running;

  /// Backs up if a slot was missed (or always with [force]), then queues
  /// the next run. Returns the updated config.
  Future<AutoBackupConfig> run({bool force = false}) {
    final running = _running;
    if (running != null) return running;
    final future = _run(force: force);
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<AutoBackupConfig> _run({required bool force}) async {
    var config = await store.load();
    final uri = config.folderUri;
    if (uri == null || !(force || config.isDue(_now()))) {
      await reschedule(config);
      return config;
    }

    final dir = await workDir();
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      final secret = await password.read();
      if (config.encrypt && secret == null) {
        throw const BackupException('No password set — set it again');
      }
      final service = await openService();
      final name = config.encrypt ? encryptedFileName : fileName;
      final zip = await service.createBackup(
        targetDir: dir,
        fileName: name,
        sync: secret == null ? null : await _syncInfo(secret),
        encryptPassword: config.encrypt ? secret : null,
        snapshotDb: true,
      );
      final bytes = zip.lengthSync();
      await _writeToFolder(uri, name, zip.path);
      config = config.copyWith(
        lastAt: _now(),
        lastBytes: bytes,
        clearError: true,
      );
      await store.save(config);
      await reschedule(config);
    } catch (e) {
      config = config.copyWith(lastError: _describe(e), lastErrorAt: _now());
      await store.save(config);
      if (config.enabled) {
        await _schedule(retryDelay);
      } else {
        await reschedule(config);
      }
    } finally {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {}
    }
    return config;
  }

  /// Queues the next run for [config] (or cancels it when off/no folder).
  Future<void> reschedule([AutoBackupConfig? config]) async {
    final c = config ?? await store.load();
    final next = c.folderUri == null ? null : c.nextSlot(_now());
    await _schedule(next?.difference(_now()));
  }

  static String _describe(Object e) {
    if (e is BackupException) return e.message;
    // PlatformException from the folder plugin: its message is the readable
    // part.
    final text = e.toString();
    final match = RegExp(r'PlatformException\([^,]*, ([^,]*)').firstMatch(text);
    return match?.group(1) ?? text;
  }

  static Future<void> _writeWithSaf(
    String uri,
    String name,
    String sourcePath,
  ) => SafFolder.writeFile(uri, name: name, sourcePath: sourcePath);

  static Future<void> _scheduleWithWorkManager(Duration? delay) async {
    if (Platform.isIOS) {
      if (delay == null) {
        await Workmanager().cancelByUniqueName(iosTaskId);
        return;
      }
      // Submitting the same identifier again replaces the pending request.
      await Workmanager().registerProcessingTask(
        iosTaskId,
        iosTaskId,
        initialDelay: delay,
      );
      return;
    }
    if (delay == null) {
      await Workmanager().cancelByUniqueName(_uniqueName);
      return;
    }
    await Workmanager().registerOneOffTask(
      _uniqueName,
      taskName,
      initialDelay: delay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}

/// Entry point for WorkManager (registered in main). Must be top level and
/// kept by the compiler.
@pragma('vm:entry-point')
void autoBackupDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != AutoBackup.taskName && task != AutoBackup.iosTaskId) {
      return true;
    }
    DartPluginRegistrant.ensureInitialized();
    final ownDb = AutoBackup.appDatabase == null;
    final backup = await AutoBackup.platform();
    AppDatabase? opened;
    try {
      if (ownDb) {
        opened = AppDatabase();
        AutoBackup.appDatabase = opened;
      }
      await backup.run();
    } catch (e) {
      debugPrint('Auto backup failed: $e');
    } finally {
      if (opened != null) {
        AutoBackup.appDatabase = null;
        await opened.close();
      }
    }
    // Always "done": failures are recorded and retried by the task itself.
    return true;
  });
}
