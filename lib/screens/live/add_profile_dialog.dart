import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../machines/espresso_machine.dart';
import '../../services/profile_store.dart';
import '../../theme/app_theme.dart';
import '../profile/editor/profile_editor_screen.dart';

// Which sites offer ready-made profiles is known by each machine itself
// (EspressoMachine.profileSites) — for the Meticulous metprofiles.link and
// the community forum, for the GaggiMate mybrewfolio.com. They open in the
// device's default browser; the downloaded file then comes in via
// "Upload .json file".

// Machine and profile store are taken from the context here and passed to
// the dialog: a dialog lives in its OWN route and therefore does not see
// the home screen's providers — the same trap as with ProfileDetailScreen.
Future<void> showAddProfileDialog(
  BuildContext context, {
  Future<String?> Function()? pickJsonFile,
  Future<bool> Function(Uri url)? openUrl,
}) => showDialog<void>(
  context: context,
  builder: (_) => AddProfileDialog(
    machine: context.read<EspressoMachine>(),
    store: context.read<ProfileStore>(),
    pickJsonFile: pickJsonFile,
    openUrl: openUrl,
  ),
);

// "Add profile": build one (ProfileEditorScreen), upload a profile JSON from
// the device, or open one of the two profile sites in the browser.
class AddProfileDialog extends StatefulWidget {
  const AddProfileDialog({
    super.key,
    required this.machine,
    required this.store,
    this.pickJsonFile,
    this.openUrl,
  });

  // Where the profile goes and whose copy is refreshed afterwards.
  final EspressoMachine machine;
  final ProfileStore store;
  // Both replaceable only for tests; normally file picker and browser come
  // from the device.
  final Future<String?> Function()? pickJsonFile;
  final Future<bool> Function(Uri url)? openUrl;

  @override
  State<AddProfileDialog> createState() => _AddProfileDialogState();
}

class _AddProfileDialogState extends State<AddProfileDialog> {
  bool _busy = false;

  Future<String?> _pick() async {
    final custom = widget.pickJsonFile;
    if (custom != null) return custom();
    // FileType.any instead of an extension list: otherwise Android filters
    // out .json files entirely, depending on the file manager. We do the
    // check ourselves.
    final file = await FilePicker.pickFile(dialogTitle: 'Pick a profile .json');
    return file?.path;
  }

  Future<bool> _open(Uri url) async {
    final custom = widget.openUrl;
    if (custom != null) return custom(url);
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // The editor assembles and sends the profile itself; here only the dialog
  // is closed so it does not get in the editor's way.
  Future<void> _createProfile() async {
    final navigator = Navigator.of(context);
    navigator.pop();
    await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ProfileEditorScreen(machine: widget.machine, store: widget.store),
      ),
    );
  }

  Future<void> _uploadJson() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await _pick();
      if (path == null) return; // cancelled
      if (!path.toLowerCase().endsWith('.json')) {
        _say('That is not a .json file');
        return;
      }
      final Map<String, dynamic> profile;
      try {
        final decoded = jsonDecode(await File(path).readAsString());
        if (decoded is! Map) {
          _say('This file does not contain a profile');
          return;
        }
        profile = Map<String, dynamic>.from(decoded);
      } catch (e) {
        _say('Could not read the file: $e');
        return;
      }
      if (!mounted) return;
      final result = await widget.machine.uploadProfile(profile);
      if (!result.isOk) {
        _say('Upload failed — ${result.error}');
        return;
      }
      // Refresh the local copy right away so the profile shows up in the
      // row below.
      if (mounted) await widget.store.sync();
      // The machines name the name field differently ("name" on the
      // Meticulous, "label" on the GaggiMate).
      final name = (profile['name'] ?? profile['label'] ?? '').toString();
      _say(name.isEmpty ? 'Profile uploaded' : 'Uploaded "$name"');
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSite(String url) async {
    final ok = await _open(Uri.parse(url));
    if (!ok) {
      _say('Could not open $url');
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.card,
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
                  color: context.colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            // The editor produces the Meticulous format; the GaggiMate has
            // its own and therefore sees the entry dimmed.
            _Option(
              icon: Icons.add_circle_outline,
              title: 'Create new profile',
              subtitle: widget.machine.canEditProfiles
                  ? 'Build stages and curves yourself'
                  : 'Not available for ${widget.machine.displayName} yet',
              onTap: widget.machine.canEditProfiles && !_busy
                  ? _createProfile
                  : null,
            ),
            _Option(
              icon: Icons.upload_file_outlined,
              title: 'Upload .json file',
              subtitle: 'Pick a profile from this device',
              busy: _busy,
              onTap: _uploadJson,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                'Download profile from',
                style: TextStyle(
                  color: context.colors.textTertiary,
                  fontSize: 11.5,
                ),
              ),
            ),
            for (final site in widget.machine.profileSites)
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
                    style: TextStyle(color: context.colors.textSecondary),
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

// One row of the dialog: icon, title, optionally an explanation below.
// Without onTap it is dimmed (not built yet).
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
    final enabled = onTap != null && !busy;
    final color = enabled
        ? context.colors.textPrimary
        : context.colors.textTertiary;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.accent,
                      ),
                    )
                  : Icon(
                      icon,
                      size: 20,
                      color: enabled
                          ? context.colors.accent
                          : context.colors.textTertiary,
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: context.colors.textTertiary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
