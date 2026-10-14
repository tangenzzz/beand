import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../database/database.dart';
import '../../models/shot_phases.dart';
import '../../models/taste_profile.dart';
import '../../services/brew_recipe_store.dart';
import '../../services/profile_images.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/taste_chips.dart';
import 'history_logic.dart';
import 'history_widgets.dart' show parseHexColor;
import 'shot_chart.dart';

// Share a shot as an image: preview, a toggle for the note, then a
// 1080 × 1920 PNG via the phone's share function.

/// Logical size of the image; times [_pixelRatio] gives 1080 × 1920 (9:16).
const _cardSize = Size(360, 640);
const _pixelRatio = 3.0;

class ShotShareScreen extends StatefulWidget {
  const ShotShareScreen({
    super.key,
    required this.entry,
    required this.readings,
  });

  final ShotEntry entry;

  /// Prepared as in the shot detail (for Pour Over the scale flow as
  /// `flow`).
  final List<ShotReading> readings;

  @override
  State<ShotShareScreen> createState() => _ShotShareScreenState();
}

class _ShotShareScreenState extends State<ShotShareScreen> {
  final _boundary = GlobalKey();
  // Notes are private: only in the image on request.
  bool _includeNotes = false;
  bool _photoReady = false;
  bool _busy = false;
  late final File? _photo = _photoFile(widget.entry);
  File? _profilePhoto;

