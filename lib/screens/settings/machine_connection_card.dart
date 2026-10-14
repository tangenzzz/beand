import 'package:flutter/material.dart';

import '../../machines/espresso_machine.dart';
import '../../services/machine_discovery.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/machine_badge.dart';
import '../history/history_logic.dart';
import 'discovery_section.dart';

// The connection card for both machines (clearer, and the same for
// Meticulous and GaggiMate).
//
// Layout, top to bottom:
//   1. What the app is connected to — badge, machine name, state, address.
//   2. The discovered machines: the normal path, tap here.
//   3. "Enter address manually", collapsed — the fallback for networks
//      without mDNS. Previously the text field was open at the top and
//      looked like the main path, although it is almost never needed.
//
// One card per settings page, as everywhere.
class MachineConnectionCard extends StatefulWidget {
  const MachineConnectionCard({
    super.key,
    required this.machine,
    required this.state,
    required this.activeAddress,
    required this.configuredAddress,
    required this.error,
    required this.serviceType,
    required this.onPick,
    required this.controller,
    required this.onSave,
    required this.manualHint,
    this.discovery,
  });

  // Provides badge, brand color and name — the same as in the history.
  final ShotMachine machine;
  final MachineConnectionState state;
  // The address the app is actually connected to right now (may be the
  // fallback IP), and the configured one shown in the field.
  final String activeAddress;
  final String configuredAddress;
  final String? error;

  final String serviceType;
  final void Function(DiscoveredMachine machine) onPick;
  final TextEditingController controller;
  final VoidCallback onSave;
  final String manualHint;
  final MachineDiscovery? discovery;

  @override
  State<MachineConnectionCard> createState() => _MachineConnectionCardState();
}

class _MachineConnectionCardState extends State<MachineConnectionCard> {
  bool _manualOpen = false;
  List<DiscoveredMachine> _found = const [];

  // The machine's name is shown at the top. If it is among the discovered
  // ones, it names itself; otherwise only the configured address is left,
  // but without the technical suffix.
  String get _title {
    final configured = widget.configuredAddress;
    for (final machine in _found) {
      if (machine.address == configured || machine.ipAddress == configured) {
        return machine.displayName;
      }
    }
    if (configured.isEmpty) return widget.machine.label;
    final withoutPort = configured.split(':').first;
    return withoutPort.endsWith('.local')
        ? withoutPort.substring(0, withoutPort.length - '.local'.length)
        : withoutPort;
  }

  // The address appears in the status line only when the app is connected
  // to a DIFFERENT one than the configured one — i.e. the fallback IP. That
  // is its only purpose here.
  //
  // Previously it was compared with the title, and because the title holds
  // the name without ".local", it counted as different: the long machine
  // name then appeared a second time, truncated (it showed up four times on
  // one page).
  String _statusLine(String stateLabel) =>
      widget.activeAddress.isEmpty ||
          widget.activeAddress == widget.configuredAddress
      ? stateLabel
      : '$stateLabel · ${widget.activeAddress}';

  (Color, String) _status(BuildContext context) => switch (widget.state) {
    MachineConnectionState.connected => (context.colors.success, 'Connected'),
    MachineConnectionState.connecting => (
      context.colors.sensorMid,
      'Connecting…',
    ),
    MachineConnectionState.disconnected => (
      context.colors.textTertiary,
      'Not connected',
    ),
    MachineConnectionState.error => (
      context.colors.danger,
      'Connection failed',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (dotColor, stateLabel) = _status(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MachineBadge(
                glyph: widget.machine.glyph,
                color: widget.machine.color,
                size: 34,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
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
                            // The address belongs here: it is the only
                            // hint that the app is currently running on
                            // the fallback IP instead of the name.
                            _statusLine(stateLabel),
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
                    if (widget.error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.error!,
                        maxLines: 2,
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
          Divider(height: 24, color: colors.divider),
          DiscoverySection(
            serviceType: widget.serviceType,
            currentHost: widget.configuredAddress,
            discovery: widget.discovery,
            onPick: widget.onPick,
            onResults: (machines) {
              if (mounted) setState(() => _found = machines);
            },
          ),
          Divider(height: 24, color: colors.divider),
          InkWell(
            onTap: () => setState(() => _manualOpen = !_manualOpen),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Enter address manually',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    _manualOpen ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_manualOpen) ...[
            const SizedBox(height: 8),
            TextField(
              controller: widget.controller,
              style: TextStyle(color: colors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: widget.manualHint,
                hintStyle: TextStyle(color: colors.textTertiary),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Save & reconnect',
                onPressed: widget.onSave,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
