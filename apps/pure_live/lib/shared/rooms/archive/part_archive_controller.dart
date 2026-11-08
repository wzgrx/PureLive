import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/shared/rooms/archive/huya_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive_playback.dart';

/// Public replay parts on the room's existing native session. No live chat is
/// attached to an old recording, and only local part positions are persisted.
class PartArchiveController<P extends ArchiveVideo, Q extends ArchiveQuality> extends ArchivePlaybackController {
  /// The room runtime retains session ownership when [ownsSession] is false.
  new({
    required this.site,
    required this.loadParts,
    required this.qualitiesOf,
    required this.lineFor,
    required this.session,
    required this.recordingId,
    required this.progress,
    this.sourcesFor,
    this.initialVolume = 1,
    this.ownsSession = true,
    this.restoreOnQualityFailure = false,
  }) {
    _states = session.states.listen(_changed);
  }

  /// Platform transport namespace.
  final String site;

  /// Cancellable resolver for the currently permitted parts.
  final Future<List<P>> Function(String id, {CancelToken? cancel}) loadParts;

  /// The source's selectable renditions.
  final List<Q> Function(P part) qualitiesOf;

  /// Converts a current rendition into an on-demand input.
  final LivePlayLine Function(Q quality) lineFor;

  /// Optional ordered inputs for the same verified rendition.
  final List<PlaybackSource> Function(Q quality)? sourcesFor;
  @override
  final PlaybackSession session;

  /// Parent metadata, without playback credentials.
  final String recordingId;

  /// Independent bounded local namespace.
  final HuyaArchiveProgress progress;

  /// Initial room preference.
  final double initialVolume;

  /// False for a room-owned native decoder.
  final bool ownsSession;

  /// A variant can resolve but fail to open (for example a signed MP4 on an
  /// unavailable CDN). Keep the preceding playable variant in that case.
  final bool restoreOnQualityFailure;
  @override
  P? video;
  @override
  List<P> segments = const [];
  @override
  List<Q> qualities = const [];
  @override
  String? qualityId;
  @override
  bool busy = false;
  @override
  Object? error;
  @override
  Duration get position => _pending ?? session.state.position;
  bool _disposed = false;
  bool _ready = false;
  int _generation = 0;
  int _seekSerial = 0;
  Duration? _pending;
  Duration _lastSaved = Duration.zero;
  CancelToken? _cancel;
  StreamSubscription<PlaybackState>? _states;
  Timer? _seekDeadline;
  Future<void>? _retirement;
  @override
  Future<void> get retirement => _retirement ?? Future.value();
  bool _current(int g) => !_disposed && g == _generation;

