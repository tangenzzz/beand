import 'package:flutter/foundation.dart';

import '../espresso_machine.dart';

// Machine mode from the firmware (src/display/core/constants.h, MODE_*).
// The WS spec only documents "m: integer" without values — looked up in the
// source code.
enum GaggiMateMode {
  standby(0),
  brew(1),
  steam(2),
  water(3),
  grind(4);

  const GaggiMateMode(this.code);

  final int code;

  static GaggiMateMode? fromCode(int? code) {
    if (code == null) return null;
    for (final mode in values) {
      if (mode.code == code) return mode;
    }
    return null;
  }
}

// The running (or last run) process — `process` in the status frame.
// NOT in the AsyncAPI spec, but in src/display/plugins/WebSocketHandler.cpp;
// the web UI reads exactly these fields.
@immutable
class GaggiMateProcess {
  const GaggiMateProcess({
    required this.active,
    required this.stage,
    required this.label,
    required this.elapsed,
    required this.utility,
    required this.targetIsVolumetric,
    required this.phaseTarget,
    required this.phaseProgress,
  });

  final bool active; // a
  final String stage; // s: brew | infusion | grind
  final String label; // l: phase name, "Finished" after the end
  final Duration elapsed; // e (ms since start; freezes after the end)
  final bool utility; // u: 1 = rinse/backflush, not a real shot
  final bool targetIsVolumetric; // tt
  final double phaseTarget; // pt
  final double phaseProgress; // pp

  // A finished process stays in the status until someone clears it with
  // `req:process:clear` — that's how the UI tells "done, waiting for
  // acknowledgement" from "running".
  bool get finished => !active;

  // Is this a real coffee brew? Only those belong in the Pre/Live/Post
  // cycle and the live chart.
  //
  // The firmware fills the process block ONLY for brew and grind
  // (WebSocketHandler.cpp): a steam or water draw only reports
  // `{"a": 1}` — without `s`, `l`, `e` and without `u`. So the `u` field
  // alone can't tell it apart from a brew; a filled `s` can.
  // Verified on the simulator.
  bool get isShot => !utility && (stage == 'brew' || stage == 'infusion');

  // Steam or water draw: runs through the same process block but is neither
  // a coffee brew nor a rinse — recognizable by the empty block.
  bool get isUtilityDraw => !utility && stage.isEmpty;

  static GaggiMateProcess? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    return GaggiMateProcess(
      active: _asBool(json['a']) ?? false,
      stage: (json['s'] ?? '').toString(),
      label: (json['l'] ?? '').toString(),
      elapsed: Duration(milliseconds: (_asDouble(json['e']) ?? 0).round()),
      utility: _asBool(json['u']) ?? false,
      targetIsVolumetric: json['tt'] == 'volumetric',
      phaseTarget: _asDouble(json['pt']) ?? 0,
      phaseProgress: _asDouble(json['pp']) ?? 0,
    );
  }
}

// Merged machine state.
//
// The core of the GaggiMate integration: `evt:status` frames are
// intentionally incomplete. Fast telemetry arrives every 500 ms, slow
// states only on change (at least every 10 s, complete right after
// connecting). So EVERY frame is merged onto the last known state instead
// of replacing it:
//
//   field missing     -> last value stays
//   field is null     -> value is cleared
//
// A plain replace store would make the UI flicker on every slow frame
// (temperature jumps to 0 and back).
@immutable
class GaggiMateStatus {
  const GaggiMateStatus({
    this.currentTemp,
    this.targetTemp,
    this.currentSteamTemp,
    this.targetSteamTemp,
    this.pressure,
    this.targetPressure,
    this.flow,
    this.targetFlow,
    this.weight,
    this.targetWeight,
    this.mode,
    this.profileLabel,
    this.profileId,
    this.systemState,
    this.systemMessage,
    this.controllerError,
    this.warnings = const [],
    this.process,
    this.dualBoiler = false,
    this.hasPressureControl = false,
    this.hasDimming = false,
    this.scaleConnected = false,
    this.scaleBattery,
  });

  static const empty = GaggiMateStatus();

  final double? currentTemp; // ct
  final double? targetTemp; // tt
  final double? currentSteamTemp; // cst
  final double? targetSteamTemp; // tst
  final double? pressure; // pr
  final double? targetPressure; // pt
  final double? flow; // fl
  final double? targetFlow; // tf
  final double? weight; // cw (Bluetooth scale on the GaggiMate)
  final double? targetWeight; // tw
  final GaggiMateMode? mode; // m
  final String? profileLabel; // p
  final String? profileId; // puid
  final String? systemState; // sys.s
  final String? systemMessage; // sys.m
  final int? controllerError; // sys.c
  final List<MachineWarning> warnings; // warn[]
  final GaggiMateProcess? process;
  final bool hasPressureControl; // cp
  final bool hasDimming; // cd
  final bool dualBoiler; // db: separate steam boiler
  final bool scaleConnected; // bc
  final double? scaleBattery; // sbat

