import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/shared/rooms/archive/huya_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive_playback.dart';

/// Public SOOP files on the room's existing native session. No live chat is
/// attached to an old recording, and only local part positions are persisted.
final class SoopArchiveController extends ArchivePlaybackController {
  /// The room runtime retains session ownership when [ownsSession] is false.
  new({
    required this.source,
    required this.session,
    required this.recording,
    required this.progress,
    this.initialVolume = 1,
    this.ownsSession = true,
  }) {
    _states = session.states.listen(_changed);
  }

  /// Cancellable resolver on the SOOP HTTP/proxy route.
  final SoopArchiveSource source;
  @override
  final PlaybackSession session;

  /// Parent metadata, without playback credentials.
  final SoopArchiveVideo recording;

  /// Independent bounded local namespace.
  final HuyaArchiveProgress progress;

  /// Initial room preference.
  final double initialVolume;

  /// False for a room-owned native decoder.
  final bool ownsSession;
  @override
  SoopArchivePart? video;
  @override
  List<SoopArchivePart> segments = const [];
  @override
  List<SoopArchiveQuality> qualities = const [];
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
    if (match == null || match[1] != recording.id) throw const NotFound('soop', 'Different recording selected');
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
      final offered = await source.detail(recording.id, cancel: cancel);
      if (!_current(g)) return;
      final recent = match[2] == null ? await progress.recent('${recording.id}:') : null;
      if (!_current(g)) return;
      final partId = match[2] != null ? id : recent?.id;
      final selected = partId == null ? offered.firstOrNull : offered.where((p) => p.id == partId).firstOrNull;
      // Deleted/changed stored parts fall back only for automatic resume.
      final part = selected ?? (match[2] == null ? offered.firstOrNull : null);
      if (part == null) throw const NotFound('soop', 'Recording part removed');
      segments = offered;
      video = part;
      qualities = part.qualities;
      final q = qualities.where((q) => q.id == 'original').firstOrNull ?? qualities.first;
      qualityId = q.id;
      var at = start ?? await progress.position(part.id);
      if (!_current(g)) return;
      if (at.isNegative || part.duration > Duration.zero && at >= part.duration) at = Duration.zero;
      _pending = at > Duration.zero ? at : null;
      _lastSaved = at;
      await session.open(
        PlaybackRequest(site: SiteIds.soop, plan: _plan(q, at), volume: volume, refresh: () => _refresh(g)),
      );
      if (_current(g)) {
        await restoreRate();
        _ready = true;
      }
    } on Object catch (e) {
      if (_current(g)) error = e;
    } finally {
      if (_current(g)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  PlaybackPlan _plan(SoopArchiveQuality q, Duration at) => PlaybackPlan(
    sources: [
      LineSource(
        LivePlayLine(
          q.url,
          headers: SoopArchiveApi.mediaHeaders(recording.id),
          format: Uri.parse(q.url).path.endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.other,
        ),
      ),
    ],
    onDemand: true,
    start: at,
    appliedQualityData: q.id,
  );

  Future<PlaybackPlan> _refresh(int g) async {
    if (!_current(g)) throw StateError('Archive replaced');
    final partId = video?.id;
    final offered = await source.detail(recording.id, cancel: _cancel);
    if (!_current(g)) throw StateError('Archive replaced');
    final part = offered.where((p) => p.id == partId).firstOrNull;
    if (part == null) throw const NotFound('soop', 'Recording part removed');
    final q = part.qualities.where((q) => q.id == qualityId).firstOrNull;
    if (q == null) throw const StreamUnavailable('soop', 'Selected quality no longer available');
    video = part;
    segments = offered;
    qualities = part.qualities;
    notifyListeners();
    return _plan(q, position);
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
    try {
      final plan = await _refresh(g);
      if (!_current(g)) return;
      await session.open(PlaybackRequest(site: SiteIds.soop, plan: plan, volume: volume, refresh: () => _refresh(g)));
      if (_current(g)) {
        if (paused) await session.pause();
        await restoreRate();
        _ready = true;
      }
    } on Object catch (e) {
      if (_current(g)) {
        qualityId = previous;
        error = e;
        _pending = null;
        _ready = true;
      }
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
        {PlaybackStatus.opening, PlaybackStatus.idle, PlaybackStatus.stopped}.contains(session.state.status)) {
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
