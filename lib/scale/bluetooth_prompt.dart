import 'package:flutter/material.dart';

import 'brew_scale.dart';

/// Before anything that needs Bluetooth: if it is off, the system's dialog
/// on Android; iOS doesn't let an app switch it on, so a reminder there.
/// Returns whether Bluetooth is on.
Future<bool> ensureBluetoothOn(BuildContext context, BrewScale scale) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ios = Theme.of(context).platform == TargetPlatform.iOS;
  if (!await scale.bluetoothOff) return true;
  var on = false;
  try {
    on = await scale.requestBluetoothOn();
  } catch (e) {
    debugPrint('Bluetooth prompt failed: $e');
  }
  if (!on) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          ios
              ? 'Bluetooth is off. Turn it on in Control Center.'
              : 'Bluetooth is off.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }
  return on;
}