  bool get isReady => systemState == null || systemState == 'ready';

  // Which boiler is the UI showing right now?
  //
  // Same rule as the machine's own UI
  // (DefaultUI.cpp: `dualBoiler && currentScreen == SCREEN_ID_STEAM_SCREEN`):
  // Only a machine with a separate steam boiler has two different
  // temperatures in steam mode at all. With one boiler `tt` already delivers
  // the steam target there (Controller::getTargetTemp); with two it keeps
  // delivering the brew target — then the steam target is only in `tst`.
  bool get showsSteamBoiler => dualBoiler && mode == GaggiMateMode.steam;

  double? get displayTemp => showsSteamBoiler ? currentSteamTemp : currentTemp;
  double? get displayTarget => showsSteamBoiler ? targetSteamTemp : targetTemp;

  MachineSystemStatus get systemStatus {
    switch (systemState) {
      case null:
      case 'ready':
        return (process?.active ?? false)
            ? MachineSystemStatus.busy
            : MachineSystemStatus.ready;
      case 'starting':
        return MachineSystemStatus.starting;
      case 'waiting':
        return MachineSystemStatus.waiting;
      case 'updating':
        return MachineSystemStatus.updating;
      case 'autotuning':
        return MachineSystemStatus.busy;
      case 'mismatch':
      case 'error':
        return MachineSystemStatus.error;
      default:
        return MachineSystemStatus.unknown;
    }
  }

  // Merge a frame onto this state. Always returns a new instance.
  GaggiMateStatus merge(Map<String, dynamic> frame) {
    final sys = frame.containsKey('sys') ? frame['sys'] : _absent;
    final sysMap = sys is Map ? Map<String, dynamic>.from(sys) : null;
    // sys null as a whole -> clear all three subfields; sys missing ->
    // keep everything; sys present -> subfields individually, same rule.
    Object? sysField(String key) {
      if (identical(sys, _absent)) return _absent;
      if (sysMap == null) return null;
      return sysMap.containsKey(key) ? sysMap[key] : _absent;
    }

    return GaggiMateStatus(
      currentTemp: _num(frame, 'ct', currentTemp),
      targetTemp: _num(frame, 'tt', targetTemp),
      currentSteamTemp: _num(frame, 'cst', currentSteamTemp),
      targetSteamTemp: _num(frame, 'tst', targetSteamTemp),
      pressure: _num(frame, 'pr', pressure),
      targetPressure: _num(frame, 'pt', targetPressure),
      flow: _num(frame, 'fl', flow),
      targetFlow: _num(frame, 'tf', targetFlow),
      weight: _num(frame, 'cw', weight),
      targetWeight: _num(frame, 'tw', targetWeight),
      mode: frame.containsKey('m')
          ? GaggiMateMode.fromCode((_asDouble(frame['m']))?.round())
          : mode,
      profileLabel: _string(frame, 'p', profileLabel),
      profileId: _string(frame, 'puid', profileId),
      systemState: _pickString(sysField('s'), systemState),
      systemMessage: _pickString(sysField('m'), systemMessage),
      controllerError: () {
        final raw = sysField('c');
        if (identical(raw, _absent)) return controllerError;
        return (_asDouble(raw))?.round();
      }(),
      warnings: frame.containsKey('warn')
          ? _parseWarnings(frame['warn'])
          : warnings,
      process: frame.containsKey('process')
          ? GaggiMateProcess.fromJson(frame['process'])
          : process,
      dualBoiler: _bool(frame, 'db', dualBoiler),
      hasPressureControl: _bool(frame, 'cp', hasPressureControl),
      hasDimming: _bool(frame, 'cd', hasDimming),
      scaleConnected: _bool(frame, 'bc', scaleConnected),
      scaleBattery: _num(frame, 'sbat', scaleBattery),
    );
  }

  static const _absent = Object();

  static double? _num(Map<String, dynamic> frame, String key, double? current) {
    if (!frame.containsKey(key)) return current;
    return _asDouble(frame[key]);
  }

  static String? _string(
    Map<String, dynamic> frame,
    String key,
    String? current,
  ) {
    if (!frame.containsKey(key)) return current;
    return frame[key]?.toString();
  }

  static String? _pickString(Object? raw, String? current) {
    if (identical(raw, _absent)) return current;
    return raw?.toString();
  }

  static bool _bool(Map<String, dynamic> frame, String key, bool current) {
    if (!frame.containsKey(key)) return current;
    return _asBool(frame[key]) ?? false;
  }

  static List<MachineWarning> _parseWarnings(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          MachineWarning(
            key: (entry['k'] ?? '').toString(),
            severity: (_asDouble(entry['l']) ?? 0).round(),
            // evt:brew:confirm has no `a` — there all listed warnings are
            // active by definition (see WS spec).
            active: _asBool(entry['a']) ?? true,
          ),
    ];
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

// The firmware sends flags sometimes as bool, sometimes as 0/1
// (pObj["a"] = 1).
bool? _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return null;
}
