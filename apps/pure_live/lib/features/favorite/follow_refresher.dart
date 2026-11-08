import 'dart:async';
import 'dart:developer';

import 'package:live_core/live_core.dart';

/// What one refresh pass found: the rooms to write back (fresh details, and
/// the stored room marked pending where the request failed) and how many
/// requests failed.
final class FollowRefreshResult {
  /// Creates the result.
  const new({required this.rooms, required this.failed});

  /// Rooms for `FollowStore.update`, which merges each into the stored one
  /// (`LiveRoom.mergeFrom`: an empty or placeholder name, title or cover
  /// keeps the stored value).
  final List<LiveRoom> rooms;

  /// Requests that failed or timed out.
  final int failed;
}

/// Refreshes followed rooms (3.x `FavoriteController._refreshRoomDetails`):
/// bounded batches where supported, at most `concurrency` workers, one adapter per
/// platform, a time limit per request, and a pause of [cooldown] for a room
/// whose last request failed unless the caller bypasses it.
///
/// A failed request keeps the stored room with its state pending
/// (`LiveRoom.pendingAfterError`; 3.x reset it to offline-looking
/// `status: false`). Rooms of retired platforms, and of platforms without
/// an adapter in this build (I03.2 c6), are not requested and stay as
/// stored.
final class FollowRefresher {
  /// Creates the refresher over [sites].
  new({
    required this.sites,
    this.timeout = const Duration(seconds: 10),
    this.cooldown = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The platforms.
  final SiteRegistry sites;

  /// The limit of one request (3.x `_roomRefreshTimeout`).
  final Duration timeout;

  /// How long a failed room is skipped by passes that honour it (3.x
  /// `_refreshFailureRetryAfter`).
  final Duration cooldown;

  final DateTime Function() _now;
  final Map<String, DateTime> _failedAt = {};

  /// Refreshes [rooms]; [onProgress] is called after each request with the
  /// number done and the total, [cancelled] is checked before each request.
  Future<FollowRefreshResult> refresh(
    List<LiveRoom> rooms, {
    required int concurrency,
    bool bypassCooldown = false,
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final now = _now();
    final queue = [
      for (final room in rooms)
        if (!SiteIds.isRetired(room.platform) &&
            sites.maybeOf(room.platform) != null &&
            (bypassCooldown || !(now.difference(_failedAt[room.identityKey] ?? DateTime(0)) < cooldown)))
          room,
    ];
    final batches = <List<LiveRoom>>[];
    final groups = <String, List<LiveRoom>>{};
    for (final room in queue) {
      if (sites.maybeOf(room.platform) is! LiveSiteFollowBatchRefresher) continue;
      final group = groups.putIfAbsent(room.platform, () => [])..add(room);
      if (group.length == 20) {
        batches.add(group);
        groups.remove(room.platform);
      }
    }
    batches.addAll(groups.values.where((group) => group.length > 1));
    final parallel = concurrency.clamp(1, 20);
    final confirmed = <String, LiveRoom>{};
    var nextBatch = 0;
    Future<void> batchWorker() async {
      while (nextBatch < batches.length && !(cancelled?.call() ?? false)) {
        final group = batches[nextBatch++];
        final site = sites.maybeOf(group.first.platform);
        if (site is! LiveSiteFollowBatchRefresher) continue;
        try {
          confirmed.addAll(await (site! as LiveSiteFollowBatchRefresher).refreshFollowBatch(group).timeout(timeout));
        } on Object {
          // The normal worker pool retries unconfirmed rooms individually.
        }
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) batchWorker()]);
    final results = <LiveRoom>[];
    var failed = 0;
    var done = 0;
    var next = 0;
    Future<void> worker() async {
      while (next < queue.length) {
        if (cancelled?.call() ?? false) return;
        final room = queue[next++];
        final answer = confirmed[room.identityKey];
        final matches = answer != null && answer.hasSameIdentity(room);
        if (matches) _failedAt.remove(room.identityKey);
        final fresh = matches ? answer.withAudienceFallbackFrom(room) : await _load(room);
        if (cancelled?.call() ?? false) return;
        if (fresh == null) {
          failed++;
          results.add(room.pendingAfterError());
        } else {
          results.add(fresh);
        }
        onProgress?.call(++done, queue.length);
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
    return FollowRefreshResult(rooms: results, failed: failed);
  }

  Future<LiveRoom?> _load(LiveRoom room) async {
    final site = sites.maybeOf(room.platform);
    if (site == null) return null;
    try {
      final operation = site is LiveSiteRoomRefresher
          ? (site as LiveSiteRoomRefresher).getRoomDetailForRefresh(roomId: room.roomId)
          : site.getRoomDetail(roomId: room.roomId);
      final detail = await operation.timeout(timeout);
      _failedAt.remove(room.identityKey);
      return bindToFollow(room, detail).withAudienceFallbackFrom(room);
    } on Object catch (error) {
      _failedAt[room.identityKey] = _now();
      log('Follow refresh failed: ${room.identityKey}', name: 'FavoritePage', error: error);
      return null;
    }
  }
}

/// [detail] under [follow]'s identity: a platform may answer with another
/// id for the same room (3.x `bindFavoriteRefreshResultToRequest`), which
/// the merge into the stored follow and its tags would otherwise ignore.
LiveRoom bindToFollow(LiveRoom follow, LiveRoom detail) => detail.hasSameIdentity(follow)
    ? detail
    : LiveRoom.fromJson({...detail.toJson(), 'platform': follow.platform, 'roomId': follow.roomId});
