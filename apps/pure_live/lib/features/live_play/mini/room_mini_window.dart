import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/mini_window.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/overlay_window.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';

/// The room page's mini window (U.2j): what the picture's mini window button
/// does on this platform and the state the page lays itself out by.
///
/// The button (placed by the picture's top bar) calls:
/// - [supported]: whether to show it (Android with picture-in-picture, a
///   desktop with the mini window);
/// - [preparing]: grey it out while a switch is under way;
/// - [enter]: on Android the in-app floating window (the page closes into
///   it, A07.25 c7), or the system's picture-in-picture with "改用系统画中画"
///   (with the "无法打开画中画" toast when the system turned it off, c9); the
///   desktop mini window on a computer.
///
/// The page shows only the picture while [compact] (picture-in-picture, the
/// moment before it, the desktop mini window) and the mini window's buttons
/// while [desktop].
class RoomMiniWindow extends ChangeNotifier {
  /// Creates the mini window of [controller]'s room.
  new({
    required this.controller,
    required this.settings,
    required this.leaveFullscreen,
    required this.closeRoom,
    VoidCallback? shrinkToMini,
    bool? android,
  }) : shrinkToMini = shrinkToMini ?? closeRoom,
       android = android ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    PictureInPicture.active.addListener(_changed);
    preparing.addListener(_changed);
    DesktopWindow.mini.addListener(_desktopChanged);
    _states = controller.session.states.listen(_followPicture);
  }

  StreamSubscription<PlaybackState>? _states;

  /// The room.
  final LiveRoomController controller;

  /// `windowsPipAlwaysOnTop`, `autoPipOnLeave`.
  final SettingsStore settings;

  /// Leaves the page's fullscreen before the window shrinks.
  final Future<void> Function() leaveFullscreen;

  /// Closes the room page without the in-app floating window (the desktop
  /// mini window's ✕).
  final VoidCallback closeRoom;

  /// Closes the room page into the in-app floating window (the mini window
  /// button on Android, A07.25 c7).
  final VoidCallback shrinkToMini;

  /// Android: the system's picture-in-picture.
  final bool android;

  /// A switch into or out of a mini window is under way (the button greys
  /// out; on Android the page already shows only the picture, so the system
  /// captures that frame, 3.x).
  final ValueNotifier<bool> preparing = ValueNotifier(false);

  bool _desktop = false;
  bool _disposed = false;
  _AutoPip? _autoPip;

  /// The window is the desktop mini window.
  bool get desktop => _desktop;

  /// Only the picture: picture-in-picture (or about to be), or the desktop
  /// mini window.
  bool get compact => PictureInPicture.active.value || (android && preparing.value) || _desktop;

  /// Which mini window the picture is in, or null.
  MiniKind? get kind => _desktop
      ? MiniKind.desktop
      : compact
      ? MiniKind.systemPip
      : null;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _desktopChanged() {
    // The shell gave the window back (an error path): leave the layout too.
    if (_desktop && !DesktopWindow.mini.value) {
      _desktop = false;
      _changed();
    }
  }

  /// Whether this platform has a mini window for the room.
  Future<bool> supported() async {
    if (DesktopWindow.miniAvailable) return true;
    // The in-app floating window needs nothing of the system (A07.25 c7);
    // "改用系统画中画" needs Android 8's picture-in-picture.
    if (android) {
      return PictureInPicture.onAndroid && (!settings.get(Settings.useSystemPip) || await PictureInPicture.supported());
    }
    return false;
  }

  /// The picture's width × height for the mini windows: the video's (before
  /// its first frame, its line's), 9 × 16 for a portrait picture when
  /// "小窗跟随真实画面比例" is off (F.1d).
  (int, int) get _pictureSize {
    final state = controller.session.state;
    final picture = expectedPictureSize(state);
    return miniPictureSize(
      width: picture.width,
      height: picture.height,
      portrait: state.expectsPortrait,
      followPortrait: settings.get(Settings.portraitPipFollowSource),
    );
  }

  double get _ratio {
    final (width, height) = _pictureSize;
    return width / height;
  }

  BuildContext? _picture;

  /// The page's picture (the player view) tells where it is, so Android's
  /// picture-in-picture grows out of it rather than out of the whole page
  /// (A07.24, `sourceRectHint`).
  void attachPicture(BuildContext context) {
    _picture = context;
    _autoPip?.pictureMoved();
  }

  /// The picture's screen's physical pixels per logical one.
  double get pixelRatio {
    final context = _picture;
    if (context == null || !context.mounted) return 1;
    return View.maybeOf(context)?.devicePixelRatio ?? 1;
  }

  /// The picture's place on screen, or null when it is not laid out.
  Rect? get pictureRect {
    final context = _picture;
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The window's title and subtitle (Android 13 and later): the streamer
  /// and the room's title (A07.24).
  String get _title => controller.room.nick.isNotEmpty ? controller.room.nick : controller.room.title;

  (int, int)? _shownSize;

  /// In picture-in-picture, the window follows the picture's shape (A07.24:
  /// another quality, a portrait stream's first frame; before, only an
  /// armed "离开应用时自动画中画" did).
  void _followPicture(PlaybackState _) {
    if (_disposed || !android || !PictureInPicture.active.value) return;
    final size = _pictureSize;
    if (size == _shownSize) return;
    _shownSize = size;
    unawaited(PictureInPicture.update(width: size.$1, height: size.$2));
  }

  /// The mini window button.
  Future<void> enter(BuildContext context) async {
    if (preparing.value || compact) return;
    if (DesktopWindow.miniAvailable) {
      await _enterDesktop();
      return;
    }
    if (!android) return;
    // A07.25 c7: the room shrinks into the in-app floating window and the app
    // stays (5.4.1 went to the system's picture-in-picture, which "改用系统画中画"
    // keeps); leaving the app then takes the window along when allowed.
    if (miniWindowKind(settings) == LeaveAppWindow.overlay) {
      await leaveFullscreen();
      if (!_disposed) shrinkToMini();
    } else {
      await _enterPip();
    }
  }

  Future<void> _enterPip() async {
    final availability = await PictureInPicture.availability();
    if (_disposed) return;
    if (availability == PipAvailability.disabled) {
      showPipDisabledToast();
      return;
    }
    if (availability == PipAvailability.unsupported) {
      AppNavigator.toast(i18n('pip_enter_failed'));
      return;
    }
    // Where the picture is before the page turns into it alone (A07.24).
    final picture = pictureRect;
    // Android captures the window as the animation starts: draw the picture
    // alone first (3.x `isPipPreparing`).
    preparing.value = true;
    await SchedulerBinding.instance.endOfFrame;
    final (width, height) = _pictureSize;
    _shownSize = (width, height);
    final entry = await PictureInPicture.enter(
      width: width,
      height: height,
      picture: picture,
      pixelRatio: pixelRatio,
      title: _title,
      subtitle: controller.room.title,
    );
    if (entry == PipEntry.entered && !PictureInPicture.active.value) {
      // Hold the picture-only layout until the activity says it is in.
      final done = Completer<void>();
      void inside() {
        if (PictureInPicture.active.value && !done.isCompleted) done.complete();
      }

      PictureInPicture.active.addListener(inside);
      await done.future.timeout(const Duration(seconds: 1), onTimeout: () {});
      PictureInPicture.active.removeListener(inside);
    }
    if (!_disposed) preparing.value = false;
    switch (entry) {
      case PipEntry.entered:
        break;
      case PipEntry.disabled:
        showPipDisabledToast();
      case PipEntry.failed:
        AppNavigator.toast(i18n('pip_enter_failed'));
    }
  }

  Future<void> _enterDesktop() async {
    preparing.value = true;
    try {
      await leaveFullscreen();
      final entered = await DesktopWindow.enterMini(
        aspectRatio: _ratio,
        onTop: settings.get(Settings.windowsPipAlwaysOnTop),
      );
      if (_disposed) return;
      if (!entered) {
        AppNavigator.toast(i18n('pip_enter_failed'));
        return;
      }
      _desktop = true;
      notifyListeners();
    } finally {
      if (!_disposed) preparing.value = false;
    }
  }

  /// Back to the room (button 1, a double click, Esc): the window gets its
  /// size and place back and the room plays on.
  Future<void> backToRoom() async {
    if (!_desktop || preparing.value) return;
    preparing.value = true;
    try {
      final restored = await DesktopWindow.exitMini();
      if (_disposed) return;
      if (!restored) {
        AppNavigator.toast(i18n('windows_pip_exit_failed'));
        return;
      }
      _desktop = false;
      notifyListeners();
    } finally {
      if (!_disposed) preparing.value = false;
    }
  }

  /// The mini window's ✕ (c2, J3): playback stops, the window goes back to
  /// the page before the room and down to the taskbar.
  Future<void> close() async {
    if (!_desktop) return;
    await controller.session.pause();
    // Hidden first, so the full-size window never flashes up.
    await DesktopWindow.exitMini(hidden: true);
    _desktop = false;
    if (!_disposed) notifyListeners();
    closeRoom();
    await DesktopWindow.minimize();
  }

  /// The pin (c3, J2): the same switch as the setting "小窗始终置顶".
  Future<void> togglePin() async {
    final onTop = !settings.get(Settings.windowsPipAlwaysOnTop);
    await settings.set(Settings.windowsPipAlwaysOnTop, onTop);
    if (!await DesktopWindow.setMiniOnTop(onTop: onTop)) {
      AppNavigator.toast(i18n('windows_pip_always_on_top_apply_failed'));
    }
  }

  /// Whether the desktop lets the mini window stay on top.
  bool get canPin => DesktopWindow.miniHost?.canPin ?? false;

  /// Starts leaving the app into picture-in-picture by itself while the room
  /// plays (J1, `autoPipOnLeave`); Android only.
  void startAutoPip() {
    if (!android || _autoPip != null) return;
    _autoPip = _AutoPip(this)..start();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_states?.cancel());
    PictureInPicture.active.removeListener(_changed);
    DesktopWindow.mini.removeListener(_desktopChanged);
    _autoPip?.dispose();
    preparing.dispose();
    super.dispose();
  }
}

