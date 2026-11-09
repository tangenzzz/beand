import 'package:beand/screens/settings/about_settings_screen.dart';
import 'package:beand/screens/settings/connection_log_screen.dart';
import 'package:beand/services/connection_log.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> logged;
  setUp(() {
    logged = [];
    ConnectionLog.sink = logged.add;
  });
  tearDown(() => ConnectionLog.sink = null);

  test(
    'a command that does not reach the machine is logged with why',
    () async {
      // Nothing listens on port 9: the request is refused at once.
      final socket = MeticulousSocketService(hostname: '127.0.0.1:9');
      final ok = await socket.triggerAction('continue');
      expect(ok, isFalse);
      expect(logged.single, contains('action continue failed:'));
    },
  );

  testWidgets('the log page lists newest first, trouble stands out', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ConnectionLogScreen(
          load: () async => [
            '2026-10-21T20:30:00.000 connected meticulous.local',
            '2026-10-21T20:31:05.000 reconnect no status for 3400 ms',
          ],
        ),
      ),
    );
    await tester.pump();

    // Folded by default; the toggle names how many there are.
    expect(find.text('Show 2 entries'), findsOneWidget);
    expect(find.textContaining('no status', findRichText: true), findsNothing);
    await tester.tap(find.byKey(const ValueKey('log-toggle')));
    await tester.pump();

    final reconnect = find.textContaining('no status', findRichText: true);
    final connected = find.textContaining(
      'meticulous.local',
      findRichText: true,
    );
    expect(reconnect, findsOneWidget);
    expect(connected, findsOneWidget);
    expect(
      tester.getTopLeft(reconnect).dy,
      lessThan(tester.getTopLeft(connected).dy),
      reason: 'newest first',
    );
    expect(find.text('Share log'), findsOneWidget);
    expect(find.text('Clear log'), findsOneWidget);
  });

  group('nothing private gets in', () {
    for (final (name, input, secret) in [
      ('nostr secret key', 'failed nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqq', 'nsec1'),
      ('nostr public key', 'for npub1abcdefghijklmnopqrstuv', 'npub1'),
      ('API key', 'Incorrect API key provided: sk-ant-abc123def456', 'sk-ant'),
      ('Google key', 'key AIzaSyA1234567890abcdefghijklmn', 'AIza'),
      ('bearer token', 'Authorization: Bearer abc.def.ghi', 'abc.def'),
      ('blossom auth', 'header Nostr eyJpZCI6IjEyMzQ1Njc4OTAifQ==', 'eyJpZ'),
      ('hex key', 'pubkey ${'a1' * 32} rejected', 'a1a1a1'),
      ('email', 'mail from someone@example.com failed', 'someone@'),
      (
        'LAN address',
        'SocketException address = 192.168.1.67, port',
        '192.168',
      ),
      ('IPv6', 'address 2606:4700:3037::ac43:ce80 refused', '2606:4700'),
      ('Bluetooth address', 'attempt on AA:BB:CC:DD:EE:FF ended', 'AA:BB'),
      ('iOS device id', 'id 12345678-90ab-cdef-1234-567890abcdef', '12345678'),
      ('machine serial', 'connect meticulous-a1b2c3.local', 'a1b2c3'),
      ('machine serial, bare', 'connect meticulousA1B2C3', 'A1B2C3'),
      ('Tailscale name', 'connect pi.tailnet-abc.ts.net', 'tailnet-abc'),
      ('private server', 'lookup wss://relay.my-home.example/x', 'my-home'),
      ('host lookup', "Failed host lookup: 'my-home.example'", 'my-home'),
      ('URL with token', 'GET https://x.example/a?token=abc123', 'abc123'),
      ('key in a form', 'request api_key=abc123xyz failed', 'abc123xyz'),
      ('app folder', 'open /data/user/13/app.beand/app_flutter/x', 'user/13'),
      ('Mac folder', 'open /Users/matthias/Documents/a.db', 'matthias'),
    ]) {
      test(name, () {
        expect(ConnectionLog.sanitize(input), isNot(contains(secret)));
      });
    }

    test('what helps finding a bug stays', () {
      for (final line in [
        'no status for 3400 ms',
        'connected meticulous.local',
        'at 14:05:22 planned',
        'MeticulousSocketService._connect (package:beand/a_b.dart:12:5)',
        'upload: HTTP 503 Server busy',
      ]) {
        expect(ConnectionLog.sanitize(line), line);
      }
    });

    test('public default servers keep their name, others do not', () {
      ConnectionLog.allowHosts(['wss://relay.primal.net']);
      expect(
        ConnectionLog.hostLabel('wss://relay.primal.net'),
        'relay.primal.net',
      );
      expect(ConnectionLog.hostLabel('ws://192.168.1.67:7777'), '<own server>');
      expect(
        ConnectionLog.sanitize('to wss://relay.primal.net/x'),
        'to wss://relay.primal.net',
      );
    });

    test('a parse error does not quote the data it choked on', () {
      ConnectionLog.failure(
        'import',
        const FormatException('Bad input', 'my secret bean notes'),
      );
      expect(logged.single, contains('Bad input'));
      expect(logged.single, isNot(contains('secret bean')));
    });
  });

  group('errors nothing caught', () {
    setUp(ConnectionLog.resetCrashes);

    test('are logged with where they happened', () {
      ConnectionLog.crash(
        StateError('boom'),
        StackTrace.fromString('#0 a\n#1 b'),
      );
      expect(logged.single, contains(' crash '));
      expect(logged.single, contains('boom'));
      expect(logged.single, contains('#0 a | #1 b'));
    });

    test('a widget failing on every frame is logged once', () {
      for (var i = 0; i < 20; i++) {
        ConnectionLog.crash(StateError('boom'), null);
      }
      expect(logged, hasLength(1));
      ConnectionLog.crash(StateError('other'), null);
      expect(logged, hasLength(2));
    });
  });

  testWidgets('it is reachable from About', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const AboutSettingsScreen()),
    );
    expect(find.text('Diagnostics log'), findsOneWidget);
  });

  testWidgets('empty log says so', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ConnectionLogScreen(load: () async => const []),
      ),
    );
    await tester.pump();
    expect(find.text('Nothing logged yet.'), findsOneWidget);
  });
}
