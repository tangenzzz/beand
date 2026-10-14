import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../machines/gaggimate/gaggimate_service.dart';
import '../../scale/brew_scale.dart';
import '../../services/app_settings.dart';
import '../../services/meticulous_socket_service.dart';
import '../../theme/app_theme.dart';

// Header bar in the Home tab (design H1): oval pills to switch the Home
// view, each with connection status. Which pills appear is controlled by
// Settings → Home. Meticulous/GaggiMate show a dot, Pour Over a Bluetooth
// icon (scale); color logic is the same everywhere (see _statusColor).
class HomeModeBar extends StatelessWidget {
  const HomeModeBar({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final active = settings.activeHomeMode;
    final modes = settings.enabledHomeModes;

    // Long-press and drag reorders the pills; the order is stored in the
    // settings and survives a restart. On the phone, ReorderableListView
    // only starts after a hold by itself — a short tap still switches.
    //
    // On narrow displays the bar scrolls horizontally instead of
    // overflowing; the list takes care of that too.
    return SizedBox(
      height: _barHeight,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: modes.length,
        onReorderItem: settings.reorderEnabledHomeModes,
        // Otherwise the pill lifts with a Material shadow while dragging,
        // which doesn't fit the bar.
        proxyDecorator: (child, _, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, _) => Opacity(opacity: 0.85, child: child),
        ),
        itemBuilder: (context, i) => Padding(
          key: ValueKey(modes[i]),
          padding: const EdgeInsets.only(right: 8),
          child: Center(
            child: _ModePill(
              mode: modes[i],
              selected: modes[i] == active,
              onTap: () => settings.setHomeMode(modes[i]),
            ),
          ),
        ),
      ),
    );
  }

  // Height of the pill including border; the list needs a fixed size.
  static const _barHeight = 30.0;
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final HomeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Subtle: same (transparent) background for all; the active pill only
    // has a slightly lighter border + white text, no accent teal.
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? context.colors.textTertiary
              : context.colors.divider,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mode.label,
                style: TextStyle(
                  color: selected
                      ? context.colors.textPrimary
                      : context.colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              _StatusIndicator(mode: mode),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.mode});

  final HomeMode mode;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, _stateFor(context, mode));
    if (mode == HomeMode.pourOver) {
      return Icon(Icons.bluetooth, size: 13, color: color);
    }
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// select instead of watch: the pill should only rebuild on status changes,
// not on every sensor tick of the socket service.
MachineConnectionState _stateFor(BuildContext context, HomeMode mode) {
  switch (mode) {
    case HomeMode.meticulous:
      return context.select<MeticulousSocketService, MachineConnectionState>(
        (s) => s.connectionState,
      );
    case HomeMode.gaggimate:
      return context.select<GaggiMateService, MachineConnectionState>(
        (s) => s.connectionState,
      );
    // The scale: searching/connecting counts like connecting a machine.
    case HomeMode.pourOver:
      return context.select<BrewScale, MachineConnectionState>(
        (s) => switch (s.connection) {
          ScaleConnection.connected => MachineConnectionState.connected,
          ScaleConnection.scanning ||
          ScaleConnection.connecting => MachineConnectionState.connecting,
          ScaleConnection.disconnected =>
            s.error != null
                ? MachineConnectionState.error
                : MachineConnectionState.disconnected,
        },
      );
  }
}

Color _statusColor(BuildContext context, MachineConnectionState state) {
  switch (state) {
    case MachineConnectionState.connected:
      return context.colors.success;
    case MachineConnectionState.connecting:
      return context.colors.sensorMid;
    case MachineConnectionState.disconnected:
      return context.colors.textSecondary;
    case MachineConnectionState.error:
      return context.colors.danger;
  }
}
