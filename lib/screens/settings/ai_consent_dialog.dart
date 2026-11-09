import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ai/ai_settings.dart';
import '../../theme/app_theme.dart';

/// Asks once per recipient before the first real request goes out, and says
/// who gets what. App Store rule 5.1.2(i) requires this for third-party AI,
/// and it has to be reachable right where the data leaves the phone: the
/// switch in Settings → AI is flipped before a provider is even chosen.
///
/// True when the request may go ahead. Dismissing the dialog counts as no.
Future<bool> ensureAiConsent(BuildContext context) async {
  final settings = context.read<AiSettings>();
  if (settings.hasConsent) return true;
  final recipient = settings.recipientName;
  final allowed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = context.colors;
      final body = TextStyle(color: colors.textSecondary, height: 1.4);
      final label = body.copyWith(color: colors.textPrimary);
      return AlertDialog(
        backgroundColor: colors.card,
        title: Text(
          'Send data to $recipient?',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('bean\'d sends this straight from your phone:', style: body),
              const SizedBox(height: 12),
              Text('Bean form', style: label),
              Text('The photo or shop page you pick.', style: body),
              const SizedBox(height: 12),
              Text('Shot analysis', style: label),
              Text(
                'The shot with its curves, profile, grind, ratings and notes, '
                'the bean, and earlier shots of that bean.',
                style: body,
              ),
              const SizedBox(height: 12),
              Text('$recipient\'s terms apply.', style: body),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Not now',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          TextButton(
            key: const ValueKey('ai-consent-allow'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Allow', style: TextStyle(color: colors.accent)),
          ),
        ],
      );
    },
  );
  if (allowed != true) return false;
  await settings.grantConsent();
  return true;
}
