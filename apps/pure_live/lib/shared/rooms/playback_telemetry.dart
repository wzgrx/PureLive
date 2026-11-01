import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:live_player/live_player.dart';

/// One lazy sampler per playback session, shared by every visible consumer.
final class PlaybackTelemetry extends ValueNotifier<PlaybackStats?> with WidgetsBindingObserver {
  /// [identity] invalidates a late read after an engine, source or line switch.
  new({required this.read, Object? Function()? identity}) : _identity = identity ?? (() => null), super(null);

  /// Resolves the current native statistics source when a sample is needed.
  final Future<PlaybackStats?> Function() read;
  final Object? Function() _identity;
  final List<double> _downloads = [];
  Timer? _timer;
  bool _reading = false;
  bool _closed = false;
  bool _observing = false;
  bool _foreground = true;
  int _epoch = 0;
  Object? _lastIdentity;

  /// Native evidence is unavailable immediately after its source identity changes.
  PlaybackStats? get current => _lastIdentity == _identity() ? value : null;

  /// Short average of valid samples, including a genuinely measured zero.
  double? get downloadAverage => _downloads.isEmpty ? null : _downloads.reduce((a, b) => a + b) / _downloads.length;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    }
    _start();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _stop();
      if (_observing) WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  void _start() {
    if (_closed || !_foreground || !hasListeners || _timer != null) return;
    unawaited(_sample());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_sample()));
  }

  void _stop() {
    _epoch++;
    _timer?.cancel();
    _timer = null;
    _downloads.clear();
    value = null;
  }

  Future<void> _sample() async {
    if (_closed || _reading || !_foreground || !hasListeners) return;
    _reading = true;
    final epoch = _epoch;
    final identity = _identity();
    if (identity != _lastIdentity) {
      _lastIdentity = identity;
      _downloads.clear();
      value = null;
    }
    PlaybackStats? stats;
    try {
      stats = await read().timeout(const Duration(seconds: 2));
    } on Object {
      stats = null;
    } finally {
      _reading = false;
    }
    if (_closed || epoch != _epoch || identity != _identity() || !_foreground || !hasListeners) return;
    final rate = stats?.downloadBytesPerSecond;
    if (rate == null || !rate.isFinite || rate < 0) {
      _downloads.clear();
    } else {
      _downloads.add(rate);
      if (_downloads.length > 3) _downloads.removeAt(0);
    }
    value = stats;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _start();
    } else {
      _stop();
    }
  }

  @override
  void dispose() {
    _closed = true;
    _stop();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _observing = false;
    super.dispose();
  }
}
