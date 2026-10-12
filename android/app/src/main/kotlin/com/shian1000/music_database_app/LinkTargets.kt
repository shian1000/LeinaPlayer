package com.shian1000.music_database_app

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri

/** The services whose links this app takes over, and what a tapped link of each does. */
enum class LinkService(
    val key: String,
    val appPackage: String,
    /** "z YouTube", "ze Spotify". */
    val from: String,
) {
    YOUTUBE("youtube", "com.google.android.youtube", "z YouTube"),
    SPOTIFY("spotify", "com.spotify.music", "ze Spotify");

    companion object {
        fun of(uri: Uri): LinkService? {
            val host = uri.host?.lowercase() ?: return null
            return when {
                host == "youtu.be" || host == "youtube.com" || host.endsWith(".youtube.com") ->
                    YOUTUBE
                host == "open.spotify.com" || host == "spotify.link" ||
                    host == "spotify.app.link" -> SPOTIFY
                else -> null
            }
        }
    }
}

/** What a tapped link of a service does: ask (the chooser), or always the same. */
enum class LinkChoice(val key: String) {
    ASK("ask"), LEINA("leina"), APP("app"), BROWSER("browser");

    companion object {
        fun of(key: String?): LinkChoice = entries.firstOrNull { it.key == key } ?: ASK
    }
}

/**
 * Opening links outside this app, which may be the phone's choice for YouTube and Spotify
 * links now — so always a named package, never the system's choice (it would open this app
 * again).
 */
object LinkTargets {
    private const val PREFS = "link_chooser"

    /** The chooser's colours, from the Flutter theme (`setChooserLook`). */
    const val LOOK_KEY = "look"

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun choice(context: Context, service: LinkService): LinkChoice =
        LinkChoice.of(prefs(context).getString("choice_${service.key}", null))

    fun setChoice(context: Context, service: LinkService, choice: LinkChoice) {
        prefs(context).edit().putString("choice_${service.key}", choice.key).apply()
    }

    fun isInstalled(context: Context, packageName: String): Boolean = try {
        context.packageManager.getApplicationInfo(packageName, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    /** [uri] in the app [packageName], else (not installed) a browser. */
    fun openInApp(context: Context, uri: Uri, packageName: String): Boolean {
        try {
            context.startActivity(view(uri).setPackage(packageName))
            return true
        } catch (e: ActivityNotFoundException) {
            // Not installed: a browser instead.
        }
        return openInBrowser(context, uri)
    }

    fun openInBrowser(context: Context, uri: Uri): Boolean {
        val browser = browserPackage(context) ?: return false
        return try {
            context.startActivity(view(uri).setPackage(browser))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /** The phone's default browser, else any browser but this app. */
    fun browserPackage(context: Context): String? {
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

    private fun view(uri: Uri) =
        Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
}
