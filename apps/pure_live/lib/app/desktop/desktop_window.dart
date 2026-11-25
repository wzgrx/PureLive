import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/commands.dart';
import 'package:pure_live/app/desktop/app_window_api.dart';
import 'package:pure_live/app/desktop/close_dialog.dart';
import 'package:pure_live/app/desktop/display_geometry.dart';
import 'package:pure_live/app/desktop/mini_window.dart';
import 'package:pure_live/app/desktop/projection_runtime.dart';
import 'package:pure_live/app/desktop/shared_data.dart';
import 'package:pure_live/app/desktop/startup_entry.dart';
import 'package:pure_live/app/desktop/startup_window.dart';
import 'package:pure_live/app/desktop/title_bar.dart';
import 'package:pure_live/app/desktop/tray.dart';
import 'package:pure_live/app/desktop/uninstall_shutdown.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';

export 'package:pure_live/app/desktop/mini_window.dart' show MiniWindowHost;

/// What the title bar asks of the window (docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口): the
/// shell's window_manager; tests set their own.
abstract interface class WindowControls {
  /// Minimizes the window to the taskbar.
  Future<void> minimize();

  /// Maximizes the window.
  Future<void> maximize();

  /// Gives a maximized window its size back.
  Future<void> restore();

  /// Opens the system's window menu at the pointer (restore, move, size,
  /// minimize, maximize, close; c13).
  Future<void> showSystemMenu();

  /// Moves the window with the pointer that is down.
  Future<void> startDragging();
}

/// What the pages ask of the desktop window (the live room's and
/// multi-view's full screen, the room's mini window, new windows). Without a
/// desktop shell (phones, tests) only [fullScreen] changes and there is no
/// mini window and no new window.
abstract final class DesktopWindow {
  /// Whether the window has the Mac's title row and closing
  /// (docs/A-界面设计/A18-苹果平台界面/A18.2-macOS差异设计): the system's three buttons instead of
  /// [DesktopTitleBar]'s, and the red button only hides the window. Tests
  /// set `debugDefaultTargetPlatformOverride`.
  static bool get macStyle => defaultTargetPlatform == TargetPlatform.macOS;

  /// Whether the window fills the screen; the title bar hides meanwhile
  /// (3.x `GlobalPlayerState.isWindowFullscreen`).
  static final ValueNotifier<bool> fullScreen = ValueNotifier(false);

  static Future<void> Function({required bool on})? _setFullScreen;

  /// The window's size while the user drags its edge (the title bar shows
  /// it, 3.x `WindowSizeController.isTracking`); null otherwise.
  static final ValueNotifier<Size?> resizing = ValueNotifier(null);

  /// Whether the window is maximized: the title bar's middle button
  /// restores it then (U.13 c3).
  static final ValueNotifier<bool> maximized = ValueNotifier(false);

  /// Native minimization, distinct from loss of focus or macOS occlusion.
  static final ValueNotifier<bool> minimized = ValueNotifier(false);

  /// The title bar's window actions: the shell's, null without a desktop
  /// shell; tests set their own.
  static WindowControls? controls;

  /// The room's desktop mini window (U.2j): the shell's, null without a
  /// desktop shell; tests set their own.
  static MiniWindowHost? miniHost;

  /// Whether the window is the room's mini window now; the title bar hides
  /// meanwhile.
  static final ValueNotifier<bool> mini = ValueNotifier(false);

  /// Whether this window can become a mini window.
  static bool get miniAvailable => miniHost != null;

  /// Starts a new window process: the shell's, null where windows cannot be
  /// opened; tests set their own.
  static Future<void> Function({LiveRoom? room})? newWindowLauncher;

  /// Whether this desktop can open more windows (U.13 c12: the home menu's
  /// "新建独立播放窗口" and the room menu's "在新窗口打开" show where this is
  /// true and the setting [Settings.enableNewWindowPlay] is on).
  static bool get canOpenNewWindow => newWindowLauncher != null;

  /// Whether "open in a new window" is offered with [settings] (c12: both
  /// entries follow the setting).
  static bool offersNewWindow(SettingsStore settings) => canOpenNewWindow && settings.get(Settings.enableNewWindowPlay);

