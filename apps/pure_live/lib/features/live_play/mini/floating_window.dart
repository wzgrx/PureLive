import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/mini_window.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/logic/room_runtime.dart';
import 'package:pure_live/features/live_play/mini/mini_player.dart';
import 'package:pure_live/features/live_play/mini/room_mini_window.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/overlay_window.dart';
import 'package:pure_live/platform/system_gestures.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';

/// The in-app floating window (3.x `showAppFloating`, U.2j-b): the room that
/// played when its page closed ("退出小窗播放" on), over every page, in the
/// bottom-right corner (above the home page's bottom bar), as wide as
/// [inAppMiniBase] and "小窗大小" say. It can be dragged anywhere and stays
/// on screen when the window turns or shrinks; its grip or two fingers
/// resize it, kept for the next time (A07.22); menus, dialogs and sheets
/// hide it (it plays on). The app puts it over its pages; it shows
/// [FloatingRoom.instance].
class FloatingRoomLayer extends StatefulWidget {
  /// Creates the layer.
  const new({this.room, super.key});

  /// The floating room ([FloatingRoom.instance] by default; tests give
  /// their own).
  final FloatingRoom? room;

  @override
  State<FloatingRoomLayer> createState() => _FloatingRoomLayerState();
}

class _FloatingRoomLayerState extends State<FloatingRoomLayer> {
  late final FloatingRoom _room = widget.room ?? FloatingRoom.instance;
  final GlobalKey<OverlayState> _overlay = GlobalKey();
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    _room
      ..attachLayer()
      ..addListener(_changed);
    liveRouteObserver.openPopups.addListener(_changed);
    liveRouteObserver.currentRoute.addListener(_changed);
    PictureInPicture.active.addListener(_changed);
    OverlayWindow.active.addListener(_overlayChanged);
  }

  /// The app's floating window came or went (A07.25). Coming back, a room
  /// whose page the window took over opens its page again (the same player).
  void _overlayChanged() {
    _changed();
    if (OverlayWindow.active.value) return;
    final room = OverlayWindow.fromRoomPage;
    OverlayWindow.fromRoomPage = null;
    final runtime = _room.runtime;
    if (room != null && runtime != null && runtime.holds(room)) {
      unawaited(AppNavigator.toLiveRoomDetail(liveRoom: runtime.controller.room));
    }
  }

  @override
  void dispose() {
    _room
      ..removeListener(_changed)
      ..detachLayer();
    liveRouteObserver.openPopups.removeListener(_changed);
    liveRouteObserver.currentRoute.removeListener(_changed);
    PictureInPicture.active.removeListener(_changed);
    OverlayWindow.active.removeListener(_overlayChanged);
    _entry?.remove();
    _entry?.dispose();
    super.dispose();
  }

  /// The room, a menu or the page on top changed: rebuild, after the frame
  /// when this came in the middle of one (a room page hands over from its
  /// dispose).
  void _changed() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _changed());
      SchedulerBinding.instance.ensureVisualUpdate();
      return;
    }
    setState(() {});
    _entry?.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    // Its own overlay, so the buttons' tooltips work above the navigator.
    _entry ??= OverlayEntry(builder: _window);
    return Overlay(key: _overlay, initialEntries: [_entry!]);
  }

  Widget _window(BuildContext context) {
    final runtime = _room.runtime;
    if (runtime == null) return const SizedBox.shrink();
    // Hidden, not stopped, while a menu, dialog or sheet is open (3.x
    // `PopupAwareVisibility`).
    final hidden =
        liveRouteObserver.openPopups.value > 0 && !PictureInPicture.active.value && !OverlayWindow.active.value;
    return Offstage(
      offstage: hidden,
      child: _FloatingWindow(
        key: ObjectKey(runtime),
        runtime: runtime,
        route: liveRouteObserver.currentRoute.value,
        room: _room,
        onBackToRoom: () {
          // From the floating window over other apps: back into the app,
          // into the room (A07.25).
          if (OverlayWindow.active.value) {
            OverlayWindow.fromRoomPage = null;
            unawaited(OverlayWindow.backToApp());
          }
          unawaited(AppNavigator.toLiveRoomDetail(liveRoom: runtime.controller.room));
        },
        onClose: () {
          if (OverlayWindow.active.value) {
            OverlayWindow.fromRoomPage = null;
            unawaited(OverlayWindow.close());
          }
          unawaited(_room.close());
        },
      ),
    );
  }
}

class _FloatingWindow extends ConsumerStatefulWidget {
  const new({
    required this.runtime,
    required this.route,
    required this.room,
    required this.onBackToRoom,
    required this.onClose,
    super.key,
  });

  final RoomRuntime runtime;
  final String route;

  /// Where the last window settled ([FloatingRoom.placement]).
  final FloatingRoom room;
  final VoidCallback onBackToRoom;
  final VoidCallback onClose;

  @override
  ConsumerState<_FloatingWindow> createState() => _FloatingWindowState();
}

/// What the window is laid out by, from the last build: the area, the
/// clearances, the picture's ratio and the size settings.
final class _Layout {
  const new({
    required this.screen,
    required this.area,
    required this.ratio,
    required this.topClearance,
    required this.bottomClearance,
    required this.reachTop,
    required this.reachBottom,
    required this.gestureLeft,
    required this.gestureRight,
    required this.sizeName,
    required this.stored,
    required this.portraitWindow,
  });

