import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

/// Serial frame decoding with bounded retained payloads and transport pressure.
/// Small idle frames keep their immediate authentication/heartbeat response.
/// Large frames run outside the UI isolate; queued small frames are charged
/// to the same budget. Overflow explicitly reconnects instead of retaining an
/// unbounded chain or silently claiming every frame was delivered.
final class FrameDecode {
  /// Creates a decoder. Pressure pauses reads at half either hard limit.
  new({
    this.offloadThreshold = 8 * 1024,
    this.maxBacklogBytes = 16 * 1024 * 1024,
    this.maxPendingFrames = 1024,
    this.onPressure,
    this.onOverflow,
  }) : assert(offloadThreshold > 0, 'offloadThreshold must be positive'),
       assert(maxBacklogBytes > 0, 'maxBacklogBytes must be positive'),
       assert(maxPendingFrames > 0, 'maxPendingFrames must be positive');

  /// Frames at least this large are decoded in another isolate.
  final int offloadThreshold;

  /// All retained payloads, including small queued frames and the active one.
  final int maxBacklogBytes;

  /// Bounds queue bookkeeping even when every frame is tiny.
  final int maxPendingFrames;

  /// Pauses or resumes only this transport's incoming subscription.
  final void Function(bool paused)? onPressure;

  /// Requests a visible protocol reconnect after closing this decoder.
  final void Function()? onOverflow;

  final Queue<_QueuedFrame> _queue = Queue();
  int _bytes = 0;
  int _activeBytes = 0;
  bool _active = false;
  bool _closed = false;
  bool _pressured = false;
  Future<void>? _drainFuture;

  /// Current retained payload bytes, for pressure diagnostics.
  int get pendingBytes => _bytes;

  /// Current retained frames, including the active frame.
  int get pendingFrames => _queue.length + (_active ? 1 : 0);

  /// Completes after any current decoder has released its payload.
  Future<void> get idle => _drainFuture ?? Future.value();

  /// Reads and dispatches frames in wire order while the decoder is current.
  void run<T>(List<int> data, T Function(List<int> data) decode, void Function(T result) dispatch) {
    if (_closed) return;
    if (data.length > maxBacklogBytes - _bytes || pendingFrames >= maxPendingFrames) {
      close();
      final overflow = onOverflow;
      if (overflow != null) {
        overflow();
        return;
      }
      throw StateError('Danmaku decode backlog limit exceeded');
    }
    if (pendingFrames == 0 && data.length < offloadThreshold) {
      dispatch(decode(data));
      return;
    }
    _bytes += data.length;
    _queue.add(
      _QueuedFrame(data.length, () async {
        final result = data.length >= offloadThreshold ? await _offload(data, decode) : decode(data);
        if (!_closed) dispatch(result);
      }),
    );
    _pressure();
    _drainFuture ??= Future<void>.microtask(_drain);
  }

  Future<void> _drain() async {
    try {
      while (!_closed && _queue.isNotEmpty) {
        final frame = _queue.removeFirst();
        _active = true;
        _activeBytes = frame.bytes;
        try {
          await frame.read();
        } on Object catch (error, stack) {
          Zone.current.handleUncaughtError(error, stack);
        } finally {
          _bytes -= frame.bytes;
          _activeBytes = 0;
          _active = false;
          _pressure();
        }
      }
    } finally {
      _drainFuture = null;
    }
  }

  void _pressure() {
    final next = !_closed && (_bytes >= (maxBacklogBytes + 1) ~/ 2 || pendingFrames >= (maxPendingFrames + 1) ~/ 2);
    if (next == _pressured) return;
    _pressured = next;
    onPressure?.call(next);
  }

  /// Drops queued references and suppresses any late offload result.
  void close() {
    if (_closed) return;
    _closed = true;
    _queue.clear();
    _bytes = _activeBytes;
    _pressure();
  }

  static Future<T> _offload<T>(List<int> data, T Function(List<int> data) decode) async {
    try {
      return await Isolate.run(() => decode(data));
    } on Object {
      return decode(data);
    }
  }
}

final class _QueuedFrame {
  const new(this.bytes, this.read);
  final int bytes;
  final Future<void> Function() read;
}
