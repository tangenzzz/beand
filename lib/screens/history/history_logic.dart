import 'package:flutter/material.dart';

import '../../widgets/machine_badge.dart';

import '../../database/database.dart';
import '../../services/app_settings.dart';
import '../beans/bean_filter.dart';

// ---- Machines ----

enum ShotMachine {
  meticulous(
    'meticulous',
    'Meticulous',
    Color(0xFF3DDBC4),
    MachineGlyph.letterM,
  ),
  pourOver('pourover', 'Pour Over', Color(0xFFF2C94C), MachineGlyph.v60),
  gaggiMate('gaggimate', 'GaggiMate', Color(0xFFA78DE0), MachineGlyph.letterG);

  const ShotMachine(this.key, this.label, this.color, this.glyph);
  final String key;
  final String label;
  final Color color;
  final MachineGlyph glyph;

  static ShotMachine fromKey(String key) => ShotMachine.values.firstWhere(
    (m) => m.key == key,
    orElse: () => ShotMachine.meticulous,
  );
}

// Matches the same brew method in the Settings/Home pills (see
// AppSettings.enabledHomeModes).
ShotMachine shotMachineForHomeMode(HomeMode mode) => switch (mode) {
  HomeMode.meticulous => ShotMachine.meticulous,
  HomeMode.pourOver => ShotMachine.pourOver,
  HomeMode.gaggimate => ShotMachine.gaggiMate,
};

// ---- Formatting ----

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String two(int n) => n.toString().padLeft(2, '0');

