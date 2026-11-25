import 'dart:async';
import 'dart:ffi' show Pointer, Void;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nativeapi/nativeapi.dart' as native;
import 'package:window_manager/window_manager.dart';

export 'package:window_manager/window_manager.dart' show DragToResizeArea, TitleBarStyle;

/// PureLive's startup policy, independent of a plugin's deprecated options.
@immutable
final class AppWindowOptions {
  /// Creates a hidden startup window configuration.
  const new({this.size, this.minimumSize, this.center = false, this.title = '', this.titleBarStyle});

  /// Normal outer size in logical pixels.
  final Size? size;

  /// Minimum outer size in logical pixels.
  final Size? minimumSize;

  /// Centers before the first visible frame.
  final bool center;

  /// Initial taskbar title.
  final String title;

  /// Native caption policy.
  final TitleBarStyle? titleBarStyle;
}

/// Events used by the app shell; the adapter owns native subscriptions.
abstract mixin class AppWindowListener {
  /// A close request which the app must confirm.
  void onWindowClose() {}

  /// A continuous resize notification.
  void onWindowResize() {}

  /// Settled geometry after resizing.
  void onWindowResized() {}

  /// Settled geometry after moving.
  void onWindowMoved() {}

  /// The window became maximized.
  void onWindowMaximize() {}

  /// The window left its maximized state.
  void onWindowUnmaximize() {}

  /// The window received focus.
  void onWindowFocus() {}

  /// Focus left the window; playback policy decides whether to pause.
  void onWindowBlur() {}

  /// The window became minimized.
  void onWindowMinimize() {}

  /// The window was restored from minimization.
  void onWindowRestore() {}

  /// The native window entered fullscreen.
  void onWindowEnterFullScreen() {}

  /// The native window left fullscreen.
  void onWindowLeaveFullScreen() {}
}

/// The process's Flutter host window. Resolve it once, including when hidden.
final AppWindowApi appWindow = AppWindowApi();

/// The nativeapi-backed window operations needed by PureLive. This small
/// boundary keeps playback and persistence separate from native ownership.
final class AppWindowApi {
  /// Creates an unresolved host adapter. Native boundaries are injectable
  /// so event ownership can be tested without opening a real window.
  new({
    FutureOr<native.Window?> Function()? resolve,
    native.ListenerId Function(FutureOr<void> Function(native.WindowEvent))? listen,
    void Function(native.ListenerId)? unlisten,
  }) : _resolve = resolve ?? _resolveHostWindow,
       _listen = listen ?? native.WindowManager.instance.addListener,
       _unlisten = unlisten ?? native.WindowManager.instance.removeListener;

  final FutureOr<native.Window?> Function() _resolve;
  final native.ListenerId Function(FutureOr<void> Function(native.WindowEvent)) _listen;
  final void Function(native.ListenerId) _unlisten;

  static Future<native.Window?> _resolveHostWindow() async {
    if (!Platform.isWindows) return native.WindowManager.instance.getCurrent();
    // The runner owns the hidden Flutter host before any window is active.
    // Address that exact HWND instead of relying on desktop focus.
    final handle = await const MethodChannel('pure_live/window_startup').invokeMethod<int>('getWindowHandle');
    if (handle == null || handle == 0) return null;
    return native.Window.createWithNativeWindow(Pointer<Void>.fromAddress(handle));
  }

  native.Window? _window;
  Future<void>? _initializing;
  native.ListenerId? _nativeListener;
  final _listeners = <AppWindowListener>{};
  Timer? _settled;
  bool _preventClose = false;
  bool _destroying = false;
  bool _maximized = false;

  native.Window get _target => _window ?? (throw StateError('The desktop host window is not initialized'));

  /// Finds the current process window before its first visible frame.
  Future<void> ensureInitialized() {
    if (_window != null) return Future<void>.value();
    return _initializing ??= _initializeHost().whenComplete(() => _initializing = null);
  }

  Future<void> _initializeHost() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    native.Window? window;
    while ((window = await _resolve()) == null) {
      if (DateTime.now().isAfter(deadline)) throw StateError('The native desktop host window was not found');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _window = window;
    _maximized = window!.isMaximized;
    _nativeListener ??= _listen(_event);
  }

  void _notify(void Function(AppWindowListener) call) {
    List.of(_listeners).forEach(call);
  }

  void _event(native.WindowEvent event) {
    if (_window?.id != event.windowId) return;
    switch (event) {
      case native.WindowCloseRequestedEvent(:final request):
        if (_preventClose && !_destroying) {
          request.cancel();
          _notify((listener) => listener.onWindowClose());
        }
        _destroying = false;
      case native.WindowFocusedEvent():
        _notify((listener) => listener.onWindowFocus());
      case native.WindowBlurredEvent():
        _notify((listener) => listener.onWindowBlur());
      case native.WindowMaximizedEvent():
        _maximized = true;
        _notify((listener) => listener.onWindowMaximize());
      case native.WindowMinimizedEvent():
        _notify((listener) => listener.onWindowMinimize());
      case native.WindowRestoredEvent():
        if (_maximized && !_target.isMaximized) {
          _maximized = false;
          _notify((listener) => listener.onWindowUnmaximize());
        }
        _notify((listener) => listener.onWindowRestore());
      case native.WindowEnteredFullScreenEvent():
        _notify((listener) => listener.onWindowEnterFullScreen());
      case native.WindowExitedFullScreenEvent():
        _notify((listener) => listener.onWindowLeaveFullScreen());
      case native.WindowResizedEvent():
        _notify((listener) => listener.onWindowResize());
        _settled?.cancel();
        _settled = Timer(const Duration(milliseconds: 150), () => _notify((l) => l.onWindowResized()));
      case native.WindowMovedEvent():
        _notify((listener) => listener.onWindowMoved());
      case native.WindowClosedEvent():
        _settled?.cancel();
        final listener = _nativeListener;
        if (listener != null) _unlisten(listener);
        _nativeListener = null;
        _window?.dispose();
        _window = null;
      default:
        break;
    }
  }

