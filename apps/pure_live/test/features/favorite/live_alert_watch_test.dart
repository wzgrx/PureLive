// O01.2 (V01.1 L1, L14): the background check of "开播提醒" and the file it
// shares with the app.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/favorite/favorite_controller.dart';
import 'package:pure_live/features/favorite/follow_refresher.dart';
import 'package:pure_live/features/favorite/live_alert_watch.dart';
import 'package:pure_live/features/favorite/live_alerts.dart';

import '../../support.dart';

final class _Site extends LiveSite {
  new(this.details);

  @override
  String get id => 'douyu';

  @override
  String get name => 'douyu';

  final Map<String, LiveRoom> details;
  final List<String> requested = [];

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    requested.add(roomId);
    return details[roomId] ?? (throw StateError('no room $roomId'));
  }
}

LiveRoom _room(String id, {LiveStatus? status, String nick = '', String title = ''}) =>
    LiveRoom(platform: 'douyu', roomId: id, nick: nick, title: title, liveStatus: status);

/// Waits (real time, at most 10 s) until [done] holds: file writes are slow
/// when the whole suite runs at once.
Future<void> _until(Future<bool> Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!await done() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

const LiveAlertTexts _texts = (title: '{name} 开播了', empty: '点按进入直播间', channel: '开播提醒', channelDescription: '说明');

final class _BiliBatchSite extends LiveSite implements LiveSiteFollowBatchRefresher {
  @override
  String get id => SiteIds.bilibili;

  @override
  String get name => id;

  final List<String> detailRequests = [];
  final List<List<String?>> batchRequests = [];

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    detailRequests.add(roomId);
    return LiveRoom(platform: id, roomId: roomId, userId: '10$roomId', liveStatus: LiveStatus.offline);
  }

  @override
  Future<Map<String, LiveRoom>> refreshFollowBatch(List<LiveRoom> rooms) async {
    final uids = rooms.map((room) => room.userId).toList();
    if (uids.any((uid) => BilibiliApi.followUid(uid) == null)) return const {};
    batchRequests.add(uids);
    return {for (final room in rooms) room.identityKey: room.copyWith(liveStatus: LiveStatus.offline)};
  }
}

