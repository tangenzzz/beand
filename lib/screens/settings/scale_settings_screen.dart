import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../scale/bluetooth_prompt.dart';
import '../../scale/brew_scale.dart';
import '../../scale/meticulous_scale.dart';
import '../../scale/scale_selector.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/meticulous_mark.dart';
import '../../widgets/underline_select.dart';
import 'settings_widgets.dart';

// Connection page of the Bluetooth scales (Settings → Connections), built
// like the machines' one (MachineConnectionCard): at the top what the app
// is connected to, with the live weight and tare, so the scale can be checked
// without starting a brew. Below it the known scales, also while they are off,
// like the phone's Bluetooth settings, and the new ones a scan finds.
//
// One card per settings page.
class ScaleSettingsScreen extends StatelessWidget {
  const ScaleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scales')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: const [ScaleConnectionCard()],
      ),
    );
  }
}

class ScaleConnectionCard extends StatefulWidget {
  const ScaleConnectionCard({super.key});

  @override
  State<ScaleConnectionCard> createState() => _ScaleConnectionCardState();
}

class _ScaleConnectionCardState extends State<ScaleConnectionCard> {
  final _found = <ScaleCandidate>[];
  StreamSubscription<ScaleCandidate>? _scanSub;
  bool _scanning = false;
  bool _searchedOnce = false;
  String? _scanError;

  StreamSubscription<bool>? _bluetoothSub;
  bool _bluetoothOff = false;

