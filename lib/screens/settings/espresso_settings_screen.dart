import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../sensors/pressure_sensor.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/value_select_row.dart';
import 'sensor_settings_screen.dart';
import 'settings_widgets.dart';

// Settings → Home → Espresso: the switch for the pill on Home, the name it
// shows — your machine's ("Lelit Bianca") instead of "Espresso" — and which
// pressure sensor the view uses (the sensors themselves are under
// Connections → Sensors). One card per page.
class EspressoSettingsScreen extends StatefulWidget {
  const EspressoSettingsScreen({super.key});

  @override
  State<EspressoSettingsScreen> createState() => _EspressoSettingsScreenState();
}

class _EspressoSettingsScreenState extends State<EspressoSettingsScreen> {
  static const _mode = HomeMode.espresso;

  // "None" in the sensor list (option values can't be null).
  static const _none = '';

  bool _sensorOpen = false;

  void _openSensors() {
    setState(() => _sensorOpen = false);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SensorSettingsScreen()),
    );
  }

  Widget _sensorRow(BuildContext context) {
    final sensor = context.watch<PressureSensor>();
    final inUse = sensor.rememberedId;
    final known = sensor.knownSensors;
    return ValueSelectRow<String>(
      key: const ValueKey('espresso-sensor'),
      label: 'Sensor',
      labelSize: settingsValueLabelSize,
      labelColor: context.colors.textPrimary,
      horizontalPadding: AppSpacing.dividerInset,
      isLast: true,
      listIndent: 0,
      placeholder: 'None',
      valueText: inUse == null
          ? null
          : known.where((k) => k.id == inUse).firstOrNull?.displayName ??
                sensor.displayName,
      value: inUse ?? _none,
      open: _sensorOpen,
      onToggle: () => setState(() => _sensorOpen = !_sensorOpen),
      onClose: () => setState(() => _sensorOpen = false),
      options: [
        const ValueOption(value: _none, title: 'None'),
        for (final k in known)
          ValueOption(
            value: k.id,
            title: k.displayName,
            subtitle: k.customName == null ? null : k.name,
          ),
      ],
      onChanged: (id) {
        setState(() => _sensorOpen = false);
        sensor.select(id == _none ? null : id);
      },
      action: ValueSelectAction('Add sensor', _openSensors),
    );
  }

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
                  _sensorRow(context),
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
