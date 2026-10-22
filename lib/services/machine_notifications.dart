import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'connection_log.dart';
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
// On top, single alerts with sound, each once per cycle: preheat done
// (the machine's own preheat countdown ran out), temperature reached (the machine's "click to start"), stable (all sensors in range,
// the hero's outer ring), shot done, and connection lost while heating or
// brewing.
//
// iOS has no such service: the app stops a few seconds after it is left.
// There the status stays away, and leaving the app while heating plans
// "Temperature reached" ahead for when the heating model expects it —
// during a plain preheat "Preheat done" for when its countdown ends.

/// What the status notification shows.
@immutable
class StatusContent {
  const StatusContent({
    required this.title,
    required this.body,
    this.progress,
    this.action,
    this.chip,
  });

  final String title;
  final String body;

  /// 0…1 for the bar, null for none.
  final double? progress;
  final NotificationAction? action;

  /// What the status bar chip shows (Android 16+): the countdown while
  /// heating, a word or percentage after, the seconds while brewing. Kept
  /// short, Android cuts it after ~7 characters.
  final String? chip;

  @override
  bool operator ==(Object other) =>
      other is StatusContent &&
      other.title == title &&
      other.body == body &&
      other.progress == progress &&
      other.action == action &&
      other.chip == chip;

  @override
  int get hashCode => Object.hash(title, body, progress, action, chip);
}

/// Buttons on notifications. They act in the running app without opening
/// it (android/…/LiveStatus.kt); only if the app is not running any more
/// does a tap open it and act there.
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

  /// The app stops when it is left (iOS): alerts are then planned ahead.
  bool get plansAhead;

  /// Shows [alert] at [at] even if the app is not running any more.
  Future<void> planAlert(
    MachineAlert alert,
    DateTime at,
    String title,
    String body,
  );
  Future<void> cancelPlanned(MachineAlert alert);
}

class MachineNotifications {
  MachineNotifications({
    required this.socket,
    required this.live,
    required this.settings,
    required this.sink,
    required this.heating,
    this.dose,
    this.headline,
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

  /// The status notification's top line: profile and bean
  /// ("Damian's LRv2 · Guji"); null or empty: the machine's profile.
  final String? Function()? headline;
  final DateTime Function() _now;

  /// A planned "Should be ready" moves only for a bigger shift than this.
  static const replanThreshold = Duration(seconds: 15);

  /// How long the connection may be gone before "Connection lost".
  static const connectionGrace = Duration(seconds: 10);

  /// The status notification changes at most this often.
  static const statusInterval = Duration(seconds: 1);

  /// Set from the app lifecycle: alerts can be limited to "app closed".
  bool get inForeground => _inForeground;
  set inForeground(bool value) {
    if (value == _inForeground) return;
    _inForeground = value;
    _planReady();
    _planPreheat();
  }

  bool _inForeground = true;

  /// When the planned "Temperature reached" is due; null when none is.
  DateTime? _plannedAt;

  /// A running preheat's last countdown (seconds), null when none runs.
  double? _preheatLeft;
  Timer? _preheatTimer;

  /// When the planned "Preheat done" is due, and whether one already rang
  /// (then the real one stays away).
  DateTime? _preheatPlannedAt;
  bool _preheatRang = false;

  /// A preheat that stops with at most this much left ran out; more means
  /// it was cancelled (reset jumps straight from its count to 0).
  static const preheatDoneWithin = 3.0;

  bool _statusShown = false;
  StatusContent? _lastStatus;
  String? _lastStatusKind;
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
    _preheatTimer?.cancel();
  }

  bool get _active => settings.enabled && _activeStages.contains(live.stage);

  void _update() {
    final stage = live.stage;
    final previous = _stage;
    _stage = stage;
    // Left heating with a plan in place: settle it before the cycle's
    // alerts are cleared below.
    if (stage != ShotStage.heating) _planReady();

    // A new cycle: every alert may come once again.
    if (!_activeStages.contains(stage)) {
      _sent.clear();
      _wasStable = false;
    }

    if (_active && !_permissionAsked) {
      _permissionAsked = true;
      unawaited(
        sink.requestPermission().then(
          (ok) => ConnectionLog.write(
            'notify',
            ok ? 'permission granted' : 'permission refused',
          ),
        ),
      );
    }

    // Alerts: the moment and its numbers on top, below profile and bean —
    // the same line as on top of the status notification.
    final who = _who();
    if (previous == ShotStage.heating && stage == ShotStage.ready) {
      final target = socket.targetTemperature;
      _send(
        MachineAlert.reached,
        target == null
            ? 'Temperature reached'
            : 'Temperature reached · ${_temp(target)}',
        who ?? 'Ready to brew',
      );
    }
    // "Stable" as the hero ring shows it.
    final stable = heating.stabilized;
    if (stable && !_wasStable && _activeStages.contains(stage)) {
      _send(
        MachineAlert.stable,
        'Stable · ready to brew',
        who ?? 'All sensors in range',
        action: NotificationAction.startShot,
      );
    }
    _wasStable = stable;
    if (previous == ShotStage.running && stage == ShotStage.awaitingPurge) {
      _send(
        MachineAlert.shotDone,
        'Shot done · ${_shotSummary()}',
        [?_ratio(), ?who].join(' · ').ifEmpty('Ready to purge'),
        action: NotificationAction.purge,
      );
    }
    _watchConnection();
    _planReady();
    _watchPreheat();
    _updateStatus();
  }

  // A plain preheat runs while the machine says "idle"; only its countdown
  // (heater_status) shows it. A timer checks each second, since the count
  // also just stops coming (isPreheatActive goes stale without an event).
  void _watchPreheat() {
    final left = socket.preheatCountdownSeconds;
    if (socket.isPreheatActive && left != null && left > 0) {
      _preheatLeft = left;
      _preheatTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _watchPreheat(),
      );
      _planPreheat();
      return;
    }
    final last = _preheatLeft;
    if (last == null) return;
    _preheatLeft = null;
    _preheatTimer?.cancel();
    _preheatTimer = null;
    _planPreheat();
    final rang = _preheatRang;
    _preheatRang = false;
    if (last > preheatDoneWithin) {
      ConnectionLog.write(
        'notify',
        'preheat cancelled (${last.round()} s left)',
      );
      return;
    }
    if (rang) return;
    _sent.remove(MachineAlert.preheatDone);
    _send(MachineAlert.preheatDone, 'Preheat done', 'The machine is warmed up');
  }

