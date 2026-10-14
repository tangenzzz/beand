import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../models/shot_facts.dart';
import '../../models/shot_phases.dart';
import '../../theme/app_theme.dart';

// Fixed findings in the shot detail, right below the curve — without AI,
// always there. Two parts:
//  * Target and result of the stage at the cursor, right below the stage
//    bar; follows along when swiping over the curve (on the stage bar
//    instead of a separate list).
//  * Below that, the summary for the whole shot: problems first, then
//    notes; if there is no problem, a line says so.
class ShotFactsSection extends StatefulWidget {
  const ShotFactsSection({
    super.key,
    required this.shot,
    required this.readings,
    required this.phases,
    required this.cursorMs,
    this.showStage = true,
  });

  final Shot shot;
  final List<ShotReading> readings;
  final List<ShotPhase> phases;
  final int cursorMs;

  /// Show target and result of the stage at the cursor (collapsed: only the
  /// summary for the whole shot).
  final bool showStage;

  @override
  State<ShotFactsSection> createState() => _ShotFactsSectionState();
}

class _ShotFactsSectionState extends State<ShotFactsSection> {
  ShotFacts? _facts;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void didUpdateWidget(ShotFactsSection old) {
    super.didUpdateWidget(old);
    // Recompute when something the findings depend on changes — not on
    // every star change.
    if (old.readings != widget.readings ||
        old.shot.profileJson != widget.shot.profileJson ||
        old.shot.profileName != widget.shot.profileName ||
        old.shot.finalWeight != widget.shot.finalWeight) {
      _compute();
    }
  }

  Future<void> _compute() async {
    final db = context.read<AppDatabase>();
    final profile = await profileJsonForShot(db, widget.shot);
    if (!mounted) return;
    setState(() {
      _facts = computeShotFacts(
        readings: widget.readings,
        profile: parseShotProfile(profile.json),
        finalWeight: widget.shot.finalWeight,
        machineExits: parseStageExits(widget.shot.stageExits),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final facts = _facts;
    if (facts == null || facts.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    // One arrow for everything: the arrow at the stage name collapses the
    // stage's target/result AND the summary.
    if (!widget.showStage) return const SizedBox.shrink();
    final stage = _stageAtCursor(facts);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stage != null) ...[
            if (stage.goalText case final goal?)
              Text(
                goal,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            _Line(severity: stage.severity, text: stage.resultText(facts)),
            // Short, thin line: a paragraph within the same topic. The full
            // divider separates different topics.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.2,
                  // Same line as the divider, just short.
                  child: Divider(
                    key: const ValueKey('stage-summary-separator'),
                    height: 1,
                    color: colors.divider,
                  ),
                ),
              ),
            ),
          ] else
            const SizedBox(height: 8),
          for (final f in facts.findings)
            _Line(severity: f.severity, text: f.text),
        ],
      ),
    );
  }

  /// The stage the cursor is in. Retraction and stages without findings
  /// (no profile, name does not match) return null.
  StageFact? _stageAtCursor(ShotFacts facts) {
    ShotPhase? phase;
    for (final p in widget.phases) {
      if (widget.cursorMs >= p.startMs) phase = p;
    }
    if (phase == null || phase.isRetraction) return null;
    final key = phase.name.trim().toLowerCase();
    for (final s in facts.stages) {
      if (s.reached && s.name.trim().toLowerCase() == key) return s;
    }
    return null;
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.severity, required this.text});

  final FindingSeverity severity;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              switch (severity) {
                FindingSeverity.problem => Icons.error_outline,
                FindingSeverity.note => Icons.info_outline,
                FindingSeverity.ok => Icons.check_circle_outline,
              },
              size: 14,
              color: switch (severity) {
                FindingSeverity.problem => colors.danger,
                FindingSeverity.note => colors.textTertiary,
                FindingSeverity.ok => colors.success,
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: severity == FindingSeverity.problem
                    ? colors.textPrimary
                    : colors.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