  /// Opens a new window that shares this one's data (c14); [room] plays in
  /// it right away. Says "新窗口启动失败，请重试" and returns false when the
  /// window did not start.
  static Future<bool> openNewWindow({LiveRoom? room}) async {
    final launcher = newWindowLauncher;
    if (launcher == null) return false;
    try {
      await launcher(room: room);
      return true;
    } on Object catch (error, stack) {
      log('New window failed', name: 'Desktop', error: error, stackTrace: stack);
      AppNavigator.toast(i18n('open_new_window_failed'));
      return false;
    }
  }

  /// Shrinks the window to the mini window for a picture of [aspectRatio]
  /// (3.x `WindowHelper.enterPiP`); false when the window system refused.
  static Future<bool> enterMini({required double aspectRatio, required bool onTop}) async {
    final host = miniHost;
    if (host == null || mini.value) return false;
    try {
      await host.enter(aspectRatio: aspectRatio, onTop: onTop);
      mini.value = true;
      return true;
    } on Object catch (error, stack) {
      log('Mini window failed', name: 'Desktop', error: error, stackTrace: stack);
      return false;
    }
  }

  /// Gives the window back its size and place; [hidden] hides it first (the
  /// mini window's ✕: the room closes unseen, then [minimize]). False when
  /// the window system refused (3.x "恢复主窗口失败，请重试").
  static Future<bool> exitMini({bool hidden = false}) async {
    final host = miniHost;
    if (host == null || !mini.value) return false;
    try {
      if (hidden) await host.hide();
      await host.exit();
      mini.value = false;
      return true;
    } on Object catch (error, stack) {
      log('Leaving the mini window failed', name: 'Desktop', error: error, stackTrace: stack);
      return false;
    }
  }

  /// Keeps the mini window on top or not; false when the window system
  /// refused.
  static Future<bool> setMiniOnTop({required bool onTop}) async {
    final host = miniHost;
    if (host == null || !mini.value) return false;
    try {
      await host.setOnTop(onTop: onTop);
      return true;
    } on Object catch (error, stack) {
      log('Mini window layer failed', name: 'Desktop', error: error, stackTrace: stack);
      return false;
    }
  }

  /// Minimizes the window to the taskbar.
  static Future<void> minimize() async {
    try {
      await miniHost?.minimize();
    } on Object catch (error, stack) {
      log('Minimize failed', name: 'Desktop', error: error, stackTrace: stack);
    }
  }

  /// Moves the window with the pointer that is down.
  static Future<void> startDragging() async {
    try {
      await miniHost?.startDragging();
    } on Object {
      // The pointer went up before the window system took it.
    }
  }

  /// The child with edges that resize the mini window (3.x
  /// `PureLivePipWidget`); the shell sets it, elsewhere the child as it is.
  static Widget Function(Widget child) resizeArea = (child) => child;

  /// Puts the window into ([on]) or out of full screen (3.x `WindowHelper`).
  static Future<void> setFullScreen({required bool on}) async {
    if (fullScreen.value == on) return;
    fullScreen.value = on;
    try {
      await _setFullScreen?.call(on: on);
    } on Object catch (error, stack) {
      log('Full screen failed', name: 'Desktop', error: error, stackTrace: stack);
    }
  }
}

/// The meta key of the main window's last position (`x,y`, logical pixels).
const String windowPositionKey = 'window.position';

/// The meta key of whether the main window was maximized (`1` or `0`; U.13
/// c6).
const String windowMaximizedKey = 'window.maximized';

/// [WindowControls] over window_manager.
final class _WindowManagerControls implements WindowControls {
  const new();

  @override
  Future<void> minimize() => appWindow.minimize();

  @override
  Future<void> maximize() => appWindow.maximize();

  @override
  Future<void> restore() => appWindow.unmaximize();

  @override
  Future<void> showSystemMenu() => appWindow.popUpWindowMenu();

  @override
  Future<void> startDragging() async {
    try {
      await appWindow.startDragging();
    } on Object {
      // The pointer went up before the window system took it.
    }
  }
}

