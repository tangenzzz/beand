import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';

part 'sync_dao.g.dart';

// Everything sync (lib/sync) needs from the database: read pending changes,
// mark them as delivered, adopt states from other devices.
//
// Adopting NEVER stamps: updatedAt and deviceId come from the other device
// and stay as they are, otherwise there would be no shared "newer wins". If
// the local state is newer, it goes out again — this heals a relay that kept
// an older state.

/// Decides whether a remote state replaces the local one (lib/sync/engine/
/// lww.dart); a function here so the database does not depend on sync.
typedef RemoteWins = bool Function(int localUpdatedAt, String? localDeviceId);

/// Header of a received record.
class RemoteStamp {
  const RemoteStamp({
    required this.syncId,
    required this.updatedAt,
    required this.deviceId,
    required this.deleted,
    required this.wins,
  });
  final String syncId;
  final int updatedAt;
  final String deviceId;
  final bool deleted;
  final RemoteWins wins;
}

/// Result of adopting a record.
enum ApplyResult {
  /// Changed locally.
  applied,

  /// Local state was equal or newer.
  kept,
}

@DriftAccessor(
  tables: [Beans, Shots, ShotReadings, StoredProfiles, SyncedSettings],
)
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  // ---- Pending changes ----

  Future<List<Bean>> pendingBeans() => (select(
    beans,
  )..where((b) => b.syncState.equals(SyncState.pending))).get();

  Future<List<Shot>> pendingShots() => (select(
    shots,
  )..where((s) => s.syncState.equals(SyncState.pending))).get();

  Future<List<StoredProfile>> pendingProfiles() => (select(
    storedProfiles,
  )..where((p) => p.syncState.equals(SyncState.pending))).get();

  Future<List<SyncedSetting>> pendingSettings() => (select(
    syncedSettings,
  )..where((s) => s.syncState.equals(SyncState.pending))).get();

  /// How many records are waiting for upload (display and trigger).
  Stream<int> watchPendingCount() => customSelect(
    'SELECT '
    '(SELECT COUNT(*) FROM beans WHERE sync_state = ?1) + '
    '(SELECT COUNT(*) FROM shots WHERE sync_state = ?1) + '
    '(SELECT COUNT(*) FROM stored_profiles WHERE sync_state = ?1) + '
    '(SELECT COUNT(*) FROM synced_settings WHERE sync_state = ?1) AS n',
    variables: [Variable.withString(SyncState.pending)],
    readsFrom: {beans, shots, storedProfiles, syncedSettings},
  ).watchSingle().map((row) => row.read<int>('n'));

  /// Upload everything again (new key, new server, restore).
  /// Oversized shots stay where they are.
  Future<void> markAllPending() => transaction(() async {
    for (final table in [
      'beans',
      'shots',
      'stored_profiles',
      'synced_settings',
    ]) {
      await customStatement(
        'UPDATE $table SET sync_state = ? WHERE sync_state = ?',
        [SyncState.pending, SyncState.synced],
      );
    }
  });

  /// Is there anything here that pairing would carry along (tombstones too —
  /// those in particular delete on the other devices)?
  Future<bool> hasLocalData() async {
    final row = await customSelect(
      'SELECT (SELECT COUNT(*) FROM beans) + (SELECT COUNT(*) FROM shots) '
      '+ (SELECT COUNT(*) FROM stored_profiles) AS n',
      readsFrom: {beans, shots, storedProfiles},
    ).getSingle();
    return row.read<int>('n') > 0;
  }

  /// "Replace" when pairing: hard-delete everything syncable — without
  /// tombstones, which would otherwise go out as deletions to the other
  /// devices. The next sync then fetches their state; machine shots and
  /// profiles are also re-imported from the machine.
  Future<void> wipeSyncedData() => transaction(() async {
    await delete(shotReadings).go();
    await delete(shots).go();
    await delete(beans).go();
    await delete(storedProfiles).go();
    await delete(syncedSettings).go();
  });

  /// sha256 of every photo that ever went to a photo server (including from
  /// deleted beans/profiles, as long as the reference is still in the row).
  Future<Set<String>> uploadedBlobShas() async {
    final rows = await customSelect(
      'SELECT photo_blob AS b FROM beans WHERE photo_blob IS NOT NULL '
      'UNION ALL SELECT custom_image_blob AS b FROM stored_profiles '
      'WHERE custom_image_blob IS NOT NULL',
      readsFrom: {beans, storedProfiles},
    ).get();
    final shas = <String>{};
    for (final r in rows) {
      try {
        final sha = (jsonDecode(r.read<String>('b')) as Map)['sha256'];
        if (sha is String) shas.add(sha);
      } catch (_) {}
    }
    return shas;
  }

  /// After a restore: the backup content is the newest state. Everything is
  /// stamped [now] from this device and goes out again — otherwise the next
  /// sync would let older tombstones and changes on the relays win (e.g. the
  /// deletions one is trying to undo).
  Future<void> restampAll(int now, String? deviceId) => transaction(() async {
    for (final table in [
      'beans',
      'shots',
      'stored_profiles',
      'synced_settings',
    ]) {
      await customStatement(
        'UPDATE $table SET updated_at = ?, device_id = ?, '
        'sync_state = CASE WHEN sync_state = ? THEN ? ELSE sync_state END',
        [now, deviceId, SyncState.synced, SyncState.pending],
      );
    }
  });

  // After a relay's OK — only if the record has not changed again since it
  // was sent; otherwise it stays pending and goes out again.
  Future<void> _mark(
    String table,
    String syncId,
    int sentUpdatedAt,
    String state,
  ) => customUpdate(
    'UPDATE $table SET sync_state = ? '
    'WHERE sync_id = ? AND updated_at = ? AND sync_state = ?',
    variables: [
      Variable.withString(state),
      Variable.withString(syncId),
      Variable.withInt(sentUpdatedAt),
      Variable.withString(SyncState.pending),
    ],
    updates: {beans, shots, storedProfiles, syncedSettings},
  );

  Future<void> markSynced(String table, String syncId, int sentUpdatedAt) =>
      _mark(table, syncId, sentUpdatedAt, SyncState.synced);

  Future<void> markTooLarge(String table, String syncId, int sentUpdatedAt) =>
      _mark(table, syncId, sentUpdatedAt, SyncState.tooLarge);

  // Same age or older: adopt nothing. If the local state had already been
  // delivered but is not the same, a relay kept an older one — then resend
  // the local one.
  Future<ApplyResult> _keep(
    String table,
    String syncId,
    int localUpdatedAt,
    String? localDeviceId,
    String localState,
    RemoteStamp r,
  ) async {
    final same =
        localUpdatedAt == r.updatedAt &&
        (localDeviceId == r.deviceId || localDeviceId == null);
    if (!same && localState == SyncState.synced) {
      await customUpdate(
        'UPDATE $table SET sync_state = ? WHERE sync_id = ?',
        variables: [
          Variable.withString(SyncState.pending),
          Variable.withString(syncId),
        ],
        updates: {beans, shots, storedProfiles, syncedSettings},
      );
    }
    return ApplyResult.kept;
  }

  // ---- Beans ----

  Future<ApplyResult> applyRemoteBean(RemoteStamp r, BeansCompanion data) =>
      transaction(() async {
        final local = await (select(
          beans,
        )..where((b) => b.syncId.equals(r.syncId))).getSingleOrNull();
        if (local != null && !r.wins(local.updatedAt, local.deviceId)) {
          return _keep(
            'beans',
            r.syncId,
            local.updatedAt,
            local.deviceId,
            local.syncState,
            r,
          );
        }
        var row = (r.deleted ? AppDatabase.beanTombstone : data).copyWith(
          syncId: Value(r.syncId),
          updatedAt: Value(r.updatedAt),
          deviceId: Value(r.deviceId),
          syncState: const Value(SyncState.synced),
          deleted: Value(r.deleted),
        );
        // Different photo (or none any more): the local one no longer
        // applies; sync downloads the new one afterwards.
        if (!r.deleted &&
            row.photoBlob.present &&
            !_sameBlob(row.photoBlob.value, local?.photoBlob)) {
          row = row.copyWith(photoPath: const Value(null));
        }
        if (local == null) {
          await into(beans).insert(
            row.copyWith(name: Value(row.name.present ? row.name.value : '')),
          );
        } else {
          await (update(beans)..where((b) => b.id.equals(local.id))).write(row);
        }
        return ApplyResult.applied;
      });

  /// syncId of the bean for a local ID (for the reference in the shot).
  Future<Map<int, String>> beanSyncIds() async => {
    for (final b in await select(beans).get()) b.id: b.syncId,
  };

  Future<int?> _beanIdForSyncId(String syncId) async {
    final bean =
        await (select(beans)
              ..where((b) => b.syncId.equals(syncId) & b.deleted.equals(false)))
            .getSingleOrNull();
    return bean?.id;
  }

  // ---- Shots ----

  Future<List<ShotReading>> readingsFor(int shotId) =>
      (select(shotReadings)
            ..where((r) => r.shotId.equals(shotId))
            ..orderBy([(r) => OrderingTerm.asc(r.timeMs)]))
          .get();

  /// Adopt a shot including its curve. [beanSyncId]: the shot's bean; if it
  /// does not exist here (yet), the shot stays without a bean and the result
  /// reports that in [unresolvedBean] — sync fills in the link as soon as
  /// the bean arrives.
  Future<({ApplyResult result, bool unresolvedBean})> applyRemoteShot(
    RemoteStamp r,
    ShotsCompanion data,
    List<ShotReadingsCompanion Function(int shotId)> readings, {
    String? beanSyncId,
  }) => transaction(() async {
    final local = await (select(
      shots,
    )..where((s) => s.syncId.equals(r.syncId))).getSingleOrNull();
    if (local != null && !r.wins(local.updatedAt, local.deviceId)) {
      final kept = await _keep(
        'shots',
        r.syncId,
        local.updatedAt,
        local.deviceId,
        local.syncState,
        r,
      );
      return (result: kept, unresolvedBean: false);
    }
    final beanId = beanSyncId == null
        ? null
        : await _beanIdForSyncId(beanSyncId);
    final stamp = ShotsCompanion(
      syncId: Value(r.syncId),
      updatedAt: Value(r.updatedAt),
      deviceId: Value(r.deviceId),
      syncState: const Value(SyncState.synced),
    );
    final ShotsCompanion row;
    if (r.deleted) {
      // Tombstone: only time, machine and machine ID remain — the ID keeps
      // the shot from being re-imported from the machine.
      row = AppDatabase.shotTombstone(DateTime.now()).copyWith(
        timestamp: data.timestamp,
        externalId: data.externalId,
        machine: data.machine,
      );
    } else {
      row = data.copyWith(beanId: Value(beanId), deletedAt: const Value(null));
    }
    final merged = _mergeShot(row, stamp);
    final int id;
    if (local == null) {
      id = await into(shots).insert(merged);
    } else {
      id = local.id;
      await (update(shots)..where((s) => s.id.equals(id))).write(merged);
    }
    await (delete(shotReadings)..where((x) => x.shotId.equals(id))).go();
    if (!r.deleted) {
      await batch((b) {
        b.insertAll(shotReadings, [for (final f in readings) f(id)]);
      });
    }
    return (
      result: ApplyResult.applied,
      unresolvedBean: !r.deleted && beanSyncId != null && beanId == null,
    );
  });

  ShotsCompanion _mergeShot(ShotsCompanion row, ShotsCompanion stamp) =>
      row.copyWith(
        syncId: stamp.syncId,
        updatedAt: stamp.updatedAt,
        deviceId: stamp.deviceId,
        syncState: stamp.syncState,
      );

  /// Fill in the link when the bean arrived after the shot. Does not stamp —
  /// the other device already has the shot with this bean.
  Future<bool> linkShotToBean(String shotSyncId, String beanSyncId) async {
    final beanId = await _beanIdForSyncId(beanSyncId);
    if (beanId == null) return false;
    await (update(shots)..where(
          (s) =>
              s.syncId.equals(shotSyncId) &
              s.deletedAt.isNull() &
              s.beanId.isNull(),
        ))
        .write(ShotsCompanion(beanId: Value(beanId)));
    return true;
  }

  // ---- Profiles ----

  Future<ApplyResult> applyRemoteProfile(
    RemoteStamp r,
    StoredProfilesCompanion data,
  ) => transaction(() async {
    final local = await (select(
      storedProfiles,
    )..where((p) => p.syncId.equals(r.syncId))).getSingleOrNull();
    if (local != null && !r.wins(local.updatedAt, local.deviceId)) {
      return _keep(
        'stored_profiles',
        r.syncId,
        local.updatedAt,
        local.deviceId,
        local.syncState,
        r,
      );
    }
    var row = data.copyWith(
      syncId: Value(r.syncId),
      updatedAt: Value(r.updatedAt),
      deviceId: Value(r.deviceId),
      syncState: const Value(SyncState.synced),
      deleted: Value(r.deleted),
    );
    if (r.deleted) {
      row = row.copyWith(
        json: const Value(''),
        customDescription: const Value(null),
        customImagePath: const Value(null),
        customImageBlob: const Value(null),
      );
    } else if (row.customImageBlob.present &&
        !_sameBlob(row.customImageBlob.value, local?.customImageBlob)) {
      row = row.copyWith(customImagePath: const Value(null));
    }
    if (local == null) {
      await into(storedProfiles).insert(row);
    } else {
      await (update(
        storedProfiles,
      )..where((p) => p.syncId.equals(r.syncId))).write(row);
    }
    return ApplyResult.applied;
  });

  // ---- Photos (phase 4) ----

  // Two references point to the same file if the sha256 matches (the
  // address list may differ).
  static bool _sameBlob(String? a, String? b) {
    if (a == null || b == null) return a == b;
    String? sha(String json) {
      try {
        final map = jsonDecode(json);
        return map is Map ? map['sha256'] as String? : null;
      } catch (_) {
        return null;
      }
    }

    final sa = sha(a);
    return sa != null && sa == sha(b);
  }

  /// Record the reference after uploading — without a stamp (the record is
  /// going out right now) and only if nothing has changed since.
  Future<void> setBeanPhotoBlob(String syncId, int updatedAt, String blob) =>
      (update(beans)..where(
            (b) => b.syncId.equals(syncId) & b.updatedAt.equals(updatedAt),
          ))
          .write(BeansCompanion(photoBlob: Value(blob)));

  Future<void> setProfileImageBlob(String syncId, int updatedAt, String blob) =>
      (update(storedProfiles)..where(
            (p) => p.syncId.equals(syncId) & p.updatedAt.equals(updatedAt),
          ))
          .write(StoredProfilesCompanion(customImageBlob: Value(blob)));

  /// Beans with a reference but no local file (from another device).
  Future<List<Bean>> beansMissingPhoto() =>
      (select(beans)..where(
            (b) =>
                b.photoBlob.isNotNull() &
                b.photoPath.isNull() &
                b.deleted.equals(false),
          ))
          .get();

  Future<List<StoredProfile>> profilesMissingImage() =>
      (select(storedProfiles)..where(
            (p) =>
                p.customImageBlob.isNotNull() &
                p.customImagePath.isNull() &
                p.deleted.equals(false),
          ))
          .get();

  /// Store a downloaded photo if the reference is still the same.
  Future<bool> setBeanPhotoPath(int id, String blob, String path) async =>
      await (update(beans)
            ..where((b) => b.id.equals(id) & b.photoBlob.equals(blob)))
          .write(BeansCompanion(photoPath: Value(path))) >
      0;

  Future<bool> setProfileImagePath(
    String syncId,
    String blob,
    String path,
  ) async =>
      await (update(storedProfiles)..where(
            (p) => p.syncId.equals(syncId) & p.customImageBlob.equals(blob),
          ))
          .write(StoredProfilesCompanion(customImagePath: Value(path))) >
      0;

  /// After adding another photo server: all photos stored here as files are
  /// uploaded again — this time to ALL servers, including the new one. The
  /// new reference replaces the old one on the other devices.
  Future<void> reuploadLocalPhotos() async {
    await (update(
      beans,
    )..where((b) => b.photoPath.isNotNull() & b.deleted.equals(false))).write(
      const BeansCompanion(
        photoBlob: Value(null),
        syncState: Value(SyncState.pending),
      ),
    );
    await (update(storedProfiles)..where(
          (p) => p.customImagePath.isNotNull() & p.deleted.equals(false),
        ))
        .write(
          const StoredProfilesCompanion(
            customImageBlob: Value(null),
            syncState: Value(SyncState.pending),
          ),
        );
  }

  /// After adding a photo server: anything with a photo that is not on any
  /// server yet goes out again (this time with the photo).
  Future<void> markUnsentPhotosPending() async {
    await (update(beans)..where(
          (b) =>
              b.photoPath.isNotNull() &
              b.photoBlob.isNull() &
              b.syncState.equals(SyncState.synced),
        ))
        .write(const BeansCompanion(syncState: Value(SyncState.pending)));
    await (update(storedProfiles)..where(
          (p) =>
              p.customImagePath.isNotNull() &
              p.customImageBlob.isNull() &
              p.syncState.equals(SyncState.synced),
        ))
        .write(
          const StoredProfilesCompanion(syncState: Value(SyncState.pending)),
        );
  }

  // ---- Settings ----

  Future<Map<String, SyncedSetting>> settingsByKey() async => {
    for (final s in await select(syncedSettings).get()) s.key: s,
  };

  /// Record a locally seen value. [initial]: first capture — then it is
  /// unknown when it was set: 0 for "never set", 1 for "set at some point",
  /// so that any real change from another device wins.
  Future<void> recordSetting({
    required String key,
    required String syncId,
    required String? value,
    required int updatedAt,
    required String? deviceId,
    required String state,
  }) => into(syncedSettings).insertOnConflictUpdate(
    SyncedSettingsCompanion.insert(
      key: key,
      value: Value(value),
      syncId: Value(syncId),
      updatedAt: Value(updatedAt),
      deviceId: Value(deviceId),
      syncState: Value(state),
    ),
  );

  Future<ApplyResult> applyRemoteSetting(
    RemoteStamp r,
    String key,
    String? value,
  ) => transaction(() async {
    final local = await (select(
      syncedSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    if (local != null && !r.wins(local.updatedAt, local.deviceId)) {
      return _keep(
        'synced_settings',
        r.syncId,
        local.updatedAt,
        local.deviceId,
        local.syncState,
        r,
      );
    }
    await recordSetting(
      key: key,
      syncId: r.syncId,
      value: r.deleted ? null : value,
      updatedAt: r.updatedAt,
      deviceId: r.deviceId,
      state: SyncState.synced,
    );
    return ApplyResult.applied;
  });
}
