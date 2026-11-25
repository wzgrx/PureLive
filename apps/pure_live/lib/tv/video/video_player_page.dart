import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/music_player.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/video/video_comments.dart';
import 'package:pure_live/tv/video/video_source.dart';
import 'package:pure_live/tv/video/video_store.dart';
import 'package:pure_live/tv/video/video_widgets.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_layer.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// The steps ←→ seek by while held or pressed again soon (pure_live_TV:
/// 10 s, faster to 60 s).
const List<Duration> tvVideoSeekSteps = [
  Duration(seconds: 10),
  Duration(seconds: 20),
  Duration(seconds: 30),
  Duration(seconds: 60),
];

/// The playback rates offered (pure_live_TV cycles them).
const List<double> tvVideoRates = [1, 1.25, 1.5, 2, 0.75];

/// The qualities offered when the stream does not list its own.
const List<int> tvVideoQualities = [116, 80, 64, 32, 16];

/// How often the position is recorded and reported (heartbeat).
const Duration tvVideoReportEvery = Duration(seconds: 15);

/// The plan of [streams] at [qn]: a DASH video rendition's lines (its audio
/// rendition goes with each line), else the muxed segment's.
({PlaybackPlan plan, ExternalAudioFor? audio}) videoPlanOf(VodStreams streams, int qn, {Duration? start}) {
  if (streams.isDash) {
    final video = streams.videoFor(qn);
    final audio = streams.bestAudio();
    final lines = video == null ? <LivePlayLine>[] : streams.linesOf(video);
    return (
      plan: PlaybackPlan.of(LivePlayUrlResolution.lines(lines), onDemand: true, start: start),
      audio: audio == null ? null : (_) => ExternalAudio(Uri.parse(audio.url)),
    );
  }
  final segment = streams.segments.firstOrNull;
  return (
    plan: PlaybackPlan.of(
      LivePlayUrlResolution.lines(segment == null ? const [] : streams.linesOfSegment(segment)),
      onDemand: true,
      start: start,
    ),
    audio: null,
  );
}

/// Which side panel is open.
enum _Panel { none, comments, danmaku, parts }

/// The video player (A17.6 c12–c15): the picture with on-demand danmaku
/// and subtitles; OK shows the controls (two groups, no seek buttons, c12),
/// ←→ seek (faster when pressed again soon), ↑↓ change part or episode,
/// Back closes a panel, then the controls, then the page. Quality is a
/// choice next to its button (c13), the rate cycles, the danmaku settings
/// and the comments are panels on the right (c14, c15), so the picture
/// stays visible. The position is kept here and reported to the cloud
/// history every [tvVideoReportEvery] (heartbeat); a failure there never
/// stops playback. The video background is held still meanwhile.
class TvVideoPlayerPage extends ConsumerStatefulWidget {
  /// Plays [items] from [index], at [start] when given.
  const new({required this.items, required this.index, this.start, super.key});

  /// The parts or episodes.
  final List<VideoItem> items;

  /// The one played first.
  final int index;

  /// Where to start.
  final Duration? start;

  @override
  ConsumerState<TvVideoPlayerPage> createState() => _TvVideoPlayerPageState();
}

class _TvVideoPlayerPageState extends ConsumerState<TvVideoPlayerPage> {
  late final PlaybackSession _session = ref.read(playbackSessionFactoryProvider)();
  late final VideoSource _source = ref.read(videoSourceProvider);
  late final VideoStore _store = ref.read(videoStoreProvider);
  late int _index = widget.index;
  late int _qn = _store.prefs.quality;
  VodStreams? _streams;
  VodPlayerInfo? _info;
  Object? _error;
  bool _controls = true;
  _Panel _panel = _Panel.none;
  bool _danmakuOn = true;
  bool _subtitlesOn = true;
  double _rate = 1;
  Timer? _hide;
  Timer? _tick;
  Timer? _report;
  DateTime? _lastSeek;
  int _seekStep = 0;
  StreamSubscription<PlaybackState>? _states;
  final FocusNode _surface = FocusNode(debugLabel: 'tv video surface');
  final FocusNode _play = FocusNode(debugLabel: 'tv video play');
  final StreamController<LiveMessage> _flying = StreamController.broadcast();
  final StreamController<LiveRetraction> _retractions = StreamController.broadcast();
  List<VodDanmaku> _danmaku = const [];
  final Set<int> _segments = {};
  Duration _lastPosition = Duration.zero;
  int _cursor = 0;
  List<VodSubtitleCue> _cues = const [];
  String _cue = '';

