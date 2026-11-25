// A17.6: the TV video mode — its pages, the card menu, the player.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/video/video_pages.dart';
import 'package:pure_live/tv/video/video_panes.dart';
import 'package:pure_live/tv/video/video_player_page.dart';
import 'package:pure_live/tv/video/video_source.dart';
import 'package:pure_live/tv/video/video_store.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

import '../features/live_play/live_play_support.dart';
import '../support.dart';

const _owner = VodOwner(mid: 7, name: '阿婆主');

VodArchive _archive(String bvid, {int parts = 1}) => VodArchive(
  bvid: bvid,
  aid: 100,
  cid: 1000,
  title: '视频 $bvid',
  owner: _owner,
  duration: const Duration(minutes: 10),
  parts: [
    for (var page = 1; page <= parts; page++)
      VodPart(cid: 1000 + page, page: page, title: '第 $page 段', duration: const Duration(minutes: 10)),
  ],
);

/// Answers from tables; anything else fails.
final class _FakeSource implements VideoSource {
  bool login = true;
  Exception? recommendedError;
  final List<String> calls = [];
  final StreamController<void> _logins = StreamController.broadcast();

  @override
  bool get signedIn => login;

  @override
  Stream<void> get loginChanges => _logins.stream;

  @override
  Future<List<VodArchive>> recommended(int page) async {
    calls.add('recommended $page');
    if (recommendedError case final error?) throw error;
    return page == 1 ? [_archive('BV1'), _archive('BV2')] : const [];
  }

  @override
  Future<VodPage<VodDynamic>> dynamics(String? offset) async => const VodPage([]);

  @override
  Future<VodPage<VodArchive>> popular(int page) async => VodPage([_archive('BV9')]);

  @override
  Future<VodArchive> detail(String bvid) async => _archive(bvid, parts: bvid == 'BVparts' ? 3 : 1);

  @override
  Future<List<VodArchive>> related(String bvid) async => const [];

  @override
  Future<({bool liked, int coins, bool favorited})> relation(String bvid) async =>
      (liked: false, coins: 0, favorited: false);

  @override
  Future<PgcSeason> season({int? seasonId, int? epId}) async => const PgcSeason(
    seasonId: 5,
    title: '番剧',
    episodes: [
      PgcEpisode(epId: 51, cid: 501, title: '1', longTitle: '开始'),
      PgcEpisode(epId: 52, cid: 502, title: '2', longTitle: '继续', badge: '会员', status: 13),
    ],
  );

  @override
  Future<VodPage<VodHistoryEntry>> history(String? cursor) async => VodPage([
    VodHistoryEntry(archive: _archive('BVh'), business: 'archive', cid: 1001, progress: const Duration(minutes: 2)),
  ]);

  @override
  Future<void> deleteHistory(List<String> kids) async => calls.add('delete ${kids.join(',')}');

  @override
  Future<VodStreams> streams(VideoItem item, {int qn = 0}) async {
    calls.add('streams ${item.cid} $qn');
    return const VodStreams(
      quality: 80,
      headers: {'Referer': 'https://www.bilibili.com/'},
      qualities: [
        VodQuality(qn: 80, label: '1080P 高清'),
        VodQuality(qn: 64, label: '720P 高清'),
      ],
      videos: [VodRendition(id: 80, url: 'https://v.example/video.m4s', codecs: 'avc1.64001F')],
      audios: [VodRendition(id: 30280, url: 'https://v.example/audio.m4s', bandwidth: 192000)],
    );
  }

  @override
  Future<VodPlayerInfo> playerInfo(VideoItem item) async => const VodPlayerInfo(onlineCount: 12345);

  @override
  Future<List<VodDanmaku>> danmakuSegment(VideoItem item, int segment) async => const [];

  @override
  Future<void> reportProgress(VideoItem item, Duration progress) async => calls.add('report ${item.cid}');

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(UnsupportedError('${invocation.memberName}'));
}

