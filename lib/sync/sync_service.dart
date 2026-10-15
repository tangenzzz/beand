import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

import 'package:http/http.dart' as http;

import '../database/database.dart';
import 'blobs/blob_sync.dart';
import 'blobs/blossom_client.dart';
import '../services/backup_service.dart' show BackupSyncInfo;
import 'crypto/nip49.dart';
import 'engine/account_wipe.dart';
import 'engine/sync_engine.dart';
import 'engine/sync_state_store.dart';
import 'identity/identity.dart';
import 'identity/key_store.dart';
import 'nostr/relay_connection.dart';
import 'nostr/relay_pool.dart';

// The only place the UI knows about sync. Holds keys, relay list and state
// and decides WHEN to sync — never blocking the UI thread, never with OS
// background jobs:
//
//  * at app start and when it comes back to the foreground,
//  * a few seconds after local changes (batched),
//  * on demand ("Sync now").

enum SyncPhase { off, idle, syncing, error }

/// Public relays for everyone who has no server of their own. Content is
/// encrypted; only metadata (keys, timestamps, size) remains visible.
const defaultSyncRelays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
];

/// Public photo servers (Blossom) that accept encrypted files — checked with
/// test/sync/blossom_probe_test.dart. The big media hosts (nostr.build,
/// primal, blossom.band, nostrcheck) only accept images/videos, no encrypted
/// files. How long the servers keep anything is unclear — it does not need
/// to be long: afterwards a photo is on every device that fetched it.
const defaultBlobServers = [
  'https://nostr.download',
  'https://blossom.yakihonne.com',
];

class SyncService extends ChangeNotifier with WidgetsBindingObserver {
  SyncService({
    required this.db,
    required this.keyStore,
    required this.stateStore,
    this.connector,
    this.settings,
    this.settingsSources = const [],
    this.docsDir,
    this.httpClient,
    this.devicePresence = true,
    this.changeDelay = const Duration(seconds: 5),
    this.idleDisconnect = const Duration(minutes: 1),
    this.retryDelay = const Duration(seconds: 30),
  });

  final AppDatabase db;
  final SyncKeyStore keyStore;
  final SyncStateStore stateStore;
  final WebSocketConnector? connector;

  /// Settings that are synced along (null = none, e.g. in tests).
  final SettingsBridge? settings;

  /// Who notifies when settings change (AppSettings, AiSettings) — then a
  /// sync runs after a short pause.
  final List<Listenable> settingsSources;

  /// Where downloaded photos go (the app's documents folder).
  final Future<Directory> Function()? docsDir;

  /// For tests (photo server in the test process).
  final http.Client? httpClient;

  /// Device presence (SyncEngine.devicePresence) — off only in tests.
  final bool devicePresence;
  BlobSync? _blobs;

  /// Delay after a local change before sending — several changes in a row
  /// go out together this way.
  final Duration changeDelay;

  /// Close connections when there has been nothing to do for a while.
  final Duration idleDisconnect;

  /// A run left records unsent (all servers failed, or none accepted them):
  /// try again by itself after this long, doubling each time up to
  /// [maxRetryDelay]. Otherwise they would wait for the next change or the
  /// next return to the app.
  final Duration retryDelay;
  static const maxRetryDelay = Duration(minutes: 15);

  SyncStateData _state = SyncStateData();
  SyncIdentity? _identity;
  String? _deviceId;
  RelayPool? _pool;
  SyncEngine? _engine;
  StreamSubscription<int>? _pendingSub;
  Timer? _changeTimer;
  Timer? _idleTimer;
  Timer? _retryTimer;
  int _retries = 0;
  bool _inBackground = false;
  Future<void>? _running;
  bool _again = false;
  bool _againForce = false;
  bool _initialized = false;

  SyncPhase _phase = SyncPhase.off;
  String? _error;
  int _pending = 0;
  int? _received;

  bool get enabled => _state.enabled;
  SyncPhase get phase => _phase;

  /// Last error message (readable, without jargon), null = all good.
  String? get error => _error;
  DateTime? get lastSuccessAt => _state.lastSuccessAt;

  /// Pending local changes.
  int get pending => _pending;

  /// During a sync: how many records have been fetched so far.
  int? get received => _received;
  List<String> get relays => List.unmodifiable(_state.relays);
  SyncIdentity? get identity => _identity;
  RelayStatus relayStatus(String url) =>
      _pool?.statusOf(url) ?? const RelayStatus(RelayState.idle);

