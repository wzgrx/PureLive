import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/shared/rooms/archive_playback.dart';

/// Bounded local-only positions; media URLs and browser/session data never enter it.
final class HuyaArchiveProgress {
  /// The application meta store is replaceable in tests.
  new({required this.read, required this.write});

  /// Serialized local metadata.
  final Future<String?> Function() read;

  /// Persists local metadata.
  final Future<void> Function(String) write;
  Future<void> _queue = Future.value();

  Future<Map<String, int>> _load() async {
    try {
      final text = await read();
      if (text == null || text.length > 65536) return {};
      final json = jsonDecode(text);
      if (json is! Map) return {};
      return {
        for (final entry in json.entries.take(200))
          if (entry.key is String &&
              RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(entry.key as String) &&
              entry.value is int &&
              (entry.value as int) >= 0 &&
              (entry.value as int) <= 31536000000)
            entry.key as String: entry.value as int,
      };
    } on Object {
      return {};
    }
  }

  /// A previously stored position after preceding writes complete.
  Future<Duration> position(String id) async {
    await _queue;
    return Duration(milliseconds: (await _load())[id] ?? 0);
  }

  /// Completion resets to zero; writes are serialized and capped at 200 ids.
  Future<void> save(String id, Duration position) {
    if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(id) || position.isNegative || position.inMilliseconds > 31536000000) {
      return Future.value();
    }
    return _queue = _queue.catchError((Object _) {}).then((_) async {
      final values = await _load();
      final next = {id: position.inMilliseconds, ...values..remove(id)};
      await write(jsonEncode(Map.fromEntries(next.entries.take(200))));
    });
  }
}

/// One official Huya recording, independent of the streamer's current live room.
final class HuyaArchiveController extends ArchivePlaybackController {
  /// Owns [session], not the app's API source or progress store.
  new({
    required this.source,
    required this.session,
    required this.video,
    required this.progress,
    this.initialVolume = 1,
  }) {
    _states = session.states.listen(_changed);
  }

  /// Official, cancellable archive API.
  final HuyaArchiveSource source;
  @override
  final PlaybackSession session;
  @override
  final HuyaArchiveVideo video;

  /// Local progress store with no media credentials.
  final HuyaArchiveProgress progress;

  /// Initial preference shared with normal playback.
  final double initialVolume;
  @override
  List<HuyaArchiveQuality> qualities = const [];
  @override
  String? qualityId;
  @override
  bool busy = false;
  @override
  Object? error;
  @override
  Duration get position => _pending ?? session.state.position;

  CancelToken? _cancel;
  StreamSubscription<PlaybackState>? _states;
  Duration? _pending;
  Duration _lastSaved = Duration.zero;
  int _generation = 0;
  bool _disposed = false;
  bool _ready = false;
  Future<void>? _retirement;

  @override
  Future<void> get retirement => _retirement ?? Future.value();

  bool _current(int generation) => !_disposed && generation == _generation;

  @override
  Future<void> open(String id, {Duration? start}) async {
    if (_disposed) return;
    if (id != video.id) throw const NotFound('huya', 'Different archive selected');
    final volume = _ready ? session.state.volume : initialVolume;
    await record().catchError((Object _) {});
    if (_disposed) return;
    final generation = ++_generation;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    busy = true;
    error = null;
    _ready = false;
    _pending = null;
    notifyListeners();
    try {
      await session.stop();
      final offered = await source.qualities(id, cancel: cancel);
      if (!_current(generation)) return;
      final selected = offered.where((q) => q.playable).firstOrNull;
      if (selected == null) throw const StreamUnavailable('huya', 'No permitted archive rendition');
      var resume = start ?? await progress.position(id);
      if (!_current(generation)) return;
      if (resume.isNegative || (video.duration > Duration.zero && resume >= video.duration)) resume = Duration.zero;
      qualities = offered;
      qualityId = selected.id;
      _pending = resume > Duration.zero ? resume : null;
      _lastSaved = resume;
      await session.open(
        PlaybackRequest(
          site: SiteIds.huya,
          plan: _plan(selected, resume),
          volume: volume,
          refresh: () => _refresh(generation),
        ),
      );
      if (_current(generation)) _ready = true;
    } on Object catch (failure) {
      if (_current(generation)) error = failure;
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  PlaybackPlan _plan(HuyaArchiveQuality quality, Duration at) => PlaybackPlan(
    sources: [LineSource(LivePlayLine(quality.url, format: StreamFormat.hls, headers: HuyaArchiveApi.mediaHeaders))],
    onDemand: true,
    start: at,
    appliedQualityData: quality.id,
  );

  Future<PlaybackPlan> _refresh(int generation) async {
    final offered = await source.qualities(video.id, cancel: _cancel);
    if (!_current(generation)) throw StateError('Archive replaced');
    final selected =
        offered.where((q) => q.playable && q.id == qualityId).firstOrNull ??
        offered.where((q) => q.playable).firstOrNull;
    if (selected == null) throw const StreamUnavailable('huya', 'Archive rendition expired');
    qualities = offered;
    qualityId = selected.id;
    notifyListeners();
    return _plan(selected, position);
  }

  @override
  Future<void> selectQuality(String id) async {
    if (busy || _disposed || id == qualityId || qualities.every((q) => q.id != id || !q.playable)) return;
    final previous = qualityId;
    qualityId = id;
    final generation = _generation;
    final at = position;
    final paused = session.state.status == PlaybackStatus.paused;
    final volume = session.state.volume;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final plan = await _refresh(generation);
      if (!_current(generation)) return;
      _pending = at;
      await session.open(
        PlaybackRequest(
          site: SiteIds.huya,
          plan: PlaybackPlan(sources: plan.sources, onDemand: true, start: at, appliedQualityData: qualityId),
          volume: volume,
          refresh: () => _refresh(generation),
        ),
      );
      if (_current(generation) && paused) await session.pause();
    } on Object catch (failure) {
      if (_current(generation)) {
        qualityId = previous;
        error = failure;
      }
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<void> seek(Duration at) async {
    if (_disposed || !_ready) return;
    final duration = session.state.duration > Duration.zero ? session.state.duration : video.duration;
    final bounded = at < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && at > duration
        ? duration
        : at;
    _pending = bounded;
    notifyListeners();
    await session.seek(bounded);
  }

  void _changed(PlaybackState state) {
    if (_disposed) return;
    if (_pending != null && (state.position - _pending!).inMilliseconds.abs() < 1000) _pending = null;
    if (_ready && ((position - _lastSaved).inSeconds.abs() >= 5 || state.status == PlaybackStatus.completed)) {
      _lastSaved = position;
      unawaited(record().catchError((Object _) {}));
    }
    notifyListeners();
  }

  @override
  Future<void> record() async {
    if (!_ready ||
        {PlaybackStatus.idle, PlaybackStatus.opening, PlaybackStatus.stopped}.contains(session.state.status)) {
      return;
    }
    await progress.save(video.id, session.state.status == PlaybackStatus.completed ? Duration.zero : position);
  }

  @override
  void dispose() {
    if (_disposed) return;
    final saved = record().catchError((Object _) {});
    _disposed = true;
    _generation++;
    _cancel?.cancel();
    unawaited(_states?.cancel());
    _retirement = Future.wait<void>([session.dispose(), saved]).then((_) {});
    unawaited(_retirement);
    super.dispose();
  }
}
