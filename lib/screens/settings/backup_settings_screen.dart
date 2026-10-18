import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/database.dart';
import '../../services/app_restart.dart';
import '../../services/backup_service.dart';
import '../../sync/crypto/backup_cipher.dart';
import '../../sync/crypto/nip49.dart';
import '../../sync/sync_service.dart';
import '../../theme/app_theme.dart';
import 'backup_dialogs.dart';
import 'settings_widgets.dart';

/// Settings → Backup: create a backup as a zip file (database, all photos,
/// settings) and restore from such a file.
///
/// If sync is set up, the key is included, encrypted with a password;
/// optionally the whole backup is encrypted (.beandbak). On restore,
/// decryption and the key password check happen before anything is
/// replaced.
class BackupSettingsScreen extends StatefulWidget {
  const BackupSettingsScreen({
    super.key,
    this.service,
    this.pickBackupFile,
    this.saveBackupFile,
    this.safetyDir,
  });

  /// Tests only: ready-made service or file dialogs without system UI.
  final BackupService? service;
  final Future<String?> Function()? pickBackupFile;
  final Future<Uri?> Function(String fileName, Uint8List bytes)? saveBackupFile;

  /// Folder of the safety copy (before "Replace" when pairing) — replaceable
  /// for tests only.
  final Future<Directory> Function()? safetyDir;

  @override
  State<BackupSettingsScreen> createState() => _BackupSettingsScreenState();
}

class _BackupSettingsScreenState extends State<BackupSettingsScreen> {
  bool _busy = false;
  String? _status;

  // Safety copy before "Replace" when pairing, if present.
  File? _safetyCopy;

  @override
  void initState() {
    super.initState();
    _findSafetyCopy();
  }

  Future<void> _findSafetyCopy() async {
    final dir = await (widget.safetyDir ?? safetyCopyDir)();
    final file = BackupService.safetyCopyIn(dir);
    if (mounted) setState(() => _safetyCopy = file);
  }

  Future<BackupService> _service() async {
    final provided = widget.service;
    if (provided != null) return provided;
    // Read providers before the awaits; afterwards the BuildContext is no
    // longer guaranteed to be valid.
    final db = context.read<AppDatabase>();
    return BackupService(
      db: db,
      docsDir: await getApplicationDocumentsDirectory(),
      prefs: await SharedPreferences.getInstance(),
    );
  }

  void _say(String message) {
    if (!mounted) return;
    setState(() => _status = message);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
  }

