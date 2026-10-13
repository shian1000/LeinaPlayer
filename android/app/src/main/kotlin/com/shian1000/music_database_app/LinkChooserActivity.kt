package com.shian1000.music_database_app

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.app.Activity
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.CheckBox
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject

/**
 * A tapped YouTube or Spotify link: a sheet over half the screen asks whether to open it in
 * Leina Radio, the service's own app or a browser — unless a choice was remembered
 * (Ustawienia › Otwieranie linków) — or to save it for later with the person who sent it
 * ([LaterLinks], shown in Menu profilu › Wiadomości › Na później). Native and translucent, so it shows at once over the app
 * the link was tapped in, without starting Flutter. Links shared to the app ("Udostępnij") go
 * straight to [MainActivity]: sharing to it is the choice already.
 */
class LinkChooserActivity : Activity() {
    private lateinit var uri: Uri
    private lateinit var service: LinkService
    private lateinit var root: FrameLayout
    private lateinit var sheet: LinearLayout

    /** What the sheet shows under its handle: the choices, or "Od kogo?". */
    private lateinit var content: LinearLayout
    private lateinit var look: Look
    private lateinit var face: Typeface
    private var choosingPerson = false
    private var closing = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val data = intent?.data
        val linkService = data?.let { LinkService.of(it) }
        if (data == null || linkService == null) {
            finish()
            return
        }
        uri = data
        service = linkService
        val remembered = LinkTargets.choice(this, service)
        if (remembered != LinkChoice.ASK) {
            // Leina Radio can't do anything with a channel page and the like.
            open(if (remembered == LinkChoice.LEINA && !kind().supported) LinkChoice.APP else remembered)
            finish()
            return
        }
        buildSheet()
    }

    @Deprecated("Still called with the old back handling this app uses.")
    override fun onBackPressed() = if (choosingPerson) showChoices() else close()

    /** What the link points at, as far as the address tells. */
    private data class Kind(val label: String, val leinaAction: String, val supported: Boolean)

    private fun kind(): Kind {
        val segments = uri.pathSegments.filter { it.isNotEmpty() }
        val first = segments.firstOrNull()
        return when (service) {
            LinkService.YOUTUBE -> when {
                first == "playlist" && uri.getQueryParameter("list") != null ->
                    Kind("Playlista z YouTube", "Zaimportuj do Biblioteki", true)
                uri.host == "youtu.be" && first != null ||
                    first == "watch" && uri.getQueryParameter("v") != null ||
                    first in setOf("shorts", "live", "embed") && segments.size > 1 ->
                    Kind("Film z YouTube", "Odtwórz", true)
                else -> Kind("Link z YouTube", "Otwiera tylko filmy i playlisty", false)
            }
            LinkService.SPOTIFY -> {
                val type = segments.dropWhile { it.startsWith("intl-") || it == "embed" }
                    .firstOrNull()
                when {
                    uri.host != "open.spotify.com" ->
                        Kind("Link ze Spotify", "Odtwórz albo zaimportuj", true)
                    type == "track" -> Kind("Utwór ze Spotify", "Odtwórz", true)
                    type == "album" -> Kind("Album ze Spotify", "Zaimportuj do Biblioteki", true)
                    type == "playlist" ->
                        Kind("Playlista ze Spotify", "Zaimportuj do Biblioteki", true)
                    else -> Kind(
                        "Link ze Spotify",
                        "Otwiera tylko utwory, albumy i playlisty",
                        false,
                    )
                }
            }
        }
    }

    private fun open(choice: LinkChoice): Boolean = when (choice) {
        LinkChoice.ASK, LinkChoice.LEINA -> try {
            startActivity(
                Intent(Intent.ACTION_VIEW, uri, this, MainActivity::class.java).addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                ),
            )
            true
        } catch (e: Exception) {
            false
        }
        LinkChoice.APP -> LinkTargets.openInApp(this, uri, service.appPackage)
        LinkChoice.BROWSER -> LinkTargets.openInBrowser(this, uri)
    }

    // --- The sheet ---

    private data class Look(
        val sheet: Int,
        val pressed: Int,
        val text: Int,
        val textSecondary: Int,
        val accent: Int,
        val divider: Int,
        val monospace: Boolean,
    )

    /** The app's current theme (sent by Flutter), else plain dark or light. */
    private fun look(): Look {
        val night = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
        try {
            val json = LinkTargets.prefs(this).getString(LinkTargets.LOOK_KEY, null)
            if (json != null) {
                val all = JSONObject(json)
                val dark = when (all.optString("mode")) {
                    "dark" -> true
                    "light" -> false
                    else -> night
                }
                val theme = all.getJSONObject(if (dark) "dark" else "light")
                fun color(name: String) = theme.getLong(name).toInt()
                return Look(
                    sheet = color("surface"),
                    pressed = color("surfaceHigh"),
                    text = color("textPrimary"),
                    textSecondary = color("textSecondary"),
                    accent = color("accent"),
                    divider = color("divider"),
                    monospace = theme.optString("fontFamily") == "monospace",
                )
            }
        } catch (e: Exception) {
            // Never saved yet, or from an older version: the plain look.
        }
        return if (night) {
            Look(0xFF1F1F1F.toInt(), 0xFF2A2A2A.toInt(), Color.WHITE, 0xFFB3B3B3.toInt(),
                0xFF1ED760.toInt(), 0xFF333333.toInt(), false)
        } else {
            Look(Color.WHITE, 0xFFEDEDED.toInt(), 0xFF121212.toInt(), 0xFF6A6A6A.toInt(),
                0xFF1DB954.toInt(), 0xFFE0E0E0.toInt(), false)
        }
    }

    private fun dp(value: Int) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics,
    ).toInt()


    private fun text(value: String, size: Float, color: Int, bold: Boolean = false) =
        TextView(this).apply {
            text = value
            setTextSize(TypedValue.COMPLEX_UNIT_SP, size)
            setTextColor(color)
            typeface = Typeface.create(face, if (bold) Typeface.BOLD else Typeface.NORMAL)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }

    private fun pressable(view: View) {
        view.background = RippleDrawable(
            ColorStateList.valueOf(look.pressed), null, ColorDrawable(Color.WHITE),
        )
        view.isClickable = true
    }

    /** A sheet row: [icon] (44 dp), a title and a subtitle. */
    private fun row(icon: View, title: String, subtitle: String?, onClick: () -> Unit): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(24), dp(10), dp(24), dp(10))
            minimumHeight = dp(68)
            pressable(this)
            setOnClickListener { onClick() }
        }
        row.addView(icon, LinearLayout.LayoutParams(dp(44), dp(44)).apply { marginEnd = dp(18) })
        row.addView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                addView(text(title, 17f, look.text, bold = true))
                if (subtitle != null) addView(text(subtitle, 13f, look.textSecondary))
            },
            LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f),
        )
        return row
    }

    private fun appIcon(drawable: Drawable?) = ImageView(this).apply { setImageDrawable(drawable) }

    /** A round icon like an avatar: [glyph] (a letter) or [iconRes] on the chip colour. */
    private fun roundIcon(glyph: String? = null, iconRes: Int? = null): View {
        val circle = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(look.pressed)
        }
        return if (iconRes != null) {
            ImageView(this).apply {
                background = circle
                setImageResource(iconRes)
                imageTintList = ColorStateList.valueOf(look.text)
                setPadding(dp(10), dp(10), dp(10), dp(10))
            }
        } else {
            text(glyph ?: "", 18f, look.text, bold = true).apply {
                background = circle
                gravity = Gravity.CENTER
            }
        }
    }

    private fun divider() = View(this).apply { setBackgroundColor(look.divider) }

    private fun dividerParams() = LinearLayout.LayoutParams(MATCH_PARENT, dp(1)).apply {
        topMargin = dp(8)
        marginStart = dp(24)
        marginEnd = dp(24)
    }

    private fun header(title: String, kind: Kind) = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(24), 0, dp(24), dp(12))
        addView(text(title, 22f, look.text, bold = true))
        addView(text(kind.label, 15f, look.text).apply { setPadding(0, dp(6), 0, 0) })
        addView(
            text(uri.toString(), 13f, look.textSecondary).apply {
                ellipsize = TextUtils.TruncateAt.MIDDLE
            },
        )
    }

    private fun buildSheet() {
        look = look()
        face = if (look.monospace) Typeface.MONOSPACE else Typeface.DEFAULT

        root = FrameLayout(this).apply {
            setBackgroundColor(0x99000000.toInt())
            alpha = 0f
            setOnClickListener { close() }
        }
        sheet = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            isClickable = true
            minimumHeight = resources.displayMetrics.heightPixels / 2
            background = GradientDrawable().apply {
                setColor(look.sheet)
                val r = dp(28).toFloat()
                cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
            }
        }
        root.addView(sheet, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.BOTTOM))

        sheet.addView(
            View(this).apply {
                background = GradientDrawable().apply {
                    setColor(look.textSecondary)
                    cornerRadius = dp(2).toFloat()
                }
                alpha = 0.4f
            },
            LinearLayout.LayoutParams(dp(32), dp(4)).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = dp(12)
                bottomMargin = dp(16)
            },
        )
        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        sheet.addView(content, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        showChoices()

        // Edge to edge (Android 15+ always): the sheet runs under the navigation bar, its
        // content stays above it — and above the keyboard while a new person's name is typed.
        val bottomPadding = sheet.paddingBottom
        root.setOnApplyWindowInsetsListener { _, insets ->
            val bottom = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                maxOf(
                    insets.getInsets(WindowInsets.Type.systemBars()).bottom,
                    insets.getInsets(WindowInsets.Type.ime()).bottom,
                )
            } else {
                @Suppress("DEPRECATION")
                insets.systemWindowInsetBottom
            }
            sheet.setPadding(0, 0, 0, bottomPadding + bottom)
            insets
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
        }
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        setContentView(root)

        sheet.post {
            sheet.translationY = sheet.height.toFloat()
            sheet.animate().translationY(0f).setDuration(220).start()
            root.animate().alpha(1f).setDuration(220).start()
        }
    }

    /** Where to open the link, or "Zapisz na później". */
    private fun showChoices() {
        choosingPerson = false
        hideKeyboard()
        content.removeAllViews()
        val kind = kind()
        content.addView(header("Otwórz w…", kind))

        val remember = CheckBox(this).apply {
            text = "Zapamiętaj wybór dla linków ${service.from}"
            setTextColor(look.text)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            typeface = face
            buttonTintList = ColorStateList(
                arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()),
                intArrayOf(look.accent, look.textSecondary),
            )
        }
        fun choiceRow(icon: Drawable?, title: String, subtitle: String, choice: LinkChoice) {
            content.addView(
                row(appIcon(icon), title, subtitle) {
                    if (remember.isChecked) LinkTargets.setChoice(this, service, choice)
                    open(choice)
                    finishNow()
                },
                LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT),
            )
        }

        val pm = packageManager
        if (kind.supported) {
            choiceRow(applicationInfo.loadIcon(pm), applicationInfo.loadLabel(pm).toString(),
                kind.leinaAction, LinkChoice.LEINA)
        }
        if (LinkTargets.isInstalled(this, service.appPackage)) {
            val info = pm.getApplicationInfo(service.appPackage, 0)
            choiceRow(info.loadIcon(pm), info.loadLabel(pm).toString(), "Otwórz w aplikacji",
                LinkChoice.APP)
        }
        LinkTargets.browserPackage(this)?.let { browser ->
            val info = pm.getApplicationInfo(browser, 0)
            choiceRow(info.loadIcon(pm), info.loadLabel(pm).toString(), "Otwórz w przeglądarce",
                LinkChoice.BROWSER)
        }
        if (kind.supported) {
            content.addView(divider(), dividerParams())
            content.addView(
                row(roundIcon(iconRes = R.drawable.ic_save_later), "Zapisz na później",
                    "Wybierz, od kogo jest ten link") {
                    showPeople()
                },
                LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT),
            )
        }

        content.addView(divider(), dividerParams())
        content.addView(
            remember,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply {
                topMargin = dp(8)
                marginStart = dp(18)
                marginEnd = dp(24)
            },
        )
        content.addView(
            text("Zmienisz to w Ustawienia › Otwieranie linków", 12f, look.textSecondary).apply {
                setPadding(dp(24), 0, dp(24), dp(16))
                maxLines = 2
            },
        )
    }

    /** "Od kogo?": the people links were saved from before, or a new one. */
    private fun showPeople() {
        choosingPerson = true
        content.removeAllViews()
        val kind = kind()
        content.addView(header("Od kogo?", kind))

        val people = LaterLinks.people(this)
        val newPerson = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        content.addView(newPerson, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        fun showNewPersonRow() {
            newPerson.removeAllViews()
            newPerson.addView(
                row(roundIcon(glyph = "+"), "Nowa osoba", null) { showNameField(newPerson, kind) },
                LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT),
            )
        }
        if (people.isEmpty()) showNameField(newPerson, kind) else showNewPersonRow()

        if (people.isNotEmpty()) {
            val list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            for (person in people) {
                val name = person.optString("name")
                list.addView(
                    row(roundIcon(glyph = name.take(1).uppercase()), name, null) {
                        saveFor(person.getString("id"), name, kind)
                    },
                    LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT),
                )
            }
            // Many people: the list scrolls, the sheet stays below the status bar.
            val scroll = ScrollView(this).apply { addView(list) }
            content.addView(scroll, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
            scroll.post {
                val max = resources.displayMetrics.heightPixels / 2
                if (scroll.height > max) {
                    scroll.layoutParams = scroll.layoutParams.apply { height = max }
                }
            }
        }

        content.addView(divider(), dividerParams())
        content.addView(
            text("← Wróć", 15f, look.textSecondary, bold = true).apply {
                setPadding(dp(24), dp(14), dp(24), dp(16))
                pressable(this)
                setOnClickListener { showChoices() }
            },
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT),
        )
    }

    /** Typing a new person's name in place of the "Nowa osoba" row. */
    private fun showNameField(into: LinearLayout, kind: Kind) {
        into.removeAllViews()
        val field = EditText(this).apply {
            hint = "Imię lub nazwa"
            setTextColor(look.text)
            setHintTextColor(look.textSecondary)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = face
            isSingleLine = true
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_WORDS
            imeOptions = EditorInfo.IME_ACTION_DONE
            // Some vendors' default field (EMUI) is a filled block in the accent colour.
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                setStroke(dp(1), look.accent)
                cornerRadius = dp(8).toFloat()
            }
            setPadding(dp(14), dp(12), dp(14), dp(12))
        }
        fun submit() {
            val name = field.text.toString().trim()
            if (name.isEmpty()) return
            saveFor(LaterLinks.addPerson(this, name), name, kind)
        }
        field.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_DONE) submit()
            true
        }
        val save = text("Zapisz", 15f, look.accent, bold = true).apply {
            setPadding(dp(16), dp(12), dp(16), dp(12))
            pressable(this)
            setOnClickListener { submit() }
        }
        into.addView(
            LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(24), dp(8), dp(12), dp(8))
                addView(field, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
                addView(save)
            },
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT),
        )
        field.requestFocus()
        field.post {
            getSystemService(InputMethodManager::class.java)
                ?.showSoftInput(field, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun saveFor(personId: String, name: String, kind: Kind) {
        LaterLinks.save(this, uri.toString(), service.key, kind.label, personId)
        hideKeyboard()
        Toast.makeText(applicationContext, "Zapisano na później — od: $name", Toast.LENGTH_SHORT)
            .show()
        close()
    }

    private fun hideKeyboard() {
        val token = currentFocus?.windowToken ?: return
        getSystemService(InputMethodManager::class.java)?.hideSoftInputFromWindow(token, 0)
    }

    private fun close() {
        if (closing) return
        if (!::sheet.isInitialized) {
            finishNow()
            return
        }
        closing = true
        hideKeyboard()
        root.animate().alpha(0f).setDuration(180).start()
        sheet.animate().translationY(sheet.height.toFloat()).setDuration(180)
            .setListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) = finishNow()
            }).start()
    }

    private fun finishNow() {
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }
}
