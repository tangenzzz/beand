import 'package:beand/models/machine_status.dart';
import 'package:beand/screens/settings/discovery_section.dart';
import 'package:beand/screens/settings/meticulous_settings_screen.dart';
import 'package:beand/services/machine_address_fallback.dart';
import 'package:beand/services/machine_address_store.dart';
import 'package:beand/services/machine_discovery.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Does not really search — bonsoir needs Android or iOS; there is no
// platform side in tests.
class FakeDiscovery extends MachineDiscovery {
  FakeDiscovery(this.machines, {this.error});

  final List<DiscoveredMachine> machines;
  final Object? error;
  final askedTypes = <String>[];

  @override
  Stream<DiscoveredMachine> browse(
    String serviceType, {
    Duration timeout = const Duration(seconds: 4),
  }) {
    askedTypes.add(serviceType);
    if (error != null) return Stream<DiscoveredMachine>.error(error!);
    return Stream.fromIterable(machines);
  }
}

// Does not really connect: socket.io would start a real attempt in the
// test and leave running timers behind.
class OfflineSocket extends MeticulousSocketService {
  OfflineSocket({super.hostname = 'alt.local'});

  int connects = 0;

  @override
  void connect() => connects++;
}

const _meticulous = DiscoveredMachine(
  displayName: 'meticulousDemoMachine-000000',
  host: 'meticulousDemoMachine-000000.local',
  ip: '192.168.1.20',
  port: 80,
);
// A machine whose display name is NOT its hostname — then the address
// below the name says something new.
const _renamed = DiscoveredMachine(
  displayName: 'Kitchen',
  host: 'meticulous-kitchen.local',
  ip: '192.168.1.42',
  port: 80,
);
const _other = DiscoveredMachine(
  displayName: 'meticulous-spare',
  host: 'meticulous-spare.local',
  ip: '192.168.1.99',
  port: 80,
);

