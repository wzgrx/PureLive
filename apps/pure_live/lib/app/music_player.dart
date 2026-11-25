import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_vod/live_vod.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/music_catalog.dart';
import 'package:pure_live/app/music_library.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The audio cache's directory on `dart:io` (live_vod `AudioCacheFiles`).
final class MusicCacheFiles implements AudioCacheFiles {
  /// Creates the files of [directory] (made on first write).
  new(this.directory);

  /// The directory.
  final Directory directory;

  /// The path of [name].
  String pathOf(String name) => p.join(directory.path, name);

  @override
  Future<List<CachedFile>> list() async {
    if (!directory.existsSync()) return const [];
    return [
      for (final entity in directory.listSync())
        if (entity is File)
          (name: p.basename(entity.path), size: entity.lengthSync(), modified: entity.lastModifiedSync()),
    ];
  }

  @override
  Future<int?> sizeOf(String name) async {
    final file = File(pathOf(name));
    return file.existsSync() ? file.lengthSync() : null;
  }

  @override
  Future<void> rename(String from, String to) async {
    await File(pathOf(from)).rename(pathOf(to));
  }

  @override
  Future<void> delete(String name) async {
    final file = File(pathOf(name));
    if (file.existsSync()) await file.delete();
  }
}

/// What the system media notification shows of music (Android; a no-op
/// elsewhere and in tests).
abstract interface class MusicNotification {
  /// Shows [track] with the player's commands.
  Future<void> show(MusicTrack track, MusicPlayer player);

  /// Shows the playing state.
  void update({required bool playing, required bool buffering, required Duration position});

  /// Removes the notification.
  Future<void> hide();
}

/// The notification through the app's audio_service handler (the live
/// room's, M13.14), with the queue's buttons.
final class SystemMusicNotification implements MusicNotification {
  @override
  Future<void> show(MusicTrack track, MusicPlayer player) => RoomMediaNotification.showTrack(
    owner: this,
    id: track.id,
    title: track.title,
    artist: track.archive.owner.name,
    cover: track.archive.cover,
    duration: track.part.duration > Duration.zero ? track.part.duration : track.archive.duration,
    play: player.resume,
    pause: player.pause,
    stop: player.pause,
    next: player.next,
    previous: player.previous,
    seek: player.seek,
  );

  @override
  void update({required bool playing, required bool buffering, required Duration position}) =>
      RoomMediaNotification.updateTrack(owner: this, playing: playing, buffering: buffering, position: position);

  @override
  Future<void> hide() => RoomMediaNotification.hide(this);
}

