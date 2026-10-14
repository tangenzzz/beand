import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../database/database.dart';
import '../../models/brew_recipe.dart';
import '../../models/machine_profile.dart' show profilePlaceholderColor;
import '../../services/brew_recipe_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../history/history_logic.dart';
import '../live/pourover/recipe_format.dart';

// View into a Pour Over profile (tapping a card below the brew cards) —
// laid out like the machines' profile view (ProfileDetailScreen): one large
// card with header (color or custom photo), key facts, description,
// breakdown of the pours and "About". At the very bottom "Delete profile"
// like on the Meticulous: removes it from your own selection.
class PourOverProfileDetailScreen extends StatefulWidget {
  const PourOverProfileDetailScreen({
    super.key,
    required this.recipe,
    this.pickPhoto,
  });

  final BrewRecipe recipe;

  // Returns the path of the chosen photo ('camera' | 'gallery'), already in
  // the photo folder; null = cancelled. Replaceable only for tests.
  final Future<String?> Function(String source)? pickPhoto;

  @override
  State<PourOverProfileDetailScreen> createState() =>
      _PourOverProfileDetailScreenState();
}

class _PourOverProfileDetailScreenState
    extends State<PourOverProfileDetailScreen> {
  late final Future<ProfileUsage> _usage = context
      .read<AppDatabase>()
      .profileUsage(widget.recipe.name, machine: 'pourover');

  static Future<String?> _pickAndStore(String source) async {
    final picked = await ImagePicker().pickImage(
      source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return null;
    // The picker returns a cache file that Android may delete at any time —
    // so copy it into the app folder (the same as for machine profiles,
    // included in the backup).
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, BrewRecipeStore.photoFolder))
      ..createSync(recursive: true);
    final target = p.join(
      dir.path,
      'pourover_${DateTime.now().microsecondsSinceEpoch}${p.extension(picked.path)}',
    );
    await File(picked.path).copy(target);
    return target;
  }

  // As with machine profiles: camera / gallery / remove photo.
  Future<void> _photoActions() async {
    final store = context.read<BrewRecipeStore>();
    final hasPhoto = store.photoFor(widget.recipe.id) != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.tile),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                Icons.photo_camera_outlined,
                color: context.colors.textSecondary,
              ),
              title: Text(
                'Take photo',
                style: TextStyle(color: context.colors.textPrimary),
              ),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: context.colors.textSecondary,
              ),
              title: Text(
                'Choose from gallery',
                style: TextStyle(color: context.colors.textPrimary),
              ),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(
                  Icons.hide_image_outlined,
                  color: context.colors.textSecondary,
                ),
                title: Text(
                  'Remove photo',
                  style: TextStyle(color: context.colors.textPrimary),
                ),
                onTap: () => Navigator.pop(context, 'reset'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'reset') {
      store.setPhoto(widget.recipe.id, null);
      return;
    }
    try {
      final path = await (widget.pickPhoto ?? _pickAndStore)(action);
      if (path == null || !mounted) return;
      store.setPhoto(widget.recipe.id, path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load photo'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _deleteProfile() async {
    final name = widget.recipe.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.card,
        title: Text(
          'Delete profile?',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          '"$name" is removed from your profiles. You can add it again with + '
          'or in Settings. Brews you already made with it stay in your history.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.colors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    context.read<BrewRecipeStore>().remove(widget.recipe.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    final photo = context.watch<BrewRecipeStore>().photoFor(r.id);
    final steps = r.steps;
    final water = steps.isEmpty ? r.waterMl : steps.last.targetTotalG;
    return Scaffold(
      appBar: AppBar(titleSpacing: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.tileOuterMargin,
          0,
          AppSpacing.tileOuterMargin,
          AppSpacing.tileOuterMargin * 3,
        ),
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.colors.card,
              borderRadius: BorderRadius.circular(AppRadii.tile),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(recipe: r, photo: photo, onEditImage: _photoActions),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      _Fact('Dose', formatGrams(r.doseG), 'g'),
                      _Fact('Water', formatGrams(water), 'g'),
                      _Fact('Ratio', '1:${formatRatio(r.ratioValue)}', ''),
                      _Fact(
                        'Temp',
                        r.waterTempC != null ? formatGrams(r.waterTempC!) : '–',
                        r.waterTempC != null ? '°C' : '',
                      ),
                    ],
                  ),
                ),
                if (r.description != null && r.description!.trim().isNotEmpty)
                  _Section(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionLabel('Description'),
                        const SizedBox(height: 6),
                        _ExpandableText(r.description!.trim()),
                      ],
                    ),
                  ),
                if (steps.isNotEmpty) _PoursSection(steps: steps),
                _BrewSection(recipe: r),
                _AboutSection(recipe: r, usage: _usage),
              ],
            ),
          ),
          // Delete at the very end, like on the Meticulous.
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 20, 10, 4),
            child: AppButton(
              label: 'Delete profile',
              icon: Icons.delete_outline,
              variant: AppButtonVariant.destructive,
              expand: true,
              onPressed: _deleteProfile,
            ),
          ),
        ],
      ),
    );
  }
}

// A section of the large card: thin divider on top, padding.
class _Section extends StatelessWidget {
  const _Section({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: context.colors.divider),
        Padding(padding: const EdgeInsets.all(14), child: child),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      color: context.colors.textTertiary,
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.9,
    ),
  );
}

// Header like on the machines: the profile's placeholder color or a custom
// photo, gradient downwards, with name and brewer on top; bottom right the
// button to change the photo.
class _Header extends StatelessWidget {
  const _Header({
    required this.recipe,
    required this.photo,
    required this.onEditImage,
  });

