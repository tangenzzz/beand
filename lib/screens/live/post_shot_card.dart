import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../services/ai/ai_settings.dart';
import '../../services/live_shot_service.dart';
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
                    : _Body(key: ValueKey(entry.shot.id), entry: entry),
              ),
              // The AI analysis is tailored to espresso — there is none for
              // pour over.
              if (entry != null && entry.shot.machine != 'pourover')
                _AnalyseRow(shot: entry.shot),
              const SizedBox(height: 10),
              _SaveButton(enabled: entry != null),
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
  const _SaveButton({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'Save',
      onPressed: enabled
          ? () {
              FocusScope.of(context).unfocus();
              context.read<LiveShotService>().confirmPostShot();
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
  const _Body({super.key, required this.entry});

  final ShotEntry entry;

  @override
  Widget build(BuildContext context) {
    final shot = entry.shot;
    final bean = entry.bean;
    final profile = (shot.profileName ?? '').trim();
    final title = bean?.name ?? (profile.isEmpty ? 'Shot' : profile);
    final details = [
      if (bean != null && profile.isNotEmpty) profile,
      if (shot.finalWeight != null)
        shot.doseGrams != null
            ? '${grams(shot.doseGrams!)} → ${grams(shot.finalWeight!)} g'
            : '${grams(shot.finalWeight!)} g',
      if (shot.durationMs != null) '${seconds(shot.durationMs!)} s',
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
