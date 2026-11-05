import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/connection_log.dart';
import 'acaia_driver.dart';
import 'acaia_protocol.dart' show hexPacket;
import 'bookoo_driver.dart';
import 'brew_scale.dart';
import 'decent_driver.dart';
import 'scale_driver.dart';

const scaleLastDeviceIdPrefKey = 'scale.lastDeviceId';
const scaleLastDeviceNamePrefKey = 'scale.lastDeviceName';
const scaleKnownPrefKey = 'scale.known';

void _log(String message) {
  debugPrint('BleScale: $message');
  ConnectionLog.write('scale', message);
}

/// A Bluetooth scale via flutter_reactive_ble: scan, connect, reconnect and
/// permissions are the same for every scale; what a scale speaks is in its
/// [ScaleDriver] — Acaia (Lunar/Pearl, old and new firmware), Decent and
/// Bookoo — picked by the name it advertises. Until 2026-10-21 this was
/// AcaiaScale; the Acaia steps moved unchanged into AcaiaDriver.
class BleScale extends BrewScale {
  BleScale({FlutterReactiveBle? ble, List<ScaleDriver>? drivers})
    : _ble = ble ?? FlutterReactiveBle(),
      _drivers = drivers ?? [AcaiaDriver(), DecentDriver(), BookooDriver()] {
    unawaited(_loadRemembered());
  }

  final FlutterReactiveBle _ble;
  final List<ScaleDriver> _drivers;

  /// The driver for the connected (or connecting) scale.
  ScaleDriver? _driver;

  ScaleDriver? _driverFor(String? name) {
    if (name == null) return null;
    for (final d in _drivers) {
      if (d.matches(name)) return d;
    }
    return null;
  }

  @override
  String? get details => isConnected ? _driver?.details : null;

  static const _scanTimeout = Duration(seconds: 15);
  static const _connectTimeout = Duration(seconds: 10);

  /// How long the app searches for a lost scale before giving up.
  static const _reconnectWindow = Duration(minutes: 2);
  static const _keepPackets = 30;

  ScaleConnection _connection = ScaleConnection.disconnected;
  @override
  ScaleConnection get connection => _connection;

  String? _deviceName;
  @override
  String? get deviceName => _deviceName;

  String? _rememberedId;
  @override
  String? get rememberedId => _rememberedId;

  double? _grams;
  @override
  double? get grams => _grams;

  String? _error;
  @override
  String? get error => _error;

  int? _battery;
  @override
  int? get batteryPercent => isConnected ? _battery : null;
  Timer? _batteryTimer;

  final _packets = <String>[];
  @override
  List<String> get recentPackets => List.unmodifiable(_packets);

  int _packetCount = 0;

  final _readings = StreamController<ScaleReading>.broadcast();
  @override
  Stream<ScaleReading> get readings => _readings.stream;

  String? _deviceId;
  Characteristic? _writeChar;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  Timer? _heartbeat;
  Timer? _watchdog;
  // The connection attempt hasn't answered yet (see _teardown).
  bool _connPending = false;
  // Attempts given up on that are still running: their end, by scale.
  final _abandoned = <String, Future<void>>{};
  DateTime? _lastPacket;
  bool _wantConnected = false;
  int _reconnects = 0;
  Completer<void>? _connecting;

  // Every disconnect / switch to another scale starts a new session. A
  // reconnect loop or connection attempt of an older session stops instead
  // of reaching for the new scale (bug 2026-11-04: Decent off, Acaia on —
  // the Decent's loop kept running and nothing connected any more).
  int _session = 0;

  // The pending "connected and set up" of _open(); _teardown() ends it, so
  // a cancelled attempt never hangs (it used to block every later connect
  // until the app restarted).
  Completer<void>? _ready;

