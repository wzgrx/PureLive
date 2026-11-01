import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/music_player.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/vod.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/screen_orientation.dart';
import 'package:pure_live/platform/system_ui.dart';
import 'package:pure_live/shared/audio/audio_focus.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';
import 'package:pure_live/shared/rooms/archive/archive_time.dart';
import 'package:pure_live/shared/rooms/archive/douyu_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive/huya_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive_playback.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_layer.dart';

/// Native on-demand playback with one shared control surface on every client:
/// exact seeking, allowed renditions, resume, same-session segments and comments.
class ArchivePlayerPage extends ConsumerStatefulWidget {
  /// Opens an official video hash id.
  const new({required this.videoId, this.archiveVideo, this.onRetire, super.key});

  /// The `/show/` hash id, never a media URL.
  final String videoId;

  /// Official Huya metadata selects the shared archive controller.
  final HuyaArchiveVideo? archiveVideo;

  /// Lets an owning live page await native cleanup before resuming.
  final ValueChanged<Future<void>>? onRetire;

  @override
  ConsumerState<ArchivePlayerPage> createState() => _ArchivePlayerPageState();
}

class _ArchivePlayerPageState extends ConsumerState<ArchivePlayerPage> with WidgetsBindingObserver {
  late final ArchivePlaybackController _controller;
  late final Future<void> _wallpaperHold;
  RoomAudioFocus? _audioFocus;
  Timer? _hide;
  bool _fullscreen = false;
  bool _controls = true;
  bool _changingFullscreen = false;
  bool _sidewaysBefore = false;
  bool _desktopAlreadyFullscreen = false;
  final _surface = FocusNode(debugLabel: 'douyu vod video');
  final _play = FocusNode(debugLabel: 'douyu vod play');
  double? _scrub;

