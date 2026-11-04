import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_vod/src/archive.dart';

/// Public SOOP broadcast metadata, without transient media URLs.
final class SoopArchiveVideo implements ArchiveVideo {
  /// Creates one creator archive row.
  const new({
    required this.id,
    required this.title,
    required this.authorId,
    this.authorName = '',
    this.cover = '',
    this.publishedAt,
    this.duration = Duration.zero,
  });
  @override
  final String id;
  @override
  final String title;

  /// Public broadcaster id.
  final String authorId;

  /// Platform-supplied creator name.
  final String authorName;

  /// Public thumbnail.
  final String cover;

  /// Publication instant, interpreted in Korea Standard Time.
  final DateTime? publishedAt;
  @override
  final Duration duration;
}

/// Server pagination, independent of the number of rows surviving validation.
typedef SoopArchiveList = ({List<SoopArchiveVideo> videos, bool hasMore});

/// One actual file/part of a recording. Qualities are ephemeral.
final class SoopArchivePart implements ArchiveVideo {
  /// Creates a part, using the server's stable file_order.
  const new({required this.recording, required this.order, required this.qualities, required this.duration});

  /// Parent recording metadata.
  final SoopArchiveVideo recording;

  /// Stable server part number.
  final int order;

  /// Only qualities supplied by this part's current response.
  final List<SoopArchiveQuality> qualities;
  @override
  String get id => '${recording.id}:$order';
  @override
  String get title => '${recording.title} · $order';
  @override
  final Duration duration;
}

/// One permitted HTTP rendition from quality_info.
final class SoopArchiveQuality implements ArchiveQuality {
  /// Transient URLs are never persisted with progress.
  const new({required this.id, required this.label, required this.url});
  @override
  final String id;
  @override
  final String label;

  /// Validated CDN URL, refreshed whenever playback is reopened.
  final String url;
  @override
  bool get playable => true;
}

/// Read-only, cancellable creator archive and playback contracts.
abstract interface class SoopArchiveSource {
  /// Official broadcast replays, newest first.
  Future<SoopArchiveList> list(String author, {int page = 1, CancelToken? cancel});

  /// All currently permitted parts; restrictions never produce guessed URLs.
  Future<List<SoopArchivePart>> detail(String id, {CancelToken? cancel});
}

/// Current SOOP public station/video APIs, sharing the live platform route.
final class SoopArchiveApi implements SoopArchiveSource {
  /// App-owned transport and optional existing SOOP login.
  const new(this.http, {this.cookies});

  /// Shared transport, including proxy, rate limiting and cancellation.
  final LiveHttp http;

  /// Never reads another platform's account.
  final CookieVault? cookies;
  static final _id = RegExp(r'^[1-9][0-9]{0,18}$');
  static final _author = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// Public author id, room URL or official station replay URL.
  static String? authorFromText(String raw) {
    final text = raw.trim();
    if (_author.hasMatch(text)) return text.toLowerCase();
    final u = Uri.tryParse(text);
    if (u == null ||
        !{'https', 'http'}.contains(u.scheme) ||
        u.userInfo.isNotEmpty ||
        u.hasPort ||
        !{
          'www.sooplive.com',
          'www.sooplive.co.kr',
          'play.sooplive.com',
          'play.sooplive.co.kr',
          'ch.sooplive.co.kr',
        }.contains(u.host)) {
      return null;
    }
    final p = u.pathSegments.where((s) => s.isNotEmpty).toList();
    final value = p.length == 3 && p.first == 'station' && p.last == 'vod'
        ? p[1]
        : p.length == 1 || p.length == 2 && _id.hasMatch(p.last)
        ? p.first
        : '';
    return _author.hasMatch(value) && !{'station', 'vod', 'live', 'main'}.contains(value) ? value.toLowerCase() : null;
  }

  /// Official public VOD id; never treats a title id as a live room.
  static String? videoFromText(String text) {
    final u = Uri.tryParse(text.trim());
    if (u == null || u.scheme != 'https' || u.host != 'vod.sooplive.com' || u.userInfo.isNotEmpty || u.hasPort) {
      return null;
    }
    return RegExp(r'^/(?:player|PLAYER/STATION)/([1-9][0-9]{0,18})/?$').firstMatch(u.path)?.group(1);
  }

