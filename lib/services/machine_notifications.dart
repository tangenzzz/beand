import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'heating_estimator.dart';
import 'live_shot_service.dart';
import 'meticulous_socket_service.dart';
import 'notification_settings.dart';

// Notifications for the Meticulous (Settings → Notifications).
//
// From preheat until the shot is done a status notification stays up — like
// a music player's: "Heating 76° → 90° · about 3:38 left", "Ready",
// "Brewing · 18 s". It is a foreground service: only with it may the app
// keep its connection to the machine in the background; without, Android
// freezes the app soon after it is left and nothing would arrive. It goes
// away when the cycle ends, so it costs nothing the rest of the time.
//
// On top, single alerts with sound, each once per cycle: temperature
// reached (the machine's "click to start"), stable (all sensors in range,
// the hero's outer ring), shot done, and connection lost while heating or
// brewing.

/// What the status notification shows.
@immutable
class StatusContent {
  const StatusContent({
    required this.title,
    required this.body,
    this.progress,
    this.action,
    this.countdownTo,
    this.countUpFrom,
    this.chip,
  });

  final String title;
  final String body;

  /// 0…1 for the bar, null for none.
  final double? progress;
  final NotificationAction? action;

  /// A clock Android runs by itself: down to this moment (heating) or up
  /// from it (brewing). Shown in the notification and, from Android 16 on,
  /// in the status bar chip.
  final DateTime? countdownTo;
  final DateTime? countUpFrom;

  /// A short word for the chip when there is no clock ("Ready").
  final String? chip;

  @override
  bool operator ==(Object other) =>
      other is StatusContent &&
      other.title == title &&
      other.body == body &&
      other.progress == progress &&
      other.action == action &&
      other.countdownTo == countdownTo &&
      other.countUpFrom == countUpFrom &&
      other.chip == chip;

  @override
  int get hashCode => Object.hash(
    title,
    body,
    progress,
    action,
    countdownTo,
    countUpFrom,
    chip,
  );
}

/// Buttons on notifications; tapping one opens the app and does it there.
enum NotificationAction {
  startShot('start', 'Start shot'),
  stop('stop', 'Stop'),
  purge('purge', 'Purge');

  const NotificationAction(this.id, this.label);
  final String id;
  final String label;