/// The desktop window (3.x `DesktopManager`, `DesktopWindowMixin`,
/// `WindowSizeController`; docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口): no system title bar (the
/// app draws [DesktopTitleBar]), the size, place and maximized state of
/// last time (c6), the tray (main window only, c10), what the close button
/// does ([WindowCloser]), the window's name with the room (c11), new
/// windows over the shared data (c12, c14) and the start-up entry
/// ([Settings.enableStartUp]).
final class DesktopShell with AppWindowListener {
  new _(this._store, {required this.primary, this._recording, this._dataRoot, this._instanceId = ''});

  /// A listener without native startup, for platform event-sequence regressions.
  @visibleForTesting
  new testListener(LiveStore store) : this._(store, primary: false);

  final LiveStore _store;

  /// The main window (extra windows have no tray and simply close).
  final bool primary;

  final AppRecording? _recording;
  final Directory? _dataRoot;
  final String _instanceId;

  DesktopTray? _tray;
  WindowManagerMiniHost? _mini;
  SharedDataWatch? _shared;
  late final WindowCloser _closer;
  Timer? _saveTimer;
  StreamSubscription<Setting<Object>>? _settings;
  StreamSubscription<int>? _recordings;
  int _activeRecordings = 0;
  String? _title;
  AppLifecycleListener? _exitListener;
  bool _quitting = false;
  WindowsUninstallHandler? _uninstall;

  /// The authenticated endpoint of an extra projection window, if requested.
  ProjectionRuntime? projection;

  /// The shell of this window; null before [start] and where it does not
  /// run.
  static DesktopShell? current;

  /// Whether the shell runs here: Windows, Linux (X02.1) and macOS (A18.2).
  /// Everything else checks [current] and the window's abilities, not the
  /// platform, so Linux gets the same title bar, tray and closing; macOS
  /// differs only where [DesktopWindow.macStyle] says.
  static bool get supported => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Smallest window (UI_PLAN §5.3, U.13 c6; 3.x 400 × 300): it falls to
  /// the phone layout.
  static const Size minimumSize = Size(360, 400);

  /// Sets the window up before the first frame; nothing where the shell does
  /// not run. [dataRoot] is the folder all windows share (c14), [recording]
  /// this window's recorder (the close dialog and the tray count it).
  static Future<void> start(
    LiveStore store, {
    required bool primary,
    AppRecording? recording,
    Directory? dataRoot,
    String instanceId = '',
  }) async {
    if (!supported || current != null) return;
    final shell = current = DesktopShell._(
      store,
      primary: primary,
      recording: recording,
      dataRoot: dataRoot,
      instanceId: instanceId,
    );
    await shell._start();
  }

  SettingsStore get _prefs => _store.settings;

