import 'dart:math';

import 'package:flutter/material.dart';

import '../data/album_covers.dart';
import '../data/startup_covers.dart';
import '../theme.dart';
import '../theme_controller.dart';
import 'cover_art.dart';
import 'cover_filters.dart';

/// Covers this big and up use the large image (the full player).
bool isLargeCover(double size) => size >= 120;

/// What [SongCover] draws for [image] at [size]: decoded at the size shown, with the user's
/// filter ([seed] varies its grain). Also used to get a cover ready before it's shown
/// ([precacheSongCover]), so both must build equal providers.
ImageProvider coverImageFor(
  BuildContext context,
  ImageProvider image,
  double size,
  String seed, {
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
    seed: seed.hashCode,
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
  await precacheImage(coverImageFor(context, image, size, cover.seed), context);
}

/// A song's album cover ([AlbumCovers]); the placeholder [CoverArt] until it's found, or when
/// no source has one.
class SongCover extends StatefulWidget {
  const SongCover({
    super.key,
    required this.cover,
    this.size = 56,
    this.filterStrength,
    this.startup,
  });

  final CoverRequest cover;
  final double size;

  /// Instead of the filter's saved intensity (the slider's preview).
  final double? filterStrength;

  /// A place seen as the app starts (Home's first cards, the mini player), and the song it
  /// shows: the cover found there is remembered ([StartupCovers]), and on the next start it
  /// stands in until this one is found again. Until [settled] (Home's songs before music.db
  /// has loaded, looked for without their album) what's found here is neither shown over the
  /// stand-in nor remembered: it may be another picture than the song's own cover.
  final ({String slot, String check, bool settled})? startup;

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
    } else if (isLargeCover(old.size) != isLargeCover(widget.size) ||
        // The same cover, now with the song a video may be searched for (the player's song
        // shown before music.db loaded, QueueSession.showSaved), and nothing found without it.
        (_image == null &&
            old.cover.videoSearch == null &&
            widget.cover.videoSearch != null)) {
      _resolve();
    } else if (old.startup?.settled == false &&
        widget.startup?.settled == true) {
      // Found while it couldn't be told apart from another picture: the same request now.
      if (_image case final image?) _remember(image, widget.cover.seed);
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
    final cover = widget.cover;
    final asked = widget.startup;
    covers
        .resolve(cover, large: large, wanted: wanted)
        .then((image) {
          // Settled meanwhile (music.db loaded while this was looked for): the same request.
          final startup = wanted() ? widget.startup : asked;
          if (image != null && startup != null && startup.settled) {
            _rememberIn(covers, startup, image, cover.seed);
          }
          if (wanted() && image != _image) setState(() => _image = image);
        })
        .catchError((Object e) => debugPrint('Showing a cover failed: $e'));
  }

  void _remember(ImageProvider image, String seed) {
    final covers = AlbumCoversScope.maybeOf(context);
    final startup = widget.startup;
    if (covers != null && startup != null) {
      _rememberIn(covers, startup, image, seed);
    }
  }

  static void _rememberIn(
    AlbumCovers covers,
    ({String slot, String check, bool settled}) startup,
    ImageProvider image,
    String seed,
  ) {
    covers.startup
        ?.remember(startup.slot, startup.check, image, seed)
        .catchError(
          (Object e) => debugPrint('Remembering a start-up cover failed: $e'),
        );
  }

  /// What stands in for the cover until it's found, from the last start.
  StartupCover? _standIn(BuildContext context) => switch (widget.startup) {
    (:final slot, :final check, settled: _) => AlbumCoversScope.maybeOf(
      context,
    )?.startup?.of(slot, check),
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final placeholder = CoverArt(seed: widget.cover.seed, size: size);
    var image = _image;
    var seed = widget.cover.seed;
    if (image == null || widget.startup?.settled == false) {
      final standIn = _standIn(context);
      if (standIn != null) {
        // With the seed it was drawn with: once found, the same file is the same image.
        image = FileImage(standIn.file);
        seed = standIn.seed;
      }
    }
    if (image == null) return placeholder;
    final filter = ThemeScope.maybeOf(context)?.coverFilter ?? CoverFilter.none;
    return ClipRRect(
      borderRadius: context.palette.radius(4),
      child: Image(
        image: coverImageFor(
          context,
          image,
          size,
          seed,
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
