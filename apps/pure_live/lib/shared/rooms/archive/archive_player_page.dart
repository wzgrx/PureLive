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
import 'package:pure_live/app/ui_mode.dart';
import 'package:pure_live/app/vod.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/screen_orientation.dart';
import 'package:pure_live/platform/system_ui.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/audio/audio_focus.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';
import 'package:pure_live/shared/rooms/archive/archive_rate_dialog.dart';
import 'package:pure_live/shared/rooms/archive/archive_recording.dart';
import 'package:pure_live/shared/rooms/archive/archive_time.dart';
import 'package:pure_live/shared/rooms/archive/bilibili_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive/douyu_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive/huya_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive_playback.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_layer.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

enum _ArchivePanel { speed, quality, episodes, more, danmaku }

/// Native on-demand playback with one shared control surface on every client:
/// exact seeking, allowed renditions, resume, same-session segments and comments.
class ArchivePlayerPage extends ConsumerStatefulWidget {
  /// Opens an official video hash id.
  const new({
    required this.videoId,
    this.archiveVideo,
    this.bilibiliVideo,
    this.recordings = const [],
    this.room,
    this.onProgress,
    this.onRetire,
    super.key,
  });

  /// The `/show/` hash id, never a media URL.
  final String videoId;

  /// Official Huya metadata selects the shared archive controller.
  final HuyaArchiveVideo? archiveVideo;

  /// Public Bilibili metadata selects its own parts and media contract.
  final VodArchive? bilibiliVideo;

  /// Sibling metadata already loaded by the creator catalog.
  final List<ArchiveRecording> recordings;

  /// Creator identity supplied by the invoking room, never persisted here.
  final LiveRoom? room;

  /// Reports known part identity to the owning catalog without persisting media metadata.
  final void Function(String id, int? part, Duration position)? onProgress;

  /// Lets an owning live page await native cleanup before resuming.
  final ValueChanged<Future<void>>? onRetire;

  @override
  ConsumerState<ArchivePlayerPage> createState() => _ArchivePlayerPageState();
}

class _ArchivePlayerPageState extends ConsumerState<ArchivePlayerPage> with WidgetsBindingObserver {
  late ArchivePlaybackController _controller;
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
  _ArchivePanel? _panel;
  FocusNode? _returnFocus;
  bool _keyboardNavigation = false;
  bool _embeddedLandscape = false;
  bool _swapping = false;
  int _tab = 0;
  PlaybackStatus? _lastStatus;
  ArchiveRecording? _selected;
  Future<void> _retiring = Future.value();
  final GlobalKey _videoKey = GlobalKey(debugLabel: 'archive-video-output');
  final _contentScroll = ScrollController();
  final _panelScope = FocusScopeNode(debugLabel: 'archive-panel');

