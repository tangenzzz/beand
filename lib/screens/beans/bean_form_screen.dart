import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../services/ai/ai_prompt.dart';
import '../../services/ai/ai_service.dart';
import '../../services/ai/ai_settings.dart';
import '../../services/ai/bean_extraction.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import 'bean_suggestions.dart';
import 'bean_widgets.dart';
import '../../widgets/dot_choice_group.dart';
import '../../widgets/app_button.dart';

// Form for creating/editing a bean (one card, photo at the top,
// label-left/value-right like the Pre-Shot card). The pop result is the
// saved Bean (null on cancel or delete).
class BeanFormScreen extends StatefulWidget {
  const BeanFormScreen({super.key, this.bean});

  final Bean? bean;

  @override
  State<BeanFormScreen> createState() => _BeanFormScreenState();
}

class _BeanFormScreenState extends State<BeanFormScreen> {
  static const _labelWidth = 92.0;
  static const _months = [
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

  late final TextEditingController _name;
  late final TextEditingController _roaster;
  late final TextEditingController _country;
  late final TextEditingController _processing;
  late final TextEditingController _variety;
  late final TextEditingController _producer;
  late final TextEditingController _weight;
  late final TextEditingController _cost;
  late final TextEditingController _taste;

  // Both without preselection: null = nothing tapped. Tapping the selected
  // pill again deselects it.
  bool? _isBlend;
  String? _roastedFor;
  DateTime? _roastDate;
  late bool _isFrozen;
  DateTime? _thawedDate;
  String? _photoPath;
  // Photos newly added in this session — deleted again on cancel.
  final _addedPhotos = <String>{};
  bool _saved = false;
  BeanSuggestions _suggestions = const BeanSuggestions();

  // --- Read from packaging/link -------------------------------------------
  //
  // Imported values are NOT saved silently: they appear marked in the form,
  // the user looks at them, and only their normal "Save" makes them real.
  // Marked here means: the field's label carries the accent color until the
  // field is touched.
  final _aiFilled = <String>{};
  bool _aiBusy = false;
  // Owned by the screen, not the dialog: a controller created in the dialog
  // and disposed right after it closes is still in use during the fade-out
  // — "used after being disposed".
  final _link = TextEditingController();
  String? _aiNote;
  _FormSnapshot? _aiUndo;

  @override
  void initState() {
    super.initState();
    final b = widget.bean;
    _name = TextEditingController(text: b?.name)..addListener(_onNameChanged);
    _roaster = TextEditingController(text: b?.roaster);
    _country = TextEditingController(text: b?.country);
    _processing = TextEditingController(text: b?.processing);
    _variety = TextEditingController(text: b?.variety);
    _producer = TextEditingController(text: b?.producer);
    _weight = TextEditingController(text: _formatNumber(b?.weightGrams));
    _cost = TextEditingController(text: _formatNumber(b?.cost));
    _taste = TextEditingController(text: b?.taste);
    _isBlend = b?.isBlend;
    _roastedFor = b?.roastedFor;
    _roastDate = b?.roastDate;
    _isFrozen = b?.isFrozen ?? false;
    _thawedDate = b?.thawedDate;
    _photoPath = b?.photoPath;

    // As soon as the user touches an imported field, it's theirs — the
    // marking disappears by itself without them having to confirm anything.
    for (final entry in _markedControllers.entries) {
      entry.value.addListener(() => _clearMark(entry.key));
    }

    final db = context.read<AppDatabase>();
    db.allBeans().then((beans) {
      if (!mounted) return;
      setState(() => _suggestions = BeanSuggestions.fromBeans(beans));
    });
  }

  @override
  void dispose() {
    if (!_saved) {
      for (final path in _addedPhotos) {
        _deleteFile(path);
      }
    }
    _link.dispose();
    for (final c in [
      _name,
      _roaster,
      _country,
      _processing,
      _variety,
      _producer,
      _weight,
      _cost,
      _taste,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  // Which key belongs to which text field. Name and Roastery are not in
  // BeanFormField (they can't be turned off), but need the same marking.
  Map<String, TextEditingController> get _markedControllers => {
    'name': _name,
    'roaster': _roaster,
    BeanFormField.country.name: _country,
    BeanFormField.processing.name: _processing,
    BeanFormField.variety.name: _variety,
    BeanFormField.producer.name: _producer,
    BeanFormField.weight.name: _weight,
    BeanFormField.cost.name: _cost,
    BeanFormField.taste.name: _taste,
  };

  void _clearMark(String key) {
    if (!_aiFilled.remove(key)) return;
    if (mounted) setState(() {});
  }

  // "17,50" should show as "17.5" — but 250 g is 250 and not 25. Trimming
  // zeros therefore applies ONLY after a decimal comma; before, it ate the
  // last digit of every round number (250 g, 1000 g, 20 €).
  static String _formatNumber(double? v) {
    if (v == null) return '';
    if (v % 1 == 0) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }

  static double? _parseNumber(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  static String? _nullIfEmpty(String text) {
    final t = text.trim();
    return t.isEmpty ? null : t;
  }

  static void _deleteFile(String? path) {
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  String _formatDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _roastDate ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (picked != null) setState(() => _roastDate = picked);
  }

  Future<void> _photoActions() async {
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
            if (_photoPath != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: context.colors.danger,
                ),
                title: Text(
                  'Remove photo',
                  style: TextStyle(color: context.colors.danger),
                ),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'remove') {
      _replacePhoto(null);
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      // The picker returns a cache file Android may delete at any time — so
      // copy it into the app folder.
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'bean_photos'))
        ..createSync(recursive: true);
      final target = p.join(
        dir.path,
        'bean_${DateTime.now().microsecondsSinceEpoch}${p.extension(picked.path)}',
      );
      await File(picked.path).copy(target);
      if (!mounted) {
        _deleteFile(target);
        return;
      }
      _addedPhotos.add(target);
      _replacePhoto(target);
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

  // ----- Fill from packaging or link ----------------------------------------

  Future<void> _showFillSheet() async {
    final source = await showModalBottomSheet<_FillSource>(
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
            for (final entry in const [
              (
                _FillSource.camera,
                Icons.photo_camera_outlined,
                'Photo of the packaging',
              ),
              (
                _FillSource.gallery,
                Icons.photo_library_outlined,
                'Picture from gallery',
              ),
              (_FillSource.link, Icons.link, 'From a shop link'),
            ])
              ListTile(
                leading: Icon(entry.$2, color: context.colors.textSecondary),
                title: Text(
                  entry.$3,
                  style: TextStyle(color: context.colors.textPrimary),
                ),
                onTap: () => Navigator.pop(context, entry.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    if (source == _FillSource.link) {
      await _fillFromLink();
    } else {
      await _fillFromPhoto(source);
    }
  }

  Future<void> _fillFromLink() async {
    _link.clear();
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.card,
        title: Text(
          'Shop link',
          style: TextStyle(color: context.colors.textPrimary, fontSize: 17),
        ),
        // StatefulBuilder because the pasted text must become visible in the
        // dialog itself — the screen below doesn't rebuild from it.
        content: StatefulBuilder(
          builder: (context, setDialogState) => TextField(
            controller: _link,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              hintText: 'https://…',
              hintStyle: TextStyle(color: context.colors.textTertiary),
              // The link almost always comes from the clipboard — on a phone,
              // pasting via the long-press menu is the fiddliest step of the
              // whole flow.
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: Icon(
                  Icons.content_paste,
                  size: 18,
                  color: context.colors.textSecondary,
                ),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  final text = data?.text?.trim();
                  if (text == null || text.isEmpty) return;
                  _link
                    ..text = text
                    ..selection = TextSelection.collapsed(offset: text.length);
                  setDialogState(() {});
                },
              ),
            ),
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _link.text),
            child: Text('Read', style: TextStyle(color: context.colors.accent)),
          ),
        ],
      ),
    );
    if (entered == null || !mounted) return;

    var raw = entered.trim();
    if (raw.isEmpty) return;
    // Copying from the browser sometimes yields just "roesterei.de/kenia" —
    // without a scheme, fetching fails with a meaningless message.
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      raw = 'https://$raw';
    }
    final url = Uri.tryParse(raw);
    if (url == null || !url.hasAuthority) {
      _toast('That does not look like a web address.');
      return;
    }
    await _read(url: url);
  }

