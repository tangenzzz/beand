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
    // Machine notifications (lib/services/machine_notifications.dart): a
    // little time after leaving the app, so the connection stays up and a
    // better estimate can still move "Should be ready" — or take it back.
    let center = NotificationCenter.default
    center.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.beginGrace() }
    center.addObserver(
      forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.endGrace() }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private var grace: UIBackgroundTaskIdentifier = .invalid

  private func beginGrace() {
    guard grace == .invalid else { return }
    grace = UIApplication.shared.beginBackgroundTask(withName: "beand.machine") { [weak self] in
      self?.endGrace()
    }
  }

  private func endGrace() {
    guard grace != .invalid else { return }
    UIApplication.shared.endBackgroundTask(grace)
    grace = .invalid
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Gear photo cutout (lib/services/gear_cutout.dart).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BeandCutout") {
      Cutout.register(messenger: registrar.messenger())
    }
    // After a restore (lib/services/app_restart.dart): iOS cannot start an
    // app again, so it only ends; the user opens it anew.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BeandApp") {
      FlutterMethodChannel(name: "beand/app", binaryMessenger: registrar.messenger())
        .setMethodCallHandler { call, result in
          guard call.method == "restart" else { return result(FlutterMethodNotImplemented) }
          result(nil)
          // Briefly, so settings are fully written.
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
        }
    }
  }
}
