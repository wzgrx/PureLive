import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/shared/rooms/archive/huya_manifest_entry.dart';
import 'package:pure_live/shared/rooms/archive_playback.dart';

/// Bounded local-only positions; media URLs and browser/session data never enter it.
final class HuyaArchiveProgress {
  /// The application meta store is replaceable in tests.
  new({required this.read, required this.write, String idPattern = r'^[1-9][0-9]{0,18}$'})
    : _validId = RegExp(idPattern);

  /// Serialized local metadata.
  final Future<String?> Function() read;

  /// Persists local metadata.
  final Future<void> Function(String) write;
  Future<void> _queue = Future.value();
  final RegExp _validId;

  Future<Map<String, int>> _load() async {
    try {
      final text = await read();
      if (text == null || text.length > 65536) return {};
      final json = jsonDecode(text);
      if (json is! Map) return {};
      return {
        for (final entry in json.entries.take(200))
          if (entry.key is String &&
              _validId.hasMatch(entry.key as String) &&
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

  /// Most recently watched part in a platform-specific namespace.
  Future<({String id, Duration position})?> recent(String prefix) async {
    await _queue;
    final values = await _load();
    final entry = values.entries.where((e) => e.key.startsWith(prefix)).firstOrNull;
    return entry == null ? null : (id: entry.key, position: Duration(milliseconds: entry.value));
  }

  /// Completion resets to zero; writes are serialized and capped at 200 ids.
  Future<void> save(String id, Duration position) {
    if (!_validId.hasMatch(id) || position.isNegative || position.inMilliseconds > 31536000000) {
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
    this.ownsSession = true,
    this.seekTimeout = const Duration(seconds: 10),
    this.initialVolume = 1,
    ProxyPolicy proxy = const FixedProxyPolicy(),
    HuyaManifestEntry? manifestEntry,
  }) {
    _entry = manifestEntry ?? HuyaManifestEntry(proxy: proxy);
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

  /// False when the live-room runtime owns the shared native session.
  final bool ownsSession;

  /// Bounded direct seek and one fresh-URL recovery acknowledgement window.
  final Duration seekTimeout;
  Duration? _failedSeekTarget;
  @override
  List<HuyaArchiveQuality> qualities = const [];
  @override
  String? qualityId;
  @override
  bool busy = false;
  @override
  Object? error;
  @override
  Duration get position => _pending ?? _timelineOffset + session.state.position;

  @override
  Duration get duration => _timelineDuration > Duration.zero ? _timelineDuration : super.duration;

  late final HuyaManifestEntry _entry;
  Duration _timelineOffset = Duration.zero;
  Duration _timelineDuration = Duration.zero;
  bool _usesAnchor = false;

  CancelToken? _cancel;
  StreamSubscription<PlaybackState>? _states;
  Duration? _pending;
  Duration _lastSaved = Duration.zero;
  int _generation = 0;
  Timer? _seekDeadline;
  int _seekSerial = 0;
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
    _seekDeadline?.cancel();
    _failedSeekTarget = null;
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
          plan: await _plan(selected, resume),
          volume: volume,
          refresh: () => _refresh(generation),
        ),
      );
      if (_current(generation)) {
        await restoreRate();
        _ready = true;
        await _entry.retirePrevious(keepCurrent: _usesAnchor);
      }
    } on Object catch (failure) {
      if (_current(generation)) error = failure;
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<PlaybackPlan> _plan(HuyaArchiveQuality quality, Duration at) async {
    final generation = _generation;
    final cancel = _cancel;
    final provider = source;
    final anchor = at > Duration.zero && provider is HuyaArchiveAnchorSource
        ? await (provider as HuyaArchiveAnchorSource).anchor(quality.url, at, cancel: cancel)
        : null;
    if (!_current(generation) || !identical(cancel, _cancel)) throw StateError('Archive replaced');
    final url = anchor == null ? quality.url : await _entry.publish(anchor, quality.url);
    if (!_current(generation)) throw StateError('Archive replaced');
    _timelineOffset = anchor?.offset ?? Duration.zero;
    _timelineDuration = anchor?.duration ?? Duration.zero;
    _usesAnchor = anchor != null;
    return PlaybackPlan(
      sources: [
        LineSource(
          LivePlayLine(url, format: StreamFormat.hls, headers: anchor == null ? HuyaArchiveApi.mediaHeaders : const {}),
        ),
      ],
      onDemand: true,
      start: anchor?.start ?? at,
      appliedQualityData: quality.id,
    );
  }

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
    return await _plan(selected, position);
  }

  @override
  Future<void> selectQuality(String id) async {
    if (busy || _disposed || id == qualityId || qualities.every((q) => q.id != id || !q.playable)) return;
    _seekSerial++;
    _seekDeadline?.cancel();
    final previous = qualityId;
    qualityId = id;
    final generation = _generation;
    final at = position;
    final paused = session.state.status == PlaybackStatus.paused;
    final volume = session.state.volume;
    busy = true;
    error = null;
    _pending = at;
    _ready = false;
    notifyListeners();
    try {
      final plan = await _refresh(generation);
      if (!_current(generation)) return;
      _pending = at;
      await session.open(
        PlaybackRequest(
          site: SiteIds.huya,
          plan: PlaybackPlan(sources: plan.sources, onDemand: true, start: plan.start, appliedQualityData: qualityId),
          volume: volume,
          refresh: () => _refresh(generation),
        ),
      );
      if (_current(generation)) {
        await restoreRate();
        if (paused) await session.pause();
        _ready = true;
        await _entry.retirePrevious(keepCurrent: _usesAnchor);
      }
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
    if (_disposed || !_ready || busy) return;
    final duration = this.duration;
    final bounded = at < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && at > duration
        ? duration
        : at;
    _pending = bounded;
    _failedSeekTarget = null;
    error = null;
    final serial = ++_seekSerial;
    final generation = _generation;
    _seekDeadline?.cancel();
    bool current() => _current(generation) && serial == _seekSerial;
    void recover() {
      if (current() && _pending != null) unawaited(_recoverSeek(bounded, generation, serial));
    }

    _seekDeadline = Timer(seekTimeout, recover);
    notifyListeners();
    if (source is HuyaArchiveAnchorSource) {
      // Native time-pos can acknowledge before decoding at a reset HLS PTS.
      // Re-enter from nearby segments instead of scanning toward an old epoch.
      _seekDeadline?.cancel();
      await _recoverSeek(bounded, generation, serial);
      return;
    }
    try {
      await session.seek(bounded).timeout(seekTimeout);
    } on Object {
      if (current() && _pending != null) {
        _seekDeadline?.cancel();
        await _recoverSeek(bounded, generation, serial);
      }
    }
  }

  Future<void> _recoverSeek(Duration at, int generation, int serial) async {
    bool current() => _current(generation) && serial == _seekSerial;
    if (!current() || busy) return;
    final paused = session.state.status == PlaybackStatus.paused;
    final volume = session.state.volume;
    final audioOnly = session.state.audioOnly;
    busy = true;
    error = null;
    _ready = false;
    notifyListeners();
    try {
      final plan = await _refresh(generation);
      if (!current()) return;
      await session.open(
        PlaybackRequest(
          site: SiteIds.huya,
          plan: PlaybackPlan(sources: plan.sources, onDemand: true, start: plan.start, appliedQualityData: qualityId),
          volume: volume,
          audioOnly: audioOnly,
          refresh: () => _refresh(generation),
        ),
      );
      if (!current()) return;
      await restoreRate();
      if (paused) await session.pause();
      if (!current()) return;
      _ready = true;
      await _entry.retirePrevious(keepCurrent: _usesAnchor);
      if (_pending != null) {
        _seekDeadline = Timer(seekTimeout, () {
          if (!current() || _pending == null) return;
          _pending = null;
          _failedSeekTarget = at;
          error = TimeoutException('Archive seek recovery was not acknowledged');
          notifyListeners();
        });
      }
    } on Object catch (failure) {
      if (current()) {
        _pending = null;
        error = failure;
      }
    } finally {
      if (current()) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void _changed(PlaybackState state) {
    if (_disposed) return;
    final tolerance = Duration(milliseconds: 1000 + (rate * 1000).round());
    final actual = _timelineOffset + state.position;
    bool acknowledged(Duration target) => _usesAnchor
        ? actual >= target - const Duration(milliseconds: 250) && actual <= target + tolerance
        : (actual - target).abs() <= tolerance;
    if (_pending != null && acknowledged(_pending!)) {
      _pending = null;
      _seekDeadline?.cancel();
      error = null;
    }
    if (_failedSeekTarget != null && error is TimeoutException && acknowledged(_failedSeekTarget!)) {
      _failedSeekTarget = null;
      error = null;
    }
    if (_ready &&
        _pending == null &&
        ((position - _lastSaved).inSeconds.abs() >= 5 || state.status == PlaybackStatus.completed)) {
      _lastSaved = position;
      unawaited(record().catchError((Object _) {}));
    }
    notifyListeners();
  }

  @override
  Future<void> record() async {
    if (!_ready ||
        _pending != null ||
        {PlaybackStatus.idle, PlaybackStatus.opening, PlaybackStatus.stopped}.contains(session.state.status)) {
      return;
    }
    await progress.save(video.id, session.state.status == PlaybackStatus.completed ? Duration.zero : position);
  }

  @override
  void dispose() {
    if (_disposed) return;
    final saved = record().catchError((Object _) {});
    _seekDeadline?.cancel();
    _disposed = true;
    _generation++;
    _cancel?.cancel();
    unawaited(_states?.cancel());
    _retirement = Future.wait<void>([if (ownsSession) session.dispose(), saved, _entry.close()]).then((_) {});
    unawaited(_retirement);
    super.dispose();
  }
}
