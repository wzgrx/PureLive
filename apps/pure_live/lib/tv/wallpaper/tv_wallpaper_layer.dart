import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_files.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_model.dart';
import 'package:pure_live/tv/wallpaper/wallpaper_playback.dart';

/// Sets and changes the TV background; its files in the app's support
/// folder, `tv_wallpaper/`.
final Provider<TvWallpaperStore> tvWallpaperStoreProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  return TvWallpaperStore(
    settings: services.store.settings,
    files: TvWallpaperFiles(
      folder: Future.value(Directory(p.join(services.dataRoot.path, 'tv_wallpaper'))),
      http: services.http,
    ),
  );
});

/// The background now (rebuilt when any of its settings change).
TvWallpaper watchTvWallpaper(WidgetRef ref) {
  for (final setting in <Setting<Object>>[
    Settings.tvWallpaperKind,
    Settings.tvWallpaperValue,
    Settings.tvWallpaperFit,
    Settings.tvWallpaperMask,
  ]) {
    watchSetting(ref, setting);
  }
  return TvWallpaper.of(ref.read(storeProvider).settings);
}

/// Foreground video holds the optional background until its own cleanup ends.
abstract final class TvWallpaperVideo {
  static final ValueNotifier<int> _holds = ValueNotifier(0);
  static final Set<TvWallpaperPlayback> _players = {};
  static final Set<Future<void>> _retiringWallpapers = {};

  /// Number of foreground video owners.
  static ValueListenable<int> get holds => _holds;

  /// Suspends and retires all registered background sessions before playback.
  static Future<void> hold() {
    _holds.value++;
    return Future.wait([
      for (final player in _players.toList()) player.setHeld(held: true),
      for (final cleanup in _retiringWallpapers.toList()) _waitForBackgroundCleanup(cleanup),
    ]);
  }

  /// A replaced room still owns resources until its asynchronous cleanup ends.
  static void trackCleanup(Future<void> cleanup) {
    unawaited(hold());
    unawaited(releaseAfter(cleanup));
  }

  /// Restores the background only after the last foreground owner leaves.
  static void release() {
    _holds.value = (_holds.value - 1).clamp(0, 1 << 20);
    for (final player in _players.toList()) {
      unawaited(player.setHeld(held: _holds.value > 0));
    }
  }

  /// Keeps decoding resources mutually exclusive during foreground shutdown.
  static Future<void> releaseAfter(Future<void> cleanup) async {
    try {
      await cleanup.timeout(const Duration(seconds: 6));
    } on Object {
      developer.log('Foreground playback retirement unavailable', name: 'TvWallpaper');
      // The background stays held until the original cleanup actually ends.
      unawaited(cleanup.then((_) => release(), onError: (Object _) {}));
      return;
    }
    release();
  }

  static void _register(TvWallpaperPlayback player) {
    _players.add(player);
    // Flutter mounts a replacement before disposing the old keyed view.
    // Apply visibility after finalizing that tree, when retirement is tracked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_players.contains(player)) unawaited(player.setHeld(held: _holds.value > 0));
    });
  }

  static void _unregister(TvWallpaperPlayback player) {
    _players.remove(player);
    // A view leaving the tree does not prove its native decoder is gone.
    unawaited(hold());
    final cleanup = player.waitForResourceRelease();
    _retiringWallpapers.add(cleanup);
    unawaited(
      cleanup.then(
        (_) {
          _retiringWallpapers.remove(cleanup);
          release();
        },
        onError: (Object _) {
          _retiringWallpapers.remove(cleanup);
          // Keep cosmetics held when actual release cannot be established.
          developer.log('Unmounted wallpaper retirement unavailable', name: 'TvWallpaper');
        },
      ),
    );
  }

  static Future<void> _waitForBackgroundCleanup(Future<void> cleanup) async {
    try {
      await cleanup.timeout(const Duration(seconds: 6));
    } on Object {
      developer.log('Unmounted wallpaper startup barrier unavailable', name: 'TvWallpaper');
    }
  }
}

/// The TV interface's background (A17.8 h1), under every TV page: a colour,
/// a gradient, a picture (blurred already, h7) or a muted looping video,
/// with the dark veil over it. Nothing when there is none (the pages then
/// paint the theme's colour as before).
class TvWallpaperLayer extends ConsumerWidget {
  /// Creates the layer.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpaper = watchTvWallpaper(ref);
    if (!wallpaper.active) return const SizedBox.shrink();
    final picture = switch (wallpaper.kind) {
      TvWallpaperKind.color => ColoredBox(color: parseColorHex(wallpaper.value) ?? OnVideoColors.ground),
      TvWallpaperKind.gradient => DecoratedBox(
        decoration: BoxDecoration(gradient: tvGradientOf(wallpaper.value)?.gradient),
      ),
      TvWallpaperKind.image => Image.file(
        File(wallpaper.value),
        key: ValueKey('tv-wallpaper-image-${wallpaper.value}'),
        fit: wallpaper.fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
      TvWallpaperKind.video => _VideoWallpaper(
        key: ValueKey(wallpaper.value),
        path: wallpaper.value,
        fit: wallpaper.fit,
      ),
      TvWallpaperKind.none => const SizedBox.shrink(),
    };
    return Stack(
      key: const ValueKey('tv-wallpaper'),
      fit: StackFit.expand,
      children: [
        picture,
        if (wallpaper.kind != TvWallpaperKind.color && wallpaper.kind != TvWallpaperKind.gradient)
          ColoredBox(color: OnVideoColors.ground.withValues(alpha: wallpaper.mask)),
      ],
    );
  }
}

class _VideoWallpaper extends ConsumerStatefulWidget {
  const new({required this.path, required this.fit, super.key});

  final String path;
  final BoxFit fit;

  @override
  ConsumerState<_VideoWallpaper> createState() => _VideoWallpaperState();
}

class _VideoWallpaperState extends ConsumerState<_VideoWallpaper> {
  late final TvWallpaperPlayback _player;
  PlaybackSession? _session;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final create = ref.read(playbackSessionFactoryProvider);
    _player = TvWallpaperPlayback(
      createSession: create,
      request: () => PlaybackRequest(
        site: 'wallpaper',
        volume: 0,
        plan: PlaybackPlan.of(
          LivePlayUrlResolution.lines([LivePlayLine(Uri.file(widget.path).toString())]),
          onDemand: true,
        ),
      ),
      onSessionChanged: (session) {
        if (mounted && !_closing) setState(() => _session = session);
      },
    );
    TvWallpaperVideo._register(_player);
  }

  @override
  void dispose() {
    _closing = true;
    TvWallpaperVideo._unregister(_player);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch (_session) {
    final session? => LiveVideoView(session: session, fit: widget.fit),
    null => const SizedBox.expand(),
  };
}
