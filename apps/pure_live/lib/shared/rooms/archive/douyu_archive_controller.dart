import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/shared/rooms/archive/douyu_archive_progress.dart';
import 'package:pure_live/shared/rooms/archive_playback.dart';

/// One on-demand player. Generation guards cover detail, rendition, segment and
/// comment requests. The session retains its normal transport/recovery policy.
final class DouyuVodController extends ArchivePlaybackController {
  /// Owns [session]; [source] and local [progress] remain app-owned.
  new({required this.source, required this.session, required this.progress, this.initialVolume = 1}) {
    _states = session.states.listen(_onState);
  }

  /// Official endpoint wrapper (or deterministic test source).
  final DouyuVodSource source;

  /// The page's native player session.
  @override
  final PlaybackSession session;

  /// Local progress/history.
  final DouyuVodProgressStore progress;

  @override
  bool get supportsDanmaku => true;

  /// Same initial volume as the app's playback preference.
  final double initialVolume;

  DouyuVodDetail? _detail;
  CancelToken? _cancel;
  StreamSubscription<PlaybackState>? _states;
  DouyuVodTimeline? _timeline;
  final StreamController<LiveMessage> _messages = StreamController.broadcast();
  final StreamController<LiveRetraction> _retractions = StreamController.broadcast();
  int _generation = 0;
  bool _disposed = false;
  bool _ready = false;
  Future<void>? _retirement;

  @override
  Future<void> get retirement => _retirement ?? Future.value();
  Duration _lastSaved = Duration.zero;
  Duration? _pendingPosition;

  /// Keeps a requested position until the engine acknowledges the new clock.
  @override
  Duration get position => _pendingPosition ?? session.state.position;

  /// Selected video metadata, available after its detail request.
  @override
  DouyuVodVideo? get video => _detail?.video;

  /// Server-offered renditions, including unavailable permission tiers.
  @override
  List<DouyuVodQuality> qualities = const [];

  /// Actually selected rendition id.
  @override
  String? qualityId;

  /// Ordered segments of this broadcast.
  @override
  List<DouyuVodVideo> segments = const [];

  /// Loading/resolving a video or switching its rendition.
  @override
  bool busy = false;

  /// Failure for the UI to translate; never display signed URLs from it.
  @override
  Object? error;

  /// Whether the optional timeline is shown.
  @override
  bool danmakuVisible = true;

  /// Timeline comments converted to the shared overlay's model.
  @override
  Stream<LiveMessage> get messages => _messages.stream;

  /// Clears the flying layer after a seek/video change.
  @override
  Stream<LiveRetraction> get retractions => _retractions.stream;

