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
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (palette.panelHeaders) return _PanelTitleBar(text);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: AppFontSize.section,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Section heading styled as the title bar of a retro desktop window ("NAZWA ×").
class _PanelTitleBar extends StatelessWidget {
  const _PanelTitleBar(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: palette.outline ?? palette.surfaceHigh,
      child: Row(
        children: [
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

/// Top bar of each bottom-nav tab: avatar opening the profile menu, then a title (or other
/// [content], e.g. Home's filter chips), then optional actions. Every tab uses it, so the avatar
/// sits at exactly the same spot when switching tabs.
class TabHeader extends StatelessWidget {
  const TabHeader({
    super.key,
    this.title,
    this.content,
    required this.onAvatarTap,
    this.actions = const [],
  }) : assert(
         (title == null) != (content == null),
         'Pass either a title or content',
       );

  final String? title;
  final Widget? content;
  final VoidCallback onAvatarTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      // Same height with or without action icons, so the avatar sits at the same spot on every
      // tab.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
        child: Row(
          children: [
            ProfileAvatar(onTap: onAvatarTap),
            const SizedBox(width: 12),
            Expanded(
              child:
                  content ??
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppFontSize.tabTitle,
                      fontWeight: FontWeight.bold,
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

/// "utwór" in the form that goes with [count]: 1 utwór, 2 utwory, 5 utworów.
String songsWord(int count) {
  if (count == 1) return 'utwór';
  final tens = count % 100 ~/ 10;
  final last = count % 10;
  return tens != 1 && last >= 2 && last <= 4 ? 'utwory' : 'utworów';
}
