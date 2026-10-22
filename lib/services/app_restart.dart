import 'dart:io';

import 'package:flutter/services.dart';

/// False where the app only closes and has to be opened by hand (iOS).
bool get restartReopensItself => !Platform.isIOS;

/// Restarts the app (process ends, fresh start). iOS can only end it —
/// the user then opens it again ([restartReopensItself]).
Future<void> restartApp() async {
  try {
    await const MethodChannel('beand/app').invokeMethod<void>('restart');
  } on MissingPluginException {
    await SystemNavigator.pop();
  } on PlatformException {
    await SystemNavigator.pop();
  }
}
