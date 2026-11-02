import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import '../live_play/live_play_support.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(pumpEventQueue);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<FakeEngine> page(WidgetTester tester, {bool landscape = false}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  tester.view
    ..physicalSize = landscape ? const Size(852, 393) : const Size(393, 852)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() => tester.runAsync(services.close));
  await tester.runAsync(loadStrings);
  final engine = FakeEngine();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => LivePlayPage(
          route: RouteArgs(
            RoutePath.kLivePlay,
            arguments: LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '测试主播'),
          ),
        ),
      ),
      GoRoute(
        path: RoutePath.kReplayArchives,
        builder: (context, _) => Scaffold(
          body: TextButton(onPressed: () => context.pop(), child: const Text('回放目录测试页')),
        ),
      ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() {
    AppNavigator.router = null;
    router.dispose();
  });
  final previous = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previous);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => FakeSite(liveRoom())})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await settle(tester);
  return engine;
}

void main() {
  testWidgets(
    'title entry pauses live while browsing and restores the original playback intent without reopening media',
    (tester) async {
      final engine = await page(tester);
      final controller = tester.widget<ChatList>(find.byType(ChatList).first).controller;
      expect(controller.session.state.status, PlaybackStatus.playing);
      await tester.tap(find.byKey(const ValueKey('room-replay-entry')));
      await settle(tester);
      expect(find.text('回放目录测试页'), findsOneWidget);
      expect(controller.session.state.status, PlaybackStatus.paused);
      await tester.tap(find.text('回放目录测试页'));
      await settle(tester);
      expect(controller.session.state.status, PlaybackStatus.playing);
      expect(engine.opens, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('a fullscreen menu may unmount while pause is pending; the stable navigator still opens the archive', (
    tester,
  ) async {
    final engine = await page(tester, landscape: true);
    await tester.tap(find.byKey(const ValueKey('live-play-fullscreen')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-play-menu')));
    await tester.pumpAndSettle();
    final pause = Completer<void>();
    engine.onPause = () => pause.future;
    await tester.tap(find.byKey(const ValueKey('room-menu-replayArchive')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('room-menu-panel')), findsNothing);
    expect(find.text('回放目录测试页'), findsNothing);
    pause.complete();
    await settle(tester);
    expect(find.text('回放目录测试页'), findsOneWidget);
    engine.onPause = null;
    await tester.tap(find.text('回放目录测试页'));
    await settle(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}