  Future<void> _start() async {
    await appWindow.ensureInitialized();
    // Never larger than the screen's work area (a size kept from a bigger
    // display, or the default on a small one, put the window's left part
    // off the screen on the Mac runner).
    final geometry = await startupWindowGeometry(_store, primary: primary);
    final size = fitWindowSize(geometry.size, await _workArea());
    final position = primary ? parseWindowPosition(await _store.meta.get(windowPositionKey)) : null;
    final maximize = geometry.maximized;
    final options = AppWindowOptions(
      size: size,
      minimumSize: minimumSize,
      center: position == null,
      title: i18nOr('app_name', 'PureLive'),
      titleBarStyle: TitleBarStyle.hidden,
    );
    await restoreStartupWindow(options, () async {
      await appWindow.setPreventClose(true);
      if (position != null) {
        // A monitor unplugged since last time: back to the middle (c6).
        if (await _onScreen(position, size)) {
          await appWindow.setPosition(position);
        } else {
          await appWindow.center();
        }
      }
      if (maximize) await appWindow.maximize();
      await appWindow.show();
      await appWindow.focus();
    });
    DesktopWindow.maximized.value = maximize;
    appWindow.addListener(this);
    DesktopWindow._setFullScreen = ({required on}) => appWindow.setFullScreen(on);
    DesktopWindow.controls = const _WindowManagerControls();
    DesktopWindow.miniHost = _mini = WindowManagerMiniHost(_prefs, normalMinimum: minimumSize);
    final mac = DesktopWindow.macStyle;
    // The Mac's window edges resize by themselves; a second app process is
    // not how a Mac opens windows (A18.2 offers none).
    if (!mac) {
      DesktopWindow.resizeArea = (child) => DragToResizeArea(child: child);
      DesktopWindow.newWindowLauncher = startWindowProcess;
    }
    _closer = WindowCloser(
      settings: _prefs,
      primary: primary,
      hasTray: () => _tray != null,
      recordings: () => _activeRecordings,
      ask: _ask,
      hide: appWindow.hide,
      minimize: appWindow.minimize,
      // macOS quits through the system (⌘Q's path), which asks [_exitRequested].
      exit: mac ? appWindow.destroy : exit,
      show: show,
      failed: () => AppNavigator.toast(i18n('window_close_action_failed')),
      hideOnClose: mac,
    );
    if (mac) _exitListener = AppLifecycleListener(onExitRequested: _exitRequested);
    final recording = _recording;
    if (recording != null) {
      _activeRecordings = recording.activeCount;
      _recordings = recording.activeCounts.listen((count) {
        _activeRecordings = count;
        _tray?.setRecording(count);
      });
    }
    liveRouteObserver.topPage.addListener(_retitle);
    if (_dataRoot case final root?) _shared = SharedDataWatch(_store, root)..start();
    if (primary) {
      // The Mac's menu bar icon can be turned off (A18.2 c7, K2).
      if (!mac || _prefs.get(Settings.showMenuBarIcon)) _showTray();
      _settings = _prefs.changes.listen((setting) {
        if (setting.key == Settings.enableStartUp.key) unawaited(_applyStartup());
        if (mac && setting.key == Settings.showMenuBarIcon.key) {
          if (_prefs.get(Settings.showMenuBarIcon)) {
            _showTray();
          } else {
            _tray?.dispose();
            _tray = null;
          }
        }
      });
      if (isReleaseBuild) unawaited(_applyStartup());
    }
    if (Platform.isWindows) {
      _uninstall = WindowsUninstallHandler(exit);
      await _uninstall!.connect();
    }
  }

  void _showTray() {
    if (_tray != null) return;
    try {
      _tray = DesktopTray.create(
        onShow: show,
        onHide: appWindow.hide,
        onExit: _closer.exitFromTray,
        mac: DesktopWindow.macStyle,
        onRecordCenter: () async {
          await show();
          AppCommand.record.run();
        },
      )..setRecording(_activeRecordings);
    } on Object catch (error, stack) {
      // Without a tray, "minimize" minimizes to the taskbar (c7).
      log('Tray failed', name: 'Desktop', error: error, stackTrace: stack);
    }
  }

  /// The primary display's work area, or null when unknown.
  Future<Size?> _workArea() async {
    try {
      final displays = readDesktopDisplays();
      final display = displays.where((display) => display.isPrimary).firstOrNull ?? displays.firstOrNull;
      return display?.workArea.size;
    } on Object {
      return null;
    }
  }

  /// Whether [position] puts most of the window's title row on a display.
  Future<bool> _onScreen(Offset position, Size size) async {
    try {
      final displays = readDesktopDisplays();
      return titleRowOnScreen(position, size, [for (final display in displays) display.workArea]);
    } on Object {
      return false;
    }
  }

  /// The start-up entry for the settings row (3.x `StartupController`'s
  /// "applying" and "failed" texts).
  static final ValueNotifier<StartupEntryState> startupState = ValueNotifier(StartupEntryState.idle);

  Future<void> _applyStartup() async {
    startupState.value = StartupEntryState.applying;
    final applied = await applyStartupEntry(enabled: _prefs.get(Settings.enableStartUp));
    startupState.value = applied ? StartupEntryState.idle : StartupEntryState.failed;
  }

