import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_store/src/database.dart';

/// The durable, ordered rooms a user explicitly saved for later viewing.
///
/// Store only room identities and a short display name. Playback URLs,
/// request headers and platform-specific session data must be resolved
/// anew when a room is selected.
final class SavedRoomQueueStore {
  /// Creates the queue over the shared application database.
  new(this._db);

  final StoreDatabase _db;
  static const _key = 'rooms.saved-queue.v1';
  static const Set<String> _tables = {StoreTables.meta};
  static final _identifier = RegExp(r'^[A-Za-z0-9_.@:-]{1,128}$');

  /// An intentional storage and menu bound.
  static const maxRooms = 100;

  static bool _eligible(LiveRoom room) =>
      _identifier.hasMatch(room.platform) &&
      _identifier.hasMatch(room.roomId) &&
      room.platform != 'unknown' &&
      !SiteIds.isRetired(room.platform) &&
      !const {'0', 'null', 'undefined', 'nan', 'none'}.contains(room.roomId.toLowerCase());

  static String _label(String input) {
    final safe = input.trim();
    return safe.runes.take(100).map(String.fromCharCode).join();
  }

  /// Returns the current rooms in the user's saved order.
  Future<List<LiveRoom>> all() async {
    final rows = await _db.rows('SELECT value FROM meta WHERE key = ?', [_key]);
    if (rows.isEmpty) return const [];
    final raw = rows.single.read<String>('value');
    if (raw.length > 65536) return const [];
    try {
      final values = jsonDecode(raw);
      if (values is! List<Object?> || values.length > maxRooms) return const [];
      final seen = <String>{};
      return List.unmodifiable([
        for (final entry in values)
          if (entry case {'platform': final String site, 'roomId': final String id, 'nick': final String nick})
            if (LiveRoom(platform: site, roomId: id, nick: _label(nick)) case final room
                when _eligible(room) && seen.add(room.identityKey))
              room,
      ]);
    } on FormatException {
      return const [];
    }
  }

  /// Tracks edits, including changes from another application window.
  Stream<List<LiveRoom>> watch() => _db.watch(_tables, all);

  Future<void> _save(List<LiveRoom> rooms) => _db.run('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', [
    _key,
    jsonEncode([
      for (final room in rooms) {'platform': room.platform, 'roomId': room.roomId, 'nick': _label(room.nick)},
    ]),
  ]);

  /// Adds an eligible room once, at the end of the queue.
  Future<bool> add(LiveRoom room) => _db.write(_tables, () async {
    if (!_eligible(room)) return false;
    final current = await all();
    if (current.length >= maxRooms || current.any(room.hasSameIdentity)) return false;
    await _save([...current, room]);
    return true;
  });

  /// Removes just [room]. Unrelated follows and history are unaffected.
  Future<bool> remove(LiveRoom room) => _db.write(_tables, () async {
    final current = await all();
    final kept = current.where((r) => !r.hasSameIdentity(room)).toList();
    if (kept.length == current.length) return false;
    await _save(kept);
    return true;
  });

  /// Moves [room] to [position] within the current durable list.
  Future<bool> move(LiveRoom room, int position) => _db.write(_tables, () async {
    final current = (await all()).toList();
    final before = current.indexWhere(room.hasSameIdentity);
    if (before < 0 || position < 0 || position >= current.length || before == position) return false;
    current.insert(position, current.removeAt(before));
    await _save(current);
    return true;
  });
}
