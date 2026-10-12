import 'dart:math';

import 'package:flutter/material.dart';

import '../data/album_covers.dart';
import '../theme.dart';
import '../theme_controller.dart';
import 'cover_art.dart';
import 'cover_filters.dart';

/// Covers this big and up use the large image (the full player).
bool isLargeCover(double size) => size >= 120;

/// What [SongCover] draws for [image] at [size]: decoded at the size shown, with the user's
/// filter. Also used to get a cover ready before it's shown ([precacheSongCover]), so both must
/// build equal providers.
ImageProvider coverImageFor(
  BuildContext context,
  ImageProvider image,
  double size,
  CoverRequest cover, {
  double? strength,
}) {
  final ratio = MediaQuery.devicePixelRatioOf(context);
  final pixels = (size * ratio).round();
  final themes = ThemeScope.maybeOf(context);
  final filter = themes?.coverFilter ?? CoverFilter.none;
  final mix = strength ?? themes?.coverFilterStrength ?? 1;
  if (filter == CoverFilter.none || mix <= 0) {
    // By height, so a 16:9 thumbnail, cropped to the middle square, stays sharp.
    return ResizeImage(image, height: pixels);
  }
  return FilteredImage(
    image,
    filter: filter,
    size: pixels,
    color: themes?.monochromeColor ?? ThemeController.defaultMonochromeColor,
    // About 1.25 dp per dot: coarse enough to see, fine enough to read.
    dot: max(2, (ratio * 1.25).round()),
    seed: cover.seed.hashCode,
    strength: mix,
    background: themes?.monochromeBackground,
  );
}

/// Finds and decodes [cover] at [size] (filter included) ahead of time, so a screen that opens
/// later shows it in its first frame.
Future<void> precacheSongCover(
  BuildContext context,
  CoverRequest cover,
  double size,
) async {
  final covers = AlbumCoversScope.maybeOf(context);
  if (covers == null) return;
  final image = await covers.resolve(cover, large: isLargeCover(size));
  if (image == null || !context.mounted) return;
  await precacheImage(coverImageFor(context, image, size, cover), context);
}

/// A song's album cover ([AlbumCovers]); the placeholder [CoverArt] until it's found, or when
/// no source has one.
class SongCover extends StatefulWidget {
  const SongCover({
    super.key,
    required this.cover,
    this.size = 56,
    this.filterStrength,
  });

  final CoverRequest cover;
  final double size;

  /// Instead of the filter's saved intensity (the slider's preview).
  final double? filterStrength;

  @override
  State<SongCover> createState() => _SongCoverState();
}

class _SongCoverState extends State<SongCover> {
  ImageProvider? _image;
  Object? _request;

  /// A frame of this song's cover has been drawn: when the image changes (a rebuild with
  /// another filter or size), the old one stays until the new one is ready, not the placeholder.
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Also when the cover sources change or the cache is cleared (the scope notifies).
    _resolve();
  }

  @override
  void didUpdateWidget(SongCover old) {
    super.didUpdateWidget(old);
    if (old.cover.identity != widget.cover.identity) {
      _image = null;
      _shown = false;
      _resolve();
    } else if (isLargeCover(old.size) != isLargeCover(widget.size)) {
      _resolve();
    }
  }

  @override
  void dispose() {
    _request = null;
    super.dispose();
  }

  void _resolve() {
    final covers = AlbumCoversScope.maybeOf(context);
    if (covers == null) return;
    final large = isLargeCover(widget.size);
    // Known from before: shown in this very frame; still checked again below.
    _image = covers.known(widget.cover, large: large) ?? _image;
    final request = Object();
    _request = request;
    bool wanted() => mounted && _request == request;
    covers
        .resolve(widget.cover, large: large, wanted: wanted)
        .then((image) {
          if (wanted() && image != _image) setState(() => _image = image);
        })
        .catchError((Object e) => debugPrint('Showing a cover failed: $e'));
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final placeholder = CoverArt(seed: widget.cover.seed, size: size);
    final image = _image;
    if (image == null) return placeholder;
    final filter = ThemeScope.maybeOf(context)?.coverFilter ?? CoverFilter.none;
    return ClipRRect(
      borderRadius: context.palette.radius(4),
      child: Image(
        image: coverImageFor(
          context,
          image,
          size,
          widget.cover,
          strength: widget.filterStrength,
        ),
        filterQuality: filter == CoverFilter.monochrome
            ? FilterQuality.none
            : FilterQuality.medium,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, sync) {
          if (frame != null || sync) _shown = true;
          return _shown ? child : placeholder;
        },
        errorBuilder: (context, error, stack) => placeholder,
      ),
    );
  }
}
