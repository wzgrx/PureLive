import 'dart:async';

import 'package:live_player/live_player.dart';

/// A scripted [PlayerEngine]: records every call; [onOpen] decides what an
/// open does (default: succeed, then report buffering and playing).
final class FakeEngine implements PlayerEngine, LiveRewindCache {
  final StreamController<EngineEvent> _events = StreamController.broadcast(sync: true);

  /// Every opened media, in order.
  final List<EngineMedia> opens = [];

  /// Calls other than open, in order (`play`, `pause`, `stop`, `seek`, ...).
  final List<String> calls = [];

  /// The current verified ranges or a gated native response for tests.
  Future<List<LiveRewindRange>> Function()? liveRanges;

  @override
  Future<List<LiveRewindRange>> readLiveSeekRanges() async => await liveRanges?.call() ?? const [];

  /// What the next opens do; null opens and plays.
  Future<void> Function(EngineMedia media)? onOpen;

  /// Optional native teardown delay/failure for lifecycle fault injection.
  Future<void> Function()? onDispose;

  /// Optional stop reply held by a busy native player.
  Future<void> Function()? onStop;

  /// Optional queued control operation for a busy native player.
  Future<void> Function(double)? onVolume;

  @override
  bool reportsFrames = false;

  /// Whether [dispose] ran.
  bool disposed = false;

  @override
  Stream<EngineEvent> get events => _events.stream;

  /// Reports [event].
  void emit(EngineEvent event) => _events.add(event);

  /// The position [advance] reports next.
  Duration position = Duration.zero;

  /// Reports playback moving on by [step] (mpv's `time-pos`).
  void advance([Duration step = const Duration(seconds: 1)]) {
    position += step;
    emit(EnginePosition(position));
  }

  /// Reports a started picture.
  void playing() {
    emit(const EngineBuffering(buffering: false));
    emit(const EnginePlaying(playing: true));
  }

  @override
  Future<void> open(EngineMedia media) async {
    opens.add(media);
    final script = onOpen;
    if (script != null) {
      await script(media);
      return;
    }
    playing();
  }

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async {
    calls.add('stop');
    await onStop?.call();
  }

  @override
  Future<void> seek(Duration position) async => calls.add('seek ${position.inSeconds}');

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume $volume');
    await onVolume?.call(volume);
  }

  @override
  Future<void> setAudioOnly({required bool enabled}) async => calls.add('audioOnly $enabled');

  @override
  Future<void> dispose() async {
    disposed = true;
    await onDispose?.call();
    await _events.close();
  }
}
