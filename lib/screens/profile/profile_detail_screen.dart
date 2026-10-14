import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../models/machine_profile.dart';
import '../../models/profile_detail.dart';
import '../../models/profile_draft.dart';
import '../../machines/espresso_machine.dart';
import '../../machines/gaggimate/gaggimate_profile_detail.dart';
import '../../services/profile_store.dart';
import '../../theme/app_theme.dart';
import '../history/history_logic.dart';
import 'editor/profile_editor_screen.dart';
import '../../widgets/app_button.dart';

// View into a machine profile (tapping a profile card in the Home tab):
// image + description, key facts, stage breakdown modeled on the Meticulous
// web view (numbered stages, color per type, setpoint curve, exit triggers,
// limits), variables, author and own usage. Read-only — loads or heats
// nothing.
class ProfileDetailScreen extends StatefulWidget {
  const ProfileDetailScreen({
    super.key,
    required this.summary,
    required this.machine,
    required this.store,
    this.pickPhoto,
  });

  // From the card: name/image/color are available immediately, the rest
  // comes from the local copy or the machine.
  final MachineProfile summary;
  // The machine's profile store whose row the card comes from: it decides
  // which profiles are meant and how they are reloaded. The screen is opened
  // via Navigator and so lives outside the Home screen that provides the
  // machine — hence a parameter.
  final ProfileStore store;
  // The machine the profile belongs to: it provides the hostname for
  // reloaded profile images and deletes the profile on request. A parameter
  // like [store], because this screen is opened via Navigator and so lives
  // outside the Home screen that provides the machine.
  final EspressoMachine machine;
  // Returns the path of the chosen photo ('camera' | 'gallery'), already
  // copied into the app folder; null = cancelled. Replaceable only for tests.
  final Future<String?> Function(String source)? pickPhoto;

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  late final Stream<StoredProfile?> _stored;
  Future<ProfileUsage>? _usage;
  // Result of the sync with the machine: null = still running.
  bool? _refreshOk;
  bool _deleting = false;
  // The sync that runs on open. Deleting waits for it (see
  // _deleteProfile).
  Future<bool>? _refreshing;

  @override
  void initState() {
    super.initState();
    final db = context.read<AppDatabase>();
    _stored = db.watchStoredProfile(
      widget.summary.id,
      machine: widget.store.machineKey,
    );
    _usage = db.profileUsage(
      widget.summary.name,
      machine: widget.store.machineKey,
    );
    _refresh();
  }

  // Show the local copy immediately and update from the machine in the
  // background; without a connection the copy stays.
  Future<void> _refresh() async {
    setState(() => _refreshOk = null);
    final running = widget.store.refresh(widget.summary.id);
    _refreshing = running;
    final ok = await running;
    if (mounted) setState(() => _refreshOk = ok);
  }

