import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audio_service/audio_service.dart' as audio;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/live_play/logic/background_keeper.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/overlay_window.dart';

export 'package:pure_live/platform/device_controls.dart';

/// Whether this app may use picture-in-picture (U.2j c9).
enum PipAvailability {
  /// It may.
  allowed,

  /// The device offers it, but the system settings turned it off for this
  /// app ("无法打开画中画", "去设置").
  disabled,

  /// The device has none.
  unsupported,
}

/// How a request to enter picture-in-picture ended.
enum PipEntry {
  /// The window is entering it.
  entered,

  /// The system settings turned it off for this app.
  disabled,

  /// The system refused for another reason (3.x's "打开画中画失败，请重试").
  failed,
}

/// Android's system picture-in-picture (`pure_live/pip` in `MainActivity`;
/// 3.x used the floating plugin). [active] follows the activity.
abstract final class PictureInPicture {
  static const MethodChannel _channel = MethodChannel('pure_live/pip');
  static bool _listening = false;

  /// Whether the activity is in picture-in-picture now.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  /// Whether to treat this as Android (tests); null asks the platform.
  @visibleForTesting
  static bool? debugAndroid;

  static bool get _android => debugAndroid ?? (!kIsWeb && Platform.isAndroid);

  /// Whether this runs on Android ([debugAndroid] in tests).
  static bool get onAndroid => _android;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') active.value = call.arguments == true;
      // The pause / play action of the system's picture-in-picture window
      // (docs/A-界面设计/A14-系统界面/A14.1-系统界面 c7).
      if (call.method == 'togglePlay') await _toggle?.call();
      // A07.24: the mute action.
      if (call.method == 'toggleMute') await _toggleMute?.call();
    });
  }

  static Object? _owner;
  static bool? _playing;
  static bool? _muted;
  static Future<void> Function()? _toggle;
  static Future<void> Function()? _toggleMute;

  /// Lets the picture-in-picture window of [owner] (the room playing) show
  /// a pause or play action (U.14 c7) and, with [toggleMute], a mute or
  /// unmute one (A07.24); sent to Android only on a change.
  static void bindPlayback({
    required Object owner,
    required bool playing,
    required Future<void> Function() play,
    required Future<void> Function() pause,
    bool? muted,
    Future<void> Function()? toggleMute,
  }) {
    if (!_android) return;
    _owner = owner;
    _toggle = () => (_playing ?? false) ? pause() : play();
    _toggleMute = toggleMute;
    final mute = toggleMute == null ? null : muted ?? false;
    if (_playing == playing && _muted == mute) return;
    _playing = playing;
    _muted = mute;
    _listen();
    unawaited(_setPlaying(playing, mute));
  }

  /// Takes the actions away when [owner] leaves.
  static void unbindPlayback(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _toggle = null;
    _toggleMute = null;
    _playing = null;
    _muted = null;
    unawaited(_setPlaying(null, null));
  }

  static Future<void> _setPlaying(bool? playing, bool? muted) async {
    try {
      await _channel.invokeMethod<void>('setPlaying', {
        'playing': playing,
        'play': i18n('media_play'),
        'pause': i18n('media_pause'),
        'muted': muted,
        'mute': i18n('live_play_mute'),
        'unmute': i18n('live_play_unmute'),
      });
    } on Object catch (error) {
      developer.log('Picture-in-picture action failed', name: 'LivePlay', error: error);
    }
  }

  /// Whether this device offers picture-in-picture.
  static Future<bool> supported() async {
    if (!_android) return false;
    _listen();
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on Object {
      return false;
    }
  }

  /// Whether this app may use picture-in-picture now (the system settings
  /// can turn it off per app).
  static Future<PipAvailability> availability() async {
    if (!_android) return PipAvailability.unsupported;
    _listen();
    try {
      return switch (await _channel.invokeMethod<String>('status')) {
        'allowed' => PipAvailability.allowed,
        'disabled' => PipAvailability.disabled,
        _ => PipAvailability.unsupported,
      };
    } on Object {
      return PipAvailability.unsupported;
    }
  }

  /// Where [rect] (logical pixels, [pixelRatio] physical ones each) is on
  /// the screen in physical pixels, as the system's `sourceRectHint` takes
  /// it; null when there is none.
  static List<int>? _hint(Rect? rect, double pixelRatio) {
    if (rect == null || rect.isEmpty || !rect.isFinite) return null;
    return [
      (rect.left * pixelRatio).round(),
      (rect.top * pixelRatio).round(),
      (rect.right * pixelRatio).round(),
      (rect.bottom * pixelRatio).round(),
    ];
  }

  /// Enters picture-in-picture with the picture's [width]:[height] (the
  /// system limits the ratio to 2.39:1); the window grows out of [picture],
  /// the picture's place on screen in logical pixels ([pixelRatio] physical
  /// ones each; A07.24), and says [title].
  static Future<PipEntry> enter({
    required int width,
    required int height,
    Rect? picture,
    double pixelRatio = 1,
    String? title,
    String? subtitle,
  }) async {
    if (!_android) return PipEntry.failed;
    _listen();
    try {
      if (title != null) await update(title: title, subtitle: subtitle);
      final entry = await _channel.invokeMethod<Object>('enter', {
        'width': width,
        'height': height,
        'hint': _hint(picture, pixelRatio),
      });
      return switch (entry) {
        'entered' || true => PipEntry.entered,
        'disabled' => PipEntry.disabled,
        _ => PipEntry.failed,
      };
    } on Object {
      return PipEntry.failed;
    }
  }

  /// Tells the window (in picture-in-picture or about to be) what changed
  /// (A07.24): the picture's [width]:[height] (another quality, a portrait
  /// stream's first frame), its place on screen, the [title] and
  /// [subtitle] (Android 13 and later show them).
  static Future<void> update({
    int? width,
    int? height,
    Rect? picture,
    double pixelRatio = 1,
    String? title,
    String? subtitle,
  }) async {
    if (!_android) return;
    _listen();
    try {
      await _channel.invokeMethod<void>('update', {
        'width': ?width,
        'height': ?height,
        if (picture != null) 'hint': _hint(picture, pixelRatio),
        'title': ?title,
        'subtitle': ?subtitle,
      });
    } on Object catch (error) {
      developer.log('Picture-in-picture update failed', name: 'LivePlay', error: error);
    }
  }

  /// The user removed the application task: dismiss its external window only
  /// after the playback owner has retired its media resources.
  static Future<void> closeTask() async {
    if (!_android) return;
    _autoOwner = null;
    // A cached Flutter engine can outlive the removed PiP Activity. Some
    // devices never deliver its final mode callback before detaching it.
    active.value = false;
    try {
      await _channel.invokeMethod<void>('closeTask');
    } on Object catch (error) {
      developer.log('Task window cleanup failed', name: 'LivePlay', error: error);
    }
  }

  /// Opens this app's picture-in-picture page of the system settings (its
  /// details page where there is none). False when nothing opened.
  static Future<bool> openSettings() async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on Object {
      return false;
    }
  }

  static Object? _autoOwner;

  /// Lets leaving the app (home, recents) enter picture-in-picture by itself
  /// with the picture's [width]:[height] (J1: Android 12 and later animate
  /// it, 8-11 enter when the user leaves), growing out of [picture] (its
  /// place on screen in logical pixels, [pixelRatio] physical ones each, A07.24);
  /// [enabled] false stops that. [owner] is who
  /// arms it (a room page, the floating window): only the one that armed it
  /// last can disarm it, so a room page closing as the floating window takes
  /// over does not undo the window's.
  static Future<void> setAutoEnter({
    required bool enabled,
    int width = 16,
    int height = 9,
    Rect? picture,
    double pixelRatio = 1,
    Object? owner,
  }) async {
    if (!_android) return;
    if (enabled) {
      _autoOwner = owner;
    } else if (owner != null && !identical(owner, _autoOwner)) {
      return;
    } else {
      _autoOwner = null;
    }
    _listen();
    try {
      await _channel.invokeMethod<void>('setAutoEnter', {
        'enabled': enabled,
        'width': width,
        'height': height,
        'hint': _hint(picture, pixelRatio),
      });
    } on Object catch (error) {
      developer.log('Auto picture-in-picture failed', name: 'LivePlay', error: error);
    }
  }
}

