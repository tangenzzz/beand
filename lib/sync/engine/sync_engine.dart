import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../database/database.dart';
import '../../database/sync_dao.dart';
import '../../database/sync_ids.dart';
import '../blobs/blob_ref.dart';
import '../blobs/blob_sync.dart';
import '../identity/identity.dart';
import '../nostr/event.dart';
import '../nostr/relay_pool.dart';
import '../records/bean_codec.dart';
import '../records/device_codec.dart';
import '../records/profile_codec.dart';
import '../records/setting_codec.dart';
import '../records/shot_codec.dart';
import '../records/sync_envelope.dart';
import 'event_worker.dart';
import 'lww.dart';
import 'sync_state_store.dart';

// The actual sync, without UI and without triggers (those are handled by
// SyncService):
//
//  1. Capture settings: whatever changed in the prefs gets a timestamp and
//     waits for upload.
//  2. Fetch (inbox): all own kind-30078 events since the last sync per
//     relay (minus a 10 min buffer against clock skew), the first time
//     everything, page by page. Collect everything first, then apply in a
//     fixed order (settings, beans, profiles, shots) so the bean is usually
//     there before its shot. Each event: verify signature, decrypt, read
//     envelope, last-writer-wins. Skip broken ones, never crash.
//  3. Send (outbox): everything with syncState pending as an event to all
//     relays; one OK is enough, then `synced`.
//  4. Device presence: send "I'm here" and check whether a relay has lost
//     data or a new or long-absent device has joined — then resend the
//     whole dataset once (at most every 6 h).

/// Link to the app's settings: where they live and who must re-read them
/// after a takeover (AppSettings, AiSettings).
class SettingsBridge {
  const SettingsBridge({required this.prefs, required this.reload, this.keys});

  final Future<SettingsStore> Function() prefs;
  final Future<void> Function() reload;

  /// If not given: syncedSettingKeys().
  final List<String>? keys;
}

class SyncReport {
  int received = 0;
  int applied = 0;
  int skipped = 0;
  int sent = 0;

  /// Photos from other devices that are now here.
  int photosFetched = 0;

  /// Records no relay accepted (stay pending).
  int notSent = 0;

  /// The whole dataset was resent, and why (device presence).
  String? resentAll;

  /// Too large for an event.
  int tooLarge = 0;

  /// Relays that were unreachable or refused.
  final failedRelays = <String>{};

  @override
  String toString() =>
      'SyncReport(received $received, applied $applied, skipped $skipped, '
      'sent $sent, notSent $notSent, tooLarge $tooLarge, '
      'photos $photosFetched, '
      '${resentAll == null ? '' : 'resentAll ($resentAll), '}'
      'failed $failedRelays)';
}

