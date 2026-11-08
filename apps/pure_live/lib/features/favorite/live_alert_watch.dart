import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:pure_live/features/favorite/follow_refresher.dart';
import 'package:pure_live/features/favorite/live_alerts.dart';

// "开播提醒" after the app is frozen or cleared (O01.2, in
// docs/O-Android系统集成/O01-通知和前台服务; V01.1 L1, L14): Android's WorkManager runs a
// short Dart check every 15 minutes or later (the system decides). The app
// and the check share one small file: the follows covered, what is known of
// each (so a broadcast is told once, whoever saw it first) and the words of
// the notification. The check opens no database and uses no cookies.

/// The notification's words, in the app's language at the last write.
typedef LiveAlertTexts = ({String title, String empty, String channel, String channelDescription});

/// What the background check reads and writes.
final class LiveAlertWatch {
  /// Creates the state.
  const new({required this.rooms, required this.names, required this.states, required this.texts, this.nextCheck});

  /// Reads [json]; null when it is not a state of this version.
  static LiveAlertWatch? fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['v'] != version) return null;
    DateTime? time(Object? value) => value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
    final texts = json['texts'];
    if (texts is! Map<String, Object?>) return null;
    String text(String key) => texts[key] is String ? texts[key]! as String : '';
    final rooms = <LiveRoom>[];
    final names = <String, String>{};
    for (final entry in json['rooms'] is List<Object?> ? json['rooms']! as List<Object?> : const <Object?>[]) {
      if (entry is! Map<String, Object?>) continue;
      final platform = entry['platform'];
      final roomId = entry['roomId'];
      if (platform is! String || roomId is! String || platform.isEmpty || roomId.isEmpty) continue;
      final room = LiveRoom(
        platform: platform,
        roomId: roomId,
        userId: platform == SiteIds.bilibili ? BilibiliApi.followUid(entry['userId']) : null,
        nick: entry['nick'] is String ? entry['nick']! as String : '',
        title: entry['title'] is String ? entry['title']! as String : '',
      );
      rooms.add(room);
      if (entry['name'] case final String name when name.isNotEmpty) names[room.identityKey] = name;
    }
    final states = <String, LiveAlertSeen>{};
    final saved = json['states'];
    if (saved is Map<String, Object?>) {
      for (final MapEntry(:key, :value) in saved.entries) {
        if (value is! Map<String, Object?>) continue;
        final seenAt = time(value['seenAt']);
        final live = value['live'];
        if (seenAt == null || live is! bool) continue;
        states[key] = (
          live: live,
          startedAt: time(value['startedAt']),
          endedAt: time(value['endedAt']),
          seenAt: seenAt,
        );
      }
    }
    return LiveAlertWatch(
      rooms: rooms,
      names: names,
      states: states,
      texts: (
        title: text('title'),
        empty: text('empty'),
        channel: text('channel'),
        channelDescription: text('channelDescription'),
      ),
      nextCheck: time(json['nextCheck']),
    );
  }

  /// The file's version.
  static const int version = 1;

  /// The follows covered.
  final List<LiveRoom> rooms;

  /// The name shown for each room (identity key), the platform's name for a
  /// streamer without one.
  final Map<String, String> names;

  /// What is known of each room ([LiveAlertTracker.states]).
  final Map<String, LiveAlertSeen> states;

  /// The notification's words.
  final LiveAlertTexts texts;

  /// Until when the app checks itself: the background check does nothing
  /// before then.
  final DateTime? nextCheck;

  /// Updates observations and backfills identities on rooms still watched.
  /// A concurrently saved identity wins over an older worker result.
  LiveAlertWatch withStates(Map<String, LiveAlertSeen> states, {Iterable<LiveRoom> refreshed = const []}) {
    final learned = {
      for (final room in refreshed)
        if (BilibiliApi.followUid(room.userId) case final uid? when room.platform == SiteIds.bilibili)
          room.identityKey: uid,
    };
    return LiveAlertWatch(
      rooms: [
        for (final room in rooms)
          if (room.platform == SiteIds.bilibili && BilibiliApi.followUid(room.userId) == null)
            room.copyWith(userId: learned[room.identityKey])
          else
            room,
      ],
      names: names,
      states: states,
      texts: texts,
      nextCheck: nextCheck,
    );
  }

  /// The JSON form.
  Map<String, Object?> toJson() => {
    'v': version,
    'nextCheck': nextCheck?.millisecondsSinceEpoch,
    'texts': {
      'title': texts.title,
      'empty': texts.empty,
      'channel': texts.channel,
      'channelDescription': texts.channelDescription,
    },
    'rooms': [
      for (final room in rooms)
        {
          'platform': room.platform,
          'roomId': room.roomId,
          if (BilibiliApi.followUid(room.userId) case final uid? when room.platform == SiteIds.bilibili) 'userId': uid,
          'nick': room.nick,
          'title': room.title,
          'name': ?names[room.identityKey],
        },
    ],
    'states': {
      for (final MapEntry(:key, :value) in states.entries)
        key: {
          'live': value.live,
          'startedAt': value.startedAt?.millisecondsSinceEpoch,
          'endedAt': value.endedAt?.millisecondsSinceEpoch,
          'seenAt': value.seenAt.millisecondsSinceEpoch,
        },
    },
  };

  /// The notification of [room] (V01.1 L7): "晚风 开播了" over the
  /// broadcast's title, or "点按进入直播间" when there is none.
  ({String title, String text}) contentOf(LiveRoom room) {
    final name = names[room.identityKey] ?? (room.nick.trim().isEmpty ? room.roomId : room.nick.trim());
    final title = room.title.trim();
    return (title: texts.title.replaceAll('{name}', name), text: title.isEmpty ? texts.empty : title);
  }
}