  late final Future<void> _wallpaperReady;
  int _openRevision = 0;

  VideoItem get _item => widget.items[_index];

  @override
  void initState() {
    super.initState();
    _wallpaperReady = TvWallpaperVideo.hold();
    unawaited(yieldMusicToOtherPlayback(ref));
    _danmakuOn = _store.prefs.danmaku;
    _subtitlesOn = _store.prefs.subtitles;
    _states = _session.states.listen(_stateChanged);
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
    _report = Timer.periodic(tvVideoReportEvery, (_) => unawaited(_record()));
    unawaited(_open(start: widget.start));
    _showControls();
  }

  @override
  void dispose() {
    unawaited(_record());
    _hide?.cancel();
    _tick?.cancel();
    _report?.cancel();
    unawaited(_states?.cancel());
    unawaited(TvWallpaperVideo.releaseAfter(_session.waitForResourceRelease()));
    unawaited(_flying.close());
    unawaited(_retractions.close());
    _surface.dispose();
    _play.dispose();
    super.dispose();
  }

  Future<void> _open({Duration? start}) async {
    final revision = ++_openRevision;
    await _wallpaperReady;
    if (!mounted || revision != _openRevision) return;
    final item = _item;
    setState(() {
      _error = null;
      _streams = null;
      _danmaku = const [];
      _segments.clear();
      _cursor = 0;
      _cues = const [];
      _cue = '';
    });
    try {
      final streams = await _source.streams(item, qn: _qn);
      if (!mounted || item != _item) return;
      final resume = start ?? _resumeOf(item);
      final (:plan, :audio) = videoPlanOf(streams, _qn, start: resume);
      setState(() => _streams = streams);
      await _session.open(PlaybackRequest(site: vodSite, plan: plan, audio: audio));
      if (_rate != 1) await _session.setRate(_rate);
      unawaited(_loadInfo(item));
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Duration? _resumeOf(VideoItem item) {
    final progress = _store.progressOf(item.progressKey);
    if (progress == null || progress.cid != item.cid) return null;
    return progress.position > const Duration(seconds: 5) ? progress.position : null;
  }

  Future<void> _loadInfo(VideoItem item) async {
    try {
      final info = await _source.playerInfo(item);
      if (!mounted || item != _item) return;
      setState(() => _info = info);
      final track = info.subtitles.firstOrNull;
      if (track != null) {
        final cues = await _source.subtitleCues(track);
        if (mounted && item == _item) setState(() => _cues = cues);
      }
    } on Object {
      // Subtitles and the viewers are extras.
    }
  }

  void _stateChanged(PlaybackState state) {
    if (!mounted) return;
    setState(() {});
    if (state.status == PlaybackStatus.completed) {
      unawaited(_record());
      if (_store.prefs.autoNext && _index + 1 < widget.items.length) _go(_index + 1);
    }
  }

  /// Danmaku of the passed time go up; a seek starts over from there;
  /// segments load as the time reaches them. The subtitle follows.
  void _onTick() {
    if (!mounted) return;
    final state = _session.state;
    final position = state.position;
    if (_danmakuOn && state.status == PlaybackStatus.playing) {
      final segment = position.inMilliseconds ~/ danmakuSegmentLength.inMilliseconds + 1;
      if (!_segments.contains(segment)) unawaited(_loadSegment(segment));
      final jumped = position < _lastPosition || position - _lastPosition > const Duration(seconds: 2);
      if (jumped) _cursor = _firstAfter(position);
      while (_cursor < _danmaku.length && _danmaku[_cursor].progress <= position) {
        final danmaku = _danmaku[_cursor++];
        if (!jumped) {
          _flying.add(
            LiveMessage(
              type: LiveMessageType.chat,
              userName: '',
              message: danmaku.text,
              color: LiveMessageColor((danmaku.color >> 16) & 0xFF, (danmaku.color >> 8) & 0xFF, danmaku.color & 0xFF),
            ),
          );
        }
      }
    }
    _lastPosition = position;
    var cue = '';
    if (_subtitlesOn) {
      for (final item in _cues) {
        if (item.start <= position && position < item.end) {
          cue = item.text;
          break;
        }
      }
    }
    if (cue != _cue) setState(() => _cue = cue);
  }

  int _firstAfter(Duration position) {
    var low = 0;
    var high = _danmaku.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_danmaku[mid].progress <= position) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  Future<void> _loadSegment(int segment) async {
    _segments.add(segment);
    final item = _item;
    try {
      final more = await _source.danmakuSegment(item, segment);
      if (!mounted || item != _item) return;
      final all = [..._danmaku, ...more]..sort((a, b) => a.progress.compareTo(b.progress));
      _danmaku = all;
      _cursor = _firstAfter(_session.state.position);
    } on Object {
      // No danmaku is no failure.
    }
  }

  Future<void> _record() async {
    final state = _session.state;
    if (state.duration <= Duration.zero) return;
    final item = _item;
    await _store.record(item, state.position, state.duration);
    if (!_source.signedIn) return;
    try {
      await _source.reportProgress(item, state.position);
    } on Object {
      // The cloud history is best effort.
    }
  }

  void _go(int index) {
    if (index < 0 || index >= widget.items.length || index == _index) return;
    unawaited(_record());
    setState(() {
      _index = index;
      _info = null;
    });
    unawaited(_open());
    _showControls();
  }

  void _showControls() {
    _hide?.cancel();
    if (!_controls) setState(() => _controls = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _panel == _Panel.none && !_play.hasFocus) _play.requestFocus();
    });
    _hide = Timer(const Duration(seconds: 5), _hideControls);
  }

