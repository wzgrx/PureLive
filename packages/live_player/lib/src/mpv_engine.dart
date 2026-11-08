import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/src/buffering_probe.dart';
import 'package:live_player/src/diagnostics.dart';
import 'package:live_player/src/engine.dart';
import 'package:live_player/src/frame_rate.dart';
import 'package:live_player/src/mpv_input.dart';
import 'package:live_player/src/mpv_options.dart';
import 'package:live_player/src/playback_stats.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// The [MpvPlatform] of a Flutter [platform]; null on Fuchsia.
MpvPlatform? mpvPlatformOf(TargetPlatform platform) => switch (platform) {
  TargetPlatform.android => MpvPlatform.android,
  TargetPlatform.iOS => MpvPlatform.ios,
  TargetPlatform.windows => MpvPlatform.windows,
  TargetPlatform.linux => MpvPlatform.linux,
  TargetPlatform.macOS => MpvPlatform.macos,
  TargetPlatform.fuchsia => null,
};

/// The display size in [params] with rotation applied (3.x's
/// `resolveVideoParamsDisplaySize`): width and height come from the same
/// event, so a transient width is never paired with an older height.
({int width, int height})? displaySizeOf(VideoParams params) {
  var width = params.dw ?? params.w ?? 0;
  var height = params.dh ?? params.h ?? 0;
  if (width <= 0 || height <= 0) return null;
  final rotate = (params.rotate ?? 0) % 180;
  if (rotate == 90) (width, height) = (height, width);
  return (width: width, height: height);
}

/// The mpv [PlayerEngine] over the media_kit fork in `third_party/` (3.x's
/// `MediaKitAdapter`, the only engine in v4).
///
/// - [MpvEngineConfig.liveProperties] are applied once per player; every
///   open sets `hwdec` (software for the session's decoder fallback) and
///   `http-proxy` (empty for loopback inputs), then loads the media with its
///   headers.
/// - mpv's error log goes through [NativeDiagnosticGate]; the session only
///   sees confirmed failures.
/// - Audio-only mode never reopens: Android turns the controller's video
///   output off (the fork's `setVideoOutputEnabled`), desktop selects
///   `vid=no`; Android does not re-send `vid=auto` after an open.
/// - Windows reports presented frames (the fork's `frameRevision`).
final class MpvEngine implements PlayerEngine, PlaybackRate, PlaybackStatsSource, VolumeGainControl {
  new _(
    this.player,
    this.controller,
    this.config,
    this._diagnosticEngine,
    this._trace, {
    void Function(String)? onBufferingSnapshot,
  }) {
    _bufferingProbe = NativeBufferingProbe(
      read: _readProperty,
      report: (line) => (onBufferingSnapshot ?? debugPrint)('$line engine=$_diagnosticEngine open=$_diagnosticOpens'),
    );
    _gate = NativeDiagnosticGate(onError: (error) => _add(EngineError(error)));
    _bind();
  }

  /// Creates the player and its video controller. Needs a Flutter binding.
  /// [onBufferingSnapshot] receives bounded, non-identifying native state
  /// before a stall timeout, so applications can retain it at normal log level.
  static Future<MpvEngine> create({
    MpvEngineConfig? config,
    void Function(String)? onBufferingSnapshot,
    @visibleForTesting FutureOr<Player> Function()? createPlayer,
  }) async {
    final resolved = config ?? MpvEngineConfig(platform: mpvPlatformOf(defaultTargetPlatform) ?? MpvPlatform.linux);
    final id = ++_nextDiagnosticEngine;
    var open = 0;
    void report(String phase, [int? error]) {
      try {
        (onBufferingSnapshot ?? debugPrint)(
          'mpv lifecycle engine=$id open=$open phase=$phase${error == null ? '' : ' error=$error'}',
        );
      } on Object {
        /* Diagnostic sinks cannot change playback. */
      }
    }

    report('create-request');
    MediaKit.ensureInitialized();
    final player = await (createPlayer?.call() ?? Player(configuration: const PlayerConfiguration(title: 'Pure Live')));
    try {
      final native = player.platform;
      if (native is NativePlayer) {
        native.lifecycleListener = report;
        report('native-wait');
        await native.waitForPlayerInitialization;
        report('configure-live');
        for (final MapEntry(:key, :value) in resolved.liveProperties.entries) {
          await native.setPropertyAsync(key, value);
        }
      }
      final probe = mpvProbeValues();
      if (probe != mpvProbeDefaults) {
        debugPrint('mpv probe override: probesize=${probe.probeSize} analyzeduration=${probe.analyzeDuration}');
      }
      final macos = resolved.platform == MpvPlatform.macos;
      final controller = VideoController(
        player,
        configuration: VideoControllerConfiguration(
          vo: resolved.videoOutput,
          hwdec: resolved.preferredHardwareDecoder,
          enableHardwareAcceleration: !macos && resolved.preferredHardwareDecoder != 'no',
          androidAttachSurfaceAfterVideoParameters: resolved.customOutput || resolved.androidCompatibility
              ? null
              : false,
        ),
      );
      report('engine-ready');
      return MpvEngine._(player, controller, resolved, id, (phase) {
        if (phase == 'open-request') open++;
        report(phase);
      }, onBufferingSnapshot: onBufferingSnapshot);
    } on Object {
      report('create-failed');
      // The caller never received an engine, so this factory still owns Player.
      // Await cleanup: if native disposal hangs, the session retains this attempt
      // in its bounded quarantine rather than silently leaking its allocation.
      try {
        await player.dispose();
        report('failed-create-released');
      } on Object {
        report('failed-create-release-error');
      }
      rethrow;
    }
  }