/// The file the app and the background check share.
final class LiveAlertWatchFile {
  /// Creates the store over [file] (found once, by the first use).
  new(this.file);

  /// The file name in the app's support folder.
  static const String name = 'live_alert_watch.json';

  /// The file.
  final Future<File> file;

  /// The state; null when there is none or it cannot be read.
  Future<LiveAlertWatch?> read() async {
    try {
      final file = await this.file;
      if (!file.existsSync()) return null;
      return LiveAlertWatch.fromJson(jsonDecode(await file.readAsString()));
    } on Object catch (error) {
      log('Live alert state unreadable', name: 'LiveAlerts', error: error);
      return null;
    }
  }

  /// Writes [watch] whole (a temporary file renamed over the old one, so a
  /// reader never sees half of it). Each write has a temporary file of its
  /// own: two writes sharing one (the app's start wrote twice at once, and
  /// the background check runs beside the app) cut each other's file short
  /// and the second rename failed, leaving the older state in place. Writes
  /// through one store land in the order they were asked for.
  Future<void> write(LiveAlertWatch watch) => _inTurn(() async {
    final file = await this.file;
    final temporary = File('${file.path}.$pid.${_serial++}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      await temporary.parent.create(recursive: true);
      await temporary.writeAsString(jsonEncode(watch.toJson()), flush: true);
      await temporary.rename(file.path);
    } on Object {
      try {
        if (temporary.existsSync()) await temporary.delete();
      } on FileSystemException {
        // Gone already.
      }
      rethrow;
    }
  });

  /// Removes the state ("开播提醒" or the background check turned off).
  Future<void> clear() => _inTurn(() async {
    try {
      final file = await this.file;
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Gone already.
    }
  });

  static int _serial = 0;
  Future<void> _last = Future.value();

  Future<void> _inTurn(Future<void> Function() work) {
    final done = _last.then((_) => work());
    _last = done.then((_) {}, onError: (Object _) {});
    return done;
  }
}

/// The app's side of the background check (O01.2): the shared file,
/// turning the periodic work on and off, and the words in the app's
/// language.
final class LiveAlertBackground {
  /// Creates the side.
  const new({required this.file, required this.schedule, required this.texts, required this.nameOf});

  /// The shared file.
  final LiveAlertWatchFile file;

  /// Turns Android's periodic check on or off.
  final Future<void> Function({required bool on}) schedule;

  /// The notification's words now.
  final LiveAlertTexts Function() texts;

  /// The name shown for a room.
  final String Function(LiveRoom room) nameOf;

  /// How long past the app's next own check the background check waits (a
  /// late timer is not a frozen app).
  static const Duration grace = Duration(minutes: 5);
}

/// One background check (O01.2): reads the state, and unless the app
/// checks itself now, asks for the covered follows, [post]s the ones that
/// began a broadcast and writes what it saw back (merged with what the app
/// wrote meanwhile). Returns the rooms posted.
Future<List<LiveRoom>> runLiveAlertCheck({
  required LiveAlertWatchFile file,
  required FollowRefresher refresher,
  required Future<void> Function(LiveRoom room, LiveAlertWatch watch) post,
  DateTime Function() now = DateTime.now,
  int concurrency = 3,
}) async {
  final watch = await file.read();
  if (watch == null || watch.rooms.isEmpty) return const [];
  final next = watch.nextCheck;
  if (next != null && now().isBefore(next)) return const [];
  final tracker = LiveAlertTracker(now: now)..adopt(watch.states);
  final result = await refresher.refresh(watch.rooms, concurrency: concurrency, bypassCooldown: true);
  final started = tracker.observe(result.rooms);
  for (final room in started) {
    try {
      await post(room, watch);
    } on Object catch (error) {
      log('Live alert failed: ${room.identityKey}', name: 'LiveAlerts', error: error);
    }
  }
  final latest = await file.read() ?? watch;
  final merged = LiveAlertTracker(now: now)
    ..adopt(latest.states)
    ..adopt(tracker.states);
  await file.write(latest.withStates(merged.states, refreshed: result.rooms));
  return started;
}