/// The music player of the TV interface (pure_live_TV `b9d2f739`
/// `MusicPlayerController`), on live_player's `PlaybackSession` and
/// live_vod's queue, cache and stream rules.
///
/// - One session for the whole queue; each track opens as an on-demand plan
///   (its end is `completed`, it seeks). Audio only plays the best DASH
///   audio (Hi-Res when asked), from the cache when it was heard before;
///   with the picture on it plays the muxed MP4.
/// - The queue (`PlayQueue`): sequence wraps, repeat-one replays on its own
///   end (manual next still moves), shuffle walks a shuffled order;
///   failures move on until min(length, 5) failed in a row.
/// - It outlives the pages: leaving the music pages keeps playing. A live
///   room or a video taking the speakers calls [yieldToOtherPlayback]: the
///   stream stops, the queue and the position stay.
/// - The remote's media keys (play/pause, next, previous, fast-forward,
///   rewind) work on every page while music owns the speakers; the system
///   notification has the same buttons.
/// - The queue, the track and the position are saved every 10 s while
///   playing and on pause, so [resumeLastSession] can pick up after a
///   restart (the "resume on open" setting).
class MusicPlayer extends ChangeNotifier {
  /// Creates the player.
  new({
    required this.catalog,
    required this.library,
    required this.settings,
    required PlaybackSession Function() session,
    this.cacheDirectory,
    this.notification,
    this.onMessage,
  }) : _newSession = session {
    _queue.mode = _modeOf(settings.get(Settings.musicPlayMode));
    _audioOnly = settings.get(Settings.musicAudioOnly);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// The network.
  final MusicCatalog catalog;

  /// The library (recent plays, the saved session).
  final MusicLibrary library;

  /// The music settings.
  final SettingsStore settings;

  /// Where cached audio goes; null turns the cache off.
  final Directory? cacheDirectory;

  /// The system notification, if any.
  final MusicNotification? notification;

  /// Shows a short message (a failed track).
  final void Function(String key)? onMessage;

  final PlaybackSession Function() _newSession;
  final PlayQueue<MusicTrack> _queue = PlayQueue<MusicTrack>(idOf: (track) => track.id);
  final Map<String, MusicTrack> _resolved = {};
  PlaybackSession? _session;
  StreamSubscription<PlaybackState>? _states;
  bool _audioOnly = true;
  bool _resolving = false;
  Object? _error;
  bool _yielded = false;
  bool _opened = false;
  bool _disposed = false;
  bool _fromCache = false;
  int _generation = 0;
  Timer? _heartbeat;
  Future<AudioCache?>? _cacheLoading;
  bool _resumeTried = false;
  DateTime _seekAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _seekStep = 10;

  /// The playback snapshot (position and duration change many times a
  /// second; only the progress and the lyrics listen to it).
  final ValueNotifier<PlaybackState> playback = ValueNotifier(const PlaybackState());

  /// Where the saved session is kept.
  static const String sessionKey = 'music.session';

  /// How often the position is saved while playing.
  static const Duration heartbeat = Duration(seconds: 10);

  /// "Previous" further into a track than this restarts it instead.
  static const Duration restartThreshold = Duration(seconds: 5);

  // State ---------------------------------------------------------------------

  /// The queue in list order (resolved tracks where known).
  List<MusicTrack> get tracks => [for (final track in _queue.items) _resolved[track.id] ?? track];

  /// The current track's place, -1 when none.
  int get index => _queue.index;

  /// The current track.
  MusicTrack? get current {
    final track = _queue.current;
    return track == null ? null : _resolved[track.id] ?? track;
  }

  /// Whether there is a queue.
  bool get hasQueue => _queue.isNotEmpty;

  /// How the queue moves on.
  PlayMode get mode => _queue.mode;

  /// Audio only (cover and lyrics) or with the picture.
  bool get audioOnly => _audioOnly;

  /// A track's stream is being looked up.
  bool get resolving => _resolving;

  /// The last failure of the current track, if any.
  Object? get error => _error;

  /// Whether the current track came from the audio cache.
  bool get fromCache => _fromCache;

  /// The session (the video view draws its picture); null before the first
  /// track.
  PlaybackSession? get session => _session;

  /// Whether music is playing or about to.
  bool get isPlaying => playback.value.isActive;

  /// Whether another player took the speakers since music last played.
  bool get yielded => _yielded;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  static PlayMode _modeOf(String name) => PlayMode.values.where((mode) => mode.name == name).firstOrNull ?? .sequence;

  // Queue ---------------------------------------------------------------------

  /// Replaces the queue with [tracks] and plays [start].
  Future<void> play(List<MusicTrack> tracks, {int start = 0}) async {
    if (tracks.isEmpty) return;
    _queue.replace(tracks, start: start);
    // The same song twice in [tracks] is queued once: start on its place.
    final wanted = tracks[start.clamp(0, tracks.length - 1)].id;
    _queue.jumpTo(_queue.items.indexWhere((track) => track.id == wanted));
    _changed();
    await _openCurrent();
  }

  /// Puts [track] right after the current one (starts it when nothing is
  /// queued).
  Future<PlayNextResult> playNext(MusicTrack track) async {
    final result = _queue.playNext(track);
    _changed();
    if (result == PlayNextResult.started) await _openCurrent();
    return result;
  }

  /// Adds [track] at the end; false when it is queued already.
  Future<bool> enqueue(MusicTrack track) async {
    final wasEmpty = !_queue.isNotEmpty;
    final added = _queue.enqueue(track);
    _changed();
    if (added && wasEmpty) await _openCurrent();
    return added;
  }

  /// Removes the song at [position]; removing the current one plays the
  /// next.
  Future<void> removeAt(int position) async {
    final wasCurrent = _queue.removeAt(position);
    _changed();
    if (!wasCurrent) return;
    if (_queue.isNotEmpty) {
      await _openCurrent();
    } else {
      await stop();
    }
  }

  /// Moves the song at [from] to [to].
  void move(int from, int to) {
    _queue.move(from, to);
    _changed();
  }

  /// Plays the song at [position].
  Future<void> jumpTo(int position) async {
    if (!_queue.jumpTo(position)) return;
    _changed();
    await _openCurrent();
  }

  /// The next song (always moves, even in repeat-one).
  Future<void> next() async {
    if (_queue.next() == null) return;
    _changed();
    await _openCurrent();
  }

  /// The previous song, or the start of this one when it is more than
  /// [restartThreshold] in (the music-player convention).
  Future<void> previous() async {
    final session = _session;
    if (session != null && !_yielded && playback.value.position > restartThreshold) {
      await seek(Duration.zero);
      if (!playback.value.isActive) await session.resume();
      return;
    }
    if (_queue.previous() == null) return;
    _changed();
    await _openCurrent();
  }

  /// Sets how the queue moves on (and remembers it).
  Future<void> setMode(PlayMode mode) async {
    _queue.mode = mode;
    _changed();
    await settings.set(Settings.musicPlayMode, mode.name);
  }

  /// The next mode: sequence → repeat-one → shuffle.
  Future<void> cycleMode() => setMode(_queue.mode.next);

  /// Empties the queue and stops.
  Future<void> stop() async {
    _generation++;
    _queue.replace(const []);
    _resolved.clear();
    _resolving = false;
    _error = null;
    _opened = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _session?.stop();
    await notification?.hide();
    unawaited(BackgroundKeepAlive.set(enabled: false));
    await library.store.remove(sessionKey);
    _changed();
  }

  // Transport -----------------------------------------------------------------

  /// Plays or pauses; after a stop or a yield it reopens the current song
  /// where it was.
  Future<void> togglePlayPause() => playback.value.isActive && !_yielded ? pause() : resume();

  /// Resumes (reopens the current song where it was when the stream is
  /// gone).
  Future<void> resume() async {
    final session = _session;
    final status = playback.value.status;
    if (session == null || _yielded || !_opened || status == .stopped || status == .error || status == .idle) {
      if (_queue.current != null) await _openCurrent(start: _yielded || _opened ? playback.value.position : null);
      return;
    }
    if (status == .completed) {
      await session.seek(Duration.zero);
      return;
    }
    await session.resume();
  }

  /// Pauses (and saves where).
  Future<void> pause() async {
    await _session?.pause();
    await _saveSession();
  }

  /// Seeks within the current song.
  Future<void> seek(Duration position) async {
    final session = _session;
    if (session == null || _yielded) return;
    final duration = playback.value.duration;
    var target = position.isNegative ? Duration.zero : position;
    if (duration > Duration.zero && target > duration) target = duration;
    playback.value = playback.value.copyWith(position: target);
    await session.seek(target);
  }

  /// Seeks [seconds] forward (negative: back).
  Future<void> seekBy(int seconds) => seek(playback.value.position + Duration(seconds: seconds));

  /// Seeks with pure_live_TV's press acceleration: presses within 200 ms
  /// grow the step from 10 s by 5 s up to 60 s (a held arrow walks fast).
  Future<void> seekAccelerated(int direction, {DateTime? now}) {
    final at = now ?? DateTime.now();
    _seekStep = at.difference(_seekAt) < const Duration(milliseconds: 200) ? (_seekStep + 5).clamp(10, 60) : 10;
    _seekAt = at;
    return seekBy(direction * _seekStep);
  }

  /// Switches between audio only and the picture (and remembers it); the
  /// song reopens where it was.
  Future<void> setAudioOnly({required bool enabled}) async {
    if (enabled == _audioOnly) return;
    _audioOnly = enabled;
    _changed();
    await settings.set(Settings.musicAudioOnly, enabled);
    if (_queue.current != null && _opened && !_yielded) await _openCurrent(start: playback.value.position);
  }

  /// Another player (a live room, a video) takes the speakers: the stream
  /// stops, the queue and the position stay (pure_live_TV `pauseForLive`).
  Future<void> yieldToOtherPlayback() async {
    if (_yielded || !_queue.isNotEmpty) return;
    await _saveSession();
    _generation++;
    _yielded = true;
    _resolving = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _session?.stop();
    await notification?.hide();
    unawaited(BackgroundKeepAlive.set(enabled: false));
    _changed();
  }

  // Opening -------------------------------------------------------------------

  PlaybackSession _sessionNow() {
    final existing = _session;
    if (existing != null) return existing;
    final session = _session = _newSession();
    _states = session.states.listen(_onState);
    return session;
  }

  Future<void> _openCurrent({Duration? start}) async {
    final track = _queue.current;
    if (track == null) return;
    final generation = ++_generation;
    _yielded = false;
    _resolving = true;
    _error = null;
    _fromCache = false;
    _changed();
    try {
      await library.ready();
      final known = _resolved[track.id] ?? track;
      final lossless = settings.get(Settings.musicLossless);
      MusicStream? stream;
      String? cached;
      if (_audioOnly && known.part.cid > 0) {
        final cache = await _cacheNow();
        final file = cache?.lookup(AudioCacheKey.of(bvid: known.archive.bvid, cid: known.part.cid, lossless: lossless));
        if (file != null) cached = MusicCacheFiles(cacheDirectory!).pathOf(file);
      }
      if (cached == null) {
        stream = await catalog.stream(known, audioOnly: _audioOnly, lossless: lossless);
        if (generation != _generation) return;
        _resolved[track.id] = stream.track;
      }
      final resolved = _resolved[track.id] ?? known;
      final lines = cached != null ? [LivePlayLine(Uri.file(cached).toString())] : stream!.lines;
      final session = _sessionNow();
      _opened = false;
      await session.open(
        PlaybackRequest(
          site: vodSite,
          plan: PlaybackPlan(
            sources: [for (final line in lines) LineSource(line)],
            onDemand: true,
            start: start != null && start > Duration.zero ? start : null,
          ),
          audioOnly: _audioOnly,
        ),
      );
      if (generation != _generation) return;
      if (session.state.status == PlaybackStatus.error) {
        // Every line failed while opening (errors are states, not throws).
        _failed(session.state.error ?? 'open failed');
        return;
      }
      _opened = true;
      _fromCache = cached != null;
      _queue.opened();
      _resolving = false;
      _changed();
      unawaited(library.recordPlay(resolved));
      unawaited(catalog.reportPlay(resolved).catchError((Object _) {}));
      unawaited(notification?.show(resolved, this));
      unawaited(_saveSession());
      _heartbeat ??= Timer.periodic(heartbeat, (_) {
        if (playback.value.isActive) unawaited(_saveSession());
      });
      if (stream?.audio case final audio?) unawaited(_download(resolved, audio, stream!.headers, lossless: lossless));
    } on Object catch (error, stackTrace) {
      if (generation != _generation) return;
      developer.log('Track failed: ${track.id}', name: 'Music', error: error, stackTrace: stackTrace);
      _failed(error);
    }
  }

  void _failed(Object error) {
    _resolving = false;
    _error = error;
    _changed();
    onMessage?.call('tv_music_play_failed');
    final next = _queue.failed();
    if (next == null) {
      // Every recent try failed: stop moving (a dead network must not spin
      // the queue), keep the queue.
      _generation++;
      unawaited(_session?.stop());
      return;
    }
    _changed();
    unawaited(_openCurrent());
  }

  void _onState(PlaybackState state) {
    final before = playback.value;
    playback.value = state;
    if (_yielded) return;
    if (before.isActive != state.isActive || before.status != state.status) {
      notification?.update(
        playing: state.isActive,
        buffering: state.status == PlaybackStatus.buffering,
        position: state.position,
      );
      unawaited(BackgroundKeepAlive.set(enabled: state.isActive));
      _changed();
    }
    // While a track is looked up or opening, the states belong to the
    // previous one or to the open itself (checked when it returns).
    if (before.status == state.status || _resolving || !_opened) return;
    switch (state.status) {
      case PlaybackStatus.completed:
        unawaited(_onCompleted());
      case PlaybackStatus.error:
        _failed(state.error ?? 'playback error');
      case _:
        break;
    }
  }

  Future<void> _onCompleted() async {
    if (_queue.mode == PlayMode.repeatOne) {
      await _session?.seek(Duration.zero);
      return;
    }
    if (_queue.next(auto: true) == null) {
      _changed();
      return;
    }
    _changed();
    await _openCurrent();
  }

  // Remote media keys -----------------------------------------------------------

  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent || !_queue.isNotEmpty || _yielded) return false;
    final key = event.logicalKey;
    if (event is KeyRepeatEvent &&
        key != LogicalKeyboardKey.mediaFastForward &&
        key != LogicalKeyboardKey.mediaRewind) {
      return key == LogicalKeyboardKey.mediaPlayPause;
    }
    switch (key) {
      case LogicalKeyboardKey.mediaPlayPause:
        unawaited(togglePlayPause());
      case LogicalKeyboardKey.mediaPlay:
        unawaited(resume());
      case LogicalKeyboardKey.mediaPause || LogicalKeyboardKey.mediaStop:
        unawaited(pause());
      case LogicalKeyboardKey.mediaTrackNext:
        unawaited(next());
      case LogicalKeyboardKey.mediaTrackPrevious:
        unawaited(previous());
      case LogicalKeyboardKey.mediaFastForward:
        unawaited(seekAccelerated(1));
      case LogicalKeyboardKey.mediaRewind:
        unawaited(seekAccelerated(-1));
      default:
        return false;
    }
    return true;
  }

  // Audio cache -------------------------------------------------------------------

  Future<AudioCache?> _cacheNow() {
    final directory = cacheDirectory;
    final limit = settings.get(Settings.musicCacheLimitMb);
    if (directory == null || limit <= 0) return Future.value();
    return _cacheLoading ??= () async {
      try {
        final cache = AudioCache(MusicCacheFiles(directory), maxBytes: limit * 1024 * 1024);
        await cache.load();
        return cache;
      } on Object catch (error) {
        developer.log('Audio cache unavailable', name: 'Music', error: error);
        return null;
      }
    }();
  }

  /// What the cache holds, for the settings (null when it is off).
  Future<AudioCacheUsage?> cacheUsage() async => (await _cacheNow())?.usage;

  /// Empties the audio cache.
  Future<void> clearCache() async {
    await (await _cacheNow())?.clear();
  }

  /// Downloads [audio] of [track] into the cache while it plays (the cache
  /// keeps it under the limit, least recently played out first).
  Future<void> _download(
    MusicTrack track,
    VodRendition audio,
    Map<String, String> headers, {
    required bool lossless,
  }) async {
    final cache = await _cacheNow();
    if (cache == null || track.part.cid <= 0) return;
    cache.maxBytes = settings.get(Settings.musicCacheLimitMb) * 1024 * 1024;
    final key = AudioCacheKey.of(bvid: track.archive.bvid, cid: track.part.cid, lossless: lossless);
    final part = cache.begin(key);
    if (part == null) return;
    final files = MusicCacheFiles(cacheDirectory!);
    try {
      await cacheDirectory!.create(recursive: true);
      final response = await catalog.download(audio.url, headers);
      if (!response.isSuccess) throw HttpException('HTTP ${response.status}');
      final sink = File(files.pathOf(part)).openWrite();
      try {
        await sink.addStream(response.body);
      } finally {
        await sink.close();
      }
      await cache.commit(key, keep: {key});
    } on Object catch (error) {
      developer.log('Cache download failed: ${track.id}', name: 'Music', error: error);
      await cache.abort(key);
    }
  }

  // The saved session ---------------------------------------------------------------

  Future<void> _saveSession() async {
    if (!_queue.isNotEmpty || _disposed) return;
    try {
      await library.store.writeJson(sessionKey, {
        'tracks': [for (final track in tracks) track.toJson()],
        'index': _queue.index,
        'positionMs': playback.value.position.inMilliseconds,
      });
    } on Object catch (error) {
      developer.log('Session save failed', name: 'Music', error: error);
    }
  }

  /// Restores the last queue and position once per run when the "resume on
  /// open" setting is on and nothing is queued.
  Future<void> resumeLastSession() async {
    if (_resumeTried) return;
    _resumeTried = true;
    if (!settings.get(Settings.musicResumeOnOpen) || _queue.isNotEmpty) return;
    await library.ready();
    final saved = library.store.readJson(sessionKey);
    if (saved is! Map<String, Object?>) return;
    final list = saved['tracks'];
    final tracks = [
      if (list is List<Object?>)
        for (final item in list.whereType<Map<String, Object?>>()) MusicTrack.fromJson(item),
    ].where((track) => track.archive.bvid.isNotEmpty).toList();
    if (tracks.isEmpty || _queue.isNotEmpty) return;
    _queue.replace(tracks, start: jsonInt(saved['index']) ?? 0);
    _changed();
    await _openCurrent(start: Duration(milliseconds: jsonInt(saved['positionMs']) ?? 0));
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    HardwareKeyboard.instance.removeHandler(_onKey);
    _heartbeat?.cancel();
    unawaited(_states?.cancel());
    unawaited(_session?.dispose());
    unawaited(notification?.hide());
    playback.dispose();
    super.dispose();
  }
}