  SyncService? _sync() {
    try {
      return context.read<SyncService>();
    } on ProviderNotFoundException {
      // Without sync (tests) no key.
      return null;
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    final sync = _sync();
    final options = await showBackupOptionsDialog(
      context,
      hasSyncKey: sync?.identity != null,
    );
    if (options == null || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Packing backup…';
    });
    File? zip;
    try {
      final service = await _service();
      BackupSyncInfo? syncInfo;
      final password = options.password;
      if (sync?.identity != null && password != null) {
        setState(() => _status = 'Locking sync key…');
        syncInfo = await sync!.backupInfo(password);
        if (!mounted) return;
        setState(() => _status = 'Packing backup…');
      }
      // Pack into the cache first, then the system dialog asks for the
      // destination — a folder on the device or in a cloud that offers
      // itself as a storage location (Drive, Nextcloud, ...).
      final dir = Directory('${(await getTemporaryDirectory()).path}/backups');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      if (options.encrypt) {
        setState(() => _status = 'Packing and encrypting backup…');
      }
      zip = await service.createBackup(
        targetDir: dir,
        sync: syncInfo,
        encryptPassword: options.encrypt ? password : null,
      );
      final size = _humanSize(zip.lengthSync());
      if (!mounted) return;
      setState(() => _status = 'Choose where to save ($size)…');

      final bytes = await zip.readAsBytes();
      final name = p.basename(zip.path);
      final save = widget.saveBackupFile;
      final target = save != null
          ? await save(name, bytes)
          : await FilePicker.saveFile(
              fileName: name,
              bytes: bytes,
              mimeType: options.encrypt
                  ? 'application/octet-stream'
                  : 'application/zip',
              dialogTitle: "Save bean'd backup",
            );
      if (!mounted) return;
      _say(target == null ? 'Backup not saved' : 'Backup saved ($size)');
    } on BackupException catch (e) {
      _say(e.message);
    } catch (e) {
      _say('Backup failed: $e');
    } finally {
      // The copy in the cache is no longer needed.
      try {
        zip?.parent.deleteSync(recursive: true);
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  /// [preset]: this file instead of the file picker (safety copy).
  Future<void> _restore({File? preset}) async {
    if (_busy) return;
    final pick = widget.pickBackupFile;
    // FileType.any: otherwise Android filters out .zip depending on the file
    // manager — same behavior as the profile upload (add_profile_dialog.dart).
    final path = preset != null
        ? preset.path
        : pick != null
        ? await pick()
        : (await FilePicker.pickFile(dialogTitle: 'Pick a bean\'d backup'))
              ?.path;
    if (path == null || !mounted) return;

    setState(() {
      _busy = true;
      _status = 'Reading backup…';
    });
    Directory? decrypted;
    try {
      final service = await _service();
      var file = File(path);

      // 1. Fully encrypted: decrypt first (into the cache).
      String? password;
      if (isEncryptedBackup(file)) {
        String? error;
        while (password == null) {
          if (!mounted) return;
          setState(() => _busy = false);
          final entered = await showRestorePasswordDialog(
            context,
            title: 'Encrypted backup',
            message: 'Enter the backup password.',
            error: error,
          );
          if (entered == null || !mounted) return;
          setState(() {
            _busy = true;
            _status = 'Decrypting backup…';
          });
          decrypted ??= Directory(
            '${(await getTemporaryDirectory()).path}/restore',
          );
          try {
            file = await service.decryptBackup(
              File(path),
              entered,
              targetDir: decrypted,
            );
            password = entered;
          } on BackupException catch (e) {
            error = e.message;
          }
          if (!mounted) return;
        }
      }

      final manifest = await service.readManifest(file);
      final syncInfo = await service.readSyncInfo(file);
      if (!mounted) return;
      setState(() => _busy = false);
      final confirmed = await _confirmRestore(manifest);
      if (!confirmed || !mounted) return;

      // 2. Sync key: check the password while nothing is replaced yet.
      Uint8List? key;
      if (syncInfo != null) {
        if (password != null) {
          setState(() {
            _busy = true;
            _status = 'Unlocking sync key…';
          });
          try {
            key = await SyncService.decryptBackupKey(syncInfo, password);
          } on Nip49Exception {
            // Different password for the key: ask below.
          }
          if (!mounted) return;
        }
        String? error;
        while (key == null) {
          setState(() => _busy = false);
          final entered = await showRestorePasswordDialog(
            context,
            title: 'Sync key',
            message:
                'Enter the sync key password, or skip to restore '
                'without sync.',
            error: error,
            allowSkip: true,
          );
          if (entered == null || !mounted) return;
          if (entered.isEmpty) break;
          setState(() {
            _busy = true;
            _status = 'Unlocking sync key…';
          });
          try {
            key = await SyncService.decryptBackupKey(syncInfo, entered);
          } on Nip49Exception {
            error = 'Wrong password.';
          }
          if (!mounted) return;
        }
      }

      setState(() {
        _busy = true;
        _status = 'Restoring…';
      });
      await service.restore(file);
      // Delete the decrypted copy right away — the restart dialog below ends
      // the app, a finally would never run.
      _deleteQuietly(decrypted);
      if (!mounted) return;
      // Sync: after the restart fetch everything again and send once; with a
      // key from the backup, right away with its account and servers.
      final sync = _sync();
      if (sync != null) {
        await sync.afterRestore();
        if (key != null) await sync.adoptFromBackup(syncInfo!, key);
      }
      if (!mounted) return;
      await _restartDialog();
    } on BackupException catch (e) {
      _say(e.message);
    } catch (e) {
      _say('Restore failed: $e');
    } finally {
      _deleteQuietly(decrypted);
      if (mounted) setState(() => _busy = false);
    }
  }

  static void _deleteQuietly(Directory? dir) {
    try {
      if (dir?.existsSync() ?? false) dir!.deleteSync(recursive: true);
    } catch (_) {}
  }

  Future<bool> _confirmRestore(BackupManifest m) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.card,
        title: Text(
          'Restore this backup?',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'From ${_dateLabel(m.createdAt)}',
              style: TextStyle(color: context.colors.textSecondary),
            ),
            const SizedBox(height: 10),
            Text(
              '${m.shots} shots · ${m.beans} beans · ${m.profiles} profiles\n'
              '${m.photos} images · ${m.settings} settings',
              style: TextStyle(
                color: context.colors.textSecondary,
                height: 1.5,
              ),
            ),
            if (m.syncNpub != null)
              Text(
                'Includes your sync key',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  height: 1.5,
                ),
              ),
            const SizedBox(height: 14),
            Text(
              'Everything currently in the app is replaced and cannot be '
              'recovered afterwards.',
              style: TextStyle(color: context.colors.danger, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Restore',
              style: TextStyle(color: context.colors.danger),
            ),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  /// After restoring, all services still point to the closed old connection
  /// — the app must restart (a real process restart).
  Future<void> _restartDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.card,
        title: Text(
          'Restored',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          'The backup is in place. bean\'d restarts now to load it.',
          style: TextStyle(color: context.colors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              restartApp();
            },
            child: Text(
              'Restart',
              style: TextStyle(color: context.colors.accent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          // One block: three actions, no lines between them.
          SettingsCard(
            children: [
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: Icons.save_alt,
                    title: 'Create backup',
                    info:
                        'A backup holds everything: all shots and their curves, '
                        'beans, profiles, every photo and all settings — in one '
                        'file. With sync on, your sync key goes in too, locked '
                        'with a password. Save it to a folder on the phone or in '
                        'your cloud.',
                    enabled: !_busy,
                    onTap: _create,
                  ),
                  SettingsRow(
                    icon: Icons.restore,
                    title: 'Restore from backup',
                    info: 'Replaces everything in the app with the backup.',
                    enabled: !_busy,
                    danger: true,
                    onTap: _restore,
                  ),
                  if (_safetyCopy case final copy?)
                    SettingsRow(
                      icon: Icons.history,
                      title: 'Restore data from before linking',
                      info:
                          'Made automatically when you chose Replace while '
                          'linking a device (${_dateLabel(copy.lastModifiedSync())}).',
                      enabled: !_busy,
                      danger: true,
                      onTap: () => _restore(preset: copy),
                    ),
                ],
              ),
            ],
          ),
          if (_busy || _status != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.dividerInset,
                vertical: 14,
              ),
              child: Row(
                children: [
                  if (_busy)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.accent,
                      ),
                    ),
                  if (_busy) const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _status ?? '',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _dateLabel(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year}, ${two(t.hour)}:${two(t.minute)}';
}

String _humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