  @override
  Future<void> open(String id, {Duration? start}) async {
    if (_disposed) return;
    final match = RegExp(r'^([1-9][0-9]{0,18})(?::([1-9][0-9]{0,5}))?$').firstMatch(id);
    if (match == null || match[1] != recordingId) throw NotFound(site, 'Different recording selected');
    final volume = _ready ? session.state.volume : initialVolume;
    await record().catchError((Object _) {});
    if (_disposed) return;
    final g = ++_generation;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    _seekSerial++;
    _seekDeadline?.cancel();
    _pending = null;
    busy = true;
    error = null;
    _ready = false;
    notifyListeners();
    try {
      await session.stop();
      final offered = await loadParts(recordingId, cancel: cancel);
      if (!_current(g)) return;
      final recent = match[2] == null ? await progress.recent('$recordingId:') : null;
      if (!_current(g)) return;
      final partId = match[2] != null ? id : recent?.id;
      final selected = partId == null ? offered.firstOrNull : offered.where((p) => p.id == partId).firstOrNull;
      // Deleted/changed stored parts fall back only for automatic resume.
      final part = selected ?? (match[2] == null ? offered.firstOrNull : null);
      if (part == null) throw NotFound(site, 'Recording part removed');
      segments = offered;
      video = part;
      qualities = qualitiesOf(part);
      final q = qualities.where((q) => q.id == 'original').firstOrNull ?? qualities.first;
      qualityId = q.id;
      var at = start ?? await progress.position(part.id);
      if (!_current(g)) return;
      if (at.isNegative || part.duration > Duration.zero && at >= part.duration) at = Duration.zero;
      _pending = at > Duration.zero ? at : null;
      _lastSaved = at;
      final backup = restoreOnQualityFailure
          ? qualities.where((other) => other.playable && other.id != q.id).firstOrNull
          : null;
      if (backup != null) {
        try {
          await _openVariant(g, _plan(q, at), volume, paused: false);
        } on Object {
          if (!_current(g)) return;
          // A new rendition must use a freshly resolved URL. Keep the
          // same part and resume point; one fallback is the entire budget.
          qualityId = backup.id;
          _pending = at > Duration.zero ? at : null;
          final plan = await _refresh(g);
          if (!_current(g)) return;
          await _openVariant(g, plan, volume, paused: false);
        }
      } else {
        await session.open(PlaybackRequest(site: site, plan: _plan(q, at), volume: volume, refresh: () => _refresh(g)));
        if (_current(g)) await restoreRate();
      }
      if (_current(g)) _ready = true;
    } on Object catch (e) {
      if (_current(g)) error = e;
    } finally {
      if (_current(g)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  PlaybackPlan _plan(Q quality, Duration at) => PlaybackPlan(
    sources: sourcesFor?.call(quality) ?? [LineSource(lineFor(quality))],
    onDemand: true,
    start: at,
    appliedQualityData: quality.id,
  );

  Future<PlaybackPlan> _refresh(int g) async {
    if (!_current(g)) throw StateError('Archive replaced');
    final partId = video?.id;
    final offered = await loadParts(recordingId, cancel: _cancel);
    if (!_current(g)) throw StateError('Archive replaced');
    final part = offered.where((p) => p.id == partId).firstOrNull;
    if (part == null) throw NotFound(site, 'Recording part removed');
    final q = qualitiesOf(part).where((q) => q.id == qualityId).firstOrNull;
    if (q == null) throw StreamUnavailable(site, 'Selected quality no longer available');
    video = part;
    segments = offered;
    qualities = qualitiesOf(part);
    notifyListeners();
    return _plan(q, position);
  }

  Future<void> _confirmVariant(int generation, {required bool segmented}) async {
    final result = Completer<PlaybackState?>();
    void observe(PlaybackState state) {
      if (result.isCompleted) return;
      if (const {PlaybackStatus.playing, PlaybackStatus.completed, PlaybackStatus.error}.contains(state.status)) {
        result.complete(state);
      }
    }

    final subscription = session.states.listen(observe);
    final cancel = _cancel;
    try {
      observe(session.state);
      final state =
          await Future.any<PlaybackState?>([
            result.future,
            if (cancel != null) cancel.whenCancelled.then<PlaybackState?>((_) => null),
          ]).timeout(
            segmented
                ? PlaybackSession.segmentedStartupAllowance + const Duration(seconds: 3)
                : const Duration(seconds: 12),
          );
      if (_current(generation) && state?.status == PlaybackStatus.error) {
        final failure = state?.error;
        if (failure is Exception) throw failure;
        if (failure is Error) throw failure;
        throw StreamUnavailable(site, 'The selected replay quality did not open');
      }
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _openVariant(int generation, PlaybackPlan plan, double volume, {required bool paused}) async {
    // Confirm playback before pausing it again, without audible output
    // while replacing an already paused source.
    final muted = restoreOnQualityFailure && paused;
    await session.open(
      PlaybackRequest(site: site, plan: plan, volume: muted ? 0 : volume, refresh: () => _refresh(generation)),
    );
    if (!_current(generation)) return;
    if (restoreOnQualityFailure) {
      await _confirmVariant(
        generation,
        segmented: plan.sources.any((source) => source is LineSource && source.vodPlaylist != null),
      );
    }
    if (!_current(generation)) return;
    if (paused) await session.pause();
    if (!_current(generation)) return;
    if (muted) await session.setVolume(volume);
    if (_current(generation)) await restoreRate();
  }

  @override
  Future<void> selectQuality(String id) async {
    if (_disposed || busy || !_ready || id == qualityId || qualities.every((q) => q.id != id)) return;
    final g = _generation;
    final previous = qualityId;
    final at = position;
    final paused = session.state.status == PlaybackStatus.paused;
    final volume = session.state.volume;
    _seekSerial++;
    _seekDeadline?.cancel();
    _pending = at;
    busy = true;
    error = null;
    _ready = false;
    qualityId = id;
    notifyListeners();
    var replaced = false;
    try {
      final plan = await _refresh(g);
      if (!_current(g)) return;
      replaced = true;
      await _openVariant(g, plan, volume, paused: paused);
      if (_current(g)) _ready = true;
    } on Object catch (e) {
      if (!_current(g)) return;
      qualityId = previous;
      if (restoreOnQualityFailure && replaced && previous != null) {
        try {
          _pending = at;
          final plan = await _refresh(g);
          if (!_current(g)) return;
          await _openVariant(g, plan, volume, paused: paused);
          if (_current(g)) {
            error = null;
            _ready = true;
          }
          return;
        } on Object catch (restoreError) {
          if (!_current(g)) return;
          error = restoreError;
          _pending = null;
          _ready = true;
          return;
        }
      }
      error = e;
      _pending = null;
      _ready = true;
    } finally {
      if (_current(g)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<void> seek(Duration requested) async {
    var target = requested;
    if (_disposed || busy || !_ready) return;
    final end = duration;
    if (target.isNegative) target = Duration.zero;
    if (end > Duration.zero && target > end) target = end;
    final g = _generation;
    final serial = ++_seekSerial;
    _pending = target;
    error = null;
    _seekDeadline?.cancel();
    _seekDeadline = Timer(const Duration(seconds: 10), () {
      if (_current(g) && serial == _seekSerial && _pending != null) {
        _pending = null;
        error = TimeoutException('Archive seek acknowledgement');
        notifyListeners();
      }
    });
    notifyListeners();
    try {
      await session.seek(target).timeout(const Duration(seconds: 10));
    } on Object catch (e) {
      if (_current(g) && serial == _seekSerial) {
        _pending = null;
        error = e;
        notifyListeners();
      }
    }
  }

  void _changed(PlaybackState state) {
    if (_disposed) return;
    if (_pending case final at?
        when state.status == PlaybackStatus.completed ||
            state.status != PlaybackStatus.opening && (state.position - at).abs() <= const Duration(seconds: 2)) {
      _pending = null;
      _seekDeadline?.cancel();
    }
    if (_ready &&
        !busy &&
        ((position - _lastSaved).abs() >= const Duration(seconds: 5) || state.status == PlaybackStatus.completed)) {
      _lastSaved = position;
      unawaited(record().catchError((Object _) {}));
    }
    notifyListeners();
  }

  @override
  Future<void> record() async {
    final part = video;
    if (!_ready ||
        _pending != null ||
        part == null ||
        const {
          PlaybackStatus.opening,
          PlaybackStatus.idle,
          PlaybackStatus.stopped,
          PlaybackStatus.error,
        }.contains(session.state.status)) {
      return;
    }
    await progress.save(part.id, session.state.status == PlaybackStatus.completed ? Duration.zero : position);
  }

  @override
  void dispose() {
    if (_disposed) return;
    final saved = record().catchError((Object _) {});
    _disposed = true;
    _generation++;
    _seekSerial++;
    _seekDeadline?.cancel();
    _cancel?.cancel();
    unawaited(_states?.cancel());
    _retirement = Future.wait<void>([saved, if (ownsSession) session.dispose()]).then((_) {});
    unawaited(_retirement);
    super.dispose();
  }
}