void main() {
  Widget wrapSection(
    FakeDiscovery discovery, {
    required String currentHost,
    required void Function(DiscoveredMachine) onPick,
  }) => MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: DiscoverySection(
        serviceType: meticulousServiceType,
        currentHost: currentHost,
        discovery: discovery,
        onPick: onPick,
      ),
    ),
  );

  testWidgets('found machines are listed with name, hostname and IP', (
    tester,
  ) async {
    final discovery = FakeDiscovery([_meticulous, _renamed]);
    await tester.pumpWidget(
      wrapSection(discovery, currentHost: 'alt.local', onPick: (_) {}),
    );
    await tester.pump();

    // Only our own service type is queried, not _http._tcp.
    expect(discovery.askedTypes, [meticulousServiceType]);
    expect(find.text(_meticulous.displayName), findsOneWidget);
    // The hostname is just the name with ".local" — so only the IP is shown
    // below it, not both.
    expect(find.text(_meticulous.ip!), findsOneWidget);
    expect(
      find.text('${_meticulous.host} · ${_meticulous.ip}'),
      findsNothing,
      reason: 'name not three times on one page',
    );
    // A machine whose hostname is NOT its name shows both.
    expect(find.text('${_renamed.host} · ${_renamed.ip}'), findsOneWidget);
    expect(find.text('Use'), findsNWidgets(2));
  });

  testWidgets('the configured machine is marked and not tappable', (
    tester,
  ) async {
    final picked = <DiscoveredMachine>[];
    await tester.pumpWidget(
      wrapSection(
        FakeDiscovery([_meticulous, _other]),
        currentHost: _meticulous.host,
        onPick: picked.add,
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('Use'), findsOneWidget, reason: 'only the other one');

    // The machine in use carries the check mark but stays tappable: if its
    // IP is in the settings, a tap brings its name back.
    await tester.tap(find.text(_meticulous.displayName));
    await tester.pump();
    expect(picked, [_meticulous]);

    await tester.tap(find.text(_other.displayName));
    await tester.pump();
    expect(picked, [_meticulous, _other]);
  });

  testWidgets('without platform support it says what to do', (tester) async {
    await tester.pumpWidget(
      wrapSection(
        FakeDiscovery(const [], error: const DiscoveryUnsupported()),
        currentHost: 'alt.local',
        onPick: (_) {},
      ),
    );
    await tester.pump();

    expect(
      find.text('Search needs Android or iOS — use "Enter address manually".'),
      findsOneWidget,
    );
  });

  testWidgets('an empty network says so instead of staying silent', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapSection(
        FakeDiscovery(const []),
        currentHost: 'alt.local',
        onPick: (_) {},
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Nothing found. Check that the machine is on, or '
        'use "Enter address manually".',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping saves hostname and IP and reconnects', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = OfflineSocket();
    addTearDown(service.dispose);
    service.latestStatus = MachineStatus.fromJson({'name': 'idle'});

    await tester.pumpWidget(
      ChangeNotifierProvider<MeticulousSocketService>.value(
        value: service,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MeticulousSettingsScreen(
            discovery: FakeDiscovery([_meticulous]),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Use'));
    await tester.pump();
    await tester.pump();

    expect(service.hostname, _meticulous.host);
    expect(service.connects, 1, reason: 'reconnected once');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(hostnamePrefKey), _meticulous.host);
    expect(
      prefs.getString(lastIpPrefKey),
      _meticulous.ip,
      reason: 'IP stored alongside as fallback',
    );
  });

  testWidgets('the card says at the top what the app is connected to', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'flutter.machine_hostname': 'meine-maschine.local',
    });
    final service = OfflineSocket();
    addTearDown(service.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MeticulousSocketService>.value(
        value: service,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MeticulousSettingsScreen(discovery: FakeDiscovery(const [])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // The name without the technical suffix at the top, ...
    expect(find.text('meine-maschine'), findsOneWidget);
    // ... below it the state and the address the app is really connected
    // to — here a different one than configured, i.e. the fallback.
    expect(find.text('Not connected · alt.local'), findsOneWidget);
    // And the text field sits collapsed below.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('at the configured address only the state is shown', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'flutter.machine_hostname': 'meine-maschine.local',
    });
    final service = OfflineSocket(hostname: 'meine-maschine.local');
    addTearDown(service.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MeticulousSocketService>.value(
        value: service,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MeticulousSettingsScreen(discovery: FakeDiscovery(const [])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('meine-maschine'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    // The long name appeared twice here, because the title carries it
    // without ".local" and the status line with it.
    expect(find.text('Not connected · meine-maschine.local'), findsNothing);
  });

  // Regression: the same IP appeared twice at the top.
  testWidgets('the address does not appear twice in the header', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'flutter.machine_hostname': '192.168.1.20',
    });
    final service = OfflineSocket(hostname: '192.168.1.20');
    addTearDown(service.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MeticulousSocketService>.value(
        value: service,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MeticulousSettingsScreen(discovery: FakeDiscovery(const [])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Nothing found: the address is the title — then the line below only
    // shows the state.
    expect(find.text('192.168.1.20'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Not connected · 192.168.1.20'), findsNothing);
  });

  // If the machine is among the found ones, the header calls it by its
  // name — and the address below then says something new.
  testWidgets('a found machine gives the header its name', (tester) async {
    SharedPreferences.setMockInitialValues({
      'flutter.machine_hostname': '192.168.1.20',
    });
    final service = OfflineSocket();
    addTearDown(service.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<MeticulousSocketService>.value(
        value: service,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MeticulousSettingsScreen(
            discovery: FakeDiscovery([_meticulous]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(
      find.text(_meticulous.displayName),
      findsNWidgets(2),
      reason: 'header and result list',
    );
    // Its IP is configured, the same machine is meant: check mark.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('Use'), findsNothing);
  });

  group('MachineAddressFallback', () {
    test('tries the last IP first, then the search', () async {
      final discovery = FakeDiscovery([_other]);
      final fallback = MachineAddressFallback(
        serviceType: meticulousServiceType,
        discovery: discovery,
        lastIp: '192.168.1.20',
      );

      expect(
        await fallback.nextAddress('alt.local'),
        '192.168.1.20',
        reason: 'the remembered IP costs no search',
      );
      expect(discovery.askedTypes, isEmpty);

      // The IP does not answer either -> search.
      expect(await fallback.nextAddress('192.168.1.20'), _other.host);
      expect(discovery.askedTypes, [meticulousServiceType]);
      // And the found machine's IP is now the remembered one.
      expect(fallback.lastIp, _other.ip);
    });

    test('the same address is not suggested twice', () async {
      final fallback = MachineAddressFallback(
        serviceType: meticulousServiceType,
        discovery: FakeDiscovery([_meticulous]),
        cooldown: Duration.zero,
      );

      expect(await fallback.nextAddress('alt.local'), _meticulous.host);
      // The found hostname does not answer either -> its IP.
      expect(await fallback.nextAddress(_meticulous.host), _meticulous.ip);
      // After that nothing is left.
      expect(await fallback.nextAddress(_meticulous.ip!), isNull);
    });

    test('does not search in an endless loop', () async {
      final discovery = FakeDiscovery(const []);
      final fallback = MachineAddressFallback(
        serviceType: meticulousServiceType,
        discovery: discovery,
        cooldown: const Duration(seconds: 20),
      );

      expect(await fallback.nextAddress('alt.local'), isNull);
      expect(await fallback.nextAddress('alt.local'), isNull);
      expect(
        discovery.askedTypes,
        hasLength(1),
        reason: 'Socket.IO retries often, searching happens rarely',
      );

      // After a successful connection everything starts over.
      fallback.reset();
      expect(await fallback.nextAddress('alt.local'), isNull);
      expect(discovery.askedTypes, hasLength(2));
    });
  });

  // Regression: after a failed attempt the IP was saved as the hostname in
  // the settings and the name was gone.
  group('What may be saved', () {
    const store = MachineAddressStore(hostKey: 'host_key', ipKey: 'ip_key');

    test('an IP does not replace the configured name', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.host_key': 'meine-maschine.local',
      });

      await store.remember(address: '192.168.1.20');

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('host_key'),
        'meine-maschine.local',
        reason: 'the name survives the dropout',
      );
      expect(prefs.getString('ip_key'), '192.168.1.20');
    });

    test('a name is saved and takes the IP along', () async {
      SharedPreferences.setMockInitialValues({});

      await store.remember(address: 'meine-maschine.local', ip: '192.168.1.20');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('host_key'), 'meine-maschine.local');
      expect(prefs.getString('ip_key'), '192.168.1.20');
    });

    test('recognizes IP addresses, also with a port', () {
      expect(looksLikeIpAddress('192.168.1.20'), isTrue);
      expect(looksLikeIpAddress('192.168.1.20:8080'), isTrue);
      expect(looksLikeIpAddress('[2001:db8::1]:8080'), isTrue);
      expect(looksLikeIpAddress('2001:db8::1'), isTrue);
      expect(looksLikeIpAddress('gaggimate.local'), isFalse);
      expect(looksLikeIpAddress('gaggimate.local:8080'), isFalse);
      expect(looksLikeIpAddress('meticulousDemoMachine-000000.local'), isFalse);
    });
  });

  group('Hostname derivation', () {
    // Android's NSD reports no hostname (BonsoirDiscovery.
    // supportsMdnsHostname is false there): the name is derived, the
    // address stays alongside as fallback.
    test('without a reported hostname the instance name provides it', () {
      final machine = BonsoirMachineDiscovery.machineFromService(
        BonsoirService(
          name: 'meticulousDemoMachine-000000',
          type: meticulousServiceType,
          port: 80,
          hostAddresses: const ['192.168.1.20'],
          attributes: const {
            'server_name': 'meticulousDemoMachine-000000',
            'machine_name': 'meticulousDemoMachine-000000',
          },
        ),
      );

      expect(machine.host, 'meticulousDemoMachine-000000.local');
      expect(machine.ip, '192.168.1.20');
      expect(machine.displayName, 'meticulousDemoMachine-000000');
      expect(
        machine.address,
        'meticulousDemoMachine-000000.local',
        reason: 'port 80 is not in the field',
      );
    });

    // Apple's Bonjour reports the hostname — it is authoritative, not
    // derived, and is taken as it comes (without the trailing dot mDNS
    // sends along).
    test('a reported hostname wins over the derivation', () {
      final machine = BonsoirMachineDiscovery.machineFromService(
        BonsoirService(
          name: 'GaggiMate',
          type: gaggimateServiceType,
          port: 80,
          hostname: 'gaggimate.local.',
          hostAddresses: const ['192.168.1.57'],
          attributes: const {'version': '1.2.3', 'type': 'espresso_machine'},
        ),
      );

      expect(machine.host, 'gaggimate.local');
      expect(machine.ip, '192.168.1.57');
      expect(machine.displayName, 'GaggiMate');
    });

    test('an unusual port is included in the address', () {
      final machine = BonsoirMachineDiscovery.machineFromService(
        BonsoirService(
          name: 'gaggimate',
          type: gaggimateServiceType,
          port: 8080,
          hostAddresses: const ['192.168.1.57'],
        ),
      );

      expect(machine.address, 'gaggimate.local:8080');
      expect(machine.ipAddress, '192.168.1.57:8080');
    });

    test('IPv4 first, link-local never', () {
      expect(
        BonsoirMachineDiscovery.pickAddress(const [
          'fe80::1234',
          '2001:db8::1',
          '192.168.1.5',
        ]),
        '192.168.1.5',
      );
      // Avahi also reports only link-local for services on the same host —
      // nothing to be done with that.
      expect(BonsoirMachineDiscovery.pickAddress(const ['fe80::1234']), isNull);
      expect(
        BonsoirMachineDiscovery.pickAddress(const ['fe80::1', '2001:db8::1']),
        '2001:db8::1',
      );
      expect(BonsoirMachineDiscovery.pickAddress(const []), isNull);
    });
  });
}