  bool get _mobile => {TargetPlatform.android, TargetPlatform.iOS}.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selected = widget.recordings.where((v) => v.id == widget.videoId).firstOrNull;
    _createController(_selected?.video ?? widget.bilibiliVideo ?? widget.archiveVideo);
    unawaited(yieldMusicToOtherPlayback(ref));
    _wallpaperHold = TvWallpaperVideo.hold();
    unawaited(
      _wallpaperHold.then((_) {
        if (mounted) return _controller.open(widget.videoId);
      }),
    );
  }

  void _createController(Object? selected) {
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
    _controller = selected is VodArchive
        ? BilibiliArchiveController(
            source: ref.read(bilibiliReplayProvider),
            session: session,
            progress: ref.read(bilibiliReplayProgressProvider),
            initialVolume: settings.get(Settings.globalVolumeMute)
                ? 0
                : settings.get(_mobile ? Settings.defaultMobileVolume : Settings.defaultDesktopVolume),
          )
        : selected is! HuyaArchiveVideo
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
            video: selected,
            progress: ref.read(huyaArchiveProgressProvider),
            initialVolume: settings.get(Settings.globalVolumeMute)
                ? 0
                : settings.get(_mobile ? Settings.defaultMobileVolume : Settings.defaultDesktopVolume),
          );
    _controller.addListener(_changed);
    if (SystemAudioFocus.available) {
      _audioFocus = RoomAudioFocus(
        session: session,
        port: SystemAudioFocus.instance,
        mayPlayNow: () => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        mixWithOthers: settings.get(Settings.allowAudioMixing),
        mixingChanges: settings.watch(Settings.allowAudioMixing),
      )..start();
    }
  }

  void _changed() {
    if (!mounted) return;
    final status = _controller.session.state.status;
    if (_controller.error != null ||
        status == PlaybackStatus.paused ||
        status == PlaybackStatus.completed ||
        status == PlaybackStatus.error) {
      _hide?.cancel();
      _controls = true;
    } else if (status == PlaybackStatus.playing && _lastStatus != status) {
      _scheduleHide();
    }
    _lastStatus = status;
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Leaving a landscape embed must not suppress the next rotation.
    if (MediaQuery.orientationOf(context) == Orientation.portrait) _embeddedLandscape = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    _reportProgress();
    _controller.removeListener(_changed);
    _controller.dispose();
    final retired = Future.wait<void>([_retiring, _controller.retirement]).then((_) {});
    widget.onRetire?.call(retired);
    unawaited(TvWallpaperVideo.releaseAfter(Future.wait([_wallpaperHold, retired])));
    _surface.dispose();
    _play.dispose();
    _contentScroll.dispose();
    _panelScope.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (_panel != null || _scrub != null || _controller.session.state.status != PlaybackStatus.playing) return;
    _hide = Timer(const Duration(seconds: 3), () {
      if (!mounted ||
          _panel != null ||
          _scrub != null ||
          _keyboardNavigation ||
          _controller.session.state.status != PlaybackStatus.playing) {
        return;
      }
      setState(() => _controls = false);
      _surface.requestFocus();
    });
  }

  void _showControls() {
    if (!mounted) return;
    setState(() => _controls = true);
    _scheduleHide();
  }

  void _openPanel(_ArchivePanel panel) {
    _hide?.cancel();
    _returnFocus = FocusManager.instance.primaryFocus;
    setState(() {
      _panel = panel;
      _controls = true;
    });
  }

  void _closePanel() {
    final previous = _returnFocus;
    _returnFocus = null;
    setState(() => _panel = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (previous?.context != null) {
        previous!.requestFocus();
      } else {
        _surface.requestFocus();
      }
    });
    _scheduleHide();
  }

  Future<void> _applyRate(double rate) async {
    final controller = _controller;
    final ok = await controller.setRate(rate);
    if (!mounted || !identical(controller, _controller)) return;
    if (!ok) AppNavigator.toast(i18n('archive_rate_unavailable'));
    if (_panel == _ArchivePanel.speed) _closePanel();
  }

  Future<void> _toggleFullscreen() async {
    if (_changingFullscreen) return;
    _changingFullscreen = true;
    try {
      if (_fullscreen) {
        await _restoreFullscreen();
        if (mounted) {
          setState(() {
            _fullscreen = false;
            _embeddedLandscape = true;
          });
        }
      } else {
        _sidewaysBefore = MediaQuery.orientationOf(context) == Orientation.landscape;
        _desktopAlreadyFullscreen = DesktopWindow.fullScreen.value;
        setState(() {
          _fullscreen = true;
          _embeddedLandscape = false;
        });
        if (_mobile) {
          await ScreenOrientation.landscape();
          if (mounted && _fullscreen) await SystemUiVisibility.fullscreen();
        } else {
          await DesktopWindow.setFullScreen(on: true);
        }
      }
      if (mounted) _showControls();
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

  void _back({required bool immersive}) {
    if (_panel != null) {
      _closePanel();
    } else if (_fullscreen) {
      unawaited(_toggleFullscreen());
    } else if (immersive) {
      setState(() => _embeddedLandscape = true);
      _showControls();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _togglePlay() {
    if (_controller.busy || _swapping) return;
    if (_controller.session.state.status == PlaybackStatus.completed) {
      unawaited(_controller.open(_controller.video!.id, start: Duration.zero));
    } else {
      unawaited(_controller.session.togglePlayPause());
    }
    _showControls();
  }

  Future<void> _chooseRecording(ArchiveRecording recording) async {
    if (_swapping || _controller.busy || recording.id == _recordingId) return;
    _reportProgress();
    final old = _controller;
    final focus = _audioFocus;
    _audioFocus = null;
    _hide?.cancel();
    old.removeListener(_changed);
    setState(() {
      _panel = null;
      _swapping = true;
      _controls = true;
    });
    _retiring = () async {
      await WidgetsBinding.instance.endOfFrame;
      await focus?.dispose();
      old.dispose();
      await old.retirement;
    }();
    try {
      await _retiring;
      if (!mounted) return;
      _selected = recording;
      _createController(recording.video);
      _lastStatus = null;
      setState(() => _swapping = false);
      await _controller.open(recording.id);
    } on Object {
      if (mounted) {
        setState(() => _swapping = false);
        AppNavigator.toast(i18n('replay_open_failed'));
      }
    }
  }

  void _reportProgress() {
    final video = _controller.video;
    widget.onProgress?.call(
      _recordingId,
      video is BilibiliArchivePart ? video.part.page : null,
      _controller.session.state.status == PlaybackStatus.completed ? Duration.zero : _controller.position,
    );
  }

  String get _recordingId => switch (_controller.video) {
    final BilibiliArchivePart v => v.archive.bvid,
    final ArchiveVideo v => v.id,
    _ => _selected?.id ?? widget.videoId,
  };
  String get _author => switch (_controller.video) {
    final BilibiliArchivePart v when v.archive.owner.name.isNotEmpty => v.archive.owner.name,
    final HuyaArchiveVideo v when v.authorName.isNotEmpty => v.authorName,
    final DouyuVodVideo v when v.authorName.isNotEmpty => v.authorName,
    _ => _selected?.author.isNotEmpty == true ? _selected!.author : widget.room?.nick ?? '',
  };
  String get _avatar => switch (_controller.video) {
    final BilibiliArchivePart v => v.archive.owner.face,
    _ => widget.room?.avatar ?? '',
  };
  String get _platform => switch (_controller) {
    BilibiliArchiveController() => SiteIds.bilibili,
    HuyaArchiveController() => SiteIds.huya,
    _ => SiteIds.douyu,
  };
  String get _title => archiveDisplayTitle(switch (_controller.video) {
    final BilibiliArchivePart v => v.archive.title,
    final ArchiveVideo v => v.title,
    _ => _selected?.title ?? widget.bilibiliVideo?.title ?? widget.archiveVideo?.title ?? i18n('replay_title'),
  }, author: _author);
  DateTime? get _date => switch (_controller.video) {
    final BilibiliArchivePart v => v.archive.publishedAt?.toLocal(),
    final HuyaArchiveVideo v => DateTime.tryParse(v.date),
    final DouyuVodVideo v => v.publishedAt?.toLocal(),
    _ => _selected?.date,
  };
  String get _quality =>
      _controller.qualities.where((q) => q.id == _controller.qualityId).firstOrNull?.label ?? i18n('douyu_vod_quality');
  int get _partIndex => _controller.segments.indexWhere((v) => v.id == _controller.video?.id);
  bool get _hasParts => _controller.segments.length > 1;

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    _keyboardNavigation = true;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause ||
        node.hasPrimaryFocus &&
            event is KeyDownEvent &&
            {LogicalKeyboardKey.enter, LogicalKeyboardKey.select}.contains(key)) {
      _togglePlay();
      _play.requestFocus();
      return KeyEventResult.handled;
    }
    if (!_controls && {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight}.contains(key)) {
      unawaited(
        _controller.seek(_controller.position + Duration(seconds: key == LogicalKeyboardKey.arrowLeft ? -10 : 10)),
      );
      _showControls();
      return KeyEventResult.handled;
    }
    if (!_controls && {LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown}.contains(key)) {
      _showControls();
      _play.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _onVideoButton({
    required String label,
    required IconData icon,
    required VoidCallback? action,
    Key? key,
    FocusNode? focus,
    double size = 48,
  }) => SizedBox(
    width: size,
    height: size,
    child: IconButton(
      key: key,
      focusNode: focus,
      tooltip: label,
      onPressed: action,
      style: IconButton.styleFrom(
        foregroundColor: OnVideoColors.foreground,
        backgroundColor: OnVideoColors.ground.withValues(alpha: .42),
      ),
      icon: Icon(icon, size: size > 48 ? 32 : 24),
    ),
  );

  Widget _video({required bool immersive}) {
    final state = _controller.session.state;
    final duration = state.duration > Duration.zero ? state.duration : _controller.video?.duration ?? Duration.zero;
    final maximum = duration.inMilliseconds.toDouble();
    final position = (_scrub ?? _controller.position.inMilliseconds.toDouble()).clamp(0.0, maximum > 0 ? maximum : 1.0);
    final chrome = _controls || state.status != PlaybackStatus.playing || _controller.error != null;
    return Focus(
      focusNode: _surface,
      autofocus: true,
      onKeyEvent: _key,
      child: Listener(
        onPointerDown: (_) {
          _keyboardNavigation = false;
        },
        child: MouseRegion(
          onHover: (_) => _showControls(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (state.status == PlaybackStatus.playing && _controls) {
                _hide?.cancel();
                setState(() => _controls = false);
                _surface.requestFocus();
              } else {
                _showControls();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: OnVideoColors.ground),
                if (!_swapping)
                  LiveVideoView(
                    key: _videoKey,
                    session: _controller.session,
                    outputSize: !_mobile,
                    keepScreenOn: watchSetting(ref, Settings.enableScreenKeepOn),
                  ),
                if (!_swapping && _controller.supportsDanmaku)
                  DanmakuFrameRateBuilder(
                    builder: (context, fps, refreshRate) => IgnorePointer(
                      child: DanmakuOverlay(
                        messages: _controller.messages,
                        retractions: _controller.retractions,
                        look: danmakuLookOf(ref),
                        running: state.status == PlaybackStatus.playing,
                        visible: _controller.danmakuVisible,
                        maxVisible: watchSetting(ref, Settings.danmakuMaxVisibleCount),
                        fps: fps,
                        refreshRate: refreshRate,
                        giftClearance: const EdgeInsets.only(top: 48, bottom: 100),
                      ),
                    ),
                  ),
                if (_swapping ||
                    _controller.busy ||
                    {PlaybackStatus.opening, PlaybackStatus.buffering}.contains(state.status))
                  const Center(child: CircularProgressIndicator()),
                if (chrome && _panel == null) ...[
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              OnVideoColors.ground.withValues(alpha: .5),
                              OnVideoColors.ground.withValues(alpha: 0),
                              OnVideoColors.ground.withValues(alpha: .85),
                            ],
                            stops: const [0, .4, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    top: 4,
                    child: SafeArea(
                      bottom: false,
                      top: immersive,
                      child: Row(
                        children: [
                          if (immersive)
                            _onVideoButton(
                              key: const ValueKey('archive-back'),
                              label: i18n('back'),
                              icon: AppIcons.back,
                              action: () => _back(immersive: immersive),
                            ),
                          Expanded(
                            child: Text(
                              immersive ? _title : i18n('replay'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.textStyles.t14.copyWith(color: OnVideoColors.foreground),
                            ),
                          ),
                          _onVideoButton(
                            label: i18n('volume'),
                            icon: state.volume > 0 ? AppIcons.volumeHigh : AppIcons.volumeMuted,
                            action: () => unawaited(_controller.session.setVolume(state.volume > 0 ? 0 : 1)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: immersive ? 12 : 30),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _onVideoButton(
                            label: i18n('douyu_vod_rewind'),
                            icon: AppIcons.vodRewind,
                            action: _controller.busy
                                ? null
                                : () => unawaited(_controller.seek(_controller.position - const Duration(seconds: 10))),
                          ),
                          SizedBox(width: immersive ? 48 : 24),
                          _onVideoButton(
                            key: const ValueKey('vod-play-pause'),
                            focus: _play,
                            label: i18n(state.status == PlaybackStatus.playing ? 'pause' : 'play'),
                            icon: state.status == PlaybackStatus.playing ? AppIcons.pause : AppIcons.play,
                            size: 60,
                            action: _controller.busy || _swapping ? null : _togglePlay,
                          ),
                          SizedBox(width: immersive ? 48 : 24),
                          _onVideoButton(
                            label: i18n('douyu_vod_forward'),
                            icon: AppIcons.vodForward,
                            action: _controller.busy
                                ? null
                                : () => unawaited(_controller.seek(_controller.position + const Duration(seconds: 10))),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      bottom: immersive,
                      child: Theme(
                        data: ThemeData.dark(useMaterial3: true),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 40,
                              child: Slider(
                                key: const ValueKey('vod-seek'),
                                padding: EdgeInsets.zero,
                                value: position,
                                max: maximum > 0 ? maximum : 1,
                                onChangeStart: _controller.busy || maximum <= 0
                                    ? null
                                    : (v) {
                                        _hide?.cancel();
                                        setState(() => _scrub = v);
                                      },
                                onChanged: _controller.busy || maximum <= 0 ? null : (v) => setState(() => _scrub = v),
                                onChangeEnd: (v) {
                                  setState(() => _scrub = null);
                                  unawaited(_controller.seek(Duration(milliseconds: v.round())));
                                  _showControls();
                                },
                              ),
                            ),
                            SizedBox(
                              height: 48,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      key: const ValueKey('archive-video-clock'),
                                      '${vodTime(Duration(milliseconds: position.round()))} / ${vodTime(duration)}',
                                      maxLines: 1,
                                      style: context.textStyles.t12.copyWith(color: OnVideoColors.foreground),
                                    ),
                                  ),
                                  if (immersive) ...[
                                    _videoText(
                                      archiveRateLabel(_controller.rate),
                                      () => _openPanel(_ArchivePanel.speed),
                                      key: const ValueKey('archive-rate'),
                                    ),
                                    _videoText(_quality, () => _openPanel(_ArchivePanel.quality)),
                                    _onVideoButton(
                                      label: i18n('archive_scenes'),
                                      icon: AppIcons.vodCatalog,
                                      action: () => _openPanel(_ArchivePanel.episodes),
                                    ),
                                    _onVideoButton(
                                      label: i18n('archive_more'),
                                      icon: AppIcons.more,
                                      action: () => _openPanel(_ArchivePanel.more),
                                    ),
                                  ] else if (_hasParts && MediaQuery.textScalerOf(context).scale(12) < 20)
                                    _videoText(
                                      i18n(
                                        'archive_current_part',
                                        args: {'index': '${_partIndex + 1}', 'count': '${_controller.segments.length}'},
                                      ),
                                      () => _openPanel(_ArchivePanel.episodes),
                                    ),
                                  _onVideoButton(
                                    key: const ValueKey('vod-fullscreen'),
                                    label: i18n('fullscreen'),
                                    icon: immersive ? AppIcons.exitFullscreen : AppIcons.fullscreen,
                                    action: () => unawaited(_toggleFullscreen()),
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
                if (_controller.error != null || state.status == PlaybackStatus.error)
                  Positioned.fill(
                    child: ColoredBox(
                      color: OnVideoColors.ground.withValues(alpha: .8),
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                i18n(
                                  _controller.error is TimeoutException
                                      ? 'replay_seek_failed'
                                      : _controller.error is NeedsLogin
                                      ? 'douyu_vod_login'
                                      : 'douyu_vod_play_failed',
                                ),
                                textAlign: TextAlign.center,
                                style: context.textStyles.t14.copyWith(color: OnVideoColors.foreground),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                children: [
                                  FilledButton(
                                    onPressed: _controller.busy
                                        ? null
                                        : () => unawaited(
                                            _controller.open(
                                              _controller.video?.id ?? widget.videoId,
                                              start: _controller.position,
                                            ),
                                          ),
                                    child: Text(i18n('retry')),
                                  ),
                                  TextButton(
                                    onPressed: _controller.busy ? null : _restart,
                                    child: Text(i18n('archive_restart')),
                                  ),
                                  TextButton(
                                    onPressed: () => _back(immersive: immersive),
                                    child: Text(i18n('replay_back_catalog')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoText(String label, VoidCallback action, {Key? key}) => TextButton(
    key: key,
    onPressed: _controller.busy ? null : action,
    style: TextButton.styleFrom(
      foregroundColor: OnVideoColors.foreground,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 10),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.textStyles.t12.copyWith(color: OnVideoColors.foreground),
    ),
  );
  void _restart() {
    _closeIfOpen();
    unawaited(_controller.open(_controller.video?.id ?? widget.videoId, start: Duration.zero));
    _showControls();
  }

  void _closeIfOpen() {
    if (_panel != null) _closePanel();
  }

  Widget _identity() => Row(
    children: [
      CommonAvatar(avatarUrl: _avatar, fallbackName: _author.isEmpty ? i18n('replay_title') : _author, radius: 16),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _author.isEmpty ? i18n('replay_title') : _author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.t16,
            ),
            Text(
              '${platformName(_platform)} · ${i18n('replay_title')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.t12.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _quick() => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      TextButton(
        key: const ValueKey('archive-rate'),
        onPressed: _controller.busy ? null : () => _openPanel(_ArchivePanel.speed),
        child: Text('${i18n('archive_rate_short')}  ${archiveRateLabel(_controller.rate)}'),
      ),
      TextButton(
        key: const ValueKey('archive-quality'),
        onPressed: _controller.busy ? null : () => _openPanel(_ArchivePanel.quality),
        child: Text('${i18n('douyu_vod_quality')}  $_quality', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      TextButton.icon(
        onPressed: () => _openPanel(_ArchivePanel.more),
        icon: const Icon(AppIcons.more, size: 20),
        label: Text(i18n('archive_more')),
      ),
    ],
  );
  Widget _tabs() => Row(
    children: [
      if (_hasParts) _tabButton(0, i18n('archive_parts', args: {'count': '${_controller.segments.length}'})),
      _tabButton(1, i18n('archive_creator_replays')),
    ],
  );
  Widget _tabButton(int tab, String label) {
    final selected = (_hasParts ? _tab : 1) == tab;
    final scheme = Theme.of(context).colorScheme;
    return Flexible(
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(width: 2, color: selected ? scheme.primary : scheme.surface)),
        ),
        child: TextButton(
          onPressed: () => setState(() => _tab = tab),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.t14.copyWith(color: selected ? scheme.onSurface : scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _partList({bool tv = false}) =>
      Column(children: [for (final (i, part) in _controller.segments.indexed) _partTile(part, i, tv: tv)]);
  Widget _partTile(ArchiveVideo part, int i, {bool tv = false}) {
    final selected = part.id == _controller.video?.id;
    final scheme = Theme.of(context).colorScheme;
    void choose() {
      if (selected) {
        _closeIfOpen();
        _showControls();
        return;
      }
      _closeIfOpen();
      unawaited(_controller.open(part.id));
      _showControls();
    }

    final content = Container(
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer.withValues(alpha: .32) : scheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          Text(
            '${i + 1}'.padLeft(2, '0'),
            style: context.textStyles.t14.copyWith(color: selected ? scheme.primary : scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  i18n('douyu_vod_segment', args: {'index': '${i + 1}'}),
                  style: context.textStyles.t14.copyWith(color: selected ? scheme.primary : scheme.onSurface),
                ),
                if (selected)
                  Text(
                    i18n('archive_current_position', args: {'position': vodTime(_controller.position)}),
                    style: context.textStyles.t12.copyWith(color: scheme.primary),
                  ),
              ],
            ),
          ),
          Text(vodTime(part.duration), style: context.textStyles.t12.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: tv
          ? TvFocusable(
              key: ValueKey('archive-part-${part.id}'),
              zoom: false,
              onTap: _controller.busy ? null : choose,
              builder: (_, _) => content,
            )
          : InkWell(
              key: ValueKey('archive-part-${part.id}'),
              onTap: _controller.busy ? null : choose,
              borderRadius: BorderRadius.circular(8),
              child: content,
            ),
    );
  }

  Widget _recordingList({bool tv = false}) {
    final siblings = widget.recordings.where((v) => v.id != _recordingId).toList();
    return Column(
      children: [
        for (final item in siblings)
          ArchiveRecordingTile(
            key: ValueKey('archive-related-${item.id}'),
            recording: item,
            tv: tv,
            onTap: _swapping || _controller.busy ? null : () => unawaited(_chooseRecording(item)),
          ),
        if (siblings.isEmpty)
          TextButton(onPressed: () => _back(immersive: false), child: Text(i18n('replay_back_catalog'))),
      ],
    );
  }

  Widget _content({required bool tv}) {
    final date = _date;
    final video = _controller.video;
    final total = video is BilibiliArchivePart ? video.archive.duration : video?.duration;
    return ListView(
      key: const PageStorageKey('archive-watch-content'),
      controller: _contentScroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(_title, key: const ValueKey('archive-visible-title'), style: context.textStyles.t18),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            if (date != null)
              Text(
                '${date.year}.${date.month}.${date.day}',
                style: context.textStyles.t12.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            if (total != null && total > Duration.zero)
              Text(
                i18n(
                  video is BilibiliArchivePart ? 'archive_total_duration' : 'archive_record_duration',
                  args: {'duration': vodTime(total)},
                ),
                style: context.textStyles.t12.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _quick(),
        _tabs(),
        const SizedBox(height: 8),
        if (_hasParts && _tab == 0) _partList(tv: tv) else _recordingList(tv: tv),
      ],
    );
  }

  Widget _panelBody(bool tv) => switch (_panel!) {
    _ArchivePanel.quality => Column(
      children: [
        for (final q in _controller.qualities)
          ListTile(
            key: ValueKey('archive-quality-${q.id}'),
            enabled: q.playable && !_controller.busy,
            title: Text(q.label),
            subtitle: q.playable ? null : Text(i18n('douyu_vod_restricted')),
            trailing: q.id == _controller.qualityId ? const Icon(AppIcons.selected) : null,
            onTap: q.playable && !_controller.busy
                ? () {
                    _closePanel();
                    unawaited(_controller.selectQuality(q.id));
                  }
                : null,
          ),
      ],
    ),
    _ArchivePanel.episodes => Column(
      children: [
        _tabs(),
        const SizedBox(height: 8),
        if (_hasParts && _tab == 0) _partList(tv: tv) else _recordingList(tv: tv),
      ],
    ),
    _ArchivePanel.more => Column(
      children: [
        ListTile(
          title: Text(i18n('volume')),
          trailing: IconButton(
            tooltip: i18n('volume'),
            icon: Icon(_controller.session.state.volume > 0 ? AppIcons.volumeHigh : AppIcons.volumeMuted),
            onPressed: () => unawaited(_controller.session.setVolume(_controller.session.state.volume > 0 ? 0 : 1)),
          ),
        ),
        Slider(
          key: const ValueKey('archive-volume'),
          value: _controller.session.state.volume.clamp(0, 1),
          onChanged: (v) => unawaited(_controller.session.setVolume(v)),
        ),
        if (_controller.supportsDanmaku)
          SwitchListTile(
            title: Text(i18n('douyu_vod_danmaku')),
            value: _controller.danmakuVisible,
            onChanged: (_) => _controller.toggleDanmaku(),
          ),
        if (_controller.supportsDanmaku)
          ListTile(
            key: const ValueKey('vod-danmaku-settings'),
            title: Text(i18n('douyu_vod_danmaku_settings')),
            trailing: const Icon(AppIcons.forward),
            onTap: () => setState(() => _panel = _ArchivePanel.danmaku),
          ),
        ListTile(
          title: Text(i18n('archive_restart')),
          leading: const Icon(AppIcons.playAgain),
          onTap: _controller.busy ? null : _restart,
        ),
        ListTile(
          title: Text(i18n('replay_back_catalog')),
          leading: const Icon(AppIcons.vodCatalog),
          onTap: () {
            _closePanel();
            Navigator.of(context).pop();
          },
        ),
      ],
    ),
    _ArchivePanel.danmaku => const DanmakuSettingsContent(),
    _ArchivePanel.speed => const SizedBox.shrink(),
  };
  Widget _panelLayer({required BoxConstraints box, required bool side, required bool tv}) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final insets = MediaQuery.paddingOf(context);
    final available = (box.maxHeight - keyboard - insets.top).clamp(80.0, box.maxHeight);
    final height = side ? available : (box.maxHeight * .82).clamp(80.0, available);
    final width = side ? (box.maxWidth * .42).clamp(240.0, 360.0) : box.maxWidth.clamp(0.0, 560.0);
    final title = i18n(switch (_panel!) {
      _ArchivePanel.speed => 'archive_rate_title',
      _ArchivePanel.quality => 'douyu_vod_quality',
      _ArchivePanel.episodes => 'archive_scenes',
      _ArchivePanel.more => 'archive_more',
      _ArchivePanel.danmaku => 'douyu_vod_danmaku_settings',
    });
    return Stack(
      children: [
        ModalBarrier(
          color: Theme.of(context).colorScheme.scrim.withValues(alpha: .55),
          onDismiss: _closePanel,
          semanticsLabel: i18n('close'),
        ),
        Positioned(
          right: side ? 0 : null,
          left: side ? null : 0,
          bottom: keyboard,
          top: side ? insets.top : null,
          child: Align(
            alignment: side ? Alignment.centerRight : Alignment.bottomCenter,
            child: SizedBox(
              width: side ? width : box.maxWidth,
              height: height,
              child: Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Material(
                    key: const ValueKey('archive-settings-panel'),
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    clipBehavior: Clip.antiAlias,
                    borderRadius: BorderRadius.vertical(top: side ? Radius.zero : const Radius.circular(20)),
                    child: FocusScope(
                      node: _panelScope,
                      autofocus: true,
                      child: _panel == _ArchivePanel.speed
                          ? ArchiveRateDialog(
                              key: const ValueKey('archive-rate-editor'),
                              rate: _controller.rate,
                              embedded: true,
                              onSelected: (v) => unawaited(_applyRate(v)),
                              onClose: _closePanel,
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      const SizedBox(width: 16),
                                      Expanded(child: Text(title, style: context.textStyles.t18)),
                                      IconButton(
                                        autofocus: true,
                                        tooltip: i18n('close'),
                                        onPressed: _closePanel,
                                        icon: const Icon(AppIcons.close),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: _panel == _ArchivePanel.danmaku
                                      ? _panelBody(tv)
                                      : SingleChildScrollView(
                                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                                          child: _panelBody(tv),
                                        ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final landscape = box.maxHeight < 480 && box.maxWidth > box.maxHeight;
      final tv = UiMode.parse(watchSetting(ref, Settings.uiMode))
          .showsTv(television: ref.watch(televisionDeviceProvider));
      final immersive = _fullscreen || landscape && !_embeddedLandscape;
      final portrait = box.maxWidth < 600 && !landscape;
      final video = _video(immersive: immersive);
      final content = _content(tv: tv);
      final normal = Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('archive-back'),
                    tooltip: i18n('back'),
                    onPressed: () => _back(immersive: false),
                    icon: const Icon(AppIcons.back),
                  ),
                  Expanded(child: _identity()),
                  IconButton(
                    tooltip: i18n('replay_back_catalog'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(AppIcons.vodCatalog),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: portrait
                ? Column(
                    children: [
                      AspectRatio(aspectRatio: 16 / 9, child: video),
                      Expanded(child: content),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: landscape ? 6 : 7,
                        child: AspectRatio(aspectRatio: 16 / 9, child: video),
                      ),
                      Expanded(flex: landscape ? 4 : 3, child: content),
                    ],
                  ),
          ),
        ],
      );
      return PopScope<void>(
        canPop: _panel == null && !immersive,
        onPopInvokedWithResult: (popped, _) {
          if (!popped) _back(immersive: immersive);
        },
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
              _back(immersive: immersive);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Stack(
              children: [
                ExcludeSemantics(
                  excluding: _panel != null,
                  child: ExcludeFocus(
                    excluding: _panel != null,
                    child: immersive ? video : SafeArea(child: normal),
                  ),
                ),
                if (_panel != null) _panelLayer(box: box, side: immersive || box.maxWidth >= 840, tv: tv),
              ],
            ),
          ),
        ),
      );
    },
  );
}
