import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/machine_profile.dart';
import '../../models/profile_draft.dart';
import '../../services/machine_address_fallback.dart';
import '../espresso_machine.dart';
import 'gaggimate_profile.dart';
import 'gaggimate_profile_codec.dart';
import 'gaggimate_status.dart';

// Transport layer so the service stays testable without a real machine:
// a WebSocket in production, a pair of streams in tests.
abstract class GaggiMateTransport {
  Stream<dynamic> get messages;
  // Completes once the WebSocket handshake is done; throws if it fails.
  // Without this there would be no way to tell whether a connection is
  // really up.
  Future<void> get ready;
  void send(String data);
  Future<void> close();
}

typedef GaggiMateTransportFactory = GaggiMateTransport Function(Uri uri);

class _WebSocketTransport implements GaggiMateTransport {
  _WebSocketTransport(Uri uri) : _channel = WebSocketChannel.connect(uri);

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<dynamic> get messages => _channel.stream;

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close() => _channel.sink.close();
}

// Connection to the GaggiMate (ESP32 retrofit for Gaggia/Rancilio).
//
// A single WebSocket channel, no REST: all messages are JSON objects with a
// `tp` field. Requests carry an `rid` that the response echoes. Based on
// docs/websocket-api.yaml from the GaggiMate repo — plus what only the
// source code shows (the web UI uses, among others, req:process:deactivate,
// req:process:clear and req:change-mode, which are missing from the spec).
class GaggiMateService extends ChangeNotifier implements EspressoMachine {
  GaggiMateService({
    required String host,
    GaggiMateTransportFactory? transportFactory,
    this.autoReconnect = true,
  }) : _host = host, // ignore: prefer_initializing_formals
       _transportFactory = transportFactory ?? _WebSocketTransport.new;

  static const _requestTimeout = Duration(seconds: 10);
  static const _baseReconnectDelay = Duration(seconds: 1);
  static const _maxReconnectDelay = Duration(seconds: 30);

  final GaggiMateTransportFactory _transportFactory;
  final bool autoReconnect;
  final _random = Random();

  String _host;
  GaggiMateTransport? _transport;

  // Silent re-discovery when the address is dead (see
  // MachineAddressFallback) — same mechanism as for the Meticulous. Not set
  // = off.
  MachineAddressFallback? addressFallback;
  void Function(String host, String? ip)? onAddressChanged;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _stopped = false;
  int _requestCounter = 0;

  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  GaggiMateStatus status = GaggiMateStatus.empty;

  // The machine blocked a start because of an error warning
  // (evt:brew:confirm) and is waiting for an answer. The dismissal is a
  // broadcast to ALL clients — display and app should close the same dialog
  // at the same time.
  List<MachineWarning>? pendingBrewConfirmation;

  List<GaggiMateProfile> profiles = const [];

  final _historyShotSaved = StreamController<int>.broadcast();

  // Fires with the id as soon as the machine has written a brew to its
  // history. Not ChangeNotifier state but an event: every shot counts
  // exactly once, even if the same id value arrived twice.
  Stream<int> get historyShotSaved => _historyShotSaved.stream;

  @override
  String get displayName => 'GaggiMate';

  @override
  String get machineKey => 'gaggimate';

  @override
  String get host => _host;

  @override
  MachineConnectionState connectionState = MachineConnectionState.disconnected;

  @override
  String? lastError;

  @override
  MachineCapabilities get capabilities => MachineCapabilities(
    temperatureSensors: 1,
    // Only the Pro with pressure control can do pressure and flow; the
    // machine reports this itself (cp) instead of us checking a model.
    pressure: status.hasPressureControl,
    flow: status.hasPressureControl,
    weight: status.scaleConnected,
    profiles: true,
    flush: true,
    steam: true,
  );

  @override
  MachineLiveState get liveState {
    final process = status.process;
    // Only a real coffee brew counts as an extraction — steam, water,
    // grinding and flushing run through the same process block.
    final brewing = process != null && process.active && process.isShot;
    return MachineLiveState(
      // In steam mode on a dual-boiler machine the steam boiler, otherwise
      // the brew boiler — see GaggiMateStatus.showsSteamBoiler.
      temperature: status.displayTemp,
      targetTemperature: status.displayTarget,
      pressure: status.hasPressureControl ? status.pressure : null,
      targetPressure: status.hasPressureControl ? status.targetPressure : null,
      flow: status.hasPressureControl ? status.flow : null,
      weight: status.scaleConnected ? status.weight : null,
      phase: process?.label ?? '',
      extracting: brewing,
      shotTime: process?.elapsed,
      activeProfileName: status.profileLabel,
      activeProfileId: status.profileId,
      systemStatus: connectionState == MachineConnectionState.connected
          ? status.systemStatus
          : MachineSystemStatus.unknown,
      systemMessage: status.systemMessage,
      warnings: status.warnings,
    );
  }

