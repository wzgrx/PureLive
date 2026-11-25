import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/music_library.dart';
import 'package:pure_live/app/music_player.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/video/video_widgets.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';

// The pieces of the music pages (A17.7 g2, g3, g6, g7): one song row, one
// song menu, adding to a playlist, the play mode written out, the mini bar.

/// The words of a play mode ("列表循环").
String musicModeLabel(PlayMode mode) => i18n(switch (mode) {
  PlayMode.sequence => 'tv_music_mode_sequence',
  PlayMode.repeatOne => 'tv_music_mode_repeat_one',
  PlayMode.shuffle => 'tv_music_mode_shuffle',
});

/// "列表循环 ⌄" (g3): the play mode as a button that offers the three.
class TvMusicModeButton extends ConsumerWidget {
  /// Creates the button.
  const new({this.small = false, super.key});

  /// The smaller form.
  final bool small;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(musicPlayerProvider);
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) => TvButton(
        key: const ValueKey('tv-music-mode'),
        small: small,
        label: '${musicModeLabel(player.mode)} ⌄',
        onTap: () async {
          final mode = await showTvChoice<PlayMode>(
            context,
            title: i18n('tv_music_mode'),
            current: player.mode,
            options: [for (final mode in PlayMode.values) TvChoice(value: mode, label: musicModeLabel(mode))],
          );
          if (mode != null) await player.setMode(mode);
        },
      ),
    );
  }
}

/// Where a song row sits, which decides how its menu removes it (g6).
enum MusicRowPlace {
  /// The queue: "从队列移除".
  queue,

  /// A playlist of the user's: "移出歌单".
  playlist,

  /// The recent plays: "从最近播放移除".
  recent,

  /// The liked songs: "从喜欢的歌曲移除".
  liked,

  /// Anywhere else: nothing to remove.
  other,
}

/// One song (g2: the queue, the player's panel, playlists, recent plays,
/// folders): its place, title, uploader and length; the song playing now in
/// the primary colour.
class TvSongRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.track,
    required this.number,
    required this.onTap,
    this.playing = false,
    this.onLongPress,
    this.autofocus = false,
    this.focusNode,
    super.key,
  });

  /// The song.
  final MusicTrack track;

  /// Its place, from 1.
  final int number;

  /// Plays it.
  final VoidCallback onTap;

  /// The menu.
  final VoidCallback? onLongPress;

  /// It is the one playing.
  final bool playing;

  /// Takes the focus.
  final bool autofocus;

  /// Its node.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final duration = track.part.duration > Duration.zero ? track.part.duration : track.archive.duration;
    final color = playing ? palette.accent : palette.text;
    return TvFocusable(
      zoom: false,
      autofocus: autofocus,
      focusNode: focusNode,
      onTap: onTap,
      onLongPress: onLongPress,
      builder: (context, focused) => Container(
        padding: EdgeInsets.symmetric(horizontal: scale.px(16), vertical: scale.px(10)),
        decoration: BoxDecoration(
          color: focused ? palette.highest : (playing ? palette.selected : null),
          borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: scale.pxText(40),
              child: Text(
                '$number',
                key: playing ? const ValueKey('tv-song-playing') : null,
                style: scale.font(TvTextSize.small, color: playing ? palette.accent : palette.textSecondary).tabular,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: scale.font(TvTextSize.body, weight: FontWeight.w600, color: color),
                  ),
                  Text(
                    track.archive.owner.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: scale.font(TvTextSize.small, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
            if (duration > Duration.zero)
              Text(videoClock(duration), style: scale.font(TvTextSize.small, color: palette.textSecondary).tabular),
          ],
        ),
      ),
    );
  }
}

