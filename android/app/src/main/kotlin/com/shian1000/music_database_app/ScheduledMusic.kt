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
import android.os.Build
import android.util.Log
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.Calendar
import kotlin.math.roundToInt

/**
 * "Zaplanowane uruchomienie muzyki" and "Zaplanowane wyłączenie" (Ja): Android keeps the times, so
 * the music starts with the app closed. What plays is decided in Dart
 * (`lib/src/playback/scheduled_music.dart`), which runs once [MainActivity] has been brought up.
 */
object ScheduledMusic {
    enum class Kind(val key: String, val action: String, val requestCode: Int) {
        START("start", "com.shian1000.music_database_app.SCHEDULED_START", 0),
        STOP("stop", "com.shian1000.music_database_app.SCHEDULED_STOP", 1);

        companion object {
            fun of(key: String?) = entries.first { it.key == key }
        }
    }

    private const val PREFS = "scheduled_music"
    private const val KEY_STARTED = "started_at"
    private const val START_WITHIN_MS = 15 * 60 * 1000L
    private const val CHANNEL_ID = "com.shian1000.music_database_app.scheduled"
    private const val NOTIFICATION_ID = 7301
    private const val TAG = "ScheduledMusic"

    var bridge: ScheduledMusicBridge? = null
    private var shownActivity: WeakReference<Activity>? = null

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun startIntent(context: Context) = Intent(context, MainActivity::class.java)
        .setAction(Kind.START.action)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    private fun openApp(context: Context) = PendingIntent.getActivity(
        context,
        0,
        startIntent(context),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun receiver(context: Context, kind: Kind) = PendingIntent.getBroadcast(
        context,
        kind.requestCode,
        Intent(context, ScheduledMusicReceiver::class.java).setAction(kind.action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun daysKey(kind: Kind) = "${kind.key}_days"

    /** The weekdays [kind] repeats on, as Dart's `DateTime.weekday`. */
    private fun days(context: Context, kind: Kind): List<Int> =
        prefs(context).getString(daysKey(kind), "")!!.split(",").mapNotNull { it.toIntOrNull() }

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

    /** What comes after [kind]'s time passed: its next day, or nothing. */
    private fun moveOn(context: Context, kind: Kind) {
        val at = prefs(context).getLong(kind.key, 0)
        val days = days(context, kind)
        if (at != 0L && days.isNotEmpty()) {
            schedule(context, kind, nextAfter(at, days), days)
        } else {
            prefs(context).edit().remove(kind.key).apply()
        }
    }

    /** Whether Android took it: the exact-alarm permission can be taken away on Android 12. */
    fun schedule(context: Context, kind: Kind, at: Long, days: List<Int>): Boolean {
        val alarms = context.getSystemService(AlarmManager::class.java)
        return try {
            // setAlarmClock, unlike the other kinds, goes off on time in Doze.
            alarms.setAlarmClock(
                AlarmManager.AlarmClockInfo(at, openApp(context)),
                receiver(context, kind),
            )
            prefs(context).edit()
                .putLong(kind.key, at)
                .putString(daysKey(kind), days.joinToString(","))
                .apply()
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "Scheduling refused: $e")
            false
        }
    }

    fun cancel(context: Context, kind: Kind) {
        context.getSystemService(AlarmManager::class.java).cancel(receiver(context, kind))
        prefs(context).edit().remove(kind.key).apply()
    }

    /** Android forgets these when the phone restarts and when the app is updated. */
    fun rearm(context: Context) {
        for (kind in Kind.entries) {
            val at = prefs(context).getLong(kind.key, 0)
            if (at == 0L) continue
            if (at > System.currentTimeMillis()) {
                schedule(context, kind, at, days(context, kind))
            } else {
                moveOn(context, kind)
            }
        }
    }

    fun takeStarted(context: Context): Boolean {
        val startedAt = prefs(context).getLong(KEY_STARTED, 0)
        if (startedAt == 0L) return false
        prefs(context).edit().remove(KEY_STARTED).apply()
        // Opened hours later (the app couldn't be brought up): music now would be a surprise.
        val recent = System.currentTimeMillis() - startedAt < START_WITHIN_MS
        if (!recent) finishStarting(context)
        return recent
    }

    fun fire(context: Context, kind: Kind) {
        if (kind == Kind.STOP) {
            moveOn(context, kind)
            // No engine means no music playing, so nothing to stop.
            bridge?.fired(kind)
            return
        }
        // commit: the process may be gone right after this receiver.
        prefs(context).edit()
            .putLong(KEY_STARTED, System.currentTimeMillis())
            .commit()
        moveOn(context, kind)
        bridge?.fired(kind)
        // Android 10+ refuses activities started from the background, except through a
        // full-screen notification; the direct start covers older phones and an unlocked screen.
        showNotification(context)
        try {
            context.startActivity(startIntent(context))
        } catch (e: RuntimeException) {
            Log.w(TAG, "Starting the app directly failed: $e")
        }
    }

    private fun showNotification(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Zaplanowana muzyka",
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
                .setContentTitle("Zaplanowana muzyka")
                .setContentText("Dotknij, aby otworzyć Leina Player")
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
            else -> ScheduledMusic.Kind.entries
                .firstOrNull { it.action == intent.action }
                ?.let { ScheduledMusic.fire(context, it) }
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

    fun fired(kind: ScheduledMusic.Kind) {
        channel.invokeMethod("fired", kind.key)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "schedule" -> result.success(
                ScheduledMusic.schedule(
                    context,
                    ScheduledMusic.Kind.of(call.argument<String>("kind")),
                    call.argument<Number>("at")!!.toLong(),
                    call.argument<List<Int>>("days")!!,
                ),
            )
            "cancel" -> {
                ScheduledMusic.cancel(context, ScheduledMusic.Kind.of(call.arguments as String))
                result.success(null)
            }
            "takeStarted" -> result.success(ScheduledMusic.takeStarted(context))
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