/// Android's wake and Wi-Fi locks while the room plays in the background
/// (`pure_live/background_playback`, 3.x `BackgroundPlaybackService`).
abstract final class BackgroundKeepAlive {
  static const MethodChannel _channel = MethodChannel('pure_live/background_playback');
  static bool? _applied;

  /// Sees every change (also where there are no locks).
  @visibleForTesting
  static void Function({required bool enabled})? debugLog;

  /// Forgets what was applied (tests).
  @visibleForTesting
  static void debugReset() => _applied = null;

  /// Holds or releases the locks; repeats are not sent again.
  static Future<void> set({required bool enabled}) async {
    if (_applied == enabled) return;
    _applied = enabled;
    debugLog?.call(enabled: enabled);
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setKeepAlive', {'enabled': enabled});
    } on Object catch (error) {
      developer.log('Keep-alive failed', name: 'LivePlay', error: error);
    }
  }
}

/// The handler behind the system media notification: its buttons call the
/// room's commands.
class _RoomAudioHandler extends audio.BaseAudioHandler {
  Future<void> Function()? onPlay;
  Future<void> Function()? onPause;
  Future<void> Function()? onStop;
  Future<void> Function()? onTaskRemoval;
  Future<void>? _taskRemoval;
  // Music (A17.7): the queue's buttons and the position.
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;
  Future<void> Function(Duration position)? onSeek;

