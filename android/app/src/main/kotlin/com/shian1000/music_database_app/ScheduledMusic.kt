package com.shian1000.music_database_app

import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.Calendar
import kotlin.math.roundToInt

/**
 * "Zaplanowane uruchomienie" (several, like alarms) and "Zaplanowane wyłączenie" (Ja › Zaplanowana
 * muzyka): Android keeps the times, so the music starts with the app closed. Each time has a key
 * given by Dart: [STOP], "start" or "start_<id>". What plays is decided in Dart
 * (`lib/src/playback/scheduled_music.dart`), which runs once [MainActivity] has been brought up.
 */
object ScheduledMusic {
    const val START_ACTION = "com.shian1000.music_database_app.SCHEDULED_START"
    const val STOP_ACTION = "com.shian1000.music_database_app.SCHEDULED_STOP"
    const val STOP = "stop"
    const val EXTRA_KEY = "key"

    /** The keys of times kept in [PREFS]; "start" alone was the only start of older versions. */
    private val TIME_KEY = Regex("stop|start(_\\d+)?")

    private const val PREFS = "scheduled_music"
    private const val KEY_STARTED = "started_at"
    private const val KEY_STARTED_KEY = "started_key"
    private const val START_WITHIN_MS = 15 * 60 * 1000L
    private const val CHANNEL_ID = "com.shian1000.music_database_app.scheduled"
    private const val NOTIFICATION_ID = 7301
    private const val TAG = "ScheduledMusic"

    var bridge: ScheduledMusicBridge? = null

    /** The activity on screen last, to open Android's settings in its task. */
    var visibleActivity: WeakReference<Activity>? = null
    private var shownActivity: WeakReference<Activity>? = null

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun startIntent(context: Context) = Intent(context, MainActivity::class.java)
        .setAction(START_ACTION)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    private fun openApp(context: Context) = PendingIntent.getActivity(
        context,
        0,
        startIntent(context),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** Kept as older versions had them: "start" 0, [STOP] 1, so their alarms are the same ones. */
    private fun requestCode(key: String) = when (key) {
        "start" -> 0
        STOP -> 1
        else -> key.removePrefix("start_").toInt() + 1
    }

    private fun receiver(context: Context, key: String) = PendingIntent.getBroadcast(
        context,
        requestCode(key),
        Intent(context, ScheduledMusicReceiver::class.java)
            .setAction(if (key == STOP) STOP_ACTION else START_ACTION)
            .putExtra(EXTRA_KEY, key),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun daysKey(key: String) = "${key}_days"

    /** The weekdays [key] repeats on, as Dart's `DateTime.weekday`. */
    private fun days(context: Context, key: String): List<Int> =
        prefs(context).getString(daysKey(key), "")!!.split(",").mapNotNull { it.toIntOrNull() }

    private fun timeKeys(context: Context) = prefs(context).all.keys.filter { TIME_KEY.matches(it) }

    /** The first repeat of [at] still to come, by the calendar (clock changes keep the hour). */
    private fun nextAfter(at: Long, days: List<Int>): Long {
        val next = Calendar.getInstance().apply { timeInMillis = at }
        do {
            next.add(Calendar.DAY_OF_MONTH, 1)
            // Calendar counts from Sunday = 1, Dart from Monday = 1.
            val weekday = (next.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
        } while (next.timeInMillis <= System.currentTimeMillis() || weekday !in days)
        return next.timeInMillis
    }

    /** What comes after [key]'s time passed: its next day, or nothing. */
    private fun moveOn(context: Context, key: String) {
        val at = prefs(context).getLong(key, 0)
        val days = days(context, key)
        if (at != 0L && days.isNotEmpty()) {
            schedule(context, key, nextAfter(at, days), days)
        } else {
            prefs(context).edit().remove(key).remove(daysKey(key)).apply()
        }
    }

    /** Whether Android took it: the exact-alarm permission can be taken away on Android 12. */
    fun schedule(context: Context, key: String, at: Long, days: List<Int>): Boolean {
        val alarms = context.getSystemService(AlarmManager::class.java)
        return try {
            // setAlarmClock, unlike the other kinds, goes off on time in Doze.
            alarms.setAlarmClock(
                AlarmManager.AlarmClockInfo(at, openApp(context)),
                receiver(context, key),
            )
            prefs(context).edit()
                .putLong(key, at)
                .putString(daysKey(key), days.joinToString(","))
                .apply()
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "Scheduling refused: $e")
            false
        }
    }

    fun cancel(context: Context, key: String) {
        context.getSystemService(AlarmManager::class.java).cancel(receiver(context, key))
        prefs(context).edit().remove(key).remove(daysKey(key)).apply()
    }

    fun cancelAllBut(context: Context, keys: Collection<String>) {
        for (key in timeKeys(context)) if (key !in keys) cancel(context, key)
    }

    /** Android forgets these when the phone restarts and when the app is updated. */
    fun rearm(context: Context) {
        for (key in timeKeys(context)) {
            val at = prefs(context).getLong(key, 0)
            if (at == 0L) continue
            if (at > System.currentTimeMillis()) {
                schedule(context, key, at, days(context, key))
            } else {
                moveOn(context, key)
            }
        }
    }

    /** The key of the start that went off, if it did recently. */
    fun takeStarted(context: Context): String? {
        val startedAt = prefs(context).getLong(KEY_STARTED, 0)
        if (startedAt == 0L) return null
        val key = prefs(context).getString(KEY_STARTED_KEY, null) ?: "start"
        prefs(context).edit().remove(KEY_STARTED).remove(KEY_STARTED_KEY).apply()
        // Opened hours later (the app couldn't be brought up): music now would be a surprise.
        val recent = System.currentTimeMillis() - startedAt < START_WITHIN_MS
        if (!recent) finishStarting(context)
        return if (recent) key else null
    }

    fun fire(context: Context, key: String) {
        if (key == STOP) {
            moveOn(context, key)
            // No engine means no music playing, so nothing to stop.
            bridge?.fired(key)
            return
        }
        // commit: the process may be gone right after this receiver.
        prefs(context).edit()
            .putLong(KEY_STARTED, System.currentTimeMillis())
            .putString(KEY_STARTED_KEY, key)
            .commit()
        moveOn(context, key)
        bridge?.fired(key)
        // Android 10+ refuses activities started from the background, except through a
        // full-screen notification; the direct start covers older phones and an unlocked screen.
        showNotification(context)
        try {
            context.startActivity(startIntent(context))
        } catch (e: RuntimeException) {
            Log.w(TAG, "Starting the app directly failed: $e")
        }
    }

    private fun showNotification(appContext: Context) {
        val context = AppLanguage.wrap(appContext)
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.scheduled_music),
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply { setSound(null, null) },
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        manager.notify(
            NOTIFICATION_ID,
            builder
                .setSmallIcon(R.drawable.ic_stat_leina)
                .setContentTitle(context.getString(R.string.scheduled_music))
                .setContentText(context.getString(R.string.scheduled_music_tap))
                .setCategory(Notification.CATEGORY_ALARM)
                .setContentIntent(openApp(context))
                .setFullScreenIntent(openApp(context), true)
                .build(),
        )
    }

    /** Only while the music starts: Android 12+ lets a visible app start its media service. */
    fun showOverLockScreen(activity: Activity) {
        shownActivity = WeakReference(activity)
        setOverLockScreen(activity, true)
    }

    fun finishStarting(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        shownActivity?.get()?.let { setOverLockScreen(it, false) }
        shownActivity = null
    }

    private fun setOverLockScreen(activity: Activity, on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            activity.setShowWhenLocked(on)
            activity.setTurnScreenOn(on)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) activity.window.addFlags(flags) else activity.window.clearFlags(flags)
        }
    }
}

class ScheduledMusicReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                ScheduledMusic.rearm(context)
            ScheduledMusic.STOP_ACTION -> ScheduledMusic.fire(context, ScheduledMusic.STOP)
            // An alarm set by an older version carries no key: it was the only start.
            ScheduledMusic.START_ACTION -> ScheduledMusic.fire(
                context,
                intent.getStringExtra(ScheduledMusic.EXTRA_KEY) ?: "start",
            )
        }
    }
}

/** The `music_database_app/scheduled_music` channel. */
class ScheduledMusicBridge(val messenger: BinaryMessenger, private val context: Context) :
    MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "music_database_app/scheduled_music")

    init {
        channel.setMethodCallHandler(this)
    }

    fun fired(key: String) {
        channel.invokeMethod("fired", key)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "schedule" -> result.success(
                ScheduledMusic.schedule(
                    context,
                    call.argument<String>("key")!!,
                    call.argument<Number>("at")!!.toLong(),
                    call.argument<List<Int>>("days")!!,
                ),
            )
            "cancel" -> {
                ScheduledMusic.cancel(context, call.arguments as String)
                result.success(null)
            }
            "cancelAllBut" -> {
                @Suppress("UNCHECKED_CAST")
                ScheduledMusic.cancelAllBut(context, call.arguments as List<String>)
                result.success(null)
            }
            "takeStarted" -> result.success(ScheduledMusic.takeStarted(context))
            "canStartApp" -> result.success(canStartApp())
            "openStartAppSettings" -> result.success(openStartAppSettings())
            "setVolume" -> {
                setVolume(call.arguments as Int)
                result.success(null)
            }
            "finishStarting" -> {
                ScheduledMusic.finishStarting(context)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Whether the full-screen notification may bring the app up. Android 14+ grants it only to
     * alarm and calling apps by itself; denied, the notification just sits there (seen on the Pixel).
     */
    private fun canStartApp(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE ||
            context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()

    /** Whether Android's screen for allowing it could be opened. */
    private fun openStartAppSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return false
        val intent = Intent(
            Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
            Uri.parse("package:${context.packageName}"),
        )
        // From the activity, Back on that screen comes back to the app, not to Settings' own task.
        val activity = ScheduledMusic.visibleActivity?.get()
        return try {
            if (activity != null) {
                activity.startActivity(intent)
            } else {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            true
        } catch (e: RuntimeException) {
            Log.w("ScheduledMusic", "Opening the full-screen notification settings failed: $e")
            false
        }
    }

    private fun setVolume(percent: Int) {
        val audio = context.getSystemService(AudioManager::class.java)
        val stream = AudioManager.STREAM_MUSIC
        val volume = (audio.getStreamMaxVolume(stream) * percent / 100.0).roundToInt().coerceAtLeast(1)
        try {
            audio.setStreamVolume(stream, volume, 0)
        } catch (e: SecurityException) {
            // Do Not Disturb can refuse it.
            Log.w("ScheduledMusic", "Setting the volume failed: $e")
        }
    }
}
