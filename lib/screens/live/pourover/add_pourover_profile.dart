import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pourover_profile_editor.dart';
import '../../../models/brew_recipe.dart';
import '../../../services/brew_recipe_store.dart';
import '../../../services/meticulous_pourover_profiles.dart';
import '../../../services/pourover_brew_service.dart';
import '../../../theme/app_theme.dart';
import '../../settings/pourover_profiles_screen.dart';

// "+" on the Pour Over profile rows (user 2026-11-04): everyone gathers
// their own profiles — a .json file from the device (the Meticulous' Pour
// Over format or a brew-recipes recipe), the brew-recipes collection, or
// the two sites to download from. In Machine mode a Meticulous file goes
// onto the machine (its dial brews from its own list).

const pourOverProfileSites = [
  (
    label: 'community.meticuloushome.com',
    url: 'https://community.meticuloushome.com/brew-profiles',
  ),
  (
    label: 'github.com/HotThoughts/brew-recipes',
    url: 'https://github.com/HotThoughts/brew-recipes',
  ),
];

Future<void> showAddPourOverProfile(
  BuildContext context, {
  Future<String?> Function()? pickJsonFile,
  Future<bool> Function(Uri url)? openUrl,
}) => showDialog<void>(
  context: context,
  builder: (_) => AddPourOverProfileDialog(
    store: context.read<BrewRecipeStore>(),
    brew: context.read<PourOverBrewService>(),
    pickJsonFile: pickJsonFile,
    openUrl: openUrl,
    openRecipes: () => _openRecipes(context),
  ),
);

// The collection opens right here (not in the settings tab), and going
// back leads to the "+" dialog again (user 2026-11-04).
Future<void> _openRecipes(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const PourOverProfilesScreen()),
  );
  if (context.mounted) await showAddPourOverProfile(context);
}

class AddPourOverProfileDialog extends StatefulWidget {
  const AddPourOverProfileDialog({
    super.key,
    required this.store,
    required this.brew,
    required this.openRecipes,
    this.pickJsonFile,
    this.openUrl,
  });

  final BrewRecipeStore store;
  final PourOverBrewService brew;
  final Future<void> Function() openRecipes;
  // Replaceable for tests; normally file picker and browser of the device.
  final Future<String?> Function()? pickJsonFile;
  final Future<bool> Function(Uri url)? openUrl;

  @override
  State<AddPourOverProfileDialog> createState() =>
      _AddPourOverProfileDialogState();
}

class _AddPourOverProfileDialogState extends State<AddPourOverProfileDialog> {
  bool _busy = false;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<String?> _pick() async {
    final custom = widget.pickJsonFile;
    if (custom != null) return custom();
    // FileType.any: an extension filter hides .json files on some Android
    // file managers; the check is ours.
    final file = await FilePicker.pickFile(dialogTitle: 'Pick a profile .json');
    return file?.path;
  }

  Future<void> _uploadJson() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await _pick();
      if (path == null) return;
      if (!path.toLowerCase().endsWith('.json')) {
        _say('That is not a .json file');
        return;
      }
      final Map<String, dynamic> json;
      try {
        final decoded = jsonDecode(await File(path).readAsString());
        if (decoded is! Map) {
          _say('This file does not contain a profile');
          return;
        }
        json = Map<String, dynamic>.from(decoded);
      } catch (e) {
        _say('Could not read the file');
        return;
      }
      final BrewRecipe recipe;
      try {
        recipe = parsePourOverProfile(json);
      } on BrewRecipeFormatException catch (e) {
        _say('Not a pour over profile: ${e.message}');
        return;
      }
      final source = widget.store.machineSource;
      if (widget.brew.dialLeads &&
          json['brew_type'] == 'pour_over' &&
          source != null) {
        // Machine mode: onto the machine, its dial brews from its list.
        try {
          await source.upload(json);
          await widget.store.refreshMachine();
          _say('"${recipe.name}" is on the Meticulous');
        } catch (e) {
          _say('Upload to the Meticulous failed — $e');
          return;
        }
      } else {
        widget.store.importProfile(json);
        _say('Added "${recipe.name}"');
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSite(String url) async {
    final custom = widget.openUrl;
    final uri = Uri.parse(url);
    final ok = custom != null
        ? await custom(uri)
        : await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      _say('Could not open $url');
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final machine = widget.brew.dialLeads;
    return Dialog(
      backgroundColor: colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Add profile',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _Option(
              icon: Icons.add,
              // Same words as on the Meticulous pill.
              title: 'Create new profile',
              subtitle: 'Write your own recipe',
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                unawaited(
                  navigator.push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => const PourOverProfileEditor(),
                    ),
                  ),
                );
              },
            ),
            _Option(
              icon: Icons.upload_file_outlined,
              title: 'Upload .json file',
              // Same words as on the Meticulous pill.
              subtitle: 'Pick a profile from this device',
              busy: _busy,
              onTap: _uploadJson,
            ),
            if (!machine)
              _Option(
                icon: Icons.menu_book_outlined,
                title: 'Brew-recipes',
                subtitle: 'Pick from the collection',
                onTap: () {
                  Navigator.of(context).pop();
                  widget.openRecipes();
                },
              ),
            if (widget.store.machineSource != null)
              _Option(
                icon: Icons.refresh,
                title: 'Reload from the Meticulous',
                subtitle: 'Its pour over profiles',
                onTap: () {
                  Navigator.of(context).pop();
                  widget.store.refreshMachine();
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                'Download profile from',
                style: TextStyle(color: colors.textTertiary, fontSize: 11.5),
              ),
            ),
            for (final site in pourOverProfileSites)
              _Option(
                icon: Icons.open_in_new,
                title: site.label,
                onTap: () => _openSite(site.url),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 4),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      leading: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, color: colors.textSecondary),
      title: Text(title, style: TextStyle(color: colors.textPrimary)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(color: colors.textTertiary, fontSize: 12),
            ),
      onTap: busy ? null : onTap,
    );
  }
}
