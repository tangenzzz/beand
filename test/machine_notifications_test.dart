import 'package:clock/clock.dart';
import 'package:beand/services/heating_snapshot.dart';
import 'package:beand/services/live_shot_service.dart';
import 'package:beand/services/machine_notifications.dart';
import 'package:beand/services/meticulous_socket_service.dart';
import 'package:beand/services/notification_settings.dart';
import 'package:flutter_test/flutter_test.dart';

// The machine's state set by hand: stage, stabilized and readings.
class FakeLive extends LiveShotService {
  final actions = <String>[];

  void set(ShotStage next, {bool? stable}) {
    stage = next;
    markExtracting(next == ShotStage.running);
    if (stable != null) stabilized = stable;
    notifyListeners();
  }

  void reading({required double weight, required double pressure}) {
    addReading(
      timeMs: 1000,
      pressure: pressure,
      flow: 2,
      weight: weight,
      stage: 'Percolation',
    );
    notifyListeners();
  }

  @override
  String get machineKey => 'meticulous';
  @override
  double? get targetTemperature => 90;
  @override
  void start() {}
  @override
  Future<bool> startShot() async {
    actions.add('start');
    return true;
  }

  @override
  Future<bool> stopShot() async {
    actions.add('stop');
    return true;
  }

  @override
  Future<bool> purge() async {
    actions.add('purge');
    return true;
  }
}

class FakeSink implements NotificationSink {
  final statuses = <StatusContent>[];
  final alerts = <MachineAlert>[];
  final alertTitles = <String>[];
  int permissionAsks = 0;
  bool hidden = false;

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return true;
  }

  @override
  Future<void> showStatus(StatusContent content) async {
    hidden = false;
    statuses.add(content);
  }

  @override
  Future<void> hideStatus() async => hidden = true;

  @override
  Future<void> alert(
    MachineAlert alert,
    String title,
    String body, {
    NotificationAction? action,
  }) async {
    alerts.add(alert);
    alertTitles.add('$title | $body');
  }
}

