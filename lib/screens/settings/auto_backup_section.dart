import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:saf_folder/saf_folder.dart';

import '../../services/auto_backup.dart';
import '../../sync/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/underline_select.dart';
import 'backup_dialogs.dart';
import 'settings_widgets.dart';

/// Block "Auto backup" on the backup page: schedule (off/daily/weekly), day,
/// time, target folder, password (sync key + optional encryption), status
/// of the last run and "Back up now".
class AutoBackupSection extends StatefulWidget {
  const AutoBackupSection({super.key, this.backup, this.pickFolder});

  /// Tests only: a service with fake folder/scheduler instead of the
  /// platform one.
  final Future<AutoBackup> Function()? backup;
  final Future<SafFolder?> Function()? pickFolder;

  @override
  State<AutoBackupSection> createState() => _AutoBackupSectionState();
}

class _AutoBackupSectionState extends State<AutoBackupSection> {
  AutoBackup? _backup;
  AutoBackupConfig? _config;
  bool _running = false;
  bool _hasPassword = false;

  // The saved folder is no longer writable (permission revoked, folder
  // gone) — shown instead of its name.
  bool _folderLost = false;

  static const _weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final backup = await (widget.backup ?? AutoBackup.platform)();
    final config = await backup.store.load();
    final hasPassword = await backup.password.read() != null;
    if (!mounted) return;
    setState(() {
      _backup = backup;
      _config = config;
      _hasPassword = hasPassword;
    });
    final uri = config.folderUri;
    if (uri != null && widget.pickFolder == null) {
      try {
        final name = await SafFolder.nameIfWritable(uri);
        if (mounted) setState(() => _folderLost = name == null);
      } catch (_) {}
    }
  }

  // Every schedule change re-arms (no catch-up for slots before it) and
  // queues the next run.
  Future<void> _update(AutoBackupConfig next, {bool rearm = true}) async {
    final backup = _backup;
    if (backup == null) return;
    final config = rearm ? next.copyWith(armedAt: DateTime.now()) : next;
    setState(() => _config = config);
    await backup.store.save(config);
    await backup.reschedule(config);
  }

  bool get _hasSyncKey {
    try {
      return context.read<SyncService>().identity != null;
    } on ProviderNotFoundException {
      return false;
    }
  }

  Future<void> _setFrequency(AutoBackupFrequency f) async {
    final config = _config!;
    final turningOn = !config.enabled && f != AutoBackupFrequency.off;
    await _update(config.copyWith(frequency: f));
    // With sync on, the password belongs to setting it up — otherwise the
    // sync key would quietly stay out.
    if (turningOn && _hasSyncKey && !_hasPassword && mounted) {
      await _editPassword();
    }
  }

  Future<void> _editPassword() async {
    final backup = _backup;
    final config = _config;
    if (backup == null || config == null) return;
    final options = await showAutoBackupPasswordDialog(
      context,
      hasSyncKey: _hasSyncKey,
      encrypt: config.encrypt,
      canRemove: _hasPassword,
    );
    if (options == null || !mounted) return;
    final password = options.password;
    if (options.remove) {
      await backup.password.delete();
    } else if (password != null) {
      await backup.password.write(password);
    }
    if (!mounted) return;
    setState(() => _hasPassword = !options.remove && password != null);
    await _update(config.copyWith(encrypt: options.encrypt), rearm: false);
  }

  Future<void> _pickTime() async {
    final config = _config!;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: config.minuteOfDay ~/ 60,
        minute: config.minuteOfDay % 60,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    await _update(
      config.copyWith(minuteOfDay: picked.hour * 60 + picked.minute),
    );
  }

  Future<void> _pickFolder() async {
    final config = _config!;
    final SafFolder? folder;
    try {
      folder = await (widget.pickFolder ?? SafFolder.pick)();
    } catch (e) {
      _say('Could not open the folder picker');
      return;
    }
    if (folder == null || !mounted) return;
    final old = config.folderUri;
    if (old != null && old != folder.uri && widget.pickFolder == null) {
      try {
        await SafFolder.release(old);
      } catch (_) {}
    }
    setState(() => _folderLost = false);
    await _update(
      config.copyWith(
        folderUri: folder.uri,
        folderName: folder.name ?? 'Folder',
      ),
    );
  }

  Future<void> _runNow() async {
    final backup = _backup;
    if (backup == null || _running) return;
    setState(() => _running = true);
    try {
      final config = await backup.run(force: true);
      if (!mounted) return;
      setState(() => _config = config);
      final failed =
          config.lastErrorAt != null &&
          (config.lastAt == null ||
              config.lastErrorAt!.isAfter(config.lastAt!));
      _say(failed ? 'Backup failed: ${config.lastError}' : 'Backup saved');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    if (config == null) {
      return const SettingsGroup(
        label: 'Auto backup',
        children: [SizedBox(height: 48)],
      );
    }
    final colors = context.colors;
    final hasFolder = config.folderUri != null;
    return SettingsGroup(
      label: 'Auto backup',
      children: [
        SettingsSection(
          title: 'Schedule',
          info:
              'Saves a backup on its own and overwrites the same file each '
              'time in the folder below. The app does not have to be open; '
              'the phone may run it a few minutes late. With a password, '
              'your sync key goes in too — asked for only when you '
              'restore.',
          child: UnderlineSelect<AutoBackupFrequency>(
            options: [
              for (final f in AutoBackupFrequency.values)
                UnderlineOption(f, f.label),
            ],
            value: config.frequency,
            onChanged: (f) => _setFrequency(f!),
          ),
        ),
        if (config.frequency == AutoBackupFrequency.weekly)
          SettingsSection(
            title: 'Day',
            child: UnderlineSelect<int>(
              options: [
                for (var d = DateTime.monday; d <= DateTime.sunday; d++)
                  UnderlineOption(d, _weekdays[d - 1]),
              ],
              value: config.weekday,
              onChanged: (d) => _update(config.copyWith(weekday: d)),
            ),
          ),
        if (config.enabled) ...[
          SettingsRow(
            icon: Icons.schedule,
            title: 'Time',
            subtitle: _clock(config.minuteOfDay),
            onTap: _pickTime,
          ),
          SettingsRow(
            icon: Icons.folder_outlined,
            title: 'Folder',
            subtitle: !hasFolder
                ? 'Choose where the backup goes'
                : _folderLost
                ? 'No access any more — choose again'
                : config.folderName,
            danger: _folderLost,
            onTap: _pickFolder,
          ),
          SettingsRow(
            icon: Icons.lock_outline,
            title: 'Password',
            subtitle: !_hasPassword
                ? (_hasSyncKey ? 'Not set — sync key left out' : 'Not set')
                : config.encrypt
                ? 'Set · whole backup encrypted'
                : (_hasSyncKey ? 'Set · sync key included' : 'Set'),
            onTap: _editPassword,
          ),
          SettingsRow(
            icon: Icons.save_alt,
            title: _running ? 'Backing up…' : 'Back up now',
            enabled: hasFolder && !_running,
            onTap: _runNow,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.dividerInset,
              0,
              AppSpacing.dividerInset,
              14,
            ),
            child: SettingsText(
              _statusLine(config),
              color: _failedLast(config) ? colors.danger : null,
            ),
          ),
        ],
      ],
    );
  }

  static bool _failedLast(AutoBackupConfig c) =>
      c.lastErrorAt != null &&
      (c.lastAt == null || c.lastErrorAt!.isAfter(c.lastAt!));

  String _statusLine(AutoBackupConfig c) {
    final lines = <String>[];
    if (_failedLast(c)) {
      lines.add('Last try failed (${_date(c.lastErrorAt!)}): ${c.lastError}');
    }
    final last = c.lastAt;
    lines.add(
      last == null
          ? 'No auto backup yet'
          : 'Last backup ${_date(last)} · ${_size(c.lastBytes ?? 0)}',
    );
    final next = c.folderUri == null ? null : c.nextSlot(DateTime.now());
    if (next != null) lines.add('Next ${_date(next)}');
    return lines.join('\n');
  }
}

String _clock(int minuteOfDay) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(minuteOfDay ~/ 60)}:${two(minuteOfDay % 60)}';
}

String _date(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year}, '
      '${two(t.hour)}:${two(t.minute)}';
}

String _size(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
