import 'dart:convert';
import 'dart:io';

// Plain text of every sync event (before NIP-44 encryption):
//
//   {"v":1,"type":"bean","id":"<syncId>","updatedAt":…,"deviceId":"…",
//    "deleted":false,"enc":"gzip+base64","data":"…"}
//
// `data` is the gzip-compressed, base64-encoded JSON of the record.

const syncEnvelopeVersion = 1;
const _encoding = 'gzip+base64';

/// Too large for an event: the whole envelope is stored gzip-compressed and
/// encrypted on the photo servers; `data` is only the reference (BlobRef).
const _blobEncoding = 'blob';

/// Largest plain text (UTF-8 bytes) that still goes inline into an event;
/// beyond that the record goes as a blob.
///
/// Not the NIP-44 maximum (65,535), but what the relays accept: strfry
/// (damus, nos.lol, primal, …) rejects events over 65,536 bytes of JSON by
/// default. NIP-44 pads 40,960 bytes to 40,960 and base64 makes that
/// 54,704 characters of content, plus id/pubkey/sig/tags well under 64 KiB.
/// One byte more pads to 49,152 → 65,628 characters → rejected.
/// test/sync/envelope_size_test.dart guards this.
const maxInlineEnvelopeBytes = 40960;

class SyncEnvelope {
  const SyncEnvelope({
    required this.type,
    required this.id,
    required this.updatedAt,
    required this.deviceId,
    required this.deleted,
    required this.data,
    this.blobRef,
  });

  final String type;
  final String id;
  final int updatedAt;
  final String deviceId;
  final bool deleted;

  /// The record itself; empty for tombstones.
  final Map<String, Object?> data;

  /// Set when the record is offloaded: then [data] is empty and the full
  /// envelope must be fetched first.
  final Map<String, Object?>? blobRef;

  String encode() => jsonEncode({
    'v': syncEnvelopeVersion,
    'type': type,
    'id': id,
    'updatedAt': updatedAt,
    'deviceId': deviceId,
    'deleted': deleted,
    'enc': blobRef != null ? _blobEncoding : _encoding,
    'data':
        blobRef ?? base64.encode(gzip.encode(utf8.encode(jsonEncode(data)))),
  });

  /// Throws [FormatException] on unknown version, missing fields or broken
  /// data — the caller then skips the event.
  factory SyncEnvelope.decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      throw const FormatException('Envelope is not JSON');
    }
    if (json is! Map) throw const FormatException('Envelope is not an object');
    if (json['v'] != syncEnvelopeVersion) {
      throw FormatException('Unsupported envelope version ${json['v']}');
    }
    if (json['type'] is! String ||
        json['id'] is! String ||
        json['updatedAt'] is! int ||
        json['deviceId'] is! String ||
        json['deleted'] is! bool) {
      throw const FormatException('Envelope fields missing');
    }
    var data = <String, Object?>{};
    Map<String, Object?>? blobRef;
    final raw = json['data'];
    if (json['enc'] == _blobEncoding) {
      if (raw is! Map) throw const FormatException('Blob reference missing');
      blobRef = Map<String, Object?>.from(raw);
    } else if (raw is String && raw.isNotEmpty) {
      if (json['enc'] != _encoding) {
        throw FormatException('Unknown encoding ${json['enc']}');
      }
      try {
        final decoded = jsonDecode(
          utf8.decode(gzip.decode(base64.decode(raw))),
        );
        if (decoded is! Map) throw const FormatException('data');
        data = Map<String, Object?>.from(decoded);
      } catch (_) {
        throw const FormatException('Envelope data is damaged');
      }
    }
    return SyncEnvelope(
      type: json['type'] as String,
      id: json['id'] as String,
      updatedAt: json['updatedAt'] as int,
      deviceId: json['deviceId'] as String,
      deleted: json['deleted'] as bool,
      data: data,
      blobRef: blobRef,
    );
  }
}