  // iOS: "Preheat done" planned for the end of the countdown when the app
  // is left during a preheat — exact, the machine counts it itself. Comes
  // with the live status switch, like "Should be ready".
  void _planPreheat() {
    if (!sink.plansAhead) return;
    final left = _preheatLeft;
    final want =
        !_inForeground && settings.enabled && left != null && !_preheatRang;
    final planned = _preheatPlannedAt;
    if (want) {
      final at = _now().add(Duration(milliseconds: (left * 1000).round()));
      if (planned != null && planned.difference(at).abs() < replanThreshold) {
        return;
      }
      ConnectionLog.write(
        'notify',
        '"Preheat done" ${planned == null ? 'planned' : 'moved'} for '
            '${_hhmmss(at)} (in ${_clock(left)})',
      );
      _preheatPlannedAt = at;
      unawaited(
        sink.planAlert(
          MachineAlert.preheatDone,
          at,
          'Preheat done',
          'The machine is warmed up',
        ),
      );
      return;
    }
    if (planned == null) return;
    ConnectionLog.write(
      'notify',
      '"Preheat done" taken back '
          '(${_inForeground ? 'app in front' : 'preheat over'})',
    );
    _preheatPlannedAt = null;
    // Already shown: the real one would come twice.
    if (!planned.isAfter(_now())) _preheatRang = true;
    unawaited(sink.cancelPlanned(MachineAlert.preheatDone));
  }

