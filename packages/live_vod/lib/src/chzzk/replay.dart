import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_vod/src/archive.dart';

/// Public recording metadata. Transient playlist URLs are kept separately.
final class ChzzkArchiveVideo implements ArchiveVideo {
  /// Creates a validated public broadcast row.
  const new({
    required this.id,
    required this.title,
    required this.channelId,
    required this.authorName,
    required this.cover,
    required this.publishedAt,
    required this.duration,
  });

  @override
  final String id;
  @override
  final String title;

  /// Canonical public channel id.
  final String channelId;

  /// Visible public creator name.
  final String authorName;

  /// Thumbnail, when provided.
  final String cover;

  /// Server publication time.
  final DateTime? publishedAt;
  @override
  final Duration duration;
}

/// A recording's single playable HLS part.
final class ChzzkArchivePart implements ArchiveVideo {
  /// Builds one playable part.
  const new(this.recording, this.quality);

  /// Recording metadata.
  final ChzzkArchiveVideo recording;

  /// The server's adaptive playlist.
  final ChzzkArchiveQuality quality;
  @override
  String get id => '${recording.id}:1';
  @override
  String get title => recording.title;
  @override
  Duration get duration => recording.duration;
}

/// An adaptive HLS playlist; no quality names are guessed from URL text.
final class ChzzkArchiveQuality implements ArchiveQuality {
  /// Creates a quality from a validated HTTPS URL.
  const new(this.url);

  /// Ephemeral playlist URL.
  final String url;
  @override
  String get id => 'auto';
  @override
  String get label => 'Auto';
  @override
  bool get playable => true;
}

/// Actual server pagination.
typedef ChzzkArchiveList = ({List<ChzzkArchiveVideo> videos, bool hasMore});

/// Public CHZZK replays on the same route as live playback.
final class ChzzkArchiveApi {
  /// Uses the app-owned HTTP transport.
  const new(this.http);

  /// Transport with cancellation and configured per-site proxy.
  final LiveHttp http;
  static final _channel = RegExp(r'^[0-9a-f]{32}$');
  static final _id = RegExp(r'^[1-9][0-9]{0,18}$');

  /// Public media request headers.
  static const headers = ChzzkApi.headers;

  /// A channel id or official channel/live/videos URL.
  static String? channelFromText(String text) {
    final value = text.trim().toLowerCase();
    if (_channel.hasMatch(value)) return value;
    final uri = _official(text);
    if (uri == null) return null;
    final p = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final candidate = switch (p) {
      [final id] || [final id, 'videos'] || ['live', final id] => id,
      _ => '',
    };
    return _channel.hasMatch(candidate) ? candidate : null;
  }

  /// A public recording URL.
  static String? videoFromText(String text) {
    final p = _official(text)?.pathSegments.where((s) => s.isNotEmpty).toList();
    if (p case ['video', final id] when _id.hasMatch(id)) return id;
    return null;
  }

  static Uri? _official(String text) {
    final uri = Uri.tryParse(text.trim());
    return uri != null &&
            const {'http', 'https'}.contains(uri.scheme) &&
            uri.host == 'chzzk.naver.com' &&
            !uri.hasPort &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }

  Future<Map<Object?, Object?>> _get(String path, CancelToken? cancel, [Map<String, String>? query]) async {
    final root = await http.getJson(
      'chzzk',
      Uri.https('api.chzzk.naver.com', path, query),
      headers: headers,
      cancel: cancel,
    );
    if (root is! Map || jsonInt(root['code']) != 200 || root['content'] is! Map) {
      throw const ApiChanged('chzzk', 'Public replay response');
    }
    return root['content'] as Map<Object?, Object?>;
  }

  /// Lists current public REPLAY rows; the service uses zero-based pages.
  Future<ChzzkArchiveList> list(String channel, {int page = 1, CancelToken? cancel}) async {
    if (!_channel.hasMatch(channel) || page < 1 || page > 10000) throw const FormatException('Invalid replay page');
    final content = await _get('/service/v1/channels/$channel/videos', cancel, {
      'size': '20',
      'page': '${page - 1}',
      'videoType': 'REPLAY',
      'sortType': 'LATEST',
    });
    return parseList(content, channel: channel, page: page);
  }

