import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/radio_scan.dart';
import '../scale/brew_scale.dart'
    show KnownScale, ScaleCandidate, ScaleConnection;
import '../services/connection_log.dart';

/// A pressure reading in bar.
@immutable
class PressureReading {
  const PressureReading(this.bar, this.at);
  final double bar;
  final DateTime at;
}

/// An external pressure sensor in the group head or portafilter (Home →
/// Espresso), for machines the app does not talk to. Only this interface is
/// known to the rest of the app.
abstract class PressureSensor extends ChangeNotifier {
  ScaleConnection get connection;
  bool get isConnected => connection == ScaleConnection.connected;

  /// Name the sensor advertises.
  String? get deviceName;

  /// Short name for the command row.
  String get shortName => 'Sensor';

  int? get batteryPercent => null;

  /// Last reading, null before the first one.
  double? get bar;

  Stream<PressureReading> get readings;

  String? get error;

  /// The sensor Home → Espresso uses (the one it connects to); null = none.
  String? get rememberedId => null;

  /// Name to show: the user's own for the sensor in use, else what it
  /// advertises.
  String? get displayName => deviceName;

  /// Sensors the app has connected to before (Settings → Connections →
  /// Sensors), also while they are off.
  List<KnownScale> get knownSensors => const [];

  /// Sensors nearby, for the settings page — from the app's shared radio
  /// scan, so it never cuts a scale's search short.
  Stream<ScaleCandidate> scan({
    Duration timeout = const Duration(seconds: 10),
  }) => const Stream.empty();

  Future<void> connect();

  /// Switches to [candidate] right away and makes it the one in use.
  Future<void> connectTo(ScaleCandidate candidate) => connect();

  Future<void> disconnect();

  /// Which known sensor Home → Espresso uses; null = none (disconnects, the
  /// known sensors stay).
  Future<void> select(String? id) async {}

  Future<void> renameSensor(String id, String name) async {}

  /// Removes a sensor from the known ones (disconnects it if in use).
  Future<void> forgetSensor(String id) async {}

  /// Disconnects and forgets the sensor in use.
  Future<void> forget() => disconnect();

  /// Sets the current pressure as zero (done with no pressure on it).
  Future<void> zero() async {}
}

/// Pressensor PRS (pressensor.com), over Bluetooth LE. Protocol as in
/// Beanconqueror (src/classes/devices/prsPressure.ts): name contains
/// "PRS"; one service with a notify characteristic carrying the pressure as
/// a big-endian signed 16-bit value in millibar, and a write characteristic
/// that zeroes the sensor on any byte. Battery via the standard service.
///
/// Not checked on a real sensor yet.
class Pressensor extends PressureSensor {
  Pressensor({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle() {
    unawaited(_loadRemembered());
  }

  static final serviceUuid = Uuid.parse('873ae82a-4c5a-4342-b539-9d900bf7ebd0');
  static final pressureUuid = Uuid.parse(
    '873ae82b-4c5a-4342-b539-9d900bf7ebd0',
  );
  static final zeroUuid = Uuid.parse('873ae82c-4c5a-4342-b539-9d900bf7ebd0');
  static final _batteryService = Uuid.parse('180f');
  static final _batteryChar = Uuid.parse('2a19');

  static const lastIdPrefKey = 'pressure_sensor.lastId';
  static const lastNamePrefKey = 'pressure_sensor.lastName';
  static const knownPrefKey = 'pressure_sensor.known';

  static const _scanTimeout = Duration(seconds: 15);
  static const _connectTimeout = Duration(seconds: 10);

  /// Whether an advertised name is a Pressensor.
  static bool matches(String name) => name.toUpperCase().contains('PRS');

  /// Millibar packet → bar; null for a packet too short to read.
  static double? parse(List<int> packet) {
    if (packet.length < 2) return null;
    var raw = (packet[0] << 8) | packet[1];
    if (raw >= 0x8000) raw -= 0x10000;
    return raw / 1000;
  }

  final FlutterReactiveBle _ble;
  late final BleRadioScan _radio = BleRadioScan.of(_ble);

  ScaleConnection _connection = ScaleConnection.disconnected;
  @override
  ScaleConnection get connection => _connection;

  String? _deviceId;
  String? _deviceName;
  @override
  String? get deviceName => _deviceName;

  @override
  String get shortName => 'Pressensor';

  @override
  String? get rememberedId => _deviceId;

  List<KnownScale> _known = const [];
  @override
  List<KnownScale> get knownSensors => _known;

  @override
  String? get displayName =>
      _known.where((k) => k.id == _deviceId).firstOrNull?.customName ??
      _deviceName;

  int? _battery;
  @override
  int? get batteryPercent => _battery;

  double? _bar;
  @override
  double? get bar => _bar;

  String? _error;
  @override
  String? get error => _error;

  final _readings = StreamController<PressureReading>.broadcast();
  @override
  Stream<PressureReading> get readings => _readings.stream;

  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;
  Timer? _batteryTimer;
  int _session = 0;

  static void _log(String message) {
    debugPrint('Pressensor: $message');
    ConnectionLog.write('pressure', message);
  }

  Future<void> _loadRemembered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString(lastIdPrefKey);
      _deviceName = prefs.getString(lastNamePrefKey);
      var known = const <KnownScale>[];
      final raw = prefs.getString(knownPrefKey);
      if (raw != null) {
        known = [
          for (final e in jsonDecode(raw) as List) ?KnownScale.fromJson(e),
        ];
      }
      // The sensor of versions before the list counts too.
      final id = _deviceId, name = _deviceName;
      _known = [
        ...known,
        if (id != null && name != null && !known.any((k) => k.id == id))
          KnownScale(id: id, name: name),
      ];
      notifyListeners();
    } catch (e) {
      debugPrint('Pressensor: known sensors unreadable: $e');
    }
  }

