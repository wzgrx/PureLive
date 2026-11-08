import 'dart:async';
import 'dart:developer';

import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';

/// Runs explicit room appointments while an eligible app window is active.
/// Navigation remains owned by the app; this object never tries to wake a
/// stopped process or bypass the operating system's background limits.
final class ForegroundRoomScheduler {
  /// Creates a stopped scheduler. [openRoom] completes after the scheduled
  /// page closes so overlapping appointments do not stack player pages.
  new({
    required this.schedules,
    required this.claim,
    required this.canOpen,
    required this.openRoom,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Current durable appointments.
  final Stream<List<RoomOpenSchedule>> schedules;

  /// Atomically consumes one due occurrence.
  final Future<RoomOpenSchedule?> Function(DateTime now) claim;

  /// Whether the window and navigation state allow an explicit room open.
  final bool Function() canOpen;

  /// Opens the new page on the existing navigation stack.
  final Future<void> Function(LiveRoom room) openRoom;
  final DateTime Function() _now;
  StreamSubscription<List<RoomOpenSchedule>>? _subscription;
  List<RoomOpenSchedule> _items = const [];
  Timer? _timer;
  bool _foreground = false;
  bool _opening = false;
  bool _disposed = false;

  /// Observes the app store. No polling is needed when no task can run.
  void start() {
    if (_disposed || _subscription != null) return;
    _subscription = schedules.listen(
      (items) {
        _items = items;
        _syncTimer();
      },
      onError: (Object error, StackTrace _) {
        log('Room schedule watch failed: ${error.runtimeType}', name: 'RoomSchedule');
      },
    );
  }

  /// Tracks the operating system's foreground state.
  void setForeground({required bool value}) {
    if (_disposed) return;
    _foreground = value;
    _syncTimer();
  }

  void _syncTimer() {
    final now = _now();
    final pending = _items.any((item) {
      final once = item.onceAt;
      return item.enabled &&
          (once == null || item.lastOccurrence == null && !now.isAfter(once.add(const Duration(minutes: 2))));
    });
    if (_disposed || !_foreground || _opening || !pending) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_check()));
  }

  Future<void> _check() async {
    if (_disposed || !_foreground || _opening || !canOpen()) return;
    final now = _now();
    if (!_items.any((item) => item.isDueAt(now))) {
      _syncTimer();
      return;
    }
    _opening = true;
    _syncTimer();
    try {
      final task = await claim(now);
      if (task != null && !_disposed && _foreground && canOpen()) await openRoom(task.room);
    } on Object catch (error) {
      log('Room schedule dispatch failed: ${error.runtimeType}', name: 'RoomSchedule');
    } finally {
      _opening = false;
      _syncTimer();
    }
  }

  /// Stops observing and cancels the pending timer.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_subscription?.cancel());
  }
}
