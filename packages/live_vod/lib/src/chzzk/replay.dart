import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_vod/src/archive.dart';
import 'package:live_vod/src/chzzk/segments.dart';

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

/// A recording's single playable part.
final class ChzzkArchivePart implements ArchiveVideo {
  /// Builds one playable part.
  const new(this.recording, this.qualities);

  /// Recording metadata.
  final ChzzkArchiveVideo recording;

  /// The server's available quality choices.
  final List<ChzzkArchiveQuality> qualities;
  @override
  String get id => '${recording.id}:1';
  @override
  String get title => recording.title;
  @override
  Duration get duration => recording.duration;
}

/// A public, seekable media URL discovered for this recording.
final class ChzzkArchiveQuality implements ArchiveQuality {
  /// Creates a quality from a validated HTTPS URL.
  const new(this.url, {this.id = 'auto', this.label = 'Auto', this.format = StreamFormat.hls, this.segments});

  /// Ephemeral media URL.
  final String url;
  @override
  final String id;
  @override
  final String label;

  /// Distinguishes a playlist from a progressive muxed MP4.
  final StreamFormat format;

  /// The same quality as independently seekable public TS segments, when offered.
  final ChzzkVodSegments? segments;
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
  static const Map<String, String> headers = ChzzkApi.headers;

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

  /// Resolves public HLS or a finished recording's muxed MP4 representations.
  Future<List<ChzzkArchivePart>> detail(String id, {CancelToken? cancel}) async {
    if (!_id.hasMatch(id)) throw const FormatException('Invalid replay id');
    final row = await _get('/service/v3/videos/$id', cancel);
    final recording = _publicRecording(row, id);
    final hls = _playlist(row);
    if (hls != null) {
      return [
        ChzzkArchivePart(recording, [hls]),
      ];
    }
    final vodId = jsonString(row['videoId']);
    final key = jsonString(row['inKey']);
    if (row['vodStatus'] != 'ABR_HLS' ||
        vodId == null ||
        !_vodId.hasMatch(vodId) ||
        key == null ||
        key.isEmpty ||
        key.length > 2048) {
      throw const StreamUnavailable('chzzk', 'Public replay is still processing');
    }
    final url = Uri.https('apis.naver.com', '/neonplayer/vodplay/v1/playback/$vodId', {
      'key': key,
      'env': 'real',
      'lc': 'en_US',
      'cpl': 'en_US',
    });
    final manifest = await _readManifest(url, cancel);
    return parseMediaManifest(recording, manifest);
  }

  static final _vodId = RegExp(r'^[A-Za-z0-9_-]{16,128}$');
  static const int _maxManifestBytes = 2 * 1024 * 1024;

  Future<Object?> _readManifest(Uri url, CancelToken? cancel) async {
    final owned = CancelToken();
    if (cancel != null) {
      if (cancel.isCancelled) owned.cancel();
      unawaited(cancel.whenCancelled.then((_) => owned.cancel()));
    }
    Future<Object?> read() async {
      final reply = await http.open(
        LiveRequest.get(
          site: 'chzzk',
          url: url,
          headers: const {...ChzzkApi.mediaHeaders, 'accept': 'application/json'},
          timeout: const Duration(seconds: 12),
          cancel: owned,
        ),
      );
      if (!reply.isSuccess ||
          reply.url.scheme != 'https' ||
          reply.url.host != url.host ||
          (reply.contentLength ?? 0) > _maxManifestBytes) {
        await reply.discard();
        throw const StreamUnavailable('chzzk', 'Public media manifest unavailable');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in reply.body) {
        if (bytes.length + chunk.length > _maxManifestBytes) {
          throw const ApiChanged('chzzk', 'Media manifest too large');
        }
        bytes.add(chunk);
      }
      try {
        return jsonDecode(utf8.decode(bytes.takeBytes()));
      } on FormatException {
        throw const ApiChanged('chzzk', 'Invalid media manifest');
      }
    }

    try {
      return await read().timeout(const Duration(seconds: 14));
    } finally {
      owned.cancel();
    }
  }

  static ChzzkArchiveVideo _publicRecording(Map<Object?, Object?> row, String id) {
    final recording = _video(row, requireExposure: true);
    if (recording == null) throw const StreamUnavailable('chzzk', 'Replay is not public');
    if (recording.id != id) throw const ApiChanged('chzzk', 'Replay identity');
    return recording;
  }

  /// Accepts permitted HLS when the platform supplies a public rewind playlist.
  static List<ChzzkArchivePart> parseDetail(Map<Object?, Object?> row, {required String id}) {
    final recording = _publicRecording(row, id);
    final q = _playlist(row);
    if (q == null) throw const StreamUnavailable('chzzk', 'No permitted public HLS playlist');
    return [
      ChzzkArchivePart(recording, [q]),
    ];
  }

  static ChzzkArchiveQuality? _playlist(Map<Object?, Object?> row) {
    final raw = row['liveRewindPlaybackJson'];
    if (raw is! String || raw.length > 262144) {
      return null;
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
      return ChzzkArchiveQuality(uri.toString());
    }
    return null;
  }