  @override
  Future<void> onTaskRemoved() => _taskRemoval ??= _finishTaskRemoval();

  Future<void> _finishTaskRemoval() async {
    final owner = RoomMediaNotification._owner;
    try {
      // Closing a task must not wait forever for a driver or metadata write.
      // The runtime still owns any retirement continuing after this grace.
      await (onTaskRemoval ?? onStop)?.call().timeout(const Duration(seconds: 3));
    } on Object catch (error, stackTrace) {
      developer.log('Task playback retirement failed', name: 'LivePlay', error: error, stackTrace: stackTrace);
    } finally {
      // A new playback owner can appear while the old native resources retire.
      // Its notification and newly opened task must not be closed by this callback.
      if (RoomMediaNotification._owner == null || identical(RoomMediaNotification._owner, owner)) {
        playbackState.add(
          playbackState.value.copyWith(playing: false, processingState: audio.AudioProcessingState.idle),
        );
        await PictureInPicture.closeTask();
      }
    }
  }

  @override
  Future<void> skipToNext() async {
    await onNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onPrevious?.call();
  }

  @override
  Future<void> seek(Duration position) async {
    await onSeek?.call(position);
  }

  @override
  Future<void> play() async {
    await onPlay?.call();
  }

  @override
  Future<void> pause() async {
    await onPause?.call();
  }

  @override
  Future<void> stop() async {
    await onStop?.call();
    playbackState.add(playbackState.value.copyWith(playing: false, processingState: audio.AudioProcessingState.idle));
  }
}

/// The media notification's buttons with the app's words, so a screen
/// reader says "暂停" instead of audio_service's "Pause" (U.14 c6).
@visibleForTesting
List<audio.MediaControl> mediaControls({required bool playing}) => [
  if (playing)
    audio.MediaControl(
      androidIcon: audio.MediaControl.pause.androidIcon,
      label: i18n('media_pause'),
      action: audio.MediaAction.pause,
    )
  else
    audio.MediaControl(
      androidIcon: audio.MediaControl.play.androidIcon,
      label: i18n('media_play'),
      action: audio.MediaAction.play,
    ),
  audio.MediaControl(
    androidIcon: audio.MediaControl.stop.androidIcon,
    label: i18n('media_stop'),
    action: audio.MediaAction.stop,
  ),
];

/// The system media notification of the room playing (3.x
/// `LiveAudioService` + `LiveAudioHandler`, audio_service): title,
/// streamer, cover, play/pause and stop; on Android, and on iOS as the lock
/// screen's and the control centre's "正在播放" (A18.1 c5).
abstract final class RoomMediaNotification {
  static Future<_RoomAudioHandler?>? _handler;
  static Object? _owner;

  /// Whether this platform shows it.
  static bool get available => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Sees every [show] (`show true`), [update] (`update false`) and [hide]
  /// (`hide`), also where [available] is false.
  @visibleForTesting
  static void Function(String event)? debugLog;

  static Future<_RoomAudioHandler?> _ensure() => _handler ??= () async {
    try {
      return await audio.AudioService.init(
        builder: _RoomAudioHandler.new,
        config: audio.AudioServiceConfig(
          androidNotificationChannelId: 'com.mystyle.purelive.audio',
          androidNotificationChannelName: i18n('audio_channel_name'),
          androidNotificationOngoing: true,
          // The one-colour television of the status bar (U.14 c2; 3.x used
          // the launcher icon, a white blob there).
          androidNotificationIcon: 'drawable/ic_stat_playback',
        ),
      );
    } on Object catch (error, stackTrace) {
      developer.log('Media notification failed', name: 'LivePlay', error: error, stackTrace: stackTrace);
      return null;
    }
  }();

