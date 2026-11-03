import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/shared/rooms/archive/huya_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive_playback.dart';

/// A single native Bilibili part; ids keep per-part local resume positions apart.
final class BilibiliArchivePart implements ArchiveVideo {
  /// Uses public metadata only.
  const new(this.archive, this.part);

  /// Creator-owned video.
  final VodArchive archive;

  /// Native media unit.
  final VodPart part;
  @override
  String get id => '${archive.bvid}:${part.cid}';
  @override
  String get title => archive.playableParts.length > 1 ? '${archive.title} · ${part.title}' : archive.title;
  @override
  Duration get duration => part.duration;
}

/// A permitted, actually returned rendition, without guessing account rights.
final class BilibiliArchiveQuality implements ArchiveQuality {
  /// Wraps a server quality.
  const new(this.quality, {required this.playable});

  /// Actual platform quality metadata.
  final VodQuality quality;
  @override
  final bool playable;
  @override
  String get id => '${quality.qn}';
  @override
  String get label => quality.label;
}

/// Reuses the public VOD media path including DASH external audio and local login.
final class BilibiliArchiveController extends ArchivePlaybackController {
  /// Owns only its playback session, not API/account stores.
  new({
    required this.source,
    required this.session,
    required this.progress,
    this.ownsSession = true,
    this.initialVolume = 1,
  }) {
    _states = session.states.listen(_changed);
  }

  /// Official replay API.
  final BilibiliReplaySource source;
  @override
  final PlaybackSession session;

  /// Local ids and positions only.
  final HuyaArchiveProgress progress;

  /// Shared playback volume preference.
  final double initialVolume;

  /// False when the live-room runtime owns the shared native session.
  final bool ownsSession;
  @override
  BilibiliArchivePart? video;
  @override
  List<BilibiliArchivePart> segments = const [];
  @override
  List<BilibiliArchiveQuality> qualities = const [];
  @override
  String? qualityId;
  @override
  bool busy = false;
  @override
  Object? error;
  @override
  Duration get position => _pending ?? session.state.position;
  VodArchive? _archive;
  ExternalAudio? _audio;
  @override
  bool get requiresExternalAudio => _audio != null;
  StreamSubscription<PlaybackState>? _states;
  Duration? _pending;
  Duration _lastSaved = Duration.zero;
  Timer? _seekDeadline;
  int _seekSerial = 0;
  bool _disposed = false;
  bool _ready = false;
  int _generation = 0;
  Future<void>? _retirement;
  @override
  Future<void> get retirement => _retirement ?? Future.value();
  bool _current(int g) => !_disposed && _generation == g;

  PlaybackPlan _plan(VodStreams streams, int qn, Duration at) {
    final offered = {for (final v in streams.videos) v.id, if (streams.segments.isNotEmpty) streams.quality};
    qualities = [for (final q in streams.qualities) BilibiliArchiveQuality(q, playable: offered.contains(q.qn))];
    if (qualities.isEmpty) {
      qualities = [
        BilibiliArchiveQuality(
          VodQuality(qn: streams.quality, label: VodQuality.labelOf(streams.quality)),
          playable: true,
        ),
      ];
    }
    final rendition = streams.videoFor(qn > 0 ? qn : streams.quality);
    final segment = streams.segments.firstOrNull;
    if (!streams.isDash && streams.segments.length > 1) {
      throw const ApiChanged('bilibili', 'Unsupported multipart durl');
    }
    final lines = streams.isDash
        ? (rendition == null ? <LivePlayLine>[] : streams.linesOf(rendition))
        : (segment == null ? <LivePlayLine>[] : streams.linesOfSegment(segment));
    if (lines.isEmpty) throw const StreamUnavailable('bilibili', 'No permitted replay media');
    final audio = streams.bestAudio();
    _audio = streams.isDash && audio != null ? ExternalAudio(Uri.parse(audio.url)) : null;
    qualityId = '${rendition?.id ?? streams.quality}';
    return PlaybackPlan.of(LivePlayUrlResolution.lines(lines), onDemand: true, start: at);
  }

