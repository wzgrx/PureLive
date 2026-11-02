import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/music_player.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/player/player_view.dart' show videoFits;
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';
import 'package:pure_live/shared/remote/playback_remote.dart';
import 'package:pure_live/shared/remote/playback_target.dart';
import 'package:pure_live/shared/rooms/auto_room_switch.dart';
import 'package:pure_live/shared/rooms/playback_hud.dart';
import 'package:pure_live/shared/rooms/playback_lines.dart';
import 'package:pure_live/shared/rooms/room_gain.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/tv/room/tv_room_overlays.dart';
import 'package:pure_live/tv/room/tv_room_settings_panel.dart';
import 'package:pure_live/tv/room/tv_super_chat_panel.dart';
import 'package:pure_live/tv/tv_navigation.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/wallpaper/tv_wallpaper_layer.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_room_dialog.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';

/// The player settings (M9) as the engine's configuration (the phone room's
/// rule, M13.3).
MpvEngineConfig tvEngineConfig(SettingsStore settings) => MpvEngineConfig(
  platform: mpvPlatformOf(defaultTargetPlatform) ?? MpvPlatform.linux,
  hardwareDecoding: settings.get(Settings.enableCodec),
  customOutput: settings.get(Settings.customPlayerOutput),
  videoOutputDriver: settings.get(Settings.videoOutputDriver),
  hardwareDecoder: settings.get(Settings.videoHardwareDecoder),
  audioOutputDriver: settings.get(Settings.audioOutputDriver),
  androidCompatibility: settings.get(Settings.playerCompatMode),
  rtxVideoSuperResolution: settings.get(Settings.enableRtxVsr),
  volumeGainDb: settings.get(Settings.volumeBoostDb),
);

/// The basic TV room (pure_live_TV `LivePlayPage` and `PlayerKeyScope`;
/// arguments: [TvRoomArgs] or a lone `LiveRoom`).
///
/// The picture fills the screen with the flying danmaku over it. The remote:
/// - OK shows or hides the controls (quality, line, danmaku, follow,
///   refresh, room list); on a failed or offline room OK retries;
/// - Up and Down switch to the previous or next room of the list the room
///   was opened from (presses within 300 ms add up, then one switch), the
///   list wraps around; a banner names the new room;
/// - Left, Right or Menu open the room list on the side;
/// - Back closes the list, then the controls, then leaves, telling the page
///   below which room was shown last (its card takes the focus).
///
/// The logic is the phone room's `LiveRoomController` (one per room, with
/// its own playback session); only the layout and the keys are the TV's.
/// The fuller TV room (programme guide, catch-up, danmaku panel) is M14.2.
class TvLivePlayPage extends ConsumerStatefulWidget {
  /// Creates the room for [route].
  const new({required this.route, super.key});

  /// The path and arguments the room was opened with.
  final RouteArgs route;

  @override
  ConsumerState<TvLivePlayPage> createState() => TvLivePlayPageState();
}

/// The TV room's state (tests read [index] and [controller]).
class TvLivePlayPageState extends ConsumerState<TvLivePlayPage> {
  final FocusNode _keys = FocusNode(debugLabel: 'tv room keys');
  final FocusNode _firstControl = FocusNode(debugLabel: 'tv room first control');
  final FocusNode _superChatFocus = FocusNode(debugLabel: 'tv room super chats');
  List<LiveRoom> _playlist = const [];
  int _index = 0;
  LiveRoomController? _controller;
  AutoRoomSwitch? _autoRoomSwitch;
  StreamSubscription<PlaybackState>? _autoRoomStates;
  PlaybackSession? _session;
  late final Future<void> _wallpaperReady;
  RoomBackgroundPolicy? _background;
  String? _problem;
  bool _controls = false;
  bool _panel = false;

  /// The play settings on the right (A17.4 c3, c7).
  bool _settings = false;
  bool _superChatPanel = false;
  bool _banner = false;
  Timer? _hideControls;
  Timer? _hideBanner;
  Timer? _debounce;
  int _pendingDelta = 0;
  ValueNotifier<LiveRoom?>? _shown;
  PlaybackRemote? _remote;
  RemotePlaybackTarget? _remoteTarget;

  /// How long the controls stay without a key.
  static const Duration controlsTimeout = Duration(seconds: 6);

  /// Presses within this window add up to one switch.
  static const Duration switchWindow = Duration(milliseconds: 300);

  /// How long the banner of a new room stays.
  static const Duration bannerTime = Duration(seconds: 3);

