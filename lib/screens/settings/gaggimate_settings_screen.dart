import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../machines/gaggimate/gaggimate_service.dart';
import '../../services/machine_address_store.dart';
import '../../services/machine_discovery.dart';
import '../../theme/app_theme.dart';
import '../history/history_logic.dart';
import 'machine_connection_card.dart';

const gaggimateHostPrefKey = 'gaggimate_host';
// See lastIpPrefKey in meticulous_settings_screen.dart — each machine
// remembers its last seen IP separately.
const gaggimateLastIpPrefKey = 'gaggimate_last_ip';

const gaggimateAddressStore = MachineAddressStore(
  hostKey: gaggimateHostPrefKey,
  ipKey: gaggimateLastIpPrefKey,
);

// GaggiMate connection page — one card, like everywhere in the settings,
// and the same as for the Meticulous (MachineConnectionCard).
class GaggiMateSettingsScreen extends StatefulWidget {
  const GaggiMateSettingsScreen({super.key, this.discovery});

  // For tests; normally DiscoverySection searches via the system services.
  final MachineDiscovery? discovery;

  @override
  State<GaggiMateSettingsScreen> createState() =>
      _GaggiMateSettingsScreenState();
}

class _GaggiMateSettingsScreenState extends State<GaggiMateSettingsScreen> {
  late final TextEditingController _hostController;

  // See _configuredHost in meticulous_settings_screen.dart.
  String? _configuredHost;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(
      text: context.read<GaggiMateService>().host,
    );
    unawaited(_showConfiguredHost());
  }

  Future<void> _showConfiguredHost() async {
    final configured = await gaggimateAddressStore.configuredHost();
    if (!mounted || configured == null || configured.isEmpty) return;
    setState(() => _configuredHost = configured);
    if (_hostController.text == configured) return;
    _hostController.text = configured;
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final host = _hostController.text.trim();
    if (host.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(gaggimateHostPrefKey, host);
    if (!mounted) return;
    setState(() => _configuredHost = host);
    _reconnect(host);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved, reconnecting…')));
  }

  // See _useDiscovered in meticulous_settings_screen.dart.
  Future<void> _useDiscovered(DiscoveredMachine machine) async {
    _hostController.text = machine.address;
    final ip = machine.ipAddress;
    await gaggimateAddressStore.remember(address: machine.address, ip: ip);
    if (!mounted) return;
    setState(() => _configuredHost = machine.address);
    final service = context.read<GaggiMateService>();
    if (ip != null) service.addressFallback?.lastIp = ip;
    _reconnect(machine.address);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Using ${machine.displayName}')));
  }

  void _reconnect(String host) {
    final service = context.read<GaggiMateService>();
    // updateHost only reconnects if the name actually changes — with the
    // same name "Save & reconnect" is still a request to reconnect.
    if (host == service.host) {
      service.connect();
    } else {
      service.updateHost(host);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<GaggiMateService>();

    return Scaffold(
      appBar: AppBar(title: const Text('GaggiMate')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          MachineConnectionCard(
            machine: ShotMachine.gaggiMate,
            state: service.connectionState,
            activeAddress: service.host,
            configuredAddress: _configuredHost ?? service.host,
            error: service.lastError,
            serviceType: gaggimateServiceType,
            discovery: widget.discovery,
            onPick: _useDiscovered,
            controller: _hostController,
            onSave: _save,
            manualHint: 'e.g. gaggimate.local or 192.168.1.20:8080',
          ),
        ],
      ),
    );
  }
}
