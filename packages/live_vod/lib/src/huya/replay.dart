import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_vod/src/archive.dart';
import 'package:meta/meta.dart';

final _id = RegExp(r'^[1-9][0-9]{0,18}$');
final _assignment = RegExp(r'window\.HNF_GLOBAL_INIT\s*=');
final _responseKey = RegExp(r'"userPageLiveRecordVideoRsp"\s*:\s*');
final _metadataFunction = RegExp(r'"_(?:proto|write|read)"\s*:\s*function\s*\([^)]{0,128}\)\s*\{[^{}]{0,1024}\}');

/// Public metadata for one officially archived Huya broadcast.
@immutable
final class HuyaArchiveVideo implements ArchiveVideo {
  /// No media URL or credentials are retained in metadata.
  const new({
    required this.id,
    required this.title,
    required this.authorId,
    this.authorName = '',
    this.cover = '',
    this.duration = Duration.zero,
    this.date = '',
  });

  @override
  final String id;
  @override
  final String title;

  /// Public presenter uid, distinct from the room number.
  final String authorId;

  /// Presenter display name.
  final String authorName;

  /// Public cover URL.
  final String cover;
  @override
  final Duration duration;

  /// Date label supplied by the official archive.
  final String date;
}

/// One page of recorded broadcasts, in the platform's order.
@immutable
final class HuyaArchiveList {
  /// Creates a list result.
  const new({required this.videos, required this.hasMore});

  /// Broadcasts available on this page.
  final List<HuyaArchiveVideo> videos;

  /// Whether the server offers another page.
  final bool hasMore;
}

/// One permitted rendition, freshly resolved for playback.
@immutable
final class HuyaArchiveQuality implements ArchiveQuality {
  /// Wraps a quality already validated by the shared Huya parser.
  const new(this.quality);

  /// Shared native play quality; data is an ephemeral media URL.
  final LivePlayQuality quality;
  @override
  String get id => quality.selectionId.toString();
  @override
  String get label => quality.quality;
  @override
  bool get playable => HuyaApi.replayUrl(quality.data) != null;

  /// An expiring stream URL, never written into local progress.
  String get url => HuyaApi.replayUrl(quality.data)!;
}

/// Read-only archive endpoints; deterministic tests replace the transport.
abstract interface class HuyaArchiveSource {
  /// The official presenter's archive, paged without a login requirement.
  Future<HuyaArchiveList> list(String uid, {int page = 1, CancelToken? cancel});

  /// Current permitted qualities of a selected video.
  Future<List<HuyaArchiveQuality>> qualities(String videoId, {CancelToken? cancel});
}

/// Current official Huya user-video SSR data and getMomentContent qualities.
/// Tars prototype functions are discarded as metadata, never evaluated.
final class HuyaArchiveApi implements HuyaArchiveSource {
  /// Uses the application's shared transport, proxy and cancellation policy.
  const new(this.http);

  /// App-owned transport; this wrapper does not close it.
  final LiveHttp http;

  /// Media has no application cookie or cross-platform headers.
  static const Map<String, String> mediaHeaders = {'referer': 'https://www.huya.com/', 'user-agent': HuyaApi.userAgent};

