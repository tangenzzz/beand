import 'machine_address_store.dart';
import 'machine_discovery.dart';

// What happens when the saved address does not answer: silently
// re-discover in the background, without a message.
//
// Order:
//   1. the last seen IP          -> rescues broken name resolution
//   2. one short network search  -> rescues a new IP, but only for the
//      machine with the stored name: another machine of the same kind on
//      the network is a different device, not a new address. Stored as an
//      IP, the machine has no name to compare; then only a search that
//      finds a single machine of this kind counts.
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
  // The address the user chose, i.e. the first one that failed in this
  // dropout. Later calls report the stand-ins tried since (the last IP), but
  // which machine is wanted is decided by this one.
  String? _chosenHost;
  String? _standIn;

  /// Whether [address] is only the last seen IP standing in for the chosen
  /// address. It is not a new address to remember: the next start should
  /// still look for the chosen machine.
  bool isStandIn(String address) => address == _standIn;

  DateTime? _lastScanAt;
  bool _scanning = false;

  // The connection is back: reset so the next dropout again has both
  // options at hand. Which machine is wanted is kept: connected through the
  // stand-in IP, the next dropout still looks for the chosen one.
  void reset() {
    _tried.clear();
    _lastScanAt = null;
  }

  // Next address worth trying — or null.
  Future<String?> nextAddress(String currentHost) async {
    if (_tried.isEmpty && !isStandIn(currentHost)) {
      _chosenHost = currentHost;
      _standIn = null;
    }
    _tried.add(currentHost);
    final chosen = _chosenHost ?? currentHost;

    final ip = lastIp;
    if (ip != null && !_tried.contains(ip)) {
      _tried.add(ip);
      _standIn = ip;
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
      final byIp = looksLikeIpAddress(chosen);
      for (final machine in found) {
        final same = _hostName(machine.address) == _hostName(chosen);
        if (!same && !(byIp && found.length == 1)) continue;
        if (machine.ipAddress != null) lastIp = machine.ipAddress;
        // The name first: it stays correct if the machine later gets a
        // different IP.
        for (final candidate in [machine.address, machine.ipAddress]) {
          if (candidate == null ||
              _tried.contains(candidate) ||
              _hostName(candidate) == _hostName(chosen)) {
            continue;
          }
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

/// "Meticulous-ABC.local.:80" and "meticulous-abc.local" are one machine.
String _hostName(String address) {
  var host = address.trim().toLowerCase();
  final colon = host.lastIndexOf(':');
  if (colon > 0 && !host.contains(']')) host = host.substring(0, colon);
  while (host.endsWith('.')) {
    host = host.substring(0, host.length - 1);
  }
  return host;
}