String timeLabel(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

// "Mon 21 Sep" (with year if it is not the current one).
String dateLabel(DateTime t, [DateTime? now]) {
  final base = '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
  return t.year == (now ?? DateTime.now()).year ? base : '$base ${t.year}';
}

String dateTimeLabel(DateTime t, [DateTime? now]) =>
    '${dateLabel(t, now)} · ${timeLabel(t)}';

// Heading of the day group in the list: "TODAY", "YESTERDAY", otherwise
// "SAT · 19 SEP".
String dayGroupLabel(DateTime t, [DateTime? now]) {
  final today = _day(now ?? DateTime.now());
  final days = today.difference(_day(t)).inDays;
  if (days == 0) return 'TODAY';
  if (days == 1) return 'YESTERDAY';
  final year = t.year == today.year ? '' : ' ${t.year}';
  return '${_weekdays[t.weekday - 1]} · ${t.day} ${_months[t.month - 1]}$year'
      .toUpperCase();
}

// 18 -> "18", 17.5 -> "17.5", 38.43 -> "38.4".
String grams(double g) {
  final rounded = (g * 10).round() / 10;
  return rounded % 1 == 0
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

String seconds(int ms) => (ms / 1000).toStringAsFixed(1);

// Brew ratio "1 : 2.1" (output / dose).
String? ratioLabel(Shot s) {
  final dose = s.doseGrams;
  final out = s.finalWeight;
  if (dose == null || dose <= 0 || out == null) return null;
  return '1 : ${(out / dose).toStringAsFixed(1)}';
}

// ---- Grouping ----

class ShotDayGroup {
  ShotDayGroup(this.label, this.entries);
  final String label;
  final List<ShotEntry> entries;
}

// Expects newest first (like watchShotEntries) and keeps the order.
List<ShotDayGroup> groupShotsByDay(
  Iterable<ShotEntry> entries, [
  DateTime? now,
]) {
  final groups = <ShotDayGroup>[];
  DateTime? currentDay;
  for (final e in entries) {
    final day = _day(e.shot.timestamp);
    if (currentDay == null || day != currentDay) {
      groups.add(ShotDayGroup(dayGroupLabel(e.shot.timestamp, now), []));
      currentDay = day;
    }
    groups.last.entries.add(e);
  }
  return groups;
}

// ---- Search + filter ----

enum HistoryDateRange { any, today, week, month, custom }

class HistoryFilter {
  const HistoryFilter({
    this.machines = const {},
    this.beanIds = const {},
    this.roasters = const {},
    this.profiles = const {},
    this.minRating,
    this.dateRange = HistoryDateRange.any,
    this.customRange,
  });

  static const empty = HistoryFilter();

  final Set<String> machines;
  final Set<int> beanIds;
  final Set<String> roasters;
  final Set<String> profiles;
  // At least this many stars.
  final int? minRating;
  final HistoryDateRange dateRange;
  final DateTimeRange? customRange;

  int get activeCount => [
    machines.isNotEmpty,
    beanIds.isNotEmpty,
    roasters.isNotEmpty,
    profiles.isNotEmpty,
    minRating != null,
    dateRange != HistoryDateRange.any,
  ].where((a) => a).length;

  bool get isActive => activeCount > 0;
}

String? _clean(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

bool _inSet(Set<String> set, String? value) =>
    value != null && set.any((s) => s.toLowerCase() == value.toLowerCase());

bool _inDateRange(HistoryFilter f, DateTime t, DateTime now) {
  final today = _day(now);
  switch (f.dateRange) {
    case HistoryDateRange.any:
      return true;
    case HistoryDateRange.today:
      return _day(t) == today;
    case HistoryDateRange.week:
      return !_day(t).isBefore(today.subtract(const Duration(days: 6)));
    case HistoryDateRange.month:
      return !_day(t).isBefore(today.subtract(const Duration(days: 29)));
    case HistoryDateRange.custom:
      final r = f.customRange;
      if (r == null) return true;
      return !_day(t).isBefore(_day(r.start)) && !_day(t).isAfter(_day(r.end));
  }
}

// Text searched by the free-text search (lowercase).
String shotSearchText(ShotEntry e) => [
  e.bean == null ? null : beanSearchText(e.bean!),
  e.shot.profileName,
  e.shot.notes,
  ShotMachine.fromKey(e.shot.machine).label,
].whereType<String>().join(' ').toLowerCase();

// Within a field OR, between fields AND.
List<ShotEntry> filterShots(
  List<ShotEntry> entries, {
  required String query,
  required HistoryFilter filter,
  DateTime? now,
}) {
  final q = query.trim().toLowerCase();
  final at = now ?? DateTime.now();
  return [
    for (final e in entries)
      if ((q.isEmpty || shotSearchText(e).contains(q)) &&
          (filter.machines.isEmpty ||
              filter.machines.contains(e.shot.machine)) &&
          (filter.beanIds.isEmpty ||
              (e.shot.beanId != null &&
                  filter.beanIds.contains(e.shot.beanId))) &&
          (filter.roasters.isEmpty ||
              _inSet(filter.roasters, _clean(e.bean?.roaster))) &&
          (filter.profiles.isEmpty ||
              _inSet(filter.profiles, _clean(e.shot.profileName))) &&
          (filter.minRating == null ||
              (e.shot.rating ?? 0) >= filter.minRating!) &&
          _inDateRange(filter, e.shot.timestamp, at))
        e,
  ];
}

// Options for the filter sheet. Machines come from the enabled brew methods
// (Settings → Home), not just from existing shots — otherwise e.g. a newly
// enabled brew method without shots would not be offered as a filter.
// Bean/roastery/profile stay data-driven.
class HistoryFilterOptions {
  HistoryFilterOptions(
    List<ShotEntry> entries, {
    required List<ShotMachine> enabledMachines,
  }) : machines = enabledMachines,
       beans = _beans(entries),
       roasters = _distinct(entries.map((e) => _clean(e.bean?.roaster))),
       profiles = _distinct(entries.map((e) => _clean(e.shot.profileName)));

  final List<ShotMachine> machines;
  final List<Bean> beans;
  final List<String> roasters;
  final List<String> profiles;

  static List<Bean> _beans(List<ShotEntry> entries) {
    final byId = {
      for (final e in entries)
        if (e.bean != null) e.bean!.id: e.bean!,
    };
    return byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  static List<String> _distinct(Iterable<String?> values) {
    final byKey = <String, String>{};
    for (final v in values) {
      if (v != null) byKey.putIfAbsent(v.toLowerCase(), () => v);
    }
    return byKey.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
}