void main() {
  late Directory folder;
  late LiveAlertWatchFile file;
  setUp(() {
    folder = Directory.systemTemp.createTempSync('live_alert_watch');
    file = LiveAlertWatchFile(Future.value(File('${folder.path}/${LiveAlertWatchFile.name}')));
  });
  tearDown(() => folder.deleteSync(recursive: true));

  test('existing foreground follows persist Bilibili identities and subsequently batch', () async {
    final store = await LiveStore.memory(cipher: FakeCipher());
    addTearDown(store.close);
    final site = _BiliBatchSite();
    final refresher = FollowRefresher(sites: SiteRegistry({site.id: () => site}));
    for (final rid in ['1', '2']) {
      await store.follows.add(LiveRoom(platform: site.id, roomId: rid));
    }
    final first = await refresher.refresh(await store.follows.all(), concurrency: 2);
    await store.follows.update(first.rooms);
    final saved = await store.follows.all();
    expect(saved.map((room) => room.userId), unorderedEquals(['101', '102']));
    await refresher.refresh(saved, concurrency: 2);
    expect(site.detailRequests, hasLength(2));
    expect(site.batchRequests.single, unorderedEquals(['101', '102']));
  });

  test('old background watch learns Bilibili UIDs and the next check can batch without refollowing', () async {
    final site = _BiliBatchSite();
    final refresher = FollowRefresher(sites: SiteRegistry({site.id: () => site}));
    await file.write(
      LiveAlertWatch(
        rooms: [
          LiveRoom(platform: SiteIds.bilibili, roomId: '1'),
          LiveRoom(platform: SiteIds.bilibili, roomId: '2'),
        ],
        names: {},
        states: {},
        texts: _texts,
      ),
    );
    Future<List<LiveRoom>> check() =>
        runLiveAlertCheck(file: file, refresher: refresher, post: (_, _) async => fail('Neither room started'));
    await check();
    expect(site.detailRequests, unorderedEquals(['1', '2']));
    expect((await file.read())!.rooms.map((room) => room.userId), ['101', '102']);
    await check();
    expect(site.detailRequests, hasLength(2));
    expect(site.batchRequests, [
      ['101', '102'],
    ]);
  });

  test('the file keeps the rooms, names, states and words; another version or junk reads as none', () async {
    final at = DateTime.fromMillisecondsSinceEpoch(1760000000000);
    await file.write(
      LiveAlertWatch(
        rooms: [_room('1', nick: '晚风', title: '聊天')],
        names: {'douyu:1': '晚风'},
        states: {'douyu:1': (live: true, startedAt: at, endedAt: null, seenAt: at)},
        texts: _texts,
        nextCheck: at,
      ),
    );
    final read = (await file.read())!;
    expect(read.rooms.single.identityKey, 'douyu:1');
    expect(read.rooms.single.title, '聊天');
    expect(read.states['douyu:1'], (live: true, startedAt: at, endedAt: null, seenAt: at));
    expect(read.nextCheck, at);
    expect(read.contentOf(_room('1', title: ' 新标题 ')), (title: '晚风 开播了', text: '新标题'));
    expect(read.contentOf(_room('2', nick: '小雨')), (title: '小雨 开播了', text: '点按进入直播间'));

    final raw = await file.file;
    raw.writeAsStringSync('{"v": 99}');
    expect(await file.read(), isNull);
    raw.writeAsStringSync('not json');
    expect(await file.read(), isNull);
    await file.clear();
    expect(raw.existsSync(), isFalse);
  });

  test(
    'writes at the same time all land, the last asked for last; another store beside it does not break them',
    () async {
      LiveAlertWatch watch(String nick) => LiveAlertWatch(
        rooms: [_room('1', nick: nick)],
        names: {'douyu:1': nick},
        states: const {},
        texts: _texts,
      );
      // The app's start writes twice at once: with one shared temporary file
      // the second write's rename failed and the first state stayed.
      await Future.wait([file.write(watch('甲')), file.write(watch('乙'))]);
      expect((await file.read())!.names['douyu:1'], '乙');
      // The background check writes through a store of its own.
      final other = LiveAlertWatchFile(file.file);
      await Future.wait([file.write(watch('丙')), other.write(watch('丁')), file.write(watch('戊'))]);
      expect(['丙', '丁', '戊'], contains((await file.read())!.names['douyu:1']));
      expect(folder.listSync().map((entry) => entry.path.split('/').last), [LiveAlertWatchFile.name]);
    },
  );

  group('check', () {
    late DateTime now;
    late _Site site;
    late List<String> posted;
    setUp(() {
      now = DateTime(2026, 10, 15, 20);
      site = _Site({'1': _room('1', status: LiveStatus.offline), '2': _room('2', status: LiveStatus.offline)});
      posted = [];
    });

    Future<List<String>> check() async => [
      for (final room in await runLiveAlertCheck(
        file: file,
        refresher: FollowRefresher(sites: SiteRegistry({'douyu': () => site})),
        post: (room, watch) async => posted.add(watch.contentOf(room).title),
        now: () => now,
      ))
        room.roomId,
    ];

    Future<void> watch({DateTime? nextCheck, Map<String, LiveAlertSeen> states = const {}}) => file.write(
      LiveAlertWatch(
        rooms: [_room('1'), _room('2')],
        names: const {'douyu:1': '甲', 'douyu:2': '乙'},
        states: states,
        texts: _texts,
        nextCheck: nextCheck,
      ),
    );

    test('no file: nothing is asked', () async {
      expect(await check(), isEmpty);
      expect(site.requested, isEmpty);
    });

    test('while the app checks itself nothing is asked', () async {
      await watch(nextCheck: now.add(const Duration(minutes: 1)));
      expect(await check(), isEmpty);
      expect(site.requested, isEmpty);
    });

    test('first states are remembered; off air then live is told once; the file keeps what was seen', () async {
      await watch(nextCheck: now.subtract(const Duration(minutes: 1)));
      expect(await check(), isEmpty, reason: 'first seen');
      expect(site.requested, ['1', '2']);
      expect((await file.read())!.states.keys, unorderedEquals(['douyu:1', 'douyu:2']));

      site.details['2'] = _room('2', status: LiveStatus.live, title: '开播啦');
      now = now.add(const Duration(minutes: 15));
      expect(await check(), ['2']);
      expect(posted, ['乙 开播了']);
      now = now.add(const Duration(minutes: 15));
      expect(await check(), isEmpty, reason: 'the same broadcast');
      expect((await file.read())!.states['douyu:2']!.live, isTrue);
    });

    test('a broadcast the app already saw is not told again', () async {
      await watch(
        states: {
          'douyu:1': (live: true, startedAt: null, endedAt: null, seenAt: now),
          'douyu:2': (live: false, startedAt: null, endedAt: null, seenAt: now),
        },
      );
      site.details['1'] = _room('1', status: LiveStatus.live);
      now = now.add(const Duration(minutes: 20));
      expect(await check(), isEmpty);
    });
  });

  group('app side', () {
    test('turning "开播提醒" on schedules the check and writes the covered follows; off clears them', () async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      await store.follows.add(_room('1', nick: '甲', status: LiveStatus.offline));
      final scheduled = <bool>[];
      final controller = FavoriteController(
        store: store,
        refresher: FollowRefresher(
          sites: SiteRegistry({
            'douyu': () => _Site({'1': _room('1', status: LiveStatus.offline)}),
          }),
        ),
        postLiveAlert: (room) async {},
        now: () => DateTime(2026, 10, 15, 20),
        liveAlertBackground: LiveAlertBackground(
          file: file,
          schedule: ({required on}) async => scheduled.add(on),
          texts: () => _texts,
          nameOf: (room) => room.nick,
        ),
      )..start();
      addTearDown(controller.dispose);
      await controller.firstCheck;
      await _until(() async => scheduled.isNotEmpty);
      expect(scheduled, [false], reason: '"开播提醒" is off by default');
      expect(await file.read(), isNull);

      await store.settings.set(Settings.liveAlertEnabled, true);
      await _until(() async => scheduled.last && await file.read() != null);
      expect(scheduled.last, isTrue);
      final written = (await file.read())!;
      expect(written.rooms.map((room) => room.identityKey), ['douyu:1']);
      expect(written.names, {'douyu:1': '甲'});
      expect(written.nextCheck, DateTime(2026, 10, 15, 20, 20), reason: 'its 15-minute timer and 5 minutes more');

      await store.settings.set(Settings.liveAlertBackground, false);
      await _until(() async => !scheduled.last && await file.read() == null);
      expect(scheduled.last, isFalse);
      expect(await file.read(), isNull);
    });

    test('a pass takes what the background check saw: a broadcast it told of is not told again', () async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      await store.settings.set(Settings.liveAlertEnabled, true);
      await store.follows.add(_room('1', nick: '甲', status: LiveStatus.offline));
      final site = _Site({'1': _room('1', status: LiveStatus.offline)});
      var now = DateTime(2026, 10, 15, 20);
      final posted = <String>[];
      final controller = FavoriteController(
        store: store,
        refresher: FollowRefresher(sites: SiteRegistry({'douyu': () => site})),
        postLiveAlert: (room) async => posted.add(room.roomId),
        now: () => now,
        liveAlertBackground: LiveAlertBackground(
          file: file,
          schedule: ({required on}) async {},
          texts: () => _texts,
          nameOf: (room) => room.nick,
        ),
      )..start();
      addTearDown(controller.dispose);
      await controller.firstCheck;
      await _until(() async => (await file.read())?.states.containsKey('douyu:1') ?? false);
      // The start writes the file twice; the second must not land after the
      // clock below moved on (its "next check" would then hold the
      // background check back: the flaky failure of 2026-10-17).
      await controller.backgroundSettled();

      // Frozen: the background check sees 甲 go live and tells of it.
      site.details['1'] = _room('1', status: LiveStatus.live);
      now = now.add(const Duration(minutes: 30));
      final told = await runLiveAlertCheck(
        file: file,
        refresher: FollowRefresher(sites: SiteRegistry({'douyu': () => site})),
        post: (room, watch) async {},
        now: () => now,
      );
      expect(told.map((room) => room.roomId), ['1']);

      // Back: the app's pass sees the same broadcast.
      now = now.add(const Duration(minutes: 1));
      await controller.refreshAll(visible: false);
      expect(posted, isEmpty);
    });
  });
}