  /// The room's logic; null when the arguments were unusable.
  LiveRoomController? get controller => _controller;

  /// The room's place in the list.
  int get index => _index;

  /// The list switched through.
  List<LiveRoom> get playlist => _playlist;

  @override
  void initState() {
    super.initState();
    // One video at a time on a box: the video background waits (A17.8).
    _wallpaperReady = TvWallpaperVideo.hold();
    // Music gives the speakers to the room.
    unawaited(yieldMusicToOtherPlayback(ref));
    final arguments = widget.route.arguments;
    final (room, list) = switch (arguments) {
      final TvRoomArgs args => (args.room, args.playlist),
      LiveRoomArgs(:final room, :final playlist) => (room, playlist),
      final LiveRoom room => (room, const <LiveRoom>[]),
      _ => (null, const <LiveRoom>[]),
    };
    if (room == null) {
      _problem = i18n('get_room_info_failed_retry');
      return;
    }
    if (arguments is TvRoomArgs) _shown = arguments.shown;
    final at = list.indexWhere(room.hasSameIdentity);
    _playlist = at < 0 ? [room, ...list] : list;
    _index = at < 0 ? 0 : at;
    _remote = ref.read(appServicesProvider).remoteControl;
    _remoteTarget = playbackRemoteTarget(
      available: () => mounted && (ModalRoute.isCurrentOf(context) ?? true),
      room: () => _room,
      session: () => _controller?.session,
      refresh: () async => await _controller?.load(),
      volume: (value) async => await _controller?.setVolume(value, save: true),
      navigation: {
        for (final key in ['previous', 'next', 'up', 'down', 'left', 'right', 'ok', 'back']) key: () => _remoteKey(key),
        'danmaku': () async {
          final settings = ref.read(storeProvider).settings;
          await settings.set(Settings.hideDanmaku, !settings.get(Settings.hideDanmaku));
          return true;
        },
      },
    );
    _remote!.register(_remoteTarget!);
    _autoRoomSwitch = AutoRoomSwitch(
      store: ref.read(storeProvider),
      onRefresh: () async => await _controller?.load(preservePause: true),
      siteOf: ref.read(sitesProvider).maybeOf,
      maySwitch: () =>
          mounted &&
          _controller?.sleepDeadline == null &&
          !(_controller?.sleepTimerFinished ?? false) &&
          (ModalRoute.isCurrentOf(context) ?? true) &&
          (_controller?.mayAutoStart?.call() ?? true),
      onSwitch: (next) {
        if (!mounted) return;
        var index = _playlist.indexWhere(next.hasSameIdentity);
        if (index < 0) {
          index = _playlist.length;
          _playlist = [..._playlist, next];
        }
        switchTo(index, automatic: true);
      },
      onExhausted: () => AppNavigator.toast(i18n('auto_room_switch_stopped')),
    );
    liveRouteObserver.currentRoute.addListener(_syncAutoRoomSwitch);
    _open(_playlist[_index]);
  }

  void _open(LiveRoom room, {bool automatic = false}) {
    final audioOnly = automatic && (_controller?.audioOnly ?? false);
    _autoRoomSwitch?.setRoom(room, automatic: automatic);
    TvWallpaperVideo.trackCleanup(_closeRoom());
    final site = ref.read(sitesProvider).maybeOf(room.platform);
    if (site == null) {
      _problem = i18n('platform_retired');
      return;
    }
    _problem = null;
    _shown?.value = room;
    final store = ref.read(storeProvider);
    final danmaku = ref.read(danmakuProvider);
    final session = _session = ref.read(playbackSessionFactoryProvider)(config: tvEngineConfig(store.settings));
    final controller = _controller = LiveRoomController(
      room: room,
      site: site,
      session: session,
      danmaku: danmaku.connectionFor(site.id),
      danmakuSupported: danmaku.supports(site.id),
      store: store,
      // A TV box plays at full volume; the TV's own volume governs.
      mobile: defaultTargetPlatform == TargetPlatform.android,
      toast: (message) => AppNavigator.toast(message),
      network: ref.read(networkProbeProvider),
      emotes: ref.read(emoteLibraryProvider),
      initialAudioOnly: audioOnly,
    );
    _background = RoomBackgroundPolicy(controller: controller, settings: store.settings)..start();
    controller.addListener(_syncAutoRoomSwitch);
    _autoRoomStates = session.states.listen((_) => _syncAutoRoomSwitch());
    unawaited(
      _wallpaperReady.then((_) {
        if (mounted && identical(_controller, controller)) unawaited(controller.start());
      }),
    );
  }

