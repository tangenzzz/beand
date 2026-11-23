import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../services/ai/ai_settings.dart';
import '../../services/live_shot_service.dart';
import '../../services/setup_suggestion.dart';
import '../../services/shot_setup.dart';
import '../history/setup_suggestion_widgets.dart';
import '../../theme/app_theme.dart';
import '../../widgets/taste_chips.dart';
import '../history/history_logic.dart';
import '../history/history_widgets.dart';
import '../history/shot_detail_screen.dart';
import '../../widgets/app_button.dart';
import 'tile_title.dart';

// Post-shot card: the most recently saved shot with rating (stars and taste
// flower) and note — the same data as in the history shot detail. At the
// bottom the Save button: it completes the cycle and releases the pre-shot
// card again (see LiveShotService.activeCard).
class PostShotCard extends StatefulWidget {
  const PostShotCard({super.key});

  @override
  State<PostShotCard> createState() => _PostShotCardState();
}

class _PostShotCardState extends State<PostShotCard> {
  // Create once: a new stream per build() would resubscribe and requery on
  // every rebuild of the carousel.
  //
  // Only shots of the machine whose home screen this card belongs to — each
  // home provides its own LiveShotService (see live_tab.dart), which knows
  // its machine key. Without this, the last Meticulous shot would show in
  // the card after a GaggiMate brew.
  late final Stream<ShotEntry?> _latest = context
      .read<AppDatabase>()
      .watchLatestShotEntry(
        machine: context.read<LiveShotService>().machineKey,
      );

  // The setup a shot without one would get on Save (see _SuggestionBox).
  final _chosen = ValueNotifier<SetupSuggestion?>(null);

  @override
  void dispose() {
    _chosen.dispose();
    super.dispose();
  }

  // Save on a shot without its setup takes the suggestion shown — only into
  // fields still empty, so what was entered in the shot detail meanwhile
  // stays.
  Future<void> _applySuggestion(Shot shot) async {
    final s = _chosen.value;
    if (s == null || !shotNeedsDetails(shot)) return;
    await s.applyTo(context.read<AppDatabase>(), shot.id);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      padding: const EdgeInsets.all(14),
      child: StreamBuilder<ShotEntry?>(
        stream: _latest,
        builder: (context, snapshot) {
          final entry = snapshot.data;
          final isActiveCard = context.select<LiveShotService, bool>(
            (s) => s.activeCard == ActiveCard.post,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileTitle(short: 'POST', active: isActiveCard),
              const SizedBox(height: 10),
              Expanded(
                child: entry == null
                    ? Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          'No shot yet. Your last shot shows up here for rating.',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      )
                    // Key per shot: for a new shot the note starts empty.
                    : _Body(
                        key: ValueKey(entry.shot.id),
                        entry: entry,
                        chosen: _chosen,
                      ),
              ),
              // The AI analysis is tailored to espresso — there is none for
              // pour over.
              if (entry != null && entry.shot.machine != 'pourover')
                _AnalyseRow(shot: entry.shot),
              const SizedBox(height: 10),
              _SaveButton(
                enabled: entry != null,
                beforeSave: entry == null
                    ? null
                    : () => _applySuggestion(entry.shot),
              ),
              const SizedBox(height: AppSpacing.tileActionBottom),
            ],
          );
        },
      ),
    );
  }
}

