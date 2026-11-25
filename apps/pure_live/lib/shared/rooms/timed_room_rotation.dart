import 'dart:async';
import 'dart:math';

import 'package:live_core/live_core.dart';

/// The order of a user-initiated viewing session.
enum RoomRotationOrder {
  /// Play in the saved order, wrapping at the end.
  ordered,

  /// Visit each room once per cycle, without repeating the current room.
  shuffled,
}

/// A single owner for room switching timers.
///
/// A room earns a full interval only while the owner reports active
/// playback. Pausing, a covered route, or switching manually resets the
/// interval. A dispatched switch is never followed by another timer until
/// the owner observes the replacement.
final class TimedRoomRotation {
  /// Creates a stopped rotator. [switchTo] reports whether the owner
  /// accepted a request, not whether the remote media opened.
  new({required this.switchTo, Random? random}) : _random = random ?? Random();

  /// Dispatches one eligible room replacement.
  final bool Function(LiveRoom room) switchTo;
  final Random _random;
  Timer? _timer;
  List<LiveRoom> _rooms = const [];
  final _visited = <String>{};
  Duration _interval = const Duration(minutes: 1);
  RoomRotationOrder _order = RoomRotationOrder.ordered;
  LiveRoom? _current;
  bool _eligible = false;
  bool _dispatching = false;
  bool _disposed = false;
  int _generation = 0;

  /// Whether the user started a rotation with more than one room.
  bool get active => _rooms.length > 1;

  /// Begins a fresh session from a saved snapshot. No timer is armed until
  /// [observe] confirms that the current room is playing.
  void start(List<LiveRoom> rooms, {required Duration interval, required RoomRotationOrder order}) {
    if (_disposed) return;
    if (interval < const Duration(seconds: 5) || interval > const Duration(hours: 24)) {
      throw ArgumentError.value(interval, 'interval', 'must be between five seconds and one day');
    }
    stop();
    final seen = <String>{};
    _rooms = List.unmodifiable(rooms.where((room) => seen.add(room.identityKey)));
    _interval = interval;
    _order = order;
  }

  /// Reports playback and route eligibility. Repeated snapshots for one
  /// playing room keep the original timer instead of extending it.
  void observe(LiveRoom room, {required bool eligible}) {
    if (_disposed || !active) return;
    final changed = !_currentSafeIdentity(room);
    final allowed = eligible && _rooms.any(room.hasSameIdentity);
    if (changed || allowed != _eligible) {
      _timer?.cancel();
      _timer = null;
      _generation++;
    }
    if (changed) {
      _current = room;
      _dispatching = false;
    }
    _eligible = allowed;
    if (allowed) _visited.add(room.identityKey);
    _arm();
  }

  bool _currentSafeIdentity(LiveRoom room) => _current?.hasSameIdentity(room) ?? false;

  void _arm() {
    if (!active || !_eligible || _dispatching || _timer != null) return;
    final generation = _generation;
    _timer = Timer(_interval, () {
      _timer = null;
      if (_disposed || generation != _generation || !_eligible || _dispatching || !active) return;
      final current = _current;
      if (current == null) return;
      final next = _next(current);
      _dispatching = true;
      if (!switchTo(next)) {
        _dispatching = false;
        _arm();
      }
    });
  }

  LiveRoom _next(LiveRoom current) {
    if (_order == RoomRotationOrder.ordered) {
      final at = _rooms.indexWhere(current.hasSameIdentity);
      return _rooms[(at + 1) % _rooms.length];
    }
    var available = _rooms.where((r) => !current.hasSameIdentity(r) && !_visited.contains(r.identityKey)).toList();
    if (available.isEmpty) {
      _visited
        ..clear()
        ..add(current.identityKey);
      available = _rooms.where((r) => !current.hasSameIdentity(r)).toList();
    }
    return available[_random.nextInt(available.length)];
  }

  /// Stops the session immediately, including a timer awaiting the next room.
  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _rooms = const [];
    _current = null;
    _eligible = false;
    _dispatching = false;
    _visited.clear();
  }

  /// Permanently releases the route's rotator.
  void dispose() {
    stop();
    _disposed = true;
  }
}