  /// Gives the window [size] now (3.x applied the window size setting at
  /// once); a maximized or full-screen window is restored first. False when
  /// the window manager refused.
  Future<bool> resize(Size size) async {
    try {
      if (await appWindow.isFullScreen()) await appWindow.setFullScreen(false);
      if (await appWindow.isMaximized()) await appWindow.unmaximize();
      await appWindow.setSize(size);
      return true;
    } on Object catch (error, stack) {
      log('Window size not applied', name: 'Desktop', error: error, stackTrace: stack);
      return false;
    }
  }

  /// Shows and focuses the window (tray, second launch).
  Future<void> show() async {
    await appWindow.show();
    await appWindow.focus();
  }

  /// Closes this window's app: stops its recordings (what was recorded is
  /// kept), saves the window and leaves (3.x `exitDesktopApplication`).
  Future<void> exit() async {
    await _beforeExit();
    await appWindow.setPreventClose(false);
    await appWindow.destroy();
  }

  /// macOS is asked to quit (⌘Q, the Dock's or the menu bar icon's "退出",
  /// A18.2 c6): while recording it asks first; then the same as [exit]
  /// before the system ends the app.
  Future<AppExitResponse> _exitRequested() async {
    if (_quitting) return AppExitResponse.exit;
    final count = _activeRecordings;
    if (count > 0) {
      await show();
      final context = AppNavigator.navigatorContext;
      if (context != null && context.mounted && !await showQuitWhileRecordingDialog(context, recording: count)) {
        return AppExitResponse.cancel;
      }
    }
    _quitting = true;
    await _beforeExit();
    return AppExitResponse.exit;
  }

  Future<void> _beforeExit() async {
    await _saveGeometry();
    try {
      await _recording?.dispose().timeout(const Duration(seconds: 3));
    } on Object catch (error, stack) {
      log('Recording stop failed', name: 'Desktop', error: error, stackTrace: stack);
    }
    // An extra window's own task list is not read again (a new window gets
    // a new id).
    if (!primary) await _forget(recorderTasksKeyFor(_instanceId));
    _tray?.dispose();
    _tray = null;
  }

  Future<void> _forget(String key) async {
    try {
      await _store.meta.set(key, null);
    } on Object {
      // Left behind; nothing reads it.
    }
  }

  /// The title bar's or the system's close ([WindowCloser.close]).
  Future<void> requestClose() => _closer.close();

  Future<CloseChoice?> _ask({
    required bool tray,
    required int recording,
    required bool askRemember,
    required bool remember,
  }) async {
    final context = AppNavigator.navigatorContext;
    // Nothing to ask on: leave, as before.
    if (context == null) return (action: CloseAction.exit, remember: remember);
    return await showCloseWindowDialog(
      context,
      tray: tray,
      recording: recording,
      askRemember: askRemember,
      remember: remember,
    );
  }

  /// The window's name follows the room on top (c11).
  void _retitle() {
    final title = nativeWindowTitle(i18nOr('app_name', 'PureLive'), roomNameOf(liveRouteObserver.topPage.value));
    if (title == _title) return;
    _title = title;
    unawaited(appWindow.setTitle(title).catchError((Object _) {}));
  }

  @override
  void onWindowClose() => unawaited(requestClose());

  @override
  void onWindowResized() {
    DesktopWindow.resizing.value = null;
    _scheduleSave();
  }

  @override
  void onWindowResize() =>
      unawaited(appWindow.getSize().then((size) => DesktopWindow.resizing.value = size, onError: (Object _) => null));

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowMaximize() => _maximizedChanged(maximized: true);

  @override
  void onWindowUnmaximize() => _maximizedChanged(maximized: false);

  void _maximizedChanged({required bool maximized}) {
    // Windows may restore from the taskbar with maximize, without restore.
    DesktopWindow.minimized.value = false;
    DesktopWindow.maximized.value = maximized;
    // The mini window un-maximizes on its way in; that is not the user's.
    if (primary && !DesktopWindow.mini.value) unawaited(_remember(windowMaximizedKey, maximized ? '1' : '0'));
  }

  Future<void> _remember(String key, String value) async {
    try {
      await _store.meta.set(key, value);
    } on Object catch (error, stack) {
      log('Saving the window failed', name: 'Desktop', error: error, stackTrace: stack);
    }
  }

