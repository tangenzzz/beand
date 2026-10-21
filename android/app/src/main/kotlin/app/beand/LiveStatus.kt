package app.beand

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

// The machine status notification (lib/services/machine_notifications.dart)
// as an Android "Live Update": from Android 16 on it may sit as a small chip
// in the status bar — a countdown while heating ("3:38", ticking by itself),
// a word when ready ("Ready"), the seconds while brewing — and at the top
// of the lock screen. On older Android the same notification, without the
// chip.
//
// flutter_local_notifications starts the foreground service with this
// notification's id; posting here under the same id replaces its content
// and keeps it the service's notification. The plugin has no API for the
// promoted parts (setRequestPromotedOngoing, setShortCriticalText) yet.
object LiveStatus {
    private const val CHANNEL_ID = "beand_status"
    private const val NOTIFICATION_ID = 7
    const val EXTRA_ACTION = "beand_action"

    private var channel: MethodChannel? = null
    private var pendingAction: String? = null

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
                // A button tapped while the app was closed: handed over once
                // the Dart side is up.
                "takeAction" -> {
                    result.success(pendingAction)
                    pendingAction = null
                }
                else -> result.notImplemented()
            }
        }
    }

    // From MainActivity: a notification button. At launch the Dart side is
    // not listening yet — it fetches the action with "takeAction" then.
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

    private fun openApp(context: Context, action: String?, request: Int): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (action != null) intent.putExtra(EXTRA_ACTION, action)
        return PendingIntent.getActivity(
            context,
            request,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
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
        val builder = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_beand)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setContentIntent(openApp(context, null, 0))
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

        if (actionId != null && actionLabel != null) {
            builder.addAction(
                Notification.Action.Builder(
                    null,
                    actionLabel,
                    openApp(context, actionId, 1 + actionId.hashCode().and(0xffff)),
                ).build(),
            )
        }

        if (Build.VERSION.SDK_INT >= 36) {
            builder.setRequestPromotedOngoing(true)
            // Without a clock the chip shows this short word instead.
            if (chip != null && clockAt == null) builder.setShortCriticalText(chip)
        }

        val manager = context.getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, builder.build())
    }
}
