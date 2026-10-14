import 'dart:convert';

// Reference to an encrypted file on Blossom servers: where it lives, how to
// recognize it and how to decrypt it. Stored in the (itself encrypted) sync
// record — the server only sees random bytes.

class BlobRef {
  const BlobRef({
    required this.sha256,
    required this.size,
    required this.key,
    required this.nonce,
    required this.urls,
    this.extension = '',
  });

  /// sha256 of the ENCRYPTED file (that is how Blossom addresses it).
  final String sha256;
  final int size;

  /// XChaCha20-Poly1305: 32-byte key, 24-byte nonce (base64).
  final String key;
  final String nonce;

  /// Where it was uploaded; every Blossom server also serves it under
  /// `/<sha256>`.
  final List<String> urls;

  /// File extension of the original (".jpg"), for the local copy.
  final String extension;

  Map<String, Object> toJson() => {
    'sha256': sha256,
    'size': size,
    'key': key,
    'nonce': nonce,
    'urls': urls,
    'ext': extension,
  };

  String encode() => jsonEncode(toJson());

  /// Throws [FormatException] on missing fields.
  factory BlobRef.fromJson(Object? json) {
    if (json is! Map ||
        json['sha256'] is! String ||
        json['size'] is! int ||
        json['key'] is! String ||
        json['nonce'] is! String ||
        json['urls'] is! List) {
      throw const FormatException('Invalid blob reference');
    }
    return BlobRef(
      sha256: json['sha256'] as String,
      size: json['size'] as int,
      key: json['key'] as String,
      nonce: json['nonce'] as String,
      urls: [
        for (final u in json['urls'] as List)
          if (u is String) u,
      ],
      extension: json['ext'] is String ? json['ext'] as String : '',
    );
  }

  static BlobRef? tryDecode(String? text) {
    if (text == null) return null;
    try {
      return BlobRef.fromJson(jsonDecode(text));
    } catch (_) {
      return null;
    }
  }
}
