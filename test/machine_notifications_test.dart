import 'package:clock/clock.dart';
import 'package:beand/services/heating_estimator.dart';
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

  @override
  bool plansAhead = false;
  final planned = <MachineAlert, DateTime>{};
  final plannedTitles = <String>[];

  @override
  Future<void> planAlert(
    MachineAlert alert,
    DateTime at,
    String title,
    String body,
  ) async {
    planned[alert] = at;
    plannedTitles.add('$title | $body');
  }

  @override
  Future<void> cancelPlanned(MachineAlert alert) async => planned.remove(alert);
}

void main() {
  late MeticulousSocketService socket;
  late FakeLive live;
  late FakeSink sink;
  late NotificationSettings settings;
  late HeatingEstimator heating;
  late MachineNotifications notifications;

  setUp(() {
    socket = MeticulousSocketService(hostname: 'unreachable.local')
      ..connectionState = MachineConnectionState.connected;
    live = FakeLive();
    sink = FakeSink();
    // All alerts on here; the default (off) has its own test below.
    settings = NotificationSettings(alerts: MachineAlert.values.toSet());
    // Not started: the test sets its results by hand.
    heating = HeatingEstimator(socket);
    notifications = MachineNotifications(
      socket: socket,
      live: live,
      settings: settings,
      sink: sink,
      heating: heating,
      dose: () => 18,
    )..start();
  });

  // "Stable" comes from the heating model, as in the hero ring.
  void stable(bool value) {
    heating.stabilized = value;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    heating.notifyListeners();
  }

  tearDown(() {
    notifications.dispose();
    heating.dispose();
  });

  testWidgets('a full cycle: status from preheat on, each alert once', (
    tester,
  ) async {
    expect(sink.statuses, isEmpty, reason: 'idle: no status notification');

    live.set(ShotStage.heating);
    expect(sink.permissionAsks, 1);
    // Top line: profile and bean (here the fallback, no profile known).
    expect(sink.statuses.last.title, "bean'd");
    expect(sink.statuses.last.body, 'Heating');

    // The heating model's estimate, exact to the second, counted down.
    heating
      ..etaSeconds = 218
      ..etaAt = clock.now()
      ..ringProgress = 0.62;
    await tester.pump(const Duration(seconds: 2));
    expect(sink.statuses.last.body, '3:36 left');
    expect(sink.statuses.last.chip, '3:36');
    expect(sink.statuses.last.progress, 0.62);
    await tester.pump(const Duration(seconds: 1));
    expect(sink.statuses.last.body, '3:35 left', reason: 'every second');

    live.set(ShotStage.ready);
    expect(sink.alerts, [MachineAlert.reached]);
    expect(sink.statuses.last.body, startsWith('Ready'));
    expect(sink.statuses.last.chip, 'Ready');

    // Stabilizing: the bar shows the outer ring's fill.
    heating
      ..stabilityShown = true
      ..stabilityProgress = 0.5;
    stable(false);
    await tester.pump(const Duration(seconds: 1));
    expect(sink.statuses.last.body, startsWith('Stabilizing'));
    expect(sink.statuses.last.progress, 0.5);
    expect(sink.statuses.last.chip, '50%');

    stable(true);
    expect(sink.alerts, [MachineAlert.reached, MachineAlert.stable]);
    await tester.pump(const Duration(seconds: 1));
    expect(sink.statuses.last.body, 'Stable · ready to brew');
    expect(sink.statuses.last.chip, 'Stable');
    // The same again does not ring twice.
    stable(true);
    expect(sink.alerts, hasLength(2));

    stable(false);
    heating.stabilityShown = false;
    live.set(ShotStage.running);
    live.reading(weight: 22.4, pressure: 8.9);
    await tester.pump(const Duration(seconds: 2));
    expect(sink.statuses.last.body, startsWith('Brewing · 0:0'));
    expect(sink.statuses.last.body, endsWith('22.4 g · 8.9 bar'));
    expect(sink.statuses.last.action, NotificationAction.stop);

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
    stable(true);
    expect(sink.alerts, [MachineAlert.stable]);
    live.set(ShotStage.idle);
  });

  testWidgets('leaving the app while heating plans "reached" ahead (iOS)', (
    tester,
  ) async {
    sink.plansAhead = true;
    socket.targetTemperature = 90;
    final readyAt = clock.now().add(const Duration(minutes: 3));
    heating
      ..etaSeconds = 180
      ..etaAt = clock.now();
    live.set(ShotStage.heating);
    expect(sink.planned, isEmpty, reason: 'the app is in front');

    notifications.inForeground = false;
    expect(sink.planned[MachineAlert.reached], readyAt);
    expect(sink.plannedTitles.single, startsWith('Should be ready · 90°'));

    notifications.inForeground = true;
    expect(sink.planned, isEmpty, reason: 'back in front: taken back');

    // Ready while still away: the plan goes, the real alert comes.
    notifications.inForeground = false;
    live.set(ShotStage.ready);
    expect(sink.planned, isEmpty);
    expect(sink.alerts, [MachineAlert.reached]);
    live.set(ShotStage.idle);
  });

  testWidgets('a planned "reached" already shown is not sent twice', (
    tester,
  ) async {
    sink.plansAhead = true;
    var now = DateTime(2026, 10, 22, 8);
    notifications.dispose();
    notifications = MachineNotifications(
      socket: socket,
      live: live,
      settings: settings,
      sink: sink,
      heating: heating,
      now: () => now,
    )..start();
    heating
      ..etaSeconds = 60
      ..etaAt = now;
    live.set(ShotStage.heating);
    notifications.inForeground = false;
    expect(sink.planned, hasLength(1));

    now = now.add(const Duration(minutes: 2));
    notifications.inForeground = true;
    live.set(ShotStage.ready);
    expect(sink.alerts, isEmpty, reason: 'the planned one already rang');
    live.set(ShotStage.idle);
  });

  testWidgets('a better estimate before iOS stops the app moves the plan', (
    tester,
  ) async {
    sink.plansAhead = true;
    final start = clock.now();
    heating
      ..etaSeconds = 300
      ..etaAt = start;
    live.set(ShotStage.heating);
    notifications.inForeground = false;
    expect(sink.planned[MachineAlert.reached], start.add(_s(300)));

    // A few seconds off: left as it is.
    heating.etaSeconds = 290;
    live.set(ShotStage.heating);
    expect(sink.planned[MachineAlert.reached], start.add(_s(300)));

    heating.etaSeconds = 200;
    live.set(ShotStage.heating);
    expect(sink.planned[MachineAlert.reached], start.add(_s(200)));
    live.set(ShotStage.idle);
  });

  testWidgets('the plan comes with the live status, alerts off', (
    tester,
  ) async {
    sink.plansAhead = true;
    settings.alerts.clear();
    heating
      ..etaSeconds = 180
      ..etaAt = clock.now();
    live.set(ShotStage.heating);
    notifications.inForeground = false;
    expect(sink.planned, hasLength(1));

    notifications.inForeground = true;
    settings.setEnabled(false);
    notifications.inForeground = false;
    expect(sink.planned, isEmpty, reason: 'live status off: nothing');
    live.set(ShotStage.idle);
  });

  testWidgets('Android plans nothing ahead', (tester) async {
    heating
      ..etaSeconds = 180
      ..etaAt = clock.now();
    live.set(ShotStage.heating);
    notifications.inForeground = false;
    expect(sink.planned, isEmpty);
    live.set(ShotStage.idle);
  });

  testWidgets('alerts and status name profile and bean', (tester) async {
    notifications.dispose();
    notifications = MachineNotifications(
      socket: socket,
      live: live,
      settings: settings,
      sink: sink,
      heating: heating,
      dose: () => 18,
      headline: () => 'Classic · Guji',
    )..start();
    socket.targetTemperature = 90;
    live.set(ShotStage.heating);
    expect(sink.statuses.last.title, 'Classic · Guji');
    live.set(ShotStage.ready);
    expect(sink.alertTitles.last, 'Temperature reached · 90° | Classic · Guji');
    stable(true);
    expect(sink.alertTitles.last, 'Stable · ready to brew | Classic · Guji');
    stable(false);
    live.set(ShotStage.running);
    live.reading(weight: 36, pressure: 1);
    live.set(ShotStage.awaitingPurge);
    expect(sink.alertTitles.last, endsWith('| Ratio 1:2.0 · Classic · Guji'));
    live.set(ShotStage.idle);
  });

  testWidgets('by default only the live status, no alerts', (tester) async {
    expect(NotificationSettings().alerts, isEmpty);
    settings.alerts.clear();
    live.set(ShotStage.heating);
    live.set(ShotStage.ready);
    stable(true);
    expect(sink.alerts, isEmpty);
    expect(sink.statuses, isNotEmpty);
    stable(false);
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

Duration _s(int seconds) => Duration(seconds: seconds);
