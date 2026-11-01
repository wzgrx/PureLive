import 'dart:async';
import 'dart:convert';

import 'package:live_vod/live_vod.dart';

/// A local video position, without cookies, signed URLs or signing data.
final class DouyuVodProgress {
  /// Creates an entry.
  const new({required this.video, required this.position, required this.updated});

  /// Public metadata for the history list.
  final DouyuVodVideo video;

  /// Last watched position; zero means watched to completion.
  final Duration position;

  /// Last watch time.
  final DateTime updated;
}

/// One app-owned bounded history, backed by the existing app store's
/// metadata repository. Writes are serialized so overlapping exits cannot erase
/// another video's progress. A storage failure never prevents playback.
final class DouyuVodProgressStore {
  /// Uses the application's metadata read/write callbacks.
  new({required this.read, required this.write});

  /// Reads the one history JSON value.
  final Future<String?> Function() read;

  /// Writes the one history JSON value.
  final Future<void> Function(String value) write;

  Future<void> _queue = Future.value();

  /// Most recently watched first; invalid old entries are ignored.
  Future<List<DouyuVodProgress>> list() async {
    await _queue;
    return await _load();
  }

  Future<List<DouyuVodProgress>> _load() async {
    try {
      final raw = await read();
      if (raw == null || raw.length > 524288) return [];
      final values = jsonDecode(raw);
      if (values is! List) return [];
      final result = <DouyuVodProgress>[];
      for (final item in values.take(200)) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['id'];
        final milliseconds = item['position'];
        final timestamp = item['updated'];
        if (id is! String ||
            DouyuVodApi.idFromText(id) != id ||
            milliseconds is! int ||
            milliseconds < 0 ||
            milliseconds > 31536000000 ||
            timestamp is! String) {
          continue;
        }
        final updated = DateTime.tryParse(timestamp);
        if (updated == null) continue;
        result.add(
          DouyuVodProgress(
            video: DouyuVodVideo(
              id: id,
              title: item['title'] is String ? item['title'] as String : id,
              authorId: item['authorId'] is String ? item['authorId'] as String : '',
              authorName: item['authorName'] is String ? item['authorName'] as String : '',
              replay: item['replay'] == true,
            ),
            position: Duration(milliseconds: milliseconds),
            updated: updated,
          ),
        );
      }
      result.sort((a, b) => b.updated.compareTo(a.updated));
      return result;
    } on Object {
      return [];
    }
  }

  /// Stores a position (or zero after completion), retaining at most 200 videos.
  Future<void> save(DouyuVodVideo video, Duration position, {bool completed = false}) {
    final snapshot = completed ? Duration.zero : position;
    if (snapshot < Duration.zero || DouyuVodApi.idFromText(video.id) != video.id) return Future.value();
    return _queue = _queue
        .then((_) async {
          final entries = await _load();
          entries
            ..removeWhere((entry) => entry.video.id == video.id)
            ..insert(0, DouyuVodProgress(video: video, position: snapshot, updated: DateTime.now().toUtc()));
          await write(
            jsonEncode([
              for (final entry in entries.take(200))
                {
                  'id': entry.video.id,
                  'title': entry.video.title,
                  'authorId': entry.video.authorId,
                  'authorName': entry.video.authorName,
                  'replay': entry.video.replay,
                  'position': entry.position.inMilliseconds,
                  'updated': entry.updated.toIso8601String(),
                },
            ]),
          );
        })
        .catchError((Object _) {});
  }

  /// Clears local VOD history, after any previous write completes.
  Future<void> clear() => _queue = _queue.then((_) => write('[]')).catchError((Object _) {});
}