/// The song menu (g6): play next, add to the queue, like, add to a
/// playlist, the uploader; the removal says where from ([place]); the focus
/// starts on the first item, never on a removal.
Future<void> showSongMenu(
  BuildContext context, {
  required WidgetRef ref,
  required MusicTrack track,
  MusicRowPlace place = MusicRowPlace.other,
  String? playlistId,
  int? queueIndex,
  void Function(VodOwner owner)? openUp,
}) async {
  final player = ref.read(musicPlayerProvider);
  final library = ref.read(musicLibraryProvider);
  final liked = library.isLiked(track);
  final remove = switch (place) {
    MusicRowPlace.queue => 'tv_music_remove_queue',
    MusicRowPlace.playlist => 'tv_music_remove_playlist',
    MusicRowPlace.recent => 'tv_music_remove_recent',
    MusicRowPlace.liked => 'tv_music_remove_liked',
    MusicRowPlace.other => null,
  };
  await showTvVideoMenu(
    context,
    title: track.title,
    actions: [
      if (place != MusicRowPlace.queue)
        TvVideoAction(
          id: 'play-next',
          icon: TvIcons.musicNext,
          label: i18n('tv_music_play_next'),
          run: () async {
            await player.playNext(track);
            AppNavigator.toast(i18n('tv_music_play_next_done'));
          },
        ),
      if (place != MusicRowPlace.queue)
        TvVideoAction(
          id: 'enqueue',
          icon: TvIcons.musicQueue,
          label: i18n('tv_music_enqueue'),
          run: () async {
            final added = await player.enqueue(track);
            AppNavigator.toast(i18n(added ? 'tv_music_enqueued' : 'tv_music_already_queued'));
          },
        ),
      TvVideoAction(
        id: 'like',
        icon: TvIcons.followedMark,
        label: i18n(liked ? 'tv_music_unlike' : 'tv_music_like'),
        run: () async {
          await library.toggleLike(track);
        },
      ),
      TvVideoAction(
        id: 'add-to-playlist',
        icon: TvIcons.musicPlaylist,
        label: i18n('tv_music_add_to_playlist'),
        run: () async {
          if (context.mounted) await showAddToPlaylist(context, library: library, tracks: [track]);
        },
      ),
      if (openUp != null && track.archive.owner.mid > 0)
        TvVideoAction(
          id: 'up',
          icon: TvIcons.videoMine,
          label: i18n('tv_video_space_of', args: {'name': track.archive.owner.name}),
          run: () async => openUp(track.archive.owner),
        ),
      if (remove != null)
        TvVideoAction(
          id: 'remove',
          icon: TvIcons.delete,
          label: i18n(remove),
          run: () async {
            switch (place) {
              case MusicRowPlace.queue:
                if (queueIndex != null) await player.removeAt(queueIndex);
              case MusicRowPlace.playlist:
                if (playlistId != null) await library.removeTrack(playlistId, track);
              case MusicRowPlace.recent:
                await library.removeRecent(track);
              case MusicRowPlace.liked:
                await library.toggleLike(track);
              case MusicRowPlace.other:
                break;
            }
          },
        ),
    ],
  );
}

/// Adds [tracks] to a playlist (g7): the playlists that have them say
/// "已在"; "新建歌单并加入" names a new one and puts them in it.
Future<void> showAddToPlaylist(
  BuildContext context, {
  required MusicLibrary library,
  required List<MusicTrack> tracks,
}) async {
  const create = '';
  final ids = {for (final track in tracks) track.id};
  final id = await showTvChoice<String>(
    context,
    title: i18n('tv_music_add_to_playlist'),
    options: [
      TvChoice(value: create, label: i18n('tv_music_new_playlist_add'), icon: TvIcons.musicPlaylist),
      for (final playlist in library.playlists)
        TvChoice(
          value: playlist.id,
          label: playlist.name,
          description: playlist.tracks.any((track) => ids.contains(track.id))
              ? i18n('tv_music_already_in')
              : i18n('tv_music_song_count', args: {'count': '${playlist.tracks.length}'}),
        ),
    ],
  );
  if (id == null || !context.mounted) return;
  if (id == create) {
    final name = await TvTextInput.prompt(
      context,
      title: i18n('tv_music_new_playlist'),
      hint: i18n('tv_music_playlist_name'),
    );
    if (name == null || name.trim().isEmpty) return;
    await library.createPlaylist(name, tracks: tracks);
    AppNavigator.toast(i18n('tv_music_added_to', args: {'name': name.trim()}));
    return;
  }
  final added = await library.addTracks(id, tracks);
  final name = library.playlist(id)?.name ?? '';
  AppNavigator.toast(
    added == 0
        ? i18n('tv_music_already_in_named', args: {'name': name})
        : i18n('tv_music_added_to', args: {'name': name}),
  );
}

/// The mini bar (g1): at the bottom of the music pages while the queue
/// has songs — the cover, the song, play or pause, next; OK on the song
/// opens the player.
class TvMusicMiniBar extends ConsumerWidget {
  /// Creates the bar.
  const new({required this.onOpen, super.key});

  /// Opens the player.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(musicPlayerProvider);
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([player, player.playback]),
      builder: (context, _) {
        final track = player.current;
        if (!player.hasQueue || track == null) return const SizedBox.shrink();
        final playing = player.isPlaying;
        return Container(
          key: const ValueKey('tv-music-mini-bar'),
          margin: EdgeInsets.only(top: scale.px(12)),
          padding: EdgeInsets.all(scale.px(12)),
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: scale.px(96),
                height: scale.px(54),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(scale.px(8)),
                  child: TvCover(url: track.archive.cover),
                ),
              ),
              SizedBox(width: scale.px(16)),
              Expanded(
                child: TvFocusable(
                  key: const ValueKey('tv-music-mini-open'),
                  zoom: false,
                  onTap: onOpen,
                  builder: (context, focused) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: scale.font(TvTextSize.body, weight: FontWeight.w600, color: palette.text),
                      ),
                      Text(
                        track.archive.owner.name,
                        maxLines: 1,
                        style: scale.font(TvTextSize.small, color: palette.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              TvButton(
                key: const ValueKey('tv-music-mini-play'),
                small: true,
                icon: playing ? AppIcons.pause : AppIcons.play,
                label: i18n(playing ? 'tv_video_pause' : 'tv_video_play'),
                onTap: () => unawaited(player.togglePlayPause()),
              ),
              SizedBox(width: scale.px(8)),
              TvButton(
                key: const ValueKey('tv-music-mini-next'),
                small: true,
                label: i18n('tv_music_next'),
                onTap: () => unawaited(player.next()),
              ),
            ],
          ),
        );
      },
    );
  }
}
