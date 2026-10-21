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
