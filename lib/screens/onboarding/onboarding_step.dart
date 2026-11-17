import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';

// A screen opened from the introduction gets a fixed button at the bottom
// ("Continue"): it closes the screen — and any page opened from it — and
// the introduction moves to its next page. The back arrow top left goes
// back to the same introduction page instead.
//
// The screens only ask [OnboardingStep.maybeOf]; outside the introduction
// it is null and nothing changes.
class OnboardingStep extends InheritedWidget {
  const OnboardingStep({
    super.key,
    required this.onContinue,
    required super.child,
  });

  final VoidCallback onContinue;

  static OnboardingStep? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OnboardingStep>();

  /// Wraps a page pushed from inside a step, so it gets the button too.
  static WidgetBuilder carry(BuildContext context, WidgetBuilder builder) {
    // Called from a tap, not from build: look it up without depending.
    final step = context.getInheritedWidgetOfExactType<OnboardingStep>();
    if (step == null) return builder;
    return (_) => OnboardingStep(
      onContinue: step.onContinue,
      child: Builder(builder: builder),
    );
  }

  @override
  bool updateShouldNotify(OnboardingStep oldWidget) =>
      onContinue != oldWidget.onContinue;
}

/// The bottom bar of a step, or null outside the introduction. [onPressed]
/// replaces the plain "Continue" (the bean form saves first).
Widget? onboardingContinueBar(
  BuildContext context, {
  String label = 'Continue',
  VoidCallback? onPressed,
  bool enabled = true,
}) {
  final step = OnboardingStep.maybeOf(context);
  if (step == null) return null;
  return SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(
      AppSpacing.tileOuterMargin,
      8,
      AppSpacing.tileOuterMargin,
      16,
    ),
    child: AppButton(
      label: label,
      onPressed: enabled ? (onPressed ?? step.onContinue) : null,
      expand: true,
    ),
  );
}
