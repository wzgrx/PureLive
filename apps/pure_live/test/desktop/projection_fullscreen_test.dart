import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/desktop/projection_runtime.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../features/live_play/live_play_support.dart';
import '../support.dart';

void main() {
  testWidgets('projection room disposal cannot undo the replacement room fullscreen', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DesktopWindow.fullScreen.value = false;
    addTearDown(() => DesktopWindow.fullScreen.value = false);
    final services = (await tester.runAsync(
      () => testServices(launch: const LaunchArgs(instanceId: 'projection-test', projection: true)),
    ))!;
    await tester.runAsync(loadStrings);
    final first = liveRoom();
    final second = LiveRoom(
      platform: SiteIds.bilibili,
      roomId: '7',
      nick: 'Second room',
      title: 'Second room',
      liveStatus: LiveStatus.live,
      danmakuData: 'args-7',
    );
    final site = FakeSite(first);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('receiver home')),
        GoRoute(
          path: RoutePath.kLivePlay,
          builder: (_, state) => LivePlayPage(route: RouteArgs(RoutePath.kLivePlay, arguments: state.extra)),
        ),
      ],
    );
    AppNavigator.router = router;
    Future<void> advance() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        await tester.pump(const Duration(seconds: 1));
      }
    }

    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appServicesProvider.overrideWithValue(services),
            sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
            danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
            playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
          ],
          child: MaterialApp.router(theme: const LiveTheme().light, routerConfig: router),
        ),
      );
      navigateProjectionRoom(first);
      await advance();
      await tester.pump(const Duration(seconds: 1));
      expect(DesktopWindow.fullScreen.value, isTrue);
      site.room = second;
      navigateProjectionRoom(second);
      await advance();
      expect(DesktopWindow.fullScreen.value, isTrue, reason: 'the second room has already entered fullscreen');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Second room'), findsWidgets);
      expect(DesktopWindow.fullScreen.value, isTrue, reason: 'late disposal of the first room must not exit it');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await tester.pump(const Duration(seconds: 5));
      AppNavigator.router = null;
      router.dispose();
      await tester.runAsync(services.close);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
