import 'package:live_core/live_core.dart';
import 'package:live_vod/src/archive.dart';
import 'package:live_vod/src/douyu/sign.dart';
import 'package:live_vod/src/models.dart';
import 'package:meta/meta.dart';

/// Public metadata of an official Douyu video or a replay segment.
@immutable
final class DouyuVodVideo implements ArchiveVideo {
  /// Creates metadata, with no expiring stream URL or login credential.
  const new({
    required this.id,
    required this.title,
    this.authorId = '',
    this.authorName = '',
    this.cover = '',
    this.duration = Duration.zero,
    this.pointId = '',
    this.replay = false,
  });

  /// Reads the current web search, author, replay and video-page field shapes.
  factory fromJson(Map<String, dynamic> json, {bool replay = false}) => DouyuVodVideo(
    id: jsonString(json['hashId'] ?? json['hash_id'] ?? json['vid']) ?? '',
    title: decodeHtmlEntities(jsonString(json['title'] ?? json['name']) ?? ''),
    authorId: jsonString(json['upId'] ?? json['up_id']) ?? '',
    authorName: decodeHtmlEntities(
      jsonString(json['owner'] ?? json['nickname'] ?? json['author'] ?? json['author_name']) ?? '',
    ),
    cover: normalizeImageUrl(json['cover'] ?? json['video_pic'] ?? json['pic']),
    duration: douyuVodDuration(json['video_duration'] ?? json['duration'] ?? json['video_str_duration']),
    pointId: jsonString(json['point_id']) ?? '',
    replay: replay || jsonInt(json['is_replay']) == 1 || json['is_replay'] == true,
  );

  /// Hash id used by `/show/{id}`, distinct from the numeric point id.
  @override
  final String id;

  /// Display title.
  @override
  final String title;

  /// Public encoded author id used by author-list endpoints.
  final String authorId;

  /// Display name.
  final String authorName;

  /// Public cover URL.
  final String cover;

  /// Duration, or zero until the engine provides it.
  @override
  final Duration duration;

  /// Numeric signing point id, supplied by the video detail.
  final String pointId;

  /// Explicit replay mode from the list or platform field, never a title guess.
  final bool replay;

  /// Canonical official video page.
  Uri get uri => Uri.https('v.douyu.com', '/show/$id');
}

/// A bounded page of videos. Replay totals count sessions, not their segments.
@immutable
final class DouyuVodPage {
  /// Creates a page.
  const new({required this.videos, required this.hasMore, this.total = 0});

  /// Videos/segments on this page.
  final List<DouyuVodVideo> videos;

  /// Whether another server page exists.
  final bool hasMore;

  /// Server total, zero when not supplied.
  final int total;
}

/// One daily-signed video detail; the signer executes no remote code.
@immutable
final class DouyuVodDetail {
  /// Creates a detail.
  const new({required this.video, required this.signer});

  /// Current public metadata and numeric signing point id.
  final DouyuVodVideo video;

  /// Data-only daily descriptor parser.
  final DouyuVodSigner signer;
}

/// A platform-offered rendition, including an unavailable paid/login tier.
@immutable
final class DouyuVodQuality implements ArchiveQuality {
  /// Creates a rendition. Only [playable] entries can be opened.
  const new({required this.id, required this.label, required this.level, required this.url, required this.playable});

  /// Platform stream type.
  @override
  final String id;

  /// Platform quality label.
  @override
  final String label;

  /// Ordering level, highest first.
  final int level;

  /// Expiring media URL; never persisted in history.
  final String url;

  /// Whether the server provides a URL and allows this client to play it.
  @override
  final bool playable;
}

/// A position-based danmaku chunk, with a strictly advancing server cursor.
@immutable
final class DouyuVodDanmakuChunk {
  /// Creates a chunk.
  const new({required this.messages, required this.next, this.blocked = false});

  /// Timeline-ordered comments.
  final List<VodDanmaku> messages;

  /// Next millisecond cursor; null after the last chunk or non-advancing data.
  final Duration? next;

  /// The platform explicitly disabled comments for this video/client.
  final bool blocked;
}

/// Seconds as a number, or the platform's `MM:SS` / `HH:MM:SS` duration text.
Duration douyuVodDuration(Object? value) {
  if (value is num && value.isFinite && value > 0) return Duration(milliseconds: (value * 1000).round());
  final text = jsonString(value)?.trim() ?? '';
  if (text.isEmpty) return Duration.zero;
  final parts = text.split(':');
  if (parts.length > 3) return Duration.zero;
  var seconds = 0.0;
  for (final part in parts) {
    final number = double.tryParse(part);
    if (number == null || !number.isFinite || number < 0) return Duration.zero;
    seconds = seconds * 60 + number;
  }
  return seconds <= 31536000 ? Duration(milliseconds: (seconds * 1000).round()) : Duration.zero;
}
