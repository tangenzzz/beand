import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:clock/clock.dart';

import '../models/taste_profile.dart';
import 'sync_dao.dart';
import 'sync_ids.dart';

part 'database.g.dart';

/// Sync state of a record (column `syncState`).
abstract final class SyncState {
  /// Changed locally, not yet received by any relay.
  static const pending = 'pending';
  static const synced = 'synced';

  /// Too large for an event (> 60 KB); waits for blob support.
  /// Does not count as "pending", otherwise the counter would never hit zero.
  static const tooLarge = 'too_large';
}

// Columns every syncable record carries. They are set only in AppDatabase:
// syncId on insert, the rest by every write path via the _stamp… helpers.
mixin SyncColumns on Table {
  // Identity of the record across devices (UUID). Deterministic for
  // machine shots/profiles, see sync_ids.dart.
  TextColumn get syncId => text().unique().clientDefault(newSyncId)();
  // Last change in Unix ms; decides during sync (newer wins). 0 = freshly
  // imported from the machine and never touched — loses against any real
  // change on another device.
  IntColumn get updatedAt =>
      integer().clientDefault(() => clock.now().millisecondsSinceEpoch)();
  // Device that changed it last; breaks ties during sync.
  TextColumn get deviceId => text().nullable()();
  TextColumn get syncState =>
      text().withDefault(const Constant(SyncState.pending))();
}

class Beans extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get roaster => text().nullable()();
  DateTimeColumn get roastDate => dateTime().nullable()();
  // false = Single Origin, true = Blend.
  // Nullable: the form preselects neither "Single Origin" nor "Blend",
  // null = not specified.
  BoolColumn get isBlend => boolean().nullable()();
  // 'filter' | 'espresso' | 'omni', null = not specified.
  TextColumn get roastedFor => text().nullable()();
  // 'ultra-light' | 'light' | 'medium' | 'dark', null = not specified.
  TextColumn get roastLevel => text().nullable()();
  TextColumn get country => text().nullable()();
  TextColumn get processing => text().nullable()();
  TextColumn get variety => text().nullable()();
  TextColumn get producer => text().nullable()();
  RealColumn get weightGrams => real().nullable()();
  // Comma-separated tasting notes ("blackcurrant, grapefruit").
  TextColumn get taste => text().nullable()();
  // Price of the bag in euros.
  RealColumn get cost => real().nullable()();
  TextColumn get photoPath => text().nullable()();
  // Reference to the encrypted photo on the photo servers (JSON of BlobRef).
  // Null = not uploaded yet or no photo; cleared on every new photo. The
  // path above stays local.
  TextColumn get photoBlob => text().nullable()();
  // Frozen: freshness ring paused. On thawing, [thawedDate] is set and
  // replaces the roast date as the start of the ring from then on.
  BoolColumn get isFrozen => boolean().withDefault(const Constant(false))();
  DateTimeColumn get thawedDate => dateTime().nullable()();
  // Manually marked as empty (long press on the photo) — independent of the
  // computed remaining amount. Null = not empty.
  DateTimeColumn get emptiedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Deleted: the row stays as a tombstone (only syncId + sync columns) so
  // the deletion reaches the other devices.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
}