  Future<void> _saveKnown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        knownPrefKey,
        jsonEncode([for (final k in _known) k.toJson()]),
      );
    } catch (_) {}
  }

  Future<void> _remember(String id, String name) async {
    _deviceId = id;
    _deviceName = name;
    if (!_known.any((k) => k.id == id)) {
      _known = [..._known, KnownScale(id: id, name: name)];
      unawaited(_saveKnown());
    }
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(lastIdPrefKey, id);
      await p.setString(lastNamePrefKey, name);
    } catch (_) {}
  }

  void _set(ScaleConnection c) {
    _connection = c;
    notifyListeners();
  }

  Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid) return;
    if (await Permission.bluetoothScan.isGranted &&
        await Permission.bluetoothConnect.isGranted) {
      return;
    }
    final res = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    if (res.values.any((s) => !s.isGranted)) {
      throw Exception('Bluetooth permission denied.');
    }
  }

  @override
  Future<void> connect() async {
    if (_connection != ScaleConnection.disconnected) return;
    final session = ++_session;
    _error = null;
    try {
      await _ensurePermissions();
      _set(ScaleConnection.scanning);
      final found = await _find();
      if (session != _session) return;
      if (found == null) {
        _error = 'No pressure sensor found.';
        _log('none found');
        _set(ScaleConnection.disconnected);
        return;
      }
      await _remember(found.id, found.name);
      if (session != _session) return;
      await _open(found.id, session);
    } catch (e) {
      if (session != _session) return;
      _error = 'Could not connect the sensor.';
      _log('connect failed: $e');
      await _teardown();
      _set(ScaleConnection.disconnected);
    }
  }

  // The remembered sensor wins; otherwise the first Pressensor nearby.
  Future<ScaleCandidate?> _find() async {
    final done = Completer<ScaleCandidate?>();
    late final StreamSubscription<DiscoveredDevice> sub;
    ScaleCandidate? first;
    final timer = Timer(_scanTimeout, () {
      if (!done.isCompleted) done.complete(first);
    });
    sub = _radio
        .devices(timeout: _scanTimeout)
        .listen(
          (d) {
            if (!matches(d.name)) return;
            final c = ScaleCandidate(id: d.id, name: d.name, rssi: d.rssi);
            if (d.id == _deviceId || _deviceId == null) {
              if (!done.isCompleted) done.complete(c);
            } else {
              first ??= c;
            }
          },
          onError: (Object e) {
            if (!done.isCompleted) done.completeError(e);
          },
          onDone: () {
            if (!done.isCompleted) done.complete(first);
          },
        );
    try {
      return await done.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  Future<void> _open(String id, int session) async {
    _set(ScaleConnection.connecting);
    final ready = Completer<void>();
    await _connSub?.cancel();
    _connSub = _ble
        .connectToDevice(id: id, connectionTimeout: _connectTimeout)
        .listen(
          (u) async {
            if (session != _session) return;
            switch (u.connectionState) {
              case DeviceConnectionState.connected:
                try {
                  await _setUp(id);
                  if (!ready.isCompleted) ready.complete();
                } catch (e) {
                  if (!ready.isCompleted) ready.completeError(e);
                }
              case DeviceConnectionState.disconnected:
                if (!ready.isCompleted) {
                  ready.completeError(Exception('disconnected'));
                } else {
                  _log('lost');
                  await _teardown();
                  _set(ScaleConnection.disconnected);
                }
              default:
                break;
            }
          },
          onError: (Object e) {
            if (!ready.isCompleted) ready.completeError(e);
          },
        );
    await ready.future.timeout(_connectTimeout * 2);
    _log('connected');
    _set(ScaleConnection.connected);
  }

  Future<void> _setUp(String id) async {
    final pressure = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: pressureUuid,
      deviceId: id,
    );
    await _notifySub?.cancel();
    _notifySub = _ble.subscribeToCharacteristic(pressure).listen((packet) {
      final value = parse(packet);
      if (value == null) return;
      _bar = value;
      _readings.add(PressureReading(value, DateTime.now()));
      notifyListeners();
    }, onError: (Object e) => debugPrint('Pressensor: notify error $e'));
    // Like Beanconqueror: zero once right after connecting (no pressure on
    // the sensor at that moment).
    unawaited(Future<void>.delayed(const Duration(seconds: 1), () => zero()));
    final battery = QualifiedCharacteristic(
      serviceId: _batteryService,
      characteristicId: _batteryChar,
      deviceId: id,
    );
    Future<void> readBattery() async {
      try {
        final v = await _ble.readCharacteristic(battery);
        if (v.isNotEmpty) {
          _battery = v.first.clamp(0, 100);
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Pressensor: battery read failed $e');
      }
    }

    _batteryTimer?.cancel();
    _batteryTimer = Timer(const Duration(seconds: 3), () {
      readBattery();
      _batteryTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => readBattery(),
      );
    });
  }

  @override
  Stream<ScaleCandidate> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    await _ensurePermissions();
    final seen = <String>{};
    yield* _radio
        .devices(timeout: timeout)
        .where((d) => matches(d.name) && seen.add(d.id))
        .map((d) => ScaleCandidate(id: d.id, name: d.name, rssi: d.rssi));
  }

  @override
  Future<void> connectTo(ScaleCandidate candidate) async {
    if (candidate.id == _deviceId &&
        _connection != ScaleConnection.disconnected) {
      return;
    }
    await disconnect();
    final session = ++_session;
    _error = null;
    try {
      await _ensurePermissions();
      await _remember(candidate.id, candidate.name);
      if (session != _session) return;
      await _open(candidate.id, session);
    } catch (e) {
      if (session != _session) return;
      _error = 'Could not connect the sensor.';
      _log('connect failed: $e');
      await _teardown();
      _set(ScaleConnection.disconnected);
    }
  }

  @override
  Future<void> select(String? id) async {
    if (id == _deviceId) return;
    await disconnect();
    if (id == null) {
      _deviceId = null;
      _deviceName = null;
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(lastIdPrefKey);
        await prefs.remove(lastNamePrefKey);
      } catch (_) {}
      return;
    }
    final k = _known.where((k) => k.id == id).firstOrNull;
    if (k == null) return;
    await _remember(k.id, k.name);
  }

  @override
  Future<void> renameSensor(String id, String name) async {
    final clean = name.trim();
    _known = [
      for (final k in _known)
        if (k.id == id) k.renamed(clean.isEmpty ? null : clean) else k,
    ];
    notifyListeners();
    await _saveKnown();
  }

  @override
  Future<void> forgetSensor(String id) async {
    _known = [
      for (final k in _known)
        if (k.id != id) k,
    ];
    await _saveKnown();
    if (id == _deviceId) {
      await forget();
    } else {
      notifyListeners();
    }
  }

  @override
  Future<void> zero() async {
    final id = _deviceId;
    if (id == null ||
        !isConnected && _connection != ScaleConnection.connecting) {
      return;
    }
    try {
      await _ble.writeCharacteristicWithoutResponse(
        QualifiedCharacteristic(
          serviceId: serviceUuid,
          characteristicId: zeroUuid,
          deviceId: id,
        ),
        value: const [0],
      );
    } catch (e) {
      debugPrint('Pressensor: zero failed $e');
    }
  }

  Future<void> _teardown() async {
    _batteryTimer?.cancel();
    _batteryTimer = null;
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel();
    _connSub = null;
    _bar = null;
    _battery = null;
  }

  @override
  Future<void> disconnect() async {
    _session++;
    await _teardown();
    _set(ScaleConnection.disconnected);
  }

  @override
  Future<void> forget() async {
    await disconnect();
    final id = _deviceId;
    if (id != null && _known.any((k) => k.id == id)) {
      _known = [
        for (final k in _known)
          if (k.id != id) k,
      ];
      await _saveKnown();
    }
    _deviceId = null;
    _deviceName = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(lastIdPrefKey);
      await prefs.remove(lastNamePrefKey);
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_teardown());
    unawaited(_readings.close());
    super.dispose();
  }
}