  Future<void> init() async {
    _state = await stateStore.load();
    _deviceId = db.deviceId ?? await keyStore.deviceId();
    _identity = await keyStore.readIdentity();
    if (!_state.blobDefaultsApplied) {
      await _update((s) {
        s.blobServers = [
          ...defaultBlobServers.where((d) => !s.blobServers.contains(d)),
          ...s.blobServers,
        ];
        s.blobDefaultsApplied = true;
      });
      // Photos that were only on the device so far get uploaded now.
      if (_identity != null) await db.syncDao.markUnsentPhotosPending();
    }
    if (_state.resendAll) {
      // Only set after a restore: the backup state wins.
      await db.syncDao.restampAll(
        clock.now().millisecondsSinceEpoch,
        _deviceId,
      );
      await _update((s) => s.resendAll = false);
    }
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _pendingSub = db.syncDao.watchPendingCount().listen(_onPendingChanged);
    for (final source in settingsSources) {
      source.addListener(_onSettingsChanged);
    }
    if (_state.enabled && _identity != null) {
      _start();
      unawaited(syncNow(force: false));
    }
    notifyListeners();
  }

  // Change state: reload fresh, modify, save. The engine writes the same
  // file during a sync (last sync per server).
  Future<void> _update(void Function(SyncStateData s) change) async {
    final s = await stateStore.load();
    change(s);
    await stateStore.save(s);
    _state = s;
  }

  void _start() {
    final identity = _identity!;
    _pool?.dispose();
    _pool = RelayPool(identity: identity, connector: connector)
      ..setUrls(_state.relays)
      ..addListener(notifyListeners);
    final docs = docsDir;
    _blobs = docs == null
        ? null
        : BlobSync(
            client: BlossomClient(identity: identity, client: httpClient),
            servers: [..._state.blobServers],
            docsDir: docs,
          );
    _engine = SyncEngine(
      db: db,
      identity: identity,
      pool: _pool!,
      deviceId: _deviceId!,
      stateStore: stateStore,
      settings: settings,
      blobs: _blobs,
      devicePresence: devicePresence,
    );
    _phase = SyncPhase.idle;
  }

  void _stop() {
    _changeTimer?.cancel();
    _idleTimer?.cancel();
    _retryTimer?.cancel();
    _retries = 0;
    _pool?.removeListener(notifyListeners);
    _pool?.dispose();
    _pool = null;
    _engine = null;
    _phase = SyncPhase.off;
    _error = null;
    _received = null;
  }

  void _onPendingChanged(int count) {
    _pending = count;
    notifyListeners();
    if (count > 0 && enabled && _engine != null && !_disposed) {
      _changeTimer?.cancel();
      _changeTimer = Timer(changeDelay, () => unawaited(syncNow(force: false)));
    }
  }

  // A setting has changed. During a sync this can also be the adoption from
  // the other device — then check once afterwards.
  var _settingsChangedDuringRun = false;

