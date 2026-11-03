import 'package:live_net/live_net.dart';

/// Resolves a fresh, segment-anchored entry into a completed Huya recording.
abstract interface class HuyaArchiveAnchorSource {
  /// Null means an ordinary continuous playlist can use the native timeline.
  Future<HuyaArchiveAnchor?> anchor(String url, Duration at, {CancelToken? cancel});
}

/// A memory-only playlist and its mapping back to the recording's full clock.
final class HuyaArchiveAnchor {
  /// The first retained segment starts at [offset] on the original timeline.
  const new({required this.playlist, required this.offset, required this.start, required this.duration});

  /// Absolute segment URLs; never persisted as viewing history.
  final String playlist;

  /// Original time represented by native position zero.
  final Duration offset;

  /// A small seek within the retained first one or two segments.
  final Duration start;

  /// Sum of every original EXTINF, including the removed prefix.
  final Duration duration;

  /// Keeps the target segment and at most one preceding segment in its epoch.
  /// FFmpeg can otherwise scan indefinitely toward a pre-discontinuity PTS.
  static HuyaArchiveAnchor? parse(String text, {required Uri source, required Duration at}) {
    if (text.length > 8388608 || !text.startsWith('#EXTM3U')) throw const FormatException('Archive playlist bounds');
    final entries = <({int offset, int duration, int epoch, List<String> lines})>[];
    final pending = <String>[];
    var total = 0;
    var duration = 0;
    var epoch = 0;
    var sequence = 0;
    var ended = false;
    var discontinuous = false;
    String? version;
    String? target;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line == '#EXTM3U') continue;
      if (line.startsWith('#EXTINF:')) {
        final value = double.tryParse(line.substring(8).split(',').first);
        if (value == null || !value.isFinite || value <= 0 || value > 3600 || duration != 0) {
          throw const FormatException('Invalid archive segment duration');
        }
        duration = (value * Duration.microsecondsPerSecond).round();
        pending.add(line);
      } else if (line == '#EXT-X-DISCONTINUITY') {
        epoch++;
        discontinuous = true;
        pending.add(line);
      } else if (line.startsWith('#EXT-X-DISCONTINUITY-SEQUENCE:')) {
        epoch = int.parse(line.substring(line.indexOf(':') + 1));
      } else if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = int.parse(line.substring(line.indexOf(':') + 1));
      } else if (line.startsWith('#EXT-X-VERSION:')) {
        version = line;
      } else if (line.startsWith('#EXT-X-TARGETDURATION:')) {
        target = line;
      } else if (line == '#EXT-X-ENDLIST') {
        ended = true;
      } else if (line.startsWith('#EXT-X-PLAYLIST-TYPE:')) {
        if (line != '#EXT-X-PLAYLIST-TYPE:VOD') throw const FormatException('Not a completed recording');
      } else if (line.startsWith('#EXT-X-PROGRAM-DATE-TIME:')) {
        pending.add(line);
      } else if (line.startsWith('#')) {
        // Never discard encryption, byte ranges, initialization maps or a master.
        throw const FormatException('Unsupported archive playlist feature');
      } else {
        final uri = source.resolve(line);
        if (duration <= 0 ||
            ended ||
            entries.length >= 50000 ||
            !{'http', 'https'}.contains(uri.scheme) ||
            uri.userInfo.isNotEmpty ||
            uri.host != source.host ||
            uri.port != source.port) {
          throw const FormatException('Invalid archive segment');
        }
        entries.add((offset: total, duration: duration, epoch: epoch, lines: [...pending, uri.toString()]));
        total += duration;
        duration = 0;
        pending.clear();
      }
    }
    if (!ended || entries.isEmpty || duration != 0 || target == null || sequence < 0 || epoch < 0) {
      throw const FormatException('Incomplete archive playlist');
    }
    if (!discontinuous || at <= Duration.zero) return null;
    final bounded = at.inMicroseconds.clamp(0, total - 1);
    var index = entries.indexWhere((e) => bounded < e.offset + e.duration);
    if (index > 0 && entries[index - 1].epoch == entries[index].epoch) index--;
    final first = entries[index];
    final body = StringBuffer('#EXTM3U\n')
      ..writeln(version ?? '#EXT-X-VERSION:3')
      ..writeln(target)
      ..writeln('#EXT-X-PLAYLIST-TYPE:VOD')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:${sequence + index}')
      ..writeln('#EXT-X-DISCONTINUITY-SEQUENCE:${first.epoch}');
    for (var i = index; i < entries.length; i++) {
      for (final line in entries[i].lines) {
        if (i == index && line == '#EXT-X-DISCONTINUITY') continue;
        body.writeln(line);
      }
    }
    body.writeln('#EXT-X-ENDLIST');
    return HuyaArchiveAnchor(
      playlist: body.toString(),
      offset: Duration(microseconds: first.offset),
      start: Duration(microseconds: bounded - first.offset),
      duration: Duration(microseconds: total),
    );
  }
}