  /// Public media needs its own referer, without forwarding account cookies.
  static Map<String, String> mediaHeaders(String id) => {
    'referer': 'https://vod.sooplive.com/player/$id',
    'user-agent': SoopApi.userAgent,
  };

  Future<Map<String, dynamic>> _send(Uri url, CancelToken? cancel, {Map<String, String>? fields}) async {
    final headers = SoopApi.apiHeaders(cookie: cookies?.cookieFor('soop') ?? '');
    final request = fields == null
        ? LiveRequest(site: 'soop', url: url, headers: headers, cancel: cancel)
        : LiveRequest.form(site: 'soop', url: url, headers: headers, fields: fields, cancel: cancel);
    try {
      final response = await http.send(request);
      if (response.status == 401) throw const NeedsLogin('soop', 'Archive requires login');
      if (response.status == 404) throw const NotFound('soop', 'Archive not found');
      if ({403, 429}.contains(response.status)) throw const RiskControl('soop', detail: 'Archive refused');
      if (!response.isSuccess) throw const NetworkFailure('soop', 'Archive HTTP failure');
      if (response.bytes.length > 8 * 1024 * 1024) throw const ApiChanged('soop', 'Archive size limit');
      return _root(response.text);
    } on TransportFailure catch (e) {
      if (e.reason == TransportReason.cancelled) rethrow;
      throw const NetworkFailure('soop', 'Archive transport failed');
    }
  }

  static Map<String, dynamic> _root(String text) {
    try {
      final v = jsonDecode(text);
      if (v is Map<String, dynamic>) return v;
    } on FormatException {
      /* Fixed diagnostics below. */
    }
    throw const ApiChanged('soop', 'Invalid archive JSON');
  }

  static String _text(Object? o) => o is String
      ? o
      : o is int
      ? '$o'
      : '';
  static Duration _duration(Object? o) {
    final n = jsonInt(o);
    return n != null && n >= 0 && n <= 31536000000 ? Duration(milliseconds: n) : Duration.zero;
  }