  bool get _mobile => {TargetPlatform.android, TargetPlatform.iOS}.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = ref.read(storeProvider).settings;
    final session = ref.read(playbackSessionFactoryProvider)(
      config: MpvEngineConfig(
        platform: mpvPlatformOf(defaultTargetPlatform) ?? MpvPlatform.linux,
        hardwareDecoding: settings.get(Settings.enableCodec),
        customOutput: settings.get(Settings.customPlayerOutput),
        videoOutputDriver: settings.get(Settings.videoOutputDriver),
        hardwareDecoder: settings.get(Settings.videoHardwareDecoder),
        audioOutputDriver: settings.get(Settings.audioOutputDriver),
        androidCompatibility: settings.get(Settings.playerCompatMode),
        rtxVideoSuperResolution: settings.get(Settings.enableRtxVsr),
        volumeGainDb: settings.get(Settings.volumeBoostDb),
      ),
    );
    _controller = widget.archiveVideo == null
        ? DouyuVodController(
            source: ref.read(douyuVodProvider),
            session: session,
            progress: ref.read(douyuVodProgressProvider),
            initialVolume: settings.get(Settings.globalVolumeMute)
                ? 0
                : settings.get(_mobile ? Settings.defaultMobileVolume : Settings.defaultDesktopVolume),
          )
        : HuyaArchiveController(
            source: ref.read(huyaArchiveProvider),
            session: session,
            video: widget.archiveVideo!,
            progress: ref.read(huyaArchiveProgressProvider),
            initialVolume: settings.get(Settings.globalVolumeMute)
                ? 0
                : settings.get(_mobile ? Settings.defaultMobileVolume : Settings.defaultDesktopVolume),
          );
    if (SystemAudioFocus.available) {
      _audioFocus = RoomAudioFocus(
        session: session,
        port: SystemAudioFocus.instance,
        mayPlayNow: () => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        mixWithOthers: settings.get(Settings.allowAudioMixing),
        mixingChanges: settings.watch(Settings.allowAudioMixing),
      )..start();
    }
    unawaited(yieldMusicToOtherPlayback(ref));
    _wallpaperHold = TvWallpaperVideo.hold();
    unawaited(_wallpaperHold.then((_) => _controller.open(widget.videoId)));
    _controller.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (_controller.session.state.status == PlaybackStatus.completed) {
      _hide?.cancel();
      _controls = true;
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // This VOD page has no background notification/service. Do not let it play
    // invisibly; returning to the page leaves an intentional pause in place.
    if (_mobile && state == AppLifecycleState.paused) {
      unawaited(_controller.session.pause());
      unawaited(_controller.record());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hide?.cancel();
    unawaited(_audioFocus?.dispose());
    if (_fullscreen) unawaited(_restoreFullscreen());
    _controller.removeListener(_changed);
    _controller.dispose();
    widget.onRetire?.call(_controller.retirement);
    unawaited(TvWallpaperVideo.releaseAfter(Future.wait([_wallpaperHold, _controller.retirement])));
    _surface.dispose();
    _play.dispose();
    super.dispose();
  }

  void _showControls() {
    _hide?.cancel();
    setState(() => _controls = true);
    _hide = Timer(const Duration(seconds: 5), () {
      if (mounted && _controller.session.state.status == PlaybackStatus.playing && !_play.hasFocus) {
        setState(() => _controls = false);
        _surface.requestFocus();
      }
    });
  }

  Future<void> _danmakuSettings() async {
    _hide?.cancel();
    await showAppDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: i18n('douyu_vod_danmaku_settings'),
        wide: true,
        content: SizedBox(height: MediaQuery.sizeOf(context).height * 0.65, child: const DanmakuSettingsContent()),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('close')))],
      ),
    );
    if (mounted) _showControls();
  }

  Future<void> _toggleFullscreen() async {
    if (_changingFullscreen) return;
    _changingFullscreen = true;
    try {
      if (_fullscreen) {
        await _restoreFullscreen();
        if (mounted) setState(() => _fullscreen = false);
      } else {
        _sidewaysBefore = MediaQuery.orientationOf(context) == Orientation.landscape;
        _desktopAlreadyFullscreen = DesktopWindow.fullScreen.value;
        setState(() => _fullscreen = true);
        if (_mobile) {
          await ScreenOrientation.landscape();
          if (mounted && _fullscreen) await SystemUiVisibility.fullscreen();
        } else {
          await DesktopWindow.setFullScreen(on: true);
        }
      }
    } finally {
      _changingFullscreen = false;
    }
  }

  Future<void> _restoreFullscreen() async {
    if (_mobile) {
      await SystemUiVisibility.restore();
      await ScreenOrientation.restore(sideways: _sidewaysBefore);
    } else if (!_desktopAlreadyFullscreen) {
      await DesktopWindow.setFullScreen(on: false);
    }
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && _fullscreen) {
      unawaited(_toggleFullscreen());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.mediaPlayPause) {
      unawaited(_controller.session.togglePlayPause());
      _showControls();
      return KeyEventResult.handled;
    }
    if (!_controls && {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight}.contains(key)) {
      final step = Duration(seconds: key == LogicalKeyboardKey.arrowLeft ? -10 : 10);
      unawaited(_controller.seek(_controller.position + step));
      return KeyEventResult.handled;
    }
    if (!_controls &&
        {
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.select,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.arrowUp,
        }.contains(key)) {
      _showControls();
      _play.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.session.state;
    final video = _controller.video;
    final duration = state.duration > Duration.zero ? state.duration : video?.duration ?? Duration.zero;
    final maximum = duration.inMilliseconds.toDouble();
    final position = (_scrub ?? _controller.position.inMilliseconds.toDouble()).clamp(0.0, maximum > 0 ? maximum : 1.0);
    final look = danmakuLookOf(ref);
    final videoArea = Focus(
      onKeyEvent: _key,
      focusNode: _surface,
      autofocus: true,
      child: MouseRegion(
        onHover: (_) => _showControls(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _showControls();
            _play.requestFocus();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: OnVideoColors.ground),
              LiveVideoView(
                session: _controller.session,
                outputSize: !_mobile,
                keepScreenOn: watchSetting(ref, Settings.enableScreenKeepOn),
              ),
              if (_controller.supportsDanmaku)
                DanmakuFrameRateBuilder(
                  builder: (context, fps, refreshRate) => IgnorePointer(
                    child: DanmakuOverlay(
                      messages: _controller.messages,
                      retractions: _controller.retractions,
                      look: look,
                      running: state.status == PlaybackStatus.playing,
                      visible: _controller.danmakuVisible,
                      maxVisible: watchSetting(ref, Settings.danmakuMaxVisibleCount),
                      fps: fps,
                      refreshRate: refreshRate,
                      giftClearance: const EdgeInsets.only(top: 48, bottom: 130),
                    ),
                  ),
                ),
              if (_controller.busy || {PlaybackStatus.opening, PlaybackStatus.buffering}.contains(state.status))
                const Center(child: CircularProgressIndicator()),
              if (_controller.error != null || state.status == PlaybackStatus.error)
                Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(i18n(_controller.error is NeedsLogin ? 'douyu_vod_login' : 'douyu_vod_play_failed')),
                          TextButton(
                            onPressed: _controller.busy
                                ? null
                                : () => unawaited(
                                    _controller.open(video?.id ?? widget.videoId, start: _controller.position),
                                  ),
                            child: Text(i18n('retry')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_controls)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: ColoredBox(
                    color: OnVideoColors.dim,
                    child: SafeArea(
                      bottom: false,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: i18n('back'),
                            color: OnVideoColors.foreground,
                            icon: const Icon(AppIcons.back),
                            onPressed: () => _fullscreen ? unawaited(_toggleFullscreen()) : Navigator.of(context).pop(),
                          ),
                          Expanded(
                            child: Text(
                              video?.title ??
                                  i18n(widget.archiveVideo == null ? 'douyu_vod_title' : 'huya_replay_title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.t14.copyWith(
                                color: OnVideoColors.foreground,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_controls)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Theme(
                    data: ThemeData.dark(useMaterial3: true),
                    child: Material(
                      color: OnVideoColors.panel,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Text(vodTime(Duration(milliseconds: position.round()))),
                                  Expanded(
                                    child: Slider(
                                      key: const ValueKey('vod-seek'),
                                      value: position,
                                      max: maximum > 0 ? maximum : 1,
                                      onChangeStart: _controller.busy || maximum <= 0
                                          ? null
                                          : (value) {
                                              _hide?.cancel();
                                              setState(() => _scrub = value);
                                            },
                                      onChanged: _controller.busy || maximum <= 0
                                          ? null
                                          : (value) => setState(() => _scrub = value),
                                      onChangeEnd: (value) {
                                        setState(() => _scrub = null);
                                        unawaited(_controller.seek(Duration(milliseconds: value.round())));
                                        _showControls();
                                      },
                                    ),
                                  ),
                                  Text(vodTime(duration)),
                                ],
                              ),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    IconButton(
                                      key: const ValueKey('vod-play-pause'),
                                      focusNode: _play,
                                      tooltip: i18n(state.status == PlaybackStatus.playing ? 'pause' : 'play'),
                                      onPressed: _controller.busy
                                          ? null
                                          : () {
                                              if (state.status == PlaybackStatus.completed) {
                                                unawaited(_controller.open(video!.id, start: Duration.zero));
                                              } else {
                                                unawaited(_controller.session.togglePlayPause());
                                              }
                                              _showControls();
                                            },
                                      icon: Icon(
                                        state.status == PlaybackStatus.playing ? AppIcons.pause : AppIcons.play,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: i18n('douyu_vod_rewind'),
                                      onPressed: () => unawaited(
                                        _controller.seek(_controller.position - const Duration(seconds: 10)),
                                      ),
                                      icon: const Icon(AppIcons.vodRewind),
                                    ),
                                    IconButton(
                                      tooltip: i18n('douyu_vod_forward'),
                                      onPressed: () => unawaited(
                                        _controller.seek(_controller.position + const Duration(seconds: 10)),
                                      ),
                                      icon: const Icon(AppIcons.vodForward),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: i18n('douyu_vod_quality'),
                                      enabled: !_controller.busy,
                                      initialValue: _controller.qualityId,
                                      onSelected: (id) => unawaited(_controller.selectQuality(id)),
                                      itemBuilder: (_) => [
                                        for (final quality in _controller.qualities)
                                          PopupMenuItem(
                                            value: quality.id,
                                            enabled: quality.playable,
                                            child: Text(
                                              '${quality.label}${quality.playable ? '' : ' (${i18n('douyu_vod_restricted')})'}',
                                            ),
                                          ),
                                      ],
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                          _controller.qualities
                                                  .where((q) => q.id == _controller.qualityId)
                                                  .firstOrNull
                                                  ?.label ??
                                              i18n('douyu_vod_quality'),
                                        ),
                                      ),
                                    ),
                                    if (_controller.supportsDanmaku)
                                      IconButton(
                                        tooltip: i18n('douyu_vod_danmaku'),
                                        onPressed: _controller.toggleDanmaku,
                                        icon: DanmakuIcon(
                                          _controller.danmakuVisible ? DanmakuIconKind.on : DanmakuIconKind.off,
                                        ),
                                      ),
                                    if (_controller.supportsDanmaku)
                                      IconButton(
                                        key: const ValueKey('vod-danmaku-settings'),
                                        tooltip: i18n('douyu_vod_danmaku_settings'),
                                        onPressed: () => unawaited(_danmakuSettings()),
                                        icon: const DanmakuIcon(DanmakuIconKind.settings),
                                      ),
                                    IconButton(
                                      tooltip: i18n('volume'),
                                      onPressed: () =>
                                          unawaited(_controller.session.setVolume(state.volume > 0 ? 0 : 1)),
                                      icon: Icon(state.volume > 0 ? AppIcons.volumeHigh : AppIcons.volumeMuted),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: Slider(
                                        value: state.volume.clamp(0, 1),
                                        onChanged: (value) => unawaited(_controller.session.setVolume(value)),
                                      ),
                                    ),
                                    IconButton(
                                      key: const ValueKey('vod-fullscreen'),
                                      tooltip: i18n('fullscreen'),
                                      onPressed: () => unawaited(_toggleFullscreen()),
                                      icon: Icon(_fullscreen ? AppIcons.exitFullscreen : AppIcons.fullscreen),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return PopScope<void>(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _fullscreen) unawaited(_toggleFullscreen());
      },
      child: Scaffold(
        body: _fullscreen
            ? videoArea
            : SafeArea(
                child: Column(
                  children: [
                    Expanded(child: videoArea),
                    if (_controller.segments.length > 1)
                      SizedBox(
                        height: 72,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          scrollDirection: Axis.horizontal,
                          itemCount: _controller.segments.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, index) {
                            final segment = _controller.segments[index];
                            return OutlinedButton(
                              onPressed: _controller.busy || segment.id == video?.id
                                  ? null
                                  : () => unawaited(_controller.open(segment.id)),
                              child: Text(i18n('douyu_vod_segment', args: {'index': '${index + 1}'})),
                            );
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