  /// The media_kit player.
  final Player player;

  /// Its video controller; `LiveVideoView` renders it.
  final VideoController controller;

  /// Configuration.
  final MpvEngineConfig config;
  int? _roomGainDb;

  @override
  Future<void> setVolumeGainDb(int? decibels) async {
    _roomGainDb = decibels?.clamp(-12, 12);
    await _setProperty('volume-gain', '${(_roomGainDb ?? config.volumeGainDb).clamp(-12, 12)}');
  }

  late final NativeDiagnosticGate _gate;
  final StreamController<EngineEvent> _events = StreamController.broadcast(sync: true);
  final List<StreamSubscription<Object?>> _subscriptions = [];
  VoidCallback? _frameListener;
  late final NativeBufferingProbe _bufferingProbe;
  bool _hasSource = false;
  var _audioOnly = false;
  var _externalAudio = false;
  var _disposed = false;
  var _opens = 0;
  static var _nextDiagnosticEngine = 0;
  final int _diagnosticEngine;
  final void Function(String phase) _trace;
  var _diagnosticOpens = 0;

  bool get _android => config.platform == MpvPlatform.android;

  @override
  Stream<EngineEvent> get events => _events.stream;

  @override
  bool get reportsFrames => config.platform == MpvPlatform.windows;

  void _add(EngineEvent event) {
    if (!_disposed) _events.add(event);
  }

  void _bind() {
    final stream = player.stream;
    _subscriptions
      ..add(
        stream.playing.listen((playing) {
          _gate.playback(playing: playing, buffering: player.state.buffering, audioOnly: _audioOnly);
          _add(EnginePlaying(playing: playing));
        }),
      )
      ..add(
        stream.buffering.listen((buffering) {
          _gate.playback(playing: player.state.playing, buffering: buffering, audioOnly: _audioOnly);
          _add(EngineBuffering(buffering: buffering));
          _watchBuffering(buffering);
        }),
      )
      ..add(
        stream.completed.listen((completed) {
          if (completed) _add(const EngineCompleted());
        }),
      )
      ..add(
        stream.videoParams.listen((params) {
          final size = displaySizeOf(params);
          if (size == null) return;
          _gate.videoFrame();
          _add(EngineVideoSize(size.width, size.height));
        }),
      )
      ..add(
        stream.audioParams.listen((params) {
          if ((params.format?.isNotEmpty ?? false) || (params.sampleRate ?? 0) > 0) _gate.audioFrame();
        }),
      )
      ..add(stream.position.listen((position) => _add(EnginePosition(position))))
      ..add(stream.duration.listen((duration) => _add(EngineDuration(duration))))
      ..add(stream.log.listen((log) => _gate.log(log.prefix, log.level, log.text)));
    if (reportsFrames) {
      var last = controller.frameRevision.value;
      void onFrame() {
        final revision = controller.frameRevision.value;
        if (revision == last) return;
        last = revision;
        _add(const EngineFrame());
      }

      _frameListener = onFrame;
      controller.frameRevision.addListener(onFrame);
    }
  }

  /// A release build must retain the same bounded, non-identifying stall
  /// evidence as a profile build, without acting on or resetting the decoder.
  void _watchBuffering(bool buffering) {
    _bufferingProbe.update(buffering: !_disposed && _hasSource && buffering);
  }

  Future<void> _setProperty(String name, String value) async {
    final native = player.platform;
    if (native is NativePlayer) {
      await native.waitForPlayerInitialization;
      await native.waitForVideoControllerInitializationIfAttached;
      // Reconfiguring a reused decoder can wait on the native core. Keep the
      // UI isolate and the source-open deadline alive while that request runs.
      await native.setPropertyAsync(name, value);
    }
  }

