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

/// How far [pageThroughEvents] raises the limit, as a multiple of the page
/// size, for a second that has more events than fit on a page.
const _maxLimitGrowth = 4;

/// Calls [query] until the relay has nothing new, passing each page to
/// [onPage]. True if the relay was read to the end; false if it was stopped
/// by [cancelled] or ran into [maxPages] or [maxEvents].
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
  for (var pages = 0; pages < maxPages; pages++) {
    if (cancelled?.call() ?? false) return false;
    final page = await query(until, limit);
    if (page.isEmpty) return true;
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

    if (fresh > 0) {
      until = oldest;
      limit = pageSize;
      continue;
    }

    // Nothing new. Normally that is the end, unless one second has more
    // events than the page holds: `until` cannot get inside a second, so ask
    // for more at once and, failing that, give up on the rest of the second.
    final fullSecond =
        oldest == newest && ids.length == page.length && page.length >= limit;
    if (!fullSecond) return true;
    if (limit < pageSize * _maxLimitGrowth) {
      limit *= 2;
    } else {
      if (oldest <= 0) return true;
      until = oldest - 1;
      limit = pageSize;
    }
  }
  return false;
}
