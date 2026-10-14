import 'machine_discovery.dart';

// What happens when the saved address does not answer: silently
// re-discover in the background, without a message.
//
// Order:
//   1. the last seen IP          -> rescues broken name resolution
//   2. one short network search  -> rescues a new IP
//   3. nothing                   -> the connection error stays
//
// Each address is tried only once per dropout, and searching happens at
// most once per [cooldown] — otherwise the services' retry loop would turn
// it into a permanent search.
class MachineAddressFallback {
  MachineAddressFallback({
    required this.serviceType,
    required this.discovery,
    this.lastIp,
    this.cooldown = const Duration(seconds: 20),
  });

  final String serviceType;
  final MachineDiscovery discovery;

  // Last seen address of the machine; updated when searching.
  String? lastIp;
  final Duration cooldown;

  final Set<String> _tried = {};
  DateTime? _lastScanAt;
  bool _scanning = false;

  // The connection is back: reset everything so the next dropout again has
  // both options at hand.
  void reset() {
    _tried.clear();
    _lastScanAt = null;
  }

  // Next address worth trying — or null.
  Future<String?> nextAddress(String currentHost) async {
    _tried.add(currentHost);

    final ip = lastIp;
    if (ip != null && !_tried.contains(ip)) {
      _tried.add(ip);
      return ip;
    }

    if (_scanning) return null;
    final since = _lastScanAt;
    if (since != null && DateTime.now().difference(since) < cooldown) {
      return null;
    }
    _scanning = true;
    _lastScanAt = DateTime.now();
    try {
      final found = await discovery.scan(serviceType);
      for (final machine in found) {
        if (machine.ipAddress != null) lastIp = machine.ipAddress;
        // The name first: it stays correct if the machine later gets a
        // different IP.
        for (final candidate in [machine.address, machine.ipAddress]) {
          if (candidate == null || _tried.contains(candidate)) continue;
          _tried.add(candidate);
          return candidate;
        }
      }
      return null;
    } finally {
      _scanning = false;
    }
  }
}
