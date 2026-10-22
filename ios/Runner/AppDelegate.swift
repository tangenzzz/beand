import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Machine alerts (flutter_local_notifications) also show while the app
    // is in front.
    UNUserNotificationCenter.current().delegate = self
    // Auto backup (lib/services/auto_backup.dart): the background run gets
    // an engine of its own, which needs the plugins too.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerBGProcessingTask(withIdentifier: "app.beand.autoBackup")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Gear photo cutout (lib/services/gear_cutout.dart).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BeandCutout") {
      Cutout.register(messenger: registrar.messenger())
    }
  }
}