  /// Shows [room] for [owner] (the room page) with its commands.
  static Future<void> show({
    required Object owner,
    required LiveRoom room,
    required bool playing,
    required Future<void> Function() play,
    required Future<void> Function() pause,
    required Future<void> Function() stop,
    Future<void> Function()? taskRemoved,
  }) async {
    debugLog?.call('show $playing');
    if (!available) return;
    _owner = owner;
    final handler = await _ensure();
    if (handler == null || !identical(_owner, owner)) return;
    handler
      ..onPlay = play
      ..onPause = pause
      ..onStop = stop
      ..onTaskRemoval = taskRemoved ?? stop
      .._taskRemoval = null;
    final cover = Uri.tryParse(room.cover.trim());
    handler.mediaItem.add(
      audio.MediaItem(
        id: '${room.platform}/${room.roomId}',
        title: room.title.trim().isEmpty ? room.displayNick(room.platform) : room.title,
        artist: room.displayNick(room.platform),
        artUri: cover != null && cover.hasScheme && cover.scheme.startsWith('http') ? cover : null,
      ),
    );
    _publish(owner, playing: playing);
  }

  /// Shows [playing] on the notification of [owner].
  static void update({required Object owner, required bool playing}) {
    debugLog?.call('update $playing');
    _publish(owner, playing: playing);
  }

  static void _publish(Object owner, {required bool playing}) {
    if (!available || !identical(_owner, owner)) return;
    unawaited(
      _ensure().then((handler) {
        if (handler == null || !identical(_owner, owner)) return;
        handler.playbackState.add(
          audio.PlaybackState(
            controls: mediaControls(playing: playing),
            androidCompactActionIndices: const [0, 1],
            processingState: audio.AudioProcessingState.ready,
            playing: playing,
          ),
        );
      }),
    );
  }

  /// Shows a music track for [owner] (A17.7: the TV's music player) with
  /// the queue's buttons (previous, play or pause, next) and a seek bar;
  /// the room's notification is unchanged.
  static Future<void> showTrack({
    required Object owner,
    required String id,
    required String title,
    required String artist,
    required String cover,
    required Duration duration,
    required Future<void> Function() play,
    required Future<void> Function() pause,
    required Future<void> Function() stop,
    required Future<void> Function() next,
    required Future<void> Function() previous,
    required Future<void> Function(Duration position) seek,
  }) async {
    debugLog?.call('track $title');
    if (!available) return;
    _owner = owner;
    final handler = await _ensure();
    if (handler == null || !identical(_owner, owner)) return;
    handler
      ..onPlay = play
      ..onPause = pause
      ..onStop = stop
      ..onTaskRemoval = stop
      .._taskRemoval = null
      ..onNext = next
      ..onPrevious = previous
      ..onSeek = seek;
    final art = Uri.tryParse(cover.trim());
    handler.mediaItem.add(
      audio.MediaItem(
        id: id,
        title: title,
        artist: artist,
        duration: duration > Duration.zero ? duration : null,
        artUri: art != null && art.hasScheme && art.scheme.startsWith('http') ? art : null,
      ),
    );
    updateTrack(owner: owner, playing: false, buffering: true, position: Duration.zero);
  }

  /// Shows the music player's state on the notification of [owner].
  static void updateTrack({
    required Object owner,
    required bool playing,
    required bool buffering,
    required Duration position,
  }) {
    if (!available || !identical(_owner, owner)) return;
    unawaited(
      _ensure().then((handler) {
        if (handler == null || !identical(_owner, owner)) return;
        handler.playbackState.add(
          audio.PlaybackState(
            controls: [
              audio.MediaControl(
                androidIcon: audio.MediaControl.skipToPrevious.androidIcon,
                label: i18n('media_previous'),
                action: audio.MediaAction.skipToPrevious,
              ),
              ...mediaControls(playing: playing).take(1),
              audio.MediaControl(
                androidIcon: audio.MediaControl.skipToNext.androidIcon,
                label: i18n('media_next'),
                action: audio.MediaAction.skipToNext,
              ),
            ],
            systemActions: const {audio.MediaAction.seek},
            androidCompactActionIndices: const [0, 1, 2],
            processingState: buffering ? audio.AudioProcessingState.buffering : audio.AudioProcessingState.ready,
            playing: playing,
            updatePosition: position,
          ),
        );
      }),
    );
  }

