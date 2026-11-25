import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/desktop/app_window_api.dart';
import 'package:pure_live/app/desktop/display_geometry.dart';

/// What the room's desktop mini window asks of the window system (U.2j;
/// 3.x `WindowHelper`'s picture-in-picture): the desktop shell provides it,
/// tests replace it.
abstract interface class MiniWindowHost {
  /// Shrinks the window to the mini window for a picture of [aspectRatio],
  /// staying on top when [onTop].
  Future<void> enter({required double aspectRatio, required bool onTop});

  /// Gives the window its size, place and layer from before [enter].
  Future<void> exit();

  /// Keeps the mini window above other programs, or not.
  Future<void> setOnTop({required bool onTop});

  /// Hides the window (the mini window's ✕, before the room closes).
  Future<void> hide();

  /// Minimizes the window to the taskbar.
  Future<void> minimize();

  /// Moves the window with the pointer (a drag on the picture).
  Future<void> startDragging();

  /// Whether the desktop lets a program stay on top (most Wayland desktops
  /// do not, c5).
  bool get canPin;

  /// The mini window moved or changed size: remember it when
  /// `rememberPipPosition` is on.
  Future<void> saveGeometry();
}

/// The mini window's default size for a picture of [aspectRatio] (3.x
/// `WindowHelper._enterPiP`): landscape 360 wide, portrait 380 high (at
/// least 140 wide), nearly square 280.
Size miniWindowSize(double aspectRatio) {
  final ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16 / 9;
  if (ratio > 1.05) return Size(360, 360 / ratio);
  if (ratio < 0.95) {
    var width = 380 * ratio;
    var height = 380.0;
    if (width < 140) {
      width = 140;
      height = width / ratio;
    }
    return Size(width, height);
  }
  return ratio >= 1 ? Size(280, 280 / ratio) : Size(280 * ratio, 280);
}

/// The smallest mini window (3.x).
const Size miniWindowMinimum = Size(140, 90);

/// Where the mini window goes (3.x `resolveWindowsPipBounds`): the
/// remembered [saved] bounds when they still overlap a work area by 48 × 48,
/// else [defaultSize] at the bottom-right of [primaryWorkArea] 20 from the
/// edges; always inside its work area.
Rect resolveMiniWindowBounds({
  required Size defaultSize,
  required Rect primaryWorkArea,
  required List<Rect> workAreas,
  Rect? saved,
}) {
  final areas = workAreas.where((area) => !area.isEmpty && area.isFinite).toList();
  final fallback = primaryWorkArea.isEmpty ? const Rect.fromLTWH(0, 0, 1280, 720) : primaryWorkArea;
  if (areas.isEmpty) areas.add(fallback);
  final valid = saved != null && saved.isFinite && !saved.isEmpty ? saved : null;
  Rect? target;
  if (valid != null) {
    for (final area in areas) {
      final overlap = valid.intersect(area);
      if (overlap.width >= 48 && overlap.height >= 48) {
        target = area;
        break;
      }
    }
  }
  target ??= areas.firstWhere(
    (area) => area.overlaps(fallback) || area.contains(fallback.center),
    orElse: () => areas.first,
  );
  final requested = valid?.size ?? defaultSize;
  final minWidth = math.min(target.width, miniWindowMinimum.width);
  final minHeight = math.min(target.height, miniWindowMinimum.height);
  final width = requested.width.clamp(minWidth, target.width);
  final height = requested.height.clamp(minHeight, target.height);
  final left = (valid?.left ?? target.right - width - 20).clamp(target.left, target.right - width);
  final top = (valid?.top ?? target.bottom - height - 20).clamp(target.top, target.bottom - height);
  return Rect.fromLTWH(left, top, width, height);
}

