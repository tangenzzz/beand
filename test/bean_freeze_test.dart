import 'package:beand/database/database.dart';
import 'package:beand/screens/beans/bean_widgets.dart';
import 'package:beand/sync/records/bean_codec.dart';
import 'package:flutter_test/flutter_test.dart';

// Freezing pauses the freshness ring: it goes on where it stopped.
void main() {
  final roast = DateTime(2026, 10, 1);
  DateTime day(int n) => DateTime(2026, 10, 1 + n);

  Bean bean({
    DateTime? roastDate,
    bool frozen = false,
    DateTime? thawed,
    DateTime? frozenAt,
    int frozenDays = 0,
  }) => Bean(
    frozenDays: frozenDays,
    syncId: 'test',
    updatedAt: 0,
    syncState: SyncState.pending,
    deleted: false,
    id: 1,
    name: 'Guji',
    roastDate: roastDate,
    isFrozen: frozen,
    thawedDate: thawed,
    frozenDate: frozenAt,
    createdAt: roast,
  );

  // Frozen on [frozenDay], thawed on [thawDay]: the bean as saved then.
  Bean thaw(Bean b, int thawDay) => bean(
    roastDate: b.roastDate,
    thawed: day(thawDay),
    frozenAt: b.frozenDate,
    frozenDays: frozenDaysWhenThawing(b, day(thawDay)),
  );

  test('frozen on day 10: thaw day is day 11, then it counts on', () {
    final frozen = bean(roastDate: roast, frozen: true, frozenAt: day(10));
    final thawed = thaw(frozen, 40);
    expect(daysSinceFreshnessStart(thawed, day(40)), 11);
    expect(daysSinceFreshnessStart(thawed, day(41)), 12);
  });

  test('the next day or the same day nothing is lost or added', () {
    final frozen = bean(roastDate: roast, frozen: true, frozenAt: day(10));
    expect(daysSinceFreshnessStart(thaw(frozen, 11), day(11)), 11);
    expect(daysSinceFreshnessStart(thaw(frozen, 10), day(10)), 10);
  });

  test('several rounds in the freezer add up', () {
    final first = thaw(
      bean(roastDate: roast, frozen: true, frozenAt: day(10)),
      40,
    ); // day 11 on day 40
    expect(daysSinceFreshnessStart(first, day(45)), 16);
    final again = bean(
      roastDate: roast,
      frozen: true,
      frozenAt: day(45),
      thawed: first.thawedDate,
      frozenDays: frozenDaysWhenFreezing(first),
    );
    expect(daysSinceFreshnessStart(thaw(again, 60), day(60)), 17);
  });

  test('thawed before freeze dates were recorded: stays as it was', () {
    final old = bean(roastDate: roast, thawed: day(40));
    expect(daysSinceFreshnessStart(old, day(45)), 5);
    // Frozen again, it goes on from those 5 days.
    final again = bean(
      roastDate: roast,
      frozen: true,
      frozenAt: day(45),
      thawed: old.thawedDate,
      frozenDays: frozenDaysWhenFreezing(old),
    );
    expect(daysSinceFreshnessStart(thaw(again, 60), day(60)), 6);
  });

  test('frozen without a known date: thawing starts the ring as before', () {
    final legacy = bean(roastDate: roast, frozen: true);
    expect(daysSinceFreshnessStart(thaw(legacy, 40), day(40)), 0);
  });

  test('no roast date: counts from thawing', () {
    final frozen = bean(frozen: true, frozenAt: day(10));
    expect(daysSinceFreshnessStart(thaw(frozen, 40), day(42)), 2);
    expect(daysSinceFreshnessStart(bean(), day(42)), isNull);
  });

  test('sync carries the freezer days; older data leaves them alone', () {
    final b = thaw(bean(roastDate: roast, frozen: true, frozenAt: day(10)), 40);
    final data = beanToSyncData(b);
    final back = beanFromSyncData(data);
    expect(back.frozenDays.value, 29);
    expect(back.frozenDate.value, day(10));
    final old = Map<String, Object?>.of(data)
      ..remove('frozenDays')
      ..remove('frozenDate');
    expect(beanFromSyncData(old).frozenDays.present, isFalse);
    expect(beanFromSyncData(old).frozenDate.present, isFalse);
  });
}
