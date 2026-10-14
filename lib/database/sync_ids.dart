import 'package:uuid/uuid.dart';

// Sync identifiers of the records. The int IDs remain the primary keys in
// the app; across devices only the syncId counts.

const _uuid = Uuid();

// Fixed namespace for the deterministic IDs below. NEVER change: otherwise
// the same machine shot gets two different IDs on two devices.
const _beandNamespace = '3d2d72f7-cba4-49dc-91e2-58872da16ded';

/// Random ID for everything created in the app (beans, pour-over brews).
String newSyncId() => _uuid.v4();

/// Shot delivered by the machine: each device imports it itself from the
/// machine's history, so the same ID must come out everywhere — otherwise
/// it shows up twice after sync.
String machineShotSyncId(String machine, String externalId) =>
    _uuid.v5(_beandNamespace, 'shot:$machine:$externalId');

/// Profile of a machine, deterministic for the same reason.
String machineProfileSyncId(String machine, String profileId) =>
    _uuid.v5(_beandNamespace, 'profile:$machine:$profileId');

/// SQL expression for a random UUID v4 — only for the migration that gives
/// existing rows an ID in one go.
const sqlRandomUuidV4 =
    "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || "
    "substr(lower(hex(randomblob(2))), 2) || '-' || "
    "substr('89ab', abs(random()) % 4 + 1, 1) || "
    "substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6)))";

/// Setting: the same record on all devices per key.
String settingSyncId(String key) => _uuid.v5(_beandNamespace, 'setting:$key');