  void _syncAutoRoomSwitch() {
    final controller = _controller;
    if (controller == null) return;
    _autoRoomSwitch?.update(
      room: controller.room,
      playback: controller.session.state,
      resolving: controller.stage == RoomStage.loading || controller.switching || controller.switchingLine,
      unavailable: controller.stage == RoomStage.unplayable,
      replay: controller.playingCarousel,
    );
  }

  Future<void> _closeRoom() {
    _controller?.removeListener(_syncAutoRoomSwitch);
    unawaited(_autoRoomStates?.cancel());
    _autoRoomStates = null;
    _background?.dispose();
    _background = null;
    _controller?.dispose();
    _controller = null;
    final session = _session;
    _session = null;
    return session?.waitForResourceRelease() ?? Future<void>.value();
  }

  @override
  void dispose() {
    if (_remoteTarget case final target?) _remote?.unregister(target);
    _autoRoomSwitch?.dispose();
    liveRouteObserver.currentRoute.removeListener(_syncAutoRoomSwitch);
    _hideControls?.cancel();
    _hideBanner?.cancel();
    _debounce?.cancel();
    unawaited(TvWallpaperVideo.releaseAfter(_closeRoom()));
    _keys.dispose();
    _firstControl.dispose();
    _superChatFocus.dispose();
    super.dispose();
  }

  LiveRoom? get _room => _controller?.room ?? (_playlist.isEmpty ? null : _playlist[_index]);