  /// Removes the notification of [owner].
  static Future<void> hide(Object owner) async {
    debugLog?.call('hide');
    if (!available || !identical(_owner, owner)) return;
    _owner = null;
    final handler = await _ensure();
    if (handler == null || _owner != null) return;
    handler
      ..onPlay = null
      ..onPause = null
      ..onStop = null
      ..onTaskRemoval = null
      ..onNext = null
      ..onPrevious = null
      ..onSeek = null
      ..playbackState.add(audio.PlaybackState());
  }
}

/// The room's background policy (3.x `PlaybackLifecycleCoordinator`):
/// leaving the app pauses after [hiddenPauseDelay] unless background play
/// is on or a sleep session runs (`shouldContinueInBackground`), and
/// coming back resumes what it paused. A picture nobody sees is not
/// judged stalled (`setPresentationVisible`); the media notification is
/// shown from the foreground (Android refuses to start it later).
///
/// O01.3 (docs/O-Android系统集成/O01-通知和前台服务/O01.3-后台播放增强): away from the app a
/// [BackgroundKeeper] decides what is kept. While the room plays,
/// reconnects, waits for its broadcast or for a call, the notification
/// says it plays (its foreground service stays: Android 12 and later
/// refuse to start it again from the background, and an app without one
/// loses the network in Doze and is frozen by HyperOS) and the wake and
/// Wi-Fi locks are held; a pause of the user's lets both go. A stream that
/// failed is tried again ([BackgroundKeeper.retry]), at once when the
/// network comes back ([online]). After [hiddenPauseDelay] away (not in
/// picture-in-picture) "后台只播声音" turns the video off and "后台断开弹幕"
/// closes the danmaku; coming back undoes both. "关闭画中画时暂停" pauses
/// a room whose picture-in-picture window was closed.
class RoomBackgroundPolicy with WidgetsBindingObserver {
  /// Creates the policy for [controller]; call [start].
  new({
    required this.controller,
    required this.settings,
    this.desktop,
    this.desktopMinimized,
    this.hiddenPauseDelay = const Duration(milliseconds: 1500),
    this.online,
    KeeperTimer? keeperTimer,
    DateTime Function()? now,
  }) {
    _keeper = BackgroundKeeper(retry: controller.retry, onChanged: _syncNotification, timer: keeperTimer, now: now);
  }

  /// The room.
  final LiveRoomController controller;

  /// `enableBackgroundPlay` and the O01.3 switches.
  final SettingsStore settings;

  /// Desktop policy; null follows the target platform (tests can override).
  final bool? desktop;

  /// Native minimization events; occlusion is a separate lifecycle signal.
  final ValueListenable<bool>? desktopMinimized;

  bool get _desktop =>
      desktop ??
      switch (defaultTargetPlatform) {
        TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
        _ => false,
      };

  bool _desktopOccluded = false;

  /// Android reports a short hidden/paused pair while rotating or entering
  /// picture-in-picture; only a longer stay counts (3.x 1.5 s).
  final Duration hiddenPauseDelay;

  /// Whether there is a network, as it changes (O01.3 R6); null: not
  /// followed.
  final Stream<bool>? online;

  /// Whether the audio focus paused the room and will resume it (G05.1);
  /// the room page sets it once the focus exists.
  bool Function()? interrupted;

  /// The user paused or stopped from the notification or the lock screen
  /// (the audio focus forgets a resume it planned).
  void Function()? onUserPause;

  /// The runtime owns real native retirement when the Android task is removed.
  Future<void> Function()? onTaskRemoved;

  late final BackgroundKeeper _keeper;
  Timer? _pauseTimer;
  Timer? _awayTimer;
  bool _hidden = false;
  bool _playingWhenHidden = false;
  bool _pausedByUs = false;
  bool _started = false;
  bool _disposed = false;
  bool _videoOffByUs = false;
  bool _danmakuOffByUs = false;
  bool _hiddenInPip = false;
  bool _pipJustClosed = false;
  StreamSubscription<PlaybackState>? _states;
  StreamSubscription<bool>? _backgroundSetting;
  StreamSubscription<bool>? _desktopPauseSetting;
  StreamSubscription<bool>? _network;

