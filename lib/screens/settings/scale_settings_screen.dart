import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../scale/brew_scale.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

// Connection page of the Bluetooth scale (Settings → Connections), built
// like the machines' one (MachineConnectionCard): at the top what the app
// is connected to, below the found scales to tap. Plus the live weight with
// tare — so the scale can be checked without starting a brew — and,
// collapsed, the raw data for debugging.
//
// One card per settings page.
class ScaleSettingsScreen extends StatelessWidget {
  const ScaleSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bluetooth Scale')),
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

  @override
  void initState() {
    super.initState();
    // Don't scan while the scale is already connected or scanning itself —
    // Android does not like two scans at the same time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scale = context.read<BrewScale>();
      if (mounted && scale.connection == ScaleConnection.disconnected) _scan();
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
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
    await _scanSub?.cancel();
    if (mounted) setState(() => _scanning = false);
    if (!mounted) return;
    await context.read<BrewScale>().connectTo(c);
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

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                child: Icon(
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
                      scale.deviceName ?? 'Bluetooth Scale',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
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
                  onPressed: scale.tare,
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
          const SizedBox(height: 12),
          Row(
            children: [
              if (scale.isConnected || busy)
                AppButton(
                  label: 'Disconnect',
                  variant: AppButtonVariant.secondary,
                  expand: false,
                  height: 36,
                  onPressed: scale.disconnect,
                )
              else if (scale.rememberedId != null)
                AppButton(
                  label: 'Connect',
                  expand: false,
                  height: 36,
                  onPressed: scale.connect,
                ),
              const Spacer(),
              if (scale.rememberedId != null)
                AppButton(
                  label: 'Forget',
                  variant: AppButtonVariant.secondary,
                  expand: false,
                  height: 36,
                  onPressed: () {
                    scale.forget();
                    _scan();
                  },
                ),
            ],
          ),
          Divider(height: 24, color: colors.divider),
          // ---- Found scales ----
          Row(
            children: [
              Expanded(
                child: Text(
                  'Scales nearby',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ),
              InkWell(
                onTap: _scanning || busy ? null : _scan,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.refresh,
                        size: 14,
                        color: _scanning || busy
                            ? colors.textTertiary
                            : colors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Scan',
                        style: TextStyle(
                          color: _scanning || busy
                              ? colors.textTertiary
                              : colors.accent,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final c in _found)
            _ScaleRow(
              candidate: c,
              inUse: c.id == scale.rememberedId,
              connected: c.id == scale.rememberedId && scale.isConnected,
              onTap: busy ? null : () => _use(c),
            ),
          if (_found.isEmpty) _hint(context),
          const SizedBox(height: 4),
          Text(
            'Supported: Acaia Lunar, Pearl, Pyxis and other Acaia scales. '
            'Close other apps that use the scale first.',
            style: TextStyle(color: colors.textTertiary, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _hint(BuildContext context) {
    final colors = context.colors;
    final text = _scanError != null
        ? _scanError!
        : _scanning
        ? 'Searching…'
        : _searchedOnce
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
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
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
