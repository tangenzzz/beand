import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/connection_log.dart';
import '../../theme/app_theme.dart';
import 'settings_widgets.dart';

/// Settings → Connections → Connection log: what happened to the connection
/// to the Meticulous, newest first; share it as a file, or clear it.
class ConnectionLogScreen extends StatefulWidget {
  const ConnectionLogScreen({super.key, this.load});

  /// Tests only: lines instead of the file.
  final Future<List<String>> Function()? load;

  @override
  State<ConnectionLogScreen> createState() => _ConnectionLogScreenState();
}

class _ConnectionLogScreenState extends State<ConnectionLogScreen> {
  List<String>? _lines;

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
    final file = await ConnectionLog.file();
    if (!await file.exists()) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: "bean'd connection log",
      ),
    );
  }

  Future<void> _clear() async {
    await ConnectionLog.clear();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    return Scaffold(
      appBar: AppBar(title: const Text('Connection log')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              SettingsGroup(
                label: 'Meticulous',
                info:
                    'Every drop of the connection, every reconnect and every '
                    'command, with time and reason. Share it to find out '
                    'whether the Wi-Fi or the app is to blame.',
                children: [
                  if (lines == null)
                    const SizedBox(height: 48)
                  else if (lines.isEmpty)
                    const SettingsSection(
                      child: SettingsText('Nothing logged yet.'),
                    )
                  else
                    for (final line in lines.take(400)) _LogLine(line),
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

  static const _trouble = {'reconnect', 'disconnected', 'error', 'stall'};

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