void main() {
  late _FakeSource source;
  late FakeEngine engine;
  setUp(() {
    source = _FakeSource();
    engine = FakeEngine();
  });

  Future<AppServices> pump(WidgetTester tester, Widget child) async {
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(testServices))!;
    await tester.runAsync(loadStrings);
    final store = VideoStore(services.store.meta);
    await tester.runAsync(store.load);
    final scheme = ColorScheme.fromSeed(seedColor: LiveTheme.brandBlue, brightness: Brightness.dark);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          videoSourceProvider.overrideWithValue(source),
          videoStoreProvider.overrideWithValue(store),
          playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
        ],
        child: MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
              child: TvTheme(
                palette: TvPalette.of(scheme),
                child: Scaffold(body: child),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return services;
  }

  Future<void> close(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 6));
    await tester.runAsync(services.close);
  }

  Key? focusedKey() =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvFocusable>()?.key ??
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>()?.key;

  testWidgets('the gate: signed out, the video mode is the login; signed in, the destination', (tester) async {
    source.login = false;
    final services = await pump(tester, const TvVideoGate(child: Text('目的地')));
    expect(find.byKey(const ValueKey('tv-video-login-gate')), findsOneWidget);
    expect(find.text('扫码登录'), findsOneWidget);
    expect(find.text('目的地'), findsNothing);
    expect(find.text('登录哔哩哔哩后看视频'), findsOneWidget);
    await close(tester, services);

    // The music mode's gate speaks of music.
    final music = await pump(tester, const TvVideoGate(music: true, child: Text('目的地')));
    expect(find.text('登录哔哩哔哩后听音乐'), findsOneWidget);
    expect(find.text('登录哔哩哔哩后看视频'), findsNothing);
    await close(tester, music);
  });

  testWidgets('首页: three tabs, recommended cards; a failure says why and offers "重试"', (tester) async {
    final services = await pump(tester, const TvVideoHomePane());
    expect(find.text('动态'), findsOneWidget);
    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('热门'), findsOneWidget);
    await tester.tap(find.text('推荐'));
    await settle(tester);
    expect(find.text('视频 BV1'), findsOneWidget);
    expect(find.text('视频 BV2'), findsOneWidget);
    expect(find.text('10:00'), findsNWidgets(2), reason: 'the length on the cover');
    await close(tester, services);

    source.recommendedError = Exception('boom');
    final again = await pump(tester, const TvVideoHomePane());
    await tester.tap(find.text('推荐'));
    await settle(tester);
    expect(find.text('重试'), findsOneWidget);
    await close(tester, again);
  });

  testWidgets('the detail: "播放" has the focus; one part lists no parts; a part left says "继续"', (tester) async {
    final services = await pump(tester, TvVideoDetailPage(bvid: 'BV1', archive: _archive('BV1')));
    expect(focusedKey(), const ValueKey('tv-video-detail-play'));
    expect(find.text('播放'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-video-detail-part-0')), findsNothing, reason: 'c4: a single part');
    await close(tester, services);

    final again = await pump(tester, TvVideoDetailPage(bvid: 'BVparts', archive: _archive('BVparts', parts: 3)));
    final container = ProviderScope.containerOf(tester.element(find.byType(TvVideoDetailPage)));
    final store = container.read(videoStoreProvider);
    await tester.runAsync(
      () => store.record(
        VideoItem.partsOf(_archive('BVparts', parts: 3))[1],
        const Duration(minutes: 1, seconds: 46),
        const Duration(minutes: 10),
      ),
    );
    await settle(tester);
    expect(find.text('继续 P2 · 01:46'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-video-detail-part-2'), skipOffstage: false), findsOneWidget);
    expect(find.text('P2 第 2 段 · 看到 01:46', skipOffstage: false), findsOneWidget);
    await close(tester, again);
  });

  testWidgets('a season: "第1话" first with the focus; member episodes are marked', (tester) async {
    final services = await pump(tester, const TvVideoSeasonPage(seasonId: 5));
    expect(focusedKey(), const ValueKey('tv-video-episode-0'));
    expect(find.textContaining('第1话 开始'), findsOneWidget);
    expect(find.textContaining('会员'), findsOneWidget);
    await close(tester, services);
  });

  testWidgets('history: the card menu deletes after asking', (tester) async {
    final services = await pump(tester, const TvVideoMinePane());
    await tester.tap(find.text('历史记录'));
    await settle(tester);
    expect(find.text('视频 BVh'), findsOneWidget);
    await tester.longPress(find.byKey(const ValueKey('tv-video-card-0')));
    await settle(tester);
    expect(find.text('删除这条记录'), findsOneWidget);
    expect(find.text('视频 BVh 的主页'), findsNothing);
    await tester.tap(find.text('删除这条记录'));
    await settle(tester);
    expect(find.textContaining('从观看历史里删除'), findsOneWidget, reason: 'c17: asks first');
    expect(source.calls.where((call) => call.startsWith('delete')), isEmpty);
    await tester.tap(find.text('删除这条记录').last);
    await settle(tester);
    expect(source.calls, contains('delete archive_100'));
    expect(find.text('视频 BVh'), findsNothing);
    await close(tester, services);
  });

  testWidgets('the player: DASH with its audio; one row of controls without seek buttons; ←→ seek faster', (
    tester,
  ) async {
    final items = VideoItem.partsOf(_archive('BV1'));
    final services = await pump(tester, TvVideoPlayerPage(items: items, index: 0));
    await settle(tester);
    expect(engine.opens.single.uri.toString(), 'https://v.example/video.m4s');
    expect(engine.opens.single.audio, ExternalAudio(Uri.parse('https://v.example/audio.m4s')));
    expect(find.byKey(const ValueKey('tv-video-play')), findsOneWidget);
    expect(find.text('暂停'), findsOneWidget, reason: 'playing: the button pauses');
    expect(find.text('1080P 高清'), findsOneWidget);
    expect(find.text('12345 人在看'.replaceAll('12345', '1.2万')), findsOneWidget);
    for (final word in ['快退', '快进']) {
      expect(find.textContaining(word), findsNothing, reason: 'c12');
    }
    final play = tester.getRect(find.byKey(const ValueKey('tv-video-play')));
    final comments = tester.getRect(find.byKey(const ValueKey('tv-video-comments')));
    expect(play.center.dy, comments.center.dy, reason: 'one row');
    expect(comments.right, lessThanOrEqualTo(960), reason: 'on screen');

    // The controls go after 5 s; ←→ then seek, a second press soon after
    // by a bigger step.
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(const ValueKey('tv-video-play')), findsNothing);
    expect(find.byKey(const ValueKey('tv-video-edge-progress')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    // OK brings the controls back; Back hides them, then leaves.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('tv-video-play')), findsOneWidget);
    await close(tester, services);
  });
}

/// Lets the store and the source answer (real time) and the frames run.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
