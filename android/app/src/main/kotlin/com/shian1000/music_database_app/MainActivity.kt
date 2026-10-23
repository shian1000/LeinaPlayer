package com.shian1000.music_database_app

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
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
        if (downloads?.messenger !== messenger) {
            downloads = DownloadBridge(messenger, applicationContext)
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
        private var downloads: DownloadBridge? = null
    }
}

/**
 * YouTube and Spotify links coming in ("Udostępnij" to this app, or a link opened with it —
 * through [LinkChooserActivity]) and going out to the YouTube or Spotify app, plus the chooser's
 * settings and the links it saved for later ([LaterLinks]), on the `music_database_app/links`
 * channel (`lib/src/data/incoming_links.dart`, `lib/src/data/later_links.dart`).
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
            "openYouTube", "openSpotify" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("bad_args", "url missing", null)
                } else {
                    val service =
                        if (call.method == "openYouTube") LinkService.YOUTUBE else LinkService.SPOTIFY
                    result.success(
                        LinkTargets.openInApp(context, Uri.parse(url), service.appPackage),
                    )
                }
            }
            "openLinkSettings" -> result.success(openLinkSettings())
            "linkChoices" -> result.success(
                LinkService.entries.associate { it.key to LinkTargets.choice(context, it).key },
            )
            "setLinkChoice" -> {
                val service = LinkService.entries
                    .firstOrNull { it.key == call.argument<String>("service") }
                if (service == null) {
                    result.error("bad_args", "unknown service", null)
                } else {
                    LinkTargets.setChoice(
                        context,
                        service,
                        LinkChoice.of(call.argument<String>("choice")),
                    )
                    result.success(null)
                }
            }
            "setChooserLook" -> {
                LinkTargets.prefs(context).edit()
                    .putString(LinkTargets.LOOK_KEY, call.arguments as String?)
                    .apply()
                result.success(null)
            }
            // For "Zgłoś problem": which phone and Android a report comes from.
            "deviceInfo" -> result.success(
                mapOf(
                    "manufacturer" to android.os.Build.MANUFACTURER,
                    "model" to android.os.Build.MODEL,
                    "release" to android.os.Build.VERSION.RELEASE,
                    "sdk" to android.os.Build.VERSION.SDK_INT,
                ),
            )
            "laterLinks" -> result.success(LaterLinks.all(context))
            "replaceLaterLinks" -> {
                LaterLinks.replaceAll(context, call.arguments as String)
                result.success(null)
            }
            "addLaterPerson" -> result.success(
                LaterLinks.addPerson(context, call.argument<String>("name")!!),
            )
            "renameLaterPerson" -> {
                LaterLinks.renamePerson(
                    context,
                    call.argument<String>("id")!!,
                    call.argument<String>("name")!!,
                )
                result.success(null)
            }
            "removeLaterPerson" -> {
                LaterLinks.removePerson(context, call.argument<String>("id")!!)
                result.success(null)
            }
            "updateLaterLink" -> {
                LaterLinks.updateLink(
                    context,
                    call.argument<String>("id")!!,
                    call.argument<Map<String, Any?>>("fields")!!,
                )
                result.success(null)
            }
            "removeLaterLink" -> {
                LaterLinks.removeLink(context, call.argument<String>("id")!!)
                result.success(null)
            }
            "putLaterLink" -> {
                LaterLinks.putLink(context, call.argument<Map<String, Any?>>("link")!!)
                result.success(null)
            }
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

    companion object {
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
