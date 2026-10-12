import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A dialog to pick any colour: a saturation/brightness square, a hue bar, the hex code and
/// [swatches] to start from (e.g. colours picked before); returns `null` on "Anuluj".
Future<Color?> showColorPicker(
  BuildContext context, {
  required Color initial,
  String title = 'Własny kolor',
  List<Color> swatches = const [],
}) => showDialog<Color>(
  context: context,
  builder: (_) =>
      _ColorPickerDialog(initial: initial, title: title, swatches: swatches),
);

/// Black or white, whichever reads better on [background] (a check mark on a swatch).
Color contrastOn(Color background) =>
    background.computeLuminance() > 0.4 ? Colors.black : Colors.white;

String colorHex(Color c) =>
    (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.initial,
    required this.title,
    required this.swatches,
  });

  final Color initial;
  final String title;
  final List<Color> swatches;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final _hex = TextEditingController(text: colorHex(widget.initial));

  Color get _color => _hsv.toColor();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor hsv) {
    setState(() => _hsv = hsv);
    _hex.text = colorHex(_color);
  }

  void _typed(String text) {
    final value = text.length == 6 ? int.tryParse(text, radix: 16) : null;
    if (value == null) return;
    // Keep the hue when the typed colour is grey (it has none of its own).
    final typed = HSVColor.fromColor(Color(0xFF000000 | value));
    setState(
      () => _hsv = typed.saturation == 0 ? typed.withHue(_hsv.hue) : typed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.swatches.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final swatch in widget.swatches)
                    GestureDetector(
                      onTap: () => _set(HSVColor.fromColor(swatch)),
                      child: CircleAvatar(radius: 14, backgroundColor: swatch),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _SaturationValueBox(hsv: _hsv, onChanged: _set),
            const SizedBox(height: 16),
            _HueBar(
              key: const Key('colorPicker.hue'),
              hsv: _hsv,
              onChanged: _set,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _color,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.textSecondary),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    maxLength: 6,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                    ],
                    decoration: const InputDecoration(
                      prefixText: '#',
                      hintText: 'RRGGBB',
                      counterText: '',
                    ),
                    onChanged: _typed,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Anuluj'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Saturation left → right, brightness bottom → top, for the current hue.
class _SaturationValueBox extends StatelessWidget {
  const _SaturationValueBox({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const height = 180.0;
        void pick(Offset p) => onChanged(
          hsv
              .withSaturation((p.dx / width).clamp(0.0, 1.0))
              .withValue(1 - (p.dy / height).clamp(0.0, 1.0)),
        );
        return GestureDetector(
          onPanDown: (d) => pick(d.localPosition),
          onPanUpdate: (d) => pick(d.localPosition),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: hsv.saturation * width - 10,
                  top: (1 - hsv.value) * height - 10,
                  child: _Marker(color: hsv.toColor()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HueBar extends StatelessWidget {
  const _HueBar({super.key, required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void pick(Offset p) =>
            onChanged(hsv.withHue((p.dx / width).clamp(0.0, 1.0) * 360));
        return GestureDetector(
          onPanDown: (d) => pick(d.localPosition),
          onPanUpdate: (d) => pick(d.localPosition),
          child: SizedBox(
            width: width,
            height: 28,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      colors: [
                        for (var h = 0; h <= 360; h += 60)
                          HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: hsv.hue / 360 * width - 10,
                  child: _Marker(
                    color: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Marker extends StatelessWidget {
  const _Marker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
    ),
  );
}
