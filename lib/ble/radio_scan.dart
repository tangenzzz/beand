import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/connection_log.dart';

/// A scan that could not run, with a message for the user.
class BleScanException implements Exception {
  const BleScanException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The phone's one Bluetooth scan, shared by everything that looks for a
/// device — scales, pressure sensors, a settings page, a reconnect. The
/// plugin runs a single scan: a second one silently ends the first (until
/// 2026-11-23 the scale and the Pressensor each scanned on their own, so
/// opening Home → Espresso could cut the scale's search short). Everyone
/// listens to this one instead; it runs while anyone listens.
///
/// One per [FlutterReactiveBle] — the app has one, tests their fakes.
class BleRadioScan {
  BleRadioScan._(this._ble);

  static final _byBle = Expando<BleRadioScan>();

  static BleRadioScan of(FlutterReactiveBle ble) =>
      _byBle[ble] ??= BleRadioScan._(ble);

  final FlutterReactiveBle _ble;

  StreamSubscription<DiscoveredDevice>? _radio;
  final _listeners = <StreamController<DiscoveredDevice>>{};
  final _seen = <String, DiscoveredDevice>{};
  Timer? _startTimer;

  // Android answers more than 5 scan starts in 30 s with an empty scan and no
  // error. Stay below that: the next start waits instead.
  final _starts = <DateTime>[];
  static const _maxStarts = 4;
  static const _startWindow = Duration(seconds: 30);

  /// Whether the radio scan runs right now.
  @visibleForTesting
  bool get running => _radio != null;

  static void _log(String message) {
    debugPrint('BleRadioScan: $message');
    ConnectionLog.write('bluetooth', message);
  }

  /// Every device the scan sees for [timeout] — those already seen in a
  /// running scan first. The stream ends after [timeout] (longer when the
  /// start has to wait); cancelling it leaves the scan to the others.
  Stream<DiscoveredDevice> devices({
    Duration timeout = const Duration(seconds: 10),
  }) {
    late final StreamController<DiscoveredDevice> out;
    Timer? end;
    out = StreamController<DiscoveredDevice>(
      onListen: () {
        _listeners.add(out);
        final wait = _start();
        // Long enough to really search when the start has to wait.
        end = Timer(timeout + wait, out.close);
        for (final d in _seen.values) {
          out.add(d);
        }
      },
      onCancel: () {
        end?.cancel();
        _listeners.remove(out);
        if (_listeners.isEmpty) _stop();
      },
    );
    return out.stream;
  }

  // Returns how long until the scan really runs.
  Duration _start() {
    if (_radio != null) return Duration.zero;
    if (_startTimer case final t? when t.isActive) return _nextStart();
    final wait = _nextStart();
    if (wait > Duration.zero) {
      _log('scan waits ${wait.inSeconds}s (too many scans)');
      _startTimer = Timer(wait, () {
        if (_listeners.isNotEmpty) _start();
      });
      return wait;
    }
    _starts.add(DateTime.now());
    _seen.clear();
    _log('scan started');
    _radio = _scanStream().listen(
      (d) {
        _seen[d.id] = d;
        for (final l in _listeners.toList()) {
          if (!l.isClosed) l.add(d);
        }
      },
      onError: (Object e) {
        _log('scan failed: $e');
        _radio = null;
        for (final l in _listeners.toList()) {
          if (!l.isClosed) {
            l.addError(e);
            l.close();
          }
        }
      },
      onDone: () => _radio = null,
    );
    return Duration.zero;
  }

  Duration _nextStart() {
    final now = DateTime.now();
    _starts.removeWhere((t) => now.difference(t) >= _startWindow);
    if (_starts.length < _maxStarts) return Duration.zero;
    return _startWindow - now.difference(_starts.first);
  }

  void _stop() {
    _startTimer?.cancel();
    _startTimer = null;
    final running = _radio;
    _radio = null;
    _seen.clear();
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
        throw const BleScanException(
          'Location permission is needed to find Bluetooth devices.',
        );
      }
      rethrow;
    }
  }
}
