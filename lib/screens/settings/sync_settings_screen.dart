import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/database.dart';
import '../../services/backup_service.dart';
import '../../sync/crypto/nip49.dart';
import '../../sync/nostr/relay_pool.dart';
import '../../sync/sync_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import 'settings_widgets.dart';
import 'sync_key_screens.dart';
import '../../sync/secure_screen.dart';

// Settings → Sync. Like every settings page, ONE card. At the top what
// everyone needs (on/off, status, "Sync now"); below it the details for
// people with their own server. No Nostr jargon: relays are called
// "servers" here, the key "sync key".

class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({
    super.key,
    this.authenticate = confirmDeviceOwner,
    this.scan,
    this.safetyCopy,
  });

  /// Fingerprint/PIN before the QR — replaceable for tests only.
  final Future<bool> Function() authenticate;

  /// Camera instead of ScanKeyScreen — tests only.
  final Future<String?> Function(BuildContext context)? scan;

  /// Safety copy before "Replace" — replaceable for tests only.
  final Future<void> Function()? safetyCopy;

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

// Layout: at first glance nothing about Nostr — switch, status with
// "Sync now", show/scan QR. Servers, photo servers and key only under
// "Advanced settings"; the ⓘ there explains Nostr.
class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  bool _advanced = false;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.dividerInset,
                  14,
                  8,
                  14,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: SettingsTitle(
                        'Sync between your devices',
                        info:
                            'Beans, shots, profiles, photos and settings, '
                            'end-to-end encrypted. Machine addresses and AI '
                            'keys stay on each device.',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: sync.enabled,
                      onChanged: (on) => on ? sync.enable() : sync.disable(),
                    ),
                  ],
                ),
              ),
              // New device: first take over the other's key, then turn on —
              // otherwise turning on would create a key of its own.
              if (!sync.enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.dividerInset,
                    0,
                    8,
                    14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Already syncing on another device?',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      AppButton(
                        label: 'Scan QR code',
                        icon: Icons.qr_code_scanner,
                        variant: AppButtonVariant.secondary,
                        expand: false,
                        height: 40,
                        onPressed: () => scanSyncKey(
                          context,
                          sync,
                          enableAfter: true,
                          scan: widget.scan,
                          safetyCopy: widget.safetyCopy,
                        ),
                      ),
                    ],
                  ),
                ),
              if (sync.enabled) ...[
                const _StatusSection(),
                _Section(
                  title: 'Other devices',
                  info:
                      'Show the code on a device that already syncs and scan '
                      'it on the new one.',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppButton(
                        label: 'Show QR code',
                        icon: Icons.qr_code,
                        variant: AppButtonVariant.secondary,
                        expand: false,
                        height: 40,
                        onPressed: () => showSyncKeyQr(
                          context,
                          sync,
                          authenticate: widget.authenticate,
                        ),
                      ),
                      AppButton(
                        label: 'Scan QR code',
                        icon: Icons.qr_code_scanner,
                        variant: AppButtonVariant.secondary,
                        expand: false,
                        height: 40,
                        onPressed: () => scanSyncKey(
                          context,
                          sync,
                          scan: widget.scan,
                          safetyCopy: widget.safetyCopy,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  key: const ValueKey('sync-advanced'),
                  onTap: () => setState(() => _advanced = !_advanced),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.dividerInset,
                      14,
                      AppSpacing.dividerInset,
                      14,
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: SettingsTitle(
                            'Advanced settings',
                            info: nostrExplanation,
                            infoHeading: nostrHeading,
                          ),
                        ),
                        Icon(
                          _advanced ? Icons.expand_less : Icons.expand_more,
                          color: colors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_advanced) ...[
                  const _ServersSection(),
                  const _PhotoServersSection(),
                  _KeySection(authenticate: widget.authenticate),
                  // At the very bottom because it's final (delete goes at the
                  // bottom).
                  const _DeleteDataSection(),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// ⓘ on "Advanced settings": Nostr explained briefly and vividly (with a
/// heading and a QR sentence).
const nostrHeading = "bean'd uses Nostr to sync between your devices";
const nostrExplanation =
    'Nostr is a decentralized network: lots of independent servers instead '
    "of one company's cloud. bean'd rents a locker on several of them and "
    'stores your data inside.\n\n'
    'The QR code holds your sync key (nsec) — scan it on another device and '
    'sync is on.\n\n'
    'npub = the name on the locker. nsec = the only key. Lose the name and '
    'nothing happens; lose the key and someone else can open it.\n\n'
    'Add your own server for a locker at home.';

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.info});

  final String title;
  final Widget child;
  final String? info;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.dividerInset,
        14,
        AppSpacing.dividerInset,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsTitle(title, info: info),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// Small text buttons (Copy, Hex, Show) without the 48 px minimum height.
final _denseButton = TextButton.styleFrom(
  visualDensity: VisualDensity.compact,
  minimumSize: const Size(0, 32),
  padding: const EdgeInsets.symmetric(horizontal: 8),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// "3 min ago" for the status line.
String syncAgoLabel(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

class _StatusSection extends StatelessWidget {
  const _StatusSection();

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final colors = context.colors;
    final (IconData icon, Color color, String text) = switch (sync.phase) {
      SyncPhase.syncing => (
        Icons.sync,
        colors.accent,
        (sync.received ?? 0) > 0
            ? 'Syncing… ${sync.received} received'
            : 'Syncing…',
      ),
      SyncPhase.error => (
        Icons.error_outline,
        colors.danger,
        sync.error ?? 'Sync failed.',
      ),
      _ when sync.pending > 0 => (
        Icons.schedule,
        colors.textSecondary,
        sync.pending == 1
            ? '1 change waiting'
            : '${sync.pending} changes waiting',
      ),
      _ => (
        Icons.check_circle_outline,
        colors.success,
        sync.lastSuccessAt == null
            ? 'Not synced yet'
            : 'Up to date · ${syncAgoLabel(sync.lastSuccessAt!, DateTime.now())}',
      ),
    };
    return _Section(
      title: 'Status',
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
          AppButton(
            label: 'Sync now',
            expand: false,
            height: 40,
            onPressed: sync.phase == SyncPhase.syncing ? null : sync.syncNow,
          ),
        ],
      ),
    );
  }
}

class _ServersSection extends StatefulWidget {
  const _ServersSection();

  @override
  State<_ServersSection> createState() => _ServersSectionState();
}

class _ServersSectionState extends State<_ServersSection> {
  final _controller = TextEditingController();
  String? _addError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add(SyncService sync) async {
    final ok = await sync.addRelay(_controller.text);
    if (!mounted) return;
    setState(() {
      _addError = ok ? null : 'Enter a server address like wss://relay.example';
      if (ok) _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final colors = context.colors;
    final usesDefaults = defaultSyncRelays.every(sync.relays.contains);
    return _Section(
      title: 'Servers',
      info:
          'Your data is stored encrypted on these servers (Nostr relays). '
          'Public servers may delete old data at any time — that is why '
          "bean'd uses several. For more control, add your own server. A "
          'private server must allow your sync key first (see below).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sync.relays.isEmpty)
            Text(
              'No servers — nothing is synced.',
              style: TextStyle(color: colors.danger, fontSize: 13),
            ),
          for (final url in sync.relays)
            _ServerRow(
              url: url,
              status: sync.relayStatus(url),
              onRemove: () => sync.removeRelay(url),
            ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    hintText: 'wss://your-server',
                    hintStyle: TextStyle(color: colors.textTertiary),
                    errorText: _addError,
                    errorMaxLines: 2,
                  ),
                  onSubmitted: (_) => _add(sync),
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Add',
                expand: false,
                height: 40,
                onPressed: () => _add(sync),
              ),
            ],
          ),
          if (!usesDefaults)
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: sync.restoreDefaultRelays,
              child: Text(
                'Add the public default servers',
                style: TextStyle(color: colors.accent, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoServersSection extends StatefulWidget {
  const _PhotoServersSection();

  @override
  State<_PhotoServersSection> createState() => _PhotoServersSectionState();
}

class _PhotoServersSectionState extends State<_PhotoServersSection> {
  final _controller = TextEditingController();
  String? _addError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add(SyncService sync) async {
    final ok = await sync.addBlobServer(_controller.text);
    if (!mounted) return;
    setState(() {
      _addError = ok ? null : 'Enter an address like https://blossom.example';
      if (ok) _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final colors = context.colors;
    return _Section(
      title: 'Photo storage',
      info:
          'Bean photos and your own profile pictures are encrypted on this '
          'device and put on these servers (Blossom) until your other '
          'devices have fetched them. Public servers may delete files after '
          'a while — your devices keep their copies. Without a server, '
          'photos stay on each device. A private server must allow your '
          'sync key first.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sync.blobServers.isEmpty)
            Text(
              'No photo server — photos stay on this device.',
              style: TextStyle(color: colors.textTertiary, fontSize: 13),
            ),
          for (final url in sync.blobServers)
            _ServerRow(
              url: url,
              status: sync.blobServerError(url) != null
                  ? RelayStatus(
                      RelayState.error,
                      message: sync.blobServerError(url),
                    )
                  : sync.blobServerOk(url)
                  ? const RelayStatus(RelayState.connected)
                  : const RelayStatus(RelayState.idle),
              onRemove: () => sync.removeBlobServer(url),
            ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('photo-server-field'),
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    hintText: 'https://your-photo-server',
                    hintStyle: TextStyle(color: colors.textTertiary),
                    errorText: _addError,
                    errorMaxLines: 2,
                  ),
                  onSubmitted: (_) => _add(sync),
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Add',
                expand: false,
                height: 40,
                onPressed: () => _add(sync),
              ),
            ],
          ),
          if (!defaultBlobServers.every(sync.blobServers.contains))
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: sync.restoreDefaultBlobServers,
              child: Text(
                'Add the public photo servers',
                style: TextStyle(color: colors.accent, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.url,
    required this.status,
    required this.onRemove,
  });

  final String url;
  final RelayStatus status;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dot = switch (status.state) {
      RelayState.connected => colors.success,
      RelayState.error => colors.danger,
      RelayState.connecting => colors.accent,
      RelayState.idle => colors.textTertiary,
    };
    final host = Uri.tryParse(url)?.host ?? url;
    // ws:// = connection without TLS. Harmless on your own network (the data
    // itself is encrypted anyway), a warning only out there.
    final plain = url.startsWith('ws://') || url.startsWith('http://');
    final local = plain && SyncService.isLocalHost(host);
    final where = !plain
        ? null
        : !local
        ? 'unencrypted connection'
        : SyncService.isTailscaleHost(host) || !host.contains('.')
        ? 'Tailscale'
        : 'home network';
    // Tightly set: compact × button instead of the 48 px minimum height.
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        where == null ? host : '$host · $where',
                        style: TextStyle(
                          color: local || !plain
                              ? colors.textPrimary
                              : colors.danger,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (plain)
                      SettingsInfo(
                        local
                            ? 'Connected without TLS, which is fine inside '
                                  'your own network. Your data is encrypted '
                                  'on this device before it is sent — only the '
                                  'envelope (your public key, times, size) '
                                  'would be visible on the network.'
                            : 'Connected without TLS over the internet. '
                                  'Your data itself stays encrypted, but '
                                  'anyone on the way can see the envelope '
                                  '(your public key, times, size). Use '
                                  'wss:// if the server supports it.',
                      ),
                  ],
                ),
                if (status.state == RelayState.error && status.message != null)
                  Text(
                    status.message!,
                    style: TextStyle(color: colors.danger, fontSize: 12),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove server',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.close, size: 18, color: colors.textTertiary),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _KeySection extends StatelessWidget {
  const _KeySection({required this.authenticate});

  final Future<bool> Function() authenticate;

  void _copy(BuildContext context, String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what copied')));
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final colors = context.colors;
    final identity = sync.identity;
    if (identity == null) return const SizedBox.shrink();
    final npub = identity.npub;
    final short = '${npub.substring(0, 12)}…${npub.substring(npub.length - 6)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Section(
          title: 'Your npub',
          info:
              'Your public name on the servers. Your own server needs it to let '
              'you in.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.key_outlined,
                    size: 16,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      short,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  TextButton(
                    style: _denseButton,
                    onPressed: () => _copy(context, npub, 'Public key'),
                    child: Text(
                      'Copy',
                      style: TextStyle(color: colors.accent, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    style: _denseButton,
                    onPressed: () => _copy(
                      context,
                      identity.publicKeyHex,
                      'Public key (hex)',
                    ),
                    child: Text(
                      'Hex',
                      style: TextStyle(color: colors.accent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _Section(
          title: 'Your nsec',
          info:
              'The key to all your synced data. Never share it — anyone '
              'with it can read everything.',
          child: _NsecRow(nsec: identity.nsec, authenticate: authenticate),
        ),
      ],
    );
  }
}

/// Delete everything of this key from the servers, hidden under Advanced at
/// the very bottom. Afterwards sync is off and the key is gone from this
/// device; the data in the app stays.
class _DeleteDataSection extends StatefulWidget {
  const _DeleteDataSection();

  @override
  State<_DeleteDataSection> createState() => _DeleteDataSectionState();
}

class _DeleteDataSectionState extends State<_DeleteDataSection> {
  bool _busy = false;

  Future<void> _delete() async {
    final sync = context.read<SyncService>();
    // Afterwards sync is off and Advanced (including this section)
    // disappears — so show result and errors via the page's navigator.
    final navContext = Navigator.of(context).context;
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirm()) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final report = await sync.deleteServerData();
      if (!navContext.mounted) return;
      final relays = report.relaysOk.length + report.relaysFailed.length;
      final failed = [...report.relaysFailed, ...report.photoServersFailed];
      await _done(
        navContext,
        'Deleted on ${report.relaysOk.length} of $relays servers, '
        '${report.photosDeleted} photo files. Sync is off and the key is '
        'gone from this device.'
        '${failed.isEmpty ? '' : '\n\nNot reached: ${failed.join(', ')}'}',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm() async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = context.colors;
        return AlertDialog(
          backgroundColor: colors.card,
          title: Text(
            'Delete synced data?',
            style: TextStyle(color: colors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Removes everything stored under this sync key from all '
                'servers and forgets the key on this device. Your data in '
                'the app stays.\n\n'
                'Turn sync off on your other devices first — they still '
                'have this key.',
                style: TextStyle(color: colors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 14),
              Text(
                'This cannot be undone.',
                style: TextStyle(color: colors.danger, height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Delete', style: TextStyle(color: colors.danger)),
            ),
          ],
        );
      },
    );
    return answer ?? false;
  }

  Future<void> _done(BuildContext context, String message) => showDialog<void>(
    context: context,
    builder: (context) {
      final colors = context.colors;
      return AlertDialog(
        backgroundColor: colors.card,
        title: Text(
          'Synced data deleted',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          message,
          style: TextStyle(color: colors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK', style: TextStyle(color: colors.accent)),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Delete synced data',
      info:
          'Public servers may keep copies anyway — they stay encrypted and '
          'unreadable without your nsec.',
      child: AppButton(
        key: const ValueKey('sync-delete-data'),
        label: _busy ? 'Deleting…' : 'Delete synced data',
        icon: Icons.delete_outline,
        variant: AppButtonVariant.destructive,
        expand: true,
        onPressed: _busy ? null : _delete,
      ),
    );
  }
}

/// The nsec hidden; "Show" after fingerprint/face/PIN. While it is visible:
/// no screenshot, empty preview in the app switcher. On leaving the page it
/// is hidden again.
class _NsecRow extends StatefulWidget {
  const _NsecRow({required this.nsec, required this.authenticate});

  final String nsec;
  final Future<bool> Function() authenticate;

  @override
  State<_NsecRow> createState() => _NsecRowState();
}

class _NsecRowState extends State<_NsecRow> {
  bool _shown = false;

  Future<void> _toggle() async {
    if (_shown) {
      setState(() => _shown = false);
      return;
    }
    final ok = await widget.authenticate();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Not confirmed.')));
      return;
    }
    setState(() => _shown = true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = TextStyle(
      color: colors.textSecondary,
      fontSize: 13,
      fontFamily: 'monospace',
    );
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Icon(Icons.lock_outline, size: 16, color: colors.textTertiary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _shown
                ? SelectableText(widget.nsec, style: style)
                : Text('nsec1 •••••••••••••', style: style),
          ),
        ),
        TextButton(
          style: _denseButton,
          onPressed: _toggle,
          child: Text(
            _shown ? 'Hide' : 'Show',
            style: TextStyle(color: colors.accent, fontSize: 13),
          ),
        ),
      ],
    );
    return _shown ? SecureScreen(child: row) : row;
  }
}

/// "Show QR code": fingerprint/face/PIN, then the key as QR — without a
/// password; the scanning device needs nothing. The variant with a password
/// exists only under Advanced.
Future<void> showSyncKeyQr(
  BuildContext context,
  SyncService sync, {
  Future<bool> Function() authenticate = confirmDeviceOwner,
}) async {
  final identity = sync.identity;
  if (identity == null) return;
  final ok = await authenticate();
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Not confirmed.')));
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlainKeyScreen(nsec: identity.nsec),
    ),
  );
}

/// "Scan QR code": camera; protected key → password. [enableAfter]: turn
/// sync on afterwards (new device, sync was off).
Future<void> scanSyncKey(
  BuildContext context,
  SyncService sync, {
  bool enableAfter = false,
  Future<String?> Function(BuildContext context)? scan,
  Future<void> Function()? safetyCopy,
}) async {
  final scanned = scan != null
      ? await scan(context)
      : await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const ScanKeyScreen()),
        );
  if (scanned == null || !context.mounted) return;
  var password = '';
  if (!scanned.startsWith('nsec1')) {
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => const _UnlockDialog(),
    );
    if (entered == null || !context.mounted) return;
    password = entered;
  }
  await _adoptKey(
    context,
    sync,
    scanned,
    password,
    enableAfter: enableAfter,
    safetyCopy: safetyCopy,
  );
}

Future<void> _adoptKey(
  BuildContext context,
  SyncService sync,
  String key,
  String password, {
  required bool enableAfter,
  Future<void> Function()? safetyCopy,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final db = sync.db;
  try {
    final identity = await SyncService.decodeKey(key, password);
    if (!context.mounted) return;
    // If there is already something here, the user decides: merge or
    // replace (when merging, deletions on this device had also deleted the
    // other device's beans).
    var replace = false;
    if (identity.publicKeyHex != sync.identity?.publicKeyHex &&
        await db.syncDao.hasLocalData()) {
      if (!context.mounted) return;
      final choice = await showDialog<_LinkChoice>(
        context: context,
        builder: (_) => const _LinkChoiceDialog(),
      );
      if (choice == null) return;
      replace = choice == _LinkChoice.replace;
    }
    await sync.adoptIdentity(
      identity,
      replace: replace,
      beforeReplace: safetyCopy ?? () => _makeSafetyCopy(db),
    );
    // Message before turning on: enable() waits for the first sync, by then
    // the page may long be closed.
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          replace
              ? 'Replaced — loading your other devices\' data'
              : 'Linked — syncing with your devices',
        ),
      ),
    );
    if (enableAfter && !sync.enabled) await sync.enable();
  } on Nip49Exception catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          e.message == 'Wrong password'
              ? 'Wrong password.'
              : "That doesn't look like a bean'd sync key.",
        ),
      ),
    );
  } on BackupException catch (e) {
    // Without a safety copy nothing is replaced.
    messenger.showSnackBar(
      SnackBar(content: Text('Nothing replaced: ${e.message}')),
    );
  }
}