  static NotificationAction? byId(String? id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// Where the notifications go — the platform, or a fake in tests.
abstract class NotificationSink {
  /// Asks for the permission where needed; false if refused.
  Future<bool> requestPermission();
  Future<void> showStatus(StatusContent content);
  Future<void> hideStatus();
  Future<void> alert(
    MachineAlert alert,
    String title,
    String body, {
    NotificationAction? action,
  });
}

class MachineNotifications {
  MachineNotifications({
    required this.socket,
    required this.live,
    required this.settings,
    required this.sink,
    required this.heating,
    this.dose,
    DateTime Function()? now,
    // `clock` looked up on every call, so a fake clock (tests) takes effect.
  }) : _now = now ?? (() => clock.now());

  final MeticulousSocketService socket;
  final LiveShotService live;
  final NotificationSettings settings;
  final NotificationSink sink;

  /// The hero's heating model — runs in the background too, so the ETA
  /// follows the real temperature while the app is closed.
  final HeatingEstimator heating;

  /// Dose of the current shot, for the ratio in "Shot done".
  final double? Function()? dose;
  final DateTime Function() _now;

  /// How long the connection may be gone before "Connection lost".
  static const connectionGrace = Duration(seconds: 10);

  /// The status notification changes at most this often.
  static const statusInterval = Duration(seconds: 1);

  /// Set from the app lifecycle: alerts can be limited to "app closed".
  bool inForeground = true;

  bool _statusShown = false;
  StatusContent? _lastStatus;
  DateTime? _lastStatusAt;
  bool _permissionAsked = false;

  ShotStage _stage = ShotStage.idle;
  bool _wasStable = false;
  final _sent = <MachineAlert>{};
  Timer? _connectionTimer;
  Timer? _statusTimer;

  static const _activeStages = {
    ShotStage.heating,
    ShotStage.ready,
    ShotStage.running,
    ShotStage.awaitingPurge,
  };

  void start() {
    live.addListener(_update);
    socket.addListener(_update);
    settings.addListener(_update);
    heating.addListener(_update);
    _update();
  }

  void dispose() {
    live.removeListener(_update);
    socket.removeListener(_update);
    settings.removeListener(_update);
    heating.removeListener(_update);
    _connectionTimer?.cancel();
    _statusTimer?.cancel();
  }

  bool get _active => settings.enabled && _activeStages.contains(live.stage);

  void _update() {
    final stage = live.stage;
    final previous = _stage;
    _stage = stage;

    // A new cycle: every alert may come once again.
    if (!_activeStages.contains(stage)) {
      _sent.clear();
      _wasStable = false;
    }

    if (_active && !_permissionAsked) {
      _permissionAsked = true;
      unawaited(sink.requestPermission());
    }

    if (previous == ShotStage.heating && stage == ShotStage.ready) {
      _send(MachineAlert.reached, 'Temperature reached', _readyBody());
    }
    final stable = live.stabilized;
    if (stable && !_wasStable && _activeStages.contains(stage)) {
      _send(
        MachineAlert.stable,
        'Stable · ready to brew',
        'All sensors in range',
        action: NotificationAction.startShot,
      );
    }
    _wasStable = stable;
    if (previous == ShotStage.running && stage == ShotStage.awaitingPurge) {
      _send(
        MachineAlert.shotDone,
        'Shot done · ${_shotSummary()}',
        _ratio() ?? 'Ready to purge',
        action: NotificationAction.purge,
      );
    }
    _watchConnection();
    _updateStatus();
  }

  void _send(
    MachineAlert alert,
    String title,
    String body, {
    NotificationAction? action,
  }) {
    if (_sent.contains(alert)) return;
    _sent.add(alert);
    if (!settings.wants(alert)) return;
    if (settings.onlyWhenClosed && inForeground) return;
    unawaited(sink.alert(alert, title, body, action: action));
  }

  void _watchConnection() {
    final connected =
        socket.connectionState == MachineConnectionState.connected;
    if (connected || !_active) {
      _connectionTimer?.cancel();
      _connectionTimer = null;
      // Back again: a later loss may be reported anew.
      if (connected) _sent.remove(MachineAlert.connectionLost);
      return;
    }
    _connectionTimer ??= Timer(connectionGrace, () {
      _connectionTimer = null;
      if (socket.connectionState != MachineConnectionState.connected &&
          _active) {
        _send(
          MachineAlert.connectionLost,
          'Machine connection lost',
          'Still heating? Check the machine',
        );
      }
    });
  }

  // ---- Status notification ----

  void _updateStatus() {
    if (!_active) {
      _statusTimer?.cancel();
      _statusTimer = null;
      if (_statusShown) {
        _statusShown = false;
        _lastStatus = null;
        unawaited(sink.hideStatus());
      }
      return;
    }
    // While heating, the countdown moves on even without new data.
    _statusTimer ??= Timer.periodic(statusInterval, (_) => _updateStatus());
    final content = statusContent();
    final now = _now();
    if (content == _lastStatus) return;
    final last = _lastStatusAt;
    if (_statusShown &&
        last != null &&
        now.difference(last) < statusInterval &&
        content.title == _lastStatus?.title) {
      return;
    }
    _lastStatus = content;
    _lastStatusAt = now;
    _statusShown = true;
    unawaited(sink.showStatus(content));
  }

  /// What the status notification says right now.
  @visibleForTesting
  StatusContent statusContent() {
    switch (live.stage) {
      case ShotStage.running:
        final last = live.liveReadings.isEmpty ? null : live.liveReadings.last;
        return StatusContent(
          title: 'Brewing',
          countUpFrom: live.extractionStartedAt,
          body: last == null
              ? 'Starting'
              : '${(last.weight ?? 0).toStringAsFixed(1)} g · '
                    '${(last.pressure ?? 0).toStringAsFixed(1)} bar',
          action: NotificationAction.stop,
        );
      case ShotStage.awaitingPurge:
        return StatusContent(
          title: 'Shot done · ${_shotSummary()}',
          body: 'Ready to purge',
          action: NotificationAction.purge,
          chip: 'Done',
        );
      case ShotStage.ready:
        return live.stabilized
            ? StatusContent(
                title: 'Stable · ready to brew',
                body: _profile() ?? 'All sensors in range',
                progress: 1,
                chip: 'Stable',
              )
            : StatusContent(
                title: 'Ready · ${_temp(_hero())}',
                body: 'Settling',
                progress: 1,
                chip: 'Ready',
              );
      case ShotStage.heating:
      case ShotStage.idle:
      case ShotStage.purging:
        final hero = _hero();
        final target = socket.targetTemperature;
        final heat = hero == null
            ? 'Heating'
            : target == null || socket.isPreheatActive
            ? 'Heating · ${_temp(hero)}'
            : 'Heating ${_temp(hero)} → ${_temp(target)}';
        final now = _now();
        final left = heating.remainingSeconds(now);
        final readyAt = heating.readyAt;
        final progress = heating.ringProgress;
        // The exact countdown runs in the clock; the text only in minutes,
        // so it does not change every second.
        return StatusContent(
          title: heat,
          body: left == null
              ? 'Heating up'
              : left < 60
              ? 'Ready in under a minute'
              : 'Ready in about ${(left / 60).ceil()} min',
          progress: progress > 0 ? progress : null,
          countdownTo: readyAt != null && readyAt.isAfter(now) ? readyAt : null,
          chip: hero == null ? null : _temp(hero),
        );
    }
  }

  double? _hero() {
    return heating.heroValue;
  }

  String? _profile() {
    final name = socket.latestStatus?.loadedProfile ?? '';
    return name.isEmpty ? null : name;
  }

  String _readyBody() {
    final target = socket.targetTemperature;
    final parts = [if (target != null) _temp(target), ?_profile()];
    return parts.isEmpty ? 'Ready to brew' : parts.join(' · ');
  }

  String _shotSummary() {
    final last = live.liveReadings.isEmpty ? null : live.liveReadings.last;
    final time = '${_seconds(live.elapsedExtractionMs)} s';
    final weight = last?.weight;
    return weight == null ? time : '$time · ${weight.toStringAsFixed(1)} g';
  }

  String? _ratio() {
    final d = dose?.call();
    final last = live.liveReadings.isEmpty ? null : live.liveReadings.last;
    final weight = last?.weight;
    if (d == null || d <= 0 || weight == null || weight <= 0) return null;
    return 'Ratio 1:${(weight / d).toStringAsFixed(1)}';
  }

  static String _seconds(int ms) => (ms / 1000).round().toString();
  static String _temp(double? v) => v == null ? '–' : '${v.round()}°';

  /// A button on a notification was tapped (the app is open by then).
  Future<void> handleAction(NotificationAction action) async {
    switch (action) {
      case NotificationAction.startShot:
        // Only where the app would offer it too: ready at the machine.
        if (live.stage == ShotStage.ready) await live.startShot();
      case NotificationAction.stop:
        if (live.stage == ShotStage.running) await live.stopShot();
      case NotificationAction.purge:
        if (live.stage == ShotStage.awaitingPurge) await live.purge();
    }
  }
}

/// The real notifications (flutter_local_notifications): a quiet channel
/// for the status, a loud one for the alerts.
class LocalNotificationSink implements NotificationSink {
  LocalNotificationSink([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _statusId = 7;
  static const _statusChannel = AndroidNotificationChannel(
    'beand_status',
    'Machine status',
    description: 'While heating and brewing',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );
  static const _alertChannel = AndroidNotificationChannel(
    'beand_alerts',
    'Machine alerts',
    description: 'Temperature reached, stable, shot done, connection lost',
    importance: Importance.high,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  // The status notification as a Live Update (android/…/LiveStatus.kt):
  // chip in the status bar from Android 16 on. The plugin starts the
  // foreground service; this channel then fills in the notification.
  static const _live = MethodChannel('beand/live_status');

  /// Sets up channels and the tap handler; [onAction] gets button taps.
  Future<void> init(void Function(NotificationAction action) onAction) async {
    // Buttons on the status notification come through LiveStatus: while
    // running as a call, after a cold start as the pending one.
    _live.setMethodCallHandler((call) async {
      if (call.method != 'action') return;
      final action = NotificationAction.byId(call.arguments as String?);
      if (action != null) onAction(action);
    });
    try {
      final pending = await _live.invokeMethod<String>('takeAction');
      final action = NotificationAction.byId(pending);
      if (action != null) onAction(action);
    } on MissingPluginException {
      // Not on Android.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_beand'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final action = NotificationAction.byId(response.actionId);
        if (action != null) onAction(action);
      },
    );
    await _android?.createNotificationChannel(_statusChannel);
    await _android?.createNotificationChannel(_alertChannel);
  }

  @override
  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? true;

  static List<AndroidNotificationAction>? _actions(NotificationAction? a) =>
      a == null
      ? null
      : [AndroidNotificationAction(a.id, a.label, showsUserInterface: true)];

  bool _serviceRunning = false;

  @override
  Future<void> showStatus(StatusContent content) async {
    final progress = content.progress;
    final details = AndroidNotificationDetails(
      _statusChannel.id,
      _statusChannel.name,
      channelDescription: _statusChannel.description,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: false,
      category: AndroidNotificationCategory.progress,
      showProgress: progress != null,
      maxProgress: 100,
      progress: ((progress ?? 0) * 100).round(),
      actions: _actions(content.action),
    );
    try {
      if (!_serviceRunning) {
        // Android only lets an app start this while it is in front; the
        // cycle normally starts with Preheat in the app.
        await _android?.startForegroundService(
          id: _statusId,
          title: content.title,
          body: content.body,
          notificationDetails: details,
          foregroundServiceTypes: {
            AndroidServiceForegroundType.foregroundServiceTypeConnectedDevice,
          },
        );
        _serviceRunning = true;
      }
      if (!await _showLive(content)) {
        await _plugin.show(
          id: _statusId,
          title: content.title,
          body: content.body,
          notificationDetails: NotificationDetails(android: details),
        );
      }
    } catch (e) {
      debugPrint('Status notification failed: $e');
    }
  }

  // Same id as the service's notification: replaces its content with the
  // Live Update version. False where LiveStatus is missing.
  Future<bool> _showLive(StatusContent c) async {
    final progress = c.progress;
    try {
      return await _live.invokeMethod<bool>('show', {
            'title': c.title,
            'body': c.body,
            'progress': progress == null ? null : (progress * 100).round(),
            'countdownTo': c.countdownTo?.millisecondsSinceEpoch,
            'countUpFrom': c.countUpFrom?.millisecondsSinceEpoch,
            'chip': c.chip,
            'actionId': c.action?.id,
            'actionLabel': c.action?.label,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('Live status failed: $e');
      return false;
    }
  }

  @override
  Future<void> hideStatus() async {
    try {
      if (_serviceRunning) await _android?.stopForegroundService();
      await _plugin.cancel(id: _statusId);
    } catch (e) {
      debugPrint('Hiding status notification failed: $e');
    }
    _serviceRunning = false;
  }

  @override
  Future<void> alert(
    MachineAlert alert,
    String title,
    String body, {
    NotificationAction? action,
  }) async {
    try {
      await _plugin.show(
        id: 10 + alert.index,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _alertChannel.id,
            _alertChannel.name,
            channelDescription: _alertChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            actions: _actions(action),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Alert notification failed: $e');
    }
  }
}

/// Feeds the app lifecycle into [MachineNotifications.inForeground].
class NotificationLifecycle {
  NotificationLifecycle(MachineNotifications notifications)
    : _listener = AppLifecycleListener(
        onStateChange: (state) =>
            notifications.inForeground = state == AppLifecycleState.resumed,
      );

  final AppLifecycleListener _listener;

  void dispose() => _listener.dispose();
}
