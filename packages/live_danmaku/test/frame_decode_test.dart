import 'dart:async';
import 'dart:isolate';

import 'package:live_danmaku/src/frame_decode.dart';
import 'package:test/test.dart';

/// A frame of [size] bytes.
List<int> _frame(int size) => List<int>.filled(size, 7);

/// [FrameDecode] with a threshold low enough for a test frame to be a burst.
FrameDecode _small({int backlog = 16 * 1024 * 1024}) => FrameDecode(offloadThreshold: 32, maxBacklogBytes: backlog);

/// The length of the frame, as the platform decoders return their messages:
/// the value crosses back over the isolate boundary, so a burst frame read
/// elsewhere still arrives with the same result.
int _length(List<int> frame) => frame.length;

void main() {
  group('FrameDecode (D04.2 c1)', () {
    test('a frame below the threshold while nothing waits is read where it arrived', () {
      final frames = FrameDecode();
      final order = <String>[];
      frames.run(_frame(16), _length, (result) => order.add('read $result'));
      expect(order, ['read 16'], reason: 'its answer goes out in the same callback, as before');
    });

    test('a burst frame is not read on this isolate: its dispatch comes later, with the same result', () async {
      final frames = _small();
      final read = Completer<int>();
      var dispatched = false;
      frames.run(_frame(64), _length, (result) {
        dispatched = true;
        read.complete(result);
      });
      expect(dispatched, isFalse, reason: 'a frame of the threshold size is read off this isolate');
      expect(await read.future, 64);
    });

    test('a small frame that comes behind a burst waits for it', () async {
      final frames = _small();
      final order = <int>[];
      final both = Completer<void>();
      void dispatch(int result) {
        order.add(result);
        if (order.length == 2) both.complete();
      }

      frames
        ..run(_frame(64), _length, dispatch)
        ..run(_frame(4), _length, dispatch);
      await both.future;
      expect(order, [64, 4], reason: 'frames dispatch in the order they came, whatever read them');
    });

    test('a decoder that cannot be sent is read on this isolate instead', () async {
      final frames = _small();
      final port = ReceivePort();
      addTearDown(port.close);
      final read = Completer<String>();
      frames.run(
        // The closure holds a port, which no isolate accepts: the offload
        // fails and the same decoder runs here.
        _frame(64),
        (frame) {
          port.sendPort.send(frame.length);
          return 'read ${frame.length}';
        },
        read.complete,
      );
      expect(await read.future, 'read 64');
      expect(await port.first, 64);
    });

    test('a frame whose dispatch throws does not stop the ones behind it', () async {
      final frames = _small();
      final errors = <Object>[];
      final second = Completer<int>();
      await runZonedGuarded(() async {
        frames
          ..run(_frame(64), _length, (_) => throw StateError('dispatch failed'))
          ..run(_frame(4), _length, second.complete);
        await second.future;
      }, (error, _) => errors.add(error));
      expect(errors, [isStateError]);
      expect(await second.future, 4);
    });

    test('a whole run of bursts arrives in order and leaves the line empty', () async {
      final frames = _small(backlog: 100);
      final order = <int>[];
      final ten = Completer<void>();
      for (var i = 0; i < 10; i++) {
        frames.run(_frame(64), _length, (result) {
          order.add(result);
          if (order.length == 10) ten.complete();
        });
      }
      await ten.future;
      expect(order, List.filled(10, 64), reason: 'the backlog only changes where a frame is read, not what arrives');
      var atOnce = false;
      frames.run(_frame(4), _length, (_) => atOnce = true);
      expect(atOnce, isTrue, reason: 'nothing waits anymore, so the small frame is read here again');
    });

    test("a decoder that throws is the frame's own: it reaches the zone and the line goes on", () async {
      final frames = _small();
      final errors = <Object>[];
      final second = Completer<int>();
      await runZonedGuarded(() async {
        frames
          ..run<List<int>>(_frame(64), (frame) => throw const FormatException('bad frame'), (result) => result.length)
          ..run(_frame(4), _length, second.complete);
        await second.future;
      }, (error, _) => errors.add(error));
      expect(errors, [isFormatException], reason: 'a frame that cannot be read is what the listener used to see');
      expect(await second.future, 4);
    });
  });
}
