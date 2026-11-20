import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';
import '../theme_controller.dart';

/// "Ustawienia › Wygląd › Język": the phone's language (Polish when the app doesn't know it) or
/// one chosen for good. Each language is named in itself.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final themes = ThemeScope.of(context);
    final systemLocale = resolveSystemLocale(
      WidgetsBinding.instance.platformDispatcher.locales,
    );
    final systemName = availableLanguages
        .firstWhere(
          (l) => l.locale == systemLocale,
          orElse: () => availableLanguages.first,
        )
        .name;

    Widget option(String tag, String title, {String? subtitle}) {
      final selected = themes.languageTag == tag;
      return ListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? palette.accent : palette.textSecondary,
        ),
        onTap: () => themes.setLanguage(tag),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: palette.surface,
        title: Text(l10n.languageTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12),
        children: [
          option(
            systemLanguageTag,
            l10n.languageSystem,
            subtitle: l10n.languageSystemSubtitle(systemName),
          ),
          const Divider(height: 24),
          for (final language in availableLanguages)
            option(language.tag, language.name),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Text(
              l10n.languageNote,
              style: TextStyle(
                fontSize: AppFontSize.listSubtitle,
                color: palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