void main() {
  late MeticulousSocketService socket;
  late FakeLive live;
  late FakeSink sink;
  late NotificationSettings settings;
  late MachineNotifications notifications;

  setUp(() {
    HeatingSnapshot.instance.clear();
    socket = MeticulousSocketService(hostname: 'unreachable.local')
      ..connectionState = MachineConnectionState.connected;
    live = FakeLive();
    sink = FakeSink();
    settings = NotificationSettings();
    notifications = MachineNotifications(
      socket: socket,
      live: live,
      settings: settings,
      sink: sink,
      dose: () => 18,
    )..start();
  });

  tearDown(() => notifications.dispose());

  testWidgets('a full cycle: status from preheat on, each alert once', (
    tester,
  ) async {
    expect(sink.statuses, isEmpty, reason: 'idle: no status notification');

    live.set(ShotStage.heating);
    expect(sink.permissionAsks, 1);
    expect(sink.statuses.last.title, startsWith('Heating'));
    expect(sink.statuses.last.body, 'Heating up');

    // The hero ring's estimate counts down in the notification.
    HeatingSnapshot.instance.publishEta(218, clock.now());
    HeatingSnapshot.instance.progress = 0.62;
    await tester.pump(const Duration(seconds: 2));
    // Text only in minutes; the exact countdown is a clock Android runs
    // (and shows in the status bar chip from Android 16 on).
    expect(sink.statuses.last.body, 'Ready in about 4 min');
    expect(sink.statuses.last.progress, 0.62);
    expect(sink.statuses.last.countdownTo, HeatingSnapshot.instance.readyAt);

    live.set(ShotStage.ready);
    expect(sink.alerts, [MachineAlert.reached]);
    expect(sink.statuses.last.title, startsWith('Ready'));
    expect(sink.statuses.last.chip, 'Ready');
    expect(sink.statuses.last.countdownTo, isNull);

    live.set(ShotStage.ready, stable: true);
    expect(sink.alerts, [MachineAlert.reached, MachineAlert.stable]);
    expect(sink.statuses.last.title, 'Stable · ready to brew');
    expect(sink.statuses.last.chip, 'Stable');
    // The same again does not ring twice.
    live.set(ShotStage.ready, stable: true);
    expect(sink.alerts, hasLength(2));

    live.set(ShotStage.running, stable: false);
    live.reading(weight: 22.4, pressure: 8.9);
    await tester.pump(const Duration(seconds: 2));
    expect(sink.statuses.last.title, startsWith('Brewing'));
    expect(sink.statuses.last.body, '22.4 g · 8.9 bar');
    expect(sink.statuses.last.action, NotificationAction.stop);
    expect(sink.statuses.last.countUpFrom, isNotNull);
    expect(sink.statuses.last.countUpFrom, live.extractionStartedAt);

    live.reading(weight: 41.4, pressure: 0.5);
    live.set(ShotStage.awaitingPurge);
    expect(sink.alerts.last, MachineAlert.shotDone);
    expect(sink.alertTitles.last, contains('41.4 g'));
    expect(sink.alertTitles.last, contains('Ratio 1:2.3'));

    // Purging and back to idle: the status goes away.
    live.set(ShotStage.purging);
    expect(sink.hidden, isTrue);
    live.set(ShotStage.idle);

    // The next cycle may ring again.
    live.set(ShotStage.heating);
    live.set(ShotStage.ready);
    expect(sink.alerts.where((a) => a == MachineAlert.reached), hasLength(2));
    expect(sink.permissionAsks, 1, reason: 'asked only once');
    live.set(ShotStage.idle);
  });

  testWidgets('"only when the app is closed" holds alerts back in front', (
    tester,
  ) async {
    settings.setOnlyWhenClosed(true);
    notifications.inForeground = true;
    live.set(ShotStage.heating);
    live.set(ShotStage.ready);
    expect(sink.alerts, isEmpty);
    expect(sink.statuses, isNotEmpty, reason: 'the status shows anyway');

    notifications.inForeground = false;
    live.set(ShotStage.ready, stable: true);
    expect(sink.alerts, [MachineAlert.stable]);
    live.set(ShotStage.idle);
  });

  testWidgets('a single alert switched off stays quiet', (tester) async {
    settings.setAlert(MachineAlert.reached, false);
    live.set(ShotStage.heating);
    live.set(ShotStage.ready);
    expect(sink.alerts, isEmpty);
    live.set(ShotStage.idle);
  });

  testWidgets('switched off: no status, no alerts', (tester) async {
    settings.setEnabled(false);
    live.set(ShotStage.heating);
    live.set(ShotStage.ready);
    expect(sink.statuses, isEmpty);
    expect(sink.alerts, isEmpty);
    live.set(ShotStage.idle);
  });

  testWidgets('connection gone while heating: alert after a grace time', (
    tester,
  ) async {
    live.set(ShotStage.heating);
    socket.connectionState = MachineConnectionState.disconnected;
    socket.notifyListeners();
    await tester.pump(const Duration(seconds: 5));
    expect(sink.alerts, isEmpty, reason: 'a short drop is no alarm');
    await tester.pump(const Duration(seconds: 6));
    expect(sink.alerts, [MachineAlert.connectionLost]);

    // Back and gone again: reported anew.
    socket.connectionState = MachineConnectionState.connected;
    socket.notifyListeners();
    socket.connectionState = MachineConnectionState.disconnected;
    socket.notifyListeners();
    await tester.pump(const Duration(seconds: 11));
    expect(sink.alerts, hasLength(2));
    live.set(ShotStage.idle);
  });

  testWidgets('buttons act only where the app would offer them', (
    tester,
  ) async {
    live.set(ShotStage.heating);
    await notifications.handleAction(NotificationAction.startShot);
    expect(live.actions, isEmpty, reason: 'not ready yet');
    live.set(ShotStage.ready);
    await notifications.handleAction(NotificationAction.startShot);
    live.set(ShotStage.running);
    await notifications.handleAction(NotificationAction.stop);
    live.set(ShotStage.awaitingPurge);
    await notifications.handleAction(NotificationAction.purge);
    expect(live.actions, ['start', 'stop', 'purge']);
    live.set(ShotStage.idle);
  });
}