  static DateTime? _date(Object? o) {
    final s = _text(o);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(s)) return null;
    return DateTime.tryParse('${s.replaceFirst(' ', 'T')}+09:00')?.toUtc();
  }

  static String _url(Object? o) {
    final u = Uri.tryParse(_text(o));
    return u != null &&
            u.scheme == 'https' &&
            u.userInfo.isEmpty &&
            !u.hasPort &&
            ['sooplive.com', 'sooplive.co.kr', 'afreecatv.com'].any((h) => u.host == h || u.host.endsWith('.$h'))
        ? u.toString()
        : '';
  }

  @override
  Future<SoopArchiveList> list(String author, {int page = 1, CancelToken? cancel}) async {
    if (!_author.hasMatch(author) || page < 1 || page > 100000) {
      throw const FormatException('Invalid SOOP archive page');
    }
    final root = await _send(
      Uri.https('chapi.sooplive.com', '/api/$author/vods/review', {
        'page': '$page',
        'per_page': '20',
        'orderby': 'reg_date',
      }),
      cancel,
    );
    return parseList(root, author: author, page: page);
  }

  /// Pure list parser with independently checked pagination and author identity.
  static SoopArchiveList parseList(Map<String, dynamic> root, {required String author, required int page}) {
    final rows = root['data'];
    final meta = root['meta'];
    if (rows is! List ||
        rows.length > 100 ||
        meta is! Map ||
        jsonInt(meta['current_page']) != page ||
        jsonInt(meta['last_page']) == null) {
      throw const ApiChanged('soop', 'Archive pagination shape');
    }
    final seen = <String>{};
    final videos = <SoopArchiveVideo>[];
    for (final row in rows) {
      if (row is! Map || _text(row['user_id']) != author || row['ucc'] is! Map) continue;
      final ucc = row['ucc'] as Map;
      final id = _text(row['title_no']);
      final title = _text(row['title_name']);
      if (!_id.hasMatch(id) || title.isEmpty || title.length > 4096 || !seen.add(id)) continue;
      videos.add(
        SoopArchiveVideo(
          id: id,
          title: decodeHtmlEntities(title),
          authorId: author,
          authorName: _text(row['user_nick']),
          cover: normalizeImageUrl(ucc['thumb']),
          publishedAt: _date(row['reg_date']),
          duration: _duration(ucc['total_file_duration']),
        ),
      );
    }
    return (videos: List.unmodifiable(videos), hasMore: page < jsonInt(meta['last_page'])!);
  }

  @override
  Future<List<SoopArchivePart>> detail(String id, {CancelToken? cancel}) async {
    if (!_id.hasMatch(id)) throw const FormatException('Invalid SOOP recording id');
    return parseDetail(
      await _send(
        Uri.https('api.m.sooplive.com', '/station/video/a/view'),
        cancel,
        fields: {'nTitleNo': id, 'nApiLevel': '10'},
      ),
      id: id,
    );
  }

  /// Only server-provided public files and qualities are admitted.
  static List<SoopArchivePart> parseDetail(Map<String, dynamic> root, {required String id}) {
    final data = root['data'];
    if (data is! Map) throw const ApiChanged('soop', 'Archive detail shape');
    if (jsonInt(data['code']) == -6221) throw const NotFound('soop', 'Recording removed');
    if (jsonInt(data['code']) == -6205) throw const StreamUnavailable('soop', 'Recording private');
    if (data['adult_status'] == 'notLogin') throw const NeedsLogin('soop', 'Recording requires age verification');
    if (data['is_paid'] == true || data['is_ppv'] == true) {
      throw const NeedsLogin('soop', 'Paid recording not supported');
    }
    if (jsonInt(root['result']) != 1 || _text(data['title_no']) != id) {
      throw const ApiChanged('soop', 'Archive detail identity');
    }
    final rows = data['files'];
    if (rows is! List || rows.length > 500) throw const ApiChanged('soop', 'Archive file shape');
    final video = SoopArchiveVideo(
      id: id,
      title: _text(data['title']),
      authorId: _text(data['bj_id']),
      authorName: _text(data['writer_nick']),
      cover: normalizeImageUrl(data['thumb']),
      publishedAt: _date(data['write_tm']),
      duration: _duration(data['total_file_duration']),
    );
    final parts = <SoopArchivePart>[];
    final seen = <int>{};
    for (final row in rows) {
      if (row is! Map || row['hide'] == 'Y') continue;
      final order = jsonInt(row['file_order']);
      if (order == null || order < 1 || order > 100000 || !seen.add(order)) continue;
      final qualities = <SoopArchiveQuality>[];
      final ids = <String>{};
      final qualityInfo = row['quality_info'];
      if (qualityInfo is List && qualityInfo.length <= 32) {
        for (final q in qualityInfo) {
          if (q is! Map) continue;
          final key = _text(q['name']);
          final url = _url(q['file']);
          final label = _text(q['label']);
          if (key.isEmpty || key.length > 64 || label.isEmpty || label.length > 64 || url.isEmpty || !ids.add(key)) {
            continue;
          }
          qualities.add(SoopArchiveQuality(id: key, label: label, url: url));
        }
      }
      final file = _url(row['file']);
      if (qualities.isEmpty && file.isNotEmpty) {
        qualities.add(SoopArchiveQuality(id: 'source', label: '原画', url: file));
      }
      if (qualities.isNotEmpty) {
        parts.add(
          SoopArchivePart(
            recording: video,
            order: order,
            qualities: List.unmodifiable(qualities),
            duration: _duration(row['duration']),
          ),
        );
      }
    }
    parts.sort((a, b) => a.order.compareTo(b.order));
    if (parts.isEmpty) {
      throw const StreamUnavailable('soop', 'No public recording files; login or regional restrictions may apply');
    }
    return List.unmodifiable(parts);
  }
}