  /// Opens metadata, restores local position, then loads the permitted rendition.
  @override
  Future<void> open(String id, {Duration? start}) async {
    final volume = _ready ? session.state.volume : initialVolume;
    await record();
    if (_disposed) return;
    final generation = ++_generation;
    _cancel?.cancel();
    final cancel = _cancel = CancelToken();
    _timeline?.dispose();
    _timeline = null;
    _retractions.add(const LiveRetraction.all());
    _ready = false;
    _pendingPosition = null;
    _detail = null;
    qualities = const [];
    segments = const [];
    qualityId = null;
    busy = true;
    error = null;
    notifyListeners();
    await session.stop();
    try {
      final detail = await source.detail(id, cancel: cancel);
      if (!_current(generation)) return;
      _detail = detail;
      final history = await progress.list();
      if (!_current(generation)) return;
      final saved = history.where((entry) => entry.video.id == id).firstOrNull?.position;
      final requested = start ?? saved ?? Duration.zero;
      final duration = detail.video.duration;
      final resume = requested < Duration.zero || (duration > Duration.zero && requested >= duration)
          ? Duration.zero
          : requested;
      final offered = await source.qualities(detail, cancel: cancel);
      if (!_current(generation)) return;
      qualities = offered;
      final quality = offered.where((item) => item.playable).firstOrNull;
      if (quality == null) throw const StreamUnavailable('douyu', 'No permitted video rendition');
      qualityId = quality.id;
      _lastSaved = resume;
      _pendingPosition = resume > Duration.zero ? resume : null;
      _timeline = DouyuVodTimeline(
        fetch: (position, token) => source.danmaku(id, position, cancel: token),
        clear: () {
          if (!_disposed) _retractions.add(const LiveRetraction.all());
        },
        emit: (message) {
          if (_disposed || !danmakuVisible) return;
          _messages.add(
            LiveMessage(
              type: LiveMessageType.chat,
              userName: '',
              message: message.text,
              messageId: message.id,
              color: LiveMessageColor((message.color >> 16) & 255, (message.color >> 8) & 255, message.color & 255),
            ),
          );
        },
      )..seek(resume);
      await session.open(
        PlaybackRequest(
          site: SiteIds.douyu,
          plan: _plan(quality, resume),
          volume: volume,
          refresh: () => _renew(generation),
        ),
      );
      if (!_current(generation)) return;
      _ready = true;
      unawaited(_loadSegments(detail.video, generation, cancel));
    } on Object catch (failure) {
      if (_current(generation)) error = failure;
    } finally {
      if (_current(generation)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  PlaybackPlan _plan(DouyuVodQuality quality, Duration position) => PlaybackPlan(
    sources: [
      LineSource(
        LivePlayLine(
          quality.url,
          headers: const {'Referer': 'https://v.douyu.com/', 'User-Agent': DouyuVodApi.userAgent},
        ),
      ),
    ],
    onDemand: true,
    start: position,
    appliedQualityData: quality.id,
  );

  Future<PlaybackPlan> _renew(int generation) async {
    final detail = _detail;
    if (!_current(generation) || detail == null) throw StateError('Video replaced');
    // Fetch the descriptor again: a replay can cross the daily signing rollover.
    final fresh = await source.detail(detail.video.id, cancel: _cancel);
    if (!_current(generation)) throw StateError('Video replaced');
    final offered = await source.qualities(fresh, cancel: _cancel);
    if (!_current(generation)) throw StateError('Video replaced');
    final permitted = offered.where((quality) => quality.playable);
    final selected = permitted.where((quality) => quality.id == qualityId).firstOrNull ?? permitted.firstOrNull;
    if (selected == null) throw const StreamUnavailable('douyu', 'No permitted video rendition');
    _detail = fresh;
    qualities = offered;
    qualityId = selected.id;
    notifyListeners();
    return _plan(selected, position);
  }

  Future<void> _loadSegments(DouyuVodVideo video, int generation, CancelToken cancel) async {
    try {
      final values = await source.replaySegments(video, cancel: cancel);
      if (!_current(generation)) return;
      segments = values;
      notifyListeners();
    } on Object {
      /* The video itself remains playable if its companion list fails. */
    }
  }

  /// A rendition change preserves the exact position, volume and pause state.
  @override
  Future<void> selectQuality(String id) async {
    if (_disposed || busy || id == qualityId || !qualities.any((item) => item.id == id && item.playable)) return;
    final generation = _generation;
    final paused = session.state.status == PlaybackStatus.paused;
    final position = this.position;
    final volume = session.state.volume;
    final previous = qualityId;
    qualityId = id;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final plan = await _renew(generation);
      if (!_current(generation)) return;
      // The request position was captured before async renewal, avoiding a jump
      // caused by an opening state resetting the engine's reported position.
      final source = plan.sources.first;
      _pendingPosition = position;
      await session.open(
        PlaybackRequest(
          site: SiteIds.douyu,
          plan: PlaybackPlan(sources: [source], onDemand: true, start: position, appliedQualityData: qualityId),
          volume: volume,
          refresh: () => _renew(generation),
        ),
      );
      if (!_current(generation)) return;
      if (paused) await session.pause();
      _timeline?.seek(position);
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

  /// Seeks the media and comment clocks together.
  @override
  Future<void> seek(Duration position) async {
    if (_disposed || !_ready || busy) return;
    final duration = session.state.duration;
    final target = position < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && position > duration
        ? duration
        : position;
    _pendingPosition = target;
    _timeline?.seek(target);
    await session.seek(target);
    await record();
  }

  /// Hiding also clears the current frame; reenabling starts at the current clock.
  @override
  void toggleDanmaku() {
    danmakuVisible = !danmakuVisible;
    _timeline?.seek(position);
    notifyListeners();
  }

  void _onState(PlaybackState state) {
    if (_disposed) return;
    // Native position/property notifications are asynchronous. An already
    // queued nonzero snapshot from before the seek is not its acknowledgement.
    if (_pendingPosition case final target?
        when state.status == PlaybackStatus.completed ||
            state.status != PlaybackStatus.opening && (state.position - target).abs() <= const Duration(seconds: 2)) {
      _pendingPosition = null;
    }
    if (_ready && !busy) {
      _timeline?.update(position, playing: state.status == PlaybackStatus.playing);
      if ((position - _lastSaved).abs() >= const Duration(seconds: 5) || state.status == PlaybackStatus.completed) {
        _lastSaved = position;
        unawaited(record());
      }
    }
    notifyListeners();
  }

  /// Saves before video replacement or page disposal; transient opening states
  /// must not overwrite an existing position with zero.
  @override
  Future<void> record() async {
    final selected = video;
    if (!_ready || selected == null) return;
    final state = session.state;
    if ({PlaybackStatus.opening, PlaybackStatus.idle, PlaybackStatus.stopped}.contains(state.status)) return;
    await progress.save(selected, position, completed: state.status == PlaybackStatus.completed);
  }

  @override
  void dispose() {
    if (_disposed) return;
    final saved = record().catchError((Object _) {});
    _disposed = true;
    _generation++;
    _cancel?.cancel();
    _timeline?.dispose();
    unawaited(_states?.cancel());
    _retirement = Future.wait<void>([session.dispose(), saved]).then((_) {});
    unawaited(_retirement);
    unawaited(_messages.close());
    unawaited(_retractions.close());
    super.dispose();
  }
}
