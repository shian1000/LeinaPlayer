package com.shian1000.music_database_app

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity (a FlutterActivity) lets the media notification/background service and
// the app share one Flutter engine.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // The engine outlives this activity while music plays in the background, and the queue
        // still needs NewPipe for the next song then — so the bridge lives with the engine and
        // is never torn down with the activity.
        if (newPipe?.messenger !== messenger) {
            newPipe?.dispose()
            newPipe = NewPipeBridge(messenger)
        }
        if (links?.messenger !== messenger) {
            links = LinksBridge(messenger, applicationContext)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A new activity on an engine that already runs Dart (music kept it alive) gets the
        // link pushed; on a cold start Dart asks for it once it's ready.
        if (savedInstanceState == null) links?.receive(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        links?.receive(intent)
    }

    companion object {
        private var newPipe: NewPipeBridge? = null
        private var links: LinksBridge? = null
    }
}

/**
 * YouTube links coming in ("Udostępnij" to this app, or a link opened with it) and going out to
 * the YouTube app, on the `music_database_app/links` channel (`lib/src/data/incoming_links.dart`).
 */
private class LinksBridge(val messenger: BinaryMessenger, private val context: Context) :
    MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "music_database_app/links")

    /** Received before Dart was listening; handed over by `initialLink`. */
    private var pending: String? = null

    init {
        channel.setMethodCallHandler(this)
    }

    fun receive(intent: Intent?) {
        val link = linkOf(intent) ?: return
        pending = link
        channel.invokeMethod("link", link, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (pending == link) pending = null
            }

            // Dart isn't listening yet: it takes the link from `pending` when it starts.
            override fun error(code: String, message: String?, details: Any?) {}
            override fun notImplemented() {}
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialLink" -> {
                result.success(pending)
                pending = null
            }
            "openYouTube" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("bad_args", "url missing", null)
                } else {
                    result.success(openYouTube(Uri.parse(url)))
                }
            }
            "openLinkSettings" -> result.success(openLinkSettings())
            else -> result.notImplemented()
        }
    }

    /** The system's "Open by default" screen for this app (Android 12+), else its app info. */
    private fun openLinkSettings(): Boolean {
        val uri = Uri.parse("package:${context.packageName}")
        val intents = listOfNotNull(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Intent(Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS, uri)
            } else {
                null
            },
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri),
        )
        for (intent in intents) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (e: ActivityNotFoundException) {
                // Some vendors leave the newer screen out.
            }
        }
        return false
    }

    /**
     * The YouTube app, else a browser — never through the system's choice for YouTube links,
     * which may be this app now (the last-resort fallback would open itself).
     */
    private fun openYouTube(uri: Uri): Boolean {
        val view = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(Intent(view).setPackage(YOUTUBE_PACKAGE))
            return true
        } catch (e: ActivityNotFoundException) {
            // Not installed: a browser instead.
        }
        val browser = browserPackage() ?: return false
        return try {
            context.startActivity(Intent(view).setPackage(browser))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun browserPackage(): String? {
        val probe = Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com"))
        val pm = context.packageManager
        val preferred = pm.resolveActivity(probe, PackageManager.MATCH_DEFAULT_ONLY)
            ?.activityInfo?.packageName
        // "android" is the chooser, shown when no browser is the default.
        if (preferred != null && preferred != "android" && preferred != context.packageName) {
            return preferred
        }
        return pm.queryIntentActivities(probe, 0)
            .map { it.activityInfo.packageName }
            .firstOrNull { it != context.packageName }
    }

    companion object {
        const val YOUTUBE_PACKAGE = "com.google.android.youtube"

        /** The shared text or the opened address; nothing for a launch from the app list. */
        fun linkOf(intent: Intent?): String? {
            if (intent == null) return null
            // Reopening the app from Recents redelivers the intent it was first started with.
            if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
            return when (intent.action) {
                Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
                Intent.ACTION_VIEW -> intent.dataString
                else -> null
            }
        }
    }
}
