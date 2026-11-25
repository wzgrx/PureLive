import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_details.dart';
import 'package:pure_live/features/live_play/layout/room_info_bar.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/tv/room/tv_room_overlays.dart';
import 'package:pure_live/tv/tv_theme.dart';

import '../../qa_capture.dart';
import '../../support.dart';
import 'live_play_support.dart';

void _nothing() {}

void main() {
  for (final surface in ['strip', 'details', 'tv']) {
    testWidgets('PR94: $surface updates the separate VIP count without changing the room', (tester) async {
      final size = surface == 'tv' ? const Size(1280, 720) : const Size(393, 852);
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await prepareQaFonts(tester);
      final services = (await tester.runAsync(testServices))!;
      await tester.runAsync(loadStrings);
      final detail = liveRoom(platform: SiteIds.douyu).copyWith(popularity: '12345');
      final site = FakeSite(detail)..siteId = SiteIds.douyu;
      final danmaku = FakeDanmaku();
      final session = fakeSession(FakeEngine());
      final controller = LiveRoomController(
        room: detail,
        site: site,
        session: session,
        danmaku: danmaku,
        danmakuSupported: true,
        store: services.store,
        toast: (_) {},
        refreshInterval: Duration.zero,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        await tester.runAsync(() async {
          await session.dispose();
          await services.close();
        });
      });
      await tester.runAsync(controller.start);
      final theme = surface == 'tv' ? const LiveTheme().dark : const LiveTheme().light;
      final body = switch (surface) {
        'strip' => Padding(
          padding: const EdgeInsets.all(16),
          child: AudienceStrip(controller: controller),
        ),
        'details' => RoomDetailsPanel(controller: controller, onClose: _nothing),
        _ => ListenableBuilder(
          listenable: controller,
          builder: (_, _) => TvRoomControls(
            controller: controller,
            followed: false,
            danmakuOn: true,
            onQuality: _nothing,
            onLine: _nothing,
            onDanmaku: _nothing,
            onFollow: _nothing,
            onRefresh: _nothing,
            onList: _nothing,
          ),
        ),
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: MaterialApp(
            theme: theme,
            home: TvTheme(
              palette: TvPalette.of(theme.colorScheme),
              child: Scaffold(
                body: Align(alignment: surface == 'tv' ? Alignment.bottomCenter : Alignment.topCenter, child: body),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialRoom = controller.room;
      for (final count in [127, 0]) {
        danmaku.emit(
          DanmakuReceived(
            LiveMessage(
              type: LiveMessageType.online,
              userName: '',
              message: '',
              color: LiveMessageColor.white,
              data: LiveVipCount(value: count),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(controller.room, same(initialRoom), reason: 'VIP updates must not replace audience metadata.');
        expect(controller.room.hasRealOnlineCount, isFalse);
        if (surface == 'strip') {
          expect(find.byTooltip('贵宾'), findsOneWidget);
          expect(find.text('$count'), findsOneWidget);
        } else if (surface == 'details') {
          expect(find.text('贵宾'), findsOneWidget);
          expect(find.text('$count'), findsOneWidget);
        } else {
          expect(find.textContaining('贵宾 $count'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        if (count == 127) await captureQaFrame(tester, 'vip-$surface');
      }
    });
  }
}