  void _showControls() {
    setState(() {
      _controls = true;
      _panel = false;
      _superChatPanel = false;
    });
    _touch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controls && _firstControl.context != null) _firstControl.requestFocus();
    });
  }

  /// Restarts the controls' timeout (a key or a choice in them).
  void _touch() {
    _hideControls?.cancel();
    _hideControls = Timer(controlsTimeout, () {
      if (mounted && _controls) _hide();
    });
  }

  void _hide() {
    _hideControls?.cancel();
    setState(() {
      _controls = false;
      _panel = false;
      _settings = false;
      _superChatPanel = false;
    });
    _keys.requestFocus();
  }

  void _openPanel() {
    _hideControls?.cancel();
    setState(() {
      _panel = true;
      _settings = false;
      _superChatPanel = false;
      _controls = false;
    });
  }

  void _openSettings() {
    _hideControls?.cancel();
    setState(() {
      _settings = true;
      _panel = false;
      _superChatPanel = false;
      _controls = false;
    });
  }

  /// Queues a switch by [delta] rooms; presses within [switchWindow] add up.
  void switchBy(int delta) {
    if (_playlist.length < 2) {
      AppNavigator.toast(i18n('tv_no_other_room'));
      return;
    }
    _pendingDelta += delta;
    _autoRoomSwitch?.suspend(value: true);
    _debounce?.cancel();
    _debounce = Timer(switchWindow, () {
      final total = _pendingDelta;
      _pendingDelta = 0;
      if (total != 0 && mounted) switchTo((_index + total) % _playlist.length);
      _autoRoomSwitch?.suspend(value: false);
    });
  }

  /// Shows room [index] of the list.
  void switchTo(int index, {bool automatic = false}) {
    if (index < 0 || index >= _playlist.length) return;
    final wasPanel = _panel;
    setState(() {
      _index = index;
      _open(_playlist[index], automatic: automatic);
      _panel = false;
      _superChatPanel = false;
      _banner = true;
    });
    _hideBanner?.cancel();
    _hideBanner = Timer(bannerTime, () {
      if (mounted) setState(() => _banner = false);
    });
    if (wasPanel || _controls) _keys.requestFocus();
  }

  bool get _blocked {
    final controller = _controller;
    if (controller == null) return true;
    return switch (controller.stage) {
      RoomStage.failed || RoomStage.offline || RoomStage.unplayable => true,
      RoomStage.loading => false,
      RoomStage.playing => controller.session.state.status == PlaybackStatus.error,
    };
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_panel) {
      // The list walks by focus; Right closes it (it is on the left).
      if (key == LogicalKeyboardKey.arrowRight) {
        _hide();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // The settings walk by focus; Back closes them.
    if (_settings || _superChatPanel) return KeyEventResult.ignored;
    final up = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.channelUp;
    final down = key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.channelDown;
    if (up || down) {
      switchBy(up ? -1 : 1);
      if (_controls) _touch();
      return KeyEventResult.handled;
    }
    if (_controls) {
      _touch();
      // Left, Right and OK belong to the buttons.
      return KeyEventResult.ignored;
    }
    if (isTvConfirmKey(key)) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      final controller = _controller;
      if (_blocked) {
        if (controller != null) {
          unawaited(controller.stage == RoomStage.offline ? controller.load() : controller.retry());
        }
      } else {
        _showControls();
      }
      return KeyEventResult.handled;
    }
    // A17.4 c3: Left opens the rooms on the left; Right, the menu key and
    // the info key open the play settings on the right.
    if (key == LogicalKeyboardKey.arrowLeft) {
      _openPanel();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.info) {
      _openSettings();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<bool> _remoteKey(String key) async {
    if (!mounted) return false;
    if (key == 'previous' || key == 'next') {
      if (_playlist.length < 2) return false;
      switchBy(key == 'previous' ? -1 : 1);
      return true;
    }
    if (key == 'back') return await AppNavigator.mouseBack();
    if (_panel || _settings || _controls || _superChatPanel) {
      final focus = FocusManager.instance.primaryFocus;
      if (key == 'ok') {
        final context = focus?.context;
        if (context == null) return false;
        Actions.maybeInvoke(context, const ActivateIntent());
        return true;
      }
      final direction = switch (key) {
        'up' => TraversalDirection.up,
        'down' => TraversalDirection.down,
        'left' => TraversalDirection.left,
        'right' => TraversalDirection.right,
        _ => null,
      };
      return direction != null && (focus?.focusInDirection(direction) ?? false);
    }
    switch (key) {
      case 'up':
        switchBy(-1);
      case 'down':
        switchBy(1);
      case 'left':
        _openPanel();
      case 'right':
        _openSettings();
      case 'ok':
        if (_blocked) {
          await _controller?.retry();
        } else {
          _showControls();
        }
      default:
        return false;
    }
    return true;
  }

  void _showSuperChats() {
    _hideControls?.cancel();
    setState(() {
      _superChatPanel = true;
      _controls = false;
      _settings = false;
      _panel = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _superChatPanel) _superChatFocus.requestFocus();
    });
  }

  Future<void> _pickQuality() async {
    final controller = _controller;
    if (controller == null || controller.qualities.isEmpty) return;
    _hideControls?.cancel();
    final picked = await showTvChoice<int>(
      context,
      title: i18n('tv_quality'),
      current: controller.qualityIndex,
      options: [
        for (final (index, quality) in controller.qualities.indexed) TvChoice(value: index, label: quality.quality),
      ],
    );
    if (picked != null && picked != controller.qualityIndex) unawaited(controller.selectQuality(picked));
    if (mounted && _controls) _touch();
  }

  Future<void> _pickLine() async {
    final controller = _controller;
    if (controller == null) return;
    final state = controller.session.state;
    if (state.lineCount < 2) return;
    final lines = PlaybackLineChoices(
      controller.session,
      detailed: ref.read(storeProvider).settings.get(Settings.playbackLineDetails),
      telemetry: controller.telemetry,
    );
    _hideControls?.cancel();
    final picked = await showTvChoice<int>(
      context,
      title: i18n('tv_line'),
      current: state.lineIndex,
      options: [
        for (var index = 0; index < state.lineCount; index++)
          TvChoice(value: index, label: lines.name(index), description: lines.detailed ? lines.origins[index] : null),
      ],
    );
    if (picked != null && picked != state.lineIndex) unawaited(controller.selectLine(picked));
    if (mounted && _controls) _touch();
  }

  Future<void> _pickGain() async {
    final room = _room;
    if (room == null) return;
    final settings = ref.read(storeProvider).settings;
    _hideControls?.cancel();
    const inherit = 100;
    final picked = await showTvChoice<int>(
      context,
      title: i18n('room_gain'),
      current: RoomGain.overrideOf(settings, room) ?? inherit,
      options: [
        TvChoice(value: inherit, label: i18n('room_gain_default')),
        for (var db = -12; db <= 12; db++) TvChoice(value: db, label: '${db > 0 ? '+' : ''}$db dB'),
      ],
    );
    if (picked != null) await RoomGain.save(settings, room, picked == inherit ? null : picked);
    if (mounted && _controls) _touch();
  }

  Future<void> _toggleFollow({required bool followed}) async {
    final room = _room;
    if (room == null) return;
    final store = ref.read(storeProvider);
    _hideControls?.cancel();
    if (followed) {
      await tvUnfollowRoom(context, store: store, room: room);
    } else {
      await followRoom(store, room);
    }
    if (mounted && _controls) _touch();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // Back closes the list or the controls first, then leaves (the room
    // shown is already in `TvRoomArgs.shown` for the page below).
    return PopScope<Object?>(
      canPop: !_panel && !_settings && !_controls && !_superChatPanel,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hide();
      },
      child: Scaffold(
        backgroundColor: OnVideoColors.ground,
        body: Focus(
          focusNode: _keys,
          autofocus: true,
          onKeyEvent: _onKey,
          child: controller == null
              ? TvBackground(
                  child: TvStatusView(
                    icon: AppIcons.playbackError,
                    title: _problem ?? i18n('get_room_info_failed_retry'),
                    subtitle: i18n('tv_room_switch_hint'),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      key: const ValueKey('tv-room-touch-surface'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (_blocked || _panel || _settings || _superChatPanel) return;
                        if (_controls) {
                          _hide();
                        } else {
                          _showControls();
                        }
                      },
                      child: _Picture(key: ObjectKey(controller), controller: controller),
                    ),
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => StreamBuilder<PlaybackState>(
                        stream: controller.session.states,
                        initialData: controller.session.state,
                        builder: (context, snapshot) =>
                            TvRoomStatus(controller: controller, playback: snapshot.data ?? controller.session.state),
                      ),
                    ),
                    PlaybackHud(
                      telemetry: controller.telemetry,
                      controls: _controls,
                      fullscreen: true,
                      clearance: EdgeInsets.only(top: _banner ? 110 : 12, bottom: _controls ? 170 : 52),
                    ),
                    if (_banner && !_controls && !_panel && !_settings && !_superChatPanel)
                      Positioned(
                        left: 0,
                        top: 0,
                        child: ListenableBuilder(
                          listenable: controller,
                          builder: (context, _) =>
                              TvChannelBanner(room: controller.room, index: _index, count: _playlist.length),
                        ),
                      ),
                    if (_controls)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ListenableBuilder(
                          listenable: controller,
                          builder: (context, _) => StreamBuilder<bool>(
                            stream: ref.read(storeProvider).follows.watchContains(controller.room),
                            builder: (context, followed) => TvRoomControls(
                              controller: controller,
                              followed: followed.data ?? false,
                              danmakuOn: watchSetting(ref, Settings.enableDanmakuDisplay),
                              onQuality: () => unawaited(_pickQuality()),
                              onLine: () => unawaited(_pickLine()),
                              onGain: () => unawaited(_pickGain()),
                              onDanmaku: () {
                                _touch();
                                final settings = ref.read(storeProvider).settings;
                                unawaited(
                                  settings.set(
                                    Settings.enableDanmakuDisplay,
                                    !settings.get(Settings.enableDanmakuDisplay),
                                  ),
                                );
                              },
                              onFollow: () => unawaited(_toggleFollow(followed: followed.data ?? false)),
                              onRefresh: () {
                                _touch();
                                unawaited(controller.load());
                              },
                              onList: _openPanel,
                              onSuperChat:
                                  watchSetting(ref, Settings.showFullscreenSuperChat) &&
                                      controller.superChats.isNotEmpty
                                  ? _showSuperChats
                                  : null,
                              firstButton: _firstControl,
                            ),
                          ),
                        ),
                      ),
                    if (_panel)
                      Positioned(
                        top: 0,
                        left: 0,
                        bottom: 0,
                        child: TvRoomList(rooms: _playlist, current: _index, onPick: switchTo),
                      ),
                    if (_superChatPanel)
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        width: TvScale.of(context).px(roomSidePanelWidth),
                        child: TvSuperChatPanel(controller: controller, focusNode: _superChatFocus, onClose: _hide),
                      ),
                    if (_settings)
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        child: TvRoomSettingsPanel(controller: controller, onClose: _hide),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The picture and the flying danmaku.
class _Picture extends ConsumerWidget {
  const new({required this.controller, super.key});

  final LiveRoomController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fit = videoFits[watchSetting(ref, Settings.videoFitIndex).clamp(0, videoFits.length - 1)];
    final showDanmaku = watchSetting(ref, Settings.enableDanmakuDisplay) && !watchSetting(ref, Settings.hideDanmaku);
    return Stack(
      fit: StackFit.expand,
      children: [
        LiveVideoView(session: controller.session, fit: fit),
        DanmakuOverlay(
          messages: controller.flying,
          retractions: controller.retractions,
          look: danmakuLookOf(ref),
          visible: showDanmaku,
          // D05.2: the room's "同屏最大弹幕条数".
          maxVisible: watchSetting(ref, Settings.danmakuMaxVisibleCount),
        ),
      ],
    );
  }
}
