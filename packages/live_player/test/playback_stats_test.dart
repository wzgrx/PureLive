import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';

void main() {
  group('G01.5: playback stats', () {
    test('small native builds keep codec names when long descriptions are absent', () async {
      final stats = await readPlaybackStats(
        (name) async => switch (name) {
          'video-format' => 'h264',
          'audio-codec-name' => 'aac',
          _ => '',
        },
      );
      expect(stats.videoCodec, 'h264');
      expect(stats.audioCodec, 'aac');
    });

    test('reads the properties the playback information panel shows', () async {
      final properties = {
        'video-params/w': '2560',
        'video-params/h': '1440',
        'video-format': 'hevc',
        'video-codec': 'hevc (Main) / H.265',
        'metadata/by-key/encoder': 'obs-output module (libobs version 32.2.1)',
        'audio-params/samplerate': '48000',
        'audio-params/channel-count': '2',
        'audio-bitrate': '160000',
        'audio-codec': 'aac (LC)',
        'frame-drop-count': '2',
        'estimated-frame-number': '503',
        'demuxer-cache-duration': '6.40',
        'cache-speed': '375000',
        'mpv-version': 'mpv 0.41.0',
        'ffmpeg-version': '9.0.2',
      };
      final stats = await readPlaybackStats((property) async => properties[property] ?? '');
      expect(stats.width, 2560);
      expect(stats.height, 1440);
      expect(stats.videoFormat, 'hevc');
      expect(stats.videoCodec, 'hevc (Main) / H.265');
      expect(stats.encoder, 'obs-output module (libobs version 32.2.1)');
      expect(stats.sampleRate, 48000);
      expect(stats.channels, 2);
      expect(stats.audioBitrate, 160000);
      expect(stats.audioCodec, 'aac (LC)');
      expect(stats.droppedFrames, 2);
      expect(stats.decodedFrames, 503);
      expect(stats.bufferSeconds, 6.4);
      expect(stats.downloadBytesPerSecond, 375000);
      expect(stats.mpvVersion, 'mpv 0.41.0');
      expect(stats.ffmpegVersion, '9.0.2');
    });

    test('a missing, blank, malformed or failed property is null', () async {
      final stats = await readPlaybackStats((property) async {
        if (property == 'video-params/w') throw StateError('no native player');
        return switch (property) {
          'video-params/h' => '  ',
          'audio-params/samplerate' => 'not a number',
          'audio-params/channel-count' => '-1',
          'video-format' => '  h264  ',
          _ => '',
        };
      });
      expect(stats.width, isNull);
      expect(stats.height, isNull);
      expect(stats.sampleRate, isNull);
      expect(stats.channels, isNull);
      expect(stats.videoFormat, 'h264', reason: 'a present string is trimmed, not parsed');
      expect(stats.encoder, isNull);
      expect(stats.droppedFrames, isNull);
      expect(stats.decodedFrames, isNull);
      expect(stats.bufferSeconds, isNull);
      expect(stats.downloadBytesPerSecond, isNull);
    });

    test('a property that never answers times out; the rest of the snapshot still arrives', () {
      fakeAsync((async) {
        PlaybackStats? stats;
        unawaited(
          readPlaybackStats((property) async {
            if (property == 'video-params/w') return await Completer<String>().future;
            return property == 'video-format' ? 'h264' : '';
          }, timeout: const Duration(seconds: 1)).then((value) => stats = value),
        );
        async.elapse(const Duration(seconds: 2));
        expect(stats, isNotNull);
        final value = stats!;
        expect(value.width, isNull);
        expect(value.videoFormat, 'h264');
      });
    });

    test('the encoder comes from metadata/by-key first, else the metadata list', () async {
      final direct = await readPlaybackStats((property) async {
        return switch (property) {
          'metadata/by-key/encoder' => 'obs-output module (libobs version 32.2.1)',
          'metadata' => 'encoder=ignored',
          _ => '',
        };
      });
      expect(direct.encoder, 'obs-output module (libobs version 32.2.1)');

      final list = await readPlaybackStats((property) async {
        return switch (property) {
          'metadata' => 'title=Room\nEncoder=obs-output module (libobs version 32.2.1)\n',
          _ => '',
        };
      });
      expect(list.encoder, 'obs-output module (libobs version 32.2.1)');

      final none = await readPlaybackStats((property) async => '');
      expect(none.encoder, isNull);
    });

    test('dropped and decoded frames fall back to the decoder and the frame count', () async {
      final stats = await readPlaybackStats((property) async {
        return switch (property) {
          'frame-drop-count' => '',
          'decoder-frame-drop-count' => '3',
          'estimated-frame-number' => '',
          'estimated-frame-count' => '100',
          _ => '',
        };
      });
      expect(stats.droppedFrames, 3);
      expect(stats.decodedFrames, 100);

      final zero = await readPlaybackStats((property) async {
        return switch (property) {
          'frame-drop-count' => '0',
          'estimated-frame-number' => '0',
          _ => '',
        };
      });
      expect(zero.droppedFrames, 0);
      expect(zero.decodedFrames, 0);
    });

    test('an engine without a native player reports no values instead of throwing', () async {
      final stats = await readPlaybackStats((property) async => throw StateError('disposed'));
      expect(stats.width, isNull);
      expect(stats.encoder, isNull);
      expect(stats.mpvVersion, isNull);
    });
  });
}
