import 'dart:convert';

import 'package:meta/meta.dart';

/// How long one native property may take in [readPlaybackStats].
const Duration playbackStatsTimeout = Duration(milliseconds: 500);

/// One read-only snapshot of what mpv plays, for the live room's playback
/// information panel. Every value is optional: a property the platform or
/// the mpv build does not provide is null, and the panel shows “—”.
@immutable
final class PlaybackStats {
  /// Creates a snapshot.
  const new({
    this.width,
    this.height,
    this.videoFormat,
    this.videoCodec,
    this.encoder,
    this.sampleRate,
    this.channels,
    this.audioBitrate,
    this.audioCodec,
    this.droppedFrames,
    this.decodedFrames,
    this.bufferSeconds,
    this.downloadBytesPerSecond,
    this.mpvVersion,
    this.ffmpegVersion,
  });

  /// Coded video width (`video-params/w`), pixels.
  final int? width;

  /// Coded video height (`video-params/h`), pixels.
  final int? height;

  /// Short video format (`video-format`: `h264`, `hevc`, `av1`, …).
  final String? videoFormat;

  /// The video description (`video-codec`), falling back to its short format.
  final String? videoCodec;

  /// The encoder the streamer wrote into the stream's metadata
  /// (`metadata/by-key/encoder`; OBS sends `obs-output module …`).
  final String? encoder;

  /// Audio sample rate (`audio-params/samplerate`), Hz.
  final int? sampleRate;

  /// Audio channel count (`audio-params/channel-count`).
  final int? channels;

  /// Estimated audio bitrate (`audio-bitrate`), bits a second.
  final int? audioBitrate;

  /// The audio description (`audio-codec`), falling back to its short name.
  final String? audioCodec;

  /// Frames dropped by the renderer (`frame-drop-count`, else the decoder's
  /// `decoder-frame-drop-count`).
  final int? droppedFrames;

  /// Frames decoded so far (`estimated-frame-number`, else
  /// `estimated-frame-count`).
  final int? decodedFrames;

  /// Seconds of media in the demuxer cache (`demuxer-cache-duration`).
  final double? bufferSeconds;

  /// Bytes a second mpv reads from the stream (`cache-speed`).
  final double? downloadBytesPerSecond;

  /// The mpv build (`mpv-version`).
  final String? mpvVersion;

  /// The FFmpeg build (`ffmpeg-version`).
  final String? ffmpegVersion;
}

/// An engine that can take a [PlaybackStats] snapshot on demand. The live
/// room's panel polls it while open; nothing reads it otherwise.
abstract interface class PlaybackStatsSource {
  /// Reads one snapshot. Never throws: unavailable properties are null.
  Future<PlaybackStats> readStats();
}

/// Reads one [PlaybackStats] through [read] (a native property reader).
///
/// Each property is read with [timeout]; a missing, blank, malformed or
/// failed one is null. The frame rate is not read here: the session already
/// exposes it as `PlaybackState.frameRate`.
Future<PlaybackStats> readPlaybackStats(
  Future<String> Function(String property) read, {
  Duration timeout = playbackStatsTimeout,
}) async {
  Future<String?> value(String property) async {
    try {
      final text = (await read(property).timeout(timeout)).trim();
      return text.isEmpty ? null : text;
    } on Object {
      return null;
    }
  }

  final values = await Future.wait<String?>([
    value('video-params/w'),
    value('video-params/h'),
    value('video-format'),
    value('video-codec'),
    value('audio-params/samplerate'),
    value('audio-params/channel-count'),
    value('audio-bitrate'),
    value('audio-codec'),
    value('frame-drop-count'),
    value('decoder-frame-drop-count'),
    value('estimated-frame-number'),
    value('estimated-frame-count'),
    value('demuxer-cache-duration'),
    value('cache-speed'),
    value('mpv-version'),
    value('ffmpeg-version'),
    value('audio-codec-name'),
  ]);
  String? at(int index) => values[index];
  return PlaybackStats(
    width: _positiveInt(at(0)),
    height: _positiveInt(at(1)),
    videoFormat: at(2),
    videoCodec: at(3) ?? at(2),
    encoder: await _encoder(value),
    sampleRate: _positiveInt(at(4)),
    channels: _positiveInt(at(5)),
    audioBitrate: _positiveInt(at(6)),
    audioCodec: at(7) ?? at(16),
    droppedFrames: _nonNegativeInt(at(8)) ?? _nonNegativeInt(at(9)),
    decodedFrames: _nonNegativeInt(at(10)) ?? _positiveInt(at(11)),
    bufferSeconds: _nonNegativeDouble(at(12)),
    downloadBytesPerSecond: _nonNegativeDouble(at(13)),
    mpvVersion: at(14),
    ffmpegVersion: at(15),
  );
}

/// The streamer's encoder: `metadata/by-key/encoder` first, else the same
/// key read out of the whole `metadata` list (names are case-insensitive).
Future<String?> _encoder(Future<String?> Function(String property) value) async {
  final direct = await value('metadata/by-key/encoder');
  if (direct != null) return direct;
  final metadata = await value('metadata');
  if (metadata == null) return null;
  for (final line in const LineSplitter().convert(metadata)) {
    final match = RegExp(r'^\s*([^=:]+?)\s*[=:]\s*(.*)$').firstMatch(line);
    if (match == null || match.group(1)!.trim().toLowerCase() != 'encoder') continue;
    final encoder = match.group(2)!.trim();
    if (encoder.isNotEmpty) return encoder;
  }
  return null;
}

int? _positiveInt(String? text) {
  final value = _number(text);
  if (value == null || value <= 0) return null;
  return value.isFinite ? value.round() : null;
}

int? _nonNegativeInt(String? text) {
  final value = _number(text);
  if (value == null || value < 0) return null;
  return value.isFinite ? value.round() : null;
}

double? _nonNegativeDouble(String? text) {
  final value = _number(text);
  if (value == null || value < 0 || !value.isFinite) return null;
  return value;
}

double? _number(String? text) {
  if (text == null) return null;
  final value = num.tryParse(text.trim());
  return value == null || !value.isFinite ? null : value.toDouble();
}