  Future<void> _fillFromPhoto(_FillSource source) async {
    final Uint8List bytes;
    String? storedPath;
    try {
      final picked = await ImagePicker().pickImage(
        source: source == _FillSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      bytes = await picked.readAsBytes();

      // The reading photo only becomes the bean's photo if it has none yet:
      // for reading, people usually show the back with the small print, and
      // that shouldn't replace a good product photo. But no image at all is
      // worse than the back.
      if (_photoPath == null) {
        final docs = await getApplicationDocumentsDirectory();
        final dir = Directory(p.join(docs.path, 'bean_photos'))
          ..createSync(recursive: true);
        final target = p.join(
          dir.path,
          'bean_${DateTime.now().microsecondsSinceEpoch}${p.extension(picked.path)}',
        );
        await File(picked.path).copy(target);
        if (!mounted) {
          _deleteFile(target);
          return;
        }
        storedPath = target;
      }
    } catch (_) {
      if (mounted) _toast('Could not load photo');
      return;
    }

    await _read(
      image: AiImage(
        bytes: bytes,
        mediaType: _mediaTypeOf(storedPath ?? 'photo.jpg'),
      ),
      newPhotoPath: storedPath,
    );
  }

  static String _mediaTypeOf(String path) =>
      p.extension(path).toLowerCase() == '.png' ? 'image/png' : 'image/jpeg';

  Future<void> _read({AiImage? image, Uri? url, String? newPhotoPath}) async {
    setState(() {
      _aiBusy = true;
      _aiNote = null;
    });
    try {
      final result = await context.read<AiService>().extractBean(
        image: image,
        url: url,
      );
      if (!mounted) return;
      _applyDraft(result.draft, newPhotoPath: newPhotoPath);
    } on AiFailure catch (e) {
      if (!mounted) return;
      // The photo was for nothing — but it's already copied, so delete it.
      if (newPhotoPath != null) _deleteFile(newPhotoPath);
      setState(() => _aiNote = e.message);
    } catch (e) {
      if (!mounted) return;
      if (newPhotoPath != null) _deleteFile(newPhotoPath);
      setState(() => _aiNote = '$e');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  void _applyDraft(BeanDraft draft, {String? newPhotoPath}) {
    if (draft.isEmpty) {
      if (newPhotoPath != null) _deleteFile(newPhotoPath);
      setState(() => _aiNote = 'Nothing readable found — nothing was changed.');
      return;
    }

    // Before the first letter: whatever is there now must be restorable. A
    // change to the form that can't be undone is no longer a suggestion.
    final before = _FormSnapshot.of(this);
    final filled = <String>{};

    void setText(String key, TextEditingController c, String? value) {
      if (value == null || value.isEmpty) return;
      c.text = value;
      filled.add(key);
    }

    setText('name', _name, draft.name);
    setText('roaster', _roaster, draft.roaster);
    setText(BeanFormField.country.name, _country, draft.country);
    setText(BeanFormField.processing.name, _processing, draft.processing);
    setText(BeanFormField.variety.name, _variety, draft.variety);
    setText(BeanFormField.producer.name, _producer, draft.producer);
    setText(
      BeanFormField.weight.name,
      _weight,
      _formatNumber(draft.weightGrams),
    );
    setText(BeanFormField.cost.name, _cost, _formatNumber(draft.costInEuro));
    setText(
      BeanFormField.taste.name,
      _taste,
      draft.taste.isEmpty ? null : draft.taste.join(', '),
    );

    if (draft.roastDate != null) {
      _roastDate = draft.roastDate;
      filled.add(BeanFormField.roastDate.name);
    }
    if (draft.isBlend != null) {
      _isBlend = draft.isBlend;
      filled.add(BeanFormField.type.name);
    }
    if (draft.roastedFor != null) {
      _roastedFor = draft.roastedFor;
      filled.add(BeanFormField.roastedFor.name);
    }

    if (newPhotoPath != null) {
      _addedPhotos.add(newPhotoPath);
      _photoPath = newPhotoPath;
    }

    setState(() {
      _aiUndo = before;
      // Set the marks only NOW: assigning the texts above triggered the
      // listeners that remove marks.
      _aiFilled
        ..clear()
        ..addAll(filled);
      _aiNote = [
        '${filled.length} field${filled.length == 1 ? '' : 's'} read — '
            'check the highlighted ones.',
        if (draft.hasForeignPrice)
          'The price was not in euro, so it was left out.',
      ].join(' ');
    });
  }

  void _undoFill() {
    final before = _aiUndo;
    if (before == null) return;
    // A photo that only came in with the reading goes back too.
    final photoNow = _photoPath;
    if (photoNow != null &&
        photoNow != before.photoPath &&
        _addedPhotos.remove(photoNow)) {
      _deleteFile(photoNow);
    }
    before.restore(this);
    setState(() {
      _aiFilled.clear();
      _aiUndo = null;
      _aiNote = null;
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  // Freezing pauses the freshness ring. When thawing a bean saved as frozen,
  // the ring starts today (thaw day = roast day); if only toggled back and
  // forth, the saved state is kept.
  void _toggleFrozen() {
    final saved = widget.bean;
    final freezing = !_isFrozen;
    setState(() {
      _isFrozen = freezing;
      if (!freezing) {
        _thawedDate = (saved != null && saved.isFrozen)
            ? DateTime.now()
            : saved?.thawedDate;
      }
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            freezing
                ? 'Frozen – freshness ring paused'
                : (saved != null && saved.isFrozen)
                ? 'Thawed – freshness ring starts today'
                : 'Not frozen',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _replacePhoto(String? newPath) {
    final old = _photoPath;
    // Delete only photos added in this session right away; the bean's saved
    // photo only on save.
    if (old != null && _addedPhotos.remove(old)) _deleteFile(old);
    setState(() => _photoPath = newPath);
  }

  List<String> _normalizedTaste() {
    final seen = <String>{};
    return [
      for (final t in splitTaste(_taste.text))
        if (seen.add(t.toLowerCase())) t,
    ];
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final db = context.read<AppDatabase>();
    final taste = _normalizedTaste();
    final companion = BeansCompanion(
      name: Value(name),
      roaster: Value(_nullIfEmpty(_roaster.text)),
      roastDate: Value(_roastDate),
      isBlend: Value(_isBlend),
      roastedFor: Value(_roastedFor),
      country: Value(_nullIfEmpty(_country.text)),
      processing: Value(_nullIfEmpty(_processing.text)),
      variety: Value(_nullIfEmpty(_variety.text)),
      producer: Value(_nullIfEmpty(_producer.text)),
      isFrozen: Value(_isFrozen),
      thawedDate: Value(_thawedDate),
      weightGrams: Value(_parseNumber(_weight.text)),
      taste: Value(taste.isEmpty ? null : taste.join(', ')),
      cost: Value(_parseNumber(_cost.text)),
      photoPath: Value(_photoPath),
    );
    final existing = widget.bean;
    final saved = existing == null
        ? await db.insertBean(companion)
        : await db.updateBean(existing.id, companion);
    _saved = true;
    if (existing != null && existing.photoPath != _photoPath) {
      _deleteFile(existing.photoPath);
    }
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  // With shots: first say how many will lose the bean and offer "Used up" —
  // usually the bag is just empty, and then everything is kept.
  Future<void> _delete() async {
    final bean = widget.bean!;
    final db = context.read<AppDatabase>();
    final shotCount = await db.countShotsOfBean(bean.id);
    if (!mounted) return;
    final offerUsedUp = shotCount > 0 && bean.emptiedAt == null;
    final choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.card,
        title: Text(
          'Delete bean?',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          shotCount == 0
              ? '"${bean.name}" will be removed.'
              : '"${bean.name}" is used by $shotCount '
                    '${shotCount == 1 ? 'shot' : 'shots'}. They keep their '
                    'data but lose the bean.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (offerUsedUp)
            TextButton(
              onPressed: () => Navigator.pop(context, _DeleteChoice.usedUp),
              child: const Text('Mark as used up'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, _DeleteChoice.delete),
            child: Text(
              'Delete',
              style: TextStyle(color: context.colors.danger),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _DeleteChoice.usedUp:
        await db.updateBean(
          bean.id,
          BeansCompanion(emptiedAt: Value(DateTime.now())),
        );
      case _DeleteChoice.delete:
        await db.deleteBean(bean.id);
        _deleteFile(bean.photoPath);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.bean != null;
    final visibleFields = context.watch<AppSettings>().visibleBeanFormFields;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(editing ? 'Edit bean' : 'New bean'),
        actions: [
          TextButton(
            onPressed: _name.text.trim().isEmpty ? null : _save,
            style: TextButton.styleFrom(foregroundColor: context.colors.accent),
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: context.colors.card,
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                ),
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  children: [
                    // Photo next to name and roastery.
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _PhotoTile(path: _photoPath, onTap: _photoActions),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 44),
                                  child: _SuggestionRow(
                                    label: 'Name',
                                    stacked: true,
                                    marked: _aiFilled.contains('name'),
                                    controller: _name,
                                    suggestions: _suggestions.names,
                                    capitalization: TextCapitalization.words,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                _SuggestionRow(
                                  label: 'Roastery',
                                  stacked: true,
                                  marked: _aiFilled.contains('roaster'),
                                  controller: _roaster,
                                  suggestions: _suggestions.roasters,
                                  capitalization: TextCapitalization.words,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Fill from packaging/link — only if AI is set up AND the
                    // feature is turned on. Otherwise the row isn't there; a
                    // button that first explains it doesn't work is no
                    // button.
                    if (context.watch<AiSettings>().isEnabled(
                      AiFeature.beanForm,
                    ))
                      _fillRow(context),
                    // Order and visibility come from Settings → Beans → Form.
                    for (final field in visibleFields) ...[
                      _dividerOf(context),
                      _fieldRow(field),
                    ],
                  ],
                ),
              ),
              // Snowflake in the top-right card corner (opposite the photo):
              // beans frozen yes/no, pauses the freshness ring.
              Positioned(
                top: 16,
                right: 16,
                child: _FreezeButton(frozen: _isFrozen, onTap: _toggleFrozen),
              ),
            ],
          ),
          if (editing)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppButton(
                label: 'Delete bean',
                icon: Icons.delete_outline,
                variant: AppButtonVariant.destructive,
                onPressed: _delete,
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Subtle and in the form the app already has for this (cf. "Enter address
  // manually" in the connection card): no border, no fill, 13 px in the
  // secondary color. By house rule, only touchable things get a fill.
  Widget _fillRow(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _aiBusy ? null : _showFillSheet,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: _aiBusy
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.textTertiary,
                        )
                      : Icon(
                          Icons.auto_awesome_outlined,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                ),
                const SizedBox(width: 8),
                Text(
                  _aiBusy ? 'Reading…' : 'Fill from packaging or link',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        if (_aiNote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _aiNote!,
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                if (_aiUndo != null)
                  GestureDetector(
                    onTap: _undoFill,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        'Undo',
                        style: TextStyle(color: colors.accent, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _fieldRow(BeanFormField field) {
    switch (field) {
      case BeanFormField.country:
        return _SuggestionRow(
          label: 'Country',
          marked: _aiFilled.contains(field.name),
          controller: _country,
          suggestions: _suggestions.countries,
          capitalization: TextCapitalization.words,
        );
      case BeanFormField.producer:
        return _SuggestionRow(
          label: 'Producer',
          marked: _aiFilled.contains(field.name),
          controller: _producer,
          suggestions: _suggestions.producers,
          capitalization: TextCapitalization.words,
        );
      case BeanFormField.variety:
        return _SuggestionRow(
          label: 'Variety',
          marked: _aiFilled.contains(field.name),
          controller: _variety,
          suggestions: _suggestions.varieties,
          capitalization: TextCapitalization.words,
        );
      case BeanFormField.processing:
        return _SuggestionRow(
          label: 'Processing',
          marked: _aiFilled.contains(field.name),
          controller: _processing,
          suggestions: _suggestions.processings,
          capitalization: TextCapitalization.words,
        );
      case BeanFormField.type:
        return _FormRow(
          label: 'Type',
          marked: _aiFilled.contains(field.name),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: DotChoiceGroup<bool>(
              options: const [
                DotChoice(false, 'Single Origin'),
                DotChoice(true, 'Blend'),
              ],
              value: _isBlend,
              allowDeselect: true,
              onChanged: (value) {
                _clearMark(field.name);
                setState(() => _isBlend = value);
              },
            ),
          ),
        );
      case BeanFormField.roastedFor:
        return _FormRow(
          label: 'Roasted for',
          marked: _aiFilled.contains(field.name),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: DotChoiceGroup<String>(
              options: [
                for (final option in roastedForOptions)
                  DotChoice(option.value, option.label),
              ],
              value: _roastedFor,
              allowDeselect: true,
              onChanged: (value) {
                _clearMark(field.name);
                setState(() => _roastedFor = value);
              },
            ),
          ),
        );
      case BeanFormField.roastDate:
        return _FormRow(
          label: 'Roast date',
          marked: _aiFilled.contains(field.name),
          onTap: () {
            _clearMark(field.name);
            _pickDate();
          },
          trailing: _roastDate == null
              ? Icon(
                  Icons.calendar_today_outlined,
                  color: context.colors.textTertiary,
                  size: 18,
                )
              : GestureDetector(
                  onTap: () {
                    _clearMark(field.name);
                    setState(() => _roastDate = null);
                  },
                  child: Icon(
                    Icons.close,
                    color: context.colors.textTertiary,
                    size: 18,
                  ),
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              _roastDate == null ? 'Not set' : _formatDate(_roastDate!),
              style: TextStyle(
                color: _roastDate == null
                    ? context.colors.textTertiary
                    : context.colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      case BeanFormField.weight:
        return _FormRow(
          label: 'Weight',
          marked: _aiFilled.contains(field.name),
          child: _plainField(_weight, suffix: 'g', numeric: true),
        );
      case BeanFormField.cost:
        return _FormRow(
          label: 'Cost',
          marked: _aiFilled.contains(field.name),
          child: _plainField(_cost, suffix: '€', numeric: true),
        );
      case BeanFormField.taste:
        return _SuggestionRow(
          label: 'Taste',
          marked: _aiFilled.contains(field.name),
          controller: _taste,
          suggestions: _suggestions.tastes,
          tokenMode: true,
          hint: 'e.g. blackcurrant, grapefruit',
        );
    }
  }

  static Widget _dividerOf(BuildContext context) => Divider(
    height: 1,
    indent: AppSpacing.dividerInset,
    endIndent: AppSpacing.dividerInset,
    color: context.colors.divider,
  );

  Widget _plainField(
    TextEditingController controller, {
    String? suffix,
    bool numeric = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
          : null,
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      decoration: _fieldDecoration(context, suffix: suffix),
    );
  }

  static InputDecoration _fieldDecoration(
    BuildContext context, {
    String? hint,
    String? suffix,
    EdgeInsets padding = const EdgeInsets.symmetric(vertical: 14),
  }) {
    return InputDecoration(
      isDense: true,
      border: InputBorder.none,
      contentPadding: padding,
      hintText: hint,
      hintStyle: TextStyle(color: context.colors.textTertiary, fontSize: 14),
      suffixText: suffix,
      suffixStyle: TextStyle(color: context.colors.textSecondary, fontSize: 14),
    );
  }
}

class _FreezeButton extends StatelessWidget {
  const _FreezeButton({required this.frozen, required this.onTap});

  final bool frozen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: frozen,
      label: 'Frozen',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: frozen
                ? context.colors.ice.withValues(alpha: 0.18)
                : context.colors.bg,
            shape: BoxShape.circle,
            border: Border.all(
              color: frozen ? context.colors.ice : context.colors.divider,
            ),
          ),
          child: Icon(
            Icons.ac_unit,
            size: 18,
            color: frozen ? context.colors.ice : context.colors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.path, required this.onTap});

  final String? path;
  final VoidCallback onTap;

  static const _size = 120.0;
  static const _radius = 16.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: path == null ? 'Add photo' : 'Change photo',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (path == null)
                Container(
                  decoration: BoxDecoration(
                    color: context.colors.bg,
                    borderRadius: BorderRadius.circular(_radius),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo_outlined,
                        color: context.colors.textTertiary,
                        size: 30,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Add photo',
                        style: TextStyle(
                          color: context.colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else
                BeanThumbnail(path: path, size: _size, radius: _radius),
              if (path != null)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Label on the left (fixed width), content on the right, optional trailing
// icon.
class _FormRow extends StatelessWidget {
  const _FormRow({
    required this.label,
    required this.child,
    this.trailing,
    this.onTap,
    this.marked = false,
  });

  final String label;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// The value came from packaging or a web page and is not confirmed yet.
  /// This is shown only through the label color — no border, no fill, no
  /// badge. That's the house rule (color only on text) and also the quietest
  /// thing that still stands out.
  final bool marked;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.dividerInset,
        ),
        child: Row(
          children: [
            SizedBox(
              width: _BeanFormScreenState._labelWidth,
              child: Text(
                label,
                style: TextStyle(
                  color: marked
                      ? context.colors.accent
                      : context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(child: child),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

// Text row with suggestion chips below while the field has focus and letters
// have been typed that match the start of a suggestion.
// [tokenMode]: the field holds a comma list; suggestions apply to the word
// being typed, and a tap appends it to the list.
class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow({
    required this.label,
    required this.controller,
    required this.suggestions,
    this.tokenMode = false,
    this.stacked = false,
    this.marked = false,
    this.capitalization = TextCapitalization.none,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final List<String> suggestions;
  final bool tokenMode;

  /// See [_FormRow.marked].
  final bool marked;
  // Label above the field instead of to the left (header block next to the
  // photo).
  final bool stacked;
  final TextCapitalization capitalization;
  final String? hint;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  static const _maxChips = 12;

  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(_SuggestionRow old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  // Words already fully entered (everything before the last comma) and the
  // word currently being typed.
  ({List<String> done, String current}) _split() {
    final text = widget.controller.text;
    if (!widget.tokenMode) return (done: const [], current: text.trim());
    final comma = text.lastIndexOf(',');
    return (
      done: splitTaste(comma < 0 ? '' : text.substring(0, comma)),
      current: text.substring(comma + 1).trim(),
    );
  }

  // Only values starting with the letters already typed; without input (or
  // with an empty current word) there are no suggestions.
  List<String> _matches() {
    if (!_focus.hasFocus) return const [];
    final (:done, :current) = _split();
    final query = current.toLowerCase();
    if (query.isEmpty) return const [];
    final taken = {for (final d in done) d.toLowerCase()};
    return [
      for (final s in widget.suggestions)
        if (!taken.contains(s.toLowerCase()) &&
            s.toLowerCase() != query &&
            s.toLowerCase().startsWith(query))
          s,
    ].take(_maxChips).toList();
  }

  void _apply(String value) {
    final text = widget.tokenMode
        ? '${[..._split().done, value].join(', ')}, '
        : value;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Widget _field() {
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      textCapitalization: widget.capitalization,
      // Room for the chip row below the field so it doesn't end up under the
      // keyboard during autoscroll.
      scrollPadding: const EdgeInsets.only(bottom: 100),
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: widget.stacked ? 15 : 14,
        fontWeight: FontWeight.w500,
      ),
      decoration: _BeanFormScreenState._fieldDecoration(
        context,
        hint: widget.hint,
        padding: EdgeInsets.symmetric(vertical: widget.stacked ? 6 : 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches();
    return Column(
      children: [
        if (widget.stacked)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.marked
                      ? context.colors.accent
                      : context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
              _field(),
            ],
          )
        else
          _FormRow(label: widget.label, marked: widget.marked, child: _field()),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.topCenter,
          child: matches.isEmpty
              ? const SizedBox(width: double.infinity)
              // Without TextFieldTapRegion, a tap on a chip counts as
              // "outside" and takes focus from the field.
              : TextFieldTapRegion(
                  child: SizedBox(
                    height: widget.stacked ? 40 : 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: widget.stacked
                          ? const EdgeInsets.only(top: 4, bottom: 4)
                          : const EdgeInsets.fromLTRB(
                              AppSpacing.dividerInset,
                              0,
                              AppSpacing.dividerInset,
                              10,
                            ),
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) => GestureDetector(
                        onTap: () => _apply(matches[i]),
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: context.colors.divider),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            matches[i],
                            style: TextStyle(
                              color: context.colors.accent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// Where the app should read from.
enum _FillSource { camera, gallery, link }

// The state of the form before anything was imported. Only there so that
// "Undo" really restores everything — including a field that was already
// filled before and got overwritten.
class _FormSnapshot {
  _FormSnapshot({
    required this.texts,
    required this.isBlend,
    required this.roastedFor,
    required this.roastDate,
    required this.photoPath,
  });

  final Map<String, String> texts;
  final bool? isBlend;
  final String? roastedFor;
  final DateTime? roastDate;
  final String? photoPath;

  factory _FormSnapshot.of(_BeanFormScreenState state) => _FormSnapshot(
    texts: {
      for (final entry in state._markedControllers.entries)
        entry.key: entry.value.text,
    },
    isBlend: state._isBlend,
    roastedFor: state._roastedFor,
    roastDate: state._roastDate,
    photoPath: state._photoPath,
  );

  void restore(_BeanFormScreenState state) {
    state._markedControllers.forEach((key, controller) {
      controller.text = texts[key] ?? '';
    });
    state._isBlend = isBlend;
    state._roastedFor = roastedFor;
    state._roastDate = roastDate;
    state._photoPath = photoPath;
  }
}

enum _DeleteChoice { usedUp, delete }
