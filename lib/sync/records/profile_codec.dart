import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/database.dart';
import 'bean_codec.dart' show photoFromSyncData;

// Stored profile ↔ `data` in the sync event. Without the local image paths
// and without the sync columns. The custom image goes along as a reference
// to the photo servers (`customImage`, phase 4); each device fetches the
// machine's image itself as soon as it sees the machine.

const profileType = 'profile';

const _localProfileFields = {
  'imagePath',
  'customImagePath',
  'customImageBlob',
  'syncId',
  'updatedAt',
  'deviceId',
  'syncState',
  'deleted',
};

/// [includeImage]: as for the bean photo (bean_codec.dart).
Map<String, Object?> profileToSyncData(
  StoredProfile p, {
  bool includeImage = true,
}) {
  if (p.deleted) return {'id': p.id, 'machine': p.machine};
  return p.toJson()
    ..removeWhere((k, _) => _localProfileFields.contains(k))
    ..addAll({
      if (includeImage)
        'customImage': p.customImageBlob == null
            ? null
            : jsonDecode(p.customImageBlob!),
    });
}

/// Throws [FormatException] if required fields are missing.
StoredProfilesCompanion profileFromSyncData(
  Map<String, Object?> data, {
  required bool deleted,
}) {
  final id = data['id'];
  final machine = data['machine'];
  if (id is! String || machine is! String) {
    throw const FormatException('Profile without id/machine');
  }
  if (deleted) {
    return StoredProfilesCompanion(
      id: Value(id),
      machine: Value(machine),
      name: const Value(''),
      json: const Value(''),
      fetchedAt: Value(DateTime.now()),
    );
  }
  final StoredProfile profile;
  final image = photoFromSyncData(data, 'customImage');
  try {
    profile = StoredProfile.fromJson({
      ...data,
      'imagePath': null,
      'customImagePath': null,
      'customImageBlob': null,
      'syncId': '',
      'updatedAt': 0,
      'deviceId': null,
      'syncState': SyncState.synced,
      'deleted': false,
    });
  } catch (e) {
    throw FormatException('Profile data does not fit: $e');
  }
  return profile
      .toCompanion(true)
      .copyWith(
        imagePath: const Value.absent(),
        customImagePath: const Value.absent(),
        customImageBlob: image,
        syncId: const Value.absent(),
        updatedAt: const Value.absent(),
        deviceId: const Value.absent(),
        syncState: const Value.absent(),
        deleted: const Value.absent(),
      );
}