  /// Accepts a public uid or the exact official archive URL.
  static String? uidFromText(String value) {
    final text = value.trim();
    if (_id.hasMatch(text)) return text;
    final uri = Uri.tryParse(text);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) || !{'www.huya.com', 'huya.com'}.contains(uri.host)) {
      return null;
    }
    final match = RegExp(r'^/video/u/([1-9][0-9]{0,18})/?$').firstMatch(uri.path);
    return match?.group(1);
  }

  @override
  Future<HuyaArchiveList> list(String uid, {int page = 1, CancelToken? cancel}) async {
    if (!_id.hasMatch(uid) || page < 1 || page > 10000) throw const FormatException('Invalid archive page');
    final response = await _get(
      Uri.https('www.huya.com', '/video/u/$uid', {'tabName': 'live', 'pageIndex': '$page'}),
      cancel,
    );
    return parseList(response.text, uid: uid, page: page);
  }

  @override
  Future<List<HuyaArchiveQuality>> qualities(String videoId, {CancelToken? cancel}) async {
    if (!_id.hasMatch(videoId)) throw const FormatException('Invalid archive id');
    final response = await _get(
      Uri.https('liveapi.huya.com', '/moment/getMomentContent', {'videoId': videoId}),
      cancel,
    );
    final qualities = HuyaApi.replayQualities(response.text, status: response.status);
    if (qualities.isEmpty) throw const StreamUnavailable('huya', 'Archive has no permitted rendition');
    return [for (final quality in qualities) HuyaArchiveQuality(quality)];
  }

  Future<LiveResponse> _get(Uri url, CancelToken? cancel) async {
    try {
      final response = await http.send(
        LiveRequest(site: SiteIds.huya, url: url, headers: mediaHeaders, cancel: cancel),
      );
      if (response.status == 404) throw const NotFound('huya', 'Archive not found');
      if (response.status == 401) throw const NeedsLogin('huya', 'Archive requires login');
      if ({403, 429}.contains(response.status)) throw const RiskControl('huya', detail: 'Archive refused');
      if (!response.isSuccess) throw NetworkFailure('huya', 'Archive HTTP ${response.status}');
      if (response.bytes.length > 8388608) throw const ApiChanged('huya', 'Archive response size');
      return response;
    } on TransportFailure {
      throw const NetworkFailure('huya', 'Archive transport failed');
    }
  }

  /// Parses only the official data assignment; unrelated scripts never run.
  static HuyaArchiveList parseList(String html, {required String uid, required int page}) {
    if (html.length > 8388608 || !_id.hasMatch(uid) || page < 1) {
      throw const ApiChanged('huya', 'Archive response bounds');
    }
    final root = HtmlElement.parseFragment(html);
    final script = root.query((e) => e.tag == 'script' && _assignment.hasMatch(e.text));
    final source = script?.text;
    final assignment = source == null ? null : _assignment.firstMatch(source);
    final key = assignment == null ? null : _responseKey.firstMatch(source!.substring(assignment.end));
    if (key == null) throw const ApiChanged('huya', 'Archive list assignment missing');
    final literal = _object(source!.substring(assignment!.end + key.end));
    Object? decoded;
    try {
      decoded = jsonDecode(literal.replaceAll(_metadataFunction, '"_proto":null'));
    } on FormatException {
      throw const ApiChanged('huya', 'Unknown archive metadata');
    }
    if (decoded is! Map || decoded['respHeader'] is! Map || (decoded['respHeader'] as Map)['code'] != 0) {
      throw const ApiChanged('huya', 'Archive list refused');
    }
    final vector = decoded['videoDataList'];
    final rows = vector is Map ? vector['value'] : null;
    if (rows is! List || rows.length > 100) throw const ApiChanged('huya', 'Archive list shape');
    final seen = <String>{};
    final videos = <HuyaArchiveVideo>[];
    for (final row in rows) {
      if (row is! Map || row['videoData'] is! Map) continue;
      final data = row['videoData'] as Map;
      final id = jsonString(data['vid']) ?? '';
      final title = jsonString(data['videoTitle']) ?? '';
      final user = data['userInfo'];
      if (!_id.hasMatch(id) || title.isEmpty || !seen.add(id)) continue;
      // Never attribute a different presenter's video to this requested uid.
      final actual = user is Map ? jsonString(user['uid']) : null;
      if (actual != null && actual != uid) continue;
      final covers = data['covers'];
      videos.add(
        HuyaArchiveVideo(
          id: id,
          title: decodeHtmlEntities(title),
          authorId: uid,
          authorName: user is Map ? jsonString(user['userNick']) ?? '' : '',
          cover: normalizeImageUrl(covers is Map ? covers['cover320'] ?? covers['cover'] : null),
          duration: _duration(data['duration']),
          date: jsonString(row['date']) ?? '',
        ),
      );
    }
    final total = jsonInt(decoded['total']);
    return HuyaArchiveList(
      videos: List.unmodifiable(videos),
      hasMore: rows.isNotEmpty && total != null && page * 10 < total,
    );
  }

  static Duration _duration(Object? raw) {
    final parts = (jsonString(raw) ?? '').split(':');
    if (parts.length != 3) return Duration.zero;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = int.tryParse(parts[2]);
    if (h == null || m == null || s == null || h < 0 || h > 1000 || m < 0 || m > 59 || s < 0 || s > 59) {
      return Duration.zero;
    }
    return Duration(hours: h, minutes: m, seconds: s);
  }

  static String _object(String text) {
    var depth = 0;
    var quote = '';
    var escape = false;
    final start = text.indexOf('{');
    if (start < 0 || text.substring(0, start).trim().isNotEmpty) {
      throw const ApiChanged('huya', 'Archive literal missing');
    }
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (quote.isNotEmpty) {
        if (escape) {
          escape = false;
        } else if (c == r'\') {
          escape = true;
        } else if (c == quote) {
          quote = '';
        }
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '{') {
        if (++depth > 64) throw const ApiChanged('huya', 'Archive nesting');
      } else if (c == '}' && --depth == 0) {
        return text.substring(start, i + 1);
      }
    }
    throw const ApiChanged('huya', 'Truncated archive literal');
  }
}