/// Keeps leaving the app from the room page in step with the room (J1,
/// "离开应用时自动小窗"): the app's floating window or, with "改用系统画中画", the
/// system's picture-in-picture, armed only while the setting is on, the room
/// page is on top and the picture plays.
final class _AutoPip {
  new(this.mini);

  final RoomMiniWindow mini;
  StreamSubscription<PlaybackState>? _states;
  StreamSubscription<Setting<Object>>? _settings;
  bool? _armed;
  (int, int)? _size;

  LiveRoomController get _room => mini.controller;

  void start() {
    _states = _room.session.states.listen((_) => _sync());
    _settings = mini.settings.changes.listen((setting) {
      if (setting.key == Settings.autoPipOnLeave.key ||
          setting.key == Settings.useSystemPip.key ||
          setting.key == Settings.floatWindowSize.key ||
          setting.key == Settings.portraitPipFollowSource.key) {
        _sync();
      }
    });
    _room.addListener(_sync);
    liveRouteObserver.currentRoute.addListener(_sync);
    OverlayWindow.permitted.addListener(_sync);
    // A07.25 c9: armed for the floating window but not allowed, leaving the
    // app hides the room; back, the toast says once how to keep it.
    _lifecycle = AppLifecycleListener(
      onPause: () {
        if ((_armed ?? false) && _choice == LeaveAppWindow.overlay && !OverlayWindow.permitted.value) {
          OverlayTip.missed();
        }
      },
      onResume: () => OverlayTip.comeBack(mini.settings),
    );
    _sync();
  }

