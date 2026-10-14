import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/album_covers.dart';
import '../data/combined_search.dart';
import '../data/song_catalog.dart';
import '../data/youtube_library.dart';
import '../dummy.dart';
import '../playback/youtube_playback.dart';
import '../theme.dart';
import 'song_cover.dart';
import 'song_names.dart';

/// One round button of the share sheet; [onTap] `null` shows it dimmed, and tapping it then
/// shows [unavailable] (why it can't be used).
class ShareOption {
  const ShareOption({
    required this.icon,
    required this.label,
    this.onTap,
    this.unavailable,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? unavailable;
}

/// "Udostępnij": a preview card of what's shared over a row of round buttons, laid out like the
/// reference app's share sheet. The sheet closes before an option runs.
Future<void> showShareSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Widget cover,
  required Color tint,
  required List<ShareOption> options,
}) {
  final messenger = ScaffoldMessenger.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final palette = sheetContext.palette;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: palette.radius(12),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [tint, Color.lerp(tint, palette.background, 0.6)!],
                  ),
                ),
                child: Column(
                  children: [
                    cover,
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppFontSize.section,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final option in options)
                    _ShareButton(
                      option: option,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        final onTap = option.onTap;
                        if (onTap != null) {
                          onTap();
                        } else if (option.unavailable != null) {
                          messenger.showSnackBar(
                            SnackBar(content: Text(option.unavailable!)),
                          );
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Where a shared playlist link leads, for the "Otwórz w …" button.
enum ShareTarget { youtube, spotify }

/// A playlist's link: Kopiuj link, Otwórz w YouTube / Spotify, Więcej (the phone's share sheet).
/// [makeOnYouTube] takes the middle place for a playlist made on the phone: "Utwórz na
/// YouTube" while it has no [link] (the other two dimmed), "Dokończ…" ([unfinished]) when
/// making it stopped half-way.
Future<void> showLinkShareSheet(
  BuildContext context, {
  required Uri? link,
  required ShareTarget target,
  required String title,
  required String subtitle,
  required Widget cover,
  required Color tint,
  VoidCallback? makeOnYouTube,
  bool unfinished = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  const noLink =
      'Ta playlista nie ma jeszcze linku — najpierw utwórz ją na YouTube.';
  return showShareSheet(
    context,
    title: title,
    subtitle: subtitle,
    cover: cover,
    tint: tint,
    options: [
      ShareOption(
        icon: Icons.link,
        label: 'Kopiuj link',
        onTap: link == null
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: link.toString()));
                messenger.showSnackBar(
                  const SnackBar(content: Text('Skopiowano link')),
                );
              },
        unavailable: noLink,
      ),
      if (makeOnYouTube != null)
        ShareOption(
          icon: Icons.playlist_add,
          label: unfinished ? 'Dokończ na YouTube' : 'Utwórz na YouTube',
          onTap: makeOnYouTube,
        )
      else if (link != null)
        ShareOption(
          icon: target == ShareTarget.youtube
              ? Icons.smart_display_outlined
              : Icons.graphic_eq,
          label: target == ShareTarget.youtube
              ? 'Otwórz w YouTube'
              : 'Otwórz w Spotify',
          onTap: () async {
            final opened = target == ShareTarget.youtube
                ? await openInYouTube(link)
                : await _openSpotify(link);
            if (!opened) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Nie udało się otworzyć linku.')),
              );
            }
          },
        ),
      ShareOption(
        icon: Icons.more_horiz,
        label: 'Więcej',
        onTap: link == null ? null : () => _shareLink(link, title),
        unavailable: noLink,
      ),
    ],
  );
}

/// A song: as Leina Radio (not built yet), its YouTube video, its Spotify track, or its file
/// (not built yet). YouTube and Spotify hand the link to the phone's share sheet; they're dimmed
/// when the song has no such link. [idPrefix] names the dummies (`<idPrefix> › Udostępnij › …`).
Future<void> showSongShareSheet(
  BuildContext context,
  SearchHit hit, {
  required String idPrefix,
}) {
  // A video may have been found since the row was made.
  final song = withPhoneYouTube(hit, YouTubeLibraryScope.of(context));
  final videoId = song.youtubeVideoId;
  final spotify = song.spotifyUri;
  final subject = '${song.artistLabel} – ${song.title}';
  void dummy(String label) =>
      showDummy(context, '$idPrefix › Udostępnij › $label');
  return showShareSheet(
    context,
    title: song.shownTitle(context),
    subtitle: song.shownArtist(context),
    cover: SongCover(cover: CoverRequest.of(song), size: 160),
    tint: context.palette.colorForSeed(song.coverSeed),
    options: [
      ShareOption(
        icon: Icons.cell_tower,
        label: 'Leina Radio',
        onTap: () => dummy('Leina Radio'),
      ),
      ShareOption(
        icon: Icons.smart_display_outlined,
        label: 'YouTube',
        onTap: videoId == null
            ? null
            : () => _shareLink(youTubeWatchUri(videoId), subject),
        unavailable: song.youTube == YouTubeLink.unknown
            ? 'Nie znamy jeszcze filmu z tym utworem — odtwórz go, a telefon '
                  'poszuka go na YouTube.'
            : 'Tego utworu nie ma na YouTube.',
      ),
      ShareOption(
        icon: Icons.graphic_eq,
        label: 'Spotify',
        onTap: spotify == null ? null : () => _shareLink(spotify, subject),
        unavailable: 'Brak linku do tego utworu na Spotify.',
      ),
      ShareOption(
        icon: Icons.audio_file_outlined,
        label: 'MP3',
        onTap: () => dummy('MP3'),
      ),
    ],
  );
}

Future<void> _shareLink(Uri link, String subject) => SharePlus.instance.share(
  ShareParams(text: link.toString(), subject: subject),
);

/// The Spotify app when it's installed (it claims its own links), the browser otherwise.
Future<bool> _openSpotify(Uri link) async {
  try {
    if (await launchUrl(link, mode: LaunchMode.externalNonBrowserApplication)) {
      return true;
    }
  } catch (_) {
    // No app claims the link; fall through to the browser.
  }
  return launchUrl(link, mode: LaunchMode.externalApplication);
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.option, required this.onTap});

  final ShareOption option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final available = option.onTap != null;
    final color = available
        ? palette.textPrimary
        : palette.textSecondary.withValues(alpha: 0.4);
    return SizedBox(
      width: 80,
      child: InkWell(
        borderRadius: palette.radius(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: palette.chip,
                child: Icon(option.icon, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                option.label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppFontSize.small, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
