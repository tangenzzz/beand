import '../nostr/event.dart';

// Fetching all events of a filter page by page from one relay. Relays are
// untrusted and differ, so a page says little on its own:
//
//  * A `limit` is an upper bound. A relay with a lower cap returns short pages
//    while more is left, so only a page without anything new means the end.
//  * `until` includes its own second. Moving it to the oldest event of a page
//    costs one repeated event, but skips none.
//  * A relay can answer forever. Progress is measured in event IDs we have not
//    seen, and there is a budget for one that invents new ones.
//  * `until` cannot get inside a second. A second with more events than a
//    page is read by raising the limit for as long as the relay fills it. A
//    relay that caps below that second's count cannot be read fully by any
//    filter; the rest is read, and the run counts as incomplete.

/// Calls [query] until the relay has nothing new, passing each page to
/// [onPage]. True if the relay was read to the end; false if it was stopped
/// by [cancelled], ran into [maxPages] or [maxEvents], or had to skip part of
/// a second.
Future<bool> pageThroughEvents({
  required Future<List<NostrEvent>> Function(int? until, int limit) query,
  required void Function(List<NostrEvent> page) onPage,
  required int pageSize,
  bool Function()? cancelled,
  int maxPages = 2000,
  int maxEvents = 100000,
}) async {
  final seen = <String>{};
  var limit = pageSize;
  int? until;
  // A second left behind because the relay would not hand over all of it.
  // Whether it held more is unknown until the relay shows it has older
  // events: then its short page was a cap, not the end.
  var skippedSecond = false;
  var incomplete = false;
  for (var pages = 0; pages < maxPages; pages++) {
    if (cancelled?.call() ?? false) return false;
    final page = await query(until, limit);
    if (page.isEmpty) return !incomplete;
    if (skippedSecond) incomplete = true;
    skippedSecond = false;
    onPage(page);

    var fresh = 0;
    final ids = <String>{};
    var oldest = page.first.createdAt;
    var newest = oldest;
    for (final event in page) {
      ids.add(event.id);
      if (seen.add(event.id)) fresh++;
      if (event.createdAt < oldest) oldest = event.createdAt;
      if (event.createdAt > newest) newest = event.createdAt;
    }
    if (seen.length > maxEvents) return false;
    // A relay that ignores `until` would be asked the same thing forever.
    final asked = until;
    if (asked != null && oldest > asked) return false;

    if (fresh > 0) {
      // Still inside the same crowded second: keep the raised limit.
      if (until != oldest) limit = pageSize;
      until = oldest;
      continue;
    }

    // Nothing new. Normally that is the end, unless one second has more
    // events than the page holds: then ask for more of it at once.
    final oneSecond = oldest == newest && ids.length == page.length;
    if (!oneSecond) return !incomplete;
    if (page.length >= limit) {
      if (limit > maxEvents) return false;
      limit *= 2;
      continue;
    }
    // The relay gave less than asked: the end, or its cap. Look past the
    // second to tell.
    if (oldest <= 0) return !incomplete;
    until = oldest - 1;
    limit = pageSize;
    skippedSecond = true;
  }
  return false;
}