@TableIndex(name: 'shots_external_id', columns: {#externalId}, unique: true)
class Shots extends Table with SyncColumns {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get timestamp => dateTime()();
  IntColumn get beanId => integer().nullable().references(Beans, #id)();
  TextColumn get profileName => text().nullable()();
  RealColumn get doseGrams => real().nullable()();
  RealColumn get finalWeight => real().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get grindSize => text().nullable()();
  // Grinder and fitted burr set at brew time (Settings → My Setup →
  // Grinders), as text like the profile name: renaming a grinder later
  // doesn't rewrite old shots.
  TextColumn get grinder => text().nullable()();
  TextColumn get burrs => text().nullable()();
  // The brew chain's gear at brew time (My Coffee Desk), one piece per
  // line in desk order — text like the grinder, so later edits on the desk
  // don't rewrite old shots.
  TextColumn get brewedWith => text().nullable()();
  // Which brew chain it was (its ID on My Coffee Desk) — so the next brew on
  // this machine starts with it, and the shot detail can change it.
  TextColumn get brewChainId => text().nullable()();
  // The grinder's zero point that day (dial reading at burr touch) — so a
  // shot stays comparable after re-zeroing: effective = grind − zero.
  RealColumn get grindZero => real().nullable()();
  IntColumn get rating => integer().nullable()();
  // The eight axes of the rating flower, 0-5 each (null = not rated).
  // Separate columns instead of an encoded string so they can be filtered
  // and sorted later.
  IntColumn get tasteFinish => integer().nullable()();
  IntColumn get tasteBody => integer().nullable()();
  IntColumn get tasteAcidity => integer().nullable()();
  IntColumn get tasteSweetness => integer().nullable()();
  IntColumn get tasteHollow => integer().nullable()();
  IntColumn get tasteSalty => integer().nullable()();
  IntColumn get tasteAstringent => integer().nullable()();
  IntColumn get tasteBitter => integer().nullable()();
  // Free extra attributes, comma-separated ("strawberry, ash"): no score and
  // no polarity, just present or not. The eight axes above stay fixed
  // columns because they are sorted/filtered by.
  TextColumn get tasteExtras => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get shotPhotoPath => text().nullable()();
  // Raw JSON of the debug file as a backup in case the ShotReadings import
  // fails or the debug format changes.
  TextColumn get rawDebugJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // ID of the shot in the machine's history — prevents duplicate imports.
  // Null for shots that don't come from the machine (Pour Over, ...).
  TextColumn get externalId => text().nullable()();
  // 'meticulous' | 'pourover' | 'gaggimate'.
  TextColumn get machine => text().withDefault(const Constant('meticulous'))();
  // Profile color ("#F03038") and local copy of the profile image: the
  // machine only serves the image while reachable, but the history must look
  // complete offline too.
  TextColumn get profileColor => text().nullable()();
  TextColumn get profileImagePath => text().nullable()();
  // Mean of the four bar sensors over the brew (without retraction), °C. Not
  // displayed (the profile target temperature is shown instead), but kept
  // stored.
  RealColumn get brewTemp => real().nullable()();
  // Target temperature of the profile (°C) — the "Temp" in the shot detail.
  RealColumn get profileTemp => real().nullable()();
  // Deleted: the row stays as a tombstone (only timestamp + externalId) so
  // the import doesn't fetch the shot from the machine again.
  DateTimeColumn get deletedAt => dateTime().nullable()();
  // AI shot analysis as JSON (ShotAnalysis), plus who produced it and when.
  // Stored so an old shot shows it offline and without new costs;
  // "Re-analyse" overwrites it.
  TextColumn get aiAnalysis => text().nullable()();
  // The profile at brew time (stages + variables, without image), from the
  // machine's history entry. Shot findings and AI analysis run against this
  // — not against the current version in StoredProfiles, which may have
  // changed since. ~1-2 KB per shot.
  TextColumn get profileJson => text().nullable()();
  // How each stage ended, according to the machine (GaggiMate only, which
  // records it): JSON list of {stage, reason, pumped, scale}. Takes
  // precedence over the curve-based estimate in the shot findings.
  TextColumn get stageExits => text().nullable()();
  TextColumn get aiAnalysisModel => text().nullable()();
  DateTimeColumn get aiAnalysedAt => dateTime().nullable()();
}

// One row per time step from the Meticulous debug file (imported after the
// shot ends via /api/v1/history/last-debug-file). Live data during the shot
// goes separately over Socket.IO and does not end up here.
@TableIndex(name: 'shot_readings_shot_id', columns: {#shotId})
class ShotReadings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get shotId => integer().references(Shots, #id)();
  IntColumn get timeMs => integer()();
  IntColumn get profileMs => integer().nullable()();
  RealColumn get pressure => real().nullable()();
  RealColumn get flow => real().nullable()();
  RealColumn get weight => real().nullable()();
  RealColumn get gravimetricFlow => real().nullable()();
  RealColumn get externalTemp1 => real().nullable()();
  RealColumn get externalTemp2 => real().nullable()();
  RealColumn get barUp => real().nullable()();
  RealColumn get barMidUp => real().nullable()();
  RealColumn get barMidDown => real().nullable()();
  RealColumn get barDown => real().nullable()();
  RealColumn get tubeTemp => real().nullable()();
  RealColumn get motorTemp => real().nullable()();
  RealColumn get lamTemp => real().nullable()();
  RealColumn get motorPosition => real().nullable()();
  RealColumn get motorSpeed => real().nullable()();
  RealColumn get motorPower => real().nullable()();
  RealColumn get motorCurrent => real().nullable()();
  RealColumn get bandheaterPower => real().nullable()();
  RealColumn get bandheaterCurrent => real().nullable()();
  RealColumn get pressureSensorRaw => real().nullable()();
  BoolColumn get waterStatus => boolean().nullable()();
  RealColumn get weightPrediction => real().nullable()();
  // Name of the profile stage at this point ("Percolation", ...; at the end
  // "retracting") — the phases in the chart are derived from it.
  TextColumn get stage => text().nullable()();
}

// How often a profile was used in the app (for the profile view).
class ProfileUsage {
  const ProfileUsage({required this.count, this.lastUsed, this.averageRating});
  final int count;
  final DateTime? lastUsed;
  // Mean of the given stars (null if none is rated).
  final double? averageRating;
}

// Shot + its bean (if linked and still present).
class ShotEntry {
  const ShotEntry(this.shot, this.bean);
  final Shot shot;
  final Bean? bean;
}

// Local copy of the machine's profiles so profile cards and the profile view
// work without a connection too. Kept even if the machine deletes a profile
// later.
class StoredProfiles extends Table with SyncColumns {
  // ID of the profile on the machine.
  TextColumn get id => text()();
  // Which machine owns the profile (key as in Shots.machine). Both machines
  // assign their IDs independently, so only the pair of both is unique.
  TextColumn get machine => text().withDefault(const Constant('meticulous'))();
  TextColumn get name => text()();
  // Full profile JSON (as from GET /api/v1/profile/get/{id}).
  TextColumn get json => text()();
  // Local copy of the profile image.
  TextColumn get imagePath => text().nullable()();
  // Position in the machine's profile list.
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get fetchedAt => dateTime()();
  // Custom description/image (e.g. copied from the community catalog): take
  // precedence over the machine's values and are never overwritten by the
  // sync with the machine.
  TextColumn get customDescription => text().nullable()();
  TextColumn get customImagePath => text().nullable()();
  // Reference to the encrypted custom image (like Beans.photoBlob).
  TextColumn get customImageBlob => text().nullable()();
  // Deleted (forgotten in the app or removed on the machine): stays as a
  // tombstone so the deletion reaches the other devices. If the profile
  // reappears on the machine, the row comes back to life.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id, machine};
}

// One row per synced setting (whitelist in
// lib/sync/records/setting_codec.dart). The settings themselves stay in
// shared_preferences; this only records which value was last seen or
// received and when it changed — prefs have no timestamps, and without them
// there is no "newer wins".
class SyncedSettings extends Table with SyncColumns {
  TextColumn get key => text()();
  // Value as JSON (bool, number, text, text list); null = not set.
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [Beans, Shots, ShotReadings, StoredProfiles, SyncedSettings],
  daos: [SyncDao],
)
class AppDatabase extends _$AppDatabase {
  // [executor] for tests only (in-memory DB / migration test).
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// ID of this device for sync (last changing device per record). Set by
  /// main() at startup from the sync key store; without it (tests) the
  /// column stays empty.
  String? deviceId;

  @override
  int get schemaVersion => 23;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Whether an earlier step already rebuilt the table per the current
      // definition (i.e. with sync columns).
      var beansHaveSync = false;
      var profilesHaveSync = false;
      if (from < 2) {
        // Beans tab: origin -> country, variety (unused) dropped, new fields
        // for the bean form.
        await m.renameColumn(beans, 'origin', beans.country);
        await m.dropColumn(beans, 'variety');
        await m.addColumn(beans, beans.isBlend);
        await m.addColumn(beans, beans.processing);
        await m.addColumn(beans, beans.weightGrams);
        await m.addColumn(beans, beans.taste);
        await m.addColumn(beans, beans.cost);
      }
      if (from < 3) {
        // Form extension: variety/producer + freezing/thawing.
        await m.addColumn(beans, beans.variety);
        await m.addColumn(beans, beans.producer);
        await m.addColumn(beans, beans.isFrozen);
        await m.addColumn(beans, beans.thawedDate);
      }
      if (from < 4) {
        // History tab: import shots from the machine (externalId, profile
        // color/image, machine, temperature) + stage per data point.
        await m.addColumn(shots, shots.externalId);
        await m.addColumn(shots, shots.machine);
        await m.addColumn(shots, shots.profileColor);
        await m.addColumn(shots, shots.profileImagePath);
        await m.addColumn(shots, shots.brewTemp);
        await m.addColumn(shotReadings, shotReadings.stage);
        await m.createIndex(shotReadingsShotId);
        await m.createIndex(shotsExternalId);
      }
      if (from < 5) {
        // Profile target temperature instead of measured temperature +
        // deleting shots.
        await m.addColumn(shots, shots.profileTemp);
        await m.addColumn(shots, shots.deletedAt);
      }
      if (from < 6) {
        // Store profiles locally (available offline).
        await m.createTable(storedProfiles);
      } else if (from == 6) {
        // (When created from schema 6 on, the table already has the columns.)
        await m.addColumn(storedProfiles, storedProfiles.customDescription);
        await m.addColumn(storedProfiles, storedProfiles.customImagePath);
      }
      if (from < 8) {
        // Bean form: new "Roasted for", and "Type" may stay empty.
        // Switching to nullable requires rebuilding the table (alterTable
        // copies the existing rows, so previously saved beans keep their
        // type).
        await m.addColumn(beans, beans.roastedFor);
        // Rebuilds the table per the CURRENT definition — including the
        // sync columns from schema 15, which therefore must already be
        // filled with values here.
        await m.alterTable(_beansWithSyncColumns());
        beansHaveSync = true;
      }
      if (from < 9) {
        // Rating flower: eight taste axes per shot.
        for (final column in [
          shots.tasteFinish,
          shots.tasteBody,
          shots.tasteAcidity,
          shots.tasteSweetness,
          shots.tasteHollow,
          shots.tasteSalty,
          shots.tasteAstringent,
          shots.tasteBitter,
        ]) {
          await m.addColumn(shots, column);
        }
      }
      if (from < 10) {
        // Rating chips: free extra attributes per shot.
        await m.addColumn(shots, shots.tasteExtras);
      }
      // Only for databases where the profile table existed BEFORE this
      // step: anyone coming from below 6 created it fresh above per the
      // current definition — including column and key.
      if (from >= 6 && from < 11) {
        // Second machine: profiles now belong to a machine. The primary key
        // becomes the pair (id, machine), which requires rebuilding the
        // table — alterTable copies the existing rows, which get 'meticulous'
        // via the column default.
        await m.addColumn(storedProfiles, storedProfiles.machine);
        // As with beans above: rebuilt per the current definition, i.e.
        // including the sync columns.
        await m.alterTable(_profilesWithSyncColumns());
        profilesHaveSync = true;
      }
      if (from < 12) {
        // Store the AI shot analysis on the shot.
        await m.addColumn(shots, shots.aiAnalysis);
        await m.addColumn(shots, shots.aiAnalysisModel);
        await m.addColumn(shots, shots.aiAnalysedAt);
      }
      if (from < 13) {
        // Profile at brew time on the shot (backfilled for old shots on the
        // next sync with the machine).
        await m.addColumn(shots, shots.profileJson);
      }
      if (from < 14) {
        // GaggiMate exit reasons per stage.
        await m.addColumn(shots, shots.stageExits);
      }
      if (from < 19) {
        // Grinder + burrs per shot. Before the sync rebuild of schema 15,
        // which copies the shots per the current definition and so needs
        // the columns to exist.
        await m.addColumn(shots, shots.grinder);
        await m.addColumn(shots, shots.burrs);
      }
      if (from < 20) {
        // Brew chain's gear per shot — before the rebuild of schema 15 for
        // the same reason as grinder and burrs.
        await m.addColumn(shots, shots.brewedWith);
      }
      if (from < 21) {
        // Brew chain ID per shot — before the rebuild of schema 15 as well.
        await m.addColumn(shots, shots.brewChainId);
      }
      if (from < 23) {
        // Zero point per shot — before the rebuild of schema 15 as well.
        await m.addColumn(shots, shots.grindZero);
      }
      if (from < 15) {
        // Sync foundation: syncId, updatedAt, deviceId, syncState; beans and
        // profiles also get the `deleted` tombstone. syncId is NOT NULL +
        // UNIQUE, hence a rebuild instead of addColumn.
        if (!beansHaveSync) await m.alterTable(_beansWithSyncColumns());
        if (!profilesHaveSync) await m.alterTable(_profilesWithSyncColumns());
        await m.alterTable(_shotsWithSyncColumns());
        await _deterministicSyncIds();
      }
      if (from < 16) {
        // Sync: settings.
        await m.createTable(syncedSettings);
      }
      if (from >= 15 && from < 17) {
        // Sync: references to encrypted photos. Anyone coming from below 15
        // already rebuilt (or created) both tables above per the current
        // definition — including these columns.
        await m.addColumn(beans, beans.photoBlob);
        await m.addColumn(storedProfiles, storedProfiles.customImageBlob);
      }
      if (from >= 15 && from < 18) {
        // Bean manually marked as empty (below 15: rebuilt above).
        await m.addColumn(beans, beans.emptiedAt);
      }
      if (from >= 15 && from < 22) {
        // Roast level (below 15: rebuilt above).
        await m.addColumn(beans, beans.roastLevel);
      }
    },
  );

  // Existing rows count as the user's state at migration time — NOT as 0
  // like a fresh import, otherwise an empty copy on a new device could
  // overwrite ratings and notes.
  Map<GeneratedColumn, Expression> _syncTransformer(
    GeneratedColumn<String> syncId,
    GeneratedColumn<int> updatedAt,
  ) => {
    syncId: const CustomExpression<String>(sqlRandomUuidV4),
    updatedAt: Constant(clock.now().millisecondsSinceEpoch),
  };

  TableMigration _beansWithSyncColumns() => TableMigration(
    beans,
    newColumns: [
      beans.syncId,
      beans.updatedAt,
      beans.deviceId,
      beans.syncState,
      beans.deleted,
      beans.photoBlob,
      beans.emptiedAt,
      beans.roastLevel,
    ],
    columnTransformer: _syncTransformer(beans.syncId, beans.updatedAt),
  );

  TableMigration _profilesWithSyncColumns() => TableMigration(
    storedProfiles,
    newColumns: [
      storedProfiles.syncId,
      storedProfiles.updatedAt,
      storedProfiles.deviceId,
      storedProfiles.syncState,
      storedProfiles.deleted,
      storedProfiles.customImageBlob,
    ],
    columnTransformer: _syncTransformer(
      storedProfiles.syncId,
      storedProfiles.updatedAt,
    ),
  );

  TableMigration _shotsWithSyncColumns() => TableMigration(
    shots,
    newColumns: [
      shots.syncId,
      shots.updatedAt,
      shots.deviceId,
      shots.syncState,
    ],
    columnTransformer: _syncTransformer(shots.syncId, shots.updatedAt),
  );

  // Machine shots and profiles get the deterministic ID (sync_ids.dart)
  // instead of the random one, which another device also assigns on its
  // own import.
  Future<void> _deterministicSyncIds() async {
    final machineShots =
        await (selectOnly(shots)
              ..addColumns([shots.id, shots.machine, shots.externalId])
              ..where(shots.externalId.isNotNull()))
            .get();
    final profiles = await (selectOnly(
      storedProfiles,
    )..addColumns([storedProfiles.id, storedProfiles.machine])).get();
    await batch((b) {
      for (final row in machineShots) {
        b.update(
          shots,
          ShotsCompanion(
            syncId: Value(
              machineShotSyncId(
                row.read(shots.machine)!,
                row.read(shots.externalId)!,
              ),
            ),
          ),
          where: (s) => s.id.equals(row.read(shots.id)!),
        );
      }
      for (final row in profiles) {
        final id = row.read(storedProfiles.id)!;
        final machine = row.read(storedProfiles.machine)!;
        b.update(
          storedProfiles,
          StoredProfilesCompanion(
            syncId: Value(machineProfileSyncId(machine, id)),
          ),
          where: (p) => p.id.equals(id) & p.machine.equals(machine),
        );
      }
    });
  }

  // ---- Sync stamps ----
  //
  // EVERY change a user makes goes through one of these helpers: new
  // timestamp, this device, pending upload. Derived data that each device
  // fetches from the machine itself (backfill…) deliberately does NOT stamp
  // — otherwise a backfill on device A would beat a newer rating on
  // device B.

  int _now() => clock.now().millisecondsSinceEpoch;

  // New (or removed) photo: the old reference is no longer valid, the new
  // one is uploaded on the next send.
  BeansCompanion _stampBean(BeansCompanion c) => c.copyWith(
    photoBlob: c.photoPath.present ? const Value(null) : c.photoBlob,
    updatedAt: Value(_now()),
    deviceId: Value(deviceId),
    syncState: const Value(SyncState.pending),
  );

  ShotsCompanion _stampShot(ShotsCompanion c) => c.copyWith(
    updatedAt: Value(_now()),
    deviceId: Value(deviceId),
    syncState: const Value(SyncState.pending),
  );

  StoredProfilesCompanion _stampProfile(StoredProfilesCompanion c) =>
      c.copyWith(
        updatedAt: Value(_now()),
        deviceId: Value(deviceId),
        syncState: const Value(SyncState.pending),
      );

  // Update a shot as long as it is not a tombstone.
  Future<void> _writeShot(int id, ShotsCompanion c) => (update(
    shots,
  )..where((s) => s.id.equals(id) & s.deletedAt.isNull())).write(_stampShot(c));

  // What remains of a deleted bean (deleteBean and sync).
  static const beanTombstone = BeansCompanion(
    deleted: Value(true),
    name: Value(''),
    roaster: Value(null),
    roastDate: Value(null),
    isBlend: Value(null),
    roastedFor: Value(null),
    roastLevel: Value(null),
    country: Value(null),
    processing: Value(null),
    variety: Value(null),
    producer: Value(null),
    weightGrams: Value(null),
    taste: Value(null),
    cost: Value(null),
    photoPath: Value(null),
    photoBlob: Value(null),
    isFrozen: Value(false),
    thawedDate: Value(null),
    emptiedAt: Value(null),
  );

  // Without deleted beans (tombstones) — applies to all read paths below.
  Stream<List<Bean>> watchBeans() =>
      (select(beans)..where((b) => b.deleted.equals(false))).watch();

  Future<List<Bean>> allBeans() =>
      (select(beans)..where((b) => b.deleted.equals(false))).get();

  /// Whether the bean (still) exists — a shot only links existing ones.
  Future<bool> beanExists(int id) async =>
      await (select(beans)
            ..where((b) => b.id.equals(id) & b.deleted.equals(false)))
          .getSingleOrNull() !=
      null;

  // Grams used per bean: sum of the doses of all shots with this bean
  // (shots without a dose don't count). Basis for the remaining amount.
  Stream<Map<int, double>> watchBeanUsage() =>
      customSelect(
        'SELECT bean_id, SUM(dose_grams) AS used FROM shots '
        'WHERE bean_id IS NOT NULL AND dose_grams IS NOT NULL GROUP BY bean_id',
        readsFrom: {shots},
      ).watch().map(
        (rows) => {
          for (final r in rows) r.read<int>('bean_id'): r.read<double>('used'),
        },
      );

  // Shots per grinder name (excluding deleted ones) — the shot counter on My
  // Coffee Desk. Shots keep the grinder as text, so a renamed grinder
  // starts counting anew.
  Stream<Map<String, int>> watchGrinderShotCounts() =>
      customSelect(
        'SELECT grinder, COUNT(*) AS n FROM shots '
        'WHERE grinder IS NOT NULL AND deleted_at IS NULL GROUP BY grinder',
        readsFrom: {shots},
      ).watch().map(
        (rows) => {
          for (final r in rows) r.read<String>('grinder'): r.read<int>('n'),
        },
      );

  Future<Bean> insertBean(BeansCompanion bean) =>
      into(beans).insertReturning(_stampBean(bean));

  Future<Bean> updateBean(int id, BeansCompanion bean) async {
    await (update(
      beans,
    )..where((b) => b.id.equals(id))).write(_stampBean(bean));
    return (select(beans)..where((b) => b.id.equals(id))).getSingle();
  }

  // ---- Stored profiles ----

  // [machine] limits to the profiles of one machine; without it all are
  // returned (the history has no machine boundary).
  Stream<List<StoredProfile>> watchStoredProfiles({String? machine}) {
    final query = select(storedProfiles)
      ..where((p) => p.deleted.equals(false))
      ..orderBy([
        (p) => OrderingTerm.asc(p.position),
        (p) => OrderingTerm.asc(p.name),
      ]);
    if (machine != null) query.where((p) => p.machine.equals(machine));
    return query.watch();
  }

  Stream<StoredProfile?> watchStoredProfile(String id, {String? machine}) {
    final query = select(storedProfiles)
      ..where((p) => p.id.equals(id) & p.deleted.equals(false));
    if (machine != null) query.where((p) => p.machine.equals(machine));
    return query.watchSingleOrNull();
  }

  Future<StoredProfile?> storedProfile(String id, {required String machine}) =>
      (select(storedProfiles)..where(
            (p) =>
                p.id.equals(id) &
                p.machine.equals(machine) &
                p.deleted.equals(false),
          ))
          .getSingleOrNull();

  // Find a profile by its name: shots store only the profile name, but the
  // Pre-Shot card needs the ID (to load it on the machine).
  Future<StoredProfile?> storedProfileByName(String name, {String? machine}) {
    final query = select(storedProfiles)
      ..where((p) => p.name.equals(name) & p.deleted.equals(false))
      ..orderBy([(p) => OrderingTerm.asc(p.position)])
      ..limit(1);
    if (machine != null) query.where((p) => p.machine.equals(machine));
    return query.getSingleOrNull();
  }

  Future<Map<String, StoredProfile>> storedProfilesById({
    String? machine,
  }) async {
    final query = select(storedProfiles)..where((p) => p.deleted.equals(false));
    if (machine != null) query.where((p) => p.machine.equals(machine));
    return {for (final p in await query.get()) p.id: p};
  }

  // New order of the profile row (long press and drag). [ids] in the
  // desired order; only changed positions are written, profiles not listed
  // stay where they are.
  Future<void> setStoredProfileOrder(
    List<String> ids, {
    required String machine,
  }) => transaction(() async {
    for (var i = 0; i < ids.length; i++) {
      await (update(storedProfiles)..where(
            (p) =>
                p.id.equals(ids[i]) &
                p.machine.equals(machine) &
                p.position.equals(i).not(),
          ))
          .write(_stampProfile(StoredProfilesCompanion(position: Value(i))));
    }
  });

  Future<void> setProfileCustomDescription(
    String id,
    String? text, {
    required String machine,
  }) {
    final trimmed = text?.trim();
    return (update(
      storedProfiles,
    )..where((p) => p.id.equals(id) & p.machine.equals(machine))).write(
      _stampProfile(
        StoredProfilesCompanion(
          customDescription: Value(
            trimmed == null || trimmed.isEmpty ? null : trimmed,
          ),
        ),
      ),
    );
  }

  Future<void> setProfileCustomImage(
    String id,
    String? path, {
    required String machine,
  }) =>
      (update(
        storedProfiles,
      )..where((p) => p.id.equals(id) & p.machine.equals(machine))).write(
        _stampProfile(
          StoredProfilesCompanion(
            customImagePath: Value(path),
            customImageBlob: const Value(null),
          ),
        ),
      );

  /// Save a profile as the machine delivers it. [profile] must carry id and
  /// machine. A new profile counts as a fresh import (updatedAt 0), a
  /// changed version as a change — it should also reach a device that
  /// currently can't see the machine.
  Future<void> upsertStoredProfile(StoredProfilesCompanion profile) =>
      transaction(() async {
        final id = profile.id.value;
        // Without a value, the column default applies.
        final machine = profile.machine.present
            ? profile.machine.value
            : 'meticulous';
        final where =
            storedProfiles.id.equals(id) &
            storedProfiles.machine.equals(machine);
        final exists = await (select(
          storedProfiles,
        )..where((_) => where)).getSingleOrNull();
        if (exists == null) {
          await into(storedProfiles).insert(
            profile.copyWith(
              machine: Value(machine),
              syncId: Value(machineProfileSyncId(machine, id)),
              updatedAt: const Value(0),
              deviceId: Value(deviceId),
            ),
          );
        } else {
          // A tombstone also comes back to life here: the profile is back
          // on the machine.
          await (update(storedProfiles)..where((_) => where)).write(
            _stampProfile(profile.copyWith(deleted: const Value(false))),
          );
        }
      });

  // Tombstone instead of deleting so the deletion reaches the other devices.
  // The profile data is dropped, only key + sync columns remain.
  Future<void> deleteStoredProfile(String id, {required String machine}) =>
      (update(
        storedProfiles,
      )..where((p) => p.id.equals(id) & p.machine.equals(machine))).write(
        _stampProfile(
          const StoredProfilesCompanion(
            deleted: Value(true),
            json: Value(''),
            imagePath: Value(null),
            customDescription: Value(null),
            customImagePath: Value(null),
            customImageBlob: Value(null),
          ),
        ),
      );

  // ---- Shots / History ----

  // Without deleted shots (tombstones).
  JoinedSelectStatement<HasResultSet, dynamic> _shotEntryQuery() =>
      select(shots).join([
        leftOuterJoin(
          beans,
          beans.id.equalsExp(shots.beanId) & beans.deleted.equals(false),
        ),
      ])..where(shots.deletedAt.isNull());

  ShotEntry _toEntry(TypedResult row) =>
      ShotEntry(row.readTable(shots), row.readTableOrNull(beans));

  // Newest first.
  Stream<List<ShotEntry>> watchShotEntries() {
    final query = _shotEntryQuery()
      ..orderBy([OrderingTerm.desc(shots.timestamp)]);
    return query.watch().map((rows) => rows.map(_toEntry).toList());
  }

  // [machine] limits to one machine (key as in Shots.machine): the
  // Post-Shot card of a home screen only shows brews of its own machine.
  Stream<ShotEntry?> watchLatestShotEntry({String? machine}) {
    final query = _shotEntryQuery()
      ..orderBy([OrderingTerm.desc(shots.timestamp)])
      ..limit(1);
    if (machine != null) query.where(shots.machine.equals(machine));
    return query.watch().map(
      (rows) => rows.isEmpty ? null : _toEntry(rows.first),
    );
  }

  Stream<ShotEntry?> watchShotEntry(int id) {
    final query = _shotEntryQuery()..where(shots.id.equals(id));
    return query.watch().map(
      (rows) => rows.isEmpty ? null : _toEntry(rows.first),
    );
  }

  Future<List<ShotReading>> readingsFor(int shotId) =>
      (select(shotReadings)
            ..where((r) => r.shotId.equals(shotId))
            ..orderBy([(r) => OrderingTerm.asc(r.timeMs)]))
          .get();

  // Own usage of a profile. [machine] is required (key as in Shots.machine):
  // profile names are only unique within a machine; without the restriction,
  // same-named profiles of two machines would share their shots.
  Future<ProfileUsage> profileUsage(
    String profileName, {
    required String machine,
  }) async {
    final row =
        await (selectOnly(shots)
              ..addColumns([
                shots.id.count(),
                shots.timestamp.max(),
                shots.rating.avg(),
              ])
              ..where(
                shots.profileName.equals(profileName) &
                    shots.machine.equals(machine) &
                    shots.deletedAt.isNull(),
              ))
            .getSingle();
    return ProfileUsage(
      count: row.read(shots.id.count()) ?? 0,
      lastUsed: row.read(shots.timestamp.max()),
      averageRating: row.read(shots.rating.avg()),
    );
  }

  // Most recent real shot (without tombstones). Provides the values used to
  // prefill the Pre-Shot card at app start.
  Future<Shot?> lastShot({String? machine}) {
    final query = select(shots)
      ..where((s) => s.deletedAt.isNull())
      ..orderBy([(s) => OrderingTerm.desc(s.timestamp)])
      ..limit(1);
    if (machine != null) query.where((s) => s.machine.equals(machine));
    return query.getSingleOrNull();
  }

  // Brew chain IDs of the latest shots of [machine] that name one, newest
  // first.
  Future<List<String>> recentChainIds({
    required String machine,
    int limit = 20,
  }) async {
    final query = selectOnly(shots)
      ..addColumns([shots.brewChainId])
      ..where(
        shots.deletedAt.isNull() &
            shots.brewChainId.isNotNull() &
            shots.machine.equals(machine),
      )
      ..orderBy([OrderingTerm.desc(shots.timestamp)])
      ..limit(limit);
    return [for (final row in await query.get()) row.read(shots.brewChainId)!];
  }

  // Most recent shot with this profile (and optionally this bean) that
  // carries any setup values at all — a shot without dose AND without grind
  // size doesn't help prefilling, so it is skipped.
  Future<Shot?> lastShotWithSetup({
    required String profileName,
    int? beanId,
    String? machine,
  }) {
    final query = select(shots)
      ..where(
        (s) =>
            s.deletedAt.isNull() &
            s.profileName.equals(profileName) &
            (s.doseGrams.isNotNull() | s.grindSize.isNotNull()),
      )
      ..orderBy([(s) => OrderingTerm.desc(s.timestamp)])
      ..limit(1);
    if (beanId != null) query.where((s) => s.beanId.equals(beanId));
    if (machine != null) query.where((s) => s.machine.equals(machine));
    return query.getSingleOrNull();
  }

  Future<Set<String>> knownExternalIds() async {
    final rows =
        await (selectOnly(shots)
              ..addColumns([shots.externalId])
              ..where(shots.externalId.isNotNull()))
            .get();
    return {for (final r in rows) r.read(shots.externalId)!};
  }

  Future<void> setShotRating(int id, int? rating) => _writeShot(
    id,
    ShotsCompanion(rating: Value(rating == 0 ? null : rating)),
  );

  /// Set a value of the rating flower; 0 clears it.
  Future<void> setShotTaste(int id, TasteAxis axis, int value) {
    final v = Value(value <= 0 ? null : value.clamp(1, TasteAxis.maxValue));
    final companion = switch (axis) {
      TasteAxis.finish => ShotsCompanion(tasteFinish: v),
      TasteAxis.body => ShotsCompanion(tasteBody: v),
      TasteAxis.acidity => ShotsCompanion(tasteAcidity: v),
      TasteAxis.sweetness => ShotsCompanion(tasteSweetness: v),
      TasteAxis.hollow => ShotsCompanion(tasteHollow: v),
      TasteAxis.salty => ShotsCompanion(tasteSalty: v),
      TasteAxis.astringent => ShotsCompanion(tasteAstringent: v),
      TasteAxis.bitter => ShotsCompanion(tasteBitter: v),
    };
    return _writeShot(id, companion);
  }

  /// Replace a shot's free extra attributes.
  Future<void> setShotTasteExtras(int id, Iterable<String> extras) =>
      _writeShot(
        id,
        ShotsCompanion(tasteExtras: Value(joinTasteExtras(extras))),
      );

  /// Recently used free attributes, most recent shot first — the suggestion
  /// list of the rating chips. If the same attribute appears several times,
  /// the spelling of the most recent shot wins.
  Stream<List<String>> watchRecentTasteExtras({int shotLimit = 60}) {
    final query = select(shots)
      ..where((s) => s.deletedAt.isNull() & s.tasteExtras.isNotNull())
      ..orderBy([(s) => OrderingTerm.desc(s.timestamp)])
      ..limit(shotLimit);
    return query.watch().map((rows) {
      final byKey = <String, String>{};
      for (final row in rows) {
        for (final extra in splitTasteExtras(row.tasteExtras)) {
          byKey.putIfAbsent(extra.toLowerCase(), () => extra);
        }
      }
      return byKey.values.toList();
    });
  }

  Future<void> setShotDose(int id, double? dose) =>
      _writeShot(id, ShotsCompanion(doseGrams: Value(dose)));

  Future<void> setShotGrind(int id, String? grind) =>
      _writeShot(id, ShotsCompanion(grindSize: Value(grind)));

  /// The brew chain chosen afterwards in the shot detail, with what it
  /// holds now (grinder, burrs, pieces).
  Future<void> setShotChain(
    int id, {
    required String? chainId,
    required String? grinder,
    required String? burrs,
    required String? brewedWith,
    double? grindZero,
  }) => _writeShot(
    id,
    ShotsCompanion(
      brewChainId: Value(chainId),
      grindZero: Value(grindZero),
      grinder: Value(grinder),
      burrs: Value(burrs),
      brewedWith: Value(brewedWith),
    ),
  );

  Future<void> setShotBean(int id, int? beanId) =>
      _writeShot(id, ShotsCompanion(beanId: Value(beanId)));

  Future<void> setShotNotes(int id, String? notes) {
    final trimmed = notes?.trim();
    return _writeShot(
      id,
      ShotsCompanion(
        notes: Value(trimmed == null || trimmed.isEmpty ? null : notes),
      ),
    );
  }

  /// Store an AI analysis on the shot (overwrites an earlier one).
  Future<void> setShotAnalysis(
    int id, {
    required String json,
    required String model,
    DateTime? at,
  }) => _writeShot(
    id,
    ShotsCompanion(
      aiAnalysis: Value(json),
      aiAnalysisModel: Value(model),
      aiAnalysedAt: Value(at ?? DateTime.now()),
    ),
  );

  /// Earlier shots of the same bean before [before], newest first — the
  /// history passed to the shot analysis.
  Future<List<Shot>> earlierShotsOfBean(
    int beanId, {
    required DateTime before,
    int limit = 5,
  }) =>
      (select(shots)
            ..where(
              (s) =>
                  s.deletedAt.isNull() &
                  s.beanId.equals(beanId) &
                  s.timestamp.isSmallerThanValue(before),
            )
            ..orderBy([(s) => OrderingTerm.desc(s.timestamp)])
            ..limit(limit))
          .get();

  // Delete shots from the app (time series gone). Each one stays as a
  // tombstone: machine-imported ones so they aren't imported again, and all
  // of them so the deletion reaches the other devices.
  Future<void> deleteShots(Iterable<int> ids) => transaction(() async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (delete(shotReadings)..where((r) => r.shotId.isIn(list))).go();
    await (update(shots)..where((s) => s.id.isIn(list) & s.deletedAt.isNull()))
        .write(_stampShot(shotTombstone(DateTime.now())));
  });

  /// What remains of a deleted shot: timestamp, machine and machine ID
  /// (left untouched), everything else empty.
  static ShotsCompanion shotTombstone(DateTime deletedAt) => ShotsCompanion(
    deletedAt: Value(deletedAt),
    beanId: const Value(null),
    profileName: const Value(null),
    profileColor: const Value(null),
    profileImagePath: const Value(null),
    doseGrams: const Value(null),
    finalWeight: const Value(null),
    durationMs: const Value(null),
    grindSize: const Value(null),
    rating: const Value(null),
    notes: const Value(null),
    shotPhotoPath: const Value(null),
    rawDebugJson: const Value(null),
    brewTemp: const Value(null),
    profileTemp: const Value(null),
    aiAnalysis: const Value(null),
    aiAnalysisModel: const Value(null),
    aiAnalysedAt: const Value(null),
    profileJson: const Value(null),
    stageExits: const Value(null),
    tasteFinish: const Value(null),
    tasteBody: const Value(null),
    tasteAcidity: const Value(null),
    tasteSweetness: const Value(null),
    tasteHollow: const Value(null),
    tasteSalty: const Value(null),
    tasteAstringent: const Value(null),
    tasteBitter: const Value(null),
    tasteExtras: const Value(null),
  );

  // Backfills the profile at brew time for shots that don't have it yet
  // (schema 13). The machine's short list provides it per shot.
  Future<void> backfillShotProfiles(Map<String, String> byExternalId) async {
    if (byExternalId.isEmpty) return;
    final missing =
        await (selectOnly(shots)
              ..addColumns([shots.externalId])
              ..where(
                shots.profileJson.isNull() &
                    shots.externalId.isNotNull() &
                    shots.deletedAt.isNull(),
              ))
            .get();
    await batch((b) {
      for (final row in missing) {
        final id = row.read(shots.externalId)!;
        final json = byExternalId[id];
        if (json == null) continue;
        b.update(
          shots,
          ShotsCompanion(profileJson: Value(json)),
          where: (s) => s.externalId.equals(id),
        );
      }
    });
  }

  // Adds the target temperature to already imported shots (schema v5; the
  // machine's short list contains it per shot in the profile).
  Future<void> backfillProfileTemps(Map<String, double> byExternalId) async {
    if (byExternalId.isEmpty) return;
    final missing =
        await (selectOnly(shots)
              ..addColumns([shots.externalId])
              ..where(
                shots.profileTemp.isNull() &
                    shots.externalId.isNotNull() &
                    shots.deletedAt.isNull(),
              ))
            .get();
    await batch((b) {
      for (final row in missing) {
        final id = row.read(shots.externalId)!;
        final temp = byExternalId[id];
        if (temp == null) continue;
        b.update(
          shots,
          ShotsCompanion(profileTemp: Value(temp)),
          where: (s) => s.externalId.equals(id),
        );
      }
    });
  }

  // Shot + time series in one transaction: either everything is there or
  // nothing.
  //
  // Machine shots (with externalId) get the deterministic syncId.
  // [untouchedImport]: the shot comes from the machine as is, with nothing
  // added by the user (bean, dose, grind size) — updatedAt 0 so it never
  // overwrites a rating on another device.
  Future<int> insertShotWithReadings(
    ShotsCompanion shot,
    List<ShotReadingsCompanion Function(int shotId)> readings, {
    bool untouchedImport = false,
  }) => transaction(() async {
    var row = _stampShot(shot);
    if (untouchedImport) row = row.copyWith(updatedAt: const Value(0));
    if (shot.externalId.present && shot.externalId.value != null) {
      row = row.copyWith(
        syncId: Value(
          machineShotSyncId(
            shot.machine.present ? shot.machine.value : 'meticulous',
            shot.externalId.value!,
          ),
        ),
      );
    }
    final id = await into(shots).insert(row);
    await batch((b) {
      b.insertAll(shotReadings, [for (final r in readings) r(id)]);
    });
    return id;
  });

  // The bean stays as a tombstone (name empty, all details gone) so the
  // deletion reaches the other devices. The shots stay UNTOUCHED and keep
  // pointing to the tombstone — all read paths treat it as "no bean", as
  // does sync on the other devices. Previously each shot's bean was cleared
  // and thereby re-stamped; since sync is per record, that overwrote the
  // other device's complete version (data loss).
  Future<void> deleteBean(int id) => (update(
    beans,
  )..where((b) => b.id.equals(id))).write(_stampBean(beanTombstone));

  /// How many shots carry this bean (excluding deleted ones) — for the
  /// delete dialog.
  Future<int> countShotsOfBean(int beanId) async {
    final count = shots.id.count();
    final row =
        await (selectOnly(shots)
              ..addColumns([count])
              ..where(shots.beanId.equals(beanId) & shots.deletedAt.isNull()))
            .getSingle();
    return row.read(count) ?? 0;
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    // The file name stays 'coffee_app.sqlite' even though the app is now
    // called bean'd: on already installed devices the DB lives under this
    // name. Renaming would open an empty DB — only change with a migration
    // (copy the old file) and a prior backup.
    final file = File(p.join(dbFolder.path, 'coffee_app.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

extension ShotTaste on Shot {
  /// The eight axes of the rating flower as a map; not rated is 0.
  List<String> get tasteExtraList => splitTasteExtras(tasteExtras);

  TasteValues get tasteValues => {
    TasteAxis.finish: tasteFinish ?? 0,
    TasteAxis.body: tasteBody ?? 0,
    TasteAxis.acidity: tasteAcidity ?? 0,
    TasteAxis.sweetness: tasteSweetness ?? 0,
    TasteAxis.hollow: tasteHollow ?? 0,
    TasteAxis.salty: tasteSalty ?? 0,
    TasteAxis.astringent: tasteAstringent ?? 0,
    TasteAxis.bitter: tasteBitter ?? 0,
  };
}
