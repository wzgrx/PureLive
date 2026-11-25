import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/home_views.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';

import '../../qa_capture.dart';
import '../../support.dart';

final class _Site extends LiveSite {
  @override
  String get id => SiteIds.bilibili;

  @override
  String get name => '哔哩哔哩';

  final List<LiveRoom> rooms = [
    for (var i = 0; i < 80; i++)
      LiveRoom(platform: SiteIds.bilibili, roomId: '$i', title: '测试直播间 $i', nick: '主播 $i', liveStatus: LiveStatus.live),
  ];

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async => page == 1 ? rooms : [];

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async => rooms[int.parse(roomId)];
}

void main() {
  final cases = [
    (name: 'android', size: const Size(393, 852), safe: 24.0, compact: false, platform: TargetPlatform.android),
    (name: 'iphone', size: const Size(393, 852), safe: 34.0, compact: false, platform: TargetPlatform.iOS),
    (name: 'compact', size: const Size(320, 568), safe: 0.0, compact: true, platform: TargetPlatform.android),
    (name: 'three-buttons', size: const Size(393, 852), safe: 48.0, compact: true, platform: TargetPlatform.android),
    (name: 'tablet', size: const Size(1280, 800), safe: 24.0, compact: false, platform: TargetPlatform.android),
  ];
  for (final entry in cases) {
    for (final menu in [HomeMenu.favorites, HomeMenu.popular]) {
      testWidgets('A06.8 ${entry.name} ${menu.id}: jump buttons clear navigation and still scroll', (tester) async {
        tester.view
          ..physicalSize = entry.size
          ..devicePixelRatio = 1
          ..padding = FakeViewPadding(top: 24, bottom: entry.safe)
          ..viewPadding = FakeViewPadding(top: 24, bottom: entry.safe);
        addTearDown(tester.view.reset);
        await prepareQaFonts(tester);
        final site = _Site();
        final services = (await tester.runAsync(() async {
          final base = await testServices();
          await base.store.settings.set(Settings.showSplashPage, false);
          await base.store.settings.set(Settings.savedMenuIds, [
            menu.id,
            ...HomeMenu.values.where((m) => m != menu).map((m) => m.id),
          ]);
          await base.store.settings.set(Settings.hotAreasList, [site.id]);
          await base.store.settings.set(Settings.preferPlatform, site.id);
          await base.store.settings.set(Settings.liquidGlass, true);
          await base.store.settings.set(Settings.homeBottomBarCompact, entry.compact);
          await base.store.settings.set(Settings.homeBottomBarOnWide, true);
          await base.store.settings.set(Settings.pageShowScrollTop, true);
          await base.store.settings.set(Settings.pageDefaultSize, 80);
          for (final room in site.rooms) {
            await base.store.follows.add(room);
          }
          return AppServices(
            store: base.store,
            cipher: base.cipher,
            http: base.http,
            proxy: base.proxy,
            cookies: base.cookies,
            sites: SiteRegistry({site.id: () => site}),
            danmaku: base.danmaku,
            launch: base.launch,
            dataRoot: base.dataRoot,
            followsReady: base.followsReady,
            mediaOpener: base.mediaOpener,
          );
        }))!;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(services.close);
        });
        final strings = (await tester.runAsync(loadStrings))!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appServicesProvider.overrideWithValue(services)],
            child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
          ),
        );
        await tester.pumpAndSettle();
        final jump = find.byType(JumpButtons);
        expect(jump, findsOneWidget);
        final controller = tester.widget<JumpButtons>(jump).controller;
        expect(controller.position.maxScrollExtent, greaterThan(1200));
        controller.jumpTo(600);
        await tester.pumpAndSettle();
        final top = find.byKey(const ValueKey('jump-top'));
        final bottom = find.byKey(const ValueKey('jump-bottom'));
        final bar = find.byType(LiquidGlassBar);
        await captureQaFrame(tester, 'jump-${entry.name}-${menu.id}');
        for (final button in [top, bottom]) {
          expect(
            tester.getRect(button).bottom,
            lessThanOrEqualTo(tester.getRect(bar).top - 12),
            reason: 'The full touch target must clear the visible glass bar.',
          );
          expect(button.hitTestable(), findsOneWidget);
        }
        await tester.tap(top);
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(0, 0.1));
        expect(tester.widget<HomeMobileView>(find.byType(HomeMobileView)).selected, menu);
        controller.jumpTo(600);
        await tester.pumpAndSettle();
        await tester.tap(bottom);
        await tester.pumpAndSettle();
        // The final empty-page response removes the loading footer after the jump.
        expect(controller.position.extentAfter, closeTo(0, 0.1));
        expect(tester.getRect(top).bottom, lessThanOrEqualTo(tester.getRect(bar).top - 12));

        // Changing bar height must move the controls without recreating the list.
        await tester.runAsync(() => services.store.settings.set(Settings.homeBottomBarCompact, !entry.compact));
        await tester.pumpAndSettle();
        expect(tester.widget<JumpButtons>(jump).controller, same(controller));
        expect(tester.getRect(bottom).bottom, lessThanOrEqualTo(tester.getRect(bar).top - 12));

        // A plain navigation bar reserves layout space itself: do not add its height again.
        await tester.runAsync(() => services.store.settings.set(Settings.liquidGlass, false));
        await tester.pumpAndSettle();
        expect(bar, findsNothing);
        controller.jumpTo(600);
        await tester.pumpAndSettle();
        final listBounds = tester.getRect(find.ancestor(of: jump, matching: find.byType(Stack)).first);
        expect(listBounds.bottom - tester.getRect(bottom).bottom, closeTo(16, 0.1));
        if (entry.platform == TargetPlatform.android) {
          // Auto-hidden navigation must remove its clearance and preserve scroll state.
          await tester.runAsync(() async {
            await services.store.settings.set(Settings.liquidGlass, true);
            await services.store.settings.set(Settings.homeNavigationAutoHide, true);
          });
          await tester.pumpAndSettle();
          void scroll(double delta) => ScrollUpdateNotification(
            metrics: controller.position,
            context: tester.element(jump),
            scrollDelta: delta,
            dragDetails: DragUpdateDetails(globalPosition: Offset.zero, delta: Offset(0, -delta)),
          ).dispatch(tester.element(jump));
          scroll(30);
          await tester.pumpAndSettle();
          expect(bar, findsNothing);
          expect(tester.widget<JumpButtons>(jump).controller, same(controller));
          final hiddenList = tester.getRect(find.ancestor(of: jump, matching: find.byType(Stack)).first);
          expect(hiddenList.bottom - tester.getRect(bottom).bottom, closeTo(16, 0.1));
          scroll(-30);
          await tester.pumpAndSettle();
          expect(tester.getRect(bottom).bottom, lessThanOrEqualTo(tester.getRect(bar).top - 12));
        }
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(entry.platform));
    }
  }
}
