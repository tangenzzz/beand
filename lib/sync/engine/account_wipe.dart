import 'package:flutter/foundation.dart';

import '../blobs/blossom_client.dart';
import '../identity/identity.dart';
import '../nostr/event.dart';
import '../nostr/relay_connection.dart';
import '../nostr/relay_pool.dart';

// Delete everything of a sync key from the servers (Settings → Sync →
// Advanced, at the very bottom): whoever gives up the key no longer needs
// the data there.
//
// 1. Per relay, query all own app data events (paginated).
// 2. Deletion requests (NIP-09) with e and a tags, in batches.
// 3. "Request to Vanish" (NIP-62) afterwards — relays that support it forget
//    everything.
// 4. Delete photos on the photo servers: what the server lists for the key,
//    plus what the own database knows.
//
// Public relays don't HAVE to comply. Whatever remains is encrypted —
// without the nsec just random bytes.

class WipeReport {
  /// Found events (across all relays, without duplicates).
  int events = 0;

  /// Relays that queried everything and accepted every deletion request.
  final relaysOk = <String>{};
  final relaysFailed = <String>{};

  int photosDeleted = 0;
  final photoServersFailed = <String>{};

  @override
  String toString() =>
      'WipeReport(events $events, relaysOk ${relaysOk.length}, '
      'relaysFailed $relaysFailed, photosDeleted $photosDeleted, '
      'photoServersFailed $photoServersFailed)';
}

class AccountWipe {
  AccountWipe({
    required this.identity,
    required this.pool,
    required this.blossom,
    required this.blobServers,
    required this.knownBlobShas,
    this.pageSize = 500,
    this.chunkSize = 100,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SyncIdentity identity;
  final RelayPool pool;
  final BlossomClient blossom;
  final List<String> blobServers;
  final Set<String> knownBlobShas;
  final int pageSize;

  /// Targets per deletion request — keeps the event small enough for public
  /// relays (100 × e+a ≈ 22 KB).
  final int chunkSize;
  final DateTime Function() _now;

  int _nowSeconds() => _now().millisecondsSinceEpoch ~/ 1000;

  Future<WipeReport> run() async {
    final report = WipeReport();
    final pubkey = identity.publicKeyHex;

    // 1. Inventory per relay.
    final events = <String, NostrEvent>{};
    for (final url in pool.urls) {
      try {
        await _collect(url, events);
      } catch (e) {
        debugPrint('Wipe: list on $url failed: $e');
        report.relaysFailed.add(url);
      }
    }
    report.events = events.length;

    // 2. Deletion requests. Even without found events, one with a k tag so
    // relays that returned nothing still get it.
    final targets = events.values.toList();
    final chunks = <List<NostrEvent>>[
      for (var i = 0; i < targets.length; i += chunkSize)
        targets.sublist(i, (i + chunkSize).clamp(0, targets.length)),
    ];
    if (chunks.isEmpty) chunks.add(const []);
    for (final chunk in chunks) {
      final dTags = {for (final e in chunk) ?e.tag('d')};
      final deletion = NostrEvent.sign(
        identity: identity,
        kind: kindDeletion,
        tags: [
          for (final e in chunk) ['e', e.id],
          for (final d in dTags) ['a', '$kindAppData:$pubkey:$d'],
          ['k', '$kindAppData'],
        ],
        content: "bean'd sync data deleted",
        createdAt: _nowSeconds(),
      );
      _note(report, await pool.publish(deletion, force: true));
    }

    // 3. Request to Vanish — costs one event, many relays don't know it yet
    // (or reject the kind).
    final vanish = NostrEvent.sign(
      identity: identity,
      kind: kindVanish,
      tags: [
        ['relay', 'ALL_RELAYS'],
      ],
      content: "bean'd sync data deleted",
      createdAt: _nowSeconds(),
    );
    await pool.publish(vanish, force: true);

    // 4. Photos.
    for (final server in blobServers) {
      final listed = await blossom.list(server) ?? const <String>[];
      var ok = true;
      for (final sha in {...listed, ...knownBlobShas}) {
        if (await blossom.delete(server, sha)) {
          report.photosDeleted++;
        } else {
          ok = false;
        }
      }
      if (!ok) report.photoServersFailed.add(server);
    }
    return report;
  }

  Future<void> _collect(String url, Map<String, NostrEvent> events) async {
    int? until;
    while (true) {
      final page = await pool.queryOne(url, {
        'kinds': [kindAppData],
        'authors': [identity.publicKeyHex],
        'limit': pageSize,
        'until': ?until,
      }, force: true);
      for (final e in page) {
        if (e.pubkey == identity.publicKeyHex) {
          events.putIfAbsent(e.id, () => e);
        }
      }
      if (page.length < pageSize) return;
      final oldest = page
          .map((e) => e.createdAt)
          .reduce((a, b) => a < b ? a : b);
      until = (until != null && oldest >= until) ? until - 1 : oldest;
    }
  }

  // A relay only counts as done if it accepted ALL batches.
  void _note(WipeReport report, Map<String, PublishResult> results) {
    for (final url in pool.urls) {
      if (results[url]?.accepted ?? false) {
        if (!report.relaysFailed.contains(url)) report.relaysOk.add(url);
      } else {
        report.relaysFailed.add(url);
        report.relaysOk.remove(url);
      }
    }
  }
}
