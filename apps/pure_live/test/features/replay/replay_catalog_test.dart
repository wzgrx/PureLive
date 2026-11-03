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
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

import '../../support.dart';
import '../douyu_vod/vod_support.dart';
import '../huya_replay/huya_archive_support.dart';
import '../live_play/live_play_support.dart';
import 'replay_test_support.dart';

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
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  if (tv) await tester.runAsync(() => services.store.settings.set(Settings.uiMode, 'tv'));
  final engine = FakeEngine();
  final huya = FakeHuyaArchive();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        replayIdentityProvider.overrideWithValue(ReplayIdentityApi(_IdentityHttp())),
        huyaArchiveProvider.overrideWithValue(huya),
        douyuVodProvider.overrideWithValue(FakeVodSource(testSigner())),
        bilibiliReplayProvider.overrideWithValue(FakeBiliReplay()),
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
    await tester.tap(find.byKey(const ValueKey('archive-rate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('archive-rate-1.75')));
    await tester.pumpAndSettle();
    expect(engine.rates.last, 1.75);
    Navigator.of(tester.element(find.byKey(const ValueKey('archive-rate')))).pop();
    await settle(tester);
    expect(engine.disposed, isTrue);
    expect(find.byKey(const ValueKey('replay-catalog-page')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('TV replay rows have the standard visible focus target and OK opens on-demand playback', (tester) async {
    final (engine, _) = await page(tester, platform: SiteIds.huya, size: const Size(1280, 720), tv: true);
    expect(find.byType(TvInputField), findsNothing);
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
      await tester.tap(find.byKey(ValueKey('replay-recording-${archive.bvid}')));
      await settle(tester);
      expect(find.byType(ArchivePlayerPage), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('archive-rate')));
      await settle(tester);
      expect(find.byKey(const ValueKey('archive-settings-panel')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byKey(const ValueKey('archive-settings-panel')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    });
  }

  testWidgets('landscape controls hide, keyboard restores them and panel leaves video size unchanged', (tester) async {
    final (engine, _) = await page(tester, platform: SiteIds.bilibili, size: const Size(740, 360));
    await tester.tap(find.byKey(ValueKey('replay-recording-${archive.bvid}')));
    await settle(tester);
    final stage = tester.getRect(find.byType(LiveVideoView).last);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('archive-rate')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.byKey(const ValueKey('archive-rate')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('archive-rate')));
    await settle(tester);
    expect(tester.getRect(find.byType(LiveVideoView).last), stage);
    expect(engine.opens, hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(ArchivePlayerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('archive-settings-panel')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.getRect(find.byType(LiveVideoView).last).width, lessThan(740));
    tester.view.physicalSize = const Size(393, 852);
    await tester.pump();
    tester.view.physicalSize = const Size(740, 360);
    await tester.pump();
    expect(tester.getRect(find.byType(LiveVideoView).last).width, 740);
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
    expect(source.calls, ['list:123:1']);
    await tester.ensureVisible(find.byKey(const ValueKey('replay-more')));
    await tester.tap(find.byKey(const ValueKey('replay-more')));
    await settle(tester);
    expect(source.calls, ['list:123:1', 'list:123:2']);
    expect(find.byKey(const ValueKey('replay-more')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  });

  testWidgets('switching a recording waits for native retirement before creating its replacement', (tester) async {
    final retired = Completer<void>();
    final engines = <FakeEngine>[];
    await page(
      tester,
      platform: SiteIds.huya,
      playbackFactory: () {
        final engine = FakeEngine();
        if (engines.isEmpty) engine.onDispose = () => retired.future;
        engines.add(engine);
        return fakeSession(engine);
      },
    );
    await tester.tap(find.byKey(const ValueKey('replay-more')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('replay-recording-${firstArchive.id}')));
    await settle(tester);
    final target = find.byKey(ValueKey('archive-related-${secondArchive.id}'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await settle(tester);
    expect(engines, hasLength(1));
    expect(engines.first.disposed, isTrue);
    retired.complete();
    await settle(tester);
    expect(engines, hasLength(2));
    expect(engines.last.opens, hasLength(1));
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
