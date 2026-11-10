import 'dart:async';
import 'dart:isolate';

/// The frames of one socket, decoded without holding up the isolate that
/// paints (D04.2 c1).
///
/// A platform reads a frame with its own pure function and then dispatches
/// the answer (its messages, its acknowledgement). Reading a burst frame is
/// the expensive part — Bilibili inflates it with a pure Dart brotli, Douyin
/// with gzip and a protobuf per message — and it used to happen where the
/// frame arrived, so the frames behind it waited and the danmaku on screen
/// jumped (docs/D-弹幕/D04-数据流和性能/D04.2-弹幕高峰滚动卡顿/README.md).
///
/// A frame shorter than [offloadThreshold] while nothing else waits is read
/// here, exactly as before; a longer one, or one that comes while a read is
/// still going, is read in another isolate. The order never changes: every
/// frame behind an offloaded one waits for it, so a platform's
/// acknowledgement still answers the frame the server expects and two frames
/// never dispatch over each other.
///
/// [Isolate.run] can fail (an isolate that will not start, a closure holding
/// what cannot be sent); the frame is then read here instead, which is what
/// happened for every frame before. So is a frame past [maxBacklogBytes] of
/// waiting ones: when the socket is read faster than it can be decoded,
/// decoding it here is no worse than before, while a line of frames waiting
/// for one isolate would only grow.
final class FrameDecode {
  /// Creates the decoder; [offloadThreshold] is the frame size below which a
  /// frame is read on the calling isolate while nothing waits.
  new({this.offloadThreshold = 8 * 1024, this.maxBacklogBytes = 16 * 1024 * 1024});

  /// Frames this much shorter, while nothing waits, are read on the calling
  /// isolate: an answer to one of them goes out in the same callback, as it
  /// did before this existed.
  final int offloadThreshold;

  /// Most bytes a frame may wait behind the ones being read; past it a frame
  /// is read on the calling isolate, so the waiting bytes stay bounded.
  final int maxBacklogBytes;

  Future<void> _chain = Future<void>.value();
  int _waiting = 0;
  int _backlog = 0;

  /// Reads [data] with [decode] and gives the result to [dispatch], in the
  /// order the calls came in. What [dispatch] throws reaches the zone as an
  /// uncaught error, as it did when the socket listener called it itself; a
  /// frame that fails does not stop the frames behind it.
  void run<T>(List<int> data, T Function(List<int> data) decode, void Function(T result) dispatch) {
    if (_waiting == 0 && data.length < offloadThreshold) {
      dispatch(decode(data));
      return;
    }
    final offload = data.length >= offloadThreshold && _backlog + data.length <= maxBacklogBytes;
    _waiting++;
    if (offload) _backlog += data.length;
    _chain = _chain.then((_) => _read(data, decode, dispatch, offload: offload));
  }

  Future<void> _read<T>(
    List<int> data,
    T Function(List<int> data) decode,
    void Function(T result) dispatch, {
    required bool offload,
  }) async {
    try {
      dispatch(offload ? await _offload(data, decode) : decode(data));
    } on Object catch (error, stack) {
      Zone.current.handleUncaughtError(error, stack);
    } finally {
      _waiting--;
      if (offload) _backlog -= data.length;
    }
  }

  /// [decode] of [data] in another isolate; in this one when that fails.
  static Future<T> _offload<T>(List<int> data, T Function(List<int> data) decode) async {
    try {
      return await Isolate.run(() => decode(data));
    } on Object {
      return decode(data);
    }
  }
}
