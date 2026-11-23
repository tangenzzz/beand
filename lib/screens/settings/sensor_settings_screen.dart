import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../scale/bluetooth_prompt.dart';
import '../../scale/brew_scale.dart';
import '../../sensors/pressure_sensor.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import 'scale_settings_screen.dart' show FoundDeviceRow, KnownDeviceRow;
import 'settings_widgets.dart';

// Settings → Connections → Sensors: pressure (and later flow) devices for
// Home → Espresso, built like the Scales page — at the top the sensor in use
// with its live reading and zero, below the known sensors (also while off)
// and the new ones a scan finds. Which one Espresso uses is chosen under
// Settings → Home → Espresso. One card per settings page.
class SensorSettingsScreen extends StatelessWidget {
  const SensorSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sensors')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: const [_SensorCard()],
      ),
    );
  }
}

class _SensorCard extends StatefulWidget {
  const _SensorCard();

  @override
  State<_SensorCard> createState() => _SensorCardState();
}

class _SensorCardState extends State<_SensorCard> {
  final _found = <ScaleCandidate>[];
  StreamSubscription<ScaleCandidate>? _scanSub;
  bool _scanning = false;
  bool _searchedOnce = false;
  String? _scanError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final scale = context.read<BrewScale?>();
      if (scale != null && await scale.bluetoothOff) return;
      if (mounted) _scan();
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  Future<void> _onScanTap() async {
    final scale = context.read<BrewScale?>();
    if (scale != null && !await ensureBluetoothOn(context, scale)) return;
    if (mounted) _scan();
  }

  void _scan() {
    _scanSub?.cancel();
    setState(() {
      _scanning = true;
      _scanError = null;
      _found.clear();
    });
    _scanSub = context.read<PressureSensor>().scan().listen(
      (c) {
        if (!mounted) return;
        setState(() {
          _found
            ..removeWhere((f) => f.id == c.id)
            ..add(c)
            ..sort((a, b) => b.rssi.compareTo(a.rssi));
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _searchedOnce = true;
          _scanError = e.toString().replaceFirst('Exception: ', '');
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _searchedOnce = true;
        });
      },
    );
  }

  Future<void> _use(ScaleCandidate c) async {
    final sensor = context.read<PressureSensor>();
    final scale = context.read<BrewScale?>();
    unawaited(_scanSub?.cancel());
    setState(() => _scanning = false);
    if (scale != null && !await ensureBluetoothOn(context, scale)) return;
    await sensor.connectTo(c);
  }