  // ---- Connection ---------------------------------------------------------

  @override
  void connect() {
    _stopped = false;
    _reconnectTimer?.cancel();
    _teardown();
    connectionState = MachineConnectionState.connecting;
    lastError = null;
    notifyListeners();

    try {
      final transport = _transportFactory(Uri.parse('ws://$_host/ws'));
      _transport = transport;
      _subscription = transport.messages.listen(
        _onMessage,
        onError: (Object error) {
          lastError = error.toString();
          _handleDrop(MachineConnectionState.error);
        },
        onDone: () => _handleDrop(MachineConnectionState.disconnected),
        cancelOnError: true,
      );
      // Only once the handshake is really done does the connection count as
      // open. `WebSocketChannel.connect` returns immediately and connects in
      // the background: going to `connected` right here shows a green dot
      // next to a machine that does not exist (seen on the simulator — the
      // pill stayed green while every attempt at the hostname failed).
      transport.ready.then(
        (_) {
          // Disconnected or reconnected in the meantime? Then this response
          // belongs to a transport that no longer exists.
          if (!identical(_transport, transport)) return;
          connectionState = MachineConnectionState.connected;
          _reconnectAttempts = 0;
          // See MeticulousSocketService: do not leave an old error message
          // under a green dot.
          lastError = null;
          addressFallback?.reset();
          notifyListeners();
          // The first full status frame arrives unsolicited; the profile
          // list has to be requested.
          unawaited(refreshProfiles());
        },
        onError: (Object error) {
          if (!identical(_transport, transport)) return;
          lastError = error.toString();
          _handleDrop(MachineConnectionState.error);
        },
      );
    } catch (e) {
      lastError = e.toString();
      _handleDrop(MachineConnectionState.error);
    }
  }

  @override
  void disconnect() {
    _stopped = true;
    _reconnectTimer?.cancel();
    _teardown();
    connectionState = MachineConnectionState.disconnected;
    notifyListeners();
  }

  // See MeticulousSocketService._recoverAddress — same rules.
  Future<void> _recoverAddress() async {
    final fallback = addressFallback;
    if (fallback == null || _stopped) return;
    final attemptedHost = _host;
    final next = await fallback.nextAddress(attemptedHost);
    if (next == null || next == _host || attemptedHost != _host) return;
    onAddressChanged?.call(next, fallback.lastIp);
    updateHost(next);
  }

  @override
  void updateHost(String host) {
    if (host == _host) return;
    _host = host;
    status = GaggiMateStatus.empty;
    profiles = const [];
    connect();
  }

  void _teardown() {
    _subscription?.cancel();
    _subscription = null;
    _transport?.close();
    _transport = null;
    _failPending('Connection closed');
  }

  void _handleDrop(MachineConnectionState state) {
    _teardown();
    connectionState = state;
    pendingBrewConfirmation = null;
    notifyListeners();
    // Only re-discover on an error: a normal close does not mean the
    // address is wrong.
    if (state == MachineConnectionState.error) unawaited(_recoverAddress());
    if (!_stopped && autoReconnect) _scheduleReconnect();
  }

