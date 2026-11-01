import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Shared fullscreen visibility policy, including Android before API 29.
abstract final class SystemUiVisibility {
  static const MethodChannel _channel = MethodChannel('pure_live/system_access');
  static int _turn = 0;

  /// The latest fullscreen request supersedes a pending legacy restoration.
  static Future<void> fullscreen() async {
    _turn++;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// Restores normal bars while preserving the current platform's layout.
  static Future<void> restore() async {
    final turn = ++_turn;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (turn != _turn || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      // edgeToEdge is ignored before Android 10. Use Flutter's supported
      // overlay request there so its cached state also survives resume.
      final legacy = await _channel.invokeMethod<bool>('needsLegacySystemBars') ?? false;
      if (legacy && turn == _turn) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      }
    } on MissingPluginException {
      // Older/host test engines retain the standard Flutter request above.
    } on PlatformException {
      // A detached activity cannot restore its window yet.
    }
  }
}