  Future<void> _actions(KnownScale known) async {
    final colors = context.colors;
    final sensor = context.read<PressureSensor>();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.tile),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                known.displayName.toUpperCase(),
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: colors.textSecondary),
              title: Text(
                'Rename',
                style: TextStyle(color: colors.textPrimary),
              ),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: colors.danger),
              title: Text('Forget', style: TextStyle(color: colors.danger)),
              onTap: () => Navigator.pop(context, 'forget'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == 'forget') await sensor.forgetSensor(known.id);
    if (action == 'rename' && mounted) {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _RenameSensorDialog(known: known),
      );
      if (name != null) await sensor.renameSensor(known.id, name);
    }
  }

  (Color, String) _status(PressureSensor sensor) {
    final colors = context.colors;
    final battery = sensor.batteryPercent;
    return switch (sensor.connection) {
      ScaleConnection.connected => (
        colors.success,
        battery == null ? 'Connected' : 'Connected · Battery $battery %',
      ),
      ScaleConnection.connecting => (colors.sensorMid, 'Connecting…'),
      ScaleConnection.scanning => (colors.sensorMid, 'Searching…'),
      ScaleConnection.disconnected =>
        sensor.error != null
            ? (colors.danger, 'Connection failed')
            : (colors.textTertiary, 'Not connected'),
    };
  }

  (Color, String) _knownStatus(PressureSensor sensor, KnownScale k) {
    final colors = context.colors;
    if (k.id == sensor.rememberedId &&
        sensor.connection != ScaleConnection.disconnected) {
      return _status(sensor);
    }
    final nearby = _found.any((c) => c.id == k.id);
    final inUse = k.id == sensor.rememberedId;
    return nearby
        ? (colors.accent, inUse ? 'Nearby · In use' : 'Nearby')
        : (colors.textTertiary, inUse ? 'Offline · In use' : 'Offline');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sensor = context.watch<PressureSensor>();
    final (dotColor, stateLabel) = _status(sensor);
    final known = sensor.knownSensors;
    final others = [
      for (final c in _found)
        if (!known.any((k) => k.id == c.id)) c,
    ];
    final busy =
        sensor.connection == ScaleConnection.scanning ||
        sensor.connection == ScaleConnection.connecting;

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header: the sensor in use ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(34 * 0.3),
                ),
                child: Icon(Icons.speed, size: 20, color: colors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sensor.rememberedId == null
                          ? 'No sensor in use'
                          : sensor.displayName ?? 'Pressure sensor',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.textPrimary, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: dotColor),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            stateLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (sensor.error != null && !sensor.isConnected) ...[
                      const SizedBox(height: 4),
                      Text(
                        sensor.error!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // ---- Live pressure ----
          if (sensor.isConnected) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: sensor.bar == null
                              ? '—'
                              : sensor.bar!.toStringAsFixed(1),
                          style: TextStyle(
                            color: sensor.bar == null
                                ? colors.textTertiary
                                : colors.textPrimary,
                            fontSize: 34,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        TextSpan(
                          text: ' bar',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AppButton(
                  label: 'Set zero',
                  expand: false,
                  height: 40,
                  onPressed: sensor.zero,
                ),
              ],
            ),
          ],
          if (sensor.isConnected || busy) ...[
            const SizedBox(height: 12),
            AppButton(
              label: 'Disconnect',
              variant: AppButtonVariant.secondary,
              expand: false,
              height: 36,
              onPressed: sensor.disconnect,
            ),
          ],
          Divider(height: 24, color: colors.divider),
          // ---- The sensors ----
          Row(
            children: [
              Expanded(
                child: Text(
                  (known.isEmpty ? 'Sensors nearby' : 'My sensors')
                      .toUpperCase(),
                  style: settingsGroupLabelStyle(context),
                ),
              ),
              InkWell(
                key: const ValueKey('sensor-scan'),
                onTap: _onScanTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    children: [
                      if (_scanning)
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: colors.accent,
                          ),
                        )
                      else
                        Icon(Icons.refresh, size: 14, color: colors.accent),
                      const SizedBox(width: 4),
                      Text(
                        'Scan',
                        style: TextStyle(color: colors.accent, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final k in known)
            KnownDeviceRow(
              keyPrefix: 'known-sensor',
              known: k,
              status: _knownStatus(sensor, k),
              connected: k.id == sensor.rememberedId && sensor.isConnected,
              onTap: () => _use(
                _found.where((c) => c.id == k.id).firstOrNull ??
                    ScaleCandidate(id: k.id, name: k.name, rssi: 0),
              ),
              onMore: () => _actions(k),
            ),
          if (known.isNotEmpty && others.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'New sensors'.toUpperCase(),
              style: settingsGroupLabelStyle(context),
            ),
            const SizedBox(height: 8),
          ],
          for (final c in others)
            FoundDeviceRow(
              candidate: c,
              inUse: c.id == sensor.rememberedId,
              connected: c.id == sensor.rememberedId && sensor.isConnected,
              onTap: () => _use(c),
            ),
          if (others.isEmpty) _hint(known.isNotEmpty),
          const SizedBox(height: 4),
          Text(
            'Supported: Pressensor. Close other apps that use the sensor '
            'first.',
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _hint(bool hasKnown) {
    final text = _scanError != null
        ? _scanError!
        : _scanning
        ? (hasKnown ? '' : 'Searching…')
        : _searchedOnce && !hasKnown
        ? 'No sensor found. Switch it on and tap Scan.'
        : '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(color: context.colors.textTertiary, fontSize: 12),
      ),
    );
  }
}

class _RenameSensorDialog extends StatefulWidget {
  const _RenameSensorDialog({required this.known});

  final KnownScale known;

  @override
  State<_RenameSensorDialog> createState() => _RenameSensorDialogState();
}

class _RenameSensorDialogState extends State<_RenameSensorDialog> {
  late final _name = TextEditingController(text: widget.known.displayName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.card,
      title: Text('Rename sensor', style: TextStyle(color: colors.textPrimary)),
      content: TextField(
        key: const ValueKey('sensor-name'),
        controller: _name,
        autofocus: true,
        maxLength: 30,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(color: colors.textPrimary),
        // Empty goes back to the sensor's own name.
        decoration: InputDecoration(hintText: widget.known.name),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _name.text),
          child: Text('Save', style: TextStyle(color: colors.accent)),
        ),
      ],
    );
  }
}
