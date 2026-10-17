import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../machines/espresso_machine.dart';
import '../models/machine_profile.dart';
import '../models/profile_draft.dart';
import '../models/profile_detail.dart';
import '../models/machine_sensors.dart';
import '../models/machine_status.dart';
import 'machine_address_fallback.dart';

// MachineConnectionState now lives with the shared interface
// (lib/machines/espresso_machine.dart), but is still re-exported here: the
// Meticulous UI has always imported it from here.
export '../machines/espresso_machine.dart' show MachineConnectionState;

// Holds the latest live values + a short rolling window for the
// temperature card. By design it need not be gapless — the complete time
// series comes from the debug file after the shot ends.
class MeticulousSocketService extends ChangeNotifier
    implements EspressoMachine {
  // ignore: prefer_initializing_formals
  MeticulousSocketService({required String hostname}) : _hostname = hostname;

  // ~400s rolling window for the live chart (empirically ~0.1057s/sample,
  // see _chartSampleIntervalSeconds in temperature_tile.dart).
  static const int _maxSamples = 3800;

  String _hostname;
  io.Socket? _socket;

  // Silent fallback search when the stored address does not answer (see
  // MachineAddressFallback). Without this field set the service behaves as
  // before — tests and the simulator do not need it.
  MachineAddressFallback? addressFallback;
  // Called when the fallback search found a different address, so
  // main.dart writes it into the settings.
  void Function(String host, String? ip)? onAddressChanged;

  @override
  MachineConnectionState connectionState = MachineConnectionState.disconnected;
  MachineStatus? latestStatus;
  MachineSensors? latestSensors;
  @override
  String? lastError;

  // Debounced `state` value for session detection (TemperatureTile): a
  // single deviating tick is ignored, it is only taken over after
  // `_stateConfirmTicks` equal values in a row. Reacts to a real session
  // (stays on "brewing" for minutes) practically without delay, but filters
  // a short status outlier (observed e.g. right after `action/reset`, which
  // can briefly pass through a wrong `state` before jumping back to
  // "idle" — otherwise the target display in the TemperatureTile flickers).
  static const _stateConfirmTicks = 3;
  String _confirmedSessionState = 'idle';
  String? _pendingSessionState;
  int _pendingSessionStateCount = 0;
  String get confirmedSessionState => _confirmedSessionState;

  // The target temperature is not live in the `status` event (its
  // `profile` field is only a status string like "idle"), but fixed in the
  // profile itself (`temperature` field, verified via REST). So reload it
  // only once on profile change instead of on every status tick.
  double? targetTemperature;
  // Profile whose target was SUCCESSFULLY loaded. A failed attempt (network
  // down, timeout, HTTP error) must NOT end up here, otherwise
  // `targetTemperature` stays null until the next profile change — and with
  // it hero ring, stabilized ring, ETA and target display in the
  // TemperatureTile stay empty for good, even though sensor data keeps
  // flowing.
  String? _fetchedTargetProfileId;
  DateTime? _lastTargetFetchAttemptAt;
  static const _targetFetchRetryDelay = Duration(seconds: 5);

  // `heater_status` (raw: bare number, seconds) runs ONLY during the
  // standalone `preheat` action (target ~70°C, independent of the profile
  // target `targetTemperature`!). Do not use as ETA for the profile target
  // — only to detect that active heating is happening (during a pure
  // preheat `status.name`/`phase` wrongly stays "idle", see
  // github.com/nickwilsonr/meticulous-addon _has_active_preheat()).
  double? _lastPreheatCountdown;
  DateTime? _lastPreheatCountdownAt;

  double? get preheatCountdownSeconds => _lastPreheatCountdown;

  // Water detection (meticulous-backend, head stage "water detection"):
  // before heating, the machine checks the raw detector `w_stat`. With
  // water the stage passes within one tick (never seen in captures);
  // without it the machine waits and asks to "Pour water and click to
  // continue". `w_stat` alone is not trusted outside that stage: its idle
  // value is unverified, and a missing field must not raise an alarm.
  bool? lastWaterStatus;

  bool get isWaterMissing {
    final phase = latestStatus?.phase.toLowerCase() ?? '';
    if (phase.startsWith('pour water')) return true;
    return phase == 'water detection' && lastWaterStatus == false;
  }

  bool get isPreheatActive =>
      _lastPreheatCountdown != null &&
      _lastPreheatCountdown! > 0 &&
      _lastPreheatCountdownAt != null &&
      DateTime.now().difference(_lastPreheatCountdownAt!) <
          const Duration(seconds: 2);

  final Queue<MachineSensors> _recentSensors = Queue();
  UnmodifiableListView<MachineSensors> get recentSensors =>
      UnmodifiableListView(_recentSensors);

  String get hostname => _hostname;

  @override
  void connect() {
    _socket?.dispose();
    connectionState = MachineConnectionState.connecting;
    lastError = null;
    notifyListeners();

    _socket = io.io(
      'http://$_hostname',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setTimeout(8000)
          .build(),
    );

    _socket!
      ..onConnect((_) {
        connectionState = MachineConnectionState.connected;
        // Clear the message of the last failed attempt: otherwise "timeout"
        // still shows under the green dot in the settings, although the
        // connection has long been up.
        lastError = null;
        addressFallback?.reset();
        notifyListeners();
      })
      ..onDisconnect((_) {
        connectionState = MachineConnectionState.disconnected;
        notifyListeners();
      })
      ..onConnectError((err) {
        connectionState = MachineConnectionState.error;
        lastError = err.toString();
        notifyListeners();
        // Socket.IO retries by itself — the fallback search throttles
        // itself (cooldown + already tried addresses), so it may run along
        // on every failed attempt.
        unawaited(_recoverAddress());
      })
      ..onError((err) {
        lastError = err.toString();
        notifyListeners();
      })
      ..on('status', (data) {
        latestStatus = MachineStatus.fromJson(
          Map<String, dynamic>.from(data as Map),
        );
        final profileId = latestStatus!.profileId;
        if (profileId.isNotEmpty) {
          _maybeFetchTargetTemperature(profileId);
        }
        final rawState = latestStatus!.state;
        if (rawState == _pendingSessionState) {
          _pendingSessionStateCount++;
        } else {
          _pendingSessionState = rawState;
          _pendingSessionStateCount = 1;
        }
        if (_pendingSessionStateCount >= _stateConfirmTicks) {
          _confirmedSessionState = rawState;
        }
        notifyListeners();
      })
      ..on('sensors', (data) {
        final raw = Map<String, dynamic>.from(data as Map);
        final sample = MachineSensors.fromJson(raw);
        lastWaterStatus = raw['w_stat'] as bool?;
        latestSensors = sample;
        _recentSensors.addLast(sample);
        if (_recentSensors.length > _maxSamples) {
          _recentSensors.removeFirst();
        }
        notifyListeners();
      })
      ..on('heater_status', (data) {
        if (data is num) {
          _lastPreheatCountdown = data.toDouble();
          _lastPreheatCountdownAt = DateTime.now();
          notifyListeners();
        }
      })
      ..connect();
  }

  // Loads the profile target as soon as the profile changes — and on
  // failure retries every _targetFetchRetryDelay, instead of giving up for
  // the rest of the session after a single lost request. Status events
  // arrive ~9x/s, hence the throttling.
  void _maybeFetchTargetTemperature(String profileId) {
    if (profileId == _fetchedTargetProfileId) return;
    final now = DateTime.now();
    if (_lastTargetFetchAttemptAt != null &&
        now.difference(_lastTargetFetchAttemptAt!) < _targetFetchRetryDelay) {
      return;
    }
    _lastTargetFetchAttemptAt = now;
    _fetchTargetTemperature(profileId);
  }

  Future<void> _fetchTargetTemperature(String profileId) async {
    try {
      final response = await http
          .get(Uri.parse('http://$_hostname/api/v1/profile/get/$profileId'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final temp = json['temperature'];
      if (temp is num) {
        targetTemperature = temp.toDouble();
        _fetchedTargetProfileId = profileId;
        notifyListeners();
      }
    } catch (_) {
      // No crash on network errors — target temp stays at the last known
      // value (or null); since _fetchedTargetProfileId was not set, the next
      // status tick after _targetFetchRetryDelay tries again.
    }
  }

  // Short profile list for the profile cards in the home tab. Without
  // ?full=true — it already returns name/temperature/final_weight/
  // display.accentColor without dragging along the much heavier stages.
  @override
  Future<List<MachineProfile>> fetchProfiles() async {
    final response = await http
        .get(Uri.parse('http://$_hostname/api/v1/profile/list'))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw Exception('Profile list: HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as List;
    return json
        .map(
          (e) => MachineProfile.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  // Complete profile definition for viewing (stages, variables, description).
  // Read-only access — loads/heats nothing (unlike loadProfile).
  Future<ProfileDetail> fetchProfileDetail(String id) async {
    final response = await http
        .get(Uri.parse('http://$_hostname/api/v1/profile/get/$id'))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('Profile: HTTP ${response.statusCode}');
    }
    return ProfileDetail.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      ),
    );
  }

  // WARNING (verified live): immediately starts real heating to the
  // profile's target temperature, not just "highlighting". Only call after
  // confirming there is water, just like preheat/start. For highlighting
  // without heating use hoverProfile() below instead.
  Future<bool> loadProfile(String id) async {
    try {
      final response = await http
          .get(Uri.parse('http://$_hostname/api/v1/profile/load/$id'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  // Store a profile permanently on the machine (POST /api/v1/profile/save)
  // — this is the path for "upload JSON file". Unlike /profile/load this
  // heats nothing. On error returns the machine's text, not just "didn't
  // work": the body usually says what is wrong with the profile.
  @override
  String get machineKey => 'meticulous';

  // The two sites that offer ready-made Meticulous profiles.
  @override
  List<({String label, String url})> get profileSites => const [
    (label: 'metprofiles.link', url: 'https://metprofiles.link/'),
    (
      label: 'community.meticuloushome.com',
      url: 'https://community.meticuloushome.com/brew-profiles',
    ),
  ];

  // The profile editor produces exactly this format — so no translation is
  // needed here, unlike the GaggiMate.
  @override
  bool get canEditProfiles => true;

  @override
  ProfileDraft draftFromProfile(Map<String, dynamic> json) =>
      ProfileDraft.fromJson(json);

  @override
  Map<String, dynamic> profileFromDraft(ProfileDraft draft) => draft.toJson();

  @override
  ProfileDraft emptyDraft() => ProfileDraft.empty();

  @override
  Future<ProfileSaveResult> uploadProfile(Map<String, dynamic> json) async {
    final result = await saveProfile(json);
    return result.ok
        ? ProfileSaveResult.ok((json['id'] ?? '').toString())
        : ProfileSaveResult.failed(result.error ?? 'Upload failed');
  }

  // DELETE /api/v1/profile/delete/{id}. A 404 means the machine does not
  // hold the profile (anymore) anyway — for the caller the same result as
  // a successful delete.
  @override
  Future<ProfileSaveResult> deleteProfile(String id) async {
    try {
      final response = await http
          .delete(Uri.parse('http://$_hostname/api/v1/profile/delete/$id'))
          .timeout(const Duration(seconds: 15));
      if ((response.statusCode >= 200 && response.statusCode < 300) ||
          response.statusCode == 404) {
        return ProfileSaveResult.ok(id);
      }
      final body = response.body.trim();
      return ProfileSaveResult.failed(
        body.isEmpty
            ? 'HTTP ${response.statusCode}'
            : 'HTTP ${response.statusCode}: ${body.length > 160 ? '${body.substring(0, 160)}…' : body}',
      );
    } catch (e) {
      return ProfileSaveResult.failed('$e');
    }
  }

  // The Meticulous keeps the order as the user setting `profile_order`
  // (meticulous-backend api/settings.py); after setting it, it reloads its
  // profile list, display and /profile/list follow.
  @override
  Future<ProfileSaveResult> reorderProfiles(List<String> ids) async {
    try {
      final response = await http
          .post(
            Uri.parse('http://$_hostname/api/v1/settings'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'profile_order': ids}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const ProfileSaveResult.ok(null);
      }
      return ProfileSaveResult.failed('HTTP ${response.statusCode}');
    } catch (e) {
      return ProfileSaveResult.failed('$e');
    }
  }

  Future<({bool ok, String? error})> saveProfile(
    Map<String, dynamic> profile,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('http://$_hostname/api/v1/profile/save'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(profile),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (ok: true, error: null);
      }
      final body = response.body.trim();
      return (
        ok: false,
        error: body.isEmpty
            ? 'HTTP ${response.statusCode}'
            : 'HTTP ${response.statusCode}: ${body.length > 160 ? '${body.substring(0, 160)}…' : body}',
      );
    } catch (e) {
      return (ok: false, error: '$e');
    }
  }

  // Pure highlighting/scrolling to a profile on the machine display,
  // WITHOUT loading or heating — Socket.IO event (no REST call), found via
  // github.com/MeticulousHome/pyMeticulous (api.py: send_profile_hover
  // -> sio.emit("profileHover", ...)). Exactly the behavior of the official
  // app: tapping a profile in the list only scrolls there, starts nothing.
  void hoverProfile(String id, String name) {
    _socket?.emit('profileHover', {'id': id, 'name': name});
  }

  // Machine actions. The machine reveals its allowed list itself when you
  // send an invalid action: reset, abort, start, stop, tare,
  // scale_master_calibration, preheat, continue, home, purge.
  //
  // WARNING — two traps, both verified live:
  //
  // 1. `{"status": "ok"}` only means "action accepted", NOT "had an
  //    effect". A 200 is therefore no proof of effect.
  //
  // 2. The brew at the "click to start" gate is triggered by `continue`,
  //    NOT `start`. The machine is already in the middle of a sequence there
  //    (`state: brewing`) and is just waved on; `start` refers to starting
  //    a sequence from idle and does nothing at the gate (tested multiple
  //    times, via POST and GET). Recording: 316 ms after `continue` the
  //    phase jumps to `retracting` — identical to the physical dial.
  //
  // GET vs. POST: the official actions in @meticulous-home/espresso-api
  // (`executeAction`) use GET. purge/home/reset go through a raw POST there
  // and are already confirmed to work that way here (see
  // CommandButtonsRow) — hence the split.
  static const _getActions = {'start', 'stop', 'preheat', 'tare', 'continue'};

  Future<bool> triggerAction(String action) async {
    try {
      final uri = Uri.parse('http://$_hostname/api/v1/action/$action');
      final response = _getActions.contains(action)
          ? await http.get(uri).timeout(const Duration(seconds: 5))
          : await http.post(uri).timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  // The stored address does not answer: get the next address and, if there
  // is one, move there. The UI only learns about it through the then
  // changing hostname (no message by design).
  Future<void> _recoverAddress() async {
    final fallback = addressFallback;
    if (fallback == null) return;
    final attemptedHost = _hostname;
    final next = await fallback.nextAddress(attemptedHost);
    // Has someone entered an address by hand meanwhile? Then the result
    // belongs to a question that has been settled.
    if (next == null || next == _hostname || attemptedHost != _hostname) return;
    onAddressChanged?.call(next, fallback.lastIp);
    updateHostname(next);
  }

  void updateHostname(String newHostname) {
    if (newHostname == _hostname) return;
    _hostname = newHostname;
    connect();
  }

  void disconnectSocket() {
    _socket?.dispose();
    _socket = null;
    connectionState = MachineConnectionState.disconnected;
    notifyListeners();
  }

  // ---- EspressoMachine ----------------------------------------------------
  // The Meticulous UI keeps accessing the rich fields above directly (four
  // sensors, preheat countdown, hoverProfile). This block is the shared
  // view that GaggiMate and Meticulous have in common — pill status,
  // warnings, start/stop.

  @override
  String get displayName => 'Meticulous';

  @override
  String get host => _hostname;

  @override
  MachineCapabilities get capabilities => const MachineCapabilities(
    temperatureSensors: 4,
    pressure: true,
    flow: true,
    weight: true,
    profiles: true,
  );

  @override
  MachineLiveState get liveState {
    final status = latestStatus;
    if (status == null) {
      return MachineLiveState(targetTemperature: targetTemperature);
    }
    return MachineLiveState(
      temperature: status.temp,
      targetTemperature: targetTemperature,
      pressure: status.pressure,
      flow: status.flow,
      weight: status.weight,
      phase: status.phase,
      extracting: status.extracting,
      shotTime: Duration(milliseconds: status.timeMs),
      activeProfileName: status.loadedProfile.isEmpty
          ? null
          : status.loadedProfile,
      activeProfileId: status.profileId.isEmpty ? null : status.profileId,
      systemStatus: _systemStatus(status),
      // The Meticulous has no warnings array like GaggiMate; the only
      // comparable value is the water sensor — and that is not fitted on
      // single-dose machines, so it is no use as a warning.
      warnings: const [],
    );
  }

  MachineSystemStatus _systemStatus(MachineStatus status) {
    if (connectionState != MachineConnectionState.connected) {
      return MachineSystemStatus.unknown;
    }
    if (status.extracting || isPreheatActive) return MachineSystemStatus.busy;
    return status.phase == 'idle'
        ? MachineSystemStatus.ready
        : MachineSystemStatus.busy;
  }

  @override
  void updateHost(String host) => updateHostname(host);

  @override
  void disconnect() => disconnectSocket();

  @override
  Future<bool> selectProfile(String id) => loadProfile(id);

  @override
  void highlightProfile(String id, String name) => hoverProfile(id, name);

  @override
  Future<bool> sendCommand(MachineCommand command) {
    switch (command) {
      case MachineCommand.start:
        return triggerAction('start');
      case MachineCommand.stop:
        return triggerAction('stop');
      case MachineCommand.tare:
        return triggerAction('tare');
      case MachineCommand.preheat:
        return triggerAction('preheat');
      // The Meticulous has no flush as a separate action — `purge` is
      // ejecting the remainder, not a flush through the group.
      case MachineCommand.flushStart:
      case MachineCommand.flushStop:
        return Future.value(false);
    }
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }
}
