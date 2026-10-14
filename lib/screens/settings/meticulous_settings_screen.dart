import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/machine_address_store.dart';
import '../../services/machine_discovery.dart';
import '../../services/meticulous_socket_service.dart';
import '../../theme/app_theme.dart';
import '../history/history_logic.dart';
import 'machine_connection_card.dart';

const hostnamePrefKey = 'machine_hostname';
// Last seen IP of the machine — silent fallback when the .local name no
// longer resolves (store the name, keep the IP next to it).
const lastIpPrefKey = 'machine_last_ip';

const meticulousAddressStore = MachineAddressStore(
  hostKey: hostnamePrefKey,
  ipKey: lastIpPrefKey,
);

class MeticulousSettingsScreen extends StatefulWidget {
  const MeticulousSettingsScreen({super.key, this.discovery});

  // For tests; normally DiscoverySection searches via the system services.
  final MachineDiscovery? discovery;

  @override
  State<MeticulousSettingsScreen> createState() =>
      _MeticulousSettingsScreenState();
}

class _MeticulousSettingsScreenState extends State<MeticulousSettingsScreen> {
  late final TextEditingController _hostnameController;

  // The configured address — it can differ from the one currently in use
  // if the app has fallen back to the fallback IP.
  String? _configuredHost;

  @override
  void initState() {
    super.initState();
    final service = context.read<MeticulousSocketService>();
    _hostnameController = TextEditingController(text: service.hostname);
    // If the app is currently running on the fallback IP, the field still
    // shows the configured name — otherwise it would look as if it were
    // gone, and a tap on "Save & reconnect" would make the IP the setting.
    // The status line above says what the app is really connected to.
    unawaited(_showConfiguredHost());
  }

  Future<void> _showConfiguredHost() async {
    final configured = await meticulousAddressStore.configuredHost();
    if (!mounted || configured == null || configured.isEmpty) return;
    setState(() => _configuredHost = configured);
    if (_hostnameController.text == configured) return;
    _hostnameController.text = configured;
  }

  @override
  void dispose() {
    _hostnameController.dispose();
    super.dispose();
  }

  Future<void> _saveHostname() async {
    final newHostname = _hostnameController.text.trim();
    if (newHostname.isEmpty) return;
    // An IP entered by hand becomes the setting here too — unlike the silent
    // re-discovery, this is the explicit wish.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(hostnamePrefKey, newHostname);
    if (!mounted) return;
    setState(() => _configuredHost = newHostname);
    context.read<MeticulousSocketService>().updateHostname(newHostname);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved, reconnecting…')));
  }

  // Adopt a discovered machine: the name becomes the address, the IP goes
  // next to it as fallback.
  Future<void> _useDiscovered(DiscoveredMachine machine) async {
    _hostnameController.text = machine.address;
    final ip = machine.ipAddress;
    await meticulousAddressStore.remember(address: machine.address, ip: ip);
    if (!mounted) return;
    setState(() => _configuredHost = machine.address);
    final service = context.read<MeticulousSocketService>();
    if (ip != null) service.addressFallback?.lastIp = ip;
    service.updateHostname(machine.address);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Using ${machine.displayName}')));
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<MeticulousSocketService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Meticulous')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          MachineConnectionCard(
            machine: ShotMachine.meticulous,
            state: service.connectionState,
            activeAddress: service.hostname,
            configuredAddress: _configuredHost ?? service.hostname,
            error: service.lastError,
            serviceType: meticulousServiceType,
            discovery: widget.discovery,
            onPick: _useDiscovered,
            controller: _hostnameController,
            onSave: _saveHostname,
            manualHint: 'e.g. meticulous-XXXX.local',
          ),
        ],
      ),
    );
  }
}