  // Plans "Temperature reached" when the app is left while heating, and
  // takes it back once the app is in front again or heating is over.
  void _planReady() {
    if (!sink.plansAhead) return;
    final readyAt = heating.readyAt;
    final want =
        !_inForeground &&
        _active &&
        live.stage == ShotStage.heating &&
        readyAt != null &&
        // Stands in for the live status iOS cannot show: comes with that
        // switch, not with the (default off) alert of the same moment.
        !_sent.contains(MachineAlert.reached);
    final planned = _plannedAt;
    if (want) {
      // iOS leaves the app some seconds after it is left (AppDelegate asks
      // for them): a better estimate in that time replaces the plan.
      if (planned != null &&
          planned.difference(readyAt).abs() < replanThreshold) {
        return;
      }
      ConnectionLog.write(
        'notify',
        '"Should be ready" ${planned == null ? 'planned' : 'moved'} for '
            '${_hhmmss(readyAt)} (in ${_clock(readyAt.difference(_now()).inMilliseconds / 1000)})',
      );
      _plannedAt = readyAt;
      final target = socket.targetTemperature;
      unawaited(
        sink.planAlert(
          MachineAlert.reached,
          readyAt,
          target == null
              ? 'Should be ready'
              : 'Should be ready · ${_temp(target)}',
          _who() ?? 'Estimated while bean\'d was closed',
        ),
      );
      return;
    }
    if (planned == null) return;
    ConnectionLog.write(
      'notify',
      '"Should be ready" taken back (${_whyNot()})',
    );
    _plannedAt = null;
    // Already shown: the real one would come twice.
    if (!planned.isAfter(_now())) _sent.add(MachineAlert.reached);
    unawaited(sink.cancelPlanned(MachineAlert.reached));
  }

  void _send(
    MachineAlert alert,
    String title,
    String body, {
    NotificationAction? action,
  }) {
    if (_sent.contains(alert)) return;
    _sent.add(alert);
    // In the connection log, so a missing notification can be traced.
    if (!settings.wants(alert)) {
      ConnectionLog.write('notify', '${alert.name} skipped (switched off)');
      return;
    }
    if (settings.onlyWhenClosed && inForeground) {
      ConnectionLog.write('notify', '${alert.name} skipped (app in front)');
      return;
    }
    ConnectionLog.write('notify', '${alert.name} sent');
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
    // Numbers change at most once a second; a new state (Ready, Stable,
    // Brewing, …) shows at once.
    final kind = _statusKind();
    final last = _lastStatusAt;
    if (_statusShown &&
        last != null &&
        now.difference(last) < statusInterval &&
        kind == _lastStatusKind) {
      return;
    }
    _lastStatus = content;
    _lastStatusKind = kind;
    _lastStatusAt = now;
    _statusShown = true;
    unawaited(sink.showStatus(content));
  }

  /// What the status notification says right now: profile and bean on
  /// top, below the state with its numbers — exact to the second, so the
  /// notification is updated every second while active.
  @visibleForTesting
  StatusContent statusContent() {
    final title = _headline();
    switch (live.stage) {
      case ShotStage.running:
        final last = live.liveReadings.isEmpty ? null : live.liveReadings.last;
        final time = _clock(live.elapsedExtractionMs / 1000);
        return StatusContent(
          title: title,
          body: last == null
              ? 'Brewing · $time'
              : 'Brewing · $time · ${(last.weight ?? 0).toStringAsFixed(1)} g'
                    ' · ${(last.pressure ?? 0).toStringAsFixed(1)} bar',
          action: NotificationAction.stop,
          chip: time,
        );
      case ShotStage.awaitingPurge:
        return StatusContent(
          title: title,
          body: 'Shot done · ${_shotSummary()}',
          action: NotificationAction.purge,
          chip: 'Done',
        );
      case ShotStage.ready:
        // Ready → Stabilizing → Stable, as the hero ring says it; the bar
        // shows the outer ring's fill.
        if (heating.stabilized) {
          return StatusContent(
            title: title,
            body: 'Stable · ready to brew',
            progress: 1,
            chip: 'Stable',
          );
        }
        final fill = heating.stabilityProgress;
        final stabilizing = heating.stabilityShown && fill > 0.02;
        return StatusContent(
          title: title,
          body: stabilizing
              ? 'Stabilizing · ${_temp(_hero())}'
              : 'Ready · ${_temp(_hero())}',
          progress: stabilizing ? fill : 0,
          chip: stabilizing ? '${(fill * 100).round()}%' : 'Ready',
        );
      case ShotStage.heating:
      case ShotStage.idle:
      case ShotStage.purging:
        final hero = _hero();
        final target = socket.targetTemperature;
        final temps = hero == null
            ? null
            : target == null || socket.isPreheatActive
            ? _temp(hero)
            : '${_temp(hero)} → ${_temp(target)}';
        final left = heating.remainingSeconds(_now());
        final progress = heating.ringProgress;
        return StatusContent(
          title: title,
          body: [
            if (left != null) '${_clock(left)} left' else 'Heating',
            ?temps,
          ].join(' · '),
          progress: progress > 0 ? progress : null,
          chip: left != null ? _clock(left) : temps,
        );
    }
  }