Future<void> _makeSafetyCopy(AppDatabase db) async {
  final service = BackupService(
    db: db,
    docsDir: await getApplicationDocumentsDirectory(),
    prefs: await SharedPreferences.getInstance(),
  );
  await service.createSafetyCopy(await safetyCopyDir());
}

enum _LinkChoice { merge, replace }

/// Merge or Replace when pairing — each option in one sentence.
class _LinkChoiceDialog extends StatelessWidget {
  const _LinkChoiceDialog();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget option(String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$title: ',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: text),
          ],
        ),
        style: TextStyle(color: colors.textSecondary, height: 1.4),
      ),
    );
    return AlertDialog(
      backgroundColor: colors.card,
      title: Text(
        'This device already has data',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          option(
            'Merge',
            'keep it and combine it with your other devices. Anything '
                'deleted here is deleted there too.',
          ),
          option(
            'Replace',
            'drop it and take everything from your other devices. A safety '
                'copy stays under Backup.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_LinkChoice.merge),
          child: Text('Merge', style: TextStyle(color: colors.accent)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_LinkChoice.replace),
          child: Text('Replace', style: TextStyle(color: colors.danger)),
        ),
      ],
    );
  }
}

/// Password for a scanned protected code (`ncryptsec1…`, e.g. from an older
/// app version). The app itself only shows the code without a password.
class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog();

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
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
      title: Text('Password', style: TextStyle(color: colors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This code is locked. Enter the password set on the other device.',
            style: TextStyle(color: colors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: 'Password',
              hintStyle: TextStyle(color: colors.textTertiary),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_password.text),
          child: Text('OK', style: TextStyle(color: colors.accent)),
        ),
      ],
    );
  }
}