  void _hideControls() {
    if (!mounted || _panel != _Panel.none) return;
    if (_session.state.status != PlaybackStatus.playing) return;
    setState(() => _controls = false);
    _surface.requestFocus();
  }

  void _seek(int direction) {
    final now = DateTime.now();
    final last = _lastSeek;
    _seekStep = last != null && now.difference(last) < const Duration(milliseconds: 800)
        ? (_seekStep + 1).clamp(0, tvVideoSeekSteps.length - 1)
        : 0;
    _lastSeek = now;
    final state = _session.state;
    var target = state.position + tvVideoSeekSteps[_seekStep] * direction;
    if (target < Duration.zero) target = Duration.zero;
    if (state.duration > Duration.zero && target > state.duration) target = state.duration;
    unawaited(_session.seek(target));
    setState(() {});
  }

  KeyEventResult _surfaceKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _seek(-1);
      case LogicalKeyboardKey.arrowRight:
        _seek(1);
      case LogicalKeyboardKey.arrowUp:
        _go(_index - 1);
      case LogicalKeyboardKey.arrowDown:
        _go(_index + 1);
      case LogicalKeyboardKey.select || LogicalKeyboardKey.enter || LogicalKeyboardKey.contextMenu:
        _showControls();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Back: a panel, then the controls, then the page.
  void _back() {
    if (_panel != _Panel.none) {
      setState(() => _panel = _Panel.none);
      _showControls();
      return;
    }
    if (_controls && _session.state.status == PlaybackStatus.playing) {
      _hide?.cancel();
      setState(() => _controls = false);
      _surface.requestFocus();
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _chooseQuality() async {
    final streams = _streams;
    final offered = streams == null || streams.qualities.isEmpty
        ? [for (final qn in tvVideoQualities) VodQuality(qn: qn, label: VodQuality.labelOf(qn))]
        : streams.qualities;
    final qn = await showTvChoice<int>(
      context,
      title: i18n('tv_video_quality'),
      current: streams?.quality ?? _qn,
      options: [
        for (final quality in offered)
          TvChoice(
            value: quality.qn,
            label: quality.label,
            description: quality.needsVip
                ? i18n('tv_video_vip')
                : quality.needsLogin
                ? i18n('tv_video_login_needed')
                : null,
          ),
      ],
    );
    if (qn == null || qn == _qn || !mounted) return;
    _qn = qn;
    unawaited(_store.setPrefs(_store.prefs.copyWith(quality: qn)));
    unawaited(_open(start: _session.state.position));
  }

  void _cycleRate() {
    final next = tvVideoRates[(tvVideoRates.indexOf(_rate) + 1) % tvVideoRates.length];
    setState(() => _rate = next);
    unawaited(_session.setRate(next));
    AppNavigator.toast(i18n('tv_video_rate_toast', args: {'rate': '${next}x'}));
  }

  void _toggleDanmaku() {
    setState(() => _danmakuOn = !_danmakuOn);
    unawaited(_store.setPrefs(_store.prefs.copyWith(danmaku: _danmakuOn)));
  }

  void _toggleSubtitles() {
    setState(() => _subtitlesOn = !_subtitlesOn);
    unawaited(_store.setPrefs(_store.prefs.copyWith(subtitles: _subtitlesOn)));
  }

  void _openPanel(_Panel panel) {
    _hide?.cancel();
    setState(() => _panel = panel);
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final state = _session.state;
    final playing = state.status == PlaybackStatus.playing;
    final item = _item;
    final error = _error;
    final online = _info?.onlineCount ?? 0;
    final position = state.position;
    final duration = state.duration > Duration.zero ? state.duration : item.duration;
    final fraction = duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final status = state.status;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        key: const ValueKey('tv-video-player'),
        backgroundColor: OnVideoColors.ground,
        body: Focus(
          focusNode: _surface,
          autofocus: true,
          onKeyEvent: _controls ? null : _surfaceKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LiveVideoView(session: _session),
              DanmakuOverlay(
                messages: _flying.stream,
                retractions: _retractions.stream,
                look: danmakuLookOf(ref),
                visible: _danmakuOn,
                running: playing,
                maxVisible: watchSetting(ref, Settings.danmakuMaxVisibleCount),
              ),
              if (_cue.isNotEmpty)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: scale.px(_controls ? 220 : 64)),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: OnVideoColors.scrim,
                        borderRadius: BorderRadius.circular(scale.px(8)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: scale.px(16), vertical: scale.px(6)),
                        child: Text(
                          _cue,
                          key: const ValueKey('tv-video-subtitle'),
                          textAlign: TextAlign.center,
                          style: scale.font(TvTextSize.heading, color: OnVideoColors.foreground, height: 1.4),
                        ),
                      ),
                    ),
                  ),
                ),
              if (error != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        describeLoadError(error),
                        textAlign: TextAlign.center,
                        style: scale.font(TvTextSize.body, color: OnVideoColors.foreground),
                      ),
                      SizedBox(height: scale.px(16)),
                      TvButton(
                        key: const ValueKey('tv-video-retry'),
                        label: i18n('retry'),
                        autofocus: true,
                        onTap: () => unawaited(_open(start: position)),
                      ),
                    ],
                  ),
                )
              else if (status == PlaybackStatus.opening || status == PlaybackStatus.buffering || _streams == null)
                const Center(child: CircularProgressIndicator()),
              // The bottom edge's progress line while the controls are away.
              if (!_controls)
                Align(
                  alignment: Alignment.bottomLeft,
                  child: FractionallySizedBox(
                    key: const ValueKey('tv-video-edge-progress'),
                    widthFactor: fraction,
                    child: SizedBox(
                      height: scale.px(4),
                      child: ColoredBox(color: palette.accent),
                    ),
                  ),
                ),
              if (_controls) ...[
                Align(
                  alignment: Alignment.topCenter,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [OnVideoColors.panel, OnVideoColors.clear],
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(scale.px(96), scale.px(40), scale.px(96), scale.px(64)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title == item.archiveTitle || item.archiveTitle.isEmpty
                                  ? item.title
                                  : '${item.archiveTitle} · ${item.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: scale.font(
                                TvTextSize.title,
                                weight: FontWeight.w600,
                                color: OnVideoColors.foreground,
                              ),
                            ),
                          ),
                          if (online > 0)
                            Text(
                              i18n('tv_video_online', args: {'count': videoCount(online)}),
                              key: const ValueKey('tv-video-online'),
                              style: scale.font(TvTextSize.small, color: OnVideoColors.secondary),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [OnVideoColors.panel, OnVideoColors.clear],
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(scale.px(48), scale.px(64), scale.px(48), scale.px(40)),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ProgressBar(position: position, duration: duration, onSeek: _seek),
                          SizedBox(height: scale.px(20)),
                          FocusTraversalGroup(
                            child: Row(
                              children: [
                                TvButton(
                                  key: const ValueKey('tv-video-play'),
                                  focusNode: _play,
                                  icon: playing ? AppIcons.pause : AppIcons.play,
                                  label: i18n(playing ? 'tv_video_pause' : 'tv_video_play'),
                                  onTap: () {
                                    unawaited(_session.togglePlayPause());
                                    _showControls();
                                  },
                                ),
                                SizedBox(width: scale.px(8)),
                                TvButton(
                                  key: const ValueKey('tv-video-previous'),
                                  small: true,
                                  label: i18n('tv_video_previous'),
                                  onTap: _index > 0 ? () => _go(_index - 1) : null,
                                ),
                                SizedBox(width: scale.px(8)),
                                TvButton(
                                  key: const ValueKey('tv-video-next'),
                                  small: true,
                                  label: i18n('tv_video_next'),
                                  onTap: _index + 1 < widget.items.length ? () => _go(_index + 1) : null,
                                ),
                                SizedBox(width: scale.px(24)),
                                // The second group: its own scroll when a large text size would not
                                // fit it (it fits one row at 1080p).
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    reverse: true,
                                    clipBehavior: Clip.none,
                                    child: Row(
                                      children: [
                                        TvButton(
                                          key: const ValueKey('tv-video-quality'),
                                          small: true,
                                          label: _streams == null
                                              ? i18n('tv_video_quality')
                                              : VodQuality.labelOf(_streams!.quality),
                                          onTap: () => unawaited(_chooseQuality()),
                                        ),
                                        SizedBox(width: scale.px(8)),
                                        TvButton(
                                          key: const ValueKey('tv-video-rate'),
                                          small: true,
                                          label: '${_rate}x',
                                          onTap: _cycleRate,
                                        ),
                                        SizedBox(width: scale.px(8)),
                                        TvButton(
                                          key: const ValueKey('tv-video-danmaku'),
                                          small: true,
                                          icon: _danmakuOn ? TvIcons.danmakuOn : TvIcons.danmakuOff,
                                          label: i18n(_danmakuOn ? 'tv_video_danmaku_on' : 'tv_video_danmaku_off'),
                                          onTap: _toggleDanmaku,
                                        ),
                                        SizedBox(width: scale.px(8)),
                                        TvButton(
                                          key: const ValueKey('tv-video-danmaku-settings'),
                                          small: true,
                                          label: i18n('tv_video_danmaku_settings'),
                                          onTap: () => _openPanel(_Panel.danmaku),
                                        ),
                                        if (_cues.isNotEmpty) ...[
                                          SizedBox(width: scale.px(12)),
                                          TvButton(
                                            key: const ValueKey('tv-video-subtitles'),
                                            small: true,
                                            label: i18n(
                                              _subtitlesOn ? 'tv_video_subtitles_on' : 'tv_video_subtitles_off',
                                            ),
                                            onTap: _toggleSubtitles,
                                          ),
                                        ],
                                        SizedBox(width: scale.px(8)),
                                        TvButton(
                                          key: const ValueKey('tv-video-comments'),
                                          small: true,
                                          label: i18n('tv_video_comments'),
                                          onTap: item.aid > 0 ? () => _openPanel(_Panel.comments) : null,
                                        ),
                                        if (widget.items.length > 1) ...[
                                          SizedBox(width: scale.px(12)),
                                          TvButton(
                                            key: const ValueKey('tv-video-parts'),
                                            small: true,
                                            label: i18n('tv_video_parts'),
                                            onTap: () => _openPanel(_Panel.parts),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (_panel != _Panel.none)
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    key: ValueKey('tv-video-panel-${_panel.name}'),
                    width: scale.px(800),
                    color: palette.raised.withValues(alpha: 0.96),
                    padding: EdgeInsets.all(scale.px(24)),
                    child: switch (_panel) {
                      _Panel.comments => TvVideoComments(oid: item.aid, autofocus: true),
                      _Panel.danmaku => FocusScope(
                        autofocus: true,
                        child: DanmakuSettingsContent(hint: i18n('danmaku_settings_live_hint')),
                      ),
                      _Panel.parts => _PartsList(
                        items: widget.items,
                        current: _index,
                        onPick: (index) {
                          setState(() => _panel = _Panel.none);
                          _go(index);
                        },
                      ),
                      _Panel.none => const SizedBox.shrink(),
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The progress bar: focusable, ←→ seek; the times on both ends.
class _ProgressBar extends StatelessWidget {
  const new({required this.position, required this.duration, required this.onSeek});

  final Duration position;
  final Duration duration;
  final void Function(int direction) onSeek;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final fraction = duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final time = scale.font(TvTextSize.small, color: OnVideoColors.foreground).tabular;
    return TvFocusable(
      key: const ValueKey('tv-video-progress-bar'),
      ring: false,
      zoom: false,
      onKey: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          onSeek(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onSeek(1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
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
                    const ColoredBox(color: OnVideoColors.scrimMid),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction,
                      child: ColoredBox(color: focused ? OnVideoColors.foreground : palette.accent),
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

/// The parts or episodes in the panel; OK plays one.
class _PartsList extends StatelessWidget {
  const new({required this.items, required this.current, required this.onPick});

  final List<VideoItem> items;
  final int current;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      for (final (index, item) in items.indexed)
        TvOptionRow(
          key: ValueKey('tv-video-part-$index'),
          label: item.isEpisode ? item.title : 'P${item.page}  ${item.title}',
          current: index == current,
          autofocus: index == current,
          onTap: () => onPick(index),
        ),
    ],
  );
}