  @override
  Future<void> open(String id, {Duration? start}) async {
    if (_disposed) return;
    final match = RegExp(r'^(BV[0-9A-Za-z]{10})(?::([1-9][0-9]*))?$').firstMatch(id);
    if (match == null) throw const FormatException('Invalid replay video id');
    await record().catchError((Object _) {});
    if (_disposed) return;
    _seekDeadline?.cancel();
    final g = ++_generation;
    final volume = _ready ? session.state.volume : initialVolume;
    _ready = false;
    busy = true;
    error = null;
    _pending = null;
    notifyListeners();
    try {
      await session.stop();
      final detail = _archive?.bvid == match[1] ? _archive! : await source.detail(match[1]!);
      if (!_current(g)) return;
      if (detail.bvid != match[1]) throw const ApiChanged('bilibili', 'Replay identity changed');
      _archive = detail;
      segments = [
        for (final part in detail.playableParts)
          if (part.cid > 0) BilibiliArchivePart(detail, part),
      ];
      final recent = match[2] == null ? await progress.recent('${detail.bvid}:') : null;
      if (!_current(g)) return;
      final cid = int.tryParse(match[2] ?? recent?.id.split(':').last ?? '');
      final selected = cid == null
          ? segments.firstOrNull
          : segments.where((p) => p.part.cid == cid).firstOrNull ?? (match[2] == null ? segments.firstOrNull : null);
      if (selected == null) throw const NotFound('bilibili', 'Replay part missing');
      video = selected;
      var at = start ?? await progress.position(selected.id);
      if (!_current(g)) return;
      if (at.isNegative || selected.duration > Duration.zero && at >= selected.duration) at = Duration.zero;
      final streams = await source.streams(detail.bvid, selected.part.cid);
      if (!_current(g)) return;
      _pending = at > Duration.zero ? at : null;
      _lastSaved = at;
      final plan = _plan(streams, streams.quality, at);
      await session.open(
        PlaybackRequest(
          site: SiteIds.bilibili,
          plan: plan,
          volume: volume,
          audio: (_) => _audio,
          refresh: () => _refresh(g),
        ),
      );
      if (!_current(g)) return;
      await restoreRate();
      _ready = true;
    } on Object catch (e) {
      if (_current(g)) error = e;
    } finally {
      if (_current(g)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<PlaybackPlan> _refresh(int g) async {
    final selected = video!;
    final qn = int.tryParse(qualityId ?? '') ?? 0;
    final streams = await source.streams(selected.archive.bvid, selected.part.cid, qn: qn);
    if (!_current(g)) throw StateError('Replay replaced');
    return _plan(streams, qn, position);
  }

  @override
  Future<void> selectQuality(String id) async {
    if (_disposed || busy || id == qualityId || !qualities.any((q) => q.id == id && q.playable)) return;
    _seekSerial++;
    _seekDeadline?.cancel();
    final g = _generation;
    final previous = qualityId;
    final at = position;
    final paused = session.state.status == PlaybackStatus.paused;
    final volume = session.state.volume;
    busy = true;
    error = null;
    qualityId = id;
    notifyListeners();
    try {
      final plan = await _refresh(g);
      if (!_current(g)) return;
      _pending = at;
      await session.open(
        PlaybackRequest(
          site: SiteIds.bilibili,
          plan: plan,
          volume: volume,
          audio: (_) => _audio,
          refresh: () => _refresh(g),
        ),
      );
      if (!_current(g)) return;
      await restoreRate();
      if (paused) await session.pause();
    } on Object catch (e) {
      if (_current(g)) {
        qualityId = previous;
        error = e;
      }
    } finally {
      if (_current(g)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<void> seek(Duration at) async {
    if (_disposed || !_ready || busy) return;
    final duration = session.state.duration > Duration.zero ? session.state.duration : video!.duration;
    final bounded = at < Duration.zero
        ? Duration.zero
        : duration > Duration.zero && at > duration
        ? duration
        : at;
    _pending = bounded;
    notifyListeners();
    final serial = ++_seekSerial;
    final generation = _generation;
    _seekDeadline?.cancel();
    bool current() => _current(generation) && serial == _seekSerial;
    _seekDeadline = Timer(const Duration(seconds: 10), () {
      if (!current() || _pending == null) return;
      _pending = null;
      error = TimeoutException('Archive seek was not acknowledged');
      notifyListeners();
    });
    try {
      await session.seek(bounded).timeout(const Duration(seconds: 10));
    } on Object catch (failure) {
      if (current()) {
        _pending = null;
        error = failure;
        notifyListeners();
      }
    }
  }

  void _changed(PlaybackState state) {
    if (_disposed) return;
    if (_pending != null && (state.position - _pending!).abs() < const Duration(seconds: 1)) _pending = null;
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
    if (!_ready ||
        video == null ||
        {PlaybackStatus.idle, PlaybackStatus.opening, PlaybackStatus.stopped}.contains(session.state.status)) {
      return;
    }
    await progress.save(video!.id, session.state.status == PlaybackStatus.completed ? Duration.zero : position);
  }

  @override
  void dispose() {
    if (_disposed) return;
    final saved = record().catchError((Object _) {});
    _seekDeadline?.cancel();
    _disposed = true;
    _generation++;
    unawaited(_states?.cancel());
    _retirement = Future.wait<void>([if (ownsSession) session.dispose(), saved]).then((_) {});
    unawaited(_retirement);
    super.dispose();
  }
}
