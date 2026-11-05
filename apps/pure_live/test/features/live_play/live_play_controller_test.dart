import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/testing.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/shared/danmaku/danmaku_templates.dart';
import 'package:pure_live/shared/rooms/play_quality.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

import '../../support.dart';
import 'live_play_support.dart';

const _bilibili = '../../fixtures/bilibili';

final class _PhaseFailureSite extends FakeSite {
  new(this.phase, {this.failure = const ApiChanged(SiteIds.bilibili, 'test-only-private-context')}) : super(liveRoom());

  final String phase;
  final SiteError failure;

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    if (phase == 'detail') throw failure;
    return await super.getRoomDetail(roomId: roomId);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    if (phase == 'qualities') throw failure;
    return await super.getPlayQualities(detail: detail);
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    if (phase == 'urls') throw failure;
    return await super.getPlayUrls(detail: detail, quality: quality);
  }
}

/// `getRoomPlayInfo` at qn=0 as a room offering 原画 only answers it (the
/// H01.3 rewrite of `S07-guest-qn0`): every codec lists 10000 alone.
ReplaySample _onlyOriginalListed() {
  final sample = ReplaySample.load('$_bilibili/S07-guest-qn0');
  final body = jsonDecode(utf8.decode(sample.bytes)) as Map<String, dynamic>;
  final playurl = ((body['data'] as Map)['playurl_info'] as Map)['playurl'] as Map;
  for (final stream in playurl['stream'] as List) {
    for (final format in (stream as Map)['format'] as List) {
      for (final codec in (format as Map)['codec'] as List) {
        (codec as Map)
          ..['accept_qn'] = [10000]
          ..['current_qn'] = 10000;
      }
    }
  }
  return ReplaySample(
    method: sample.method,
    url: sample.url,
    status: sample.status,
    headers: sample.headers,
    bytes: utf8.encode(jsonEncode(body)),
  );
}

/// Bilibili over the recorded guest answers of room 42062, listing 原画
/// only; a request at 10000 is served 250 (`S07-guest-qn10000`).
BilibiliSite _bilibiliGuestOriginalOnly() => BilibiliSite(
  ReplayHttp(
    [
      _onlyOriginalListed(),
      for (final name in [
        'S06-live',
        'S07-guest-qn0',
        'S07-guest-qn10000',
        'S09-guest',
        'S10-guest',
        'S11-guest',
        'S12-guest',
      ])
        ReplaySample.load('$_bilibili/$name'),
    ],
    ignoredQuery: const {'wts', 'w_rid', 'w_webid'},
  ),
  now: () => DateTime.utc(2026, 9, 27, 10, 16, 23),
  sleep: (_) async {},
);

