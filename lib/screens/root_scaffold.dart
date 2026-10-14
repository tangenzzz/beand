import 'package:flutter/material.dart';

import '../theme/bean_icon.dart';
import 'beans/beans_tab.dart';
import 'history/history_tab.dart';
import 'live/live_tab.dart';
import 'settings/settings_screen.dart';

// Access to the root navigation. The tabs open the settings over it instead
// of pushing a page onto the main navigator themselves — otherwise the page
// would also cover the tab bar.
class RootNavigation extends InheritedWidget {
  const RootNavigation({
    super.key,
    required this.openSettings,
    required this.closeSettings,
    this.openSettingsPage,
    required super.child,
  });

  final VoidCallback openSettings;
  // Opens the settings directly on a subpage (e.g. the scale from the
  // Pour Over command row); back then leads to the overview.
  final void Function(WidgetBuilder page)? openSettingsPage;
  final VoidCallback closeSettings;

  /// Null if the screen runs outside the root scaffold (tests or a page
  /// pushed directly onto the main navigator).
  static RootNavigation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RootNavigation>();

  @override
  bool updateShouldNotify(RootNavigation oldWidget) => false;
}

/// A tap on the tab button scrolls the tab's list back to the top.
///
/// The root scaffold owns one trigger per scrollable tab and calls
/// [request]; the tab itself attaches as a listener and scrolls. The other
/// way round would not work: the tabs live in an [IndexedStack] and stay
/// alive, and only the tab knows its ScrollController.
class ScrollToTopRequest extends ChangeNotifier {
  void request() => notifyListeners();
}

class RootScaffold extends StatefulWidget {
  const RootScaffold({super.key});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  int _index = 0;
  bool _settingsOpen = false;

  // Separate navigator for the settings: it sits in the scaffold's body, so
  // the tab bar below stays visible — also on the subpages (Connections,
  // Home, Beans, Backup) that stack here.
  final _settingsNavigator = GlobalKey<NavigatorState>();

  final _historyToTop = ScrollToTopRequest();
  final _beansToTop = ScrollToTopRequest();

  late final _tabs = [
    const LiveTab(),
    HistoryTab(scrollToTop: _historyToTop),
    BeansTab(scrollToTop: _beansToTop),
  ];

  @override
  void dispose() {
    _historyToTop.dispose();
    _beansToTop.dispose();
    super.dispose();
  }

  void _openSettings() => setState(() => _settingsOpen = true);

  void _openSettingsPage(WidgetBuilder page) {
    _openSettings();
    // The navigator only exists from the next frame on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settingsNavigator.currentState?.push(MaterialPageRoute(builder: page));
    });
  }

  void _closeSettings() {
    if (_settingsOpen) setState(() => _settingsOpen = false);
  }

  void _selectTab(int index) {
    // Switching tabs closes the settings, otherwise they would sit
    // invisibly over the new tab.
    _closeSettings();
    setState(() => _index = index);
    // The button always scrolls the list to the top — whether the tab was
    // already open or was just switched to.
    switch (index) {
      case 1:
        _historyToTop.request();
      case 2:
        _beansToTop.request();
    }
  }

  // Back gesture: first clear the settings subpages, then the settings
  // themselves, and only then leave the app.
  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;
    final navigator = _settingsNavigator.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
    } else {
      _closeSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RootNavigation(
      openSettings: _openSettings,
      openSettingsPage: _openSettingsPage,
      closeSettings: _closeSettings,
      child: PopScope(
        canPop: !_settingsOpen,
        onPopInvokedWithResult: _handleBack,
        child: Scaffold(
          // No AppBar any more — the settings gear sits inline at the top of
          // the Home tab (see live_tab.dart) and scrolls with the content
          // instead of staying put as a fixed overlay.
          body: Stack(
            children: [
              IndexedStack(index: _index, children: _tabs),
              if (_settingsOpen)
                // The back gesture rounds the page with the display's corner
                // radii. But this navigator ends above the tab bar at the
                // bottom, not at the display edge — if a card reaches the
                // bottom (AI settings), round corners flash there. So do not
                // round the bottom.
                Builder(
                  builder: (context) {
                    final media = MediaQuery.of(context);
                    final radii = media.displayCornerRadii;
                    return MediaQuery(
                      data: radii == null
                          ? media
                          : media.applyDisplayCornerRadii(
                              radii.copyWith(
                                bottomLeft: Radius.zero,
                                bottomRight: Radius.zero,
                              ),
                            ),
                      child: Navigator(
                        key: _settingsNavigator,
                        onGenerateRoute: (_) => MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          // Without this, tapping a tab flashes the Material ripple brightly
          // over the bar — in the dark bar it looks like a white flash.
          bottomNavigationBar: Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
            ),
            child: BottomNavigationBar(
              currentIndex: _index,
              onTap: _selectTab,
              type: BottomNavigationBarType.fixed,
              showSelectedLabels: false,
              showUnselectedLabels: false,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.coffee),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.history),
                  label: 'History',
                ),
                // The bean from the wordmark instead of a standard icon.
                BottomNavigationBarItem(icon: BeanIcon(), label: 'Beans'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
