import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_store/src/database.dart';

/// A user-entered room appointment. The daily form follows local wall time;
/// a countdown becomes a single absolute deadline.
final class RoomOpenSchedule {
  /// One reminder or foreground open at [onceAt].
  const new once({required this.id, required this.room, required DateTime at, this.enabled = true, this.lastOccurrence})
    : onceAt = at,
      dailyMinute = null;

  /// A local time in minutes after midnight, once per local date.
  const new daily({required this.id, required this.room, required int minute, this.enabled = true, this.lastOccurrence})
    : dailyMinute = minute,
      onceAt = null;

  /// A stable identifier within this database.
  final String id;

  /// The room identity; the live URL must be resolved when opening.
  final LiveRoom room;

  /// The absolute deadline of a countdown, or null for a daily schedule.
  final DateTime? onceAt;

  /// Local minutes after midnight, or null for a countdown.
  final int? dailyMinute;

  /// False for schedules explicitly paused.
  final bool enabled;

  /// The last consumed date/deadline, to avoid reopening after restarts.
  final String? lastOccurrence;

  /// This local day's deadline, or the one-time deadline.
  DateTime dueAt(DateTime now) {
    if (onceAt case final at?) return at;
    final minute = dailyMinute!;
    return now.isUtc
        ? DateTime.utc(now.year, now.month, now.day, minute ~/ 60, minute % 60)
        : DateTime(now.year, now.month, now.day, minute ~/ 60, minute % 60);
  }

  /// Whether this occurrence can be acted on now.
  bool isDueAt(DateTime now) {
    if (!enabled) return false;
    final due = dueAt(now);
    return !now.isBefore(due) &&
        now.difference(due) <= const Duration(minutes: 2) &&
        lastOccurrence != _occurrence(due);
  }

  String _occurrence(DateTime due) =>
      onceAt != null ? 'once:${due.millisecondsSinceEpoch}' : 'day:${due.year}-${due.month}-${due.day}';

  RoomOpenSchedule _claimed(String? occurrence) {
    if (onceAt case final at?) {
      return RoomOpenSchedule.once(id: id, room: room, at: at, enabled: enabled, lastOccurrence: occurrence);
    }
    return RoomOpenSchedule.daily(
      id: id,
      room: room,
      minute: dailyMinute!,
      enabled: enabled,
      lastOccurrence: occurrence,
    );
  }
}

/// Durable appointments with a transactional consume step so multiple app
/// windows cannot simultaneously act on the same due occurrence.
final class RoomScheduleStore {
  /// Creates the store over the application's database.
  new(this._db);

  final StoreDatabase _db;
  static const _key = 'rooms.open-schedules.v1';
  static const Set<String> _tables = {StoreTables.meta};
  static const int _limit = 64;
  static final _id = RegExp(r'^[a-z0-9-]{1,64}$');
  static final _roomKey = RegExp(r'^[A-Za-z0-9_.@:-]{1,128}$');

  static bool _valid(RoomOpenSchedule schedule) {
    final room = schedule.room;
    final minute = schedule.dailyMinute;
    final at = schedule.onceAt;
    return _id.hasMatch(schedule.id) &&
        _roomKey.hasMatch(room.platform) &&
        _roomKey.hasMatch(room.roomId) &&
        room.platform != 'unknown' &&
        !SiteIds.isRetired(room.platform) &&
        !const {'0', 'null', 'undefined', 'nan', 'none'}.contains(room.roomId.toLowerCase()) &&
        (minute != null ? minute >= 0 && minute < 1440 : at != null && at.millisecondsSinceEpoch > 0 && at.year < 2100);
  }

