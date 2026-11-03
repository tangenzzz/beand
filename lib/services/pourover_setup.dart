import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../scale/brew_scale.dart';

/// Steps before a Pour Over brew on the Meticulous' scale, like the
/// machine's own Pour Over mode on the dial: server on → tare → brewer on →
/// tare → coffee in → tare.
enum SetupStep { server, brewer, coffee, done }

enum SetupStatus {
  /// Waiting for the load of this step.
  waiting,

  /// Tare sent, waiting for the machine.
  taring,

  /// Tare failed — tap Tare to try again.
  tareFailed,
}

/// Runs the setup steps on the scale readings. Advances by itself once the
/// weight is steady with the expected load; Tare (command row) records the
/// current step right away (e.g. a brewer built into the server adds
/// nothing).
class PourOverSetup extends ChangeNotifier {
  PourOverSetup({required this.tare, this.targetDose});

  /// Tares the scale; throws if it failed.
  final Future<void> Function() tare;

  /// Dose of the plan — the coffee step records from 80 % of it.
  double? Function()? targetDose;

  /// Steady = the readings of the last [steadyWindow] stay within
  /// [steadyBand] (Meticulous noise idle: ±0.03 g).
  static const steadyWindow = Duration(milliseconds: 900);
  static const steadyBand = 0.3;

  /// Load change that counts as "server placed" — a server always weighs
  /// more, and small bumps on the tray must not count.
  static const serverMinLoad = 20.0;

  /// Same threshold as the dial for a brewer on top (SETUP_LOAD_CHANGE_G).
  static const brewerMinLoad = 1.2;

  /// Coffee: the dial accepts 5–40 g.
  static const coffeeMin = 5.0;
  static const coffeeMax = 60.0;

  SetupStep _step = SetupStep.server;
  SetupStep get step => _step;

  SetupStatus _status = SetupStatus.waiting;
  SetupStatus get status => _status;

  bool get done => _step == SetupStep.done;

  /// 1-based step for "2/3".
  int get stepNumber => _step.index + 1;
  static const stepCount = 3;

  double? serverG;
  double? brewerG;
  double? coffeeG;

  double? _baseline;
  double? _last;
  final _window = <({int ms, double g})>[];

  void restart() {
    _step = SetupStep.server;
    _status = SetupStatus.waiting;
    serverG = brewerG = coffeeG = null;
    _baseline = null;
    _window.clear();
    notifyListeners();
  }

  void skip() {
    _step = SetupStep.done;
    _status = SetupStatus.waiting;
    notifyListeners();
  }

  /// Back from a pause (view left): the baseline of the server step may be
  /// outdated.
  void resume() {
    _baseline = null;
    _window.clear();
  }

  bool get _steady {
    if (_window.length < 3) return false;
    if (_window.last.ms - _window.first.ms <
        steadyWindow.inMilliseconds - 150) {
      return false;
    }
    var lo = double.infinity, hi = -double.infinity;
    for (final p in _window) {
      lo = math.min(lo, p.g);
      hi = math.max(hi, p.g);
    }
    return hi - lo <= steadyBand;
  }

  void feed(ScaleReading r) {
    if (done) return;
    _last = r.grams;
    final ms = r.at.millisecondsSinceEpoch;
    _window.add((ms: ms, g: r.grams));
    while (_window.length > 2 &&
        ms - _window.first.ms > steadyWindow.inMilliseconds) {
      _window.removeAt(0);
    }
    if (_status != SetupStatus.waiting || !_steady) return;
    final g = r.grams;
    switch (_step) {
      case SetupStep.server:
        // Baseline = lowest steady value: whatever stood on the scale
        // before (last brew) is taken off first.
        final base = _baseline;
        if (base == null || g < base) {
          _baseline = g;
          return;
        }
        if (g - base >= serverMinLoad) unawaited(confirm());
      case SetupStep.brewer:
        if (g >= brewerMinLoad) unawaited(confirm());
      case SetupStep.coffee:
        final target = targetDose?.call();
        final from = target == null
            ? coffeeMin
            : math.max(coffeeMin, target * 0.8);
        if (g >= from && g <= coffeeMax) unawaited(confirm());
      case SetupStep.done:
        break;
    }
  }

  /// Records the current step with the current weight and tares.
  Future<void> confirm() async {
    if (done || _status == SetupStatus.taring) return;
    final g = _last ?? 0;
    switch (_step) {
      case SetupStep.server:
        serverG = math.max(0, g - (_baseline ?? 0));
      case SetupStep.brewer:
        brewerG = math.max(0, g);
      case SetupStep.coffee:
        coffeeG = math.max(0, g);
      case SetupStep.done:
        return;
    }
    _status = SetupStatus.taring;
    notifyListeners();
    try {
      await tare();
    } catch (_) {
      _status = SetupStatus.tareFailed;
      notifyListeners();
      return;
    }
    _status = SetupStatus.waiting;
    _window.clear();
    _step = SetupStep.values[_step.index + 1];
    notifyListeners();
  }

  /// What the brew saves (local only, see PourOverBrewService._save).
  Map<String, Object?> toJson() => {
    'serverG': serverG,
    'brewerG': brewerG,
    'coffeeG': coffeeG,
  };
}