  static Future<String?> _pickAndStore(String source) async {
    final picked = await ImagePicker().pickImage(
      source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return null;
    // The picker returns a cache file that Android may delete at any time —
    // so copy it into the app folder.
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'profile_photos'))
      ..createSync(recursive: true);
    final target = p.join(
      dir.path,
      'profile_${DateTime.now().microsecondsSinceEpoch}${p.extension(picked.path)}',
    );
    await File(picked.path).copy(target);
    return target;
  }

  // Open the saved profile in the editor. Based on the machine's RAW JSON,
  // not the prepared display — only that way do variable bindings and fields
  // we don't know (yet) survive.
  Future<void> _editProfile(StoredProfile stored) async {
    final ProfileDraft draft;
    try {
      final decoded = jsonDecode(stored.json);
      if (decoded is! Map) throw const FormatException('not an object');
      // Each machine reads its own format into the draft.
      draft = widget.machine.draftFromProfile(
        Map<String, dynamic>.from(decoded),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read this profile: $e')),
      );
      return;
    }
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileEditorScreen(
          machine: widget.machine,
          store: widget.store,
          initial: draft,
        ),
      ),
    );
    // Refresh the view after saving, otherwise the old version would still
    // be shown here.
    if (saved == true && mounted) await _refresh();
  }

  // Deletes the profile on the machine AND in the app. Order matters: the
  // machine first — the other way round, the next sync would bring the
  // profile right back.
  Future<void> _deleteProfile() async {
    final name = widget.summary.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.card,
        title: Text(
          'Delete profile?',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          '"$name" is removed from the app and from the machine. '
          'Shots you already pulled with it stay in your history.',
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

    setState(() => _deleting = true);
    // The sync on opening the screen writes the profile into the local copy.
    // If it is still running while we delete, the profile would be gone on
    // the machine and back in the app — so wait for it first.
    try {
      await _refreshing;
    } catch (_) {
      // A failed sync doesn't stop the deletion.
    }
    if (!mounted) return;
    final result = await widget.machine.deleteProfile(widget.summary.id);
    if (!mounted) return;
    if (!result.isOk) {
      // Nothing deleted: otherwise the profile would be gone in the app but
      // still on the machine — and come back on the next sync.
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete — ${result.error}'),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    await widget.store.forget(widget.summary.id);
    if (mounted) Navigator.of(context).pop();
  }

  ProfileDetail? _parse(StoredProfile stored) {
    try {
      final json = Map<String, dynamic>.from(jsonDecode(stored.json) as Map);
      return widget.store.machineKey == 'gaggimate'
          ? gaggiMateProfileDetail(json)
          : ProfileDetail.fromJson(json);
    } catch (_) {
      // A broken copy shouldn't blow up the screen — then only what the card
      // already knew is shown.
      return null;
    }
  }

  void _deleteFile(String? path) {
    if (path == null) return;
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  // Like the bean photo: camera / gallery / back to the machine's image.
  Future<void> _photoActions(StoredProfile stored) async {
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
            if (stored.customImagePath != null)
              ListTile(
                leading: Icon(Icons.undo, color: context.colors.textSecondary),
                title: Text(
                  'Use the machine image',
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
    final db = context.read<AppDatabase>();
    if (action == 'reset') {
      await db.setProfileCustomImage(
        stored.id,
        null,
        machine: widget.store.machineKey,
      );
      _deleteFile(stored.customImagePath);
      return;
    }
    try {
      final path = await (widget.pickPhoto ?? _pickAndStore)(action);
      if (path == null || !mounted) return;
      await db.setProfileCustomImage(
        stored.id,
        path,
        machine: widget.store.machineKey,
      );
      if (stored.customImagePath != path) _deleteFile(stored.customImagePath);
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

  @override
  Widget build(BuildContext context) {
    final hostname = widget.machine.host;
    return StreamBuilder<StoredProfile?>(
      stream: _stored,
      builder: (context, snapshot) {
        final stored = snapshot.data;
        // Both machines store their own profile JSON; only here is it
        // translated into the shared representation.
        final detail = stored == null ? null : _parse(stored);
        final missing =
            stored == null &&
            snapshot.connectionState != ConnectionState.waiting;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            actions: [
              // Edit sits where the trash can used to be, just moved a bit
              // away from the edge. The trash can now sits at the very
              // bottom of the page.
              if (widget.machine.canEditProfiles)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: IconButton(
                    tooltip: 'Edit profile',
                    icon: Icon(
                      Icons.edit_outlined,
                      color: context.colors.textSecondary,
                    ),
                    onPressed: stored == null
                        ? null
                        : () => _editProfile(stored),
                  ),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.tileOuterMargin,
              0,
              AppSpacing.tileOuterMargin,
              AppSpacing.tileOuterMargin * 3,
            ),
            children: [
              // One large card; only the stages keep their own small ones.
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: context.colors.card,
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      hostname: hostname,
                      name: detail?.name ?? widget.summary.name,
                      shortDescription: detail?.shortDescription,
                      localImagePath:
                          stored?.customImagePath ??
                          stored?.imagePath ??
                          widget.summary.localImagePath,
                      onEditImage: stored == null
                          ? null
                          : () => _photoActions(stored),
                      imagePath: detail?.imagePath ?? widget.summary.imagePath,
                      color: detail?.accentColor ?? widget.summary.accentColor,
                      temperature:
                          detail?.temperature ?? widget.summary.temperature,
                      finalWeight:
                          detail?.finalWeight ?? widget.summary.finalWeight,
                      stageCount: detail?.stages.length,
                    ),
                    if (detail != null) ...[
                      _DescriptionSection(
                        // Custom text takes precedence over the machine's.
                        text: stored!.customDescription ?? detail.description,
                        isCustom: stored.customDescription != null,
                        onSave: (text) => context
                            .read<AppDatabase>()
                            .setProfileCustomDescription(
                              stored.id,
                              text,
                              machine: widget.store.machineKey,
                            ),
                      ),
                      if (detail.stages.isNotEmpty)
                        _StagesSection(detail.stages),
                      if (detail.variables.isNotEmpty)
                        _VariablesSection(detail.variables),
                      _InfoSection(
                        detail: detail,
                        stored: stored,
                        usage: _usage,
                        refreshOk: _refreshOk,
                      ),
                    ] else if (missing && _refreshOk == false)
                      _Section(
                        child: Column(
                          children: [
                            Text(
                              'This profile is not saved yet and the machine is not reachable.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.colors.textSecondary,
                              ),
                            ),
                            TextButton(
                              onPressed: _refresh,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    else
                      _Section(
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.colors.textTertiary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Delete at the very end, clearly separated from the content.
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 20, 10, 4),
                child: AppButton(
                  label: 'Delete profile',
                  icon: Icons.delete_outline,
                  variant: AppButtonVariant.destructive,
                  expand: true,
                  onPressed: _deleting ? null : _deleteProfile,
                ),
              ),
            ],
          ),
        );
      },
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

// ---------------------------------------------------------------- Header

class _Header extends StatelessWidget {
  const _Header({
    required this.hostname,
    required this.name,
    required this.shortDescription,
    required this.imagePath,
    required this.localImagePath,
    required this.onEditImage,
    required this.color,
    required this.temperature,
    required this.finalWeight,
    required this.stageCount,
  });

  final String hostname;
  final String name;
  final String? shortDescription;
  final String? imagePath;
  final String? localImagePath;
  // Change photo (null = not loaded yet, no button).
  final VoidCallback? onEditImage;
  final Color color;
  final double temperature;
  final double finalWeight;
  final int? stageCount;

  @override
  Widget build(BuildContext context) {
    final local = localImagePath == null ? null : File(localImagePath!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: color),
              if (local != null && local.existsSync())
                Image.file(
                  local,
                  fit: BoxFit.cover,
                  cacheWidth: 1000,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                )
              else if (imagePath != null)
                Image.network(
                  'http://$hostname$imagePath',
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
              // In the bottom right corner; the name moves further left to
              // make room.
              if (onEditImage != null)
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
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    if (shortDescription != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        shortDescription!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _Fact('Temperature', formatNumber(temperature), '°C'),
              _Fact('Yield', formatNumber(finalWeight), 'g'),
              _Fact('Stages', stageCount?.toString() ?? '–', ''),
            ],
          ),
        ),
      ],
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
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------- Description

// Description: the machine's text or custom text (e.g. pasted from the
// community catalog). Long texts are collapsed and can be expanded.
class _DescriptionSection extends StatefulWidget {
  const _DescriptionSection({
    required this.text,
    required this.isCustom,
    required this.onSave,
  });

  final String? text;
  final bool isCustom;
  // null/empty = remove custom text (back to the machine's text).
  final Future<void> Function(String? text) onSave;

  @override
  State<_DescriptionSection> createState() => _DescriptionSectionState();
}

class _DescriptionSectionState extends State<_DescriptionSection> {
  bool _editing = false;
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEditing() {
    _controller.text = widget.text ?? '';
    setState(() => _editing = true);
  }

  Future<void> _save() async {
    await widget.onSave(_controller.text);
    if (mounted) setState(() => _editing = false);
  }

  Future<void> _useMachineText() async {
    await widget.onSave(null);
    if (mounted) setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    return _Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionLabel(
                widget.isCustom ? 'Description · edited' : 'Description',
              ),
              const Spacer(),
              // Own tooltip: since the profile editor there are two pencils
              // on the page — this one is only for the description.
              if (!_editing)
                Tooltip(
                  message: 'Edit description',
                  child: InkResponse(
                    onTap: _startEditing,
                    radius: 18,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_editing) ...[
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 4,
              maxLines: 14,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 14,
                height: 1.5,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: context.colors.card,
                hintText: 'Paste or write a description, e.g. from the community catalog',
                hintStyle: TextStyle(
                  color: context.colors.textTertiary,
                  fontSize: 13,
                ),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.isCustom)
                  TextButton(
                    onPressed: _useMachineText,
                    child: const Text('Use machine text'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _editing = false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 4),
                AppButton(
                  label: 'Save',
                  onPressed: _save,
                  expand: false,
                  height: 40,
                ),
              ],
            ),
          ] else if (text == null || text.trim().isEmpty)
            Text(
              'No description yet. Tap the pencil to add one.',
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 13.5,
              ),
            )
          else
            _ExpandableText(text),
        ],
      ),
    );
  }
}

// Text collapsed after [maxLines] lines — "Show more/less" only appears if
// it's actually longer.
class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);

  // Collapse from this many lines on.
  static const maxLines = 4;

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  static TextStyle _styleOf(BuildContext context) =>
      TextStyle(color: context.colors.textSecondary, fontSize: 14, height: 1.5);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: _styleOf(context)),
          maxLines: _ExpandableText.maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: _styleOf(context),
              maxLines: overflows && !_expanded
                  ? _ExpandableText.maxLines
                  : null,
              overflow: overflows && !_expanded
                  ? TextOverflow.ellipsis
                  : TextOverflow.visible,
            ),
            if (overflows)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Text(
                    _expanded ? 'Show less' : 'Show more',
                    style: TextStyle(
                      color: context.colors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Stages

class _StagesSection extends StatelessWidget {
  const _StagesSection(this.stages);

  final List<ProfileStage> stages;

  @override
  Widget build(BuildContext context) {
    // Legend: only types that occur in the profile (control, trigger, limits).
    final types = <String>[];
    void add(String t) {
      if (!types.contains(t)) types.add(t);
    }

    for (final s in stages) {
      add(s.type);
      for (final t in s.exitTriggers) {
        if (t.type != 'time') add(t.type);
      }
      for (final l in s.limits) {
        add(l.type);
      }
    }
    return _Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.layers_outlined,
                color: context.colors.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Stage breakdown',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                stages.length == 1 ? '1 stage' : '${stages.length} stages',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final t in types)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: colorForType(context, t),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      typeLabel(t),
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final s in stages) _StageCard(stage: s),
        ],
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  const _StageCard({required this.stage});

  final ProfileStage stage;

  @override
  Widget build(BuildContext context) {
    final color = colorForType(context, stage.type);
    final unit = unitFor(stage.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.textPrimary.withValues(alpha: 0.06),
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
                            '${stage.number}',
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
                              stage.name.isEmpty
                                  ? 'Stage ${stage.number}'
                                  : stage.name,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: _StageValue(
                                stage: stage,
                                color: color,
                                unit: unit,
                              ),
                            ),
                            if (stage.curveSeconds != null && !stage.isConstant)
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text(
                                  'over ${formatNumber(stage.curveSeconds!)} s · ${stage.interpolation}',
                                  style: TextStyle(
                                    color: context.colors.textTertiary,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if (!stage.isConstant && stage.points.length >= 2) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _CurvePainter(
                            points: stage.points,
                            color: color,
                            smooth: stage.interpolation == 'curve',
                          ),
                        ),
                      ),
                    ],
                    if (stage.exitTriggers.isNotEmpty ||
                        stage.limits.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (stage.exitTriggers.isNotEmpty)
                            const _InlineLabel('Exit'),
                          for (final t in stage.exitTriggers)
                            _TriggerChip(trigger: t),
                          if (stage.limits.isNotEmpty)
                            const _InlineLabel('Limit'),
                          for (final l in stage.limits) _LimitChip(limit: l),
                        ],
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

// The stage's setpoint on the right: "9 bar", "1 → 1.5 ml/s", "100 %".
class _StageValue extends StatelessWidget {
  const _StageValue({
    required this.stage,
    required this.color,
    required this.unit,
  });

  final ProfileStage stage;
  final Color color;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final start = stage.startValue;
    final end = stage.endValue;
    if (start == null) return const SizedBox.shrink();
    final valueStyle = TextStyle(
      color: color,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: formatNumber(start), style: valueStyle),
          if (!stage.isConstant && end != null) ...[
            TextSpan(
              text: '  →  ',
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 13,
              ),
            ),
            TextSpan(text: formatNumber(end), style: valueStyle),
          ],
          TextSpan(
            text: ' $unit',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _InlineLabel extends StatelessWidget {
  const _InlineLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    '$text:',
    style: TextStyle(color: context.colors.textTertiary, fontSize: 11.5),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.text,
    required this.color,
    this.tooltip,
  });

  final IconData icon;
  final String text;
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: Color.lerp(color, context.colors.textPrimary, 0.25),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

IconData _triggerIcon(String type) => switch (type) {
  'time' => Icons.timer_outlined,
  'weight' => Icons.scale_outlined,
  'pressure' => Icons.speed,
  'flow' => Icons.water_drop_outlined,
  'piston_position' => Icons.height,
  _ => Icons.flag_outlined,
};

// Value + unit; an unresolved variable shows its name.
String _valueText(ProfileValue v, String type) {
  final n = v.value;
  if (n == null) return v.variable ?? '–';
  final unit = unitFor(type);
  return unit == '%'
      ? '${formatNumber(n)} %'
      : '${formatNumber(n)} $unit'.trim();
}

class _TriggerChip extends StatelessWidget {
  const _TriggerChip({required this.trigger});

  final StageTrigger trigger;

  @override
  Widget build(BuildContext context) {
    final isTime = trigger.type == 'time';
    final color = isTime
        ? context.colors.textSecondary
        : colorForType(context, trigger.type);
    var text = _valueText(trigger.value, trigger.type);
    // Absolute time = time since shot start instead of since stage start.
    if (isTime && !trigger.relative) text = '$text total';
    return _Chip(
      icon: _triggerIcon(trigger.type),
      text: text,
      color: color,
      tooltip: [
        'Exit when ${typeLabel(trigger.type).toLowerCase()} ${trigger.comparison} ${_valueText(trigger.value, trigger.type)}',
        if (trigger.value.variable != null)
          '(variable: ${trigger.value.variable})',
      ].join(' '),
    );
  }
}

class _LimitChip extends StatelessWidget {
  const _LimitChip({required this.limit});

  final StageLimit limit;

  @override
  Widget build(BuildContext context) => _Chip(
    icon: Icons.arrow_circle_up_outlined,
    text: _valueText(limit.value, limit.type),
    color: colorForType(context, limit.type),
    tooltip: [
      'Limits ${typeLabel(limit.type).toLowerCase()} to ${_valueText(limit.value, limit.type)}',
      if (limit.value.variable != null) '(variable: ${limit.value.variable})',
    ].join(' '),
  );
}

// Small setpoint curve of a stage (points of the dynamics).
class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.points,
    required this.color,
    required this.smooth,
  });

  final List<StagePoint> points;
  final Color color;
  final bool smooth;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [
      for (final p in points)
        if (p.x != null && p.y != null) p,
    ];
    if (pts.length < 2) return;
    final minX = pts.first.x!;
    final maxX = pts.last.x!;
    var minY = pts.map((p) => p.y!).reduce((a, b) => a < b ? a : b);
    var maxY = pts.map((p) => p.y!).reduce((a, b) => a > b ? a : b);
    if (maxY - minY < 1e-9) {
      minY -= 1;
      maxY += 1;
    }
    const pad = 4.0;
    Offset at(StagePoint p) => Offset(
      pad +
          (maxX == minX ? 0 : (p.x! - minX) / (maxX - minX)) *
              (size.width - 2 * pad),
      size.height -
          pad -
          (p.y! - minY) / (maxY - minY) * (size.height - 2 * pad),
    );
    final offsets = pts.map(at).toList();
    final line = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    if (smooth && offsets.length > 2) {
      for (var i = 1; i < offsets.length; i++) {
        final prev = offsets[i - 1];
        final cur = offsets[i];
        final midX = (prev.dx + cur.dx) / 2;
        line.cubicTo(midX, prev.dy, midX, cur.dy, cur.dx, cur.dy);
      }
    } else {
      for (final o in offsets.skip(1)) {
        line.lineTo(o.dx, o.dy);
      }
    }
    final area = Path.from(line)
      ..lineTo(offsets.last.dx, size.height)
      ..lineTo(offsets.first.dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (final o in offsets) {
      canvas.drawCircle(o, 2.6, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.points != points || old.color != color || old.smooth != smooth;
}

// ------------------------------------------------------------- Variables

class _VariablesSection extends StatelessWidget {
  const _VariablesSection(this.variables);

  final List<ProfileVariable> variables;

  @override
  Widget build(BuildContext context) {
    return _Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Variables'),
          const SizedBox(height: 2),
          Text(
            'Values the stages refer to — adjustable on the machine.',
            style: TextStyle(
              color: context.colors.textTertiary,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < variables.length; i++) ...[
            if (i > 0) Divider(height: 1, color: context.colors.divider),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colorForType(context, variables[i].type),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      variables[i].name,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                  Text(
                    formatNumber(variables[i].value),
                    style: TextStyle(
                      color: colorForType(context, variables[i].type),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (unitFor(variables[i].type).isNotEmpty)
                    Text(
                      ' ${unitFor(variables[i].type)}',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Info

class _InfoSection extends StatelessWidget {
  const _InfoSection({
    required this.detail,
    required this.stored,
    required this.usage,
    required this.refreshOk,
  });

  final ProfileDetail detail;
  final StoredProfile stored;
  final Future<ProfileUsage>? usage;
  // Whether the sync with the machine just succeeded (null = running).
  final bool? refreshOk;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
    Widget text(String s) => Text(s, style: const TextStyle(fontSize: 13.5));

    return _Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('About'),
          const SizedBox(height: 4),
          if (detail.author != null) row('Author', text(detail.author!)),
          if (detail.previousAuthors.isNotEmpty)
            row('Based on', text(detail.previousAuthors.join(', '))),
          if (detail.lastChanged != null)
            row('Last changed', text(dateTimeLabel(detail.lastChanged!))),
          FutureBuilder<ProfileUsage>(
            future: usage,
            builder: (context, snapshot) {
              final u = snapshot.data;
              if (u == null) return const SizedBox.shrink();
              final parts = [
                u.count == 1 ? '1 shot' : '${u.count} shots',
                if (u.averageRating != null)
                  'Ø ${u.averageRating!.toStringAsFixed(1)} ★',
                if (u.lastUsed != null) 'last ${dateLabel(u.lastUsed!)}',
              ];
              return row(
                'Your shots',
                text(u.count == 0 ? 'Not used yet' : parts.join(' · ')),
              );
            },
          ),
          if (detail.isTemporary)
            row('Status', text('Temporary (not saved on the machine)')),
          row(
            'Saved in app',
            text(
              refreshOk == false
                  ? 'Offline copy from ${dateTimeLabel(stored.fetchedAt)}'
                  : 'Synced ${dateTimeLabel(stored.fetchedAt)}',
            ),
          ),
          row(
            'Profile ID',
            SelectableText(
              detail.id,
              style: TextStyle(
                color: context.colors.textTertiary,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