  /// Checks pagination and channel identity independently of visible rows.
  static ChzzkArchiveList parseList(Map<Object?, Object?> content, {required String channel, required int page}) {
    final rows = content['data'];
    final total = jsonInt(content['totalPages']);
    if (rows is! List || rows.length > 100 || total == null || total < 0 || jsonInt(content['page']) != page - 1) {
      throw const ApiChanged('chzzk', 'Replay pagination');
    }
    final seen = <String>{};
    final videos = <ChzzkArchiveVideo>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final v = _video(row);
      if (v != null && v.channelId == channel && seen.add(v.id)) videos.add(v);
    }
    return (videos: List.unmodifiable(videos), hasMore: page < total);
  }

  static ChzzkArchiveVideo? _video(Map<Object?, Object?> row, {bool requireExposure = false}) {
    // The catalog's exposure bit differs from the playback detail's bit.
    if ((requireExposure && row['exposure'] != true) ||
        row['blindType'] != null ||
        row['adult'] != false ||
        row['paidProductId'] != null ||
        row['videoType'] != 'REPLAY') {
      return null;
    }
    final id = jsonInt(row['videoNo'])?.toString() ?? '';
    final channel = row['channel'];
    if (channel is! Map) return null;
    final cid = jsonString(channel['channelId']) ?? '';
    final title = jsonString(row['videoTitle']) ?? '';
    if (!_id.hasMatch(id) || !_channel.hasMatch(cid) || title.isEmpty || title.length > 4096) return null;
    final stamp = jsonInt(row['publishDateAt']);
    return ChzzkArchiveVideo(
      id: id,
      title: title,
      channelId: cid,
      authorName: jsonString(channel['channelName']) ?? '',
      cover: normalizeImageUrl(row['thumbnailImageUrl']),
      publishedAt: stamp != null && stamp > 0 && stamp < 4102444800000
          ? DateTime.fromMillisecondsSinceEpoch(stamp, isUtc: true)
          : null,
      duration: Duration(seconds: (jsonInt(row['duration']) ?? 0).clamp(0, 604800)),
    );
  }

  /// Resolves only the platform's public HLS replay; no age/paid bypass.
  Future<List<ChzzkArchivePart>> detail(String id, {CancelToken? cancel}) async {
    if (!_id.hasMatch(id)) throw const FormatException('Invalid replay id');
    return parseDetail(await _get('/service/v3/videos/$id', cancel), id: id);
  }

  /// Accepts only permitted HLS paths, including currently converting replays
  /// when the service still supplies a public rewind playlist.
  static List<ChzzkArchivePart> parseDetail(Map<Object?, Object?> row, {required String id}) {
    final recording = _video(row, requireExposure: true);
    if (recording == null) throw const StreamUnavailable('chzzk', 'Replay is not public');
    if (recording.id != id) throw const ApiChanged('chzzk', 'Replay identity');
    final raw = row['liveRewindPlaybackJson'];
    if (raw is! String || raw.length > 262144) {
      throw const StreamUnavailable('chzzk', 'No public HLS replay');
    }
    final json = jsonDecode(raw);
    final media = json is Map ? json['media'] : null;
    if (media is! List || media.length > 16) throw const ApiChanged('chzzk', 'Replay playlist shape');
    for (final value in media) {
      if (value is! Map || value['mediaId'] != 'HLS') continue;
      final path = jsonString(value['path']);
      final uri = path == null || path.length > 8192 ? null : Uri.tryParse(path);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.hasPort ||
          uri.userInfo.isNotEmpty ||
          !uri.path.toLowerCase().endsWith('.m3u8') ||
          !const [
            'akamaized.net',
            'naver.com',
            'navercdn.com',
            'pstatic.net',
          ].any((d) => uri.host == d || uri.host.endsWith('.$d'))) {
        continue;
      }
      return [ChzzkArchivePart(recording, ChzzkArchiveQuality(uri.toString()))];
    }
    throw const StreamUnavailable('chzzk', 'No permitted public HLS playlist');
  }
}