void main() {
  late LiveStore store;
  late FakeDanmaku danmaku;
  late FakeEngine engine;
  late PlaybackSession session;
  final toasts = <String>[];
  final now = DateTime.utc(2026, 10, 1, 12);

  setUpAll(loadStrings);

  setUp(() async {
    store = await LiveStore.memory(cipher: FakeCipher());
    danmaku = FakeDanmaku();
    engine = FakeEngine();
    session = fakeSession(engine);
    toasts.clear();
  });

  tearDown(() async {
    await session.dispose();
    await store.close();
  });

  LiveRoomController controllerFor(
    LiveSite site, {
    LiveRoom? room,
    bool danmakuSupported = true,
    NetworkKind? network,
    DateTime Function()? clock,
  }) => LiveRoomController(
    room: room ?? LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '卡片上的名字'),
    site: site,
    session: session,
    danmaku: danmaku,
    danmakuSupported: danmakuSupported,
    store: store,
    toast: toasts.add,
    network: network == null ? null : () async => network,
    now: clock ?? () => now,
    refreshInterval: Duration.zero,
  );

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test(
    'issue177: anonymous chat initialization overlaps a slow first video open and is not repeated afterwards',
    () async {
      final held = Completer<void>();
      engine.onOpen = (_) => held.future;
      final controller = controllerFor(FakeSite(liveRoom()));
      final starting = controller.start();
      try {
        await pumpEventQueue();
        expect(danmaku.connects, hasLength(1), reason: 'visitor bootstrap must not wait for the video driver');
      } finally {
        held.complete();
        await starting;
      }
      await pumpEventQueue();
      expect(danmaku.connects, hasLength(1), reason: 'finishing video startup must not restart a ready visitor socket');
      controller.dispose();
    },
  );

  test('D01.34: the VIP count is an audience figure labelled 贵宾, not a chat line; a human chat is retained', () async {
    final controller = controllerFor(FakeSite(liveRoom(platform: SiteIds.douyu)));
    await controller.start();
    await settle();
    final notices = DouyuDanmakuProtocol.decode(
      DouyuDanmakuProtocol.packet('type@=oni/vn@=17000/rid@=1/', type: DouyuDanmakuProtocol.serverPacketType),
      roomId: '1',
    );
    final vip = notices.single;
    danmaku.emit(DanmakuReceived(vip));
    await settle();
    expect(controller.chat.lines.where((line) => line.text == '17000'), isEmpty);
    expect(
      audienceFigures(
        controller.room,
        vipCount: controller.vipCount,
      ).map((figure) => (figure.type, figure.value, figure.label)),
      contains((AudienceMetricType.unknown, '17000', '贵宾')),
    );
    danmaku.emit(
      const DanmakuReceived(
        LiveMessage(type: LiveMessageType.chat, userName: '贵宾', message: 'human', color: LiveMessageColor.white),
      ),
    );
    await settle();
    expect(controller.chat.lines.map((line) => line.text), contains('human'));
    controller.dispose();
  });

  for (final heat in ['', '0', '12345']) {
    test('PR94: VIP count never becomes real online viewers or a card rank ($heat)', () async {
      final detail = liveRoom(platform: SiteIds.douyu).copyWith(popularity: heat, watching: heat);
      final site = FakeSite(detail)..siteId = SiteIds.douyu;
      final controller = controllerFor(site, room: detail);
      await controller.start();
      await settle();
      final before = controller.room.audienceRankKey(preferRealOnline: false, platformEnabled: false);
      final message = DouyuDanmakuProtocol.decode(
        DouyuDanmakuProtocol.packet('type@=oni/vn@=17000/rid@=6/', type: DouyuDanmakuProtocol.serverPacketType),
        roomId: '6',
      ).single;
      danmaku.emit(DanmakuReceived(message));
      await settle();
      expect(controller.vipCount, 17000);
      expect(controller.room.onlineViewers, isEmpty);
      expect(controller.room.hasRealOnlineCount, isFalse);
      expect(controller.room.effectivePopularity, detail.effectivePopularity);
      final after = controller.room.audienceRankKey(preferRealOnline: false, platformEnabled: false);
      expect((after.metricPriority, after.value), (before.metricPriority, before.value));
      expect(controller.chat.lines.where((line) => line.text == '17000'), isEmpty);
      danmaku.emit(
        const DanmakuReceived(
          LiveMessage(
            type: LiveMessageType.online,
            userName: '',
            message: '',
            color: LiveMessageColor.white,
            data: LiveVipCount(value: 0),
          ),
        ),
      );
      await settle();
      expect(controller.vipCount, 0);
      expect(audienceFigures(controller.room, vipCount: controller.vipCount).first.value, '0');
      expect(controller.room.hasRealOnlineCount, isFalse);
      site.room = detail.copyWith(liveStatus: LiveStatus.offline);
      await controller.refreshDetail();
      expect(controller.vipCount, isNull, reason: 'An ended broadcast must not retain the old VIP figure.');
      danmaku.emit(
        const DanmakuReceived(
          LiveMessage(
            type: LiveMessageType.online,
            userName: '',
            message: '',
            color: LiveMessageColor.white,
            data: LiveVipCount(value: 222),
          ),
        ),
      );
      await settle();
      expect(controller.vipCount, isNull, reason: 'A late packet must not revive an ended broadcast VIP count.');
      controller.dispose();
      final next = controllerFor(
        FakeSite(LiveRoom(platform: SiteIds.douyu, roomId: '7'))..siteId = SiteIds.douyu,
        room: LiveRoom(platform: SiteIds.douyu, roomId: '7'),
      );
      expect(next.vipCount, isNull, reason: 'A different room starts without a VIP figure.');
      next.dispose();
    });
  }

  test('issue #78: larger font survives persistence without changing the default', () async {
    expect(store.settings.get(Settings.danmakuFontSize), 16);
    await store.settings.set(Settings.danmakuFontSize, 60);
    expect(store.settings.get(Settings.danmakuFontSize), 60);
    final template = DanmakuTemplate.of(store.settings);
    expect(DanmakuTemplate.tryDecode(template.encode(), template)!.fontSize, 60);
    await store.settings.set(Settings.danmakuFontSize, 600);
    expect(store.settings.get(Settings.danmakuFontSize), 60);
  });

  test('a live room plays the preferred quality, records history and joins the danmaku', () async {
    await store.settings.set(Settings.preferResolution, '超清');
    final site = FakeSite(liveRoom());
    final controller = controllerFor(site);
    await controller.start();
    await settle();

    expect(controller.stage, RoomStage.playing);
    expect(controller.room.title, '今晚开黑');
    expect(controller.qualities.map((q) => q.quality), ['原画', '超清', '流畅']);
    expect(controller.qualityIndex, 1);
    expect(session.state.status, PlaybackStatus.playing);
    expect(session.state.lineCount, 2);
    expect(engine.opens.single.uri.toString(), endsWith('250.flv'));
    expect((await store.history.all()).single.roomId, '6');
    expect(danmaku.connects, ['args-6']);
    expect(controller.chat.lines.map((line) => line.text), contains('弹幕服务器连接正常'));
    controller.dispose();
  });

  test('a detail without a cover keeps the card cover in the room and the history', () async {
    final card = LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '卡片上的名字', cover: 'https://img/c.jpg');
    final controller = controllerFor(FakeSite(liveRoom()), room: card);
    await controller.start();
    await settle();

    expect(controller.stage, RoomStage.playing);
    expect(controller.room.cover, 'https://img/c.jpg');
    expect((await store.history.all()).single.cover, 'https://img/c.jpg');
    controller.dispose();
  });

  test('a detail with a new cover replaces the card cover', () async {
    final card = LiveRoom(platform: SiteIds.bilibili, roomId: '6', cover: 'https://img/old.jpg');
    final detail = liveRoom().copyWith(cover: 'https://img/new.jpg');
    final controller = controllerFor(FakeSite(detail), room: card);
    await controller.start();
    await settle();

    expect(controller.room.cover, 'https://img/new.jpg');
    expect((await store.history.all()).single.cover, 'https://img/new.jpg');
    controller.dispose();
  });

  test('on mobile data the first quality follows the mobile-data preference (M12.3)', () async {
    await store.settings.setAll({Settings.preferResolution: '原画', Settings.preferResolutionCellular: '流畅'});
    final mobile = controllerFor(FakeSite(liveRoom()), network: NetworkKind.mobile);
    await mobile.start();
    await settle();
    expect(mobile.qualities[mobile.qualityIndex].quality, '流畅');
    mobile.dispose();

    final wifi = controllerFor(FakeSite(liveRoom()), network: NetworkKind.other);
    await wifi.start();
    await settle();
    expect(wifi.qualities[wifi.qualityIndex].quality, '原画');
    wifi.dispose();
  });

  test('issue #16: expired cards remain in bounded session history across a retry', () async {
    var clock = now;
    LiveSuperChatMessage card(String id, DateTime end) => LiveSuperChatMessage(
      messageId: id,
      userName: id,
      face: '',
      message: 'message $id',
      price: 30,
      startTime: now.subtract(const Duration(seconds: 10)),
      endTime: end,
      backgroundColor: '#EDF5FF',
      backgroundBottomColor: '#2A60B2',
    );
    final ended = card('ended', now.subtract(const Duration(seconds: 1)));
    final active = card('active', now.add(const Duration(seconds: 1)));
    final site = FakeSite(liveRoom())..superChats = [ended, active];
    final controller = controllerFor(site, clock: () => clock);
    await controller.start();
    await settle();
    expect(controller.superChats, [active]);
    expect(controller.superChatHistory.toSet(), {ended, active});
    clock = now.add(const Duration(seconds: 2));
    danmaku.emit(
      DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.superChat,
          userName: ended.userName,
          message: ended.message,
          color: LiveMessageColor.white,
          data: ended,
        ),
      ),
    );
    expect(controller.superChats, isEmpty);
    expect(controller.superChatHistory, hasLength(2), reason: 'duplicate replay is not stored again');
    await controller.retry();
    await settle();
    expect(controller.superChatHistory, hasLength(2), reason: 'retrying keeps this room session');
    controller.dispose();
    expect(controller.superChatHistory, isEmpty);
  });

  test('issue #16: identical paid text at different server times is not one event', () async {
    final controller = controllerFor(FakeSite(liveRoom()));
    addTearDown(controller.dispose);
    await controller.start();
    await Future<void>.delayed(const Duration(seconds: 1));
    LiveSuperChatMessage card(int seconds) => LiveSuperChatMessage(
      userName: 'viewer',
      face: '',
      message: 'same paid text',
      price: 30,
      startTime: now.add(Duration(seconds: seconds)),
      endTime: now.add(Duration(seconds: seconds + 300)),
      backgroundColor: '',
      backgroundBottomColor: '',
    );
    void emit(LiveSuperChatMessage card) => danmaku.emit(
      DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.superChat,
          userName: card.userName,
          message: card.message,
          color: LiveMessageColor.white,
          data: card,
        ),
      ),
    );
    emit(card(0));
    emit(card(1));
    emit(card(1));
    expect(controller.superChatHistory, hasLength(2), reason: 'two purchases, one replay');
    expect(controller.superChatHistory.map((card) => card.startTime), [now, now.add(const Duration(seconds: 1))]);
    expect(controller.unreadSuperChatCount, 2);
    controller.markSuperChatsRead();
    expect(controller.unreadSuperChatCount, 0);
    emit(card(1));
    expect(controller.unreadSuperChatCount, 0, reason: 'a replay cannot make a read event unread');
    emit(card(2));
    expect(controller.unreadSuperChatCount, 1);
  });

  test('issue #16: history is capped without saving it to the store', () async {
    final site = FakeSite(liveRoom())
      ..superChats = [
        for (var i = 0; i < LiveRoomController.superChatHistoryLimit + 20; i++)
          LiveSuperChatMessage(
            messageId: '$i',
            userName: '$i',
            face: '',
            message: '$i',
            price: 30,
            startTime: now.add(Duration(seconds: i)),
            endTime: now.add(const Duration(hours: 1)),
            backgroundColor: '#EDF5FF',
            backgroundBottomColor: '#2A60B2',
          ),
      ];
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    expect(controller.superChatHistory, hasLength(LiveRoomController.superChatHistoryLimit));
    expect(controller.superChatHistory.first.messageId, '20');
    controller.dispose();
  });

  test('chat passes the block list; audience, super chats, retractions and notices', () async {
    await store.blockLists.add(BlockKind.keyword, '广告');
    final site = FakeSite(liveRoom())
      ..superChats = [
        LiveSuperChatMessage(
          userName: '老板',
          face: '',
          message: '加油',
          price: 30,
          startTime: now.subtract(const Duration(seconds: 10)),
          endTime: now.add(const Duration(minutes: 1)),
          backgroundColor: '#EDF5FF',
          backgroundBottomColor: '#2A60B2',
        ),
      ];
    final controller = controllerFor(site);
    final flying = <String>[];
    controller.flying.listen((message) => flying.add(message.message));
    await controller.start();
    await settle();
    expect(controller.superChats.single.userName, '老板');

    danmaku
      ..chat('你好', id: 'm1')
      ..chat('看广告领红包')
      ..chat('再见', user: '路人', id: 'm2');
    expect(flying, ['你好', '再见']);
    expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.chat).map((line) => line.text), [
      '你好',
      '再见',
    ]);

    danmaku.emit(
      const DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.retraction,
          userName: '',
          message: '',
          color: LiveMessageColor.white,
          data: LiveRetraction.message('m1'),
        ),
      ),
    );
    expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.chat).map((line) => line.text), ['再见']);

    // Bilibili's new online count (C-1) sits beside the heat, not over it.
    danmaku.emit(
      const DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.online,
          userName: '',
          message: '',
          color: LiveMessageColor.white,
          data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: 3456),
        ),
      ),
    );
    final figures = audienceFigures(controller.room);
    expect(figures.map((f) => f.type), [AudienceMetricType.onlineViewers, AudienceMetricType.popularity]);
    expect(figures.map((f) => f.value), ['3456', '120000']);

    danmaku
      ..emit(
        const DanmakuReceived(
          LiveMessage(
            type: LiveMessageType.notice,
            userName: '',
            message: '欢迎来到直播间',
            color: LiveMessageColor.white,
            data: LiveNoticeKind.system,
          ),
        ),
      )
      ..emit(const DanmakuReconnecting(DanmakuInterruption.disconnected))
      ..emit(const DanmakuClosed(DanmakuCloseReason.reconnectsExhausted));
    final tail = controller.chat.lines.reversed.take(3).toList().reversed.toList();
    expect(tail.map((line) => line.kind), [ChatLineKind.notice, ChatLineKind.system, ChatLineKind.system]);
    expect(tail.last.text, contains('多次重连失败'));

    await controller.blockUser('路人');
    expect(await store.blockLists.list(BlockKind.user), ['路人']);
    expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.chat), isEmpty);
    controller.dispose();
  });

  test('an offline room does not play; it starts by itself when the refresh finds it live (B-24)', () async {
    final site = FakeSite(liveRoom(status: LiveStatus.offline));
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    expect(controller.stage, RoomStage.offline);
    expect(engine.opens, isEmpty);
    expect(danmaku.connects, isEmpty);

    site.room = liveRoom();
    await controller.refreshDetail();
    await settle();
    expect(controller.stage, RoomStage.playing);
    expect(danmaku.connects, ['args-6']);

    // The broadcast ended and came back: the closed danmaku connects again.
    danmaku.emit(const DanmakuClosed(DanmakuCloseReason.connectionFailed));
    await controller.refreshDetail();
    await settle();
    expect(danmaku.connects, ['args-6', 'args-6']);
    controller.dispose();
  });

  test('a carousel room plays its video from play_time (1-1)', () async {
    final carousel = liveRoom(status: LiveStatus.carousel);
    await store.follows.add(carousel);
    final site = CarouselFakeSite(carousel);
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    expect(controller.stage, RoomStage.offline, reason: 'G1 A: the user starts it');
    expect(engine.opens, isEmpty);

    await controller.playCarousel();
    await settle();
    expect(controller.stage, RoomStage.playing, reason: '${controller.failure}');
    expect(controller.playingCarousel, isTrue);
    expect(controller.qualities.map((q) => q.quality), ['轮播']);
    final first = engine.opens.single;
    expect(first.uri.path, '/video-0.mp4');
    expect(first.start, const Duration(seconds: 37), reason: "the loop's play_time, not the video's start");
    expect(first.onDemand, isFalse, reason: "the video's end is no replay's end: recovery takes the next");
    // The room is still not on air: follows keep it under 未开播.
    expect(controller.room.isPlayableNow, isFalse);
    expect((await store.follows.find(SiteIds.bilibili, '6'))!.isPlayableNow, isFalse);

    // The video ends: the recovery asks again and plays the next from its
    // play_time.
    engine.emit(const EngineCompleted());
    await settle();
    expect(engine.opens.last.uri.path, '/video-1.mp4');
    expect(engine.opens.last.start, const Duration(seconds: 5));
    expect(controller.playingCarousel, isTrue);

    // The streamer comes on air: the refresh plays the broadcast instead.
    site.room = liveRoom();
    await controller.refreshDetail();
    await settle();
    expect(controller.playingCarousel, isFalse);
    expect(engine.opens.last.uri.path, endsWith('.flv'));
    expect(engine.opens.last.start, isNull);
    controller.dispose();
  });

  test('only a carousel the app can play has the button; a reload is offline again (1-1)', () async {
    final site = CarouselFakeSite(liveRoom(status: LiveStatus.carousel));
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    await controller.playCarousel();
    await settle();
    expect(controller.playingCarousel, isTrue);
    // "刷新" (the room again) shows the carousel state, not its video.
    await controller.load();
    await settle();
    expect((controller.stage, controller.playingCarousel), (RoomStage.offline, false));
    expect(carouselPlayable(controller.room), isTrue);
    controller.dispose();

    // Another platform's carousel (none plays one yet) and a plain offline
    // room do nothing.
    for (final room in [
      LiveRoom(platform: SiteIds.youtube, roomId: '6', liveStatus: LiveStatus.carousel),
      liveRoom(status: LiveStatus.offline),
    ]) {
      expect(carouselPlayable(room), isFalse);
      final other = controllerFor(CarouselFakeSite(room), room: room);
      await other.start();
      await settle();
      await other.playCarousel();
      await settle();
      expect(other.stage, RoomStage.offline);
      other.dispose();
    }
    expect(engine.opens.where((media) => media.uri.path.endsWith('.mp4')), hasLength(1));
  });

  group('C01.6 danmaku of a new broadcast', () {
    /// The light refresh's answer: no danmaku arguments (SHOWROOM, Kilakila,
    /// TwitCasting, Baidu).
    LiveRoom refreshAnswer({LiveStatus status = LiveStatus.live, DateTime? startedAt, Object? danmakuData}) => LiveRoom(
      platform: SiteIds.bilibili,
      roomId: '6',
      liveStatus: status,
      startedAt: startedAt,
      danmakuData: danmakuData,
    );

    List<String> systemLines(LiveRoomController controller) => [
      for (final line in controller.chat.lines)
        if (line.kind == ChatLineKind.system) line.text,
    ];

    test('a new broadcast found by the refresh reconnects the danmaku with fresh arguments (C01.6)', () async {
      final first = DateTime.utc(2026, 10, 1, 10);
      final site = RefreshingFakeSite(
        liveRoom(startedAt: first),
        refreshRoom: refreshAnswer(startedAt: first),
      );
      final controller = controllerFor(site);
      await controller.start();
      await settle();
      expect(danmaku.connects, ['args-6']);
      final entries = site.detailCalls;

      // The same broadcast, its start a little off (platforms that count
      // back from the time on air): no extra request, no reconnect.
      site.refreshRoom = refreshAnswer(startedAt: first.add(const Duration(seconds: 40)));
      for (var i = 0; i < 3; i++) {
        await controller.refreshDetail();
        await settle();
      }
      expect(site.refreshCalls, 3);
      expect(site.detailCalls, entries);
      expect(danmaku.connects, ['args-6']);

      final second = first.add(const Duration(hours: 3));
      site
        ..room = liveRoom(startedAt: second).copyWith(danmakuData: 'args-7')
        ..refreshRoom = refreshAnswer(startedAt: second);
      final before = systemLines(controller).length;
      await controller.refreshDetail();
      await settle();
      expect(site.detailCalls, entries + 1);
      expect(danmaku.connects, ['args-6', 'args-7']);
      expect(systemLines(controller).sublist(before), ['开始连接弹幕服务器', '弹幕服务器连接正常']);

      // Once per broadcast.
      await controller.refreshDetail();
      await settle();
      expect(site.detailCalls, entries + 1);
      expect(danmaku.connects, hasLength(2));
      controller.dispose();
    });

    test('a broadcast that went off air and came back reconnects with fresh arguments (C01.6)', () async {
      final site = RefreshingFakeSite(liveRoom(), refreshRoom: refreshAnswer());
      final controller = controllerFor(site);
      await controller.start();
      await settle();
      // Off air while the session still plays (it recovers by itself).
      site.refreshRoom = refreshAnswer(status: LiveStatus.offline);
      await controller.refreshDetail();
      await settle();
      expect(controller.stage, RoomStage.playing);
      expect(danmaku.connects, ['args-6']);

      site
        ..room = liveRoom().copyWith(danmakuData: 'args-7')
        ..refreshRoom = refreshAnswer();
      await controller.refreshDetail();
      await settle();
      expect(danmaku.connects, ['args-6', 'args-7']);
      await controller.refreshDetail();
      await settle();
      expect(danmaku.connects, ['args-6', 'args-7']);
      controller.dispose();
    });

    test('a closed connection asks the room entry for arguments when the refresh has none (C01.6)', () async {
      final site = RefreshingFakeSite(liveRoom(), refreshRoom: refreshAnswer());
      final controller = controllerFor(site);
      await controller.start();
      await settle();
      final entries = site.detailCalls;

      // Baidu's signatures ran out: the room entry has new ones.
      site.room = liveRoom().copyWith(danmakuData: 'args-7');
      danmaku.emit(const DanmakuClosed(DanmakuCloseReason.credentialsUnavailable));
      await controller.refreshDetail();
      await settle();
      expect(danmaku.connects, ['args-6', 'args-7']);
      expect(site.detailCalls, entries + 1);

      // A refresh that brings arguments is used as it is.
      site.refreshRoom = refreshAnswer(danmakuData: 'args-8');
      danmaku.emit(const DanmakuClosed(DanmakuCloseReason.credentialsUnavailable));
      await controller.refreshDetail();
      await settle();
      expect(danmaku.connects, ['args-6', 'args-7', 'args-8']);
      expect(site.detailCalls, entries + 1);
      controller.dispose();
    });

    test('a failed room entry reconnects with the arguments the room has, quietly (C01.6)', () async {
      final site = RefreshingFakeSite(liveRoom(), refreshRoom: refreshAnswer());
      final controller = controllerFor(site);
      await controller.start();
      await settle();
      site.detailError = const NetworkFailure(SiteIds.bilibili, 'test');
      danmaku.emit(const DanmakuClosed(DanmakuCloseReason.connectionFailed));
      await controller.refreshDetail();
      await settle();
      expect(danmaku.connects, ['args-6', 'args-6']);
      expect(toasts, isEmpty);
      expect(controller.stage, RoomStage.playing);
      controller.dispose();
    });

    test("changing YouTube's all-chat setting reconnects a YouTube room (C01.6)", () async {
      final room = LiveRoom(
        platform: SiteIds.youtube,
        roomId: 'UC_test',
        nick: '主播',
        liveStatus: LiveStatus.live,
        danmakuData: 'yt-args',
      );
      final site = FakeSite(room)..siteId = SiteIds.youtube;
      final controller = controllerFor(site, room: room);
      await controller.start();
      await settle();
      expect(danmaku.connects, ['yt-args']);
      await store.settings.set(Settings.youtubeShowAllChat, true);
      await settle();
      expect(danmaku.connects, ['yt-args', 'yt-args']);
      await store.settings.set(Settings.youtubeShowAllChat, false);
      await settle();
      expect(danmaku.connects, hasLength(3));
      controller.dispose();
    });

    test("YouTube's all-chat setting leaves other rooms alone (C01.6)", () async {
      final controller = controllerFor(FakeSite(liveRoom()));
      await controller.start();
      await settle();
      await store.settings.set(Settings.youtubeShowAllChat, true);
      await settle();
      expect(danmaku.connects, ['args-6']);
      controller.dispose();
    });
  });

  for (final phase in ['detail', 'qualities', 'urls']) {
    test('issue #15: exported playback failures identify $phase without raw platform details', () async {
      final controller = controllerFor(_PhaseFailureSite(phase));
      await controller.start();
      final failures = AppLog.instance.entries.where(
        (entry) => entry.tag == 'playback' && entry.message.startsWith('playback-failure'),
      );
      expect(failures, isNotEmpty);
      final entry = failures.last;
      expect(entry.level, LogLevel.warning);
      expect(entry.message, contains('site=bilibili'));
      expect(entry.message, contains('phase=$phase'));
      expect(entry.message, contains('kind=ApiChanged'));
      expect(entry.message, matches(RegExp('room=[0-9a-f]{6}')));
      expect(entry.message, isNot(contains('test-only-private-context')));
      controller.dispose();
    });
  }

  test('issue 15: exported diagnostics retain only a fixed descriptor reason, never the raw private detail', () async {
    final controller = controllerFor(
      _PhaseFailureSite(
        'qualities',
        failure: const ApiChanged.withCode(
          SiteIds.douyu,
          ApiFailureCode.douyuDescriptorExpiry,
          'private-response-fixture Cookie: fixture-session',
        ),
      ),
    );
    await controller.start();
    final failure = AppLog.instance.entries.where((entry) => entry.message.startsWith('playback-failure')).last;
    expect(failure.message, contains('phase=qualities kind=ApiChanged code=douyuDescriptorExpiry'));
    expect(failure.message, isNot(contains('private-response-fixture')));
    expect(failure.message, isNot(contains('fixture-session')));
    controller.dispose();
  });

  test('issue135 exported unavailable diagnostics distinguish refusal without private details', () async {
    final controller = controllerFor(
      _PhaseFailureSite(
        'qualities',
        failure: const StreamUnavailable.withCode(
          SiteIds.douyu,
          ApiFailureCode.douyuPlayUnavailable,
          'private-response-fixture Cookie: fixture-session',
        ),
      ),
    );
    await controller.start();
    final failure = AppLog.instance.entries.where((entry) => entry.message.startsWith('playback-failure')).last;
    expect(failure.message, contains('phase=qualities kind=StreamUnavailable code=douyuPlayUnavailable'));
    expect(failure.message, isNot(contains('private-response-fixture')));
    expect(failure.message, isNot(contains('fixture-session')));
    controller.dispose();
  });

  test('a failed detail keeps the card and says why; retry loads again', () async {
    final site = FakeSite(liveRoom())..detailError = const NeedsLogin(SiteIds.bilibili);
    final controller = controllerFor(site);
    await controller.start();
    expect(controller.stage, RoomStage.failed);
    expect(controller.room.nick, '卡片上的名字');
    expect(controller.room.isLiveStatusPending, isTrue);
    expect(failureText(controller.failure), '需要登录该平台后才能观看');

    site.detailError = null;
    await controller.retry();
    await settle();
    expect(controller.stage, RoomStage.playing);
    controller.dispose();
  });

  test('a restricted live room explains the restriction when no stream comes', () async {
    final site = FakeSite(liveRoom(restriction: LiveRestriction.paid))..qualities = const [];
    final controller = controllerFor(site);
    await controller.start();
    expect(controller.stage, RoomStage.unplayable);
    expect(restrictionReason(controller.room.effectiveRestriction), contains('付费直播'));
    controller.dispose();
  });

  test('E05.4 c3: a live room without danmaku arguments does not connect (AcFun paid show)', () async {
    final site = FakeSite(liveRoom(restriction: LiveRestriction.paid, danmakuData: null))..qualities = const [];
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    expect(controller.stage, RoomStage.unplayable);
    expect(controller.chatConnection, ChatConnection.idle);
    expect(danmaku.connects, isEmpty);
    expect(controller.chat.lines.map((line) => line.text), isNot(contains('弹幕连接失败')));
    controller.dispose();

    // A playing room without arguments stays idle too.
    final playing = controllerFor(FakeSite(liveRoom(danmakuData: null)));
    await playing.start();
    await settle();
    expect(playing.stage, RoomStage.playing);
    expect(playing.chatConnection, ChatConnection.idle);
    expect(danmaku.connects, isEmpty);
    playing.dispose();
  });

  test('a quality the platform downgrades shows the quality really played', () async {
    final site = DowngradingSite(liveRoom(), applied: 250);
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    expect(controller.qualityIndex, 1);
    expect(toasts, ['平台实际返回 超清，已按真实画质播放'], reason: 'C01.4: entering the room says it once');

    await controller.selectQuality(controller.qualityIndex == 0 ? 1 : 0);
    expect(controller.qualityIndex, 1);
    expect(toasts, hasLength(2), reason: 'a quality picked by hand is answered every time');
    expect(toasts.last, contains('超清'));
    controller.dispose();
  });

  group('C01.4: the quality shown is the one the platform served', () {
    test('a Bilibili guest in a room listing 原画 only sees the 超清 it is served, told once', () async {
      final controller = controllerFor(
        _bilibiliGuestOriginalOnly(),
        room: LiveRoom(platform: SiteIds.bilibili, roomId: '42062'),
      );
      await controller.start();
      await settle();

      expect(controller.stage, RoomStage.playing, reason: '${controller.failure}');
      final shown = controller.qualities[controller.qualityIndex];
      expect((shown.quality, shown.id, shown.isPlaybackUnconfirmed), ('超清', 250, false));
      expect(controller.qualities.map((q) => q.quality), ['超清']);
      expect(toasts, ['平台实际返回 超清，已按真实画质播放']);

      // Refreshing the room (also the reload after a failed stream) plays the
      // same tier again without saying it again.
      await controller.load();
      await settle();
      expect(controller.qualities[controller.qualityIndex].quality, '超清');
      expect(toasts, hasLength(1));
      controller.dispose();
    });

    test('a quality the platform did not confirm keeps the request, unconfirmed, without a toast', () async {
      final controller = controllerFor(_UnconfirmedSite(liveRoom()));
      await controller.start();
      await settle();
      final shown = controller.qualities[controller.qualityIndex];
      expect((shown.quality, shown.isPlaybackUnconfirmed), ('原画', true));
      expect(toasts, isEmpty);
      controller.dispose();
    });
  });

  test('B-7: a refused cookie is said once per refusal, and not after the room closed', () async {
    final site = _RefusingSite(liveRoom())..siteId = SiteIds.twitch;
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    final before = toasts.length;
    site.refusals.add(null);
    expect(toasts.skip(before), ['Twitch 的 Cookie 已失效，已改为匿名观看，请在账号页重新填写']);
    controller.dispose();
    await settle();
    site.refusals.add(null);
    expect(toasts.skip(before), hasLength(1), reason: 'the subscription ended with the room');
    expect(site.refusals.hasListener, isFalse);
  });

  test('issue125 cookie refusal explains guest playback without claiming expiry', () async {
    final site = _RefusingSite(liveRoom())..siteId = SiteIds.kuaishou;
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    final before = toasts.length;
    site.refusals.add(null);
    expect(toasts.skip(before), ['快手拒绝了 Cookie 请求，已改为游客播放公开直播；保存的 Cookie 保持不变。']);
    controller.dispose();
    await settle();
    site.refusals.add(null);
    expect(toasts.skip(before), hasLength(1));
    expect(site.refusals.hasListener, isFalse);
  });

  test('issue135 cookie refusal explains guest playback without claiming expiry', () async {
    final site = _RefusingSite(liveRoom())..siteId = SiteIds.douyu;
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    final before = toasts.length;
    site.refusals.add(null);
    expect(toasts.skip(before), ['斗鱼登录请求未取到直播流，已改用游客线路；保存的 Cookie 保持不变。']);
    controller.dispose();
    await settle();
    site.refusals.add(null);
    expect(toasts.skip(before), hasLength(1));
    expect(site.refusals.hasListener, isFalse);
  });

  test('a recovery that switched quality shows the quality now played (11-1)', () async {
    final site = _ProfileChangedSite(liveRoom());
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    expect(controller.qualities[controller.qualityIndex].quality, '720p60');
    final toastsBefore = toasts.length;
    var notified = 0;
    controller.addListener(() => notified++);

    // The stream drops; the recovery's playlist has the new profile only.
    engine.emit(
      const EngineError(PlayerException(message: 'connection reset', type: PlayerErrorType.network, code: 'transport')),
    );
    await settle();
    expect(site.recoveries, ['720p60']);
    expect(engine.opens.last.uri.path, '/1080p60.m3u8');
    final shown = controller.qualities[controller.qualityIndex];
    expect((shown.quality, shown.isPlaybackUnconfirmed), ('1080p60', false), reason: 'the button names it, no "?"');
    expect(controller.qualities.map((q) => q.quality), ['1080p60', '360p'], reason: "C01.4: in the request's place");
    expect(notified, greaterThan(0), reason: 'the button hears of it');
    expect(toasts, hasLength(toastsBefore), reason: 'C01.4: a recovery says nothing');

    // The next recovery asks for the tier that plays now.
    engine.emit(const EngineError(PlayerException(message: 'reset', type: PlayerErrorType.network, code: 'b')));
    await settle();
    expect(site.recoveries, ['720p60', '1080p60']);
    expect(controller.qualities[controller.qualityIndex].quality, '1080p60');
    controller.dispose();
  });

  test('a platform without danmaku says so once', () async {
    final controller = controllerFor(FakeSite(liveRoom()), danmakuSupported: false);
    await controller.start();
    await settle();
    expect(danmaku.connects, isEmpty);
    expect(controller.chat.lines.single.text, '该平台暂不支持弹幕');
    controller.dispose();
  });

  group("B06: Bilibili's names", () {
    LiveMessage chat(String user) =>
        LiveMessage(type: LiveMessageType.chat, userName: user, message: '前排', color: LiveMessageColor.white);

    test('a guest: full names say nothing; masked ones bring the hint; no system line for them', () async {
      final controller = controllerFor(FakeSite(liveRoom()));
      expect(controller.nameHint, ChatNameHint.none, reason: 'not connected yet');
      await controller.start();
      await settle();
      expect(controller.nameHint, ChatNameHint.none, reason: 'guests get full names since 2026-10');
      danmaku
        ..emit(DanmakuReceived(chat('观***')))
        ..emit(DanmakuReceived(chat('离**')))
        ..emit(DanmakuReceived(chat('V***')));
      expect(controller.nameHint, ChatNameHint.guest, reason: 'the names came masked');
      expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.system).map((line) => line.text), [
        '开始连接弹幕服务器',
        '弹幕服务器连接正常',
      ]);
      await store.settings.setAll({Settings.enableDanmakuDisplay: false, Settings.enablePipDanmaku: false});
      await settle();
      expect(controller.nameHint, ChatNameHint.none, reason: 'danmaku off');
      controller.dispose();
    });

    test('signed in: none; three masked names and no full one say the login expired', () async {
      await store.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=a; DedeUserID=1');
      final site = FakeSite(liveRoom());
      final controller = controllerFor(site);
      await controller.start();
      await settle();
      expect(controller.nameHint, ChatNameHint.none);
      danmaku
        ..emit(DanmakuReceived(chat('观***')))
        ..emit(DanmakuReceived(chat('离**')));
      expect(controller.nameHint, ChatNameHint.none, reason: 'two are not enough');
      danmaku.emit(DanmakuReceived(chat('V***')));
      expect(controller.nameHint, ChatNameHint.loginExpired);
      danmaku.emit(DanmakuReceived(chat('完整的名字')));
      expect(controller.nameHint, ChatNameHint.none, reason: 'a full name: the login works');

      // Signing out connects again with the guest's credentials.
      final connects = danmaku.connects.length;
      site.room = liveRoom().copyWith(danmakuData: 'args-6-guest');
      await store.secrets.setCookie(SiteIds.bilibili, '');
      await settle();
      expect(controller.nameHint, ChatNameHint.none, reason: 'a new connection: no masked names yet');
      expect(danmaku.connects.sublist(connects), ['args-6-guest']);
      controller.dispose();
    });

    test('other platforms and other logins: no hint, no reconnect', () async {
      final room = LiveRoom(
        platform: SiteIds.douyu,
        roomId: '6',
        nick: '主播',
        liveStatus: LiveStatus.live,
        danmakuData: 'args-6',
      );
      final controller = controllerFor(FakeSite(room), room: room);
      await controller.start();
      await settle();
      danmaku.emit(DanmakuReceived(chat('观***')));
      expect(controller.nameHint, ChatNameHint.none);
      await store.secrets.setCookie(SiteIds.douyu, 'acf_uid=1');
      await store.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=a');
      await settle();
      expect(danmaku.connects, ['args-6']);
      controller.dispose();
    });
  });

  test("E06.3: a YY room plays stream-manager's FLV, two lines, at the quality 3.x's 原画 picks", () async {
    final site = YySite(
      ReplayHttp(
        [
          for (final name in ['S05-detail-live', 'S06-streams-g1', 'S06-streams-g2', 'S06-streams-g2-l10'])
            ReplaySample.load('../../fixtures/yy/$name'),
        ],
        ignoredQuery: const {'seq', 'send_time', 'sequence', 'osversion', 'width', 'height'},
      ),
      flvFirst: true,
      now: () => DateTime.utc(2026, 9, 27, 16, 56, 56),
    );
    final controller = controllerFor(
      site,
      room: LiveRoom(platform: SiteIds.yy, roomId: '22490906'),
    );
    await controller.start();
    await settle();

    expect(controller.stage, RoomStage.playing, reason: '${controller.failure}');
    expect(controller.qualities.map((q) => q.quality), ['高清', '流畅']);
    expect(controller.qualityIndex, 0);
    expect(session.state.lineCount, 2);
    expect(engine.opens.single.uri.path, endsWith('.flv'));
    expect(toasts, isEmpty);
    controller.dispose();
  });

  test("E06.3: YY's FLV names under 3.x's five preferences", () {
    const two = [LivePlayQuality(quality: '高清', id: '2'), LivePlayQuality(quality: '流畅', id: '1')];
    const three = [
      LivePlayQuality(quality: '蓝光', id: '3'),
      LivePlayQuality(quality: '高清', id: '2'),
      LivePlayQuality(quality: '流畅', id: '1'),
    ];
    const preferences = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅'];
    expect(
      [for (final name in preferences) two[defaultQualityIndex(two, name)].quality],
      ['高清', '高清', '流畅', '流畅', '流畅'],
    );
    expect(
      [for (final name in preferences) three[defaultQualityIndex(three, name)].quality],
      ['蓝光', '高清', '高清', '流畅', '流畅'],
    );
  });

  test("the starting quality follows 3.x's preference rules", () {
    const qualities = [LivePlayQuality(quality: '原画'), LivePlayQuality(quality: '蓝光'), LivePlayQuality(quality: '高清')];
    expect(defaultQualityIndex(qualities, '原画'), 0);
    expect(defaultQualityIndex(qualities, '流畅'), 2);
    expect(defaultQualityIndex(qualities, '超清'), 2);
    expect(defaultQualityIndex(qualities, '蓝光4M'), 1);
    expect(defaultQualityIndex(const [], '原画'), 0);
  });

  test('with 优先 H.264 the name match skips an HEVC quality (G01.3)', () {
    const flv = LivePlayQuality(quality: 'FLV', codec: 'avc');
    const original = LivePlayQuality(quality: '原画', codec: 'hevc');
    expect(defaultQualityIndex(const [flv, original], '原画', preferH264: true), 0);
    expect(defaultQualityIndex(const [flv, original], '原画'), 1, reason: 'off: the name wins, as before');
    expect(defaultQualityIndex(const [original, flv], '原画'), 0);
    // Only HEVC on offer: it is still the one chosen.
    expect(defaultQualityIndex(const [original], '原画', preferH264: true), 0);
    expect(
      defaultQualityIndex(const [original, LivePlayQuality(quality: '超清', codec: 'hevc')], '原画', preferH264: true),
      0,
    );
    // Without hints the rule is unchanged.
    const unhinted = [LivePlayQuality(quality: 'FLV'), LivePlayQuality(quality: '原画')];
    expect(defaultQualityIndex(unhinted, '原画', preferH264: true), 1);
    // The skipped match falls back to the relative position.
    const ladder = [
      LivePlayQuality(quality: '蓝光', codec: 'avc'),
      LivePlayQuality(quality: '超清', codec: 'hevc'),
      LivePlayQuality(quality: '高清', codec: 'avc'),
      LivePlayQuality(quality: '流畅', codec: 'avc'),
    ];
    expect(defaultQualityIndex(ladder, '超清', preferH264: true), 2);
    expect(defaultQualityIndex(ladder, '超清'), 1);
    // A fallback position on HEVC moves to the nearest other quality.
    const hevcAtPosition = [
      LivePlayQuality(quality: '蓝光', codec: 'avc'),
      LivePlayQuality(quality: '高清', codec: 'avc'),
      LivePlayQuality(quality: '超清', codec: 'hevc'),
      LivePlayQuality(quality: '流畅', codec: 'avc'),
    ];
    expect(defaultQualityIndex(hevcAtPosition, '超清', preferH264: true), 1);
  });

  group('G01.3: the starting quality of an Inke-like room', () {
    const flv = LivePlayQuality(quality: 'FLV', id: 'flv', codec: 'avc');
    const original = LivePlayQuality(quality: '原画', id: 'origin', sort: 1, codec: 'hevc');

    test('with 优先 H.264 on (the default) the H.264 FLV opens, not the HEVC original', () async {
      final site = FakeSite(liveRoom())..qualities = const [flv, original];
      final controller = controllerFor(site);
      await controller.start();
      await settle();
      expect(store.settings.get(Settings.preferResolution), '原画');
      expect(store.settings.get(Settings.preferH264), isTrue);
      expect(controller.qualityIndex, 0);
      expect(engine.opens.single.uri.toString(), endsWith('/flv.flv'));
      controller.dispose();
    });

    test('with 优先 H.264 off the original is chosen by its name', () async {
      await store.settings.set(Settings.preferH264, false);
      final site = FakeSite(liveRoom())..qualities = const [original, flv];
      final controller = controllerFor(site);
      await controller.start();
      await settle();
      expect(controller.qualityIndex, 0);
      expect(engine.opens.single.uri.toString(), endsWith('/origin.flv'));
      controller.dispose();
    });

    test('picking the original by hand plays it', () async {
      final site = FakeSite(liveRoom())..qualities = const [flv, original];
      final controller = controllerFor(site);
      await controller.start();
      await settle();
      await controller.selectQuality(1);
      await settle();
      expect(controller.qualityIndex, 1);
      expect(engine.opens.last.uri.toString(), endsWith('/origin.flv'));
      controller.dispose();
    });
  });

  test('G02.2: every recovery attempt leaves one app log line with its count and cause', () async {
    final controller = controllerFor(FakeSite(liveRoom()));
    await controller.start();
    await settle();
    expect(session.state.status, PlaybackStatus.playing);
    List<String> lines() => [
      for (final entry in AppLog.instance.entries)
        if (entry.tag == 'playback') entry.message,
    ];
    final before = lines().length;

    // The reopened line does not play yet: the recovery goes on.
    engine
      ..onOpen = ((_) async {})
      ..emit(
        const EngineError(
          PlayerException(message: 'connection reset', type: PlayerErrorType.network, code: 'transport'),
        ),
      );
    await settle();
    expect(session.state.recovery, 1);
    expect(lines().skip(before), ['recovering #1 transport']);
    expect(AppLog.instance.entries.last.format(), endsWith('[INFO] playback: recovering #1 transport'));

    // Playing again ends it; the next drop counts on.
    engine
      ..emit(const EngineBuffering(buffering: false))
      ..emit(const EnginePlaying(playing: true))
      ..emit(const EngineError(PlayerException(message: 'reset', type: PlayerErrorType.network, code: 'b')));
    await settle();
    expect(lines().skip(before), ['recovering #1 transport', 'recovering #2 b']);
    controller.dispose();
  });

  test('G03.1: entering the room leaves one timing line, its marks in order', () async {
    final site = _SlowSteps(liveRoom());
    final controller = controllerFor(site);
    bool timing(LogEntry entry) => entry.tag == 'playback' && entry.message.startsWith('playback-timing ');
    final before = AppLog.instance.entries.where(timing).length;
    await controller.start();
    await settle();
    expect(session.state.status, PlaybackStatus.playing);
    List<String> lines() =>
        [for (final entry in AppLog.instance.entries.where(timing)) entry.message].skip(before).toList();
    expect(lines(), isEmpty, reason: 'mpv says playing before any picture');
    engine.emit(const EngineVideoSize(1280, 720));
    await settle();

    final line = lines().single;
    final fields = {for (final field in line.split(' ').skip(1)) field.split('=').first: field.split('=').last};
    expect(fields.keys, [
      'site',
      'room',
      'route',
      'engine',
      'result',
      'detail',
      'qualities',
      'urls',
      'engineReady',
      'input',
      'load',
      'firstFrame',
      'playing',
      'total',
    ]);
    expect(fields['site'], SiteIds.bilibili);
    expect(fields['room'], LiveRoomController.roomTag(SiteIds.bilibili, '6'));
    expect(fields['room'], hasLength(6));
    expect((fields['route'], fields['engine'], fields['result']), ('direct', 'new', 'playing'));
    int ms(String name) => int.parse(fields[name]!);
    // T0 -> T1 holds the detail's second, T2 -> T3 the URLs' second: the
    // marks are taken in order, each after its step.
    expect(ms('detail'), greaterThanOrEqualTo(1000));
    expect(ms('qualities'), inInclusiveRange(0, 999));
    expect(ms('urls'), greaterThanOrEqualTo(1000));
    for (final name in ['engineReady', 'input', 'load', 'firstFrame', 'playing']) {
      expect(ms(name), isNonNegative, reason: name);
    }
    // The steps add up to the total (each one rounded down to whole ms).
    final steps = [for (final name in PlaybackTiming.segmentNames) int.tryParse(fields[name]!) ?? 0];
    expect(ms('total') - steps.reduce((a, b) => a + b), inInclusiveRange(0, steps.length));
    expect(AppLog.instance.entries.where(timing).last.format(), endsWith('[INFO] playback: $line'));

    // A quality switch or a reload of the room is no entry: no line.
    await controller.selectQuality(controller.qualityIndex == 0 ? 1 : 0);
    await controller.load();
    await settle();
    expect(engine.opens, hasLength(3));
    expect(lines(), [line]);
    controller.dispose();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('texts: time on air, audience numbers', () {
    expect(startedAgo(now.subtract(const Duration(minutes: 80)), now), '已开播 1 小时 20 分');
    expect(startedAgo(now.subtract(const Duration(seconds: 20)), now), '刚刚开播');
    // One formatter for the room and the cards (M13.16): days past 24 hours.
    expect(startedAgo(now.subtract(const Duration(hours: 51, minutes: 49)), now), '已开播 2 天 3 小时');
    expect(elapsedText(const Duration(minutes: 7)), '7 分钟');
    expect(elapsedText(const Duration(seconds: 10)), '1 分钟');
    expect(elapsedText(const Duration(hours: 23, minutes: 59)), '23 小时 59 分');
    expect(elapsedText(const Duration(hours: 24)), '1 天 0 小时');
    final live = LiveRoom(platform: 'douyu', roomId: '1', liveStatus: LiveStatus.live);
    expect(
      liveDuration(live.copyWith(startedAt: now.subtract(const Duration(hours: 51, minutes: 49))), now),
      '已播 2 天 3 小时',
    );
    expect(readableAudience('123456'), '12.3万');
    expect(readableAudience('999'), '999');
  });
}

/// Picarto after the streamer changed the profile (UPGRADES 11-1): the
/// room opens at 720p60; a recovery's playlist has 1080p60 only, which it
/// plays and names ([LivePlayUrlResolution.appliedQuality]).
class _ProfileChangedSite extends FakeSite implements LivePlayRecoveryResolver {
  new(super.room) {
    siteId = SiteIds.picarto;
    qualities = const [LivePlayQuality(quality: '720p60', id: '720p60'), LivePlayQuality(quality: '360p', id: '360p')];
  }

  /// Recovery requests so far, by the quality asked for.
  final List<String> recoveries = [];

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    recoveries.add('${quality.selectionId}');
    return LivePlayUrlResolution.lines(
      const [LivePlayLine('https://edge.example/1080p60.m3u8')],
      appliedQualityData: '1080p60',
      appliedQuality: const LivePlayQuality(quality: '1080p60', id: '1080p60'),
    );
  }
}

/// A platform that refuses stored cookies when the test says (Twitch, B-7).
class _RefusingSite extends FakeSite implements LiveSiteCookieRefusals {
  new(super.room);

  final StreamController<void> refusals = StreamController.broadcast(sync: true);

  @override
  Stream<void> get cookieRefusals => refusals.stream;
}

/// A platform expected to confirm the quality that did not.
class _UnconfirmedSite extends FakeSite implements LivePlayUrlResolver {
  new(super.room);

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrlResolution(urls: ['https://a.example/${quality.id}.flv'], qualityUnconfirmed: true);
}

/// A platform whose detail and play URLs take a second each (G03.1).
class _SlowSteps extends FakeSite {
  new(super.room);

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return await super.getRoomDetail(roomId: roomId);
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return await super.getPlayUrls(detail: detail, quality: quality);
  }
}
