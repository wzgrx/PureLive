import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/data_root.dart';
import 'package:pure_live/app/desktop/app_window_api.dart';
import 'package:pure_live/app/desktop/display_geometry.dart';
import 'package:pure_live/app/desktop/projection_channel.dart';
import 'package:pure_live/app/intake/system_intake.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

/// Opens a wall selection in the receiver's existing window.
void navigateProjectionRoom(LiveRoom room) {
  // Keep the receiver's home under its first room. Replacing the only root
  // match gives consecutive rooms the same GoRouter page key, preserving the
  // old StatefulWidget/player even though the route's arguments have changed.
  final navigate = AppNavigator.router.canPop() ? AppNavigator.offAndToNamed<void> : AppNavigator.toNamed<void>;
  unawaited(navigate(RoutePath.kLivePlay, arguments: LiveRoomArgs(room: room, startFullscreen: true)));
}

/// The native side of an explicitly launched projection window.
final class ProjectionRuntime {
  new _();

  ProjectionReceiver? _receiver;
  Timer? _displays;
  String? _display;
  String? _requestedDisplay;
  bool _moving = false;
  bool _closed = false;

  /// Starts after the router exists, only for `--projection` child windows.
  static Future<ProjectionRuntime?> start(AppServices services) async {
    if (!services.launch.projection || services.launch.isPrimary) return null;
    final runtime = ProjectionRuntime._();
    runtime._receiver = await ProjectionReceiver.start(
      file: File(p.join(instanceFolder(services.dataRoot, services.launch.instanceId).path, 'projection.json')),
      onOpen: runtime._open,
      onClose: () async {
        await runtime.dispose();
        if ((services.recording?.activeCount ?? 0) > 0) return;
        await appWindow.destroy();
      },
    );
    runtime._displays = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(runtime._checkDisplay()));
    return runtime;
  }

  Future<void> _open(ProjectionSelection selection) async {
    if (_closed) return;
    final context = await appNavigatorReady();
    if (_closed || context == null || !context.mounted) return;
    // Repeated cell choices do not focus the window or change its virtual
    // desktop. The user may move it with Task View / Mission Control once.
    if (_requestedDisplay != selection.display) {
      await _move(selection.display);
      _requestedDisplay = selection.display;
    }
    if (_closed) return;
    navigateProjectionRoom(selection.room);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _move(String key) async {
    if (_moving || _closed) return;
    _moving = true;
    try {
      if (key.isNotEmpty) {
        final displays = readDesktopDisplays();
        final target =
            displays.where((display) => display.persistenceKey == key).firstOrNull ??
            displays.where((display) => display.isPrimary).firstOrNull ??
            displays.firstOrNull;
        if (target != null) {
          final fullscreen = await appWindow.isFullScreen();
          if (fullscreen) await appWindow.setFullScreen(false);
          await appWindow.setBounds(target.workArea);
          if (fullscreen) await appWindow.setFullScreen(true);
          _display = target.persistenceKey;
        }
      } else {
        _display = '';
      }
    } on Object {
      // A display can disappear between the snapshot and the native move.
      // Retain the old key so the next poll can retry the primary fallback.
    } finally {
      _moving = false;
    }
  }

  Future<void> _checkDisplay() async {
    if (_closed || _moving || _display == null || _display!.isEmpty) return;
    try {
      if (!readDesktopDisplays().any((display) => display.persistenceKey == _display)) await _move(_display!);
    } on Object {
      // A transient native monitor enumeration failure is retried next poll.
    }
  }

  /// Releases the loopback endpoint and monitor watcher.
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _displays?.cancel();
    await _receiver?.dispose();
  }
}
