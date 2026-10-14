import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'acaia_protocol.dart';
import 'brew_scale.dart';

const scaleLastDeviceIdPrefKey = 'scale.lastDeviceId';
const scaleLastDeviceNamePrefKey = 'scale.lastDeviceName';

/// Acaia Lunar/Pearl (old and new firmware) via flutter_reactive_ble.
/// Protocol details: acaia_protocol.dart.
class AcaiaScale extends BrewScale {
  AcaiaScale({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle() {
    unawaited(_loadRemembered());
  }

  final FlutterReactiveBle _ble;

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
  AcaiaGeneration? _generation;
  final _parser = AcaiaFrameParser();
  Characteristic? _writeChar;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  Timer? _heartbeat;
  Timer? _watchdog;
  DateTime? _lastPacket;
  bool _wantConnected = false;
  int _reconnects = 0;
  Completer<void>? _connecting;

  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    _rememberedId = prefs.getString(scaleLastDeviceIdPrefKey);
    _deviceName ??= prefs.getString(scaleLastDeviceNamePrefKey);
    notifyListeners();
  }

  Future<void> _remember(String id, String name) async {
    _rememberedId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(scaleLastDeviceIdPrefKey, id);
    await prefs.setString(scaleLastDeviceNamePrefKey, name);
  }

  // ---- Scan -----------------------------------------------------------

  @override
  Stream<ScaleCandidate> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    await _ensurePermissions();
    await _waitForBluetooth();
    final seen = <String>{};
    yield* _scanStream()
        .where((d) => isAcaiaName(d.name) && seen.add(d.id))
        .map((d) => ScaleCandidate(id: d.id, name: d.name, rssi: d.rssi))
        .timeout(timeout, onTimeout: (sink) => sink.close());
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

  @override
  Future<void> connectTo(ScaleCandidate candidate) async {
    if (_deviceId != candidate.id) await disconnect();
    return _connectWith(candidate);
  }

  Future<void> _connectWith(ScaleCandidate? pick) async {
    if (_connection == ScaleConnection.connected) return;
    if (_connecting != null) return _connecting!.future;
    final done = _connecting = Completer<void>();
    _wantConnected = true;
    _reconnects = 0;
    _error = null;
    try {
      await _ensurePermissions();
      await _waitForBluetooth();
      var target = pick;
      if (target == null) {
        _set(ScaleConnection.scanning);
        target = await _findForConnect();
      }
      if (target == null) {
        _fail(
          'No Acaia scale found. Is it switched on and not connected to another app?',
        );
        return;
      }
      _deviceId = target.id;
      _deviceName = target.name;
      await _remember(target.id, target.name);
      await _open();
    } catch (e) {
      _fail(_describe(e));
    } finally {
      _connecting = null;
      if (!done.isCompleted) done.complete();
    }
  }

  /// The remembered scale takes precedence; we take another one if the
  /// known one doesn't show up within 2 s.
  Future<ScaleCandidate?> _findForConnect() async {
    await _loadRemembered();
    final lastId = _rememberedId;
    ScaleCandidate? firstOther;
    final found = Completer<ScaleCandidate?>();
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
      grace?.cancel();
      await sub.cancel();
    }
  }

  @override
  Future<void> disconnect() async {
    _wantConnected = false;
    await _teardown();
    _set(ScaleConnection.disconnected);
  }

  @override
  Future<void> forget() async {
    await disconnect();
    _rememberedId = null;
    _deviceName = null;
    _error = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(scaleLastDeviceIdPrefKey);
    await prefs.remove(scaleLastDeviceNamePrefKey);
    notifyListeners();
  }

  @override
  Future<void> tare() => _write(AcaiaCommands.tare);