  void _onSettingsChanged() {
    if (!enabled || _engine == null || _disposed) return;
    if (_running != null) {
      _settingsChangedDuringRun = true;
      return;
    }
    _changeTimer?.cancel();
    _changeTimer = Timer(changeDelay, () => unawaited(syncNow(force: false)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // In the background Android cuts the network; the connections would look
    // open afterwards but be dead — on return all relays would first run
    // into an error (briefly red). So close cleanly when leaving …
    if (state == AppLifecycleState.paused) {
      _inBackground = true;
      unawaited(_pool?.closeAll());
    }
    // … and reconnect fresh on return, without the backoff after errors
    // that were only caused by the background.
    if (state == AppLifecycleState.resumed) {
      _inBackground = false;
      if (enabled && _engine != null) unawaited(syncNow());
    }
  }

  /// Turn sync on. The very first time, the key is created here; everything
  /// existing is then uploaded once.
  Future<void> enable() async {
    assert(_initialized);
    if (_identity == null) {
      final created = SyncIdentity.generate();
      await keyStore.writeIdentity(created);
      _identity = created;
      await _update((s) => s.lastSync.clear());
      await db.syncDao.markAllPending();
    }
    await _update((s) {
      if (s.relays.isEmpty) s.relays = [...defaultSyncRelays];
      s.enabled = true;
    });
    _start();
    notifyListeners();
    await syncNow();
  }

  /// Off means off: no more connections. The key stays, so the same account
  /// continues when turned back on.
  Future<void> disable() async {
    await _update((s) => s.enabled = false);
    _stop();
    notifyListeners();
  }

  /// Delete everything of this key from relays and photo servers, then
  /// forget the key on this device and turn sync off. The data in the app
  /// stays; with a new or adopted key it is uploaded again. Cannot be undone.
  Future<WipeReport> deleteServerData() async {
    final identity = _identity!;
    _stop();
    await _running;
    final pool = RelayPool(identity: identity, connector: connector)
      ..setUrls(_state.relays);
    final blossom = BlossomClient(identity: identity, client: httpClient);
    final WipeReport report;
    try {
      report = await AccountWipe(
        identity: identity,
        pool: pool,
        blossom: blossom,
        blobServers: [..._state.blobServers],
        knownBlobShas: await db.syncDao.uploadedBlobShas(),
      ).run();
    } finally {
      pool.dispose();
      if (httpClient == null) blossom.close();
    }
    debugPrint('Sync: $report');
    await keyStore.deleteIdentity();
    _identity = null;
    _blobs = null;
    await _update((s) {
      s.enabled = false;
      s.lastSync.clear();
    });
    // The photos on the servers are gone — forget the references so they
    // are uploaded again with the next key.
    await db.syncDao.reuploadLocalPhotos();
    notifyListeners();
    return report;
  }

  /// Sync now. [force]: also try servers that are currently paused due to
  /// errors (when the user taps it).
  Future<void> syncNow({bool force = true}) {
    if (_engine == null) return Future.value();
    if (_running != null) {
      // Run again afterwards — and keep a forced request forced (the return
      // to the app may come while a run is still going).
      _again = true;
      _againForce = _againForce || force;
      return _running!;
    }
    return _running = _run(force).whenComplete(() {
      _running = null;
      if (_settingsChangedDuringRun) {
        _settingsChangedDuringRun = false;
        _onSettingsChanged();
      }
      if (_again) {
        final again = _againForce;
        _again = false;
        _againForce = false;
        unawaited(syncNow(force: again));
      }
    });
  }

  Future<void> _run(bool force) async {
    final engine = _engine!;
    _idleTimer?.cancel();
    _retryTimer?.cancel();
    var incomplete = false;
    _phase = SyncPhase.syncing;
    _received = 0;
    notifyListeners();
    try {
      final report = await engine.run(
        force: force,
        onProgress: (n) {
          _received = n;
          notifyListeners();
        },
      );
      debugPrint('Sync: $report');
      await _blobs?.checkServers();
      final allFailed =
          relays.isNotEmpty && report.failedRelays.length == relays.length;
      incomplete = allFailed || report.notSent > 0;
      if (allFailed) {
        _phase = SyncPhase.error;
        _error = relays.length == 1
            ? (relayStatus(relays.single).message ?? "Can't reach the server.")
            : "Can't reach any server.";
      } else {
        _phase = SyncPhase.idle;
        _error = null;
        await _update((s) => s.lastSuccessAt = DateTime.now());
      }
    } catch (e) {
      debugPrint('Sync failed: $e');
      _phase = SyncPhase.error;
      _error = 'Sync failed.';
      incomplete = true;
    } finally {
      _received = null;
      if (_engine == engine && !_disposed) {
        _idleTimer = Timer(idleDisconnect, () => _pool?.closeAll());
        if (incomplete) {
          _scheduleRetry();
        } else {
          _retries = 0;
        }
      }
      notifyListeners();
    }
  }

  // In the background Android has no network for us anyway — the return to
  // the app syncs again by itself.
  void _scheduleRetry() {
    if (_inBackground) return;
    final delay = retryDelay * (1 << _retries.clamp(0, 10));
    _retries++;
    _retryTimer = Timer(
      delay < maxRetryDelay ? delay : maxRetryDelay,
      () => unawaited(syncNow(force: false)),
    );
  }

  // ---- Servers (relays) ----

  /// Validates and normalizes an address; null = invalid. Without a ws:// or
  /// wss:// prefix: encrypted (wss), except for addresses on the local
  /// network (home network, Tailscale, *.local, host name without a dot) — a
  /// server at home usually has no certificate.
  static String? normalizeRelayUrl(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) {
      final host = Uri.tryParse('ws://$text')?.host ?? '';
      text = '${isLocalHost(host) ? 'ws' : 'wss'}://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        (uri.scheme != 'wss' && uri.scheme != 'ws') ||
        uri.host.isEmpty) {
      return null;
    }
    var result = uri.toString();
    if (result.endsWith('/') && uri.path == '/') {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// Address on the local network: home network, Tailscale, *.local, or a
  /// bare host name.
  static bool isLocalHost(String host) {
    if (host.isEmpty) return false;
    if (host == 'localhost' || host.endsWith('.local')) return true;
    if (!host.contains('.')) return true; // bare host name
    final parts = host.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 ||
        a == 127 ||
        (a == 192 && b == 168) ||
        (a == 172 && b >= 16 && b <= 31) ||
        isTailscaleHost(host);
  }

  /// Tailscale assigns addresses from 100.64.0.0/10.
  static bool isTailscaleHost(String host) {
    final parts = host.split('.').map(int.tryParse).toList();
    return parts.length == 4 &&
        parts[0] == 100 &&
        parts[1] != null &&
        parts[1]! >= 64 &&
        parts[1]! <= 127;
  }

  Future<bool> addRelay(String input) async {
    final url = normalizeRelayUrl(input);
    if (url == null || _state.relays.contains(url)) return false;
    await _update((s) => s.relays = [...s.relays, url]);
    await _sendEverythingToNewServers();
    await _relaysChanged();
    return true;
  }

  Future<void> removeRelay(String url) async {
    await _update((s) {
      s.relays = [...s.relays]..remove(url);
      s.lastSync.remove(url);
    });
    await _relaysChanged();
  }

  Future<void> restoreDefaultRelays() async {
    await _update((s) {
      final extra = s.relays.where((r) => !defaultSyncRelays.contains(r));
      s.relays = [...defaultSyncRelays, ...extra];
    });
    await _sendEverythingToNewServers();
    await _relaysChanged();
  }

  // A new server does not know the existing data — otherwise only what
  // changes is sent. So send everything once; the other servers just
  // replace the same state.
  Future<void> _sendEverythingToNewServers() async {
    if (_identity != null) await db.syncDao.markAllPending();
  }

  Future<void> _relaysChanged() async {
    _pool?.setUrls(_state.relays);
    notifyListeners();
    if (enabled) unawaited(syncNow());
  }

  // ---- Photo servers (Blossom) ----

  List<String> get blobServers => List.unmodifiable(_state.blobServers);

  /// Last error message of a photo server, null = ok/unknown.
  String? blobServerError(String url) => _blobs?.errors[url];

  /// Photo server worked last time (display green).
  bool blobServerOk(String url) => _blobs?.ok.contains(url) ?? false;

  /// Validate an http(s) address; without a scheme, http on the local
  /// network, otherwise https.
  static String? normalizeBlobServerUrl(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) {
      final host = Uri.tryParse('http://$text')?.host ?? '';
      text = '${isLocalHost(host) ? 'http' : 'https'}://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return null;
    }
    var result = uri.toString();
    if (result.endsWith('/') && uri.path == '/') {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  Future<bool> addBlobServer(String input) async {
    final url = normalizeBlobServerUrl(input);
    if (url == null || _state.blobServers.contains(url)) return false;
    await _update((s) => s.blobServers = [...s.blobServers, url]);
    _blobs?.servers.add(url);
    // All photos are uploaded again so the new server has them too.
    await db.syncDao.reuploadLocalPhotos();
    notifyListeners();
    // Check right away — otherwise the dot would stay gray until the whole
    // sync including photo uploads is done.
    unawaited(_checkBlobServer(url));
    if (enabled) unawaited(syncNow());
    return true;
  }

  Future<void> _checkBlobServer(String url) async {
    await _blobs?.checkServer(url);
    notifyListeners();
  }

  Future<void> restoreDefaultBlobServers() async {
    await _update((s) {
      final extra = s.blobServers.where((r) => !defaultBlobServers.contains(r));
      s.blobServers = [...defaultBlobServers, ...extra];
    });
    _blobs?.servers
      ?..clear()
      ..addAll(_state.blobServers);
    await db.syncDao.markUnsentPhotosPending();
    notifyListeners();
    if (enabled) unawaited(syncNow());
  }

  Future<void> removeBlobServer(String url) async {
    await _update((s) => s.blobServers = [...s.blobServers]..remove(url));
    _blobs?.servers.remove(url);
    notifyListeners();
  }

  // ---- Keys between devices (text with password) ----

  /// Key encrypted with a password (NIP-49, `ncryptsec1…`), for transfer to
  /// another device. scrypt runs in an isolate.
  Future<String> exportKey(String password) async {
    final key = _identity!.privateKeyBytes;
    return Isolate.run(() => nip49Encrypt(key, password));
  }

  /// Adopt the key of another device. The data here stays and is merged
  /// with that of the other devices. Accepts `ncryptsec1…` (with
  /// [password]) or the unprotected `nsec1…` from the plain-text QR
  /// (password ignored). Throws [Nip49Exception] on a wrong password or
  /// unusable input.
  Future<void> importKey(String ncryptsec, String password) async =>
      adoptIdentity(await decodeKey(ncryptsec, password));

  /// Open a scanned key without adopting it yet (so a wrong password shows
  /// up before asking what should happen to the data).
  static Future<SyncIdentity> decodeKey(String text, String password) async {
    final trimmed = text.trim();
    if (trimmed.startsWith('nsec1')) {
      try {
        return SyncIdentity.fromNsec(trimmed);
      } catch (_) {
        throw const Nip49Exception('Not a valid key');
      }
    }
    final key = await Isolate.run(() => nip49Decrypt(trimmed, password));
    return SyncIdentity.fromPrivateKey(key);
  }

  /// Adopt [identity]. Without [replace]: merge — everything here is
  /// included, deletions too (tombstones), and they then apply everywhere.
  /// With [replace]: discard the data here first and only fetch the state
  /// of the other devices (avoids losing data when pairing);
  /// [beforeReplace] saves it beforehand (safety copy).
  Future<void> adoptIdentity(
    SyncIdentity identity, {
    bool replace = false,
    Future<void> Function()? beforeReplace,
  }) async {
    final same = identity.publicKeyHex == _identity?.publicKeyHex;
    if (same && !replace) return;
    if (replace) {
      await beforeReplace?.call();
      _stop();
      await _running;
      await db.syncDao.wipeSyncedData();
      await _update((s) {
        s.pendingLinks.clear();
        s.presence = null;
      });
    }
    await keyStore.writeIdentity(identity);
    _identity = identity;
    await _update((s) => s.lastSync.clear());
    if (!replace) await db.syncDao.markAllPending();
    if (enabled) {
      _start();
      notifyListeners();
      await syncNow();
    } else {
      notifyListeners();
    }
  }

  /// Sync part for the backup: key encrypted with [password] plus servers.
  /// null as long as sync was never turned on.
  Future<BackupSyncInfo?> backupInfo(String password) async {
    final identity = _identity;
    if (identity == null) return null;
    return BackupSyncInfo(
      ncryptsec: await exportKey(password),
      npub: identity.npub,
      enabled: _state.enabled,
      relays: [..._state.relays],
      blobServers: [..._state.blobServers],
    );
  }

  /// Decrypt the key from a backup BEFORE restoring — so a wrong password
  /// shows up while nothing has been replaced yet.
  /// Throws [Nip49Exception] on a wrong password.
  static Future<Uint8List> decryptBackupKey(
    BackupSyncInfo info,
    String password,
  ) {
    final text = info.ncryptsec;
    return Isolate.run(() => nip49Decrypt(text, password));
  }

  /// After restoring: adopt key and servers from the backup. Starts nothing
  /// — the database is closed, the app restarts and then sends everything
  /// once (afterRestore).
  Future<void> adoptFromBackup(BackupSyncInfo info, Uint8List key) async {
    final identity = SyncIdentity.fromPrivateKey(key);
    _stop();
    await keyStore.writeIdentity(identity);
    _identity = identity;
    await _update((s) {
      s.enabled = info.enabled;
      if (info.relays.isNotEmpty) s.relays = [...info.relays];
      if (info.blobServers.isNotEmpty) s.blobServers = [...info.blobServers];
      s.blobDefaultsApplied = true;
      s.lastSync.clear();
      s.resendAll = true;
    });
    notifyListeners();
  }

  /// After restoring a backup: fetch everything again and send everything
  /// once — the database may be older or newer than the other devices. The
  /// app restarts afterwards; init() picks up the send flag.
  Future<void> afterRestore() async {
    _stop();
    await _update((s) {
      s.lastSync.clear();
      s.resendAll = true;
    });
  }

  bool _disposed = false;

  // A running sync may still finish after dispose().
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    for (final source in settingsSources) {
      source.removeListener(_onSettingsChanged);
    }
    unawaited(_pendingSub?.cancel());
    _stop();
    super.dispose();
  }
}
