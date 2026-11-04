import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/vod.dart';
import 'package:pure_live/features/replay/replay_catalog_page.dart';
import 'package:pure_live/shared/rooms/archive/archive_player_page.dart';
import 'package:pure_live/shared/rooms/archive/archive_recording.dart';
import 'package:pure_live/tv/tv_app.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

import '../../qa_capture.dart';
import '../../support.dart';
import '../douyu_vod/vod_support.dart';
import '../huya_replay/huya_archive_support.dart';
import '../live_play/live_play_support.dart';
import 'replay_test_support.dart';

const soopRecording = SoopArchiveVideo(
  id: '1234567',
  title: 'SOOP直播回放',
  authorId: 'creator',
  authorName: '测试主播',
  duration: Duration(hours: 2),
);

class FakeSoopReplay implements SoopArchiveSource {
  final calls = <String>[];
  @override
  Future<SoopArchiveList> list(String author, {int page = 1, CancelToken? cancel}) async {
    calls.add('list:$author:$page');
    return (videos: [soopRecording], hasMore: false);
  }

  @override
  Future<List<SoopArchivePart>> detail(String id, {CancelToken? cancel}) async => [
    for (var n = 1; n <= 2; n++)
      SoopArchivePart(
        recording: soopRecording,
        order: n,
        duration: const Duration(hours: 1),
        qualities: [
          SoopArchiveQuality(id: 'original', label: '1080p', url: 'https://vod.sooplive.com/$n/manifest.m3u8'),
          SoopArchiveQuality(id: 'hd4k', label: '720p', url: 'https://vod.sooplive.com/$n/720.m3u8'),
        ],
      ),
  ];
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(pumpEventQueue);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<(FakeEngine, FakeHuyaArchive)> page(
  WidgetTester tester, {
  required String platform,
  Size size = const Size(393, 852),
  double scale = 1,
  bool standalone = false,
  bool tv = false,
  PlaybackSession Function()? playbackFactory,
  FakeBiliReplay? biliSource,
  FakeHuyaArchive? huyaSource,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await prepareQaFonts(tester);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  if (tv) await tester.runAsync(() => services.store.settings.set(Settings.uiMode, 'tv'));
  final engine = FakeEngine();
  final huya = huyaSource ?? FakeHuyaArchive();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        replayIdentityProvider.overrideWithValue(ReplayIdentityApi(_IdentityHttp())),
        huyaArchiveProvider.overrideWithValue(huya),
        douyuVodProvider.overrideWithValue(FakeVodSource(testSigner())),
        bilibiliReplayProvider.overrideWithValue(biliSource ?? FakeBiliReplay()),
        soopArchiveProvider.overrideWithValue(FakeSoopReplay()),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => playbackFactory?.call() ?? fakeSession(engine)),
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: const LiveTheme().dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: tv ? TvAppFrame(child: child!) : child!,
          ),
          home: ReplayCatalogPage(
            room: standalone ? null : LiveRoom(platform: platform, roomId: '998', nick: '测试主播'),
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return (engine, huya);
}

void main() {
  testWidgets('SOOP replay uses the existing room UI with actual part choices, speed and one native session', (
    tester,
  ) async {
    final (engine, _) = await page(tester, platform: SiteIds.soop);
    expect(find.text('SOOP直播回放'), findsOneWidget);
    await captureQaFrame(tester, 'replay-soop-catalog');
    final entry = find.byKey(const ValueKey('replay-recording-1234567'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await settle(tester);
    expect(engine.opens, hasLength(1));
    expect(engine.opens.single.onDemand, isTrue);
    expect(find.byKey(const ValueKey('archive-rate')), findsOneWidget);
    expect(find.byKey(const ValueKey('archive-part-1234567:1')), findsOneWidget);
    expect(find.byKey(const ValueKey('archive-part-1234567:2')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await captureQaFrame(tester, 'replay-soop-room');
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('a list failure stops automatic requests and retry preserves the keyword', (tester) async {
    final source = FakeHuyaArchive()..failList = true;
    await page(tester, platform: SiteIds.huya, huyaSource: source);
    await tester.enterText(find.byKey(const ValueKey('replay-keyword')), '第一');
    await tester.pump(const Duration(seconds: 5));
    expect(source.calls, ['list:123:1']);
    source.failList = false;
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    for (var n = 0; n < 5; n++) {
      await settle(tester);
    }
    expect(tester.widget<TextField>(find.byKey(const ValueKey('replay-keyword'))).controller!.text, '第一');
    expect(source.calls, ['list:123:1', 'list:123:1', 'list:123:2']);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('closing the catalog cancels continuation and discards a late page', (tester) async {
    final source = FakeHuyaArchive();
    final pending = Completer<HuyaArchiveList>();
    source.lists['123:2'] = pending;
    await page(tester, platform: SiteIds.huya, huyaSource: source);
    for (var n = 0; n < 5 && source.calls.length < 2; n++) {
      await settle(tester);
    }
    expect(source.calls, ['list:123:1', 'list:123:2']);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(const HuyaArchiveList(videos: [secondArchive], hasMore: true));
    await settle(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(source.calls, ['list:123:1', 'list:123:2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary downward scrolling loads further pages without tapping more', (tester) async {
    final source = FakeHuyaArchive();
    for (var n = 1; n <= 3; n++) {
      source.lists['123:$n'] = Completer<HuyaArchiveList>()
        ..complete(
          HuyaArchiveList(
            videos: [
              for (var i = 0; i < 12; i++)
                HuyaArchiveVideo(id: '${300000000 + n * 100 + i}', title: '滚动第$n页录像$i', authorId: '123'),
            ],
            hasMore: n < 3,
          ),
        );
    }
    await page(tester, platform: SiteIds.huya, huyaSource: source);
    for (var i = 0; i < 12 && source.calls.length < 3; i++) {
      await tester.drag(find.byKey(const ValueKey('replay-catalog-list')), const Offset(0, -650));
      await settle(tester);
    }
    expect(source.calls, ['list:123:1', 'list:123:2', 'list:123:3']);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  for (final size in [const Size(393, 852), const Size(740, 360), const Size(280, 640)]) {
    testWidgets('catalog browsing stays bounded at $size with large text', (tester) async {
      await page(tester, platform: SiteIds.huya, size: size, scale: 1.5);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await captureQaFrame(tester, 'replay-browse-${size.width.toInt()}x${size.height.toInt()}');
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    });
  }

  testWidgets('continuous scrolling prefetches once and keyword search continues across later pages', (tester) async {
    final source = FakeHuyaArchive();
    for (var n = 1; n <= 3; n++) {
      final videos = [
        for (var i = 0; i < 10; i++)
          HuyaArchiveVideo(
            id: '${200000000 + n * 10 + i}',
            title: n == 3 && i == 9 ? '目标复盘录像' : '第$n页场次$i',
            authorId: '123',
            date: '2026-11-0$n',
          ),
      ];
      source.lists['123:$n'] = Completer<HuyaArchiveList>()..complete(HuyaArchiveList(videos: videos, hasMore: n < 3));
    }
    await page(tester, platform: SiteIds.huya, huyaSource: source);
    await tester.enterText(find.byKey(const ValueKey('replay-keyword')), '目标');
    for (var n = 0; n < 12 && source.calls.length < 3; n++) {
      await settle(tester);
    }
    await settle(tester);
    expect(source.calls, ['list:123:1', 'list:123:2', 'list:123:3']);
    expect(find.text('目标复盘录像'), findsOneWidget);
    expect(find.textContaining('已检索 30 条'), findsOneWidget);
    expect(find.text('第1页场次0'), findsNothing);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await captureQaFrame(tester, 'replay-search-portrait');
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('date presets are an anchored choice and filtering has an explicit progress range', (tester) async {
    await page(tester, platform: SiteIds.huya);
    await tester.tap(find.byKey(const ValueKey('replay-date-range')));
    await tester.pumpAndSettle();
    expect(find.text('近90天'), findsOneWidget);
    expect(find.text('自定义日期范围'), findsOneWidget);
    await captureQaFrame(tester, 'replay-date-presets');
    await tester.tap(find.text('近90天'));
    await settle(tester);
    expect(find.text('近90天'), findsOneWidget);
    expect(find.textContaining('已检索'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('late recording metadata enables actions and fills parts without another user action', (tester) async {
    final source = FakeBiliReplay()..pending = Completer<VodArchive>();
    await page(tester, platform: SiteIds.bilibili, biliSource: source);
    await tester.tap(find.byKey(ValueKey('replay-recording-${archive.bvid}')));
    await settle(tester);
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('archive-rate'))).onPressed, isNull);
    source.pending!.complete(archive);
    await settle(tester);
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('archive-rate'))).onPressed, isNotNull);
    expect(find.byKey(ValueKey('archive-part-${archive.bvid}:100')), findsOneWidget);
    expect(find.byKey(ValueKey('archive-part-${archive.bvid}:200')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });
  for (final platform in replayPlatforms) {
    for (final layout in [const Size(360, 800), const Size(740, 360), const Size(1280, 800)]) {
      testWidgets('$platform archive layout $layout is bounded at 150 percent type', (tester) async {
        final (engine, _) = await page(tester, platform: platform, size: layout, scale: 1.5);
        expect(find.byKey(const ValueKey('replay-catalog-page')), findsOneWidget);
        expect(
          find.byKey(
            ValueKey(
              'replay-recording-${platform == SiteIds.huya
                  ? firstArchive.id
                  : platform == SiteIds.douyu
                  ? secondVideo.id
                  : platform == SiteIds.soop
                  ? soopRecording.id
                  : archive.bvid}',
            ),
          ),
          findsOneWidget,
        );
        expect(engine.opens, isEmpty, reason: 'browsing an archive does not open a second decoder');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await settle(tester);
      });
    }
  }
  testWidgets('Bilibili room entry opens on-demand media with parts and native ownership releases on Back', (
    tester,
  ) async {
    final (engine, _) = await page(tester, platform: SiteIds.bilibili);
    final entry = find.byKey(ValueKey('replay-recording-${archive.bvid}'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await settle(tester);
    expect(engine.opens, hasLength(1));
    expect(engine.opens.first.onDemand, isTrue);
    expect(find.byKey(const ValueKey('archive-rate')), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('live-play-fullscreen'))).right, lessThanOrEqualTo(393));
    await tester.tap(find.byKey(const ValueKey('archive-rate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('archive-rate-1.75')));
    await tester.pumpAndSettle();
    expect(engine.rates.last, 1.75);
    Navigator.of(tester.element(find.byKey(const ValueKey('archive-rate')))).pop();
    await settle(tester);
    expect(engine.stops, greaterThan(0));
    expect(find.byType(LiveVideoView), findsNothing);
    expect(find.byKey(const ValueKey('replay-catalog-page')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('TV replay rows have the standard visible focus target and OK opens on-demand playback', (tester) async {
    final (engine, _) = await page(tester, platform: SiteIds.huya, size: const Size(1280, 720), tv: true);
    expect(find.byKey(const ValueKey('replay-room-input')), findsNothing);
    expect(find.byKey(const ValueKey('replay-keyword')), findsOneWidget);
    final row = find.byKey(ValueKey('replay-recording-${firstArchive.id}'));
    expect(find.descendant(of: row, matching: find.byType(TvFocusable)), findsOneWidget);
    bool focused() =>
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<ArchiveRecordingTile>()?.key ==
        ValueKey('replay-recording-${firstArchive.id}');
    for (var i = 0; i < 8 && !focused(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(focused(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await settle(tester);
    expect(engine.opens, hasLength(1));
    expect(engine.opens.single.onDemand, isTrue);
    var pauses = 0;
    engine.onPause = () async => pauses++;
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await settle(tester);
    expect(pauses, 1, reason: 'OK on the initial video surface pauses without an extra focus move');
    final playback = tester.widget<LiveVideoView>(find.byType(LiveVideoView).last).session;
    expect(playback.state.status, PlaybackStatus.paused);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await settle(tester);
    expect(playback.state.status, PlaybackStatus.playing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('querying another presenter does not retain the original room name', (tester) async {
    final (_, source) = await page(tester, platform: SiteIds.huya);
    expect(find.text('测试主播'), findsOneWidget);
    source.lists['456:1'] = Completer<HuyaArchiveList>()
      ..complete(
        const HuyaArchiveList(
          videos: [HuyaArchiveVideo(id: '100000003', title: '另一位主播的回放', authorId: '456', authorName: '另一位主播')],
          hasMore: false,
        ),
      );
    expect(find.byKey(const ValueKey('replay-room-input')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('replay-open-query')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('replay-room-input')), 'https://www.huya.com/video/u/456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text('测试主播'), findsNothing);
    expect(find.text('另一位主播的回放'), findsOneWidget);
    expect(source.calls.last, 'list:456:1');
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  for (final size in [const Size(393, 852), const Size(740, 360), const Size(1280, 800)]) {
    testWidgets('v5 player and panel remain bounded at $size with 200 percent type', (tester) async {
      await page(tester, platform: SiteIds.bilibili, size: size, scale: 2);
      await tester.ensureVisible(find.byKey(ValueKey('replay-recording-${archive.bvid}')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('replay-recording-${archive.bvid}')));
      await settle(tester);
      expect(find.byType(ArchivePlayerPage), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('archive-rate')));
      await tester.tap(find.byKey(const ValueKey('archive-rate')));
      await settle(tester);
      expect(find.byKey(const ValueKey('archive-rate-editor')), findsOneWidget);
      final editor = find.byKey(const ValueKey('archive-rate-editor'));
      final surface = find.ancestor(of: editor, matching: find.byType(Material)).first;
      expect(tester.widget<Material>(surface).color, Theme.of(tester.element(editor)).colorScheme.surface);
      expect(tester.getSize(surface), tester.getSize(editor));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byKey(const ValueKey('archive-rate-editor')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    });
  }

  testWidgets('original fullscreen keeps the replay output and closes rate before leaving', (tester) async {
    final (engine, _) = await page(tester, platform: SiteIds.bilibili);
    await tester.tap(find.byKey(ValueKey('replay-recording-${archive.bvid}')));
    await settle(tester);
    final session = tester.widget<LiveVideoView>(find.byType(LiveVideoView).last).session;
    await tester.tap(find.byKey(const ValueKey('live-play-fullscreen')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('archive-rate')));
    await settle(tester);
    expect(tester.widget<LiveVideoView>(find.byType(LiveVideoView).last).session, same(session));
    expect(engine.opens, hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byKey(const ValueKey('archive-rate-editor')), findsNothing);
    expect(find.byType(ArchivePlayerPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('standalone entry names platforms correctly and rejects foreign links without catalog requests', (
    tester,
  ) async {
    final (_, source) = await page(tester, platform: SiteIds.huya, standalone: true);
    expect(find.text('虎牙'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('replay-room-input')), 'https://evil.example/video/u/123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(source.calls, isEmpty);
    expect(find.text('无法识别输入，请检查所选平台和官方链接'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('replay-room-input')), 'https://www.huya.com/video/u/123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    // A short page fills itself without the old mandatory next-page tap.
    for (var n = 0; n < 4 && source.calls.length < 2; n++) {
      await settle(tester);
    }
    await settle(tester);
    expect(source.calls, ['list:123:1', 'list:123:2']);
    expect(find.byKey(const ValueKey('replay-more')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('switching a recording keeps the original native session', (tester) async {
    final engines = <FakeEngine>[];
    await page(
      tester,
      platform: SiteIds.huya,
      playbackFactory: () {
        final engine = FakeEngine();
        engines.add(engine);
        return fakeSession(engine);
      },
    );
    await settle(tester);
    await tester.ensureVisible(find.byKey(ValueKey('replay-recording-${firstArchive.id}')));
    await tester.tap(find.byKey(ValueKey('replay-recording-${firstArchive.id}')));
    await settle(tester);
    final target = find.byKey(ValueKey('archive-related-${secondArchive.id}'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await settle(tester);
    expect(engines, hasLength(1));
    expect(engines.single.disposed, isFalse);
    expect(engines.single.opens, hasLength(2));
    expect(engines.single.opens.every((m) => m.onDemand), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });
}

class _IdentityHttp implements LiveHttp {
  @override
  Future<LiveResponse> send(LiveRequest request) async => LiveResponse(
    url: request.url,
    status: 200,
    bytes: utf8.encode(
      jsonEncode(switch (request.site) {
        SiteIds.huya => {
          'data': {
            'profileInfo': {'uid': 123},
          },
        },
        SiteIds.douyu => {
          'room': {'up_id': 'Author0001'},
        },
        _ => {
          'code': 0,
          'data': {'uid': 7},
        },
      }),
    ),
  );
  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();
  @override
  void close() {}
}
