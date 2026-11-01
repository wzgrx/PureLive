import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/playback_telemetry.dart';

/// Canonical codec names only; opaque native strings never enter a line label.
String? playbackCodecName(String? value) {
  final text = value?.trim().toLowerCase() ?? '';
  if (RegExp(r'hevc|h[.\-]?265|hvc1|hev1').hasMatch(text)) return 'H.265';
  if (RegExp(r'avc|h[.\-]?264').hasMatch(text)) return 'H.264';
  if (RegExp(r'\bav1\b|av01').hasMatch(text)) return 'AV1';
  if (RegExp(r'\bvp9\b|vp09').hasMatch(text)) return 'VP9';
  if (RegExp(r'\bvp8\b|vp08').hasMatch(text)) return 'VP8';
  return null;
}

/// The same compact annotation in control bars and selection menus.
/// A Raw URL's transcode hint is never treated as its original stream codec.
String playbackLineName(int index, {LivePlayLine? line, String? detectedCodec}) {
  final base = i18n('toolbox_line', args: {'index': '${index + 1}'});
  final raw = line?.lineId?.startsWith('raw|') ?? false;
  final codec = playbackCodecName(detectedCodec) ?? (raw ? null : playbackCodecName(line?.codec));
  final tags = [?codec, if (raw) 'raw'];
  return tags.isEmpty ? base : '$base（${tags.join(', ')}）';
}

/// A choice can identify its CDN without exposing URL paths, signatures or headers.
String playbackLineOrigin(LivePlayLine? line) {
  final url = line == null ? null : Uri.tryParse(line.url);
  if (url == null || !{'http', 'https'}.contains(url.scheme)) return '';
  return RegExp(r'^[a-zA-Z0-9.\-:\[\]]+$').hasMatch(url.host) ? url.host : '';
}

/// One bounded native codec lookup shared by the line views of a session.
/// The room may pass its existing HUD sampler, so native reads are not duplicated.
final class PlaybackLinePresentation extends ChangeNotifier {
  /// Reuses the same weakly associated presentation until the session retires.
  factory of(PlaybackSession session, {PlaybackTelemetry? telemetry}) =>
      _sessions[session] ??= PlaybackLinePresentation._(session, telemetry);
  new _(this.session, PlaybackTelemetry? source)
    : telemetry =
          source ??
          PlaybackTelemetry(
            identity: () => (session.engine, session.state.source, session.state.line, session.input),
            read: () async {
              final engine = session.engine;
              if (engine case final PlaybackStatsSource source) return await source.readStats();
              return null;
            },
          ),
      _ownsTelemetry = source == null {
    _subscription = session.states.listen(_onState, onDone: dispose);
    _identity = _key;
    _status = session.state.status;
  }

  static final Expando<PlaybackLinePresentation> _sessions = Expando();

  /// Native playback owner.
  final PlaybackSession session;

  /// Existing or lazily owned statistics sampler.
  final PlaybackTelemetry telemetry;
  final bool _ownsTelemetry;
  StreamSubscription<PlaybackState>? _subscription;
  Object? _identity;
  PlaybackStatus? _status;
  String? _codec;
  int _samples = 0;
  bool _listening = false;
  bool _closed = false;
  Timer? _deadline;

  Object get _key => (session.engine, session.state.source, session.state.line, session.input);

  /// Detected codec belongs only to the current source and ready video.
  String? get detectedCodec => _identity == _key ? _codec : null;

  /// Metadata of each source, including unresolved recipe placeholders.
  List<LivePlayLine?> get lines => [
    for (final source in session.plan?.sources ?? const <PlaybackSource>[])
      if (source is LineSource) source.line else null,
  ];

  /// Every line label; only the currently decoded line receives native evidence.
  List<String> get labels {
    final metadata = lines;
    return [
      for (var i = 0; i < session.state.lineCount; i++)
        playbackLineName(
          i,
          line: i == session.state.lineIndex
              ? session.state.line ?? (i < metadata.length ? metadata[i] : null)
              : i < metadata.length
              ? metadata[i]
              : null,
          detectedCodec: i == session.state.lineIndex ? detectedCodec : null,
        ),
    ];
  }

