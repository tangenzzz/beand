import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import 'settings_widgets.dart';

// Settings → Home → Espresso: the switch for the pill on Home and the name
// it shows — your machine's ("Lelit Bianca") instead of "Espresso". One card
// per page.
class EspressoSettingsScreen extends StatelessWidget {
  const EspressoSettingsScreen({super.key});

  static const _mode = HomeMode.espresso;

  Future<void> _rename(BuildContext context) async {
    final settings = context.read<AppSettings>();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _DisplayNameDialog(current: settings.homeModeName(_mode)),
    );
    if (name != null) await settings.setHomeModeName(_mode, name);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final name = settings.homeModeName(_mode);
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              SettingsGroup(
                children: [
                  SettingsSwitchRow(
                    title: 'Show on Home',
                    value: settings.isHomeModeEnabled(_mode),
                    onChanged: (v) => settings.setHomeModeEnabled(_mode, v),
                  ),
                  SettingsRow(
                    key: const ValueKey('espresso-display-name'),
                    title: 'Display name',
                    subtitle: name,
                    onTap: () => _rename(context),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DisplayNameDialog extends StatefulWidget {
  const _DisplayNameDialog({required this.current});

  final String current;

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late final _name = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      backgroundColor: colors.card,
      title: Text('Display name', style: TextStyle(color: colors.textPrimary)),
      content: TextField(
        key: const ValueKey('espresso-name-field'),
        controller: _name,
        autofocus: true,
        // Short enough for the pill on Home.
        maxLength: 20,
        textCapitalization: TextCapitalization.words,
        style: TextStyle(color: colors.textPrimary),
        // Empty goes back to "Espresso".
        decoration: InputDecoration(hintText: HomeMode.espresso.label),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _name.text),
          child: Text('Save', style: TextStyle(color: colors.accent)),
        ),
      ],
    );
  }
}
