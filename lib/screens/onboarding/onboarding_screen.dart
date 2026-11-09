import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../beans/bean_form_screen.dart';
import '../settings/connections_screen.dart';
import '../settings/my_coffee_desk_screen.dart';
import 'onboarding_art.dart';

// The introduction on the very first start: full-screen pages with a
// picture, a heading, one sentence, "Add …" and "Skip". Each "Add" opens the
// real screen; coming back from it with something saved moves on.

/// What the "Add" buttons open. true = go to the next page afterwards.
class OnboardingActions {
  const OnboardingActions({
    this.connectMachine = _openConnections,
    this.addBean = _openBeanForm,
    this.addGear = _openDesk,
    this.addChain = _openChains,
  });

  final Future<bool> Function(BuildContext) connectMachine;
  final Future<bool> Function(BuildContext) addBean;
  final Future<bool> Function(BuildContext) addGear;
  final Future<bool> Function(BuildContext) addChain;

  static Future<bool> _openConnections(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ConnectionsScreen()));
    return true;
  }

  static Future<bool> _openBeanForm(BuildContext context) async {
    final saved = await Navigator.of(
      context,
    ).push<Object?>(MaterialPageRoute(builder: (_) => const BeanFormScreen()));
    return saved != null;
  }

  static Future<bool> _desk(
    BuildContext context, {
    required bool chains,
  }) async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            MyCoffeeDeskScreen(startOnChains: chains, closeAfterAdding: true),
      ),
    );
    return added ?? false;
  }

  static Future<bool> _openDesk(BuildContext context) =>
      _desk(context, chains: false);

  static Future<bool> _openChains(BuildContext context) =>
      _desk(context, chains: true);
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onFinished,
    this.actions = const OnboardingActions(),
  });

  final VoidCallback onFinished;
  final OnboardingActions actions;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  const _Page(this.art, this.title, this.text, this.button, this.action);

  final Widget art;
  final String title;
  final String text;
  final String button;
  final Future<bool> Function(BuildContext)? action;
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  var _index = 0;
  var _busy = false;

  late final _pages = [
    _Page(
      const MachineArt(),
      'Connect your machine',
      'Follow every shot live and start it from your phone.',
      'Add machine',
      widget.actions.connectMachine,
    ),
    _Page(
      const BeansArt(),
      'Add a bean',
      'See how fresh it is, what is left and every cup you made with it.',
      'Add bean',
      widget.actions.addBean,
    ),
    _Page(
      const DeskArt(),
      'Add your gear',
      'Keep your grinders, brewers and scales in one place, like your coffee '
          'desk at home.',
      'Add gear',
      widget.actions.addGear,
    ),
    _Page(
      const ChainArt(),
      'Create brew chains',
      'Group the gear you brew with and pick it all at once.',
      'Create brew chain',
      widget.actions.addChain,
    ),
    const _Page(
      CupArt(),
      'Ready for brewing',
      'Have a nice cup of coffee.',
      "Let's go",
      null,
    ),
  ];

  bool get _onLast => _index == _pages.length - 1;

  void _next() => setState(() => _index++);

  void _back() => setState(() => _index--);

  Future<void> _primary() async {
    final action = _pages[_index].action;
    if (action == null) {
      widget.onFinished();
      return;
    }
    if (_busy) return;
    _busy = true;
    final moveOn = await action(context);
    _busy = false;
    if (moveOn && mounted) _next();
  }

  // System back: a page back; on the last page it means done. On the first
  // page it leaves the app as usual.
  void _handleSystemBack(bool didPop, Object? result) {
    if (didPop) return;
    if (_onLast) {
      widget.onFinished();
    } else {
      _back();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final page = _pages[_index];
    final artBackground = onboardingArtBackground(colors);
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: _handleSystemBack,
      child: Scaffold(
        backgroundColor: colors.bg,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Column(
            key: ValueKey(_index),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: artBackground),
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: Center(child: page.art),
                    ),
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0, 0.26, 0.66, 1],
                            colors: [
                              colors.bg.withValues(alpha: 0.45),
                              colors.bg.withValues(alpha: 0),
                              colors.bg.withValues(alpha: 0),
                              colors.bg,
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_index > 0 && !_onLast)
                      SafeArea(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            tooltip: 'Back',
                            icon: Icon(
                              Icons.arrow_back,
                              color: colors.textPrimary,
                            ),
                            onPressed: _back,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      page.title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      page.text,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.accent,
                          foregroundColor: colors.bg,
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: _primary,
                        child: Text(page.button),
                      ),
                    ),
                    SizedBox(
                      height: 48,
                      child: _onLast
                          ? null
                          : TextButton(
                              onPressed: _next,
                              child: Text(
                                'Skip',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
