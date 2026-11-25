import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/music_library.dart';
import 'package:pure_live/app/music_player.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/tv/music/music_widgets.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/video/video_widgets.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';

/// The music player (A17.7 g4, g5): the cover with the lyrics (the line
/// sung now lit) or the picture, the progress, one row of controls — play,
/// previous, next, "列表循环 ⌄", picture or audio, quality, like, queue.
/// ↑ from the progress opens the queue on the right; Back closes it, then
/// leaves — the music plays on.
class TvMusicPlayerPage extends ConsumerStatefulWidget {
  /// Creates the player.
  const new({super.key});

  @override
  ConsumerState<TvMusicPlayerPage> createState() => _TvMusicPlayerPageState();
}

class _TvMusicPlayerPageState extends ConsumerState<TvMusicPlayerPage> {
  late final MusicPlayer _player = ref.read(musicPlayerProvider);
  late final MusicLibrary _library = ref.read(musicLibraryProvider);
  bool _queue = false;
  String? _lyricFor;
  LyricDocument? _lyrics;
  bool _lyricsLoading = false;
  final ScrollController _lyricScroll = ScrollController();
  final FocusNode _play = FocusNode(debugLabel: 'tv music play');

  @override
  void initState() {
    super.initState();
    _player.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    _player.removeListener(_changed);
    _lyricScroll.dispose();
    _play.dispose();
    super.dispose();
  }

  void _changed() {
    final track = _player.current;
    if (track == null || track.id == _lyricFor) return;
    _lyricFor = track.id;
    unawaited(_loadLyrics(track));
  }

  Future<void> _loadLyrics(MusicTrack track) async {
    setState(() {
      _lyrics = null;
      _lyricsLoading = true;
    });
    try {
      final lyrics = await _library.lyrics.find(
        LyricQuery(
          title: track.title,
          artist: track.archive.owner.name,
          bvid: track.archive.bvid,
          cid: track.part.cid,
          aid: track.archive.aid,
        ),
      );
      if (mounted && _lyricFor == track.id) setState(() => _lyrics = lyrics);
    } on Object {
      // No lyrics is no failure.
    } finally {
      if (mounted && _lyricFor == track.id) setState(() => _lyricsLoading = false);
    }
  }

  Future<void> _chooseQuality() async {
    final settings = ref.read(storeProvider).settings;
    final lossless = await showTvChoice<bool>(
      context,
      title: i18n('tv_music_quality'),
      current: settings.get(Settings.musicLossless),
      options: [
        TvChoice(value: false, label: i18n('tv_music_quality_standard')),
        TvChoice(value: true, label: i18n('tv_music_quality_lossless'), description: i18n('tv_video_vip')),
      ],
    );
    if (lossless != null) await settings.set(Settings.musicLossless, lossless);
  }

