package app.beand

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// The machine notifications (lib/services/machine_notifications.dart).
//
// Status: an Android "Live Update" — from Android 16 on it may sit as a small
// chip in the status bar (a countdown while heating, ticking by itself; a
// word when ready; the seconds while brewing) and at the top of the lock
// screen. On older Android the same notification, without the chip.
// flutter_local_notifications starts the foreground service with this
// notification's id; posting here under the same id replaces its content
// and keeps it the service's notification. The plugin has no API for the
// promoted parts (setRequestPromotedOngoing, setShortCriticalText) yet.
//
// Alerts (reached, stable, shot done, connection lost) go out here too, so
// their buttons work the same way as the status one's.
//
// Buttons (Start shot, Stop, Purge) act directly: the tap goes to
// [ActionReceiver] and from there to the running app — the foreground
// service keeps it alive — without opening it. Only if the app is not
// running any more does the tap open it and act there.
object LiveStatus {
    private const val STATUS_CHANNEL = "beand_status"
    private const val ALERT_CHANNEL = "beand_alerts"
    private const val STATUS_ID = 7
    const val EXTRA_ACTION = "beand_action"
    const val EXTRA_NOTIFICATION = "beand_notification"

    private var channel: MethodChannel? = null
    private var pendingAction: String? = null
    private val main = Handler(Looper.getMainLooper())

    fun register(context: Context, messenger: BinaryMessenger) {
        val ch = MethodChannel(messenger, "beand/live_status")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    show(
                        context,
                        title = call.argument<String>("title") ?: "",
                        body = call.argument<String>("body") ?: "",
                        progress = call.argument<Int>("progress"),
                        countdownTo = call.argument<Number>("countdownTo")?.toLong(),
                        countUpFrom = call.argument<Number>("countUpFrom")?.toLong(),
                        chip = call.argument<String>("chip"),
                        actionId = call.argument<String>("actionId"),
                        actionLabel = call.argument<String>("actionLabel"),
                    )
                    result.success(true)
                }
                "alert" -> {
                    alert(
                        context,
                        id = call.argument<Int>("id") ?: 10,
                        title = call.argument<String>("title") ?: "",
                        body = call.argument<String>("body") ?: "",
                        actionId = call.argument<String>("actionId"),
                        actionLabel = call.argument<String>("actionLabel"),
                    )
                    result.success(true)
                }
                // A button tapped while the app was not running: handed over
                // once the Dart side is up.
                "takeAction" -> {
                    result.success(pendingAction)
                    pendingAction = null
                }
                else -> result.notImplemented()
            }
        }
    }

    /// The engine is going away (activity destroyed): no direct path then.
    fun unregister() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    // From MainActivity: the app was opened by a button (fallback path). At
    // launch the Dart side is not listening yet — it fetches the action with
    // "takeAction" then.
    fun onIntent(intent: Intent?, atLaunch: Boolean) {
        val action = intent?.getStringExtra(EXTRA_ACTION) ?: return
        intent.removeExtra(EXTRA_ACTION)
        val ch = channel
        if (atLaunch || ch == null) {
            pendingAction = action
        } else {
            ch.invokeMethod("action", action)
        }
    }

    // From ActionReceiver: straight to the running app, or open it.
    fun dispatch(context: Context, action: String, notification: Int) {
        if (notification != STATUS_ID) {
            context.getSystemService(NotificationManager::class.java).cancel(notification)
        }
        val ch = channel
        if (ch != null) {
            main.post { ch.invokeMethod("action", action) }
        } else {
            val intent = launchIntent(context).putExtra(EXTRA_ACTION, action)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
    }

    private fun launchIntent(context: Context): Intent =
        context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)

    private fun openApp(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        launchIntent(context),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun button(
        context: Context,
        notification: Int,
        actionId: String?,
        actionLabel: String?,
    ): Notification.Action? {
        if (actionId == null || actionLabel == null) return null
        val intent = Intent(context, ActionReceiver::class.java)
            .putExtra(EXTRA_ACTION, actionId)
            .putExtra(EXTRA_NOTIFICATION, notification)
        val pending = PendingIntent.getBroadcast(
            context,
            notification * 31 + actionId.hashCode().and(0xffff),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(null, actionLabel, pending).build()
    }

    private fun show(
        context: Context,
        title: String,
        body: String,
        progress: Int?,
        countdownTo: Long?,
        countUpFrom: Long?,
        chip: String?,
        actionId: String?,
        actionLabel: String?,
    ) {
        val builder = Notification.Builder(context, STATUS_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_beand)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setContentIntent(openApp(context))
        if (progress != null) builder.setProgress(100, progress, false)

        // A running clock: down to "ready" while heating, up while brewing.
        // Android ticks it by itself, also when the app is asleep.
        val clockAt = countdownTo ?: countUpFrom
        if (clockAt != null) {
            builder.setWhen(clockAt).setShowWhen(true).setUsesChronometer(true)
            if (countdownTo != null) builder.setChronometerCountDown(true)
        } else {
            builder.setShowWhen(false)
        }
        button(context, STATUS_ID, actionId, actionLabel)?.let { builder.addAction(it) }

        if (Build.VERSION.SDK_INT >= 36) {
            builder.setRequestPromotedOngoing(true)
            // Without a clock the chip shows this short word instead.
            if (chip != null && clockAt == null) builder.setShortCriticalText(chip)
        }
        context.getSystemService(NotificationManager::class.java)
            .notify(STATUS_ID, builder.build())
    }

    private fun alert(
        context: Context,
        id: Int,
        title: String,
        body: String,
        actionId: String?,
        actionLabel: String?,
    ) {
        val builder = Notification.Builder(context, ALERT_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_beand)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setContentIntent(openApp(context))
        button(context, id, actionId, actionLabel)?.let { builder.addAction(it) }
        context.getSystemService(NotificationManager::class.java).notify(id, builder.build())
    }
}

// Receives notification button taps (see LiveStatus.dispatch).
class ActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.getStringExtra(LiveStatus.EXTRA_ACTION) ?: return
        val notification = intent.getIntExtra(LiveStatus.EXTRA_NOTIFICATION, -1)
        LiveStatus.dispatch(context, action, notification)
    }
}
