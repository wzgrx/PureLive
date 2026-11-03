import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/vod.dart';
import 'package:pure_live/features/douyu_vod/vod_page.dart';
import 'package:pure_live/features/douyu_vod/vod_player_page.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';

import '../../support.dart';
import '../live_play/live_play_support.dart';
import 'vod_support.dart';

Future<FakeVodSource> pumpPage(WidgetTester tester, {bool player = false, Size size = const Size(420, 800)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final signer = (await tester.runAsync(() async => testSigner()))!;
  final source = FakeVodSource(signer);
  final engine = FakeEngine();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        douyuVodProvider.overrideWithValue(source),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          home: player
              ? DouyuVodPlayerPage(videoId: firstVideo.id)
              : const DouyuVodCatalogPage(route: RouteArgs(RoutePath.kDouyuVod)),
        ),
      ),
    ),
  );
  await settle(tester);
  return source;
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var at = 0; at < 30; at++) {
      await Future<void>.value();
    }
  });
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('recommendations are labelled independently of replay and video search filters', (tester) async {
    final source = await pumpPage(tester);
    expect(source.calls, ['home']);
    expect(find.text('推荐视频'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('vod-search')), '测试主播');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('vod-home')));
    await settle(tester);
    expect(source.calls.last, 'home');
    expect(find.text('推荐视频'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('on-video clocks and selected quality remain readable in the light app theme', (tester) async {
    await pumpPage(tester, player: true, size: const Size(740, 360));
    await tester.tap(find.byKey(const ValueKey('live-play-fullscreen')));
    await settle(tester);
    for (final target in [find.byKey(const ValueKey('archive-video-clock')), find.text('高清')]) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: target, matching: find.byType(RichText)).first,
      );
      final color = paragraph.text.style!.color!;
      expect(color.computeLuminance(), greaterThan(0.65), reason: 'video controls must contrast with the dark panel');
    }
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('catalog searches the selected tab, appends a page and opens the encoded author catalog', (tester) async {
    final source = await pumpPage(tester);
    expect(find.text('第一场录像'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('vod-search')), '测试主播');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(source.calls, contains('search:测试主播:true:1'));
    await tester.tap(find.text('加载下一页'));
    await settle(tester);
    expect(find.text('第二场录像'), findsOneWidget);
    await tester.tap(find.text('视频', skipOffstage: false).first);
    await settle(tester);
    expect(source.calls, contains('search:测试主播:false:1'));
    await tester.tap(find.byTooltip('查看主播录像与视频').first);
    await settle(tester);
    expect(source.calls, contains('author:Author0001:false:1'));
    expect(find.text('第二场录像'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('small player controls fit, pause and restore without native video in unit tests', (tester) async {
    await pumpPage(tester, player: true, size: const Size(384, 256));
    expect(find.byKey(const ValueKey('live-play-pause')), findsOneWidget);
    expect(find.text('高清'), findsOneWidget);
    expect(find.text('超清'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('live-play-pause')));
    await settle(tester);
    expect(find.byTooltip('播放'), findsWidgets);
    await tester.tap(find.byTooltip('弹幕设置').first);
    await settle(tester);
    expect(find.byType(DanmakuSettingsContent), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room-panel-close')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