// Quiet row above Save: opens the shot detail and starts the analysis there
// — the card has no room to show it itself. Only present when AI is set up
// and the feature is on.
class _AnalyseRow extends StatelessWidget {
  const _AnalyseRow({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<AiSettings, bool>(
      (s) => s.isEnabled(AiFeature.shotAnalysis),
    );
    if (!enabled) return const SizedBox.shrink();
    final colors = context.colors;
    return InkWell(
      onTap: () {
        FocusScope.of(context).unfocus();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ShotDetailScreen(shotId: shot.id, analyse: true),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Row(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 16,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              shot.aiAnalysis == null ? 'Analyse this shot' : 'Show analysis',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// Save: rating and note go into the DB debounced anyway — the button takes
// focus away from the text field (which writes the note immediately) and
// then releases the pre-shot card again. Same style and same bottom spacing
// as the buttons of the other two cards.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.enabled, this.beforeSave});

  final bool enabled;

  /// Runs first (takes the suggested setup into a shot without one).
  final Future<void> Function()? beforeSave;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'Save',
      onPressed: enabled
          ? () async {
              FocusScope.of(context).unfocus();
              final live = context.read<LiveShotService>();
              await beforeSave?.call();
              live.confirmPostShot();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Saved'),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          : null,
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({super.key, required this.entry, required this.chosen});

  final ShotEntry entry;
  final ValueNotifier<SetupSuggestion?> chosen;

  @override
  Widget build(BuildContext context) {
    final shot = entry.shot;
    final bean = entry.bean;
    final profile = (shot.profileName ?? '').trim();
    final title = bean?.name ?? (profile.isEmpty ? 'Shot' : profile);
    final details = [
      // Espresso (no machine) has only the one stand-in profile name.
      if (bean != null && profile.isNotEmpty && shot.machine != 'espresso')
        profile,
      // Pour over: water poured and the yield (the coffee in the server,
      // "—" where nothing was weighed).
      if (shot.machine == 'pourover') ...[
        if (shot.finalWeight != null) 'Water ${grams(shot.finalWeight!)} g',
        shot.beverageGrams != null
            ? 'Yield ${grams(shot.beverageGrams!)} g'
            : 'Yield —',
      ] else if (shot.finalWeight != null)
        shot.doseGrams != null
            ? '${grams(shot.doseGrams!)} → ${grams(shot.finalWeight!)} g'
            : '${grams(shot.finalWeight!)} g',
      if (shot.durationMs != null)
        shot.machine == 'pourover'
            ? clockTime(shot.durationMs!)
            : '${seconds(shot.durationMs!)} s',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ShotDetailScreen(shotId: shot.id),
            ),
          ),
          child: Row(
            children: [
              ShotAvatar(shot: shot, bean: bean, size: 34, badge: 14),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        dateTimeLabel(shot.timestamp),
                        details,
                      ].where((t) => t.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: context.colors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
        // Brewed while the app was closed (or added later): what Save would
        // fill in, from the Pre-Shot card or the last shot with this profile.
        if (shotNeedsDetails(shot)) _SuggestionBox(shot: shot, chosen: chosen),
        // A machine the app does not talk to: yield and time by hand
        // (prefilled with what the scale and the app's clock measured).
        if (shot.machine == 'espresso') ...[
          const SizedBox(height: 8),
          _ManualFacts(shot: shot),
        ],
        // Stars, divider and chips need spacing, otherwise they stick
        // together.
        const SizedBox(height: 10),
        Center(
          child: StarRating(
            rating: shot.rating ?? 0,
            size: 22,
            gap: 3,
            tapPadding: 5,
            onChanged: (n) =>
                context.read<AppDatabase>().setShotRating(shot.id, n),
          ),
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: context.colors.divider),
        const SizedBox(height: 12),
        _TasteBlock(shot: shot),
        const SizedBox(height: 10),
        Expanded(
          child: ShotNotesField(
            shotId: shot.id,
            initial: shot.notes,
            expands: true,
          ),
        ),
      ],
    );
  }
}

// The rating chips in the card: abbreviations instead of full names, because
// width is tight. The values go into the DB immediately — like the stars;
// the Save button only completes the cycle.
class _TasteBlock extends StatelessWidget {
  const _TasteBlock({required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    return TasteChips(
      values: shot.tasteValues,
      shortLabels: true,
      onAxisChanged: (axis, value) => db.setShotTaste(shot.id, axis, value),
    );
  }
}

// Yield and time of an Espresso shot (Home → Espresso), editable in place:
// without a scale the yield is only known from the user. Writes after a
// short pause in typing.
class _ManualFacts extends StatefulWidget {
  const _ManualFacts({required this.shot});

  final Shot shot;

  @override
  State<_ManualFacts> createState() => _ManualFactsState();
}

class _ManualFactsState extends State<_ManualFacts> {
  late final _yield = TextEditingController(
    text: _num(widget.shot.finalWeight),
  );
  late final _time = TextEditingController(
    text: _num(
      widget.shot.durationMs == null ? null : widget.shot.durationMs! / 1000,
    ),
  );
  Timer? _debounce;

  static String _num(double? v) =>
      v == null ? '' : v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);

  static double? _parse(String t) =>
      double.tryParse(t.trim().replaceAll(',', '.'));

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _write);
  }

  void _write() {
    _debounce?.cancel();
    final grams = _parse(_yield.text);
    final seconds = _parse(_time.text);
    unawaited(
      context.read<AppDatabase>().updateShotFields(
        widget.shot.id,
        ShotsCompanion(
          finalWeight: Value(grams),
          durationMs: Value(seconds == null ? null : (seconds * 1000).round()),
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) _write();
    _yield.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Field(
            label: 'Yield',
            unit: 'g',
            controller: _yield,
            onChanged: (_) => _changed(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Field(
            label: 'Time',
            unit: 's',
            controller: _time,
            onChanged: (_) => _changed(),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.unit,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final String unit;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      textAlign: TextAlign.end,
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        prefixText: '$label  ',
        prefixStyle: TextStyle(color: colors.textSecondary, fontSize: 12),
        suffixText: ' $unit',
        suffixStyle: TextStyle(color: colors.textSecondary, fontSize: 12),
        hintText: '—',
        hintStyle: TextStyle(color: colors.textTertiary),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colors.accent),
        ),
      ),
    );
  }
}

// The suggested setup of a shot that came in without one (user 2026-11-23):
// its source ("Pre-Shot" / "Last shot") and what Save would write — dimmed,
// it is only a suggestion.
class _SuggestionBox extends StatefulWidget {
  const _SuggestionBox({required this.shot, required this.chosen});

  final Shot shot;
  final ValueNotifier<SetupSuggestion?> chosen;

  @override
  State<_SuggestionBox> createState() => _SuggestionBoxState();
}

class _SuggestionBoxState extends State<_SuggestionBox> {
  List<SetupSuggestion>? _options;
  SetupSource? _source;

  @override
  void initState() {
    super.initState();
    widget.chosen.value = null;
    _load();
  }

  Future<void> _load() async {
    ShotSetups? setups;
    try {
      setups = context.read<ShotSetups>();
    } on ProviderNotFoundException {
      setups = null;
    }
    final options = await suggestSetups(
      context.read<AppDatabase>(),
      widget.shot,
      setups: setups,
    );
    if (!mounted) return;
    setState(() {
      _options = options;
      _source = options.firstOrNull?.source;
    });
    widget.chosen.value = options.firstOrNull;
  }

  void _pick(SetupSource? source) {
    final s = _options?.where((o) => o.source == source).firstOrNull;
    if (s == null) return;
    setState(() => _source = source);
    widget.chosen.value = s;
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    if (options == null || options.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    final current =
        options.where((o) => o.source == _source).firstOrNull ?? options.first;
    final others = options.length > 1;
    // One line — the card has a fixed height: the source (tapping it
    // switches when there are two), then what Save would write, dimmed.
    // Tapping that opens the shot to change a value first.
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        key: const ValueKey('post-suggestion'),
        decoration: BoxDecoration(
          border: Border.all(color: colors.divider),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
        child: Row(
          children: [
            InkWell(
              key: const ValueKey('post-suggestion-source'),
              onTap: others
                  ? () => _pick(
                      options[(options.indexOf(current) + 1) % options.length]
                          .source,
                    )
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      current.source.label,
                      style: TextStyle(
                        color: others ? colors.accent : colors.textTertiary,
                        fontSize: 11.5,
                      ),
                    ),
                    if (others)
                      Icon(Icons.swap_horiz, size: 14, color: colors.accent),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ShotDetailScreen(shotId: widget.shot.id),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SetupSummary(
                        suggestion: current,
                        style: TextStyle(
                          color: colors.textSecondary.withValues(alpha: 0.75),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: colors.textTertiary,
                    ),
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
