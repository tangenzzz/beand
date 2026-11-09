import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/connection_log.dart';
import '../../theme/app_theme.dart';
import 'settings_widgets.dart';

/// Settings → About → Diagnostics log: connections, commands, sync and
/// errors, newest first; share it as a file, or clear it.
class ConnectionLogScreen extends StatefulWidget {
  const ConnectionLogScreen({super.key, this.load});

  /// Tests only: lines instead of the file.
  final Future<List<String>> Function()? load;

  @override
  State<ConnectionLogScreen> createState() => _ConnectionLogScreenState();
}

class _ConnectionLogScreenState extends State<ConnectionLogScreen> {
  List<String>? _lines;

  // Folded by default (user request 2026-10-22): the lines only on demand.
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final lines = await (widget.load ?? ConnectionLog.read)();
    if (mounted) setState(() => _lines = lines.reversed.toList());
  }

  Future<void> _share() async {
    // A copy with the app and device on top; every line is filtered again.
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'beand-diagnostics.txt'));
    await file.writeAsString(
      await ConnectionLog.shareText(await _header()),
      flush: true,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: "bean'd diagnostics log",
      ),
    );
  }

  Future<String> _header() async {
    final info = await PackageInfo.fromPlatform();
    return "bean'd ${info.version} (${info.buildNumber})\n${await _device()}";
  }

  Future<String> _device() async {
    try {
      final device = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await device.androidInfo;
        return 'Android ${a.version.release}, ${a.manufacturer} ${a.model}';
      }
      if (Platform.isIOS) {
        final i = await device.iosInfo;
        return 'iOS ${i.systemVersion}, ${i.utsname.machine}';
      }
    } catch (_) {}
    return Platform.operatingSystem;
  }

  Future<void> _clear() async {
    await ConnectionLog.clear();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics log')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              SettingsGroup(
                label: 'Log',
                info:
                    'Connections, commands, sync and errors, with time and '
                    'reason. It stays on this phone until you share it. '
                    'Addresses, keys and serial numbers are left out.',
                children: [
                  if (lines == null)
                    const SizedBox(height: 48)
                  else if (lines.isEmpty)
                    const SettingsSection(
                      child: SettingsText('Nothing logged yet.'),
                    )
                  else ...[
                    InkWell(
                      key: const ValueKey('log-toggle'),
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.dividerInset,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _expanded
                                    ? 'Hide entries'
                                    : 'Show ${lines.length} entries',
                                style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Icon(
                              _expanded ? Icons.expand_less : Icons.expand_more,
                              color: context.colors.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_expanded)
                      for (final line in lines.take(400)) _LogLine(line),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: Icons.ios_share,
                    title: 'Share log',
                    enabled: lines?.isNotEmpty ?? false,
                    onTap: _share,
                  ),
                  SettingsRow(
                    icon: Icons.delete_outline,
                    title: 'Clear log',
                    danger: true,
                    enabled: lines?.isNotEmpty ?? false,
                    onTap: _clear,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// "2026-10-21T20:31:05.123 reconnect no status for 3400 ms" → time, kind,
// detail; trouble in the warning colour.
class _LogLine extends StatelessWidget {
  const _LogLine(this.line);

  final String line;

  static const _trouble = {
    'reconnect',
    'disconnected',
    'error',
    'stall',
    'crash',
    'failed',
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final parts = line.split(' ');
    final at = DateTime.tryParse(parts.first);
    final kind = parts.length > 1 ? parts[1] : '';
    final detail = parts.length > 2 ? parts.skip(2).join(' ') : '';
    final bad = _trouble.contains(kind) || detail.contains('failed');
    String two(int v) => v.toString().padLeft(2, '0');
    final time = at == null
        ? ''
        : '${two(at.day)}.${two(at.month)}. '
              '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.dividerInset,
        vertical: 3,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$time  ',
              style: TextStyle(color: colors.textTertiary),
            ),
            TextSpan(
              text: '$kind  ',
              style: TextStyle(
                color: bad ? colors.danger : colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: detail,
              style: TextStyle(color: colors.textPrimary),
            ),
          ],
        ),
        style: TextStyle(
          fontSize: 12,
          height: 1.35,
          fontFamily: Platform.isAndroid ? 'monospace' : null,
        ),
      ),
    );
  }
}