  final BrewRecipe recipe;
  final File? photo;
  final VoidCallback onEditImage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sub = [
      brewerLabel(recipe.brewer),
      if (recipe.variant != null && recipe.variant!.isNotEmpty) recipe.variant!,
    ].join(' · ');
    return SizedBox(
      height: 200,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: profilePlaceholderColor(recipe.id)),
          if (photo != null)
            Image.file(
              photo!,
              fit: BoxFit.cover,
              cacheWidth: 1000,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          // Gradient downwards so the name is readable on any image.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.35, 1],
                colors: [Color(0x00000000), Color(0xCC000000)],
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: Colors.black38,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Change photo',
                icon: const Icon(
                  Icons.add_a_photo_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: onEditImage,
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 62,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  recipe.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sub,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, this.unit);

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final long = widget.text.length > 220;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _open || !long ? null : 4,
          overflow: _open || !long ? null : TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
        if (long)
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _open ? 'Show less' : 'Show more',
                style: TextStyle(color: context.colors.accent, fontSize: 12.5),
              ),
            ),
          ),
      ],
    );
  }
}

// Breakdown of the pours — like the machines' stage cards: number, name,
// amount on the right; below that target on the scale, pause and hint.
// On top a bar with each pour's share of the water.
class _PoursSection extends StatelessWidget {
  const _PoursSection({required this.steps});

  final List<BrewStep> steps;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = steps.last.targetTotalG;
    return _Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.water_drop_outlined, color: colors.accent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Pour breakdown',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                steps.length == 1 ? '1 pour' : '${steps.length} pours',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      Expanded(
                        flex: (steps[i].waterG * 10).round().clamp(1, 1 << 20),
                        child: Container(
                          margin: EdgeInsets.only(
                            right: i < steps.length - 1 ? 2 : 0,
                          ),
                          color: colors.accent.withValues(
                            alpha: i.isEven ? 0.85 : 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++)
            _PourCard(number: i + 1, step: steps[i]),
        ],
      ),
    );
  }
}

class _PourCard extends StatelessWidget {
  const _PourCard({required this.number, required this.step});

  final int number;
  final BrewStep step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = colors.accent;
    final wait = step.waitSeconds;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            '$number',
                            style: TextStyle(
                              color: color,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              step.label,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '+${formatGrams(step.waterG)}',
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(
                                  text: ' g',
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Chip(
                          icon: Icons.scale_outlined,
                          text: 'to ${formatGrams(step.targetTotalG)} g',
                        ),
                        if (wait != null && wait > 0)
                          _Chip(
                            icon: Icons.hourglass_empty,
                            text: 'wait ${formatClock(wait)}',
                          ),
                      ],
                    ),
                    if (step.note != null && step.note!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        step.note!.trim(),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: colors.textSecondary, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

Widget _row(BuildContext context, String label, Widget value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 7),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 96,
        child: Text(
          label,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
        ),
      ),
      Expanded(child: value),
    ],
  ),
);

Widget _text(String s) => Text(s, style: const TextStyle(fontSize: 13.5));

// Brew settings from the recipe: brewer, filter, grind size, temperature.
class _BrewSection extends StatelessWidget {
  const _BrewSection({required this.recipe});

  final BrewRecipe recipe;

  @override
  Widget build(BuildContext context) {
    final r = recipe;
    return _Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Brew'),
          const SizedBox(height: 4),
          _row(context, 'Brewer', _text(brewerLabel(r.brewer))),
          if (r.paperFilter != null && r.paperFilter!.isNotEmpty)
            _row(context, 'Filter', _text(r.paperFilter!)),
          if (r.grindSize.isNotEmpty)
            _row(context, 'Grind', _text(grindLabel(r.grindSize))),
          if (r.brewTemperature != null)
            _row(
              context,
              'Temperature',
              _text(brewTemperatureLabel(r.brewTemperature!)),
            ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.recipe, required this.usage});

  final BrewRecipe recipe;
  final Future<ProfileUsage> usage;

  @override
  Widget build(BuildContext context) {
    final r = recipe;
    final url = r.sourceUrl;
    return _Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('About'),
          const SizedBox(height: 4),
          if (r.sourceName.isNotEmpty)
            _row(
              context,
              'Source',
              url == null
                  ? _text(r.sourceName)
                  : GestureDetector(
                      onTap: () => launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(
                        r.sourceName,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: context.colors.accent,
                          decoration: TextDecoration.underline,
                          decorationColor: context.colors.accent,
                        ),
                      ),
                    ),
            ),
          if (r.competition != null && r.competition!.isNotEmpty)
            _row(context, 'Competition', _text(r.competition!)),
          if (r.tags.isNotEmpty)
            _row(context, 'Tags', _text(r.tags.join(', '))),
          FutureBuilder<ProfileUsage>(
            future: usage,
            builder: (context, snapshot) {
              final u = snapshot.data;
              if (u == null) return const SizedBox.shrink();
              final parts = [
                u.count == 1 ? '1 brew' : '${u.count} brews',
                if (u.averageRating != null)
                  'Ø ${u.averageRating!.toStringAsFixed(1)} ★',
                if (u.lastUsed != null) 'last ${dateLabel(u.lastUsed!)}',
              ];
              return _row(
                context,
                'Your brews',
                _text(u.count == 0 ? 'Not used yet' : parts.join(' · ')),
              );
            },
          ),
          _row(
            context,
            'License',
            Text(
              'brew-recipes (CC0)',
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