  @override
  void onWindowFocus() {
    DesktopWindow.minimized.value = false;
    _shared?.check();
  }

  @override
  void onWindowMinimize() => DesktopWindow.minimized.value = true;

  @override
  void onWindowRestore() => DesktopWindow.minimized.value = false;

  @override
  void onWindowEnterFullScreen() => DesktopWindow.fullScreen.value = true;

  @override
  void onWindowLeaveFullScreen() => DesktopWindow.fullScreen.value = false;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () => unawaited(_saveGeometry()));
  }

  /// Remembers the main window's normal size (3.x) and place (new): not
  /// while maximized, minimized or full screen. An extra window remembers
  /// nothing (the data is shared, c14). The mini window remembers its own
  /// (`rememberPipPosition`, U.2j).
  Future<void> _saveGeometry() async {
    _saveTimer?.cancel();
    if (DesktopWindow.mini.value) {
      await _mini?.saveGeometry();
      return;
    }
    if (!primary) return;
    try {
      if (await appWindow.isMaximized() || await appWindow.isMinimized() || await appWindow.isFullScreen()) {
        return;
      }
      final bounds = await appWindow.getBounds();
      await rememberNormalWindowSize(_store, bounds.size);
      await _store.meta.set(windowPositionKey, formatWindowPosition(bounds.topLeft));
    } on Object catch (error, stack) {
      log('Saving the window failed', name: 'Desktop', error: error, stackTrace: stack);
    }
  }

  /// Updates the tray's and the window's words (the language changed).
  void relabel() {
    _tray?.relabel();
    _title = null;
    _retitle();
  }

  /// Stops listening (tests, shutdown).
  Future<void> dispose() async {
    _uninstall?.dispose();
    await projection?.dispose();
    appWindow.removeListener(this);
    _exitListener?.dispose();
    liveRouteObserver.topPage.removeListener(_retitle);
    _saveTimer?.cancel();
    await _settings?.cancel();
    await _recordings?.cancel();
    await _shared?.dispose();
    _tray?.dispose();
    if (identical(DesktopWindow.miniHost, _mini)) {
      DesktopWindow.miniHost = null;
      DesktopWindow.resizeArea = (child) => child;
      DesktopWindow.controls = null;
      DesktopWindow.newWindowLauncher = null;
    }
    if (identical(current, this)) current = null;
  }
}

/// Whether a window at [position] of [size] has most of its title row on
/// one of [displays] (work areas): a monitor unplugged since last time
/// would hide it (U.13 c6).
bool titleRowOnScreen(Offset position, Size size, List<Rect> displays) {
  final title = Rect.fromLTWH(position.dx + 40, position.dy, (size.width - 80).clamp(40, double.infinity), 32);
  return displays.any((area) => area.overlaps(title));
}

/// The window's size from [wanted]: at least [DesktopShell.minimumSize], at
/// most the display's [workArea] when it is known.
Size fitWindowSize(Size wanted, Size? workArea) {
  const minimum = DesktopShell.minimumSize;
  double fit(double value, double low, double? high) {
    final top = high == null ? double.infinity : (high < low ? low : high);
    return value.clamp(low, top);
  }

  return Size(fit(wanted.width, minimum.width, workArea?.width), fit(wanted.height, minimum.height, workArea?.height));
}

/// `x,y` of a stored window position; null when missing or unreadable.
Offset? parseWindowPosition(String? text) {
  final parts = (text ?? '').split(',');
  if (parts.length != 2) return null;
  final x = double.tryParse(parts[0]);
  final y = double.tryParse(parts[1]);
  if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
  return Offset(x, y);
}

/// The stored form of a window position.
String formatWindowPosition(Offset position) => '${position.dx.round()},${position.dy.round()}';

/// Whether this is a release build (the start-up entry is only reconciled at
/// launch there, so development builds never register themselves).
const bool isReleaseBuild = bool.fromEnvironment('dart.vm.product');

/// The state of the Windows start-up entry.
enum StartupEntryState {
  /// Nothing pending; the entry follows the setting.
  idle,

  /// Being written.
  applying,

  /// The last write failed.
  failed,
}
