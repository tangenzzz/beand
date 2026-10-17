import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/ai/ai_prompt.dart';
import '../../services/ai/ai_provider.dart';
import '../../services/ai/ai_service.dart';
import '../../services/ai/ai_settings.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/dot_choice_group.dart';
import 'settings_widgets.dart';
import '../../widgets/app_switch_tile.dart';

// Settings → AI. One card, like on every settings page.
//
// The order from top to bottom is the order of setting it up: pick a
// provider → get and enter a key → pick a model → test → decide which
// features may take part. Deleting the key comes last at the bottom of the
// page (destructive actions go at the bottom).
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _keyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();

  AiProvider? _loadedFor;
  bool _modelsOpen = false;
  bool _loadingModels = false;
  List<AiModel>? _models;
  String? _modelsError;

  bool _testing = false;
  String? _testResult;
  String? _testWarning;
  bool _testOk = false;

  @override
  void dispose() {
    _keyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  // On a provider change everything belonging to the old one must be reset:
  // otherwise Gemini's model list shows under "Claude" and the test result
  // claims something about a connection that no longer exists.
  void _syncTo(AiSettings settings) {
    if (_loadedFor == settings.provider) return;
    _loadedFor = settings.provider;
    _keyController.clear();
    _baseUrlController.text = settings.baseUrl;
    _models = null;
    _modelsError = null;
    _modelsOpen = false;
    _testResult = null;
  }

  Future<void> _saveKey(AiSettings settings) async {
    final entered = _keyController.text.trim();
    if (entered.isEmpty) return;
    await settings.setKey(settings.provider, entered);
    if (!mounted) return;
    _keyController.clear();
    setState(() => _testResult = null);
    // The first use of a fresh key: finally fetch the real model list
    // instead of making the user type names.
    await _loadModels(settings);
  }

  Future<void> _loadModels(AiSettings settings) async {
    setState(() {
      _loadingModels = true;
      _modelsError = null;
    });
    try {
      final models = await context.read<AiService>().listModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        _modelsOpen = models.isNotEmpty;
      });
    } on AiFailure catch (e) {
      if (!mounted) return;
      setState(() => _modelsError = e.message);
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _test(AiSettings settings) async {
    setState(() {
      _testing = true;
      _testResult = null;
      _testWarning = null;
    });
    try {
      final ping = await context.read<AiService>().ping();
      if (!mounted) return;
      setState(() {
        _testOk = true;
        // A caveat is not an error, but it has to be shown: otherwise
        // "works" sometimes means "works with forced format" and sometimes
        // "works because the app gave in", and you can't tell the difference.
        _testWarning = ping.caveat;
        final tokens = ping.tokenLine;
        _testResult =
            'Answered as ${ping.model}'
            '${ping.answer.isEmpty ? '' : ' — "${ping.answer}"'}'
            '${tokens.isEmpty ? '' : ' · $tokens'}'
            '${ping.isStrict ? ' · structured output enforced' : ''}';
      });
    } on AiFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testWarning = null;
        _testResult = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testWarning = null;
        _testResult = '$e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AiSettings>();
    _syncTo(settings);
    final provider = settings.provider;

    return Scaffold(
      appBar: AppBar(title: const Text('AI')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.tileOuterMargin),
        children: [
          SettingsCard(
            children: [
              // The main switch sits NEXT TO the explanation, not above it:
              // the text already says what turns on and off here, and a
              // separate "Use AI" row above would say the same thing twice.
              //
              // Off really means off — everything below disappears, and
              // nothing AI-related shows up anywhere in the app. The key
              // stays stored: you should be able to disable AI without
              // having to re-enter the key next time.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.dividerInset,
                  14,
                  8,
                  14,
                ),
                child: Row(
                  children: [
                    // The explanation sits behind the ⓘ; the title names
                    // what the switch does.
                    const Expanded(
                      child: SettingsTitle(
                        'Use your own AI key',
                        info:
                            "bean'd has no AI server of its own. You bring "
                            'your own API key, the app talks to the provider '
                            'directly, and nothing is sent anywhere else.',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: settings.enabled,
                      onChanged: (value) {
                        settings.setEnabled(value);
                        // A test result from earlier says nothing about a
                        // state that no longer exists.
                        setState(() {
                          _testResult = null;
                          _testWarning = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
              if (settings.enabled) ...[
                _Section(
                  title: 'Provider',
                  info: '${provider.vendor}. ${provider.note}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DotChoiceGroup<AiProvider>(
                        options: [
                          for (final p in AiProvider.values)
                            DotChoice(p, p.label),
                        ],
                        value: provider,
                        onChanged: (value) => settings.setProvider(value!),
                      ),
                    ],
                  ),
                ),
                if (provider.requiresBaseUrl)
                  _Section(
                    title: 'Base URL',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _baseUrlController,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          style: TextStyle(color: context.colors.textPrimary),
                          decoration: _fieldDecoration(
                            context,
                            'https://openrouter.ai/api/v1',
                          ),
                          onSubmitted: settings.setBaseUrl,
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: AppButton(
                            label: 'Save',
                            expand: false,
                            onPressed: () =>
                                settings.setBaseUrl(_baseUrlController.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                _Section(
                  title: 'API key',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            settings.hasKey(provider)
                                ? Icons.lock_outline
                                : Icons.lock_open_outlined,
                            size: 16,
                            color: settings.hasKey(provider)
                                ? context.colors.success
                                : context.colors.textTertiary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              settings.hasKey(provider)
                                  ? 'Stored in the device keystore'
                                  : 'No key for ${provider.label} yet',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => launchUrl(
                              Uri.parse(provider.keyUrl),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: Text(
                              'Get a key',
                              style: TextStyle(
                                color: context.colors.accent,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _keyController,
                        // The key is pasted in plain text but not displayed —
                        // otherwise it would be readable by anyone on the
                        // screen and in the keyboard's suggestion memory.
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: TextStyle(color: context.colors.textPrimary),
                        decoration: _fieldDecoration(
                          context,
                          settings.hasKey(provider)
                              ? 'Paste a new key to replace it'
                              : provider.keyHint,
                        ),
                        onSubmitted: (_) => _saveKey(settings),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: AppButton(
                          label: 'Save key',
                          expand: false,
                          onPressed: () => _saveKey(settings),
                        ),
                      ),
                    ],
                  ),
                ),
                _modelSection(context, settings),
                _Section(
                  title: 'Test connection',
                  info:
                      'Sends one tiny request — it checks the key, the model '
                      'name and that the answer comes back in the structured '
                      'form the app needs.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AppButton(
                            label: _testing ? 'Testing…' : 'Test',
                            expand: false,
                            onPressed: _testing ? null : () => _test(settings),
                          ),
                        ],
                      ),
                      if (_testResult != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              !_testOk
                                  ? Icons.error_outline
                                  : _testWarning == null
                                  ? Icons.check_circle_outline
                                  : Icons.info_outline,
                              size: 16,
                              color: !_testOk
                                  ? context.colors.danger
                                  : _testWarning == null
                                  ? context.colors.success
                                  : context.colors.sensorMid,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _testResult!,
                                    style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                  if (_testWarning != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      _testWarning!,
                                      style: TextStyle(
                                        color: context.colors.sensorMid,
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                for (final feature in AiFeature.values)
                  AppSwitchTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.dividerInset,
                      vertical: 6,
                    ),
                    title: SettingsTitle(
                      feature.label,
                      info: feature.description,
                    ),
                    value: settings.isFeatureOn(feature),
                    onChanged: (value) => settings.setFeatureOn(feature, value),
                  ),
                if (settings.hasKey(provider))
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.dividerInset,
                      vertical: 10,
                    ),
                    child: AppButton(
                      label: 'Remove ${provider.label} key',
                      variant: AppButtonVariant.destructive,
                      expand: true,
                      onPressed: () async {
                        await settings.removeKey(provider);
                        if (!mounted) return;
                        setState(() => _testResult = null);
                      },
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // The model picker: expandable list in the sheet itself, like all dropdown
  // lists in the app — the selected row has a checkmark, the trigger row is
  // not highlighted. At the bottom the row for a name that isn't in the
  // list.
  Widget _modelSection(BuildContext context, AiSettings settings) {
    final colors = context.colors;
    final models = _models ?? settings.provider.fallbackModels;
    final current = settings.model;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _modelsOpen = !_modelsOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.dividerInset,
              vertical: 14,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Model',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        current.isEmpty ? 'none selected' : current,
                        style: TextStyle(
                          color: colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_loadingModels)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.textTertiary,
                    ),
                  )
                else
                  Icon(
                    _modelsOpen ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: colors.textTertiary,
                  ),
              ],
            ),
          ),
        ),
        if (_modelsOpen) ...[
          if (_models == null && _modelsError == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.dividerInset,
                0,
                AppSpacing.dividerInset,
                10,
              ),
              child: Text(
                'Not fetched yet — these are the names bean\'d knows. '
                'Reload to ask ${settings.provider.vendor} what your key can '
                'actually use.',
                style: TextStyle(
                  color: colors.textTertiary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          if (_modelsError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.dividerInset,
                0,
                AppSpacing.dividerInset,
                10,
              ),
              child: Text(
                _modelsError!,
                style: TextStyle(
                  color: colors.danger,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          for (final model in models)
            SettingsChoiceRow(
              icon: Icons.auto_awesome_outlined,
              title: model.label,
              subtitle:
                  model.note ?? (model.label == model.id ? null : model.id),
              selected: model.id == current,
              onTap: () {
                settings.setModel(model.id);
                setState(() {
                  _modelsOpen = false;
                  _testResult = null;
                });
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.dividerInset,
              6,
              AppSpacing.dividerInset,
              14,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _modelController,
                    autocorrect: false,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    decoration: _fieldDecoration(context, 'Other model id'),
                    onSubmitted: (value) {
                      if (value.trim().isEmpty) return;
                      settings.setModel(value.trim());
                      _modelController.clear();
                      setState(() {
                        _modelsOpen = false;
                        _testResult = null;
                      });
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Reload from provider',
                  icon: Icon(
                    Icons.refresh,
                    size: 20,
                    color: colors.textSecondary,
                  ),
                  onPressed: _loadingModels
                      ? null
                      : () => _loadModels(settings),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _fieldDecoration(BuildContext context, String hint) =>
      InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        hintText: hint,
        hintStyle: TextStyle(color: context.colors.textTertiary),
      );
}

// Section inside the card — same shape as in Appearance.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.info});

  final String title;
  final Widget child;
  final String? info;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.dividerInset,
        14,
        AppSpacing.dividerInset,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsTitle(title, info: info),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
