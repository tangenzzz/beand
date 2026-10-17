import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import 'settings_widgets.dart';

const sourceCodeUrl = 'https://github.com/tangenzzz/beand';

// Projects bean'd builds on. Shown in Settings → About → Credits and kept in
// sync with the credits in README.md.
class Credit {
  const Credit(this.name, this.usage, this.license, this.url);

  final String name;
  final String usage;

  /// Null where nothing is reused under a license (ideas, references).
  final String? license;
  final String url;
}

const credits = [
  Credit(
    'AcaiaArduinoBLE',
    'Acaia scale protocol',
    'MIT',
    'https://github.com/tatemazer/AcaiaArduinoBLE',
  ),
  Credit(
    'MeticAI',
    'Rules for the shot findings',
    'MIT',
    'https://github.com/hessius/MeticAI',
  ),
  Credit(
    'brew-recipes',
    'Pour-over recipes',
    'CC0',
    'https://github.com/HotThoughts/brew-recipes',
  ),
  Credit(
    'espresso-profile-schema',
    'Meticulous profile format',
    null,
    'https://github.com/MeticulousHome/espresso-profile-schema',
  ),
  Credit(
    'pyMeticulous',
    'Meticulous API',
    'GPL-3.0',
    'https://github.com/MeticulousHome/pyMeticulous',
  ),
  Credit(
    'meticulous-mcp',
    'Profile safety rules',
    'GPL-3.0',
    'https://github.com/twchad/meticulous-mcp',
  ),
  Credit(
    'meticulous-addon',
    'Preheat detection',
    'MIT',
    'https://github.com/nickwilsonr/meticulous-addon',
  ),
  Credit(
    'GaggiMate',
    'GaggiMate API',
    'CC BY-NC-SA 4.0',
    'https://github.com/jniebuhr/gaggimate',
  ),
  Credit(
    'GaggiMate logo',
    'Wordmark and cup logo, used with permission',
    null,
    'https://gaggimate.eu',
  ),
  Credit(
    'Uicons by Flaticon',
    'GaggiMate mode icons',
    'Flaticon license',
    'https://www.flaticon.com/uicons',
  ),
  Credit(
    'Nostr NIPs',
    'Sync protocol',
    'Public domain',
    'https://github.com/nostr-protocol/nips',
  ),
  Credit(
    'Blossom',
    'Photo server protocol',
    'Unlicense',
    'https://github.com/hzrd149/blossom',
  ),
  Credit(
    'Coffee Compass',
    'Idea behind the taste feedback',
    null,
    'https://www.baristahustle.com/blog/the-coffee-compass/',
  ),
  Credit(
    'Archivo',
    'Font of the wordmark',
    'OFL',
    'https://fonts.google.com/specimen/Archivo',
  ),
];

Future<void> _open(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              const SettingsNote(
                "bean'd is free and open source (GPL-3.0). It is not "
                'affiliated with any of the manufacturers mentioned; all '
                'trademarks belong to their owners.',
              ),
              SettingsRow(
                icon: Icons.code,
                title: 'Source code',
                subtitle: 'GitHub',
                onTap: () => _open(sourceCodeUrl),
              ),
              SettingsRow(
                icon: Icons.favorite_outline,
                title: 'Credits',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CreditsScreen(),
                  ),
                ),
              ),
              SettingsRow(
                icon: Icons.description_outlined,
                title: 'Open-source licenses',
                onTap: () => _showLicenses(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showLicenses(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showLicensePage(
      context: context,
      applicationName: "bean'd",
      applicationVersion: '${info.version} (${info.buildNumber})',
      applicationLegalese: 'GPL-3.0',
    );
  }
}

class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Credits')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              for (final c in credits)
                SettingsRow(
                  icon: Icons.open_in_new,
                  title: c.name,
                  subtitle: c.license == null
                      ? c.usage
                      : '${c.usage} · ${c.license}',
                  onTap: () => _open(c.url),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