  /// Starts shell observation without duplicating registrations.
  void addListener(AppWindowListener listener) => _listeners.add(listener);

  /// Stops observation; pending callbacks use the current listener snapshot.
  void removeListener(AppWindowListener listener) => _listeners.remove(listener);

  /// Applies startup geometry before app code shows the window.
  Future<void> waitUntilReadyToShow(AppWindowOptions options) async {
    await ensureInitialized();
    final window = _target;
    if (options.titleBarStyle case final style?) window.titleBarStyle = style;
    window.title = options.title;
    if (options.minimumSize case final minimum?) window.minimumSize = minimum.toNative();
    if (options.size case final size?) window.setSize(size.toNative(), false);
    if (options.center) window.center();
  }

  /// Lets PureLive's close confirmation decide whether this window exits.
  Future<void> setPreventClose(bool value) async => _preventClose = value;

  /// Closes through the native event-voting API after app approval.
  Future<void> destroy() async {
    _destroying = true;
    try {
      if (!_target.close()) _destroying = false;
    } on Object {
      _destroying = false;
      rethrow;
    }
  }

  /// Shows or restores the addressed window.
  Future<void> show({bool inactive = false}) async {
    final window = _target;
    if (window.isMinimized) window.restore();
    inactive ? window.showInactive() : window.show();
    // Win32 may consume the first ShowWindow using the launcher's SW_HIDE.
    // This is an explicit app show request: confirm it took effect, once,
    // while retaining the caller's inactive/focus policy.
    if (!window.isVisible) inactive ? window.showInactive() : window.show();
  }

  /// Hides the host without closing playback.
  Future<void> hide() async => _target.hide();

  /// Moves input focus to the host.
  Future<void> focus() async => _target.focus();

  /// Minimizes the host.
  Future<void> minimize() async => _target.minimize();

  /// Maximizes the host.
  Future<void> maximize() async => _target.maximize();

  /// Returns a maximized host to normal size.
  Future<void> unmaximize() async => _target.unmaximize();

  /// Restores a minimized host.
  Future<void> restore() async => _target.restore();

  /// Centers in the native screen work area.
  Future<void> center() async => _target.center();

  /// Whether the native host is maximized.
  Future<bool> isMaximized() async => _target.isMaximized;

  /// Whether the native host is minimized.
  Future<bool> isMinimized() async => _target.isMinimized;

  /// Whether the native host is visible.
  Future<bool> isVisible() async => _target.isVisible;

  /// Whether the native host is fullscreen.
  Future<bool> isFullScreen() async => _target.isFullScreen;

  /// Changes native fullscreen, keeping the same Flutter window.
  Future<void> setFullScreen(bool value) async => _target.isFullScreen = value;

  /// Whether the native host stays above ordinary windows.
  Future<bool> isAlwaysOnTop() async => _target.isAlwaysOnTop;

  /// Applies the mini window's pin preference.
  Future<void> setAlwaysOnTop(bool value) async => _target.isAlwaysOnTop = value;

  /// Reads bounds as Flutter logical coordinates.
  Future<Rect> getBounds() async => _target.bounds.toRect();

  /// Applies both size and position as one native update.
  Future<void> setBounds(Rect value) async => _target.bounds = value.toNative();

  /// Reads the outer logical size.
  Future<Size> getSize() async => _target.size.toSize();

  /// Changes size while keeping native position.
  Future<void> setSize(Size value) async => _target.setSize(value.toNative(), false);

  /// Changes logical position while keeping native size.
  Future<void> setPosition(Offset value) async => _target.position = value.toNative();

  /// Applies the current normal or mini window's minimum size.
  Future<void> setMinimumSize(Size value) async => _target.minimumSize = value.toNative();

  /// Updates the taskbar title.
  Future<void> setTitle(String value) async => _target.title = value;

  /// Updates the caption and macOS traffic lights independently.
  Future<void> setTitleBarStyle(TitleBarStyle value, {bool windowButtonVisibility = true}) async {
    _target.titleBarStyle = value;
    _target.isWindowControlButtonsVisible = windowButtonVisibility;
  }

  /// Begins the drag belonging to the current native pointer gesture.
  Future<void> startDragging() async => _target.startDragging();

  /// Opens the platform system menu at the current pointer.
  Future<void> popUpWindowMenu() async {
    if (!native.Window.isSystemMenuSupported()) return;
    final pointer = native.DisplayManager.instance.getCursorPosition().toOffset();
    final content = _target.contentBounds.toRect();
    _target.showSystemMenu((pointer - content.topLeft).toNative());
  }
}
