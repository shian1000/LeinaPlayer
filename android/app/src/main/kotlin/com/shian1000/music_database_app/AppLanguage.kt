package com.shian1000.music_database_app

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * Ustawienia › Wygląd › Język for the native parts (the link sheet, notifications), which run
 * without Flutter: Dart saves the choice in `shared_preferences`, read here. "system" (or none)
 * leaves Android's own choice of `values-<locale>/strings.xml`, with Polish `values/` for a
 * language the app doesn't know — as `resolveSystemLocale` in `lib/src/l10n.dart` does.
 */
object AppLanguage {
    private const val KEY = "flutter.appearance.language"

    /** [context] showing the app's chosen language. */
    fun wrap(context: Context): Context {
        val tag = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString(KEY, null)
        if (tag == null || tag == "system") return context
        val config = Configuration(context.resources.configuration)
        config.setLocale(Locale.forLanguageTag(tag))
        return context.createConfigurationContext(config)
    }
}