/// Whether this desktop refuses "always on top" (Linux under Wayland: GNOME
/// does not allow it, c5).
bool get desktopRefusesOnTop {
  if (!Platform.isLinux) return false;
  final environment = Platform.environment;
  return environment['XDG_SESSION_TYPE'] == 'wayland' || (environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty;
}

/// [MiniWindowHost] over window_manager and screen_retriever (the desktop
/// shell's window).
final class WindowManagerMiniHost implements MiniWindowHost {
  /// Creates the host; [normalMinimum] is the normal window's smallest size.
  new(this._settings, {required this.normalMinimum});

  final SettingsStore _settings;

  /// The normal window's smallest size, given back on [exit].
  final Size normalMinimum;

  Rect? _normal;
  bool _maximized = false;
  bool _onTop = false;

  @override
  bool get canPin => !desktopRefusesOnTop;

  Rect _area(DesktopDisplayGeometry display) => display.workArea;

  DesktopDisplayGeometry? _displayAt(List<DesktopDisplayGeometry> displays, Offset point) {
    for (final display in displays) {
      if (_area(display).contains(point)) return display;
    }
    return null;
  }

  Rect? _savedBounds(DesktopDisplayGeometry display) {
    if (!_settings.get(Settings.rememberPipPosition)) return null;
    final saved = _settings.get(Settings.windowsPipDisplayId);
    final width = _settings.get(Settings.windowsPipWidth);
    final height = _settings.get(Settings.windowsPipHeight);
    if (!(width > 0 && height > 0)) return null;
    final bounds = Rect.fromLTWH(
      _settings.get(Settings.windowsPipX),
      _settings.get(Settings.windowsPipY),
      width,
      height,
    );
    return display.acceptsSavedWindow(saved, bounds) ? bounds : null;
  }

  @override
  Future<void> enter({required double aspectRatio, required bool onTop}) async {
    if (await appWindow.isFullScreen()) await appWindow.setFullScreen(false);
    _maximized = await appWindow.isMaximized();
    if (_maximized) await appWindow.unmaximize();
    final normal = _normal = await appWindow.getBounds();
    _onTop = await appWindow.isAlwaysOnTop();
    try {
      final displays = readDesktopDisplays();
      final primary = displays.where((display) => display.isPrimary).firstOrNull ?? displays.firstOrNull;
      if (primary == null) throw StateError('No usable display for the mini window');
      final current = _displayAt(displays, normal.center) ?? primary;
      final bounds = resolveMiniWindowBounds(
        defaultSize: miniWindowSize(aspectRatio),
        primaryWorkArea: _area(current),
        workAreas: [for (final display in displays) _area(display)],
        saved: _savedBounds(current),
      );
      await appWindow.setMinimumSize(miniWindowMinimum);
      if (canPin) await appWindow.setAlwaysOnTop(onTop);
      if (Platform.isMacOS) {
        // c5: no traffic lights over the mini window.
        await appWindow.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      }
      await appWindow.setBounds(bounds);
    } on Object {
      await _restore();
      rethrow;
    }
  }

  Future<void> _restore() async {
    final steps = <Future<void> Function()>[
      () => appWindow.setAlwaysOnTop(_onTop),
      () => appWindow.setMinimumSize(normalMinimum),
      if (Platform.isMacOS) () => appWindow.setTitleBarStyle(TitleBarStyle.hidden),
      if (_normal case final normal?) () => appWindow.setBounds(normal),
      if (_maximized) appWindow.maximize,
    ];
    for (final step in steps) {
      try {
        await step();
      } on Object catch (error, stack) {
        log('Mini window restore step failed', name: 'Desktop', error: error, stackTrace: stack);
      }
    }
  }

  @override
  Future<void> exit() async {
    final normal = _normal;
    await appWindow.setAlwaysOnTop(_onTop);
    await appWindow.setMinimumSize(normalMinimum);
    if (Platform.isMacOS) await appWindow.setTitleBarStyle(TitleBarStyle.hidden);
    if (normal != null) await appWindow.setBounds(normal);
    if (_maximized) await appWindow.maximize();
    _normal = null;
    _maximized = false;
  }

  @override
  Future<void> setOnTop({required bool onTop}) => appWindow.setAlwaysOnTop(onTop);

  @override
  Future<void> hide() => appWindow.hide();

  @override
  Future<void> minimize() async {
    await appWindow.minimize();
    // A hidden window may stay hidden instead (the mini window's ✕ hides it
    // first): show it, then down to the taskbar.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (await appWindow.isVisible()) return;
    await appWindow.show(inactive: true);
    await appWindow.minimize();
  }

  @override
  Future<void> startDragging() => appWindow.startDragging();

  @override
  Future<void> saveGeometry() async {
    if (!_settings.get(Settings.rememberPipPosition)) return;
    try {
      final bounds = await appWindow.getBounds();
      final displays = readDesktopDisplays();
      final display =
          _displayAt(displays, bounds.center) ??
          displays.where((display) => display.isPrimary).firstOrNull ??
          displays.firstOrNull;
      if (display == null) return;
      await _settings.setAll({
        Settings.windowsPipWidth: bounds.width,
        Settings.windowsPipHeight: bounds.height,
        Settings.windowsPipX: bounds.left,
        Settings.windowsPipY: bounds.top,
        Settings.windowsPipDisplayId: display.persistenceKey,
      });
    } on Object catch (error, stack) {
      log('Saving the mini window failed', name: 'Desktop', error: error, stackTrace: stack);
    }
  }
}