  PlaybackSession get _session => controller.session;

  bool get _continues => _desktop
      ? !settings.get(Settings.desktopPauseWhenMinimized)
      : shouldContinueInBackground(
          backgroundPlaybackEnabled: settings.get(Settings.enableBackgroundPlay),
          sleepSessionActive: controller.sleepSessionActive,
        );

  /// What is kept away from the app now (O01.3).
  @visibleForTesting
  BackgroundHold get hold => _keeper.hold;

  /// The keeper's tries since the stream last played (O01.3).
  @visibleForTesting
  int get backgroundTries => _keeper.tries;

  /// Whether the room may start playing by itself now (C01.5;
  /// [LiveRoomController.mayAutoStart]): on screen or in picture-in-picture,
  /// or away from the app when it was playing as the app left and may go on
  /// in the background. A room that was offline, failed or restricted when
  /// the app left waits until the app is back.
  bool get mayStartInBackground => !_hidden || PictureInPicture.active.value || (_playingWhenHidden && _continues);

  bool _mayStart() => mayStartInBackground;

  /// Starts following the app's lifecycle and the room's playback.
  void start() {
    if (_started) return;
    _started = true;
    controller.mayAutoStart = _mayStart;
    WidgetsBinding.instance.addObserver(this);
    _states = _session.states.listen((_) => _syncNotification());
    controller.addListener(_syncNotification);
    _backgroundSetting = settings.watch(Settings.enableBackgroundPlay).skip(1).listen((_) => _syncNotification());
    if (_desktop) {
      desktopMinimized?.addListener(_desktopMinimizedChanged);
      _desktopPauseSetting = settings.watch(Settings.desktopPauseWhenMinimized).skip(1).listen((_) {
        if (!_hidden || _disposed) return;
        _pauseTimer?.cancel();
        if (_continues && _pausedByUs) {
          _pausedByUs = false;
          unawaited(_session.resume());
        } else if (!_continues) {
          _scheduleHiddenPause();
        }
        _syncNotification();
      });
      _desktopMinimizedChanged();
    }
    _network = online?.listen((online) => _keeper.networkChanged(online: online));
    PictureInPicture.active.addListener(_onPipChanged);
  }

  bool _notified = false;

  /// The volume before the picture-in-picture window's mute (A07.24).

  /// The picture-in-picture window's mute action: the player's volume to 0
  /// or back; the room's kept volume does not change.
  Future<void> _toggleMute() async {
    await controller.toggleMute(save: false, fallback: 1);
  }

  /// What the notification shows now; repeats are not sent again.
  bool? _shownPlaying;

  KeeperInput _keeperInput(PlaybackState state, {required bool continues}) {
    final error = state.error;
    final stage = controller.stage;
    return KeeperInput(
      away: _hidden && continues,
      status: state.status,
      failure: state.failure,
      networkLost: error is PlayerException && error.code == networkLostCode,
      roomStopped: stage == RoomStage.offline || stage == RoomStage.unplayable,
      roomFailed: stage == RoomStage.failed,
      interrupted: interrupted?.call() ?? false,
    );
  }

  void _syncNotification() {
    if (_disposed) return;
    final state = _session.state;
    final status = state.status;
    final active = status == PlaybackStatus.playing || status == PlaybackStatus.buffering;
    PictureInPicture.bindPlayback(
      owner: this,
      playing: active,
      play: _session.resume,
      pause: _session.pause,
      muted: state.volume <= 0,
      toggleMute: _toggleMute,
    );
    final continues = _continues;
    final hold = _keeper.update(_keeperInput(state, continues: continues));
    final kept = _hidden && continues && hold != BackgroundHold.none;
    // O01.3 R3: the locks only while something is kept, not while the
    // user's pause waits.
    unawaited(BackgroundKeepAlive.set(enabled: kept));
    _keepVideoOff(state);
    // O01.3 R1: an open, a reconnect, a stopped broadcast or a call away
    // from the app show as playing, so the foreground service stays.
    final playing = state.isActive || kept;
    final wanted = (playing || status == PlaybackStatus.paused) && continues;
    if (wanted && !_notified) {
      // Only first shown from the foreground: Android 12 and later refuse
      // to start the media notification's foreground service from the
      // background, and a room that did not play when the app left does
      // not start there (C01.5).
      if (_hidden) return;
      _notified = true;
      _shownPlaying = playing;
      unawaited(
        RoomMediaNotification.show(
          owner: this,
          room: controller.room,
          playing: playing,
          play: _session.resume,
          pause: _userPause,
          stop: _userPause,
          taskRemoved: onTaskRemoved,
        ),
      );
    } else if (wanted) {
      _show(playing: playing);
    } else if (_notified && _hidden && continues) {
      // Paused by the user, or given up while it plays in the background:
      // kept, shown paused, so it is there when the room plays again and
      // the service is never started anew from the background (C01.5).
      _show(playing: false);
    } else if (_notified && status != PlaybackStatus.opening) {
      _notified = false;
      _shownPlaying = null;
      unawaited(RoomMediaNotification.hide(this));
    }
  }

