import 'package:beand/services/meticulous_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Bug 2026-10-18: after leaving the app and purging on the machine, the
// Purge button kept pulsing on return — Android had cut the link while the
// app was in the background, the socket still counted as connected, and
// the last status stayed. The machine sends `status` every ~0.1 s, so a
// connected socket without one for longer than [staleAfter] gets rebuilt.
void main() {
  final t0 = DateTime(2026, 10, 18, 9);

  test('connected, but no status for longer than 3 s: stale', () {
    final s = MeticulousSocketService(hostname: 'unreachable.local')
      ..connectionState = MachineConnectionState.connected
      ..markStatusReceived(t0);
    expect(s.isStale(t0.add(const Duration(seconds: 2))), isFalse);
    expect(s.isStale(t0.add(const Duration(seconds: 4))), isTrue);
    s.dispose();
  });

  test('not stale without a connection or before the first status', () {
    final s = MeticulousSocketService(hostname: 'unreachable.local');
    s.connectionState = MachineConnectionState.disconnected;
    s.markStatusReceived(t0);
    expect(s.isStale(t0.add(const Duration(minutes: 1))), isFalse);

    // Freshly (re)connected: waits for the first status instead of
    // reconnecting in a loop.
    final fresh = MeticulousSocketService(hostname: 'unreachable.local')
      ..connectionState = MachineConnectionState.connected;
    expect(fresh.isStale(t0.add(const Duration(minutes: 1))), isFalse);
    s.dispose();
    fresh.dispose();
  });
}
