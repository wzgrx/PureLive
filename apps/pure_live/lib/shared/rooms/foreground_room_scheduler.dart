import 'dart:async';
import 'dart:developer';

import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';

/// Runs explicit room appointments while an eligible app window is active.
/// Navigation remains owned by the app; this object never tries to wake a
/// stopped process or bypass the operating system's background limits.
final class ForegroundRoomScheduler {
  /// Creates a stopped scheduler. [openRoom] completes after navigation is
  /// applied; the app owns replacing any previous scheduled room.
  new({
    required this.schedules,
    required this.claim,
    required this.releaseClaim,
    required this.canOpen,
    required this.openRoom,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Current durable appointments.
  final Stream<List<RoomOpenSchedule>> schedules;

  /// Atomically consumes one due occurrence.
  final Future<RoomOpenSchedule?> Function(DateTime now) claim;

  /// Makes an occurrence eligible again if a route cannot safely start.
  final Future<void> Function(RoomOpenSchedule task, DateTime now) releaseClaim;

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
    _timer?.cancel();
    _timer = null;
    if (_disposed || !_foreground || _opening) return;
    final now = _now();
    Duration? delay;
    for (final item in _items) {
      if (!item.enabled) continue;
      var due = item.dueAt(now);
      if (item.isDueAt(now)) {
        delay = const Duration(seconds: 1);
        break;
      }
      if (!due.isAfter(now)) {
        if (item.onceAt != null) continue;
        final tomorrow = now.isUtc
            ? DateTime.utc(now.year, now.month, now.day + 1)
            : DateTime(now.year, now.month, now.day + 1);
        due = item.dueAt(tomorrow);
      }
      final wait = due.difference(now);
      if (delay == null || wait < delay) delay = wait;
    }
    if (delay == null) return;
    // Re-check local wall time occasionally without polling each second all day.
    final next = delay > const Duration(minutes: 1) ? const Duration(minutes: 1) : delay;
    _timer = Timer(next, () => unawaited(_check()));
  }

  Future<void> _check() async {
    if (_disposed || !_foreground || _opening) return;
    if (!canOpen()) {
      _syncTimer();
      return;
    }
    final now = _now();
    if (!_items.any((item) => item.isDueAt(now))) {
      _syncTimer();
      return;
    }
    _opening = true;
    _syncTimer();
    try {
      final task = await claim(now);
      if (task != null) {
        if (!_disposed && _foreground && canOpen()) {
          await openRoom(task.room);
        } else {
          await releaseClaim(task, now);
        }
      }
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