  @override
  Future<void> open(EngineMedia media) async {
    _roomGainDb = media.volumeGainDb?.clamp(-12, 12);
    _diagnosticOpens++;
    _trace('open-request');
    _bufferingProbe.reset();
    _hasSource = true;
    _watchBuffering(true);
    _gate.beginOpen(decoderStartupWindow: mpvDecoderStartupWindow(media.uri));
    try {
      _trace('configure-open');
      final decoder = config.hwdecFor(software: media.decoder == DecoderMode.software);
      if (config.platform == MpvPlatform.android) {
        _trace('video-policy hwdec=$decoder vo=${config.videoOutput ?? 'default'}');
      }
      await _setProperty('hwdec', decoder);
      await _setProperty('http-proxy', media.proxyUrl);
      await _setProperty('volume-gain', '${(_roomGainDb ?? config.volumeGainDb).clamp(-12, 12)}');
      await _setExternalAudio(media.audio);
      _trace('load-request');
      await openMpvMediaInput(
        media.uri,
        configure: _setProperty,
        open: (input) => player.open(Media(input, httpHeaders: media.headers, start: media.start)),
      );
    } on Object catch (error, stack) {
      _hasSource = false;
      _bufferingProbe.reset();
      if (error is PlayerException) rethrow;
      final classification = NativeDiagnostic.classify(error.toString());
      throw PlayerException(
        message: 'Media open failed: $error',
        type: classification.type == PlayerErrorType.native ? PlayerErrorType.source : classification.type,
        code: classification.code,
        error: error,
        stackTrace: stack,
      );
    } finally {
      _gate.finishOpen();
    }
    if (media.audioOnly) {
      await _applyAudioOnly(enabled: true);
    } else if (_audioOnly) {
      await _applyAudioOnly(enabled: false);
    }
    // The session acts on these once the open is authorized.
    final state = player.state;
    final size = displaySizeOf(state.videoParams);
    if (size != null) _add(EngineVideoSize(size.width, size.height));
    _add(EngineBuffering(buffering: state.buffering));
    _watchBuffering(state.buffering);
    _add(EnginePlaying(playing: state.playing));
    unawaited(_probeFrameRate(++_opens));
  }

  /// U.2i: the frame rate of what this open plays, once known.
  Future<void> _probeFrameRate(int open) async {
    bool current() => !_disposed && open == _opens;
    try {
      final fps = await probeFrameRate(_readProperty, current: current);
      if (fps != null && current()) _add(EngineFrameRate(fps));
    } on Object {
      // No frame rate: the display keeps its own choice.
    }
  }

  Future<String> _readProperty(String name) async {
    final native = player.platform;
    if (_disposed || native is! NativePlayer) return '';
    return await native.getPropertyAsync(name);
  }

  @override
  Future<PlaybackStats> readStats() => readPlaybackStats(_readProperty);

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() {
    _hasSource = false;
    _bufferingProbe.reset();
    _trace('stop-request');
    return player.stop().then((_) => _trace('stop-complete'));
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> setVolume(double volume) => player.setVolume((volume * 100).clamp(0, 100).toDouble());

  /// Sets mpv's `audio-files` to [audio] (or clears it when an earlier open
  /// set one); the option applies to the next file loaded. A URL is appended
  /// as one item with `change-list` (a path list would split it at colons).
  Future<void> _setExternalAudio(ExternalAudio? audio) async {
    final native = player.platform;
    if (native is! NativePlayer) return;
    if (audio == null && !_externalAudio) return;
    await _setProperty('audio-files', '');
    _externalAudio = audio != null;
    if (audio != null) await native.command(['change-list', 'audio-files', 'append', audio.uri.toString()]);
  }

  @override
  Future<void> setRate(double rate) => player.setRate(rate.clamp(0.25, 4).toDouble());

  @override
  Future<void> setAudioOnly({required bool enabled}) => _applyAudioOnly(enabled: enabled);

  Future<void> _applyAudioOnly({required bool enabled}) async {
    if (enabled) {
      if (_android) {
        await controller.setVideoOutputEnabled(false);
      } else {
        await player.setVideoTrack(VideoTrack.no());
      }
      _audioOnly = true;
      return;
    }
    if (!_audioOnly) return;
    // Wait for a decoded picture (at most 2.8 s) so the view never uncovers
    // a black texture.
    final picture = Completer<void>();
    final subscription = player.stream.videoParams.listen((params) {
      if (displaySizeOf(params) != null && !picture.isCompleted) picture.complete();
    });
    try {
      if (_android) {
        await controller.setVideoOutputEnabled(true);
      } else {
        await player.setVideoTrack(VideoTrack.auto());
      }
      _audioOnly = false;
      await picture.future.timeout(const Duration(milliseconds: 2800), onTimeout: () {});
    } finally {
      unawaited(subscription.cancel());
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _opens++;
    _bufferingProbe.close();
    _gate.close();
    final listener = _frameListener;
    if (listener != null) controller.frameRevision.removeListener(listener);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    try {
      await player.stop();
    } on Object {
      // Already stopped or never opened.
    }
    await player.dispose();
    await _events.close();
  }
}

/// An [EngineFactory] creating [MpvEngine]s with [config].
EngineFactory mpvEngineFactory([MpvEngineConfig? config]) =>
    () => MpvEngine.create(config: config);
