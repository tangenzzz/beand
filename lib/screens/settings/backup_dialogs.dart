import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_switch_tile.dart';

// Dialogs for Settings → Backup with sync key and encryption (encrypting
// the whole backup can be chosen when creating it).

/// What was chosen when creating. [password] is null if neither a key is
/// included nor anything is encrypted.
class BackupOptions {
  const BackupOptions({
    required this.password,
    required this.encrypt,
    this.remove = false,
  });
  final String? password;
  final bool encrypt;

  /// Auto backup only: the stored password is to be removed.
  final bool remove;
}

Future<BackupOptions?> showBackupOptionsDialog(
  BuildContext context, {
  required bool hasSyncKey,
}) => showDialog<BackupOptions>(
  context: context,
  builder: (_) => _OptionsDialog(hasSyncKey: hasSyncKey),
);

/// The same choice for the auto backup: the password is set once here and
/// kept on the phone, so every run can use it. A password is always asked
/// for (that is what the dialog is for); [canRemove] offers dropping the
/// stored one.
Future<BackupOptions?> showAutoBackupPasswordDialog(
  BuildContext context, {
  required bool hasSyncKey,
  required bool encrypt,
  required bool canRemove,
}) => showDialog<BackupOptions>(
  context: context,
  builder: (_) => _OptionsDialog(
    hasSyncKey: hasSyncKey,
    auto: true,
    initialEncrypt: encrypt,
    canRemove: canRemove,
  ),
);

class _OptionsDialog extends StatefulWidget {
  const _OptionsDialog({
    required this.hasSyncKey,
    this.auto = false,
    this.initialEncrypt = false,
    this.canRemove = false,
  });
  final bool hasSyncKey;
  final bool auto;
  final bool initialEncrypt;
  final bool canRemove;

  @override
  State<_OptionsDialog> createState() => _OptionsDialogState();
}

class _OptionsDialogState extends State<_OptionsDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  late bool _encrypt = widget.initialEncrypt;
  String? _error;

  bool get _needsPassword => widget.auto || widget.hasSyncKey || _encrypt;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    if (_needsPassword) {
      if (_first.text.length < 8) {
        setState(() => _error = 'At least 8 characters.');
        return;
      }
      if (_first.text != _second.text) {
        setState(() => _error = "The passwords don't match.");
        return;
      }
    }
    Navigator.of(context).pop(
      BackupOptions(
        password: _needsPassword ? _first.text : null,
        encrypt: _encrypt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Short and only what's needed, plus the advice to also keep the
    // password somewhere outside this device.
    final note = widget.auto
        ? 'Kept on this phone for every auto backup; only a restore asks '
              'for it. Keep it safe elsewhere too.'
        : _encrypt
        ? 'Keep the password safe, not only on this phone. Without it the '
              'backup is lost.'
        : widget.hasSyncKey
        ? 'Keep the password safe, not only on this phone. Without it only '
              'sync needs a new key.'
        : null;
    return AlertDialog(
      backgroundColor: colors.card,
      title: Text(
        widget.auto ? 'Auto backup password' : 'Create backup',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.hasSyncKey)
              Text(
                'Includes your sync key, locked with the password.',
                style: TextStyle(color: colors.textSecondary, height: 1.4),
              ),
            AppSwitchTile(
              key: const ValueKey('encrypt-backup'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Encrypt whole backup',
                style: TextStyle(color: colors.textPrimary, fontSize: 15),
              ),
              subtitle: Text(
                'Unreadable without the password.',
                style: TextStyle(color: colors.textTertiary, fontSize: 12),
              ),
              value: _encrypt,
              onChanged: (v) => setState(() {
                _encrypt = v;
                _error = null;
              }),
            ),
            if (_needsPassword) ...[
              const SizedBox(height: 4),
              backupPasswordField(_first, 'Password', colors),
              const SizedBox(height: 8),
              backupPasswordField(_second, 'Repeat password', colors),
            ],
            if (note != null) ...[
              const SizedBox(height: 10),
              Text(
                note,
                style: TextStyle(
                  color: _encrypt ? colors.danger : colors.textTertiary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: colors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.canRemove)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              const BackupOptions(password: null, encrypt: false, remove: true),
            ),
            child: Text('Remove', style: TextStyle(color: colors.danger)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            widget.auto ? 'Save' : 'Create',
            style: TextStyle(color: colors.accent),
          ),
        ),
      ],
    );
  }
}

/// Password on restore. Result: the password, '' for "Skip" (only with
/// [allowSkip]) or null for cancel.
Future<String?> showRestorePasswordDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? error,
  bool allowSkip = false,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _RestorePasswordDialog(
    title: title,
    message: message,
    error: error,
    allowSkip: allowSkip,
  ),
);

class _RestorePasswordDialog extends StatefulWidget {
  const _RestorePasswordDialog({
    required this.title,
    required this.message,
    required this.error,
    required this.allowSkip,
  });

  final String title;
  final String message;
  final String? error;
  final bool allowSkip;

  @override
  State<_RestorePasswordDialog> createState() => _RestorePasswordDialogState();
}

class _RestorePasswordDialogState extends State<_RestorePasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.card,
      title: Text(widget.title, style: TextStyle(color: colors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message,
            style: TextStyle(color: colors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          backupPasswordField(_password, 'Password', colors),
          if (widget.error != null) ...[
            const SizedBox(height: 8),
            Text(widget.error!, style: TextStyle(color: colors.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        if (widget.allowSkip)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text('Skip', style: TextStyle(color: colors.textSecondary)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_password.text),
          child: Text('OK', style: TextStyle(color: colors.accent)),
        ),
      ],
    );
  }
}

Widget backupPasswordField(
  TextEditingController controller,
  String hint,
  AppColors colors,
) => TextField(
  controller: controller,
  obscureText: true,
  autocorrect: false,
  enableSuggestions: false,
  style: TextStyle(color: colors.textPrimary),
  decoration: InputDecoration(
    isDense: true,
    border: const OutlineInputBorder(),
    hintText: hint,
    hintStyle: TextStyle(color: colors.textTertiary),
  ),
);