  // Why no "Should be ready" is wanted now — for the connection log.
  String _whyNot() {
    if (_inForeground) return 'app in front';
    if (!settings.enabled) return 'live status off';
    if (live.stage != ShotStage.heating) return 'stage ${live.stage.name}';
    if (heating.readyAt == null) return 'no estimate';
    return 'already rang';
  }

  static String _hhmmss(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
      ':${t.second.toString().padLeft(2, '0')}';

  // Which state the status shows, without its numbers.
  String _statusKind() {
    final stabilizing =
        heating.stabilityShown && heating.stabilityProgress > 0.02;
    return '${live.stage.name}/${heating.stabilized}/$stabilizing';
  }

  String _headline() => _who() ?? "bean'd";

  static String _clock(double seconds) {
    final total = seconds.round();
    final m = total ~/ 60, s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  double? _hero() {
    return heating.heroValue;
  }

  String? _profile() {
    final name = socket.latestStatus?.loadedProfile ?? '';
    return name.isEmpty ? null : name;
  }

  // Profile and bean, or null when neither is known.
  String? _who() {
    final text = headline?.call()?.trim() ?? '';
    if (text.isNotEmpty) return text;
    return _profile();
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

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  // iOS: one category per button; "foreground" opens the app, which then
  // acts (onDidReceiveNotificationResponse).
  static final _darwinCategories = [
    for (final a in NotificationAction.values)
      DarwinNotificationCategory(
        'beand_${a.id}',
        actions: [
          DarwinNotificationAction.plain(
            a.id,
            a.label,
            options: {DarwinNotificationActionOption.foreground},
          ),
        ],
      ),
  ];

  static DarwinNotificationDetails _darwin(NotificationAction? a) =>
      DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
        categoryIdentifier: a == null ? null : 'beand_${a.id}',
      );

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
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_stat_beand'),
        // Asked once a cycle starts (requestPermission), not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
          notificationCategories: _darwinCategories,
        ),
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
  Future<bool> requestPermission() async {
    final ios = _ios;
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    return await _android?.requestNotificationsPermission() ?? true;
  }

  @override
  bool get plansAhead => Platform.isIOS;

  @override
  Future<void> planAlert(
    MachineAlert alert,
    DateTime at,
    String title,
    String body,
  ) async {
    try {
      await _plugin.zonedSchedule(
        id: 10 + alert.index,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: NotificationDetails(iOS: _darwin(null)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      final pending = await _plugin.pendingNotificationRequests();
      ConnectionLog.write('notify', 'iOS holds ${pending.length} planned');
    } catch (e) {
      ConnectionLog.write('notify', 'planning failed: $e');
    }
  }

  @override
  Future<void> cancelPlanned(MachineAlert alert) async {
    try {
      await _plugin.cancel(id: 10 + alert.index);
    } catch (e) {
      debugPrint('Cancelling planned alert failed: $e');
    }
  }

  static List<AndroidNotificationAction>? _actions(NotificationAction? a) =>
      a == null
      ? null
      : [AndroidNotificationAction(a.id, a.label, showsUserInterface: true)];

  bool _serviceRunning = false;

  @override
  Future<void> showStatus(StatusContent content) async {
    // iOS has no lasting notification (and no service to keep it up).
    if (Platform.isIOS) return;
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
    if (Platform.isIOS) return;
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
    // Through LiveStatus, so the button acts directly; the plugin only
    // where that is missing.
    try {
      final shown = await _live.invokeMethod<bool>('alert', {
        'id': 10 + alert.index,
        'title': title,
        'body': body,
        'actionId': action?.id,
        'actionLabel': action?.label,
      });
      if (shown ?? false) return;
    } on MissingPluginException {
      // Not on Android: below.
    } on PlatformException catch (e) {
      debugPrint('Live alert failed: $e');
    }
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
          iOS: _darwin(action),
        ),
      );
    } catch (e) {
      ConnectionLog.write('notify', 'alert failed: $e');
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

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
