import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

// Protection for screens showing the sync key (QR, plain text): Android
// FLAG_SECURE via the channel in MainActivity.kt — no screenshots, no
// recording, empty preview in the app switcher. In addition, for iOS (which
// has no FLAG_SECURE) and as a second safeguard: as soon as the app is no
// longer in the foreground, a cover hides the content before the system
// takes its preview snapshot.
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});

  final Widget child;

  static const _channel = MethodChannel('beand/secure_screen');

  // Several protected pages stacked (QR → plain text): protection is only
  // lifted once the last one is closed.
  static int _open = 0;

  static Future<void> _apply() async {
    try {
      await _channel.invokeMethod<void>('setSecure', _open > 0);
    } catch (_) {
      // iOS, tests: no channel — the cover below is enough there.
    }
  }

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    SecureScreen._open++;
    SecureScreen._apply();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        final covered = state != AppLifecycleState.resumed;
        if (covered != _covered && mounted) setState(() => _covered = covered);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    SecureScreen._open--;
    SecureScreen._apply();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_covered)
          Positioned.fill(child: ColoredBox(color: context.colors.bg)),
      ],
    );
  }
}
