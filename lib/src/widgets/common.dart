import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/account.dart';
import '../theme.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, this.radius = 16, this.onTap});

  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final account = AccountScope.maybeOf(context);
    final name = account?.loggedIn ?? false ? account!.userName! : null;
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: palette.accent,
        child: name == null
            ? Icon(Icons.person, color: palette.onAccent, size: radius * 1.2)
            : Text(
                name.characters.first.toUpperCase(),
                style: TextStyle(
                  color: palette.onAccent,
                  fontSize: radius,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

/// Filter chip used on Home ("Wszystko"/"Muzyka"/…) and in the Library.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: selected ? palette.accent : palette.chip,
      shape: palette.pillShape,
      child: InkWell(
        customBorder: palette.pillShape,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppFontSize.small,
              color: selected ? palette.onAccent : palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon, this.trailing});

  final String text;

  /// Before the text, e.g. the pin of a pinned Home section.
  final IconData? icon;

  /// At the right end, e.g. a section's "⋯".
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (palette.panelHeaders) {
      return palette.chamfered
          ? _TabTitleBar(text, icon: icon, trailing: trailing)
          : _PanelTitleBar(text, icon: icon, trailing: trailing);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, trailing == null ? 16 : 4, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: palette.accent),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: AppFontSize.section,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Section heading styled as the title bar of a retro desktop window ("NAZWA ×").
class _PanelTitleBar extends StatelessWidget {
  const _PanelTitleBar(this.text, {this.icon, this.trailing});

  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: palette.outline ?? palette.surfaceHigh,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: palette.textPrimary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFontSize.small,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: palette.textPrimary,
              ),
            ),
          ),
          trailing ??
              Text(
                '×',
                style: TextStyle(
                  fontSize: AppFontSize.listTitle,
                  color: palette.textPrimary,
                ),
              ),
        ],
      ),
    );
  }
}

/// Section heading as a filled tab with a cut corner, then a thin line in the same colour to the
/// edge — the panel labels of cyberpunk HUD wallpapers.
class _TabTitleBar extends StatelessWidget {
  const _TabTitleBar(this.text, {this.icon, this.trailing});

  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colour = palette.outline ?? palette.accent;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, trailing == null ? 16 : 4, 10),
      child: Row(
        children: [
          Flexible(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 3, 18, 3),
              decoration: ShapeDecoration(
                color: colour,
                shape: const ChamferedBorder(cut: 10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: palette.textPrimary),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      text.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppFontSize.listTitle,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: Divider(color: colour, height: 1)),
          ?trailing,
        ],
      ),
    );
  }
}

/// Top bar of each bottom-nav tab: a title (or other [content], e.g. Home's filter chips), then
/// optional actions. No avatar: the profile is the "Ja" tab, down by the thumb (Juxtopposed's
/// Spotify redesign).
class TabHeader extends StatelessWidget {
  const TabHeader({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
  }) : assert(
         (title == null) != (content == null),
         'Pass either a title or content',
       );

  final String? title;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      // Same height with or without action icons, so the titles sit at the same spot on every
      // tab.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          children: [
            Expanded(
              child:
                  content ??
                  Text(
                    context.palette.uppercaseTitles
                        ? title!.toUpperCase()
                        : title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.tabTitle,
                      fontWeight: FontWeight.bold,
                      letterSpacing: context.palette.uppercaseTitles
                          ? 1.5
                          : null,
                    ),
                  ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// A dialog asking for one line of text (or a number); pops it, or null on "Anuluj". Owns its
/// text controller, so it's disposed only once the closing animation is over.
class TextInputDialog extends StatefulWidget {
  const TextInputDialog({
    super.key,
    required this.title,
    required this.hint,
    required this.initial,
    this.number = false,
  });

  final String title;
  final String hint;
  final String initial;
  final bool number;

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: widget.number ? TextInputType.number : null,
        inputFormatters: widget.number
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (text) => Navigator.of(context).pop(text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

/// The Polish word for [count] things: [one] for 1, [few] for 2–4 (22–24, …), else [many].
String pluralWord(int count, String one, String few, String many) {
  if (count == 1) return one;
  final tens = count % 100 ~/ 10;
  final last = count % 10;
  return tens != 1 && last >= 2 && last <= 4 ? few : many;
}

/// "utwór" in the form that goes with [count]: 1 utwór, 2 utwory, 5 utworów.
String songsWord(int count) => pluralWord(count, 'utwór', 'utwory', 'utworów');

const _monthsGenitive = [
  'stycznia',
  'lutego',
  'marca',
  'kwietnia',
  'maja',
  'czerwca',
  'lipca',
  'sierpnia',
  'września',
  'października',
  'listopada',
  'grudnia',
];

/// "16 października", with [year] "16 października 2026".
String dayMonthLabel(DateTime d, {bool year = false}) =>
    '${d.day} ${_monthsGenitive[d.month - 1]}${year ? ' ${d.year}' : ''}';
