package app.beand

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity instead of FlutterActivity: local_auth (fingerprint/
// PIN before showing the sync key) needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        LiveStatus.onIntent(intent, atLaunch = true)
    }

    // A notification button while the app is running (singleTop).
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        LiveStatus.onIntent(intent, atLaunch = false)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        LiveStatus.unregister()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Machine status notification as a Live Update (LiveStatus.kt).
        LiveStatus.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        // Screens showing the sync key (QR, plain text): no screenshots, no
        // screen recording, blank preview in the app switcher
        // (lib/sync/secure_screen.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "beand/secure_screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        // Gear photo cutout (lib/services/gear_cutout.dart).
        Cutout.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        // After a restore: really end the process and start fresh
        // (lib/services/app_restart.dart). SystemNavigator.pop() only closes
        // the window; Dart services with the old DB connection would live on.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "beand/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "restart" -> {
                        result.success(null)
                        val launch = packageManager.getLaunchIntentForPackage(packageName)
                        val component = launch?.component
                        // Wait briefly so settings are fully written.
                        Handler(Looper.getMainLooper()).postDelayed({
                            if (component != null) {
                                startActivity(Intent.makeRestartActivityTask(component))
                            }
                            finishAffinity()
                            Runtime.getRuntime().exit(0)
                        }, 400)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