  static File? _photoFile(ShotEntry e) {
    for (final path in [e.shot.shotPhotoPath, e.bean?.photoPath]) {
      if (path != null && File(path).existsSync()) return File(path);
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The photo must be fully decoded before the image is captured —
    // otherwise it is missing from the PNG.
    if (_photoReady) return;
    // Profile photo as in the history list: the copy on the shot, otherwise
    // the current profile image; for Pour Over the recipe's own photo.
    final s = widget.entry.shot;
    if (s.machine == 'pourover') {
      _profilePhoto = context.read<BrewRecipeStore?>()?.photoForName(
        s.profileName,
      );
    } else {
      final profilePath =
          s.profileImagePath ??
          context.read<ProfileImages?>()?.pathFor(
            machine: s.machine,
            profileName: s.profileName,
          );
      if (profilePath != null && File(profilePath).existsSync()) {
        _profilePhoto = File(profilePath);
      }
    }
    final files = [?_photo, ?_profilePhoto];
    if (files.isEmpty) {
      _photoReady = true;
      return;
    }
    Future.wait([for (final f in files) precacheImage(FileImage(f), context)])
        .whenComplete(() {
          if (mounted) setState(() => _photoReady = true);
        });
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary =
          _boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final t = widget.entry.shot.timestamp;
      final file = File(
        p.join(
          dir.path,
          'beand-shot-${t.year}${two(t.month)}${two(t.day)}-'
          '${two(t.hour)}${two(t.minute)}.png',
        ),
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasNotes = (widget.entry.shot.notes ?? '').trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text(
          'Share image',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Center(
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _boundary,
                      child: ShotShareCard(
                        entry: widget.entry,
                        readings: widget.readings,
                        photo: _photoReady ? _photo : null,
                        profilePhoto: _photoReady ? _profilePhoto : null,
                        includeNotes: _includeNotes,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (hasNotes)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.dividerInset,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Include notes',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ),
                    Switch(
                      value: _includeNotes,
                      onChanged: (on) => setState(() => _includeNotes = on),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: AppButton(
                label: 'Share',
                icon: Icons.share_outlined,
                onPressed: _photoReady && !_busy ? _share : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The image itself, always in the app's dark appearance with the brand
/// turquoise — regardless of which theme is currently set.
class ShotShareCard extends StatelessWidget {
  const ShotShareCard({
    super.key,
    required this.entry,
    required this.readings,
    required this.photo,
    this.profilePhoto,
    required this.includeNotes,
  });

  final ShotEntry entry;
  final List<ShotReading> readings;
  final File? photo;
  final File? profilePhoto;
  final bool includeNotes;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: buildAppTheme(),
      // Fixed text scale: the image should look the same for everyone, even
      // if a larger font is set on the phone.
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: Builder(builder: _card),
      ),
    );
  }

  Widget _card(BuildContext context) {
    final colors = context.colors;
    final s = entry.shot;
    final bean = entry.bean;
    final notes = includeNotes ? (s.notes ?? '').trim() : '';
    final rated = (s.rating ?? 0) > 0;
    final tasted = s.tasteValues.values.any((v) => v > 0);
    return SizedBox.fromSize(
      size: _cardSize,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.bg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(photo: photo),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
              child: _Title(
                title: bean?.name ?? s.profileName ?? _kindLabel(s),
                date: _dateLabel(s.timestamp),
                subtitle: [
                  bean?.roaster,
                  bean?.country,
                  bean?.processing,
                ].whereType<String>().where((t) => t.isNotEmpty).join(' · '),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: _Numbers(shot: s),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 0),
                child: _Chart(shot: s, readings: readings),
              ),
            ),
            if (rated || tasted || notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: _Rating(
                  rating: rated ? s.rating! : null,
                  taste: tasted ? s.tasteValues : null,
                  notes: notes,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: _Profile(shot: s, photo: profilePhoto),
            ),
          ],
        ),
      ),
    );
  }
}

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

// Always with year in the image — it will be looked at later too.
String _dateLabel(DateTime t) =>
    '${t.day} ${_months[t.month - 1]} ${t.year} · ${timeLabel(t)}';

// Fallback for shots without a known machine.
String _kindLabel(Shot s) => s.machine == 'pourover' ? 'Pour over' : 'Espresso';

// Brew method: machine or pour over.
String? _machineLabel(Shot s) => switch (s.machine) {
  'meticulous' => 'Meticulous',
  'gaggimate' => 'GaggiMate',
  'pourover' => 'Pour over',
  _ => null,
};

TextStyle _caption(BuildContext context) => TextStyle(
  color: context.colors.textSecondary,
  fontSize: 9.5,
  letterSpacing: 0.8,
);

class _Header extends StatelessWidget {
  const _Header({required this.photo});

  final File? photo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final photo = this.photo;
    return SizedBox(
      // Without a photo only a narrow strip for the logo; the chart gets the
      // space.
      height: photo == null ? 56 : 168,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null)
            Image.file(photo, fit: BoxFit.cover)
          else
            ColoredBox(color: colors.card),
          // Fades into the background at the bottom, so the title below does
          // not stick to an edge.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.45, 1],
                colors: [colors.bg.withValues(alpha: 0), colors.bg],
              ),
            ),
          ),
          // Logo top right. On the photo, instead of a pill, a soft dark
          // gradient from the top sits underneath so it stays readable on
          // light images too.
          if (photo != null)
            const Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 64,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x8C000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 16,
            right: 18,
            child: Image.asset('assets/branding/wordmark.png', height: 15),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({
    required this.title,
    required this.date,
    required this.subtitle,
  });

  final String title;
  final String date;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date to the right of the name.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                date,
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
            ),
          ],
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textSecondary, fontSize: 12.5),
          ),
        ],
      ],
    );
  }
}