  void _show({required bool playing}) {
    if (_shownPlaying == playing) return;
    _shownPlaying = playing;
    RoomMediaNotification.update(owner: this, playing: playing);
  }

  /// The notification's or the lock screen's pause and stop: nothing is
  /// kept or tried until the room plays again (O01.3).
  Future<void> _userPause() async {
    _pausedByUs = false;
    _keeper.markUserPause();
    onUserPause?.call();
    await _session.pause();
    // A failed stream stays "error" after a pause: look again.
    _syncNotification();
  }

  /// The notification's pause (tests).
  @visibleForTesting
  Future<void> pauseFromNotification() => _userPause();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_desktop) {
      _desktopOccluded = switch (state) {
        AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached => true,
        AppLifecycleState.resumed || AppLifecycleState.inactive => false,
      };
      _session.setPresentationVisible(visible: !_desktopOccluded && !(desktopMinimized?.value ?? false));
      return;
    }
    switch (state) {
      case AppLifecycleState.hidden || AppLifecycleState.paused || AppLifecycleState.detached:
        onHidden();
      case AppLifecycleState.resumed:
        onResumed();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _desktopMinimizedChanged() {
    if (_disposed) return;
    if (desktopMinimized?.value ?? false) {
      onHidden();
    } else {
      onResumed();
    }
    _session.setPresentationVisible(visible: !_desktopOccluded && !(desktopMinimized?.value ?? false));
  }

  /// The app left the screen.
  @visibleForTesting
  void onHidden() {
    if (_hidden || _disposed) return;
    _hidden = true;
    final status = _session.state.status;
    _playingWhenHidden =
        status == PlaybackStatus.opening || status == PlaybackStatus.buffering || status == PlaybackStatus.playing;
    _session.setPresentationVisible(visible: false);
    // O01.3 R9: the picture-in-picture window was closed (it went before
    // the app stopped, or goes after).
    _hiddenInPip = PictureInPicture.active.value;
    if (_pipJustClosed) {
      _pipJustClosed = false;
      _onPipClosed();
    }
    _scheduleAway();
    if (_continues) {
      _syncNotification();
      return;
    }
    _scheduleHiddenPause();
  }

  void _scheduleHiddenPause() {
    _pauseTimer?.cancel();
    _pauseTimer = Timer(hiddenPauseDelay, () {
      _pauseTimer = null;
      if (_disposed || !_hidden || _continues) return;
      final status = _session.state.status;
      if (status == PlaybackStatus.paused || status == PlaybackStatus.idle || status == PlaybackStatus.stopped) return;
      _pausedByUs = true;
      unawaited(_session.pause());
    });
  }

  /// The app is back on screen.
  @visibleForTesting
  void onResumed() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _awayTimer?.cancel();
    _awayTimer = null;
    _pipJustClosed = false;
    _hiddenInPip = false;
    if (!_hidden || _disposed) return;
    _hidden = false;
    _session.setPresentationVisible(visible: !_desktop || !_desktopOccluded);
    unawaited(BackgroundKeepAlive.set(enabled: false));
    _restoreAway();
    if (_pausedByUs) {
      _pausedByUs = false;
      unawaited(_session.resume());
    }
    // Came on air while the app was away (C01.5).
    if (controller.takeStartWhenBack()) unawaited(controller.load());
    _syncNotification();
  }

  void _onPipChanged() {
    if (_disposed) return;
    if (PictureInPicture.active.value) {
      _pipJustClosed = false;
      return;
    }
    if (!_hidden) {
      // The window went first: closed if the app stops next, expanded if
      // it resumes.
      _pipJustClosed = true;
      return;
    }
    if (!_hiddenInPip) return;
    // The app stopped first, then the window went: it was closed.
    _hiddenInPip = false;
    _onPipClosed();
    // The away switches waited while the window showed the room.
    _scheduleAway();
  }

  /// "关闭画中画时暂停" (O01.3 R9): only where the room would play on.
  void _onPipClosed() {
    if (!settings.get(Settings.pauseOnPipClose) || !_continues || !_session.state.isActive) return;
    _pausedByUs = true;
    _keeper.markUserPause();
    unawaited(_session.pause());
  }

  void _scheduleAway() {
    if (_desktop) return;
    _awayTimer?.cancel();
    _awayTimer = Timer(hiddenPauseDelay, () {
      _awayTimer = null;
      _applyAway();
    });
  }

  /// The away switches (O01.3 R7, R8), once the app stayed away and no
  /// picture-in-picture window shows the room.
  void _applyAway() {
    if (!_hidden || _disposed || PictureInPicture.active.value) return;
    if (!_danmakuOffByUs && settings.get(Settings.backgroundPauseDanmaku)) {
      _danmakuOffByUs = true;
      unawaited(controller.setDanmakuSuspended(suspended: true));
    }
    if (!_videoOffByUs && _continues && settings.get(Settings.backgroundAudioOnly) && !controller.audioOnly) {
      _videoOffByUs = true;
      _keepVideoOff(_session.state);
    }
  }

  bool _videoOffQueued = false;

  /// Turns the video off, again after a reopen brought it back. Never from
  /// inside the session's own state event (its stream is synchronous).
  void _keepVideoOff(PlaybackState state) {
    if (!_videoOffByUs || !_hidden || state.audioOnly || controller.audioOnly || !state.isActive) return;
    if (_videoOffQueued) return;
    _videoOffQueued = true;
    scheduleMicrotask(() {
      _videoOffQueued = false;
      final now = _session.state;
      if (_disposed || !_videoOffByUs || !_hidden || now.audioOnly || controller.audioOnly || !now.isActive) return;
      unawaited(_session.setAudioOnly(enabled: true));
    });
  }

  void _restoreAway() {
    if (_danmakuOffByUs) {
      _danmakuOffByUs = false;
      unawaited(controller.setDanmakuSuspended(suspended: false));
    }
    if (_videoOffByUs) {
      _videoOffByUs = false;
      // The user's own "纯音频" stays.
      if (!controller.audioOnly && _session.state.audioOnly) unawaited(_session.setAudioOnly(enabled: false));
    }
  }

  /// Stops following; releases the locks and the notification.
  void dispose() {
    if (_disposed) return;
    _pauseTimer?.cancel();
    _awayTimer?.cancel();
    _keeper.dispose();
    _disposed = true;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      PictureInPicture.active.removeListener(_onPipChanged);
      desktopMinimized?.removeListener(_desktopMinimizedChanged);
    }
    controller.removeListener(_syncNotification);
    if (controller.mayAutoStart == _mayStart) controller.mayAutoStart = null;
    unawaited(_backgroundSetting?.cancel());
    unawaited(_desktopPauseSetting?.cancel());
    unawaited(_states?.cancel());
    unawaited(_network?.cancel());
    unawaited(BackgroundKeepAlive.set(enabled: false));
    unawaited(RoomMediaNotification.hide(this));
    PictureInPicture.unbindPlayback(this);
  }
}

/// Arms what keeps the room on screen when the app is left (A07.25), as the
/// user chose ([leaveAppWindow]): the system's picture-in-picture growing out
/// of [picture] with the picture's [width]:[height], or the app's floating
/// window at [window] (its place on the screen; without the permission
/// nothing); only while [playing]. [owner] is the room page or the in-app
/// floating window.
Future<void> armLeaveWindow({
  required LeaveAppWindow choice,
  required bool playing,
  required int width,
  required int height,
  required Rect window,
  required double pixelRatio,
  required Object owner,
  Rect? picture,
}) async {
  final overlay = playing && choice == LeaveAppWindow.overlay && OverlayWindow.permitted.value;
  await PictureInPicture.setAutoEnter(
    enabled: playing && choice == LeaveAppWindow.pip,
    width: width,
    height: height,
    picture: picture,
    pixelRatio: pixelRatio,
    owner: owner,
  );
  await OverlayWindow.arm(enabled: overlay, window: window, pixelRatio: pixelRatio, owner: owner);
}
