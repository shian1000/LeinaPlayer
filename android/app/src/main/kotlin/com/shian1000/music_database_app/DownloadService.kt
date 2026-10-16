package com.shian1000.music_database_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * "Pobieranie utworów": a foreground service (type dataSync) that only shows a notification while
 * the Dart side (`lib/src/playback/downloads.dart`) downloads songs. Its being there is the
 * point — a process with a foreground service isn't frozen by Android 12+'s cached-app freezer
 * nor first to be killed, so the downloads go on with the screen off. The work itself stays in
 * Dart.
 */
class DownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = notification(
            this,
            intent?.getIntExtra(EXTRA_DONE, 0) ?: 0,
            intent?.getIntExtra(EXTRA_TOTAL, 0) ?: 0,
            intent?.getStringExtra(EXTRA_TITLE) ?: "",
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, notification)
        }
        running = true
        // Killed meanwhile, it isn't restarted: Dart resumes the queue when the app comes back.
        return START_NOT_STICKY
    }

    // Android 15 limits dataSync services to 6 hours a day; past that the system asks to stop.
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "downloads"
        private const val ID = 4201
        private const val EXTRA_DONE = "done"
        private const val EXTRA_TOTAL = "total"
        private const val EXTRA_TITLE = "title"

        /** Started: progress then only updates its notification — starting it again from the
         *  background may be refused on Android 12+. */
        @Volatile private var running = false

        private fun notification(context: Context, done: Int, total: Int, title: String): Notification {
            val manager = context.getSystemService(NotificationManager::class.java)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (manager.getNotificationChannel(CHANNEL) == null) {
                    manager.createNotificationChannel(
                        NotificationChannel(CHANNEL, "Pobieranie utworów", NotificationManager.IMPORTANCE_LOW),
                    )
                }
                Notification.Builder(context, CHANNEL)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
            return builder
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle("Pobieranie utworów: ${done + 1} z $total")
                .setContentText(title)
                .setProgress(total, done, false)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .apply {
                    if (open != null) {
                        setContentIntent(
                            PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE),
                        )
                    }
                }
                .build()
        }

        fun show(context: Context, done: Int, total: Int, title: String) {
            if (running) {
                context.getSystemService(NotificationManager::class.java)
                    .notify(ID, notification(context, done, total, title))
                return
            }
            val intent = Intent(context, DownloadService::class.java)
                .putExtra(EXTRA_DONE, done)
                .putExtra(EXTRA_TOTAL, total)
                .putExtra(EXTRA_TITLE, title)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // Android 12+ refuses to start one from the background (e.g. the queue resumed
                // while the app wasn't visible): the downloads go on without it.
                Log.w("DownloadService", "Not started: $e")
            }
        }

        fun hide(context: Context) {
            context.stopService(Intent(context, DownloadService::class.java))
        }
    }
}

/** `music_database_app/downloads`: Dart's `DownloadNotification`. */
class DownloadBridge(val messenger: BinaryMessenger, private val context: Context) :
    MethodChannel.MethodCallHandler {
    init {
        MethodChannel(messenger, "music_database_app/downloads").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "show" -> {
                DownloadService.show(
                    context,
                    call.argument<Int>("done") ?: 0,
                    call.argument<Int>("total") ?: 0,
                    call.argument<String>("title") ?: "",
                )
                result.success(null)
            }
            "hide" -> {
                DownloadService.hide(context)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