  // ---------------------------------------------------------------------

  Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid) return;
    // On Android 11 and older permission_handler reports "granted" for
    // SCAN/CONNECT anyway; there the scan needs location instead
    // (see _scanStream).
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
        throw const _ScaleException(
          'Bluetooth permission denied. Allow "Nearby devices" for bean\'d.',
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
    _set(ScaleConnection.connecting);
    final ready = Completer<void>();
    await _connSub?.cancel();
    _connSub = _ble
        .connectToDevice(id: id, connectionTimeout: _connectTimeout)
        .listen(
          (update) async {
            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                try {
                  await _setUp(id);
                  _reconnects = 0;
                  _set(ScaleConnection.connected);
                  if (!ready.isCompleted) ready.complete();
                } catch (e) {
                  if (!ready.isCompleted) ready.completeError(e);
                }
              case DeviceConnectionState.disconnected:
                if (!ready.isCompleted) {
                  ready.completeError(
                    const _ScaleException('The scale closed the connection.'),
                  );
                } else {
                  _onLost();
                }
              case DeviceConnectionState.connecting:
              case DeviceConnectionState.disconnecting:
                break;
            }
          },
          onError: (Object e) {
            if (!ready.isCompleted) {
              ready.completeError(e);
            } else {
              _onLost();
            }
          },
        );
    await ready.future;
  }

  Future<void> _setUp(String id) async {
    await _ble.discoverAllServices(id);
    final services = await _ble.getDiscoveredServices(id);
    for (final s in services) {
      debugPrint(
        'AcaiaScale: service ${s.id} → '
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

    final modernNotify = find(AcaiaUuids.modernNotify);
    final modernWrite = find(AcaiaUuids.modernWrite);
    final old = find(AcaiaUuids.oldChar);
    final Characteristic notify;
    if (modernNotify != null && modernWrite != null) {
      _generation = AcaiaGeneration.modern;
      notify = modernNotify;
      _writeChar = modernWrite;
    } else if (old != null) {
      _generation = AcaiaGeneration.old;
      notify = old;
      _writeChar = old;
    } else {
      throw const _ScaleException(
        'This scale does not speak the Acaia protocol.',
      );
    }
    debugPrint('AcaiaScale: $_deviceName → ${_generation!.name} firmware');

    final battery = find('00002a19-0000-1000-8000-00805f9b34fb');

    _parser.reset();
    _packets.clear();
    _packetCount = 0;
    await _notifySub?.cancel();
    _notifySub = notify.subscribe().listen(
      _onPacket,
      onError: (Object e) {
        debugPrint('AcaiaScale: notify error $e');
      },
    );
    // Wait briefly until notifications are really enabled — otherwise the
    // reply to IDENTIFY gets lost.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _write(AcaiaCommands.identify);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _write(AcaiaCommands.notificationRequest);

    _lastPacket = DateTime.now();
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(acaiaHeartbeatPeriod, (_) {
      _write(AcaiaCommands.heartbeat).catchError((Object e) {
        debugPrint('AcaiaScale: heartbeat failed $e');
      });
    });
    // Battery level via the standard service (0x180F/0x2A19) — read only
    // once weight data is flowing, and only read, never subscribe: with
    // battery notifications enabled BEFORE the weight channel, the Pearl
    // (old firmware) stopped sending weight packets entirely and the
    // connection dropped every 10 s.
    _batteryTimer?.cancel();
    if (battery != null) {
      Future<void> readBattery() async {
        try {
          final v = await battery.read();
          if (v.isNotEmpty) {
            _battery = v.first.clamp(0, 100);
            notifyListeners();
          }
        } catch (e) {
          debugPrint('AcaiaScale: battery read failed $e');
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
      if (last != null &&
          DateTime.now().difference(last) > acaiaPacketTimeout) {
        debugPrint(
          'AcaiaScale: no packets for ${acaiaPacketTimeout.inSeconds}s',
        );
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
    if (_packetCount <= 40) debugPrint('AcaiaScale: rx $hex');

    var weights = _parser.feed(packet);
    if (weights.isEmpty) {
      final g = parseHeaderlessWeight(packet);
      if (g != null) weights = [g];
    }
    for (final g in weights) {
      _grams = g;
      _readings.add(ScaleReading(g, _lastPacket!));
    }
    notifyListeners();
  }

  Future<void> _write(Uint8List bytes) async {
    final c = _writeChar;
    if (c == null) return;
    await c.write(bytes, withResponse: !c.isWritableWithoutResponse);
  }

  bool _recovering = false;

  Future<void> _onLost() async {
    if (_recovering) return;
    _recovering = true;
    try {
      await _teardown();
      if (!_wantConnected || _deviceId == null) {
        _set(ScaleConnection.disconnected);
        return;
      }
      // First reconnect blindly (short radio dropout), after that only
      // when the scale is sending again – it can be off for minutes.
      final deadline = DateTime.now().add(_reconnectWindow);
      while (_wantConnected && DateTime.now().isBefore(deadline)) {
        _reconnects++;
        debugPrint('AcaiaScale: reconnect $_reconnects');
        try {
          if (_reconnects > 1) {
            _set(ScaleConnection.scanning);
            final id = _deviceId!;
            final back = await scan(timeout: _scanTimeout)
                .any((c) => c.id == id);
            if (!back || !_wantConnected) continue;
          }
          await _open();
          return;
        } catch (e) {
          debugPrint('AcaiaScale: reconnect failed $e');
          await _teardown();
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      if (!_wantConnected) {
        _set(ScaleConnection.disconnected);
        return;
      }
      _fail('Lost the connection to the scale.');
    } finally {
      _recovering = false;
    }
  }

  Future<void> _teardown() async {
    _heartbeat?.cancel();
    _watchdog?.cancel();
    _heartbeat = null;
    _watchdog = null;
    await _notifySub?.cancel();
    _notifySub = null;
    _batteryTimer?.cancel();
    _batteryTimer = null;
    await _connSub?.cancel(); // drops the BLE connection
    _connSub = null;
    _writeChar = null;
    _grams = null;
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
    if (e is TimeoutException) return 'The scale did not answer in time.';
    return 'Scale error: $e';
  }

  @override
  void dispose() {
    _wantConnected = false;
    _teardown();
    _readings.close();
    super.dispose();
  }
}

class _ScaleException implements Exception {
  const _ScaleException(this.message);
  final String message;
  @override
  String toString() => message;
}
