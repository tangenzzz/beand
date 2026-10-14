import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../services/ai/ai_prompt.dart';
import '../../services/ai/ai_service.dart';
import '../../services/ai/ai_settings.dart';
import '../../services/ai/shot_analysis.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import 'history_logic.dart';
import 'section_header.dart';

// AI ANALYSIS section in the shot detail, below NOTES (rate it yourself
// first, then ask the AI). Only present when the AI is set up and the
// feature is on — otherwise none of it shows, not even a saved analysis.
//
// The analysis is stored on the shot (shots.aiAnalysis): an old shot shows
// it immediately, offline and without new costs. ↻ asks again and
// overwrites.
class ShotAnalysisSection extends StatefulWidget {
  const ShotAnalysisSection({
    super.key,
    required this.shot,
    this.autoStart = false,
  });

  final Shot shot;

  /// From the Post-Shot card: start right away if there is no analysis yet,
  /// and scroll the section into view.
  final bool autoStart;

  @override
  State<ShotAnalysisSection> createState() => _ShotAnalysisSectionState();
}

class _ShotAnalysisSectionState extends State<ShotAnalysisSection> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_enabled) return;
        // Tapping "Analyse this shot" in the Post-Shot card means wanting to
        // see the analysis — so expand it if it was collapsed.
        context.read<AppSettings>().setExpandAiAnalysis(true);
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
        if (widget.shot.aiAnalysis == null) _analyse();
      });
    }
  }

  bool get _enabled =>
      context.read<AiSettings>().isEnabled(AiFeature.shotAnalysis);

  Future<void> _analyse() async {
    if (_busy) return;
    final db = context.read<AppDatabase>();
    final ai = context.read<AiService>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final input = await loadShotAnalysisInput(db, widget.shot.id);
      if (input == null) return;
      final result = await ai.analyseShot(input);
      await db.setShotAnalysis(
        widget.shot.id,
        json: result.analysis.encode(),
        model: result.model,
      );
    } on AiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<AiSettings, bool>(
      (s) => s.isEnabled(AiFeature.shotAnalysis),
    );
    if (!enabled) return const SizedBox.shrink();
    final expanded = context.select<AppSettings, bool>(
      (s) => s.expandAiAnalysis,
    );

    final colors = context.colors;
    final shot = widget.shot;
    final analysis = ShotAnalysis.decode(shot.aiAnalysis);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 12),
          child: Divider(height: 1, color: colors.divider),
        ),
        SectionHeader(
          label: 'AI ANALYSIS',
          expanded: expanded,
          onToggle: () =>
              context.read<AppSettings>().setExpandAiAnalysis(!expanded),
          trailing: [
            if (analysis != null && expanded) ...[
              Flexible(
                flex: 4,
                child: Text(
                  [
                    shot.aiAnalysisModel,
                    if (shot.aiAnalysedAt != null)
                      dateLabel(shot.aiAnalysedAt!),
                  ].whereType<String>().join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: colors.textTertiary, fontSize: 11),
                ),
              ),
              const SizedBox(width: 4),
              _busy
                  ? const _Spinner()
                  : InkWell(
                      key: const ValueKey('reanalyse'),
                      customBorder: const CircleBorder(),
                      onTap: _analyse,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Tooltip(
                          message: 'Re-analyse',
                          child: Icon(
                            Icons.refresh,
                            size: 16,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
            ],
          ],
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          if (analysis != null)
            AnimatedOpacity(
              opacity: _busy ? 0.4 : 1,
              duration: const Duration(milliseconds: 200),
              child: _AnalysisBody(analysis: analysis),
            )
          else
            _StartRow(busy: _busy, onTap: _analyse),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _analyse,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        'Retry',
                        style: TextStyle(color: colors.accent, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

// The same quiet row as "Fill from packaging or link" in the bean form.
class _StartRow extends StatelessWidget {
  const _StartRow({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: busy
                  ? const _Spinner()
                  : Icon(
                      Icons.auto_awesome_outlined,
                      size: 16,
                      color: colors.textSecondary,
                    ),
            ),
            const SizedBox(width: 8),
            Text(
              busy ? 'Analysing…' : 'Analyse this shot',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisBody extends StatelessWidget {
  const _AnalysisBody({required this.analysis});

  final ShotAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (analysis.summary.isNotEmpty)
          Text(
            analysis.summary,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        for (final (i, step) in analysis.steps.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: colors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.change,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                      if (step.why.isNotEmpty)
                        Text(
                          step.why,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (analysis.caveat != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              analysis.caveat!,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: context.colors.textTertiary,
    ),
  );
}