  final Size screen;
  final Size area;
  final double ratio;
  final double topClearance;
  final double bottomClearance;

  /// How far a window the user moved may go ([inAppMiniReach]).
  final double reachTop;
  final double reachBottom;

  /// The strips of the left and right edges the system's back gesture
  /// takes (full-screen gestures).
  final double gestureLeft;
  final double gestureRight;

  /// How much of a window [width] wide tucked into [dock] shows
  /// ([inAppMiniPeekFor]).
  double peekOf(MiniDock? dock, double width) =>
      inAppMiniPeekFor(gestureInset: dock == MiniDock.left ? gestureLeft : gestureRight, width: width);
  final String sizeName;

  /// The kept resize of this picture's kind (A07.22).
  final double stored;
  final bool portraitWindow;

  Size get room => inAppMiniRoom(area: area, topClearance: topClearance, bottomClearance: bottomClearance);

  double bounded(double wanted) =>
      inAppMiniScale(screen: screen, aspectRatio: ratio, scale: wanted, size: sizeName, room: room);

  Size sized(double scale) =>
      inAppMiniWindowSize(screen: screen, aspectRatio: ratio, size: sizeName, scale: scale, room: room);
}

class _FloatingWindowState extends ConsumerState<_FloatingWindow> with TickerProviderStateMixin {
  /// Where the user left it (top-left), or null for the corner; and the
  /// side it is tucked into (A07.24).
  Offset? _dragged;
  MiniDock? _dock;

  /// A finger is moving it: it may go past the sides then.
  bool _dragging = false;

  /// The drag began on the tucked strip (its detector stays till the end).
  bool _pullingOut = false;

  /// A resize (A07.22): the window when it began, its scale then, which
  /// corner stays, and whether it is a portrait picture's window.
  Rect? _resizeFrom;
  double _resizeFromScale = 1;
  MiniResizeAnchor _anchor = MiniResizeAnchor.centre;
  bool _resizePortrait = false;

  /// The scale shown while resizing, and after it until the stored one
  /// arrives (the store writes in the background).
  double? _scale;

  /// A07.24: a drag, a resize or the settling slide changes only the
  /// window's place and size; the picture under it is not rebuilt.
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final ValueNotifier<MiniGripCorner?> _grip = ValueNotifier(null);

  /// Whether the window's buttons (and its grip) show.
  final ValueNotifier<bool> _buttons = ValueNotifier(false);

  /// The clock of the settling slide; [_slideRun] says where it is.
  late final AnimationController _settle = AnimationController.unbounded(vsync: this)..addListener(_moved);
  _SlideSimulation? _slideRun;
  _Layout? _layout;

  /// Android's picture-in-picture is on this device (the window's button,
  /// and leaving the app turns the window into it; A07.24).
  bool _pipSupported = false;
  StreamSubscription<PlaybackState>? _states;
  bool? _armed;
  (int, int)? _armedSize;
  Rect? _armedRect;

  /// The picture's width × height for picture-in-picture.
  (int, int) _pictureSize = (16, 9);

  /// A07.25 M1, M8: the window glides from [_morphFrom] to where it belongs
  /// (out of the room page's picture as it opens; to its new place when a
  /// page with a bottom bar, a turn or a new size moves it). Its value runs
  /// from 0 to 1 on [AppMotion.floatingSpring]; the window is laid out where
  /// it belongs and only drawn moved and scaled, so nothing in it is laid out
  /// again on the way.
  late final AnimationController _morph = AnimationController.unbounded(vsync: this)..addListener(_moved);
  Rect? _morphFrom;
  bool _morphStarted = false;
  bool _morphQueued = false;
  int _morphRun = 0;

  /// Where the room page showed the picture, for M1 (taken once).
  Rect? _enterFrom;

  /// The window as last drawn.
  Rect? _lastShown;

  /// A07.25 M2, M3: the window going, a little larger and fading (back to the
  /// room) or smaller and fading (✕), before it does.
  late final AnimationController _exit = AnimationController(vsync: this)..addListener(_moved);
  bool _exitGrows = false;