/// The music player (M14.4), alive for the whole run.
final Provider<MusicPlayer> musicPlayerProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  final settings = services.store.settings;
  final player = MusicPlayer(
    catalog: ref.watch(musicCatalogProvider),
    library: ref.watch(musicLibraryProvider),
    settings: settings,
    session: () => ref.read(playbackSessionFactoryProvider)(config: musicEngineConfig(settings)),
    cacheDirectory: Directory(p.join(services.dataRoot.path, 'music_cache')),
    notification: RoomMediaNotification.available ? SystemMusicNotification() : null,
    onMessage: (key) => AppNavigator.toast(i18n(key)),
  );
  ref.onDispose(player.dispose);
  return player;
});

/// Stops music before another player takes the speakers (a live room, a
/// video; pure_live_TV's mode switch rule). Does nothing when music never
/// started in this run.
Future<void> yieldMusicToOtherPlayback(WidgetRef ref) async {
  if (!ref.read(musicPlayerProvider.exists)) return;
  await ref.read(musicPlayerProvider).yieldToOtherPlayback();
}

/// The player settings as music's engine configuration (the live room's
/// decoder and output settings).
MpvEngineConfig musicEngineConfig(SettingsStore settings) => MpvEngineConfig(
  platform: mpvPlatformOf(defaultTargetPlatform) ?? MpvPlatform.linux,
  hardwareDecoding: settings.get(Settings.enableCodec),
  customOutput: settings.get(Settings.customPlayerOutput),
  videoOutputDriver: settings.get(Settings.videoOutputDriver),
  hardwareDecoder: settings.get(Settings.videoHardwareDecoder),
  audioOutputDriver: settings.get(Settings.audioOutputDriver),
  androidCompatibility: settings.get(Settings.playerCompatMode),
  volumeGainDb: settings.get(Settings.volumeBoostDb),
);