  AppLifecycleListener? _lifecycle;

  void _sync() {
    final state = _room.session.state;
    final choice = leaveAppWindow(mini.settings);
    final armed = shouldAutoEnterPip(
      enabled: choice != LeaveAppWindow.none,
      onTop: liveRouteObserver.currentRoute.value == RoutePath.kLivePlay,
      stage: _room.stage,
      status: state.status,
      audioOnly: _room.audioOnly,
    );
    final (width, height) = mini._pictureSize;
    final picture = armed ? mini.pictureRect : null;
    final overlay = OverlayWindow.permitted.value;
    if (armed == _armed &&
        choice == _choice &&
        overlay == _overlay &&
        (!armed || (_size == (width, height) && _picture == picture))) {
      return;
    }
    final titled = armed && !(_armed ?? false);
    _armed = armed;
    _choice = choice;
    _overlay = overlay;
    _size = (width, height);
    _picture = picture;
    if (armed) mini._shownSize = (width, height);
    if (titled) unawaited(PictureInPicture.update(title: mini._title, subtitle: _room.room.title));
    unawaited(
      armLeaveWindow(
        choice: choice,
        playing: armed,
        width: width,
        height: height,
        picture: picture,
        window: overlayWindowRect(mini.settings, width / height),
        pixelRatio: mini.pixelRatio,
        owner: this,
      ),
    );
  }