  void _openQueue() {
    setState(() => _queue = true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return PopScope(
      canPop: !_queue,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _queue) {
          setState(() => _queue = false);
          _play.requestFocus();
        }
      },
      child: Scaffold(
        key: const ValueKey('tv-music-player'),
        backgroundColor: palette.background,
        body: ListenableBuilder(
          listenable: Listenable.merge([_player, _player.playback, _library]),
          builder: (context, _) {
            final track = _player.current;
            final state = _player.playback.value;
            final playing = _player.isPlaying;
            if (track == null) {
              return Center(
                child: Text(i18n('tv_music_nothing'), style: scale.font(TvTextSize.body, color: palette.textSecondary)),
              );
            }
            final duration = state.duration > Duration.zero
                ? state.duration
                : (track.part.duration > Duration.zero ? track.part.duration : track.archive.duration);
            final session = _player.session;
            return Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(scale.px(96), scale.px(56), scale.px(96), scale.px(40)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: scale.px(640),
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
                                  child: !_player.audioOnly && session != null
                                      ? LiveVideoView(session: session)
                                      : TvCover(url: track.archive.cover),
                                ),
                              ),
                            ),
                            SizedBox(width: scale.px(40)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: scale.font(TvTextSize.title, weight: FontWeight.w600, color: palette.text),
                                  ),
                                  Text(
                                    track.archive.owner.name,
                                    style: scale.font(TvTextSize.small, color: palette.textSecondary),
                                  ),
                                  SizedBox(height: scale.px(16)),
                                  Expanded(child: _lyricsView(state.position)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: scale.px(16)),
                      _MusicProgress(
                        position: state.position,
                        duration: duration,
                        onSeek: (direction) => unawaited(_player.seekAccelerated(direction)),
                        onUp: _openQueue,
                      ),
                      SizedBox(height: scale.px(16)),
                      FocusTraversalGroup(
                        child: Row(
                          children: [
                            TvButton(
                              key: const ValueKey('tv-music-play'),
                              focusNode: _play,
                              autofocus: true,
                              icon: playing ? AppIcons.pause : AppIcons.play,
                              label: i18n(playing ? 'tv_video_pause' : 'tv_video_play'),
                              onTap: () => unawaited(_player.togglePlayPause()),
                            ),
                            SizedBox(width: scale.px(8)),
                            TvButton(
                              key: const ValueKey('tv-music-previous'),
                              small: true,
                              label: i18n('tv_music_previous'),
                              onTap: () => unawaited(_player.previous()),
                            ),
                            SizedBox(width: scale.px(8)),
                            TvButton(
                              key: const ValueKey('tv-music-next'),
                              small: true,
                              label: i18n('tv_music_next'),
                              onTap: () => unawaited(_player.next()),
                            ),
                            SizedBox(width: scale.px(8)),
                            const TvMusicModeButton(small: true),
                            const Spacer(),
                            TvButton(
                              key: const ValueKey('tv-music-audio-only'),
                              small: true,
                              label: i18n(_player.audioOnly ? 'tv_music_audio_only' : 'tv_music_with_picture'),
                              onTap: () => unawaited(_player.setAudioOnly(enabled: !_player.audioOnly)),
                            ),
                            SizedBox(width: scale.px(8)),
                            TvButton(
                              key: const ValueKey('tv-music-quality'),
                              small: true,
                              label: i18n('tv_music_quality'),
                              onTap: () => unawaited(_chooseQuality()),
                            ),
                            SizedBox(width: scale.px(8)),
                            TvButton(
                              key: const ValueKey('tv-music-like'),
                              small: true,
                              selected: _library.isLiked(track),
                              label: i18n(_library.isLiked(track) ? 'tv_music_liked' : 'tv_music_like'),
                              onTap: () => unawaited(_library.toggleLike(track)),
                            ),
                            SizedBox(width: scale.px(8)),
                            TvButton(
                              key: const ValueKey('tv-music-queue'),
                              small: true,
                              label: i18n('tv_music_queue_count', args: {'count': '${_player.tracks.length}'}),
                              onTap: _openQueue,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_queue)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      key: const ValueKey('tv-music-queue-panel'),
                      width: scale.px(800),
                      color: palette.raised.withValues(alpha: 0.97),
                      padding: EdgeInsets.all(scale.px(24)),
                      child: FocusScope(child: TvMusicQueue(player: _player)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _lyricsView(Duration position) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final lyrics = _lyrics;
    if (lyrics == null || lyrics.lines.isEmpty) {
      return Text(
        i18n(_lyricsLoading ? 'tv_music_lyrics_loading' : 'tv_music_lyrics_none'),
        key: const ValueKey('tv-music-lyrics-state'),
        style: scale.font(TvTextSize.body, color: palette.textSecondary),
      );
    }
    var current = -1;
    for (final (index, line) in lyrics.lines.indexed) {
      if (line.start <= position) current = index;
    }
    final lineHeight = scale.pxText(48);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_lyricScroll.hasClients || current < 0) return;
      final target = (current * lineHeight - lineHeight * 2).clamp(0.0, _lyricScroll.position.maxScrollExtent);
      if ((_lyricScroll.offset - target).abs() > 1) {
        _lyricScroll.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
    return ListView.builder(
      key: const ValueKey('tv-music-lyrics'),
      controller: _lyricScroll,
      itemExtent: lineHeight,
      itemCount: lyrics.lines.length,
      itemBuilder: (context, index) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          lyrics.lines[index].text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: scale.font(
            index == current ? TvTextSize.heading : TvTextSize.body,
            weight: index == current ? FontWeight.w600 : FontWeight.w400,
            color: index == current ? palette.accent : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The queue (g2, g3): "列表循环 ⌄" on top, the songs as rows, the one
/// playing lit and focused; OK plays one, the menu removes it.
class TvMusicQueue extends ConsumerWidget {
  /// Creates the queue of [player].
  const new({required this.player, super.key});

  /// The player.
  final MusicPlayer player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final tracks = player.tracks;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    i18n('tv_music_queue_count', args: {'count': '${tracks.length}'}),
                    style: scale.font(TvTextSize.heading, weight: FontWeight.w600, color: palette.text),
                  ),
                ),
                const TvMusicModeButton(small: true),
              ],
            ),
            SizedBox(height: scale.px(12)),
            Expanded(
              child: ListView(
                children: [
                  for (final (index, track) in tracks.indexed)
                    TvSongRow(
                      key: ValueKey('tv-queue-$index'),
                      track: track,
                      number: index + 1,
                      playing: index == player.index,
                      autofocus: index == player.index,
                      onTap: () => unawaited(player.jumpTo(index)),
                      onLongPress: () => unawaited(
                        showSongMenu(context, ref: ref, track: track, place: MusicRowPlace.queue, queueIndex: index),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MusicProgress extends StatelessWidget {
  const new({required this.position, required this.duration, required this.onSeek, required this.onUp});

  final Duration position;
  final Duration duration;
  final void Function(int direction) onSeek;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final fraction = duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final time = scale.font(TvTextSize.small, color: palette.textSecondary).tabular;
    return TvFocusable(
      key: const ValueKey('tv-music-progress'),
      zoom: false,
      onKey: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            onSeek(-1);
          case LogicalKeyboardKey.arrowRight:
            onSeek(1);
          case LogicalKeyboardKey.arrowUp:
            onUp();
          default:
            return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      builder: (context, focused) => Row(
        children: [
          Text(videoClock(position), style: time),
          SizedBox(width: scale.px(16)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(scale.px(4)),
              child: SizedBox(
                height: scale.px(focused ? 12 : 6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: palette.highest),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction,
                      child: ColoredBox(color: palette.accent),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: scale.px(16)),
          Text(videoClock(duration), style: time),
        ],
      ),
    );
  }
}
