import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/vod.dart';
import 'package:pure_live/features/huya_replay/huya_archive_page.dart';
import 'package:pure_live/tv/tv_app.dart';

import '../../support.dart';
import '../live_play/live_play_support.dart';
import 'huya_archive_support.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    await pumpEventQueue();
  });
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<FakeEngine> page(
  WidgetTester tester,
  FakeHuyaArchive source, {
  bool tv = false,
  Size size = const Size(420, 800),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  await tester.runAsync(() => services.store.settings.set(Settings.uiMode, tv ? 'tv' : 'phone'));
  final engine = FakeEngine();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        huyaArchiveProvider.overrideWithValue(source),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: const LiveTheme().dark,
          builder: (_, child) => tv ? TvAppFrame(child: child!) : child!,
          home: HuyaArchivePage(
            room: LiveRoom(platform: SiteIds.huya, roomId: '998', userId: '123', nick: '测试主播'),
          ),
        ),
      ),
    ),
  );
  await settle(tester);
  return engine;
}

void main() {
  for (final layout in [
    ('phone', const Size(420, 800), false),
    ('desktop', const Size(1000, 700), false),
    ('tv', const Size(960, 540), true),
  ]) {
    testWidgets('${layout.$1} archive lists pages without opening live media and fits its viewport', (tester) async {
      final source = FakeHuyaArchive();
      final engine = await page(tester, source, tv: layout.$3, size: layout.$2);
      expect(source.calls, ['list:123:1']);
      expect(find.text(firstArchive.title), findsOneWidget);
      expect(engine.opens, isEmpty);
      await tester.ensureVisible(find.byKey(const ValueKey('huya-archive-more')));
      await tester.tap(find.byKey(const ValueKey('huya-archive-more')));
      await settle(tester);
      expect(source.calls, ['list:123:1', 'list:123:2']);
      expect(find.text(secondArchive.title), findsOneWidget);
      expect(find.byKey(const ValueKey('huya-archive-more')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('failed requests stay retryable and malformed archive URLs do not reach the API', (tester) async {
    final source = FakeHuyaArchive()..failList = true;
    await page(tester, source);
    expect(find.byKey(const ValueKey('huya-archive-retry')), findsOneWidget);
    source.failList = false;
    await tester.tap(find.byKey(const ValueKey('huya-archive-retry')));
    await settle(tester);
    expect(find.text(firstArchive.title), findsOneWidget);
    final count = source.calls.length;
    await tester.enterText(find.byKey(const ValueKey('huya-archive-input')), 'https://evil.test/video/u/123');
    await tester.tap(find.byKey(const ValueKey('huya-archive-search')));
    await settle(tester);
    expect(source.calls.length, count);
    expect(find.textContaining('有效的虎牙'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a stale presenter response cannot replace a newer submitted archive', (tester) async {
    final source = FakeHuyaArchive();
    final pending = source.lists['123:1'] = Completer();
    await page(tester, source);
    await tester.enterText(find.byKey(const ValueKey('huya-archive-input')), 'https://www.huya.com/video/u/456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(source.calls, ['list:123:1', 'list:456:1']);
    pending.complete(const HuyaArchiveList(videos: [secondArchive], hasMore: false));
    await settle(tester);
    expect(find.text(firstArchive.title), findsOneWidget);
    expect(find.text(secondArchive.title), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selection opens true on-demand playback and releases it on back', (tester) async {
    final source = FakeHuyaArchive();
    final engine = await page(tester, source);
    await tester.tap(find.byKey(ValueKey('huya-archive-${firstArchive.id}')));
    await settle(tester);
    expect(engine.opens, hasLength(1));
    expect(engine.opens.single.onDemand, isTrue);
    expect(engine.opens.single.headers['referer'], 'https://www.huya.com/');
    expect(find.byKey(const ValueKey('vod-danmaku-settings')), findsNothing);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await settle(tester);
    expect(engine.disposed, isTrue);
    expect(find.byKey(const ValueKey('huya-archive-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
