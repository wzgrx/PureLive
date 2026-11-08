import 'package:live_core/live_core.dart';

/// A validated, finite Naver MPEG-TS recording timeline. The URLs are
/// ephemeral playback data and are never persisted with a replay position.
final class ChzzkVodSegments {
  new _(this._template, this._scale, this._start, this._spans);

  final String _template;
  final int _scale;
  final int _start;
  final List<({int ticks, int count})> _spans;

  /// Maximum playlist size accepted by the local relay.
  static const int maxPlaylistBytes = 4 << 20;

  /// Maximum number of media entries retained for one VOD input.
  static const maxSegments = 12000;

  static final _number = RegExp(r'\$Number(?:%0([1-9])d)?\$');
  static final _representationId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
  static final _controls = RegExp(r'[\x00-\x20\x7f]');

  /// Checks the manifest's video/audio, contiguous time axis, signing
  /// template and CDN origin before any segment is passed to the player.
  static ChzzkVodSegments? parse(
    Map<Object?, Object?> track,
    Map<Object?, Object?> variant, {
    required Duration duration,
  }) {
    if ((variant['mimeType'] ?? track['mimeType']) != 'video/mp2t' || _protected(track) || _protected(variant)) {
      return null;
    }
    final codecs = (jsonString(variant['codecs'] ?? track['codecs']) ?? '').split(',').map((s) => s.trim());
    if (!codecs.any((s) => s.startsWith('avc1.')) || !codecs.any((s) => s.startsWith('mp4a.'))) return null;
    final template = variant['segmentTemplate'] ?? track['segmentTemplate'];
    final representation = jsonString(variant['id']);
    if (template is! Map || representation == null || !_representationId.hasMatch(representation)) return null;
    if (template['initialization'] != null ||
        template['initializationAttr'] != null ||
        (jsonInt(template['presentationTimeOffset']) ?? 0) != 0) {
      return null;
    }
    final timescale = jsonInt(template['timescale']);
    final start = jsonInt(template['startNumber']);
    final raw = jsonString(template['media']);
    final timeline = template['segmentTimeline'];
    final sources = variant['baseURL'] ?? track['baseURL'];
    if (timescale == null ||
        timescale < 1 ||
        timescale > 1000000 ||
        start == null ||
        start < 0 ||
        start > 99999999 ||
        raw == null ||
        raw.length > 2048 ||
        _controls.hasMatch(raw) ||
        raw.startsWith('/') ||
        timeline is! Map ||
        timeline['s'] is! List ||
        sources is! List ||
        sources.length != 1 ||
        sources.single is! Map) {
      return null;
    }
    final base = Uri.tryParse(jsonString((sources.single as Map)['value']) ?? '');
    if (!_cdn(base) || base!.hasQuery) return null;
    final replaced = raw.replaceAll(r'$RepresentationID$', representation);
    final placeholders = _number.allMatches(replaced).toList();
    if (placeholders.length != 1 || replaced.replaceFirst(_number, '').contains(r'$')) return null;
    // A sentinel makes URI resolution independent of DASH's percent padding.
    const sentinel = 'pureliveSegmentNumber';
    if (replaced.contains(sentinel) || !replaced.split('?').first.contains(_number)) return null;
    final resolved = base.resolve(replaced.replaceFirst(_number, sentinel));
    if (!_cdn(resolved) ||
        resolved.host != base.host ||
        !resolved.path.endsWith('.ts') ||
        !resolved.path.contains(sentinel)) {
      return null;
    }
    final rows = timeline['s'] as List;
    if (rows.isEmpty || rows.length > maxSegments) return null;
    final spans = <({int ticks, int count})>[];
    var length = 0;
    var total = 0;
    for (final row in rows) {
      if (row is! Map) return null;
      final ticks = jsonInt(row['d']);
      final repeat = row['r'] == null ? 0 : jsonInt(row['r']);
      final at = row['t'] == null ? total : jsonInt(row['t']);
      if (ticks == null ||
          ticks <= 0 ||
          ticks > timescale * 30 ||
          repeat == null ||
          repeat < 0 ||
          repeat >= maxSegments ||
          at != total ||
          length + repeat + 1 > maxSegments) {
        return null;
      }
      spans.add((ticks: ticks, count: repeat + 1));
      length += repeat + 1;
      total += ticks * (repeat + 1);
    }
    if ((duration.inMilliseconds - total * 1000 ~/ timescale).abs() > 10000) return null;
    final urlTemplate = resolved.toString().replaceFirst(sentinel, placeholders.single[0]!);
    // Bound expansion even if the platform returns a large signed query.
    if ((urlTemplate.length + 32) * length > maxPlaylistBytes) return null;
    return ChzzkVodSegments._(urlTemplate, timescale, start, List.unmodifiable(spans));
  }

  static bool _protected(Map<Object?, Object?> row) =>
      row['contentProtection'] != null &&
      (row['contentProtection'] is! List || (row['contentProtection']! as List).isNotEmpty);

  static bool _cdn(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      uri.host.endsWith('.akamaized.net');

  String _url(int number) => _template.replaceFirstMapped(_number, (match) {
    return '$number'.padLeft(int.tryParse(match[1] ?? '') ?? 1, '0');
  });

  /// First permitted segment; its URL is also the loopback input's origin.
  String get firstUrl => _url(_start);

  /// Generates a finite, seekable VOD playlist from the validated timeline.
  String render() {
    final longest = _spans.map((span) => span.ticks).reduce((a, b) => a > b ? a : b);
    final text = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:3')
      ..writeln('#EXT-X-PLAYLIST-TYPE:VOD')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:$_start')
      ..writeln('#EXT-X-TARGETDURATION:${(longest + _scale - 1) ~/ _scale}');
    var number = _start;
    for (final span in _spans) {
      final seconds = (span.ticks / _scale).toStringAsFixed(6);
      for (var i = 0; i < span.count; i++) {
        text
          ..writeln('#EXTINF:$seconds,')
          ..writeln(_url(number++));
      }
    }
    text.writeln('#EXT-X-ENDLIST');
    return text.toString();
  }
}
