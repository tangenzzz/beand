import 'package:flutter/services.dart';

/// Restarts the app (process ends, fresh start). Outside Android it falls
/// back to simply closing — then the user reopens it.
Future<void> restartApp() async {
  try {
    await const MethodChannel('beand/app').invokeMethod<void>('restart');
  } on MissingPluginException {
    await SystemNavigator.pop();
  } on PlatformException {
    await SystemNavigator.pop();
  }
}
