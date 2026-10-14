import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MissingPluginException;

// Both machines announce themselves on the network via mDNS/Bonjour, each
// under its OWN service type — measured on a real network and checked in
// the firmware:
//
//   Meticulous: `_meticulous._tcp`, port 80
//               TXT: server_name, machine_name, ips, domain
//   GaggiMate:  `_gaggimate._tcp`, port 80
//               TXT: version, type=espresso_machine
//               (src/display/plugins/mDNSPlugin.cpp in the firmware)
//
// Both also announce `_http._tcp` — we deliberately do NOT query that:
// every printer, NAS and TV announces itself there. The own service types
// only return espresso machines.
const meticulousServiceType = '_meticulous._tcp';
const gaggimateServiceType = '_gaggimate._tcp';

// A machine found on the network.
@immutable
class DiscoveredMachine {
  const DiscoveredMachine({
    required this.displayName,
    required this.host,
    required this.port,
    this.ip,
    this.attributes = const {},
  });

  // What is shown in the list (TXT `machine_name`, else the instance name).
  final String displayName;
  // The mDNS hostname, e.g. "gaggimate.local" — this is the address that
  // gets stored.
  final String host;
  final int port;
  // Last seen address; stored as a fallback.
  final String? ip;
  final Map<String, String> attributes;

  // What goes into the address field: the port is only included where it
  // isn't the usual 80 (both machines report 80, but a modified setup
  // doesn't have to).
  String get address => port == 80 ? host : '$host:$port';

  // The fallback as it is stored — null if the platform didn't provide a
  // usable address.
  String? get ipAddress => ip == null ? null : (port == 80 ? ip : '$ip:$port');

  @override
  bool operator ==(Object other) =>
      other is DiscoveredMachine && other.host == host && other.ip == ip;

  @override
  int get hashCode => Object.hash(host, ip);
}

// The platform can't scan (Linux/Windows/Web — bonsoir only supports
// Android and Darwin). Not an error but a statement for the UI: it then
// says "only on Android and iOS", not "nothing found".
class DiscoveryUnsupported implements Exception {
  const DiscoveryUnsupported();

  @override
  String toString() => 'Service discovery is not available on this platform';
}

abstract class MachineDiscovery {
  // Emits found machines as soon as they are resolved and closes after
  // [timeout]. Errors: [DiscoveryUnsupported] or the platform exception.
  Stream<DiscoveredMachine> browse(
    String serviceType, {
    Duration timeout = const Duration(seconds: 4),
  });

  // Collect once and return — for the silent re-scan on connection loss,
  // which has no UI.
  Future<List<DiscoveredMachine>> scan(
    String serviceType, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final found = <DiscoveredMachine>[];
    try {
      await for (final machine in browse(serviceType, timeout: timeout)) {
        if (!found.contains(machine)) found.add(machine);
      }
    } catch (_) {
      // The silent scan stays silent.
    }
    return found;
  }
}

// Scans via the operating system's Bonjour/NSD services (bonsoir).
//
// Deliberately NOT via our own multicast socket: since iOS 14 that requires
// the `com.apple.developer.networking.multicast` entitlement, which has to
// be requested from Apple individually. Using the system services needs
// only two entries in Info.plist (NSBonjourServices + usage text), and
// Android needs nothing at all.
class BonsoirMachineDiscovery extends MachineDiscovery {
  @override
  Stream<DiscoveredMachine> browse(
    String serviceType, {
    Duration timeout = const Duration(seconds: 4),
  }) {
    late final StreamController<DiscoveredMachine> controller;
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? subscription;
    Timer? stopTimer;

    Future<void> cleanUp() async {
      stopTimer?.cancel();
      stopTimer = null;
      await subscription?.cancel();
      subscription = null;
      final running = discovery;
      discovery = null;
      if (running != null && !running.isStopped) {
        try {
          await running.stop();
        } catch (_) {
          // During cleanup a failed stop can't be rescued.
        }
      }
    }

    controller = StreamController<DiscoveredMachine>(
      onListen: () async {
        try {
          final started = BonsoirDiscovery(type: serviceType, printLogs: false);
          discovery = started;
          // In bonsoir 7 this step is called initialize() (previously
          // `ready`).
          await started.initialize();
          // Listen first, then start — otherwise the first responses get
          // lost (as the bonsoir docs say too).
          subscription = started.eventStream?.listen((event) {
            if (controller.isClosed) return;
            switch (event) {
              // Found only means "there is one" — address and TXT fields
              // only come with resolving, which has to be triggered.
              case BonsoirDiscoveryServiceFoundEvent():
                event.service.resolve(started.serviceResolver);
              case BonsoirDiscoveryServiceResolvedEvent():
                controller.add(machineFromService(event.service));
              default:
                break;
            }
          });
          await started.start();
          stopTimer = Timer(timeout, () {
            if (!controller.isClosed) controller.close();
          });
        } on MissingPluginException {
          if (!controller.isClosed) {
            controller.addError(const DiscoveryUnsupported());
            await controller.close();
          }
        } catch (error, stack) {
          if (!controller.isClosed) {
            controller.addError(error, stack);
            await controller.close();
          }
        }
      },
      onCancel: cleanUp,
    );
    return controller.stream;
  }

  // Not every address the platform reports works as a stored fallback:
  // Avahi e.g. also returns IPv6 link-local (fe80::…), which isn't
  // reachable without a zone index. IPv4 first, then a regular IPv6,
  // link-local never.
  @visibleForTesting
  static String? pickAddress(List<String> addresses) {
    final ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
    for (final address in addresses) {
      if (ipv4.hasMatch(address)) return address;
    }
    for (final address in addresses) {
      if (address.contains(':') && !address.toLowerCase().startsWith('fe80')) {
        return address;
      }
    }
    return null;
  }

  @visibleForTesting
  static DiscoveredMachine machineFromService(BonsoirService service) {
    final attributes = service.attributes;
    // The platform provides the hostname IF it can (Apple yes, Android's
    // NSD no — `BonsoirDiscovery.supportsMdnsHostname`). mDNS sends it with
    // a trailing dot, which is dropped here.
    final reported = service.hostname?.replaceAll(RegExp(r'\.$'), '');
    // Otherwise derived: both machines name their service instance after
    // their hostname — the Meticulous also confirms it in the TXT field
    // `server_name`, the GaggiMate calls `MDNS.begin(hostname)` and derives
    // the instance name from it. Since this remains a derivation, the
    // address is stored as a fallback too.
    final base = attributes['server_name'] ?? service.name;
    final derived = base.endsWith('.local') ? base : '$base.local';
    return DiscoveredMachine(
      displayName: attributes['machine_name'] ?? service.name,
      host: (reported != null && reported.isNotEmpty) ? reported : derived,
      port: service.port,
      ip: pickAddress(service.hostAddresses),
      attributes: attributes,
    );
  }
}
