import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/machine_discovery.dart';
import '../../theme/app_theme.dart';

// "Found on your network" — the upper part of a machine's connection card
// (the search sits on the respective machine's page, not on a shared
// search page).
//
// Only THIS machine's identifier is searched, so results are always of the
// right type. Tapping applies hostname and IP; the field below remains as
// a fallback for networks where mDNS doesn't get through.
class DiscoverySection extends StatefulWidget {
  const DiscoverySection({
    super.key,
    required this.serviceType,
    required this.currentHost,
    required this.onPick,
    this.onResults,
    this.discovery,
  });

  final String serviceType;
  // The currently configured address — the matching result is marked
  // instead of being offered with a pointless "Use".
  final String currentHost;
  final void Function(DiscoveredMachine machine) onPick;
  // Whoever builds the card needs the results too: the header names the
  // machine as soon as it is among those found.
  final void Function(List<DiscoveredMachine> machines)? onResults;
  // For tests; normally the search via the system services.
  final MachineDiscovery? discovery;

  @override
  State<DiscoverySection> createState() => _DiscoverySectionState();
}

class _DiscoverySectionState extends State<DiscoverySection> {
  late final MachineDiscovery _discovery =
      widget.discovery ?? BonsoirMachineDiscovery();

  final _found = <DiscoveredMachine>[];
  StreamSubscription<DiscoveredMachine>? _subscription;
  bool _scanning = false;
  // The platform can't search at all (Linux/Windows) — that's different
  // from "nothing found" and is described differently.
  bool _unsupported = false;
  String? _error;
  // "Nothing found" may only show after the first pass.
  bool _searchedOnce = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  // Report results only after the frame: the first _scan() runs from
  // initState, and whoever listens is building us right now (setState
  // during build).
  void _notifyResults() {
    final listener = widget.onResults;
    if (listener == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) listener(List.unmodifiable(_found));
    });
  }

  void _scan() {
    _subscription?.cancel();
    setState(() {
      _scanning = true;
      _unsupported = false;
      _error = null;
      _found.clear();
    });
    _notifyResults();
    _subscription = _discovery
        .browse(widget.serviceType)
        .listen(
          (machine) {
            if (!mounted || _found.contains(machine)) return;
            setState(() => _found.add(machine));
            _notifyResults();
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _scanning = false;
              _searchedOnce = true;
              if (error is DiscoveryUnsupported) {
                _unsupported = true;
              } else {
                _error = error.toString();
              }
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Machines on your network',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ),
            // Deliberately no spinning ring: it would run as a continuous
            // animation and hold up every pumpAndSettle in this page's tests.
            // The hint text below says that a search is running.
            InkWell(
              onTap: _scanning ? null : _scan,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.refresh,
                      size: 14,
                      color: _scanning ? colors.textTertiary : colors.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Scan',
                      style: TextStyle(
                        color: _scanning ? colors.textTertiary : colors.accent,
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
        for (final machine in _found)
          _MachineRow(
            machine: machine,
            // The check mark is on the machine in use — even if its IP is
            // configured rather than its name.
            inUse:
                machine.address == widget.currentHost ||
                machine.ipAddress == widget.currentHost,
            onTap: () => widget.onPick(machine),
          ),
        if (_found.isEmpty) _hint(context),
      ],
    );
  }

  Widget _hint(BuildContext context) {
    final colors = context.colors;
    final text = _unsupported
        // The system services we search through only exist there — on
        // desktop the field below is the way.
        ? 'Search needs Android or iOS — use "Enter address manually".'
        : _error != null
        ? 'Search failed: $_error'
        : _scanning
        ? 'Searching…'
        : _searchedOnce
        ? 'Nothing found. Check that the machine is on, or '
              'use "Enter address manually".'
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

class _MachineRow extends StatelessWidget {
  const _MachineRow({
    required this.machine,
    required this.inUse,
    required this.onTap,
  });

  final DiscoveredMachine machine;
  final bool inUse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The row shows what the machine itself reports: name on top, address
    // below. If the address is just the name with ".local" appended, it
    // says nothing new — then the IP alone is shown below (the Meticulous's
    // name is long enough not to read it three times).
    final host = machine.address;
    final sameAsName = host == '${machine.displayName}.local';
    final subtitle = machine.ipAddress == null
        ? host
        : sameAsName
        ? machine.ipAddress!
        : '$host · ${machine.ipAddress}';
    return InkWell(
      // The machine in use stays tappable too: if its IP is in the
      // settings, a tap sets its name again — the name survives a new IP,
      // the IP doesn't.
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.coffee_maker_outlined, size: 18, color: colors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    machine.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (inUse)
              Icon(Icons.check, size: 18, color: colors.success)
            else
              Text(
                'Use',
                style: TextStyle(
                  color: colors.accent,
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