class SyncEngine {
  SyncEngine({
    required this.db,
    required this.identity,
    required this.pool,
    required this.deviceId,
    required this.stateStore,
    this.settings,
    this.blobs,
    this.pageSize = 500,
    this.parallelSends = 6,
    this.devicePresence = true,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Device presence on (step 4). Off only in tests that count events.
  final bool devicePresence;

  /// Increment whenever a new record type is added: then every device
  /// fetches everything once. 1 = beans, 2 = + shots, profiles, settings.
  static const typesVersion = 2;

  /// Buffer against differing device clocks.
  static const sinceSlack = 600;

  final AppDatabase db;
  final SyncIdentity identity;

  // Key for the background isolates (event_worker.dart).
  late final SyncKeys _keys = SyncKeys.of(identity);
  final RelayPool pool;
  final String deviceId;
  final SyncStateStore stateStore;
  final SettingsBridge? settings;

  /// Photo servers; null or empty = photos stay on the device.
  final BlobSync? blobs;

  /// Page size when fetching (strfry allows up to 500).
  final int pageSize;

  /// This many records in flight at once (each to all relays).
  final int parallelSends;
  final DateTime Function() _now;

  SyncDao get _dao => db.syncDao;
  int _nowSeconds() => _now().millisecondsSinceEpoch ~/ 1000;
  int _nowMs() => _now().millisecondsSinceEpoch;

  // created_at of sent events: strictly increasing per device. Of two
  // versions of the same record, relays keep the one with the later time,
  // with the SAME second the one with the smaller event ID — i.e. random.
  // And when fetching page by page only the second separates the pages. So
  // every event gets at least one second more than the previous one, but
  // at most [maxAhead] in the future (relays reject events too far ahead,
  // strfry e.g. from 15 min). Only with very many events in a row do
  // several share a second again.
  static const maxAhead = 300;
  int _lastCreatedAt = 0;

  int _nextCreatedAt() {
    final now = _nowSeconds();
    final next = _lastCreatedAt + 1;
    _lastCreatedAt = next < now
        ? now
        : (next > now + maxAhead ? now + maxAhead : next);
    return _lastCreatedAt;
  }

  /// Capture, fetch, send.
  Future<SyncReport> run({
    bool force = false,
    void Function(int received)? onProgress,
  }) async {
    final report = SyncReport();
    await captureSettings();
    await pull(report, force: force, onProgress: onProgress);
    await push(report, force: force);
    if (devicePresence) await presence(report, force: force);
    await fetchMissingPhotos(report);
    return report;
  }

  // ---- 1. Capture settings ----

  Future<void> captureSettings() async {
    final bridge = settings;
    if (bridge == null) return;
    final prefs = await bridge.prefs();
    final known = await _dao.settingsByKey();
    for (final key in bridge.keys ?? syncedSettingKeys()) {
      final current = readSettingJson(prefs, key);
      final row = known[key];
      if (row == null) {
        // First capture: nobody knows when the value was set. A set value
        // (1) only beats "never set" (0), but loses to any real change on
        // another device.
        await _dao.recordSetting(
          key: key,
          syncId: settingSyncId(key),
          value: current,
          updatedAt: current == null ? 0 : 1,
          deviceId: deviceId,
          state: current == null ? SyncState.synced : SyncState.pending,
        );
      } else if (row.value != current) {
        await _dao.recordSetting(
          key: key,
          syncId: row.syncId,
          value: current,
          updatedAt: _nowMs(),
          deviceId: deviceId,
          state: SyncState.pending,
        );
      }
    }
  }

  // ---- 2. Fetch ----

  Future<void> pull(
    SyncReport report, {
    bool force = false,
    void Function(int received)? onProgress,
  }) async {
    final state = await stateStore.load();
    final reset = state.typesVersion != typesVersion;
    if (reset) state.lastSync.clear();
    final done = <String, int>{};
    final events = <String, NostrEvent>{};
    await Future.wait([
      for (final url in pool.urls)
        _collect(url, state.lastSync[url], done, events, report, force, () {
          onProgress?.call(events.length);
        }),
    ]);
    report.received = events.length;

    final records = <SyncEnvelope>[];
    for (var envelope in await openEvents(events.values.toList(), _keys)) {
      if (envelope?.blobRef != null) envelope = await _unpack(envelope!);
      if (envelope == null) {
        report.skipped++;
      } else {
        records.add(envelope);
      }
    }
    records.sort((a, b) => _typeOrder(a.type).compareTo(_typeOrder(b.type)));

    final links = Map<String, String>.of(state.pendingLinks);
    final changedSettings = <String>{};
    await db.transaction(() async {
      for (final r in records) {
        try {
          if (await _apply(r, links, changedSettings)) report.applied++;
        } catch (e) {
          debugPrint('Sync: skipped ${r.type} ${r.id}: $e');
          report.skipped++;
        }
      }
      // Shots whose bean has only now (or earlier) arrived.
      for (final entry in links.entries.toList()) {
        if (await _dao.linkShotToBean(entry.key, entry.value)) {
          links.remove(entry.key);
        }
      }
    });
    if (changedSettings.isNotEmpty) await _writeSettings(changedSettings);

    // Load fresh and change only our own fields: the user may have edited
    // the server list in the meantime.
    final fresh = await stateStore.load();
    if (reset) {
      fresh.lastSync.clear();
      fresh.typesVersion = typesVersion;
    }
    for (final entry in done.entries) {
      if (fresh.relays.contains(entry.key)) {
        fresh.lastSync[entry.key] = entry.value;
      }
    }
    fresh.pendingLinks = links;
    await stateStore.save(fresh);
  }

  static int _typeOrder(String type) => switch (type) {
    settingType => 0,
    beanType => 1,
    profileType => 2,
    shotType => 3,
    _ => 4,
  };

  Future<void> _collect(
    String url,
    int? last,
    Map<String, int> done,
    Map<String, NostrEvent> events,
    SyncReport report,
    bool force,
    void Function() progress,
  ) async {
    final startedAt = _nowSeconds();
    final since = last == null ? null : last - sinceSlack;
    int? until;
    try {
      while (true) {
        final filter = <String, Object>{
          'kinds': [kindAppData],
          'authors': [identity.publicKeyHex],
          'limit': pageSize,
          'since': ?since,
          'until': ?until,
        };
        final page = await pool.queryOne(url, filter, force: force);
        for (final e in page) {
          events.putIfAbsent(e.id, () => e);
        }
        progress();
        if (page.length < pageSize) break;
        // Next page: older events. If all have the same second, the bound
        // must move one second further, otherwise the same page would come
        // again.
        final oldest = page
            .map((e) => e.createdAt)
            .reduce((a, b) => a < b ? a : b);
        until = (until != null && oldest >= until) ? until - 1 : oldest;
      }
      done[url] = startedAt;
    } catch (e) {
      debugPrint('Sync pull from $url failed: $e');
      report.failedRelays.add(url);
    }
  }

  // Fetch an outsourced envelope from the photo servers. It must match its
  // event (type, ID, version), otherwise it isn't the one meant.
  Future<SyncEnvelope?> _unpack(SyncEnvelope outer) async {
    final store = blobs;
    if (store == null) return null;
    try {
      final ref = BlobRef.fromJson(outer.blobRef);
      final bytes = await store.downloadBytes(ref);
      if (bytes == null) return null;
      final inner = SyncEnvelope.decode(utf8.decode(gzip.decode(bytes)));
      if (inner.type != outer.type ||
          inner.id != outer.id ||
          inner.updatedAt != outer.updatedAt ||
          inner.blobRef != null) {
        return null;
      }
      return inner;
    } catch (e) {
      debugPrint('Sync: outsourced ${outer.type} ${outer.id} unreadable: $e');
      return null;
    }
  }

  Future<bool> _apply(
    SyncEnvelope r,
    Map<String, String> links,
    Set<String> changedSettings,
  ) async {
    final stamp = RemoteStamp(
      syncId: r.id,
      updatedAt: r.updatedAt,
      deviceId: r.deviceId,
      deleted: r.deleted,
      // Without a recorded device (created before sync) it's this one —
      // that's also what the record is called when sending. Otherwise the
      // app would take its own echo for a foreign version and rewrite it.
      wins: (localUpdatedAt, localDeviceId) => remoteWins(
        remoteUpdatedAt: r.updatedAt,
        remoteDeviceId: r.deviceId,
        localUpdatedAt: localUpdatedAt,
        localDeviceId: localDeviceId ?? deviceId,
      ),
    );
    switch (r.type) {
      case beanType:
        final data = r.deleted
            ? const BeansCompanion()
            : beanFromSyncData(r.data);
        return await _dao.applyRemoteBean(stamp, data) == ApplyResult.applied;
      case profileType:
        final data = profileFromSyncData(r.data, deleted: r.deleted);
        if (data.machine.value.isEmpty) return false;
        // The record must match its ID (deterministic from machine +
        // profile ID).
        if (machineProfileSyncId(data.machine.value, data.id.value) != r.id) {
          throw const FormatException('Profile id does not match');
        }
        return await _dao.applyRemoteProfile(stamp, data) ==
            ApplyResult.applied;
      case shotType:
        final decoded = shotFromSyncData(r.data, deleted: r.deleted);
        final result = await _dao.applyRemoteShot(
          stamp,
          decoded.shot,
          decoded.readings,
          beanSyncId: decoded.beanSyncId,
        );
        if (result.unresolvedBean) {
          links[r.id] = decoded.beanSyncId!;
        } else if (result.result == ApplyResult.applied) {
          links.remove(r.id);
        }
        return result.result == ApplyResult.applied;
      case settingType:
        final key = r.data['key'];
        final value = r.data['value'];
        if (key is! String || (value != null && value is! String)) {
          throw const FormatException('Setting without key');
        }
        // Only what this device would sync itself.
        final allowed = settings?.keys ?? syncedSettingKeys();
        if (!allowed.contains(key) || settingSyncId(key) != r.id) return false;
        final applied =
            await _dao.applyRemoteSetting(stamp, key, value as String?) ==
            ApplyResult.applied;
        if (applied) changedSettings.add(key);
        return applied;
      case deviceType:
        // Evaluates presence(); doesn't change the database.
        final seen = _devicesSeen[r.id];
        if (seen == null || r.updatedAt > seen) {
          _devicesSeen[r.id] = r.updatedAt;
        }
        return false;
      default:
        // Type from a later app version.
        return false;
    }
  }

  // Write taken-over settings into the prefs and let the app re-read them.
  // The table already holds the new value, so the next capture sees no
  // difference.
  Future<void> _writeSettings(Set<String> keys) async {
    final bridge = settings;
    if (bridge == null) return;
    final prefs = await bridge.prefs();
    final rows = await _dao.settingsByKey();
    for (final key in keys) {
      try {
        await writeSettingJson(prefs, key, rows[key]?.value);
      } catch (e) {
        debugPrint('Sync: setting $key not applied: $e');
      }
    }
    await bridge.reload();
  }

  // ---- 3. Send ----

  Future<void> push(SyncReport report, {bool force = false}) async {
    final jobs = <_Outgoing>[];
    for (final b in await _dao.pendingBeans()) {
      jobs.add(
        _Outgoing('beans', b.syncId, b.updatedAt, () async {
          final (photo, photoRef) = await _photoReady(
            path: b.photoPath,
            blob: b.photoBlob,
            store: (ref) => _dao.setBeanPhotoBlob(b.syncId, b.updatedAt, ref),
          );
          if (photo == _Photo.failed) return null;
          final bean = photo == _Photo.uploaded
              ? b.copyWith(photoBlob: Value(photoRef))
              : b;
          return SyncEnvelope(
            type: beanType,
            id: b.syncId,
            updatedAt: b.updatedAt,
            deviceId: b.deviceId ?? deviceId,
            deleted: b.deleted,
            data: b.deleted
                ? const {}
                : beanToSyncData(bean, includePhoto: photo != _Photo.local),
          );
        }),
      );
    }
    for (final p in await _dao.pendingProfiles()) {
      jobs.add(
        _Outgoing('stored_profiles', p.syncId, p.updatedAt, () async {
          final (image, imageRef) = await _photoReady(
            path: p.customImagePath,
            blob: p.customImageBlob,
            store: (ref) =>
                _dao.setProfileImageBlob(p.syncId, p.updatedAt, ref),
          );
          if (image == _Photo.failed) return null;
          final profile = image == _Photo.uploaded
              ? p.copyWith(customImageBlob: Value(imageRef))
              : p;
          return SyncEnvelope(
            type: profileType,
            id: p.syncId,
            updatedAt: p.updatedAt,
            deviceId: p.deviceId ?? deviceId,
            deleted: p.deleted,
            data: profileToSyncData(
              profile,
              includeImage: image != _Photo.local,
            ),
          );
        }),
      );
    }
    final beanIds = await _dao.beanSyncIds();
    for (final s in await _dao.pendingShots()) {
      jobs.add(
        _Outgoing(
          'shots',
          s.syncId,
          s.updatedAt,
          () async => SyncEnvelope(
            type: shotType,
            id: s.syncId,
            updatedAt: s.updatedAt,
            deviceId: s.deviceId ?? deviceId,
            deleted: s.deletedAt != null,
            data: shotToSyncData(
              s,
              beanSyncId: s.beanId == null ? null : beanIds[s.beanId],
              readings: s.deletedAt != null
                  ? const []
                  : await _dao.readingsFor(s.id),
            ),
          ),
        ),
      );
    }
    for (final s in await _dao.pendingSettings()) {
      jobs.add(
        _Outgoing(
          'synced_settings',
          s.syncId,
          s.updatedAt,
          () async => SyncEnvelope(
            type: settingType,
            id: s.syncId,
            updatedAt: s.updatedAt,
            deviceId: s.deviceId ?? deviceId,
            deleted: false,
            data: {'key': s.key, 'value': s.value},
          ),
        ),
      );
    }

    var next = 0;
    Future<void> worker() async {
      while (next < jobs.length) {
        final job = jobs[next++];
        await _send(job, report, force: force);
      }
    }

    await Future.wait([for (var i = 0; i < parallelSends; i++) worker()]);
  }

  // A record's photo before sending: already uploaded, no photo, uploaded
  // now, local only (no photo server) or upload failed (then the whole
  // record waits — without the photo it would go out as "photo removed").
  Future<(_Photo, String?)> _photoReady({
    required String? path,
    required String? blob,
    required Future<void> Function(String ref) store,
  }) async {
    if (path == null || blob != null) return (_Photo.ready, blob);
    final store_ = blobs;
    if (store_ == null || !store_.hasServers) return (_Photo.local, null);
    if (!File(path).existsSync()) return (_Photo.local, null);
    final ref = await store_.uploadFile(path);
    if (ref == null) return (_Photo.failed, null);
    final encoded = ref.encode();
    await store(encoded);
    return (_Photo.uploaded, encoded);
  }

  Future<void> _send(
    _Outgoing job,
    SyncReport report, {
    required bool force,
  }) async {
    final built = await job.build();
    if (built == null) {
      report.notSent++;
      return;
    }
    var envelope = built;
    var plain = envelope.encode();
    if (plain.length > maxInlineEnvelopeBytes) {
      // Too large for the event: the whole envelope goes to the photo
      // servers, the event only carries the reference.
      final ref = await blobs?.uploadBytes(
        Uint8List.fromList(gzip.encode(utf8.encode(plain))),
      );
      if (ref == null) {
        debugPrint('Sync: ${envelope.type} ${envelope.id} too large');
        await _dao.markTooLarge(job.table, envelope.id, envelope.updatedAt);
        report.tooLarge++;
        return;
      }
      envelope = SyncEnvelope(
        type: envelope.type,
        id: envelope.id,
        updatedAt: envelope.updatedAt,
        deviceId: envelope.deviceId,
        deleted: envelope.deleted,
        data: const {},
        blobRef: ref.toJson(),
      );
      plain = envelope.encode();
    }
    final event = await sealEvent(
      keys: _keys,
      dTag: identity.dTag(envelope.type, envelope.id),
      plain: plain,
      createdAt: _nextCreatedAt(),
    );
    final results = await pool.publish(event, force: force);
    for (final url in pool.urls) {
      if (results[url]?.accepted != true) report.failedRelays.add(url);
    }
    if (results.values.any((r) => r.accepted)) {
      await _dao.markSynced(job.table, envelope.id, envelope.updatedAt);
      report.sent++;
    } else {
      report.notSent++;
    }
  }

  // ---- 4. Device presence ----

  /// How often our own presence goes out (otherwise every sync would cost
  /// one event per relay).
  static const presenceInterval = Duration(hours: 1);

  /// Not seen for longer = "long absent": relays may have cleaned up older
  /// data in the meantime.
  static const staleAfter = Duration(days: 14);

  /// At most this often the whole dataset — if a relay accepts presence
  /// events but doesn't keep them, it would otherwise run on every sync.
  static const resendPause = Duration(hours: 6);

  // Presence events seen while fetching: device ID → time (Unix ms).
  final _devicesSeen = <String, int>{};

  Future<void> presence(SyncReport report, {bool force = false}) async {
    final state = await stateStore.load();
    final p = state.presenceFor(identity.publicKeyHex);
    final now = _nowMs();
    final dTag = identity.dTag(deviceType, deviceId);

    // 1. Is our own presence still on every relay that had it?
    final missingOn = <String>{};
    await Future.wait([
      for (final url in pool.urls)
        () async {
          try {
            final found = await pool.queryOne(url, {
              'kinds': [kindAppData],
              'authors': [identity.publicKeyHex],
              '#d': [dTag],
              'limit': 1,
            }, force: force);
            if (found.isEmpty) missingOn.add(url);
          } catch (_) {
            // Unreachable: unknown, conclude nothing.
          }
        }(),
    ]);
    final lost = missingOn.intersection(p.relays);
    // A loss counts once: the relay only counts as "has it" again once it
    // accepts a new presence. Otherwise a relay that now rejects us
    // (whitelist) would trigger a full resend every 6 h.
    p.relays.removeAll(lost);

    // 2. New or long-absent devices. The very first time all are unknown —
    // then just remember them.
    final newcomers = <String>[];
    for (final e in _devicesSeen.entries) {
      if (e.key == deviceId) continue;
      final before = p.devices[e.key];
      // Only a NEWER presence counts; what matters is the gap to the
      // previous one (the same old presence can come back when fetching).
      if (before != null && e.value <= before) continue;
      if (p.initialized &&
          (before == null || e.value - before > staleAfter.inMilliseconds)) {
        newcomers.add(e.key);
      }
      p.devices[e.key] = e.value;
    }
    _devicesSeen.clear();
    p.initialized = true;

    // 3. Resend the whole dataset once.
    final last = p.lastResendAt;
    final resendDue = last == null || now - last > resendPause.inMilliseconds;
    if ((lost.isNotEmpty || newcomers.isNotEmpty) && resendDue) {
      report.resentAll = lost.isNotEmpty
          ? 'data gone on ${lost.join(', ')}'
          : 'device ${newcomers.join(', ')}';
      debugPrint('Sync: sending everything again (${report.resentAll})');
      await _dao.markAllPending();
      // Whoever lost data may have lost the photos too ("Delete synced
      // data" from another device deletes both).
      if (lost.isNotEmpty) await _dao.reuploadLocalPhotos();
      p.lastResendAt = now;
      await _savePresence(p);
      await push(report, force: force);
    }

    // 4. Own presence: hourly, and immediately where it's missing.
    final published = p.lastPublishedAt;
    final publishDue =
        missingOn.isNotEmpty ||
        published == null ||
        now - published > presenceInterval.inMilliseconds ||
        pool.urls.any((u) => !p.relays.contains(u));
    if (publishDue) {
      final envelope = SyncEnvelope(
        type: deviceType,
        id: deviceId,
        updatedAt: now,
        deviceId: deviceId,
        deleted: false,
        data: deviceToSyncData(now),
      );
      final event = await sealEvent(
        keys: _keys,
        dTag: dTag,
        plain: envelope.encode(),
        createdAt: _nextCreatedAt(),
      );
      final results = await pool.publish(event, force: force);
      for (final url in pool.urls) {
        if (results[url]?.accepted ?? false) p.relays.add(url);
      }
      if (results.values.any((r) => r.accepted)) p.lastPublishedAt = now;
    }
    p.relays.removeWhere((u) => !pool.urls.contains(u));
    await _savePresence(p);
  }

  // Load fresh and only replace the presence (the user may have changed the
  // servers in the meantime).
  Future<void> _savePresence(PresenceState p) async {
    final fresh = await stateStore.load();
    fresh.presence = p;
    await stateStore.save(fresh);
  }

  // ---- 5. Fetch photos from other devices ----

  Future<void> fetchMissingPhotos(SyncReport report) async {
    final store = blobs;
    if (store == null) return;
    for (final b in await _dao.beansMissingPhoto()) {
      final ref = BlobRef.tryDecode(b.photoBlob);
      if (ref == null) continue;
      final path = await store.downloadFile(ref, 'bean_photos');
      if (path != null &&
          await _dao.setBeanPhotoPath(b.id, b.photoBlob!, path)) {
        report.photosFetched++;
      }
    }
    for (final p in await _dao.profilesMissingImage()) {
      final ref = BlobRef.tryDecode(p.customImageBlob);
      if (ref == null) continue;
      final path = await store.downloadFile(ref, 'profile_photos');
      if (path != null &&
          await _dao.setProfileImagePath(p.syncId, p.customImageBlob!, path)) {
        report.photosFetched++;
      }
    }
  }
}

enum _Photo { ready, uploaded, local, failed }

class _Outgoing {
  _Outgoing(this.table, this.syncId, this.updatedAt, this.build);
  final String table;
  final String syncId;
  final int updatedAt;

  /// Only build when sending (load curve, upload photo), not all at once.
  /// null = don't send this time.
  final Future<SyncEnvelope?> Function() build;
}
