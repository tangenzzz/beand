import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/database.dart';
import '../blobs/blob_ref.dart';

// Bean ↔ `data` in the sync event. Not included: the local int ID and the
// photo path. Times as Unix ms.
//
// Fields an older device does not know are simply left untouched on import
// (missing in [beanFromSyncData]); unknown fields are ignored. This way
// later versions can add fields.

const beanType = 'bean';

/// [includePhoto]: false while a photo exists but is not (yet) on a photo
/// server — then the field is omitted entirely, and the other devices keep
/// their photo. `photo: null` on the other hand would mean "photo removed".
Map<String, Object?> beanToSyncData(Bean b, {bool includePhoto = true}) => {
  'name': b.name,
  'roaster': b.roaster,
  'roastDate': b.roastDate?.millisecondsSinceEpoch,
  'isBlend': b.isBlend,
  'roastedFor': b.roastedFor,
  'country': b.country,
  'processing': b.processing,
  'variety': b.variety,
  'producer': b.producer,
  'weightGrams': b.weightGrams,
  'taste': b.taste,
  'cost': b.cost,
  'isFrozen': b.isFrozen,
  'thawedDate': b.thawedDate?.millisecondsSinceEpoch,
  'emptiedAt': b.emptiedAt?.millisecondsSinceEpoch,
  'createdAt': b.createdAt.millisecondsSinceEpoch,
  if (includePhoto)
    'photo': b.photoBlob == null ? null : jsonDecode(b.photoBlob!),
};

/// Photo field of a received record: absent = unknown (keep local),
/// null = removed, otherwise the reference as JSON.
Value<String?> photoFromSyncData(Map<String, Object?> d, String key) {
  if (!d.containsKey(key)) return const Value.absent();
  final ref = d[key];
  if (ref == null) return const Value(null);
  return Value(BlobRef.fromJson(ref).encode());
}

/// Throws [FormatException] if a field has the wrong type.
BeansCompanion beanFromSyncData(Map<String, Object?> d) {
  Value<T> field<T>(String key) {
    if (!d.containsKey(key)) return const Value.absent();
    final v = d[key];
    if (v != null && v is! T) {
      throw FormatException('Bean field $key has the wrong type');
    }
    return Value(v as T);
  }

  Value<double?> number(String key) {
    if (!d.containsKey(key)) return const Value.absent();
    final v = d[key];
    if (v != null && v is! num) {
      throw FormatException('Bean field $key has the wrong type');
    }
    return Value((v as num?)?.toDouble());
  }

  Value<DateTime?> date(String key) {
    final ms = field<int?>(key);
    if (!ms.present) return const Value.absent();
    final v = ms.value;
    return Value(v == null ? null : DateTime.fromMillisecondsSinceEpoch(v));
  }

  final name = d['name'];
  if (name is! String) throw const FormatException('Bean without name');
  final created = date('createdAt');
  return BeansCompanion(
    name: Value(name),
    roaster: field<String?>('roaster'),
    roastDate: date('roastDate'),
    isBlend: field<bool?>('isBlend'),
    roastedFor: field<String?>('roastedFor'),
    country: field<String?>('country'),
    processing: field<String?>('processing'),
    variety: field<String?>('variety'),
    producer: field<String?>('producer'),
    weightGrams: number('weightGrams'),
    taste: field<String?>('taste'),
    cost: number('cost'),
    isFrozen: d['isFrozen'] is bool
        ? Value(d['isFrozen'] as bool)
        : const Value.absent(),
    thawedDate: date('thawedDate'),
    emptiedAt: date('emptiedAt'),
    photoBlob: photoFromSyncData(d, 'photo'),
    createdAt: created.present && created.value != null
        ? Value(created.value!)
        : const Value.absent(),
  );
}