  // Exponential, capped at 30 s — just like the machine's web UI. Without
  // this the app would reconnect every second to a sleeping machine.
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delay = Duration(
      milliseconds: min(
        _baseReconnectDelay.inMilliseconds * pow(2, _reconnectAttempts).toInt(),
        _maxReconnectDelay.inMilliseconds,
      ),
    );
    _reconnectAttempts++;
    _reconnectTimer = Timer(delay, () {
      if (!_stopped) connect();
    });
  }

  // ---- Messages -----------------------------------------------------------

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return; // Not JSON — nothing that concerns us.
    }
    if (decoded is! Map) return;
    final message = Map<String, dynamic>.from(decoded);
    final type = message['tp']?.toString();
    if (type == null) return;

    switch (type) {
      case 'evt:status':
        status = status.merge(message);
        if (connectionState != MachineConnectionState.connected) {
          connectionState = MachineConnectionState.connected;
        }
        notifyListeners();
        return;
      case 'evt:brew:confirm':
        pendingBrewConfirmation = GaggiMateStatus.empty.merge({
          'warn': message['warn'],
        }).warnings;
        notifyListeners();
        return;
      case 'evt:brew:confirm:cancel':
        pendingBrewConfirmation = null;
        notifyListeners();
        return;
      case 'evt:history-shot-saved':
        // The machine has written the brew to its flash and reports the id
        // — from now on it is available at /api/history/<id>.slog. The hook
        // for the import (see gaggimate_shot_sync_service.dart).
        final id = message['id'];
        if (id is num) _historyShotSaved.add(id.toInt());
        return;
    }

    // Response to a request: match via the echoed rid.
    final rid = message['rid']?.toString();
    if (rid != null) {
      _pending.remove(rid)?.complete(message);
    }
  }

  void _send(Map<String, dynamic> message) {
    final transport = _transport;
    if (transport == null) return;
    try {
      transport.send(jsonEncode(message));
    } catch (e) {
      lastError = e.toString();
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _request(
    String type, [
    Map<String, dynamic> extra = const {},
  ]) {
    final transport = _transport;
    if (transport == null) {
      return Future.error(StateError('GaggiMate not connected'));
    }
    final rid =
        '${_requestCounter++}-${_random.nextInt(1 << 32).toRadixString(36)}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[rid] = completer;
    _send({'tp': type, 'rid': rid, ...extra});
    return completer.future.timeout(
      _requestTimeout,
      onTimeout: () {
        _pending.remove(rid);
        throw TimeoutException('$type timed out');
      },
    );
  }

  void _failPending(String reason) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(StateError(reason));
    }
    _pending.clear();
  }

  // ---- Profiles -----------------------------------------------------------

  Future<List<GaggiMateProfile>> refreshProfiles() async {
    try {
      await fetchProfileList();
      return profiles;
    } catch (_) {
      // The list keeps the last known state — the cards should not go empty
      // because of a lost request.
      return profiles;
    }
  }

  // The raw profile JSONs as the machine keeps them. The list already
  // carries the full definitions (including phases) — so it is also the
  // source for the local copy (gaggimate_profile_sync_service.dart).
  // Always fills `profiles` too. The caching deliberately sits here and not
  // in refreshProfiles: the profile store fetches the list this way, and
  // without it the service, depending on order, would know nothing about
  // the profiles — and thus nothing about the brew temperature, which
  // depends on the selected profile.
  Future<List<Map<String, dynamic>>> fetchProfileList() async {
    final response = await _request('req:profiles:list');
    final raw = [
      for (final entry in (response['profiles'] as List?) ?? const [])
        if (entry is Map) Map<String, dynamic>.from(entry),
    ];
    profiles = [for (final entry in raw) GaggiMateProfile.fromJson(entry)];
    notifyListeners();
    return raw;
  }

  @override
  Future<List<MachineProfile>> fetchProfiles() async {
    final list = await refreshProfiles();
    return [
      for (final profile in list)
        if (!profile.utility) profile.toMachineProfile(),
    ];
  }

  // `select` activates the profile on the machine. Not to be confused with
  // `load`, which only fetches a profile for viewing (WS spec).
  //
  // Plus the switch to brew mode: this is the step that corresponds to the
  // Meticulous "start profile" — the machine then heats to the profile's
  // target and the Pre-Shot card goes from idle to heating/ready.
  @override
  Future<bool> selectProfile(String id) async {
    try {
      final response = await _request('req:profiles:select', {'id': id});
      final ok = response['error'] == null;
      if (ok) {
        changeMode(GaggiMateMode.brew);
        unawaited(refreshProfiles());
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  // The GaggiMate has no highlighting on the display without selecting —
  // the app-side selection in the Pre-Shot card is enough here.
  @override
  void highlightProfile(String id, String name) {}

  // Put a profile JSON on the machine. The firmware accepts it via
  // `req:profiles:save` and returns the saved profile — including the id it
  // assigned (an empty id creates a new profile, otherwise the existing one
  // is overwritten).
  @override
  Future<ProfileSaveResult> uploadProfile(Map<String, dynamic> json) async {
    try {
      final response = await _request('req:profiles:save', {'profile': json});
      final error = response['error'];
      if (error != null) return ProfileSaveResult.failed(error.toString());
      final saved = response['profile'];
      final id = saved is Map ? (saved['id'] ?? '').toString() : '';
      unawaited(refreshProfiles());
      return ProfileSaveResult.ok(id);
    } catch (e) {
      return ProfileSaveResult.failed('$e');
    }
  }

  // The firmware only reports an error if deleting really failed; an
  // unknown profile is not an error case for it.
  @override
  Future<ProfileSaveResult> deleteProfile(String id) async {
    try {
      final response = await _request('req:profiles:delete', {'id': id});
      final error = response['error'];
      if (error != null) return ProfileSaveResult.failed(error.toString());
      unawaited(refreshProfiles());
      return ProfileSaveResult.ok(id);
    } catch (e) {
      return ProfileSaveResult.failed('$e');
    }
  }

  // `req:profiles:reorder` with the ID list (WebSocketHandler.cpp); the
  // firmware stores it as setting `po` and then returns
  // `req:profiles:list` in that order.
  @override
  Future<ProfileSaveResult> reorderProfiles(List<String> ids) async {
    try {
      final response = await _request('req:profiles:reorder', {'order': ids});
      final error = response['error'];
      if (error != null) return ProfileSaveResult.failed(error.toString());
      unawaited(refreshProfiles());
      return const ProfileSaveResult.ok(null);
    } catch (e) {
      return ProfileSaveResult.failed('$e');
    }
  }

  // Source for ready-made GaggiMate profiles.
  @override
  List<({String label, String url})> get profileSites => const [
    (label: 'mybrewfolio.com', url: 'https://mybrewfolio.com/profiles'),
  ];

  // gaggimate_profile_codec.dart translates between the GaggiMate phase
  // format and the editable form — so the same editor works here too.
  @override
  bool get canEditProfiles => true;

  @override
  ProfileDraft draftFromProfile(Map<String, dynamic> json) =>
      gaggiMateDraftFromJson(json);

  @override
  Map<String, dynamic> profileFromDraft(ProfileDraft draft) =>
      gaggiMateJsonFromDraft(draft);

  @override
  ProfileDraft emptyDraft() => gaggiMateEmptyDraft();

  // Full profile definition for viewing — loads nothing onto the machine.
  Future<Map<String, dynamic>?> fetchProfileDetail(String id) async {
    try {
      final response = await _request('req:profiles:load', {'id': id});
      final profile = response['profile'];
      return profile is Map ? Map<String, dynamic>.from(profile) : null;
    } catch (_) {
      return null;
    }
  }

  // ---- Control ------------------------------------------------------------

  @override
  Future<bool> sendCommand(MachineCommand command) async {
    switch (command) {
      case MachineCommand.start:
        _send({'tp': 'req:process:activate'});
        return true;
      case MachineCommand.stop:
        _send({'tp': 'req:process:deactivate'});
        return true;
      case MachineCommand.flushStart:
        try {
          final response = await _request('req:flush:start');
          return response['success'] != false;
        } catch (_) {
          return false;
        }
      case MachineCommand.flushStop:
        // NOT `req:flush:stop` — in the firmware that calls
        // `onFlushRelease()` and only means "button released". It only
        // ends the hold phase of a flush WITHOUT a fixed duration
        // (Controller.cpp: `holdPhase = duration == 0`); if a flush duration
        // is set, it does nothing and the flush runs to the end. Measured on
        // the simulator: sent after 1.4 s, it still ran the full 5 s + drain
        // — `req:process:deactivate` on the other hand ended it after 0.2 s.
        _send({'tp': 'req:process:deactivate'});
        return true;
      // The GaggiMate has neither a tare action over the channel nor its
      // own preheat — it holds the temperature in standby anyway.
      case MachineCommand.tare:
      case MachineCommand.preheat:
        return false;
    }
  }

  // Clear a finished process. Until that happens it stays in the status
  // (so "finished" survives an app restart).
  void clearProcess() => _send({'tp': 'req:process:clear'});

  void changeMode(GaggiMateMode mode) =>
      _send({'tp': 'req:change-mode', 'mode': mode.code});

  // Answer to evt:brew:confirm: start despite an active error warning.
  void confirmBrew() {
    pendingBrewConfirmation = null;
    _send({'tp': 'req:process:activate', 'ignoreWarnings': true});
    notifyListeners();
  }

  void cancelBrew() {
    pendingBrewConfirmation = null;
    _send({'tp': 'req:brew:confirm:cancel'});
    notifyListeners();
  }

  @override
  void dispose() {
    _stopped = true;
    _reconnectTimer?.cancel();
    _teardown();
    _historyShotSaved.close();
    super.dispose();
  }
}