  List<KnownScale> _known = const [];
  @override
  List<KnownScale> get knownScales => _known;

  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    _rememberedId = prefs.getString(scaleLastDeviceIdPrefKey);
    final name = prefs.getString(scaleLastDeviceNamePrefKey);
    _deviceName ??= name;
    var known = const <KnownScale>[];
    try {
      final raw = prefs.getString(scaleKnownPrefKey);
      if (raw != null) {
        known = [
          for (final e in jsonDecode(raw) as List) ?KnownScale.fromJson(e),
        ];
      }
    } catch (e) {
      debugPrint('BleScale: known scales unreadable: $e');
    }
    // Keep what was added meanwhile; the scale of older versions counts too.
    final id = _rememberedId;
    final merged = [
      ...known,
      for (final k in _known)
        if (!known.any((e) => e.id == k.id)) k,
    ];
    _known = [
      ...merged,
      if (id != null && name != null && !merged.any((e) => e.id == id))
        KnownScale(id: id, name: name),
    ];
    notifyListeners();
  }

  Future<void> _saveKnown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      scaleKnownPrefKey,
      jsonEncode([for (final k in _known) k.toJson()]),
    );
  }

  void _addKnown(String id, String name) {
    if (_known.any((k) => k.id == id)) return;
    _known = [..._known, KnownScale(id: id, name: name)];
    unawaited(_saveKnown());
  }

  String? get _customName {
    final id = _deviceId ?? _rememberedId;
    return _known.where((k) => k.id == id).firstOrNull?.customName;
  }

  @override
  String? get displayName => _customName ?? _deviceName;

  @override
  String get shortName => _customName ?? scaleShortName(_deviceName);

  @override
  Future<void> renameScale(String id, String name) async {
    final clean = name.trim();
    _known = [
      for (final k in _known)
        if (k.id == id) k.renamed(clean.isEmpty ? null : clean) else k,
    ];
    notifyListeners();
    await _saveKnown();
  }

  @override
  Future<void> forgetScale(String id) async {
    _known = [
      for (final k in _known)
        if (k.id != id) k,
    ];
    if (id == _rememberedId) {
      await forget();
    } else {
      notifyListeners();
    }
    await _saveKnown();
  }

  Future<void> _remember(String id, String name) async {
    _rememberedId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(scaleLastDeviceIdPrefKey, id);
    await prefs.setString(scaleLastDeviceNamePrefKey, name);
  }

  // ---- Scan -----------------------------------------------------------

  // There is one radio scan: everyone asking for a scan (the settings page,
  // finding a scale, a reconnect) shares it. On Android a second scan silently
  // ends the first, and a scan ending stops it for everyone.
  StreamSubscription<DiscoveredDevice>? _radioScan;
  final _scanListeners = <StreamController<DiscoveredDevice>>{};
  final _seenInScan = <String, DiscoveredDevice>{};
  Timer? _scanStartTimer;

  // Android answers more than 5 scan starts in 30 s with an empty scan and no
  // error. Stay below that: the next start waits instead.
  final _scanStarts = <DateTime>[];
  static const _maxScanStarts = 4;
  static const _scanStartWindow = Duration(seconds: 30);

  @override
  Stream<ScaleCandidate> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    await _ensurePermissions();
    await _waitForBluetooth();
    final out = StreamController<DiscoveredDevice>();
    _scanListeners.add(out);
    final wait = _startRadioScan();
    // Long enough to really search when the start has to wait.
    final end = Timer(timeout + wait, out.close);
    final seen = <String>{};
    for (final d in _seenInScan.values) {
      out.add(d);
    }
    try {
      yield* out.stream
          .where((d) => _driverFor(d.name) != null && seen.add(d.id))
          .map((d) => ScaleCandidate(id: d.id, name: d.name, rssi: d.rssi));
    } finally {
      end.cancel();
      _scanListeners.remove(out);
      if (_scanListeners.isEmpty) _stopRadioScan();
    }
  }

  // Returns how long until the scan really runs.
  Duration _startRadioScan() {
    if (_radioScan != null) return Duration.zero;
    if (_scanStartTimer case final t? when t.isActive) {
      return _nextScanStart();
    }
    final wait = _nextScanStart();
    if (wait > Duration.zero) {
      _log('scan waits ${wait.inSeconds}s (too many scans)');
      _scanStartTimer = Timer(wait, () {
        if (_scanListeners.isNotEmpty) _startRadioScan();
      });
      return wait;
    }
    _scanStarts.add(DateTime.now());
    _seenInScan.clear();
    _log('scan started');
    _radioScan = _scanStream().listen(
      (d) {
        _seenInScan[d.id] = d;
        for (final l in _scanListeners.toList()) {
          if (!l.isClosed) l.add(d);
        }
      },
      onError: (Object e) {
        _log('scan failed: $e');
        _radioScan = null;
        for (final l in _scanListeners.toList()) {
          if (!l.isClosed) {
            l.addError(e);
            l.close();
          }
        }
      },
      onDone: () {
        _radioScan = null;
      },
    );
    return Duration.zero;
  }

  Duration _nextScanStart() {
    final now = DateTime.now();
    _scanStarts.removeWhere((t) => now.difference(t) >= _scanStartWindow);
    if (_scanStarts.length < _maxScanStarts) return Duration.zero;
    return _scanStartWindow - now.difference(_scanStarts.first);
  }

  void _stopRadioScan() {
    _scanStartTimer?.cancel();
    _scanStartTimer = null;
    final running = _radioScan;
    _radioScan = null;
    _seenInScan.clear();
    if (running != null) {
      _log('scan stopped');
      unawaited(running.cancel());
    }
  }

  Stream<DiscoveredDevice> _scanStream({bool askedForLocation = false}) async* {
    try {
      yield* _ble.scanForDevices(
        withServices: const [],
        scanMode: ScanMode.lowLatency,
        requireLocationServicesEnabled: false,
      );
    } catch (e) {
      // Android ≤ 11: scanning without location permission fails.
      if (!askedForLocation &&
          Platform.isAndroid &&
          e.toString().toLowerCase().contains('location')) {
        if (await Permission.locationWhenInUse.request().isGranted) {
          yield* _scanStream(askedForLocation: true);
          return;
        }
        throw const _ScaleException(
          'Location permission is needed to find the scale.',
        );
      }
      rethrow;
    }
  }

  // ---- Connect --------------------------------------------------------

  @override
  Future<void> connect() => _connectWith(null);

  /// Tapping another scale switches right over, whatever the app is doing.
  @override
  Future<void> connectTo(ScaleCandidate candidate) async {
    if (_deviceId == candidate.id && _connection == ScaleConnection.connected) {
      return;
    }
    // Tapped again while this was still dropping the old one: the last tap
    // counts.
    final mine = _session + 1;
    await disconnect();
    if (mine != _session) return;
    return _connectWith(candidate);
  }

  Future<void> _connectWith(ScaleCandidate? pick) async {
    if (_connection == ScaleConnection.connected) return;
    if (_connecting != null) return _connecting!.future;
    final done = _connecting = Completer<void>();
    // Also ends the reconnect loop of whatever came before.
    final session = ++_session;
    bool current() => session == _session;
    _wantConnected = true;
    _reconnects = 0;
    _error = null;
    try {
      await _ensurePermissions();
      await _waitForBluetooth();
      if (!current()) return;
      var target = pick;
      if (target == null) {
        _set(ScaleConnection.scanning);
        target = await _findForConnect();
        if (!current()) return;
      }
      if (target == null) {
        _fail(
          'No scale found. Is it on and free? A scale takes one connection — another phone or app may hold it.',
        );
        return;
      }
      _deviceId = target.id;
      _deviceName = target.name;
      await _remember(target.id, target.name);
      if (!current()) return;
      _log('connecting to ${target.name}');
      // Android often fails the first try right after a scan or another
      // scale's connection (GATT error 133): worth a second one.
      for (var attempt = 1; ; attempt++) {
        try {
          await _open();
          break;
        } catch (e) {
          _log('connect attempt $attempt failed: $e');
          if (!current() || attempt >= 2) rethrow;
          await _teardown();
          await Future<void>.delayed(const Duration(seconds: 1));
          if (!current()) return;
        }
      }
    } catch (e) {
      // An attempt that was cancelled has nothing to say: the app has moved
      // on, and failing here would end the new scale's connection.
      if (current()) {
        _log('connect failed: $e');
        _fail(_describe(e));
      }
    } finally {
      if (identical(_connecting, done)) _connecting = null;
      if (!done.isCompleted) done.complete();
    }
  }

  /// The remembered scale takes precedence; we take another one if the
  /// known one doesn't show up within 2 s.
  Future<ScaleCandidate?> _findForConnect() async {
    await _loadRemembered();
    final lastId = _rememberedId;
    ScaleCandidate? firstOther;
    final found = _finding = Completer<ScaleCandidate?>();
    Timer? grace;
    final sub = scan(timeout: _scanTimeout).listen(
      (c) {
        if (found.isCompleted) return;
        if (lastId == null || c.id == lastId) {
          found.complete(c);
        } else if (firstOther == null) {
          firstOther = c;
          grace = Timer(const Duration(seconds: 2), () {
            if (!found.isCompleted) found.complete(firstOther);
          });
        }
      },
      onError: (Object e) {
        if (!found.isCompleted) found.completeError(e);
      },
      onDone: () {
        if (!found.isCompleted) found.complete(firstOther);
      },
    );
    try {
      return await found.future;
    } finally {
      if (identical(_finding, found)) _finding = null;
      grace?.cancel();
      await sub.cancel();
    }
  }

  // The search of a connect() in progress; a disconnect ends it right away.
  Completer<ScaleCandidate?>? _finding;

  @override
  Future<void> disconnect() async {
    _wantConnected = false;
    _session++;
    // An attempt still under way ends by itself; nothing may wait for it.
    _connecting = null;
    final finding = _finding;
    if (finding != null && !finding.isCompleted) finding.complete(null);
    final session = _session;
    await _teardown();
    if (session == _session) _set(ScaleConnection.disconnected);
  }

  @override
  Future<void> forget() async {
    await disconnect();
    final id = _rememberedId;
    _rememberedId = null;
    _deviceId = null;
    _deviceName = null;
    _error = null;
    _known = [
      for (final k in _known)
        if (k.id != id) k,
    ];
    final prefs = await SharedPreferences.getInstance();
    await _saveKnown();
    await prefs.remove(scaleLastDeviceIdPrefKey);
    await prefs.remove(scaleLastDeviceNamePrefKey);
    notifyListeners();
  }

  @override
  Future<void> tare() => _send(_driver?.tare);

  // Whether the scale's timer runs, for its start/stop button.
  bool _timerRunning = false;

  @override
  Future<void> startTimer() {
    _timerRunning = true;
    return _send(_driver?.startTimer);
  }

  @override
  Future<void> stopTimer() {
    _timerRunning = false;
    return _send(_driver?.stopTimer);
  }

  @override
  Future<void> resetTimer() {
    _timerRunning = false;
    return _send(_driver?.resetTimer);
  }

  // One command may be several writes (see ScaleDriver.tare).
  Future<void> _send(List<Uint8List>? writes) async {
    final driver = _driver;
    if (driver == null || writes == null) return;
    for (var i = 0; i < writes.length; i++) {
      if (i > 0) await Future<void>.delayed(driver.repeatGap);
      await _write(writes[i]);
    }
  }

  // ---------------------------------------------------------------------

  Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid) return;
    // On Android 11 and older permission_handler reports "granted" for
    // SCAN/CONNECT anyway; there the scan needs location instead
    // (see _scanStream).
    // Only ask when it's needed: two requests at the same time throw, and a
    // scan and a reconnect can come together.
    if (await Permission.bluetoothScan.isGranted &&
        await Permission.bluetoothConnect.isGranted) {
      return;
    }
    final res = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    if (res.values.any((s) => !s.isGranted)) {
      throw const _ScaleException(
        'Bluetooth permission denied. Allow "Nearby devices" for bean\'d.',
      );
    }
  }

  static const _bluetoothChannel = MethodChannel('beand/bluetooth');

  Future<BleStatus> _status() => _ble.statusStream
      .firstWhere((s) => s != BleStatus.unknown)
      .timeout(const Duration(seconds: 3), onTimeout: () => BleStatus.unknown);

  @override
  Future<bool> get bluetoothOff async {
    try {
      return await _status() == BleStatus.poweredOff;
    } catch (e) {
      debugPrint('BleScale: Bluetooth status failed: $e');
      return false;
    }
  }

  @override
  Stream<bool> get bluetoothOffChanges => _ble.statusStream
      .where((s) => s != BleStatus.unknown)
      .map((s) => s == BleStatus.poweredOff)
      .distinct();

  @override
  Future<bool> requestBluetoothOn() async {
    if (!await bluetoothOff) return true;
    if (!Platform.isAndroid) return false;
    await _ensurePermissions();
    final on = await _bluetoothChannel.invokeMethod<bool>('requestEnable');
    _log('asked to switch Bluetooth on: ${on == true ? 'yes' : 'no'}');
    return on == true;
  }

  Future<void> _waitForBluetooth() async {
    final status = await _ble.statusStream
        .firstWhere((s) => s != BleStatus.unknown)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => BleStatus.unknown,
        );
    switch (status) {
      case BleStatus.ready:
        return;
      case BleStatus.poweredOff:
        throw const _ScaleException('Bluetooth is switched off.');
      case BleStatus.unauthorized:
        // iOS asks on its own (CoreBluetooth); a "no" can only be undone
        // in the system settings.
        throw _ScaleException(
          Platform.isIOS
              ? 'Bluetooth permission denied. Allow Bluetooth for bean\'d in Settings.'
              : 'Bluetooth permission denied. Allow "Nearby devices" for bean\'d.',
        );
      case BleStatus.locationServicesDisabled:
        throw const _ScaleException(
          'Turn on location services to find the scale.',
        );
      case BleStatus.unsupported:
        throw const _ScaleException('This device has no Bluetooth LE.');
      case BleStatus.unknown:
        throw const _ScaleException('Bluetooth is not ready.');
    }
  }

  Future<void> _open() async {
    final id = _deviceId!;
    final session = _session;
    _set(ScaleConnection.connecting);
    final ready = _ready = Completer<void>();
    await _connSub?.cancel();
    // Giving up on the same scale ends with a disconnect by its id, which
    // would also hit this attempt.
    await _abandoned[id];
    if (session != _session) {
      throw const _ScaleException('Connection cancelled.');
    }
    _connPending = true;
    // On subscribing, the plugin first repeats the scale's last state, usually
    // "disconnected" from the time before (log 2026-11-05). That says nothing
    // about this attempt: only after its "connecting" does a "disconnected"
    // mean it ended.
    var attemptStarted = false;
    _connSub = _ble
        .connectToDevice(id: id, connectionTimeout: _connectTimeout)
        .listen(
          (update) async {
            if (session != _session) return;
            if (update.connectionState == DeviceConnectionState.connecting) {
              attemptStarted = true;
            } else if (update.connectionState ==
                    DeviceConnectionState.disconnected &&
                !attemptStarted) {
              return;
            } else {
              attemptStarted = true;
              _connPending = false;
            }
            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                try {
                  await _setUp(id, session);
                  _reconnects = 0;
                  _addKnown(id, _deviceName ?? id);
                  _log('connected to $_deviceName');
                  _set(ScaleConnection.connected);
                  if (!ready.isCompleted) ready.complete();
                } catch (e) {
                  if (!ready.isCompleted) ready.completeError(e);
                }
              case DeviceConnectionState.disconnected:
                if (!ready.isCompleted) {
                  ready.completeError(const _ScaleException(_noAnswer));
                } else {
                  _onLost();
                }
              case DeviceConnectionState.connecting:
              case DeviceConnectionState.disconnecting:
                break;
            }
          },
          onError: (Object e) {
            _connPending = false;
            if (!ready.isCompleted) {
              ready.completeError(e);
            } else {
              _onLost();
            }
          },
        );
    // Never wait forever: the connect timeout plus room for setting up.
    try {
      await ready.future.timeout(_connectTimeout + const Duration(seconds: 15));
    } finally {
      if (identical(_ready, ready)) _ready = null;
    }
  }

  Future<void> _setUp(String id, int session) async {
    // Switched to another scale meanwhile: nothing here may touch its
    // connection (its timers and channels replaced the new scale's).
    void stillCurrent() {
      if (session != _session) {
        throw const _ScaleException('Connection cancelled.');
      }
    }

    await _ble.discoverAllServices(id);
    stillCurrent();
    final services = await _ble.getDiscoveredServices(id);
    stillCurrent();
    for (final s in services) {
      debugPrint(
        'BleScale: service ${s.id} → '
        '${s.characteristics.map((c) => '${c.id}'
            '${c.isNotifiable ? ' N' : ''}${c.isIndicatable ? ' I' : ''}'
            '${c.isWritableWithResponse ? ' W' : ''}'
            '${c.isWritableWithoutResponse ? ' w' : ''}').join(', ')}',
      );
    }
    Characteristic? find(String uuid) {
      final want = Uuid.parse(uuid).expanded;
      for (final s in services) {
        for (final c in s.characteristics) {
          if (c.id.expanded == want) return c;
        }
      }
      return null;
    }

    final driver = _driverFor(_deviceName);
    if (driver == null) {
      throw _ScaleException('$_deviceName is not a supported scale.');
    }
    _driver = driver;
    final ScaleChannels channels;
    try {
      channels = driver.pick(find);
    } on ScaleSetupException catch (e) {
      throw _ScaleException(e.message);
    }
    final notify = channels.notify;
    _writeChar = channels.write;
    debugPrint(
      'BleScale: $_deviceName → ${driver.brand}'
      '${driver.details == null ? '' : ' (${driver.details})'}',
    );

    final battery = driver.readsBatteryService
        ? find('00002a19-0000-1000-8000-00805f9b34fb')
        : null;
    _timerRunning = false;

    driver.reset();
    _battery = null;
    _packets.clear();
    _packetCount = 0;
    await _notifySub?.cancel();
    stillCurrent();
    _notifySub = notify.subscribe().listen(
      _onPacket,
      onError: (Object e) {
        debugPrint('BleScale: notify error $e');
      },
    );
    await driver.start(_write);
    stillCurrent();

    _lastPacket = DateTime.now();
    _heartbeat?.cancel();
    final beat = driver.heartbeat;
    if (beat != null) {
      _heartbeat = Timer.periodic(driver.heartbeatPeriod, (_) {
        _write(beat).catchError((Object e) {
          debugPrint('BleScale: heartbeat failed $e');
        });
      });
    }
    // Battery level via the standard service (0x180F/0x2A19) where the
    // driver wants it — read only once weight data is flowing, and only
    // read, never subscribe (see AcaiaDriver.readsBatteryService).
    _batteryTimer?.cancel();
    if (driver.batteryRequest case final ask?) {
      _batteryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        _write(ask).catchError((Object e) {
          debugPrint('BleScale: battery request failed $e');
        });
      });
    } else if (battery != null) {
      Future<void> readBattery() async {
        try {
          final v = await battery.read();
          if (v.isNotEmpty) {
            _battery = v.first.clamp(0, 100);
            notifyListeners();
          }
        } catch (e) {
          debugPrint('BleScale: battery read failed $e');
        }
      }

      _batteryTimer = Timer(const Duration(seconds: 3), () {
        readBattery();
        _batteryTimer = Timer.periodic(
          const Duration(minutes: 1),
          (_) => readBattery(),
        );
      });
    }

    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      final last = _lastPacket;
      final timeout = driver.packetTimeout;
      if (last != null && DateTime.now().difference(last) > timeout) {
        debugPrint('BleScale: no packets for ${timeout.inSeconds}s');
        _onLost();
      }
    });
  }

  void _onPacket(List<int> packet) {
    _lastPacket = DateTime.now();
    _packetCount++;
    final hex = hexPacket(packet);
    _packets.add(hex);
    if (_packets.length > _keepPackets) _packets.removeAt(0);
    final parsed = _driver?.parse(packet) ?? ScalePacket.empty;
    // The first 40, after that only what carried no weight (buttons,
    // battery, unknown packets) — weight comes 10× a second.
    if (_packetCount <= 40 || parsed.weights.isEmpty) {
      debugPrint('BleScale: rx $hex');
    }
    for (final g in parsed.weights) {
      _grams = g;
      _readings.add(ScaleReading(g, _lastPacket!));
    }
    if (parsed.battery case final b?) _battery = b;
    if (parsed.button case final button?) _onButton(button);
    notifyListeners();
  }

  /// The scale's own buttons, carried out the way the scale does on its own.
  void _onButton(ScaleButton button) {
    debugPrint('BleScale: button ${button.name}');
    final Future<void> done = switch (button) {
      ScaleButton.tare => tare(),
      ScaleButton.timer => _timerRunning ? stopTimer() : startTimer(),
      ScaleButton.timerReset => resetTimer(),
    };
    done.catchError((Object e) {
      debugPrint('BleScale: button ${button.name} failed $e');
    });
  }

  Future<void> _write(Uint8List bytes) async {
    final c = _writeChar;
    if (c == null) return;
    final confirmed =
        (_driver?.writeWithResponse ?? false) && c.isWritableWithResponse;
    await c.write(
      bytes,
      withResponse: confirmed || !c.isWritableWithoutResponse,
    );
  }

  /// Whether a lost scale may be replaced by another known one right now.
  /// Not during a brew: the zero and the weights belong to the scale in use.
  bool Function()? mayAutoSwitch;

  /// How long a lost scale has to show up again before another one takes over.
  @visibleForTesting
  Duration autoSwitchGrace = const Duration(seconds: 5);

  @visibleForTesting
  Duration lostSettle = const Duration(seconds: 2);

  bool get _otherKnown =>
      (mayAutoSwitch?.call() ?? true) && _known.any((k) => k.id != _deviceId);

  // The lost scale as soon as it shows up; after [autoSwitchGrace] a known
  // other one. Null if neither does.
  Future<ScaleCandidate?> _searchAfterLost(String id) async {
    final found = _finding = Completer<ScaleCandidate?>();
    ScaleCandidate? other;
    Timer? grace;
    void take(ScaleCandidate? c) {
      if (!found.isCompleted) found.complete(c);
    }

    final started = DateTime.now();
    final sub = scan(timeout: _scanTimeout).listen(
      (c) {
        if (c.id == id) {
          take(c);
        } else if (other == null &&
            _known.any((k) => k.id == c.id) &&
            _otherKnown) {
          other = c;
          final left = autoSwitchGrace - DateTime.now().difference(started);
          grace = Timer(left.isNegative ? Duration.zero : left, () => take(c));
        }
      },
      onError: (Object e) {
        if (!found.isCompleted) found.completeError(e);
      },
      onDone: () => take(other),
    );
    try {
      return await found.future;
    } finally {
      if (identical(_finding, found)) _finding = null;
      grace?.cancel();
      unawaited(sub.cancel());
    }
  }

  @visibleForTesting
  Future<void> simulateLost() => _onLost();

  // The session being recovered: a loop of an older one must not stop the
  // new scale from recovering.
  int? _recovering;

  Future<void> _onLost() async {
    final session = _session;
    if (_recovering == session) return;
    _recovering = session;
    _log('connection lost');
    try {
      await _teardown();
      if (session != _session) return;
      if (!_wantConnected || _deviceId == null) {
        _set(ScaleConnection.disconnected);
        return;
      }
      // First reconnect blindly (short radio dropout), after that only
      // when the scale is sending again – it can be off for minutes.
      bool current() => _wantConnected && session == _session;
      final deadline = DateTime.now().add(_reconnectWindow);
      while (current() && DateTime.now().isBefore(deadline)) {
        _reconnects++;
        debugPrint('BleScale: reconnect $_reconnects');
        try {
          // With another scale to go to, look before connecting: an attempt
          // on a scale that is off holds up everything else for its timeout.
          if (_reconnects > 1 || _otherKnown) {
            _set(ScaleConnection.scanning);
            // Android still reports a scale just switched off for a moment
            // (log 2026-11-05: 85 ms after the loss).
            if (_reconnects == 1) {
              await Future<void>.delayed(lostSettle);
              if (!current()) break;
            }
            final next = await _searchAfterLost(_deviceId!);
            if (next == null || !current()) continue;
            if (next.id != _deviceId) {
              _log('switching to ${next.name}');
              _deviceId = next.id;
              _deviceName = next.name;
              await _remember(next.id, next.name);
              if (!current()) break;
            }
          }
          if (!current()) break;
          await _open();
          return;
        } catch (e) {
          debugPrint('BleScale: reconnect failed $e');
          // Only clean up our own attempt — after a switch the connection
          // belongs to the new scale.
          if (!current()) return;
          await _teardown();
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      // Switched to another scale meanwhile: leave its connection alone.
      if (session != _session) return;
      if (!_wantConnected) {
        _set(ScaleConnection.disconnected);
        return;
      }
      _fail('Lost the connection to the scale.');
    } finally {
      if (_recovering == session) _recovering = null;
    }
  }

  Future<void> _teardown() async {
    final ready = _ready;
    _ready = null;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(const _ScaleException('Connection cancelled.'));
    }
    _heartbeat?.cancel();
    _watchdog?.cancel();
    _heartbeat = null;
    _watchdog = null;
    await _notifySub?.cancel();
    _notifySub = null;
    _batteryTimer?.cancel();
    _batteryTimer = null;
    final conn = _connSub;
    _connSub = null;
    if (conn != null && _connPending) {
      _abandon(conn, _deviceId);
    } else {
      await conn?.cancel(); // drops the BLE connection
    }
    _connPending = false;
    _writeChar = null;
    _grams = null;
  }

  // An attempt that hasn't answered must not be cancelled on Android: the
  // plugin (reactive_ble_mobile 5.6, DeviceConnector) only takes it off its
  // connection queue when it answers, so it stays first in line and no other
  // scale ever connects until the app restarts. So it runs out by itself (its
  // connect timeout) and only then is dropped; the next scale waits in the
  // plugin's queue meanwhile.
  void _abandon(StreamSubscription<ConnectionStateUpdate> conn, String? id) {
    final ended = Completer<void>();
    void end() {
      if (ended.isCompleted) return;
      ended.complete();
      unawaited(conn.cancel());
      if (id != null && identical(_abandoned[id], ended.future)) {
        _abandoned.remove(id);
      }
    }

    conn.onData((update) {
      if (update.connectionState != DeviceConnectionState.connecting) end();
    });
    conn.onError((Object _) => end());
    conn.onDone(end);
    // Should it never answer, don't hold on to it for ever.
    // Generous: a timer running out cancels the attempt, and one still waiting
    // behind others in the plugin's queue may need several timeouts.
    final limit = Timer(const Duration(seconds: 60), end);
    unawaited(ended.future.whenComplete(limit.cancel));
    if (id != null) _abandoned[id] = ended.future;
  }

  void _fail(String message) {
    _error = message;
    _wantConnected = false;
    _teardown();
    _set(ScaleConnection.disconnected);
  }

  void _set(ScaleConnection c) {
    _connection = c;
    notifyListeners();
  }

  static String _describe(Object e) {
    if (e is _ScaleException) return e.message;
    if (e is TimeoutException) return _noAnswer;
    return 'Scale error: $e';
  }

  @override
  void dispose() {
    _wantConnected = false;
    _stopRadioScan();
    _teardown();
    _readings.close();
    super.dispose();
  }
}

const _noAnswer = 'No answer from the scale. Is it on and free?';

class _ScaleException implements Exception {
  const _ScaleException(this.message);
  final String message;
  @override
  String toString() => message;
}