  /// Keeps the quality labels stable while pairing available TS segments
  /// with the original whole-file MP4. Unrecognised segments fall back to MP4.
  static List<ChzzkArchivePart> parseMediaManifest(ChzzkArchiveVideo recording, Object? manifest) {
    final segmented = <int, ChzzkVodSegments>{};
    final periods = manifest is Map && jsonString(manifest['type'])?.toLowerCase() == 'static'
        ? manifest['period']
        : null;
    if (periods case [final Map<Object?, Object?> period]) {
      final tracks = period['adaptationSet'];
      if (tracks is List &&
          tracks.length <= 16 &&
          ['segmentBase', 'segmentTemplate', 'segmentList', 'contentProtection'].every((key) => period[key] == null)) {
        for (final track in tracks) {
          if (track is! Map || track['representation'] is! List) continue;
          final variants = track['representation'] as List;
          if (variants.length > 24) continue;
          for (final v in variants) {
            if (v is! Map) continue;
            final height = jsonInt(v['height'] ?? track['height']);
            if (height == null || height < 100 || height > 4320 || segmented.containsKey(height)) continue;
            final timeline = ChzzkVodSegments.parse(track, v, duration: recording.duration);
            if (timeline != null) segmented[height] = timeline;
          }
        }
      }
    }
    if (segmented.isEmpty) return parseProgressive(recording, manifest);
    final progressive = <int, ChzzkArchiveQuality>{};
    try {
      for (final q in parseProgressive(recording, manifest).single.qualities) {
        final height = int.tryParse(q.id.substring('mp4-'.length));
        if (height != null) progressive[height] = q;
      }
    } on StreamUnavailable {
      // A public recording can legitimately have TS but no whole-file MP4.
    }
    final heights = {...segmented.keys, ...progressive.keys}.toList()..sort();
    return [
      ChzzkArchivePart(
        recording,
        List.unmodifiable([
          for (final height in heights)
            if (segmented[height] case final segments?)
              ChzzkArchiveQuality(
                progressive[height]?.url ?? segments.firstUrl,
                id: 'mp4-$height',
                label: '${height}p',
                format: progressive[height]?.format ?? StreamFormat.hls,
                segments: segments,
              )
            else
              progressive[height]!,
        ]),
      ),
    ];
  }

  /// Accepts only whole-file H.264/AAC MP4 representations of one static period.
  /// DASH segments, audio-only tracks and encrypted sources are left untouched.
  static List<ChzzkArchivePart> parseProgressive(ChzzkArchiveVideo recording, Object? manifest) {
    if (manifest is! Map || jsonString(manifest['type'])?.toLowerCase() != 'static' || manifest['period'] is! List) {
      throw const ApiChanged('chzzk', 'Unexpected media manifest');
    }
    final periods = manifest['period'] as List;
    if (periods.length != 1 || periods.single is! Map) {
      throw const StreamUnavailable('chzzk', 'Unsupported recording period layout');
    }
    final period = periods.single as Map;
    final adaptations = period['adaptationSet'];
    if (adaptations is! List || adaptations.length > 16) throw const ApiChanged('chzzk', 'Unexpected media tracks');
    bool segmentedOrProtected(Map<Object?, Object?> row) =>
        ['segmentTemplate', 'segmentList', 'segmentBase'].any((name) => row[name] != null) ||
        (row['contentProtection'] != null &&
            (row['contentProtection'] is! List || (row['contentProtection']! as List).isNotEmpty));
    final found = <int, ChzzkArchiveQuality>{};
    if (!segmentedOrProtected(period)) {
      for (final track in adaptations) {
        if (track is! Map || segmentedOrProtected(track)) continue;
        final variants = track['representation'];
        if (variants is! List || variants.length > 24) continue;
        for (final v in variants) {
          if (v is! Map || segmentedOrProtected(v) || (v['mimeType'] ?? track['mimeType']) != 'video/mp4') continue;
          final codecs = (jsonString(v['codecs'] ?? track['codecs']) ?? '').split(',').map((c) => c.trim());
          if (!codecs.any((c) => c.startsWith('avc1.')) || !codecs.any((c) => c.startsWith('mp4a.'))) continue;
          final h = jsonInt(v['height'] ?? track['height']);
          if (h == null || h < 100 || h > 4320 || found.containsKey(h)) continue;
          final sources = v['baseURL'];
          if (sources is! List || sources.length > 8) continue;
          for (final source in sources) {
            if (source is! Map) continue;
            final raw = jsonString(source['value']);
            final uri = raw == null || raw.length > 8192 ? null : Uri.tryParse(raw);
            if (uri == null ||
                uri.scheme != 'https' ||
                uri.hasPort ||
                uri.userInfo.isNotEmpty ||
                !uri.host.endsWith('.akamaized.net') ||
                !uri.path.toLowerCase().endsWith('.mp4')) {
              continue;
            }
            found[h] = ChzzkArchiveQuality(uri.toString(), id: 'mp4-$h', label: '${h}p', format: StreamFormat.other);
            break;
          }
        }
      }
    }
    if (found.isEmpty) throw const StreamUnavailable('chzzk', 'No supported public MP4 source');
    // Start on the cheapest verified muxed stream. The player can switch
    // explicitly while retaining position and resolving a fresh media URL.
    final heights = found.keys.toList()..sort();
    return [ChzzkArchivePart(recording, List.unmodifiable(heights.map((h) => found[h]!)))];
  }
}