// Two rows of three values in the order of the shot detail: time ·
// yield · temp, below that dose · ratio · grind.
// Each number centered above its own label; yield in the color of the
// weight curve. Missing values as a dash so the columns stay aligned.
class _Numbers extends StatelessWidget {
  const _Numbers({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final s = shot;
    final rows = [
      [
        ('Time', s.durationMs == null ? null : seconds(s.durationMs!), 's'),
        ('Yield', s.finalWeight == null ? null : grams(s.finalWeight!), 'g'),
        ('Temp', s.profileTemp == null ? null : grams(s.profileTemp!), '°C'),
      ],
      [
        ('Dose', s.doseGrams == null ? null : grams(s.doseGrams!), 'g'),
        ('Ratio', ratioLabel(s)?.replaceAll(' ', ''), ''),
        ('Grind', (s.grindSize ?? '').isEmpty ? null : s.grindSize, ''),
      ],
    ];
    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 10),
          Row(
            children: [
              for (final (label, value, unit) in rows[r])
                Expanded(
                  child: Column(
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: value ?? '–',
                              style: TextStyle(
                                color: label == 'Yield' && value != null
                                    ? colors.sensorMid
                                    : (value == null
                                          ? colors.textTertiary
                                          : colors.textPrimary),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            if (value != null && unit.isNotEmpty)
                              TextSpan(
                                text: ' $unit',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(label.toUpperCase(), style: _caption(context)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.shot, required this.readings});

  final Shot shot;
  final List<ShotReading> readings;

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    bool has(double? Function(ShotReading) f) =>
        readings.any((r) => (f(r) ?? 0) > 0);
    final showTemp = shot.machine == 'gaggimate' && has((r) => r.barUp);
    final keys = [
      if (has((r) => r.pressure)) ('Pressure bar', colors.success),
      if (has((r) => r.flow)) ('Flow ml/s', colors.sensorDown),
      if (has((r) => r.weight)) ('Weight g', colors.sensorMid),
      if (showTemp) ('Temp °C', colors.danger),
    ];
    const legendHeight = 18.0;
    return LayoutBuilder(
      builder: (context, c) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: legendHeight,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    for (final (label, color) in keys) ...[
                      Container(
                        width: 9,
                        height: 2,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 9.5,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
            ),
          ),
          ShotChart(
            readings: readings,
            // Stages only as subtle bands in the chart, true to time and as
            // faint as in the shot detail; no names.
            phases: computePhases(readings),
            showStageBar: false,
            cursorMs: 0,
            onCursorChanged: (_) {},
            showCursor: false,
            fineGrid: true,
            showMaxXLabel: false,
            showTemperature: showTemp,
            temperatureTarget: shot.profileTemp,
            height: math.max(60, c.maxHeight - legendHeight),
          ),
        ],
      ),
    );
  }
}

class _Rating extends StatelessWidget {
  const _Rating({
    required this.rating,
    required this.taste,
    required this.notes,
  });

  final int? rating;
  final TasteValues? taste;
  final String notes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rating = this.rating;
    final taste = this.taste;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rating != null)
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '★' * rating,
                  style: TextStyle(color: colors.star),
                ),
                TextSpan(
                  text: '★' * (5 - rating),
                  style: TextStyle(color: colors.textTertiary),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 17, letterSpacing: 2),
          ),
        if (taste != null) ...[
          const SizedBox(height: 7),
          TasteChips(
            values: taste,
            shortLabels: true,
            onlyRated: true,
            dense: true,
          ),
        ],
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            '„$notes"',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontStyle: FontStyle.italic,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

// Profile with photo and brew method; temperature and grind size are shown
// at the top with the values.
class _Profile extends StatelessWidget {
  const _Profile({required this.shot, required this.photo});

  final Shot shot;
  final File? photo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final s = shot;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brew method on the right, opposite the profile name.
            Row(
              children: [
                if ((s.profileName ?? '').isNotEmpty) ...[
                  _ProfileDot(shot: s, photo: photo),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    s.profileName ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _machineLabel(s) ?? _kindLabel(s),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Small circle with the profile photo left of the profile name; without a
// photo the initial letter on the profile color as in the history list.
class _ProfileDot extends StatelessWidget {
  const _ProfileDot({required this.shot, required this.photo});

  final Shot shot;
  final File? photo;

  static const _size = 20.0;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    final letter = (shot.profileName ?? '').trim();
    return ClipOval(
      child: Container(
        width: _size,
        height: _size,
        alignment: Alignment.center,
        color: parseHexColor(
          shot.profileColor,
          fallback: context.colors.divider,
        ),
        child: photo != null
            ? Image.file(photo, width: _size, height: _size, fit: BoxFit.cover)
            : Text(
                letter.isEmpty ? '?' : letter.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  fontSize: _size * 0.45,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.32),
                ),
              ),
      ),
    );
  }
}