  /// A safe current-line fallback while a plan is being replaced.
  String name(int index) {
    final names = labels;
    return index >= 0 && index < names.length ? names[index] : playbackLineName(index);
  }

  /// Public CDN hosts only; owned recipe inputs deliberately have no exported origin.
  List<String> get origins {
    final metadata = lines;
    return [
      for (var i = 0; i < session.state.lineCount; i++) playbackLineOrigin(i < metadata.length ? metadata[i] : null),
    ];
  }

  /// Label for an already resolved choice; callers ensure matching quality.
  String choiceName(int index, LivePlayLine? line) {
    final active = session.state.line;
    final same =
        line != null &&
        active != null &&
        (line.url == active.url || line.lineId != null && line.lineId == active.lineId && line.format == active.format);
    return playbackLineName(index, line: line, detectedCodec: same ? detectedCodec : null);
  }

  @override
  void addListener(VoidCallback listener) {
    final observed = hasListeners;
    super.addListener(listener);
    if (!observed && _codec == null) _samples = 0;
    _start();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _stop();
  }

  void _onState(PlaybackState state) {
    if (_closed) return;
    if (_identity != _key || state.status == PlaybackStatus.opening && _status != PlaybackStatus.opening) {
      _stop();
      _identity = _key;
      _codec = null;
      _samples = 0;
    }
    _status = state.status;
    if ({PlaybackStatus.idle, PlaybackStatus.stopped, PlaybackStatus.error}.contains(state.status)) {
      _stop();
      _codec = null;
    } else {
      _start();
    }
    notifyListeners();
  }

  void _start() {
    final state = session.state;
    if (_closed ||
        _listening ||
        !hasListeners ||
        _codec != null ||
        _samples >= 3 ||
        session.engine is! PlaybackStatsSource ||
        state.videoWidth == null ||
        state.videoHeight == null ||
        !{PlaybackStatus.playing, PlaybackStatus.paused, PlaybackStatus.buffering}.contains(state.status)) {
      return;
    }
    _listening = true;
    _deadline = Timer(const Duration(seconds: 3), () {
      _samples = 3;
      _stop();
    });
    telemetry.addListener(_sample);
    if (telemetry.current != null) unawaited(Future<void>.microtask(_sample));
  }

  void _sample() {
    if (_closed || !_listening || _identity != _key) return;
    final stats = telemetry.current;
    final codec = playbackCodecName(stats?.videoFormat) ?? playbackCodecName(stats?.videoCodec);
    if (codec != null) {
      _codec = codec;
      _stop();
      notifyListeners();
    } else if (++_samples >= 3) {
      _stop();
    }
  }

  void _stop() {
    _deadline?.cancel();
    _deadline = null;
    if (!_listening) return;
    _listening = false;
    telemetry.removeListener(_sample);
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _stop();
    unawaited(_subscription?.cancel());
    if (_ownsTelemetry) telemetry.dispose();
    super.dispose();
  }
}

/// Session and codec changes rebuild the same line controls on every layout.
class PlaybackLineBuilder extends StatelessWidget {
  /// The optional sampler is the room's existing HUD sampler.
  const new({required this.session, required this.builder, this.telemetry, super.key});

  /// The current playback owner.
  final PlaybackSession session;

  /// Optional existing shared sampler.
  final PlaybackTelemetry? telemetry;

  /// Builds controls from current state and verified metadata.
  final Widget Function(BuildContext context, PlaybackState state, PlaybackLinePresentation lines) builder;

  @override
  Widget build(BuildContext context) {
    final lines = PlaybackLinePresentation.of(session, telemetry: telemetry);
    return ListenableBuilder(listenable: lines, builder: (context, _) => builder(context, session.state, lines));
  }
}
