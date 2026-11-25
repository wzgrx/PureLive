import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/desktop/app_window_api.dart';

/// Last normal dimensions are separate from the user's fixed startup preset.
const windowNormalSizeKey = 'window.normalSize';

/// Resolves the main window's explicit policy before the first native layout.
Future<({Size size, bool maximized})> startupWindowGeometry(LiveStore store, {required bool primary}) async {
  final prefs = store.settings;
  final fixed = Size(prefs.get(Settings.windowWidth), prefs.get(Settings.windowHeight));
  if (!primary || !prefs.get(Settings.rememberWindowGeometry)) return (size: fixed, maximized: false);
  final parts = (await store.meta.get(windowNormalSizeKey))?.split(',');
  final width = parts?.length == 2 ? double.tryParse(parts![0]) : null;
  final height = parts?.length == 2 ? double.tryParse(parts![1]) : null;
  final valid = width != null && height != null && width.isFinite && height.isFinite && width > 0 && height > 0;
  return (size: valid ? Size(width, height) : fixed, maximized: await store.meta.get('window.maximized') == '1');
}

/// Saves only observed normal dimensions; dragging never edits a fixed preset.
Future<void> rememberNormalWindowSize(LiveStore store, Size size) async {
  if (!size.width.isFinite || !size.height.isFinite || size.width <= 0 || size.height <= 0) return;
  await store.meta.set(windowNormalSizeKey, '${size.width.clamp(360, 16384)},${size.height.clamp(400, 16384)}');
}

/// Restore the complete native layout before runApp can submit its first frame.
/// window_manager's optional callback is void and does not await async work.
Future<void> restoreStartupWindow(
  AppWindowOptions options,
  Future<void> Function() restore, {
  Future<void> Function(AppWindowOptions)? prepare,
}) async {
  await (prepare ?? appWindow.waitUntilReadyToShow)(options);
  await restore();
  if (defaultTargetPlatform == TargetPlatform.windows) {
    await const MethodChannel('pure_live/window_startup').invokeMethod<void>('layoutReady');
  }
}