  @override
  void initState() {
    super.initState();
    final from = widget.room.takeEnterFrom();
    // Over other apps or in picture-in-picture it fills the screen: nothing
    // to come out of.
    _enterFrom = OverlayWindow.active.value || PictureInPicture.active.value ? null : from;
    final placement = widget.room.placement;
    _dragged = placement?.offset;
    _free = placement?.offset != null;
    _dock = placement?.dock;
    // A07.25 c6: the first window of a run opens where the last run left it.
    _restoreSaved = placement == null;
    unawaited(
      PictureInPicture.supported().then((supported) {
        if (mounted && supported != _pipSupported) setState(() => _pipSupported = supported);
      }),
    );
    _states = widget.runtime.session.states.listen((_) => _syncAutoPip());
    OverlayWindow.permitted.addListener(_syncAutoPipLater);
    _frame.addListener(_syncExclusionLater);
    _buttons.addListener(_syncExclusionLater);
    _settle.addStatusListener(_settleStatus);
    OverlayWindow.placed.addListener(_overlayPlaced);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        // The system forgets the excluded strip while the app is away.
        _excluded = null;
        _syncExclusionLater();
        OverlayTip.comeBack(widget.runtime.controller.store.settings);
      },
      // A07.25 c9: it would have gone over the other apps but may not.
      onPause: () {
        if ((_armed ?? false) && _armedChoice == LeaveAppWindow.overlay && !OverlayWindow.permitted.value) {
          OverlayTip.missed();
        }
      },
    );
  }

  /// The floating window over other apps went (A07.25 c8): this window takes
  /// its place and size, so it is where the user left it out there; once it
  /// is laid out in the app again (over other apps it fills that window, and
  /// sizes measured there are that window's).
  void _overlayPlaced() {
    final placed = OverlayWindow.placed.value;
    if (placed == null || !mounted) return;
    OverlayWindow.placed.value = null;
    _pendingPlaced = placed;
    _enterFrom = null;
    _moved();
  }

  ({Rect rect, String? tucked})? _pendingPlaced;

  /// [_overlayPlaced] applied in [layout], the app's.
  void _takePlaced(_Layout layout) {
    final placed = _pendingPlaced;
    if (placed == null) return;
    _pendingPlaced = null;
    final setting = layout.portraitWindow ? Settings.floatWindowPortraitScale : Settings.floatWindowLandscapeScale;
    final natural = layout.sized(1);
    final kept = natural.width > 0 ? setting.normalize(layout.bounded(placed.rect.width / natural.width)) : null;
    if (kept != null) {
      _scale = kept;
      _resizePortrait = layout.portraitWindow;
    }
    final dock = switch (placed.tucked) {
      'left' => MiniDock.left,
      'right' => MiniDock.right,
      _ => null,
    };
    _settle.stop();
    _dragged = placed.rect.topLeft;
    _dock = dock;
    _free = true;
    _lastShown = null;
    // Stored after this frame (not while building).
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (kept != null) unawaited(widget.runtime.controller.store.settings.set(setting, kept));
      widget.room.placement = (offset: placed.rect.topLeft, dock: dock);
      _savePlacement();
      _placeGrip();
    });
  }

  AppLifecycleListener? _lifecycle;

  void _settleStatus(AnimationStatus status) {
    if (_settle.isAnimating) return;
    // Settled where the finger sent it: no glide from its last frame (M8 is
    // for moves the window did not make itself).
    _lastShown = null;
    _syncExclusionLater();
    // Leaving the app now takes it from here (the K90 check: it was armed
    // where the slide began).
    _syncAutoPipLater();
  }

  /// Whether the saved place ([Settings.floatWindowPosition]) is still to be
  /// put back, once the area is known.
  bool _restoreSaved = false;

  /// Keeps the window's place across restarts (A07.25 c6), as fractions of
  /// the area, so a turned or another screen puts it where it belongs.
  void _savePlacement() {
    final layout = _layout;
    if (layout == null) return;
    final placement = widget.room.placement;
    unawaited(
      widget.runtime.controller.store.settings.set(
        Settings.floatWindowPosition,
        encodeMiniPlacement(offset: placement?.offset, dock: placement?.dock, area: layout.area),
      ),
    );
  }

  /// Whether the user dragged the window: it may then go up to the status
  /// bar and down to the system's gesture bar ([inAppMiniReach]).
  bool _free = false;

  List<Rect>? _excluded;
  bool? _overlayGripExcluded;
  bool _exclusionQueued = false;

  void _syncExclusionLater() {
    if (_exclusionQueued) return;
    _exclusionQueued = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _exclusionQueued = false;
        _syncExclusion();
      })
      ..ensureVisualUpdate();
  }

  /// A window tucked into a side keeps its strip (its middle, up to 200 high)
  /// out of the system's back gesture, so pulling it back out does not go
  /// back (A07.25 c5, the user's K90 report); nothing otherwise.
  void _syncExclusion() {
    if (!mounted) return;
    final layout = _layout;
    // Kept while a pull out of the side is under way (the system decides
    // again on later moves on some phones); gone once it settled out.
    if (_dragging || _settle.isAnimating) return;
    final grip = _buttons.value && _grip.value != null;
    if (OverlayWindow.active.value) {
      // Over other apps the native window keeps its own (the tucked strip
      // there, the grip from here).
      if (grip != _overlayGripExcluded) {
        _overlayGripExcluded = grip;
        unawaited(OverlayWindow.excludeGrip(on: grip));
      }
      return;
    }
    _overlayGripExcluded = null;
    final List<Rect> rects;
    if (layout == null || PictureInPicture.active.value) {
      rects = const [];
    } else if (_dock != null) {
      rects = [inAppMiniExclusion(_rect(layout))];
    } else if (grip) {
      // The grip in the window's corner: against an edge it would sit in the
      // back gesture's strip (the K90 check: pulling it went back).
      final rect = _rect(layout);
      rects = [Rect.fromLTRB(rect.right - miniButtonSize, rect.bottom - miniButtonSize, rect.right, rect.bottom)];
    } else {
      rects = const [];
    }
    if (listEquals(rects, _excluded)) return;
    _excluded = rects;
    unawaited(SystemGestureExclusion.set(rects, pixelRatio: View.maybeOf(context)?.devicePixelRatio ?? 1));
  }

  @override
  void didUpdateWidget(_FloatingWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route) _syncAutoPipLater();
  }

  @override
  void dispose() {
    unawaited(_states?.cancel());
    if (_armed ?? false) {
      unawaited(PictureInPicture.setAutoEnter(enabled: false, owner: this));
      unawaited(OverlayWindow.arm(enabled: false, owner: this));
    }
    OverlayWindow.permitted.removeListener(_syncAutoPipLater);
    _frame.removeListener(_syncExclusionLater);
    _buttons.removeListener(_syncExclusionLater);
    _settle.removeStatusListener(_settleStatus);
    _lifecycle?.dispose();
    OverlayWindow.placed.removeListener(_overlayPlaced);
    if (_excluded?.isNotEmpty ?? false) unawaited(SystemGestureExclusion.set(const []));
    _morph.dispose();
    _exit.dispose();
    _settle.dispose();
    _frame.dispose();
    _grip.dispose();
    _buttons.dispose();
    super.dispose();
  }

  /// [_syncAutoPip] after the next frame, which it asks for (a change of the
  /// permission alone draws nothing).
  void _syncAutoPipLater() {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => _syncAutoPip())
      ..ensureVisualUpdate();
  }

  /// Leaving the app takes the window along (A07.25 c8): the same window
  /// over the other apps where "显示在其他应用的上层" is given, or Android's
  /// picture-in-picture growing out of it with "改用系统画中画"; while it
  /// plays and no room page is on top (a room page arms its own). Without
  /// the permission it hides until the app is back (c9).
  void _syncAutoPip() {
    if (!mounted || defaultTargetPlatform != TargetPlatform.android) return;
    final runtime = widget.runtime;
    final status = runtime.session.state.status;
    final choice = leaveAppWindow(runtime.controller.store.settings);
    final armed = shouldAutoEnterPip(
      enabled: choice != LeaveAppWindow.none,
      onTop: widget.route != RoutePath.kLivePlay,
      stage: runtime.controller.stage,
      status: status,
      audioOnly: runtime.controller.audioOnly,
    );
    final layout = _layout;
    final away = PictureInPicture.active.value || OverlayWindow.active.value;
    final rect = armed && layout != null && !away ? _rect(layout) : null;
    // Away from the app the window stays armed as it was.
    if (away) return;
    final overlay = OverlayWindow.permitted.value;
    if (armed == _armed &&
        choice == _armedChoice &&
        overlay == _armedOverlay &&
        (!armed || (_armedSize == _pictureSize && _armedRect == rect))) {
      return;
    }
    _armedChoice = choice;
    _armedOverlay = overlay;
    final titled = armed && !(_armed ?? false);
    _armed = armed;
    _armedSize = _pictureSize;
    _armedRect = rect;
    if (titled) {
      unawaited(PictureInPicture.update(title: _title, subtitle: runtime.controller.room.title));
    }
    unawaited(
      armLeaveWindow(
        choice: choice,
        playing: armed && rect != null,
        width: _pictureSize.$1,
        height: _pictureSize.$2,
        picture: rect,
        window: rect ?? Rect.zero,
        pixelRatio: View.maybeOf(context)?.devicePixelRatio ?? 1,
        owner: this,
      ),
    );
  }

  LeaveAppWindow? _armedChoice;
  bool? _armedOverlay;

  String get _title {
    final room = widget.runtime.controller.room;
    return room.nick.isNotEmpty ? room.nick : room.title;
  }

  /// The window's picture-in-picture button (A07.24, A07.25 c13): the
  /// system's picture-in-picture once, growing out of the window.
  Future<void> _enterPip() async {
    final layout = _layout;
    final availability = await PictureInPicture.availability();
    if (!mounted) return;
    if (availability == PipAvailability.disabled) {
      showPipDisabledToast();
      return;
    }
    final entry = await PictureInPicture.enter(
      width: _pictureSize.$1,
      height: _pictureSize.$2,
      picture: layout == null ? null : _rect(layout),
      pixelRatio: View.maybeOf(context)?.devicePixelRatio ?? 1,
      title: _title,
      subtitle: widget.runtime.controller.room.title,
    );
    if (!mounted) return;
    switch (entry) {
      case PipEntry.entered:
        break;
      case PipEntry.disabled:
        showPipDisabledToast();
      case PipEntry.failed:
        AppNavigator.toast(i18n('pip_enter_failed'));
    }
  }

  void _moved() => _frame.value++;

  /// The window's size now.
  Size _size(_Layout layout) {
    final scale = _resizePortrait == layout.portraitWindow ? _scale ?? layout.stored : layout.stored;
    return layout.sized(scale);
  }

  /// The window's place and size now.
  Rect _rect(_Layout layout) {
    final size = _size(layout);
    final Offset offset;
    final run = _slideRun;
    if (_settle.isAnimating && run != null) {
      offset = run.at(_settle.value);
    } else if (_dragging) {
      final wanted = _dragged ?? Offset.zero;
      offset = inAppMiniDragOffset(
        area: layout.area,
        window: size,
        wanted: wanted,
        topClearance: layout.reachTop,
        bottomClearance: layout.reachBottom,
        peek: layout.peekOf(
          wanted.dx + size.width / 2 < layout.area.width / 2 ? MiniDock.left : MiniDock.right,
          size.width,
        ),
      );
    } else {
      // Only a window the user dragged reaches the bars; one resized in
      // its corner keeps the corner's clearances.
      final moved = _free || _dock != null;
      offset = inAppMiniOffset(
        area: layout.area,
        window: size,
        dragged: _dragged,
        dock: _dock,
        topClearance: moved ? layout.reachTop : layout.topClearance,
        bottomClearance: moved ? layout.reachBottom : layout.bottomClearance,
        peek: layout.peekOf(_dock, size.width),
      );
    }
    return offset & size;
  }

  /// Puts the grip on the corner towards the middle (after the frame: it
  /// sits inside the surface).
  void _placeGrip() {
    final layout = _layout;
    if (layout == null) return;
    // Over other apps the native side knows which way it grows.
    if (OverlayWindow.active.value) {
      _grip.value = MiniGripCorner.bottomLeft;
      return;
    }
    _grip.value = _dock != null ? null : inAppMiniGripCorner(window: _rect(layout), area: layout.area);
  }

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Starts a glide from [from] after this frame, which draws the window
  /// still at [from] (M1, M8).
  void _queueMorph(Rect from) {
    _morphFrom = from;
    _morphStarted = false;
    if (_morphQueued) return;
    _morphQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _morphQueued = false;
      if (!mounted || _morphFrom == null) return;
      final run = ++_morphRun;
      _morphStarted = true;
      _morph.value = 0;
      _morph
          .animateWith(
            SpringSimulation(
              AppMotion.floatingSpring,
              0,
              1,
              0,
              tolerance: const Tolerance(distance: 0.002, velocity: 0.02),
            ),
          )
          .whenCompleteOrCancel(() {
            if (!mounted || run != _morphRun) return;
            _morphFrom = null;
            _morphStarted = false;
            // Arrived: the last frame of the glide is no place to glide from.
            _lastShown = null;
            _moved();
          });
    });
  }

  /// Where the window is drawn while it glides towards [target].
  Rect _shown(Rect target) {
    final from = _morphFrom;
    if (from == null) return target;
    final t = _morphStarted ? _morph.value.clamp(0.0, 1.0) : 0.0;
    return Rect.lerp(from, target, t)!;
  }

  /// The window goes (M2, M3): a little larger (back to the room) or smaller
  /// (✕), fading, then [then]. At once with less motion, or over other apps
  /// and in picture-in-picture (the system's windows).
  void _leave({required bool grow, required VoidCallback then}) {
    if (_exit.isAnimating) return;
    if (_still || PictureInPicture.active.value || OverlayWindow.active.value) {
      then();
      return;
    }
    _exitGrows = grow;
    _exit
        .animateTo(
          1,
          duration: Duration(milliseconds: grow ? 120 : 180),
          curve: Curves.easeIn,
        )
        .whenCompleteOrCancel(() {
          if (!mounted) return;
          then();
          // Still here (the room did not open): back in sight.
          Future<void>.delayed(const Duration(milliseconds: 600), () {
            if (mounted) _exit.value = 0;
          });
        });
  }

  void _dragStart() {
    final layout = _layout;
    if (layout == null) return;
    final from = _rect(layout).topLeft;
    _settle.stop();
    _dragging = true;
    _dock = null;
    _dragged = from;
    _free = true;
    _grip.value = null;
    _moved();
  }

  void _dragUpdate(Offset delta) {
    final layout = _layout;
    if (layout == null || !_dragging) return;
    // From where it shows: a drag past the limit does not pile up.
    _dragged = _rect(layout).topLeft + delta;
    _moved();
  }

  void _dragEnd(Offset velocity) {
    final layout = _layout;
    if (layout == null || !_dragging) return;
    final window = _rect(layout);
    _dragging = false;
    final settled = inAppMiniSettle(
      area: layout.area,
      window: window,
      velocity: velocity,
      topClearance: layout.reachTop,
      bottomClearance: layout.reachBottom,
      peek: layout.peekOf(window.center.dx < layout.area.width / 2 ? MiniDock.left : MiniDock.right, window.width),
    );
    _slide(from: window.topLeft, to: settled.offset, dock: settled.dock, velocity: velocity);
  }

  /// Slides from [from] to [to] on a spring that leaves at [velocity] (no
  /// slide when the system asks for less motion), tucked into [dock] or
  /// not, and remembers it.
  void _slide({required Offset from, required Offset to, required MiniDock? dock, Offset velocity = Offset.zero}) {
    _dock = dock;
    _dragged = to;
    widget.room.placement = (offset: to, dock: dock);
    _savePlacement();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still || (from - to).distance < 0.5) {
      _settle.stop();
      _lastShown = null;
      _moved();
    } else {
      final tolerance = AppMotion.tolerance(MediaQuery.devicePixelRatioOf(context));
      ReleaseSpringSimulation axis(double start, double end, double speed) => ReleaseSpringSimulation(
        spring: AppMotion.floatingSpring,
        start: start,
        end: end,
        velocity: speed,
        tolerance: tolerance,
      );
      final run = _slideRun = _SlideSimulation(axis(from.dx, to.dx, velocity.dx), axis(from.dy, to.dy, velocity.dy));
      _settle.animateRelease(run, refreshRate: View.of(context).display.refreshRate);
    }
    _placeGrip();
    _syncAutoPipLater();
  }

  /// A tap on a tucked-away window brings it back to its side.
  void _undock() {
    final layout = _layout;
    if (layout == null || _dock == null) return;
    final window = _rect(layout);
    final inside = inAppMiniOffset(
      area: layout.area,
      window: window.size,
      dragged: window.topLeft,
      topClearance: layout.reachTop,
      bottomClearance: layout.reachBottom,
    );
    _slide(from: window.topLeft, to: inside, dock: null);
  }

  void _resizeStart({required bool pinch}) {
    final layout = _layout;
    if (layout == null) return;
    final window = _rect(layout);
    _settle.stop();
    _resizeFrom = window;
    _resizeFromScale = layout.bounded(_scale ?? layout.stored);
    _resizePortrait = layout.portraitWindow;
    _scale = _resizeFromScale;
    _dragged = window.topLeft;
    _dock = null;
    final grip = _grip.value;
    _anchor = pinch
        ? MiniResizeAnchor.centre
        : grip == MiniGripCorner.bottomLeft
        ? MiniResizeAnchor.topRight
        : MiniResizeAnchor.topLeft;
  }

  void _resizeTo(double wanted) {
    final layout = _layout;
    final from = _resizeFrom;
    if (layout == null || from == null) return;
    final next = layout.bounded(wanted);
    _scale = next;
    _dragged = inAppMiniResizedOffset(from: from, size: layout.sized(next), anchor: _anchor);
    _moved();
  }

  void _gripMove(Offset moved) {
    final from = _resizeFrom;
    if (from == null) return;
    final corner = _anchor == MiniResizeAnchor.topRight ? MiniGripCorner.bottomLeft : MiniGripCorner.bottomRight;
    final long = from.width < from.height ? from.height : from.width;
    final extent = inAppMiniGripExtent(from: from.size, corner: corner, moved: moved);
    _resizeTo(_resizeFromScale * extent / long);
  }

  void _resizeEnd() {
    final layout = _layout;
    if (layout == null || _resizeFrom == null) return;
    final window = _rect(layout);
    final setting = _resizePortrait ? Settings.floatWindowPortraitScale : Settings.floatWindowLandscapeScale;
    final kept = setting.normalize(_scale ?? layout.stored);
    // Still in the corner (a grip pulled towards the middle grows it from
    // there): it stays the corner one, following a turn or another page's
    // bottom bar as before; elsewhere it stays where it is.
    final corner = inAppMiniOffset(
      area: layout.area,
      window: window.size,
      topClearance: layout.topClearance,
      bottomClearance: layout.bottomClearance,
    );
    _scale = kept;
    _resizeFrom = null;
    _lastShown = null;
    _dragged = (window.topLeft - corner).distance < 0.5 ? null : window.topLeft;
    if (_dragged == null) _free = false;
    widget.room.placement = _dragged == null ? null : (offset: _dragged!, dock: null);
    _savePlacement();
    _moved();
    _placeGrip();
    _syncAutoPipLater();
    // Remembered for the next time (A07.22 c2).
    unawaited(ref.read(storeProvider).settings.set(setting, kept));
  }

  /// M1, M8: the window glides to [target] out of the room page's picture
  /// when it opens, and from where it was when its place or size changed by
  /// itself (another page's bottom bar, a turn, "小窗大小"); not while a
  /// finger moves it or it settles (those follow the finger and the spring).
  void _glideTo(Rect target) {
    final enter = _enterFrom;
    if (enter != null) {
      _enterFrom = null;
      if (!_still) _queueMorph(fitInto(enter, aspectRatio: target.width / target.height));
      return;
    }
    final last = _lastShown;
    final idle = !_dragging && _resizeFrom == null && !_settle.isAnimating && _morphFrom == null;
    if (!idle || last == null || _still) return;
    if ((last.topLeft - target.topLeft).distance > 0.5 || (last.width - target.width).abs() > 0.5) _queueMorph(last);
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final media = MediaQuery.of(context);
    final fit = videoFits[watchSetting(ref, Settings.videoFitIndex).clamp(0, videoFits.length - 1)];
    final follow = watchSetting(ref, Settings.portraitPipFollowSource);
    final sizeName = watchSetting(ref, Settings.floatWindowSize);
    final landscapeScale = watchSetting(ref, Settings.floatWindowLandscapeScale);
    final portraitScale = watchSetting(ref, Settings.floatWindowPortraitScale);
    final keepOn = watchSetting(ref, Settings.enableScreenKeepOn);
    watchSetting(ref, Settings.autoPipOnLeave);
    watchSetting(ref, Settings.useSystemPip);
    _syncAutoPipLater();
    // A07.24: in Android's picture-in-picture the window is the whole
    // screen, the picture alone (the system draws the buttons); A07.25: in
    // the app's floating window over other apps it is the whole view, with
    // the in-app window's buttons.
    final overlay = OverlayWindow.active.value;
    final pip = PictureInPicture.active.value || overlay;
    // Built once per change of the room or the settings; a drag does not
    // come here (A07.24).
    final surface = MiniPlayerSurface(
      controller: runtime.controller,
      reconnect: runtime.reconnect,
      kind: overlay ? MiniKind.overlay : (pip ? MiniKind.systemPip : MiniKind.inApp),
      onPip: _pipSupported && !overlay ? () => unawaited(_enterPip()) : null,
      buttonsShown: _buttons,
      // F.1a: kept on while it plays only with "屏幕常亮" on.
      video: LiveVideoView(session: runtime.session, fit: fit, keepScreenOn: keepOn),
      // M2, M3: it goes visibly before the room opens or it stops.
      onBackToRoom: () => _leave(grow: true, then: widget.onBackToRoom),
      onClose: () => _leave(grow: false, then: widget.onClose),
      // Over other apps the system window moves and sizes with the finger.
      onDragStart: (_) => overlay ? unawaited(OverlayWindow.dragStart()) : _dragStart(),
      onDragUpdate: (details) => overlay ? null : _dragUpdate(details.delta),
      onDragEnd: (details) => overlay ? null : _dragEnd(details.velocity.pixelsPerSecond),
      // A07.22: the grip on the bottom corner towards the middle, and two
      // fingers anywhere. Only the window's size changes: the player is not
      // rebuilt.
      resizeGrip: _grip,
      onResizeStart: overlay
          ? ({required pinch}) => unawaited(pinch ? OverlayWindow.pinchStart() : OverlayWindow.resizeStart())
          : _resizeStart,
      onGripMove: overlay ? null : _gripMove,
      onPinch: overlay
          ? (factor) => unawaited(OverlayWindow.pinch(factor))
          : (factor) => _resizeTo(_resizeFromScale * factor),
      onResizeEnd: overlay ? () => unawaited(OverlayWindow.resizeEnd()) : _resizeEnd,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        // A07.25 c6: where the last run left it, once the area is known (not in
        // a picture-in-picture or floating window, which fill it).
        if (_restoreSaved && !pip && area.width > 0 && area.height > 0) {
          _restoreSaved = false;
          final saved = decodeMiniPlacement(runtime.controller.store.settings.get(Settings.floatWindowPosition), area);
          if (saved != null) {
            // J4: a window left tucked opens against that side, not tucked.
            final dock = saved.dock;
            _dragged = dock == null ? saved.offset : inAppMiniUntucked(dock: dock, top: saved.offset.dy, area: area);
            _dock = null;
            _free = true;
            widget.room.placement = (offset: _dragged!, dock: null);
          }
        }
        return ListenableBuilder(
          listenable: runtime.orientation,
          builder: (context, _) => StreamBuilder<PlaybackState>(
            stream: runtime.session.states,
            initialData: runtime.session.state,
            builder: (context, snapshot) {
              final state = snapshot.data ?? runtime.session.state;
              final portrait = isPortraitLayout(runtime.orientation.value, detected: state.expectsPortrait);
              final picture = expectedPictureSize(state);
              final ratio = pictureRatio(
                width: picture.width,
                height: picture.height,
                portrait: portrait,
                followPortrait: follow,
              );
              _pictureSize = miniPictureSize(
                width: picture.width,
                height: picture.height,
                portrait: portrait,
                followPortrait: follow,
              );
              // A07.22: a portrait picture's window keeps a resize of its own.
              final portraitWindow = inAppMiniPortrait(ratio);
              final stored = portraitWindow ? portraitScale : landscapeScale;
              if (_resizeFrom == null && _scale != null && (_scale! - stored).abs() < 1e-9) _scale = null;
              _layout = _Layout(
                screen: media.size,
                area: area,
                ratio: ratio,
                topClearance: media.viewPadding.top + inAppMiniMargin,
                reachTop: media.viewPadding.top,
                reachBottom: media.viewPadding.bottom,
                // Full-screen gestures take a strip of each side for back.
                gestureLeft: media.systemGestureInsets.left,
                gestureRight: media.systemGestureInsets.right,
                bottomClearance: inAppMiniBottomClearance(
                  route: widget.route,
                  width: area.width,
                  safeBottom: media.viewPadding.bottom,
                ),
                sizeName: sizeName,
                stored: stored,
                portraitWindow: portraitWindow,
              );
              SchedulerBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_dragging && _resizeFrom == null) _placeGrip();
              });
              return ValueListenableBuilder<int>(
                valueListenable: _frame,
                builder: (context, _, picture) {
                  // Back from over other apps: where and as large as it was.
                  if (!pip) _takePlaced(_layout!);
                  final window = pip ? Offset.zero & area : _rect(_layout!);
                  if (!pip) _glideTo(window);
                  final shown = pip ? window : _shown(window);
                  // Filling the screen (picture-in-picture, over other apps)
                  // is no place to glide from.
                  _lastShown = pip ? null : shown;
                  final tucked = _dock != null && !pip;
                  final settled = !_settle.isAnimating;
                  Widget framed = Stack(
                    fit: StackFit.expand,
                    children: [
                      picture!,
                      // c5: the handle on a tucked window's strip, away from
                      // the screen's edge; it comes once the window settled.
                      if (tucked) _TuckHandle(dock: _dock!, shown: settled),
                      // A tucked-away window: a tap brings it back, a drag
                      // pulls it out. Kept while that drag lasts: the window
                      // is no longer tucked once it moves, and a detector
                      // taken away mid-drag never tells its end (the K90
                      // check: the window stayed "dragged").
                      if ((tucked && settled) || _pullingOut)
                        GestureDetector(
                          key: const ValueKey('floating-window-tucked'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _undock,
                          onPanStart: (_) {
                            _pullingOut = true;
                            _dragStart();
                          },
                          onPanUpdate: (details) => _dragUpdate(details.delta),
                          onPanEnd: (details) {
                            _pullingOut = false;
                            _dragEnd(details.velocity.pixelsPerSecond);
                          },
                          onPanCancel: () {
                            _pullingOut = false;
                            _dragEnd(Offset.zero);
                          },
                        ),
                      // The same over other apps: the native side tucks and
                      // brings back the system window (A07.25 c8).
                      if (overlay) const _OverlayTucked(),
                    ],
                  );
                  // M1, M8: laid out where it belongs, drawn on the way; M2,
                  // M3: fading as it goes. Always the same widgets (still,
                  // they draw nothing of their own), so the picture under
                  // them is never built again.
                  final scale = window.width > 0 ? shown.width / window.width : 1.0;
                  final going = _exit.value;
                  framed = IgnorePointer(
                    ignoring: going > 0,
                    child: Opacity(
                      opacity: (1 - going).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: going > 0 ? (_exitGrows ? 1 + 0.04 * going : 1 - 0.15 * going) : 1,
                        child: Transform(
                          transform: Matrix4.translationValues(shown.left - window.left, shown.top - window.top, 0)
                            ..scaleByDouble(scale, scale, 1, 1),
                          child: framed,
                        ),
                      ),
                    ),
                  );
                  return Stack(
                    children: [
                      Positioned(
                        key: const ValueKey('floating-window'),
                        left: window.left,
                        top: window.top,
                        width: window.width,
                        height: window.height,
                        child: framed,
                      ),
                    ],
                  );
                },
                // 3.x showed it at 80 % while dragged; the video stays opaque
                // now (P05): a see-through video is drawn offscreen
                // (saveLayer) every frame of the drag.
                child: RepaintBoundary(
                  child: DecoratedBox(
                    // c10: square corners and a floating shadow; the video
                    // is not clipped.
                    decoration: const BoxDecoration(
                      color: OnVideoColors.ground,
                      boxShadow: OnVideoColors.floatingShadow,
                    ),
                    child: surface,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// The floating window's settling slide (A07.24): a spring on each axis,
/// each leaving at the finger's speed along it. Its value is the time, so
/// one controller runs both.
class _SlideSimulation extends Simulation {
  new(this._x, this._y) : super(tolerance: _x.tolerance);

  final Simulation _x;
  final Simulation _y;

  /// Where the window is [time] seconds in.
  Offset at(double time) => Offset(_x.x(time), _y.x(time));

  @override
  double x(double time) => time;

  @override
  double dx(double time) => 1;

  @override
  bool isDone(double time) => _x.isDone(time) && _y.isDone(time);
}

/// The largest rectangle of [aspectRatio] (width over height) inside [box],
/// centred: where a contained picture shows in it (A07.25 M1).
@visibleForTesting
Rect fitInto(Rect box, {required double aspectRatio}) {
  if (!aspectRatio.isFinite || aspectRatio <= 0 || box.isEmpty) return box;
  final width = box.width / box.height > aspectRatio ? box.height * aspectRatio : box.width;
  return Rect.fromCenter(center: box.center, width: width, height: width / aspectRatio);
}

/// The handle on a tucked window's strip (A07.25 c5): a short white bar at
/// [inAppMiniHandleInset] from the strip's inner edge, so a finger takes it
/// outside the system's back gesture strip.
class _TuckHandle extends StatelessWidget {
  const new({required this.dock, required this.shown});

  final MiniDock dock;
  final bool shown;

  @override
  Widget build(BuildContext context) => Align(
    alignment: dock == MiniDock.right ? Alignment.centerLeft : Alignment.centerRight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: inAppMiniHandleInset),
      child: IgnorePointer(
        child: AnimatedOpacity(
          key: const ValueKey('floating-window-handle'),
          opacity: shown ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: const SizedBox(
            width: 6,
            height: 36,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: OnVideoColors.foreground,
                borderRadius: BorderRadius.all(Radius.circular(3)),
                boxShadow: [BoxShadow(color: OnVideoColors.shadow, blurRadius: 4)],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Over other apps, a window the native side tucked into a side (A07.25 c8):
/// the handle, a tap brings it back and a drag pulls it out, as in the app.
class _OverlayTucked extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: OverlayWindow.tucked,
    builder: (context, side, _) {
      if (side == null) return const SizedBox.shrink();
      return Stack(
        fit: StackFit.expand,
        children: [
          _TuckHandle(dock: side == 'left' ? MiniDock.left : MiniDock.right, shown: true),
          GestureDetector(
            key: const ValueKey('overlay-window-tucked'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(OverlayWindow.untuck()),
            onPanStart: (_) => unawaited(OverlayWindow.dragStart()),
          ),
        ],
      );
    },
  );
}