  /// Reads the saved appointments, preserving their user order.
  Future<List<RoomOpenSchedule>> all() async {
    final rows = await _db.rows('SELECT value FROM meta WHERE key = ?', [_key]);
    if (rows.isEmpty) return const [];
    final raw = rows.single.read<String>('value');
    if (raw.length > 65536) return const [];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List<Object?> || parsed.length > _limit) return const [];
      final results = <RoomOpenSchedule>[];
      final seen = <String>{};
      for (final item in parsed) {
        if (item case {
          'id': final String id,
          'platform': final String site,
          'roomId': final String rid,
          'nick': final String nick,
          'enabled': final bool enabled,
          'claimed': final String? last,
        }) {
          final data = item as Map<String, Object?>;
          final room = LiveRoom(platform: site, roomId: rid, nick: nick);
          final once = data['at'];
          final minute = data['minute'];
          final lastOccurrence = last != null && last.length <= 32 ? last : null;
          final schedule = switch ((once, minute)) {
            (final int at, null) when at > 0 && at < 4102444800000 => RoomOpenSchedule.once(
              id: id,
              room: room,
              at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
              enabled: enabled,
              lastOccurrence: lastOccurrence,
            ),
            (null, final int minutes) => RoomOpenSchedule.daily(
              id: id,
              room: room,
              minute: minutes,
              enabled: enabled,
              lastOccurrence: lastOccurrence,
            ),
            _ => null,
          };
          if (schedule != null && _valid(schedule) && seen.add(id)) results.add(schedule);
        }
      }
      return List.unmodifiable(results);
    } on FormatException {
      return const [];
    }
  }

  /// Tracks changes to appointments, including edits in another window.
  Stream<List<RoomOpenSchedule>> watch() => _db.watch(_tables, all);

  Future<void> _write(List<RoomOpenSchedule> schedules) =>
      _db.run('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', [
        _key,
        jsonEncode([
          for (final s in schedules)
            {
              'id': s.id,
              'platform': s.room.platform,
              'roomId': s.room.roomId,
              'nick': s.room.nick.runes.take(100).map(String.fromCharCode).join(),
              'enabled': s.enabled,
              'at': s.onceAt?.millisecondsSinceEpoch,
              'minute': s.dailyMinute,
              'claimed': s.lastOccurrence,
            },
        ]),
      ]);

  /// Creates or edits an appointment without storing media credentials.
  Future<bool> put(RoomOpenSchedule schedule) => _db.write(_tables, () async {
    if (!_valid(schedule)) return false;
    final schedules = (await all()).toList();
    final index = schedules.indexWhere((item) => item.id == schedule.id);
    if (index < 0) {
      if (schedules.length >= _limit) return false;
      schedules.add(schedule);
    } else {
      schedules[index] = schedule;
    }
    await _write(schedules);
    return true;
  });

  /// Removes an appointment without altering the room or saved queue.
  Future<bool> remove(String id) => _db.write(_tables, () async {
    final schedules = (await all()).toList();
    final before = schedules.length;
    schedules.removeWhere((item) => item.id == id);
    if (schedules.length == before) return false;
    await _write(schedules);
    return true;
  });

  /// Claims one due occurrence. A late app launch must not start a room
  /// hours after the intended time. The caller decides whether foreground
  /// playback is allowed before requesting a claim.
  Future<RoomOpenSchedule?> claimDue(DateTime now) => _db.write(_tables, () async {
    final schedules = (await all()).toList();
    var index = -1;
    DateTime? earliest;
    for (final (n, schedule) in schedules.indexed) {
      if (!schedule.isDueAt(now)) continue;
      final due = schedule.dueAt(now);
      if (earliest == null || due.isBefore(earliest)) {
        index = n;
        earliest = due;
      }
    }
    if (index < 0 || earliest == null) return null;
    final winner = schedules[index];
    schedules[index] = winner._claimed(winner._occurrence(earliest));
    await _write(schedules);
    return winner;
  });

  /// Releases a claim that could not start while the app was foregrounded.
  /// A concurrently removed or edited appointment is not recreated.
  Future<void> releaseClaim(RoomOpenSchedule task, DateTime claimedAt) => _db.write(_tables, () async {
    final schedules = (await all()).toList();
    final occurrence = task._occurrence(task.dueAt(claimedAt));
    final index = schedules.indexWhere(
      (saved) =>
          saved.id == task.id &&
          saved.room.hasSameIdentity(task.room) &&
          saved.onceAt == task.onceAt &&
          saved.dailyMinute == task.dailyMinute &&
          saved.enabled == task.enabled &&
          saved.lastOccurrence == occurrence,
    );
    if (index < 0) return;
    schedules[index] = schedules[index]._claimed(task.lastOccurrence);
    await _write(schedules);
  });
}