  @override
  void initState() {
    super.initState();
    // Look for scales whatever the scale is doing, so another one can always
    // be tapped to switch over.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<BrewScale>().isMachineScale) _watchBluetooth();
    });
  }

  // Follows the phone's Bluetooth: scans once when it's on (also right when
  // it comes on). Listening asks iOS for its permission, so only on this
  // page with a Bluetooth scale chosen.
  void _watchBluetooth() {
    if (_bluetoothSub != null) return;
    var first = true;
    final scale = context.read<BrewScale>();
    _bluetoothSub = scale.bluetoothOffChanges.listen((off) {
      if (!mounted) return;
      final cameOn = !off && (_bluetoothOff || first);
      first = false;
      setState(() => _bluetoothOff = off);
      if (cameOn) _scan();
    });
    // The stream may say nothing until something changes.
    scale.bluetoothOff.then((off) {
      if (!mounted || !first) return;
      first = false;
      setState(() => _bluetoothOff = off);
      if (!off) _scan();
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _bluetoothSub?.cancel();
    super.dispose();
  }

  Future<void> _onScanTap() async {
    final scale = context.read<BrewScale>();
    if (await scale.bluetoothOff) {
      if (mounted) await ensureBluetoothOn(context, scale);
      return;
    }
    if (mounted) _scan();
  }

  void _scan() {
    _scanSub?.cancel();
    setState(() {
      _scanning = true;
      _scanError = null;
      _found.clear();
    });
    _scanSub = context.read<BrewScale>().scan().listen(
      (c) {
        if (!mounted) return;
        setState(() {
          _found
            ..remove(c)
            ..add(c)
            ..sort((a, b) => b.rssi.compareTo(a.rssi));
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _scanning = false;
          _searchedOnce = true;
          _scanError = e.toString().replaceFirst('_ScaleException: ', '');
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
    final scale = context.read<BrewScale>();
    // Not awaited: a scan just starting only finishes cancelling once its
    // Bluetooth checks are through, and the tap shouldn't wait for that.
    unawaited(_scanSub?.cancel());
    setState(() => _scanning = false);
    if (!await ensureBluetoothOn(context, scale)) return;
    await scale.connectTo(c);
  }

  // Chose Bluetooth as the input: if it's off, ask right away.
  Future<void> _bluetoothChosen(BrewScale scale) async {
    _watchBluetooth();
    if (await ensureBluetoothOn(context, scale) && mounted) _scan();
  }

  Future<void> _scaleActions(KnownScale known) async {
    final colors = context.colors;
    final scale = context.read<BrewScale>();
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
                known.displayName,
                style: TextStyle(color: colors.textPrimary, fontSize: 15),
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
    if (action == 'forget') await scale.forgetScale(known.id);
    if (action == 'rename' && mounted) await _renameScale(scale, known);
  }

  Future<void> _renameScale(BrewScale scale, KnownScale known) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameScaleDialog(known: known),
    );
    if (name != null) await scale.renameScale(known.id, name);
  }

  (Color, String) _status(BuildContext context, BrewScale scale) =>
      switch (scale.connection) {
        ScaleConnection.connected => (context.colors.success, 'Connected'),
        ScaleConnection.scanning => (context.colors.sensorMid, 'Searching…'),
        ScaleConnection.connecting => (context.colors.sensorMid, 'Connecting…'),
        ScaleConnection.disconnected =>
          scale.error != null
              ? (context.colors.danger, 'Connection failed')
              : (context.colors.textTertiary, 'Not connected'),
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scale = context.watch<BrewScale>();
    final (dotColor, stateLabel) = _status(context, scale);
    // Only the battery level instead of firmware and packet counters (they
    // only confused).
    final battery = scale.batteryPercent;
    final details = battery == null ? null : 'Battery $battery %';
    final busy =
        scale.connection == ScaleConnection.scanning ||
        scale.connection == ScaleConnection.connecting;
    final known = scale.knownScales;
    final others = [
      for (final c in _found)
        if (!known.any((k) => k.id == c.id)) c,
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Which scale Pour Over uses ----
          if (scale is ScaleSelector) ...[
            UnderlineSelect<ScaleSource>(
              options: const [
                UnderlineOption(ScaleSource.bluetooth, 'Bluetooth'),
                UnderlineOption(ScaleSource.meticulous, MeticulousScale.name),
              ],
              value: scale.source,
              onChanged: (v) {
                if (v == null) return;
                scale.setSource(v);
                if (v == ScaleSource.bluetooth) _bluetoothChosen(scale);
              },
            ),
            const SizedBox(height: 16),
          ],
          // ---- Header: what the app is connected to ----
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
                child: scale.isMachineScale
                    ? MeticulousMark(size: 20, color: colors.accent)
                    : Icon(
                        Icons.scale_outlined,
                        size: 20,
                        color: colors.accent,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scale.displayName ?? 'Bluetooth Scale',
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
                            details == null
                                ? stateLabel
                                : '$stateLabel · $details',
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
                    if (scale.error != null && !scale.isConnected) ...[
                      const SizedBox(height: 4),
                      Text(
                        scale.error!,
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
          // ---- Live weight ----
          if (scale.isConnected) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: scale.grams == null
                              ? '—'
                              : scale.grams!.toStringAsFixed(1),
                          style: TextStyle(
                            color: scale.grams == null
                                ? colors.textTertiary
                                : colors.textPrimary,
                            fontSize: 34,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        TextSpan(
                          text: ' g',
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
                  label: 'Tare',
                  expand: false,
                  height: 40,
                  onPressed: () => scale.tare().catchError((Object _) {}),
                ),
              ],
            ),
            if (scale.grams == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Connected, but no weight yet.',
                  style: TextStyle(color: colors.textTertiary, fontSize: 12),
                ),
              ),
          ],
          if (scale.isMachineScale) ...[
            const SizedBox(height: 12),
            Text(
              'Weighs with the scale built into the Meticulous. Pour Over '
              'then uses the filter profiles stored on the machine.',
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
          ] else ...[
            if (scale.isConnected || busy) ...[
              const SizedBox(height: 12),
              AppButton(
                label: 'Disconnect',
                variant: AppButtonVariant.secondary,
                expand: false,
                height: 36,
                onPressed: scale.disconnect,
              ),
            ],
            Divider(height: 24, color: colors.divider),
            if (_bluetoothOff) _bluetoothBanner(context, scale),
            // ---- The scales ----
            Row(
              children: [
                Expanded(
                  child: Text(
                    (known.isEmpty ? 'Scales nearby' : 'My scales')
                        .toUpperCase(),
                    style: settingsGroupLabelStyle(context),
                  ),
                ),
                // Works at any time: while one runs it searches on.
                InkWell(
                  key: const ValueKey('scale-scan'),
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
              _KnownScaleRow(
                known: k,
                status: _knownStatus(context, scale, k),
                connected: k.id == scale.rememberedId && scale.isConnected,
                onTap: () => _use(
                  _found.where((c) => c.id == k.id).firstOrNull ??
                      ScaleCandidate(id: k.id, name: k.name, rssi: 0),
                ),
                onMore: () => _scaleActions(k),
              ),
            if (known.isNotEmpty && others.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'New scales'.toUpperCase(),
                style: settingsGroupLabelStyle(context),
              ),
              const SizedBox(height: 8),
            ],
            for (final c in others)
              _ScaleRow(
                candidate: c,
                inUse: c.id == scale.rememberedId,
                connected: c.id == scale.rememberedId && scale.isConnected,
                onTap: () => _use(c),
              ),
            if (others.isEmpty) _hint(context, known.isNotEmpty),
            const SizedBox(height: 4),
            Text(
              'Supported: Acaia, Decent and Bookoo scales. Close other apps '
              'that use the scale first.',
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  (Color, String) _knownStatus(
    BuildContext context,
    BrewScale scale,
    KnownScale k,
  ) {
    final colors = context.colors;
    if (k.id == scale.rememberedId) {
      final battery = scale.batteryPercent;
      switch (scale.connection) {
        case ScaleConnection.connected:
          return (
            colors.success,
            battery == null ? 'Connected' : 'Connected · Battery $battery %',
          );
        case ScaleConnection.connecting:
          return (colors.sensorMid, 'Connecting…');
        case ScaleConnection.scanning:
          return (colors.sensorMid, 'Searching…');
        case ScaleConnection.disconnected:
          break;
      }
    }
    return _found.any((c) => c.id == k.id)
        ? (colors.accent, 'Nearby')
        : (colors.textTertiary, 'Offline');
  }

  Widget _bluetoothBanner(BuildContext context, BrewScale scale) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(Icons.bluetooth_disabled, size: 18, color: colors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              Theme.of(context).platform == TargetPlatform.iOS
                  ? 'Bluetooth is off. Turn it on in Control Center.'
                  : 'Bluetooth is off.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
          if (Theme.of(context).platform != TargetPlatform.iOS)
            AppButton(
              label: 'Turn on',
              expand: false,
              height: 36,
              onPressed: () => ensureBluetoothOn(context, scale),
            ),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context, bool hasKnown) {
    final colors = context.colors;
    final text = _bluetoothOff
        ? ''
        : _scanError != null
        ? _scanError!
        : _scanning
        ? (hasKnown ? '' : 'Searching…')
        : _searchedOnce && !hasKnown
        ? 'No scale found. Switch it on (and wake it up) and tap Scan.'
        : '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(color: colors.textTertiary, fontSize: 12),
      ),
    );
  }
}

class _RenameScaleDialog extends StatefulWidget {
  const _RenameScaleDialog({required this.known});

  final KnownScale known;

  @override
  State<_RenameScaleDialog> createState() => _RenameScaleDialogState();
}

class _RenameScaleDialogState extends State<_RenameScaleDialog> {
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
      title: Text('Rename scale', style: TextStyle(color: colors.textPrimary)),
      content: TextField(
        key: const ValueKey('scale-name'),
        controller: _name,
        autofocus: true,
        maxLength: 30,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(color: colors.textPrimary),
        // Empty goes back to the scale's own name.
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

// A scale the app knows: there also while it's off, with its state instead of
// the signal. Tapping connects, like in the phone's Bluetooth settings.
class _KnownScaleRow extends StatelessWidget {
  const _KnownScaleRow({
    required this.known,
    required this.status,
    required this.connected,
    required this.onTap,
    required this.onMore,
  });

  final KnownScale known;
  final (Color, String) status;
  final bool connected;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (dot, label) = status;
    return InkWell(
      key: ValueKey('known-scale-${known.id}'),
      onTap: connected ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(Icons.bluetooth, size: 18, color: colors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    known.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textPrimary, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.circle, size: 7, color: dot),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'More',
              icon: Icon(Icons.more_vert, size: 18, color: colors.textTertiary),
              onPressed: onMore,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScaleRow extends StatelessWidget {
  const _ScaleRow({
    required this.candidate,
    required this.inUse,
    required this.connected,
    required this.onTap,
  });

  final ScaleCandidate candidate;
  final bool inUse;
  final bool connected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.bluetooth, size: 18, color: colors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textPrimary, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Signal ${candidate.rssi} dBm',
                    style: TextStyle(color: colors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (connected)
              Icon(Icons.check, size: 18, color: colors.success)
            else
              Text(
                inUse ? 'Connect' : 'Use',
                style: TextStyle(
                  color: onTap == null ? colors.textTertiary : colors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