  LeaveAppWindow? _choice;
  bool? _overlay;

  Rect? _picture;

  /// The picture moved (fullscreen, a turn): the hint follows, after the
  /// frame that laid it out.
  void pictureMoved() {
    if (!(_armed ?? false)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void dispose() {
    unawaited(_states?.cancel());
    unawaited(_settings?.cancel());
    _room.removeListener(_sync);
    liveRouteObserver.currentRoute.removeListener(_sync);
    OverlayWindow.permitted.removeListener(_sync);
    _lifecycle?.dispose();
    if (_armed ?? false) {
      unawaited(PictureInPicture.setAutoEnter(enabled: false, owner: this));
      unawaited(OverlayWindow.arm(enabled: false, owner: this));
    }
  }
}

/// The room page's [RoomMiniWindow] for the picture's buttons.
class RoomMiniScope extends InheritedNotifier<RoomMiniWindow> {
  /// Provides [notifier] to [child].
  const new({required RoomMiniWindow super.notifier, required super.child, super.key});

  /// The room's mini window, or null outside a room page.
  static RoomMiniWindow? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RoomMiniScope>()?.notifier;
}

/// c9: the system settings turned picture-in-picture off for this app; "去设置"
/// opens this app's page there (3.x ignored the refusal). B09 c8: a toast
/// that waits for "去设置" or ✕ (U.1d c13, one the user has to answer), not
/// a centred dialog over the picture, which is often in fullscreen.
void showPipDisabledToast() => AppNavigator.showToast(
  AppToast(
    i18n('pip_disabled_toast', args: {'app': i18n('app_name')}),
    key: const ValueKey('pip-disabled-toast'),
    actionLabel: i18n('pip_open_settings'),
    onAction: () => unawaited(_openPipSettings()),
    persistent: true,
  ),
);

Future<void> _openPipSettings() async {
  if (!await PictureInPicture.openSettings()) AppNavigator.toast(i18n('pip_enter_failed'));
}

/// The app's floating window from a room page (A07.25): the in-app window's
/// size ("小窗大小") for a picture of [aspectRatio], in the bottom right corner.
Rect overlayWindowRect(SettingsStore settings, double aspectRatio) {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final screen = view.physicalSize / view.devicePixelRatio;
  final size = inAppMiniWindowSize(
    screen: screen,
    aspectRatio: aspectRatio,
    size: settings.get(Settings.floatWindowSize),
  );
  final bottom = view.padding.bottom / view.devicePixelRatio + inAppMiniMargin;
  return Offset(screen.width - size.width - inAppMiniMargin, screen.height - size.height - bottom) & size;
}

/// Leaving the app without "显示在其他应用的上层" hid the floating window (A07.25
/// c9, choice J2): back in the app, once ever, a toast says it can stay
/// over other apps, with "去开启" (the system's page for it).
abstract final class OverlayTip {
  static bool _missed = false;

  /// The window would have gone over the other apps had it been allowed.
  static void missed() => _missed = true;

  /// Back in the app: the toast, the first time only.
  static void comeBack(SettingsStore settings) {
    if (!_missed) return;
    _missed = false;
    if (OverlayWindow.permitted.value || settings.get(Settings.floatOverlayTipShown)) return;
    unawaited(settings.set(Settings.floatOverlayTipShown, true));
    AppNavigator.showToast(
      AppToast(
        i18n('overlay_tip'),
        key: const ValueKey('overlay-tip'),
        actionLabel: i18n('overlay_permission_open'),
        onAction: () => unawaited(OverlayWindow.openSettings()),
      ),
    );
  }
}
