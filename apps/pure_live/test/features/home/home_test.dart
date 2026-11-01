import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/startup.dart';
import 'package:pure_live/features/areas/areas_page.dart';
import 'package:pure_live/features/favorite/favorite_page.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/home_page.dart';
import 'package:pure_live/features/home/menu_button.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/popular/popular_page.dart';
import 'package:pure_live/features/recorder/recorder_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/app_router.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/images.dart';

import '../../support.dart';

Future<AppServices> _pump(
  WidgetTester tester, {
  required double width,
  double height = 900,
  List<String>? menus,
  bool bottomBarOnWide = false,
  bool compactBar = false,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    await services.store.settings.set(Settings.showSplashPage, false);
    if (menus != null) await services.store.settings.set(Settings.savedMenuIds, menus);
    if (bottomBarOnWide) await services.store.settings.set(Settings.homeBottomBarOnWide, true);
    if (compactBar) await services.store.settings.set(Settings.homeBottomBarCompact, true);
    return services;
  }))!;
  final strings = (await tester.runAsync(loadStrings))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
    ),
  );
  await tester.pumpAndSettle();
  return services;
}

void main() {
  testWidgets('A06.9: a mouse drags the short desktop rail scrollbar thumb', (tester) async {
    final services = await _pump(tester, width: 1000, height: 400);
    addTearDown(() => tester.runAsync(services.close));
    final rail = find.byKey(const ValueKey('home-rail'));
    final scrollable = find.descendant(of: rail, matching: find.byType(Scrollable)).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(100));
    final bounds = tester.getRect(rail);
    await tester.sendEventToBinding(PointerScrollEvent(position: bounds.center, scrollDelta: const Offset(0, 30)));
    await tester.pumpAndSettle();
    final before = position.pixels;
    expect(before, greaterThan(0));
    final start = Offset(bounds.right - 4, bounds.top + 50);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: start);
    await tester.pump(const Duration(seconds: 1));
    await mouse.down(start);
    await mouse.moveBy(const Offset(0, 120));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(before + 50), reason: 'the thumb, not the content, was dragged');
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final glass in [true, false]) {
    for (final menu in HomeMenu.values) {
      for (final single in [true, false]) {
        testWidgets('hidden navigation keeps content outside system insets: ${menu.id}, glass=$glass, single=$single', (
          tester,
        ) async {
          final services = await _pump(
            tester,
            width: 400,
            menus: [menu.id, if (!single) ...HomeMenu.values.where((other) => other != menu).map((other) => other.id)],
          );
          addTearDown(() => tester.runAsync(services.close));
          tester.view.padding = const FakeViewPadding(left: 12, top: 48, right: 8, bottom: 24);
          tester.view.viewPadding = const FakeViewPadding(left: 12, top: 48, right: 8, bottom: 24);
          await tester.runAsync(() async {
            await services.store.settings.set(Settings.liquidGlass, glass);
            await services.store.settings.set(Settings.homeNavigationAutoHide, true);
          });
          await tester.pumpAndSettle();
          final page = find.byType(switch (menu) {
            HomeMenu.favorites => FavoritePage,
            HomeMenu.popular => PopularPage,
            HomeMenu.areas => AreasPage,
            HomeMenu.record => RecorderPage,
          });
          final element = tester.element(page);
          void scroll(double delta) => ScrollUpdateNotification(
            metrics: FixedScrollMetrics(
              minScrollExtent: 0,
              maxScrollExtent: 2000,
              pixels: 300,
              viewportDimension: 700,
              axisDirection: AxisDirection.down,
              devicePixelRatio: 1,
            ),
            context: element,
            scrollDelta: delta,
            dragDetails: DragUpdateDetails(globalPosition: Offset.zero, delta: Offset(0, -delta)),
          ).dispatch(element);
          scroll(30);
          await tester.pumpAndSettle();
          expect(find.byType(AppBar), findsNothing);
          final scaffold = tester.widget<Scaffold>(find.descendant(of: page, matching: find.byType(Scaffold)).first);
          final bounds = tester.getRect(find.byWidget(scaffold.body!));
          expect(bounds.top, greaterThanOrEqualTo(48), reason: 'content must stay below the status bar');
          expect(bounds.left, greaterThanOrEqualTo(12), reason: 'content must avoid the left cutout');
          expect(bounds.right, lessThanOrEqualTo(392), reason: 'content must avoid the right cutout');
          expect(bounds.bottom, lessThanOrEqualTo(876), reason: 'content must avoid system navigation');
          scroll(-30);
          await tester.pumpAndSettle();
          expect(find.byType(AppBar), findsOneWidget);
          expect(tester.element(page), same(element), reason: 'inset changes must preserve the live page state');
          await tester.pumpWidget(const SizedBox.shrink());
        }, variant: TargetPlatformVariant.only(TargetPlatform.android));
      }
    }
  }

  testWidgets('issue 65: hiding navigation removes the followed-platform header too', (tester) async {
    final services = await _pump(tester, width: 400);
    addTearDown(() => tester.runAsync(services.close));
    await tester.runAsync(() async {
      await services.store.settings.set(Settings.liquidGlass, false);
      await services.store.settings.set(Settings.homeNavigationAutoHide, true);
      await services.store.follows.add(LiveRoom(platform: SiteIds.bilibili, roomId: 'qa-header', nick: 'QA'));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNotNull);
    final context = tester.element(find.byType(FavoritePage));
    ScrollUpdateNotification(
      metrics: FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 2000,
        pixels: 300,
        viewportDimension: 700,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1,
      ),
      context: context,
      scrollDelta: 30,
      dragDetails: DragUpdateDetails(globalPosition: Offset.zero, delta: const Offset(0, -30)),
    ).dispatch(context);
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing, reason: 'the complete header, including the platform row, must hide');
    expect(find.byType(NavigationBar), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('issue 65: navigation label options preserve accessible names', (tester) async {
    final services = await _pump(tester, width: 1280);
    await tester.runAsync(
      () => services.store.settings.set(
        const BoolSetting('desktopNavigationLabels', section: 'theme', defaultValue: true),
        false,
      ),
    );
    await tester.pumpAndSettle();
    final rail = find.byKey(const ValueKey('home-rail'));
    expect(find.descendant(of: rail, matching: find.byType(Text)), findsNothing);
    expect(find.descendant(of: rail, matching: find.byTooltip('搜索直播')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(services.close);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('issue 65: Android hides both navigation bars on vertical user scroll and restores them', (tester) async {
    final services = await _pump(tester, width: 400);
    await tester.runAsync(() async {
      await services.store.settings.set(Settings.liquidGlass, false);
      await services.store.settings.set(
        const BoolSetting('homeNavigationAutoHide', section: 'theme', defaultValue: false),
        true,
      );
    });
    await tester.pumpAndSettle();
    void scroll(double delta, AxisDirection axis, {bool user = true, double pixels = 300}) {
      final context = tester.element(find.byType(FavoritePage));
      ScrollUpdateNotification(
        metrics: FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 2000,
          pixels: pixels,
          viewportDimension: 700,
          axisDirection: axis,
          devicePixelRatio: 1,
        ),
        context: context,
        scrollDelta: delta,
        dragDetails: user ? DragUpdateDetails(globalPosition: Offset.zero, delta: Offset(0, -delta)) : null,
      ).dispatch(context);
    }

    expect(find.byType(NavigationBar), findsOneWidget);
    scroll(30, AxisDirection.right);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget, reason: 'horizontal paging leaves navigation visible');
    scroll(30, AxisDirection.down, user: false);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget, reason: 'programmatic scrolling leaves navigation visible');
    scroll(30, AxisDirection.down);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    scroll(0, AxisDirection.down, user: false, pixels: 0);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget, reason: 'the jump-to-top action restores navigation too');
    scroll(30, AxisDirection.down);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    scroll(-30, AxisDirection.down);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.getSize(find.byType(AppBar)).height, greaterThan(0));
    scroll(30, AxisDirection.down);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    scroll(-2, AxisDirection.down, pixels: 0);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget, reason: 'returning to the start always restores navigation');
    scroll(30, AxisDirection.down);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(700, 400);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-rail')), findsOneWidget, reason: 'rotation restores the navigation layout');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(services.close);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final glass in [true, false]) {
    testWidgets('issue 65: mobile labels can be hidden in either bottom bar (glass=$glass)', (tester) async {
      final services = await _pump(tester, width: 400);
      addTearDown(() => tester.runAsync(services.close));
      await tester.runAsync(() async {
        await services.store.settings.set(Settings.liquidGlass, glass);
        await services.store.settings.set(Settings.mobileNavigationLabels, false);
        await services.store.settings.set(Settings.homeNavigationAutoHide, true);
      });
      await tester.pumpAndSettle();
      if (glass) {
        expect(tester.widget<LiquidGlassBar>(find.byType(LiquidGlassBar)).showLabels, isFalse);
        expect(find.descendant(of: find.byType(LiquidGlassBar), matching: find.byType(Text)), findsNothing);
      } else {
        expect(
          tester.widget<NavigationBar>(find.byType(NavigationBar)).labelBehavior,
          NavigationDestinationLabelBehavior.alwaysHide,
        );
      }
      final context = tester.element(find.byType(FavoritePage));
      ScrollUpdateNotification(
        metrics: FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: 2000,
          pixels: 300,
          viewportDimension: 700,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 1,
        ),
        context: context,
        scrollDelta: 30,
        dragDetails: DragUpdateDetails(globalPosition: Offset.zero, delta: const Offset(0, -30)),
      ).dispatch(context);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(LiquidGlassBar), findsNothing);
      await tester.runAsync(() => services.store.settings.set(Settings.homeNavigationAutoHide, false));
      await tester.pumpAndSettle();
      expect(glass ? find.byType(LiquidGlassBar) : find.byType(NavigationBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  test("every page 3.x registered has a route, each built by its page folder's class", () {
    expect(
      {RoutePath.kInitial, ...pageRoutes.keys},
      {
        RoutePath.kInitial, RoutePath.kSignIn, RoutePath.kMine, RoutePath.kUserManage, RoutePath.kFavorite, //
        RoutePath.kPopular, RoutePath.kAreas, RoutePath.kSettings, RoutePath.kHistory, RoutePath.kSearch,
        RoutePath.kBackup, RoutePath.kIptv, RoutePath.kAbout, RoutePath.kAreaRooms, RoutePath.kLivePlay,
        RoutePath.kMultiview, RoutePath.kSettingsAccount, RoutePath.kBiliBiliWebLogin, RoutePath.kBiliBiliQRLogin,
        RoutePath.kSettingsDanmuShield, RoutePath.kSettingsHotAreas, RoutePath.kVersionHistory, RoutePath.kToolbox,
        RoutePath.kFavoriteAreas, RoutePath.kHuyaCookie, RoutePath.kDouyuAccountCookie, RoutePath.kDouyinCookie,
        RoutePath.kDouyuCookie, RoutePath.kTwitchCookie, RoutePath.kYyCookie, RoutePath.kSoop,
        RoutePath.kKuaishouCookie, RoutePath.kWebDavPage, RoutePath.kSplash, RoutePath.kVersionPage,
        RoutePath.kRecordPage, RoutePath.kRecordSettings, RoutePath.kWebSearch, RoutePath.kSettingsTags,
        RoutePath.kRemoteSync,
        RoutePath.kPlaybackRemote,
        RoutePath.kScreenMirror,
        RoutePath.kDouyuVod,
        RoutePath.kHuyaArchives,
        // U.2k: the local interaction settings (3.x pushed the page directly).
        RoutePath.kLocalInteraction,
        // U.11a: the log page moved out of the backup page (3.x) into settings.
        RoutePath.kLogs,
        // F02 c1: 设置 → 弹幕, the live room's danmaku settings on a page of their own.
        RoutePath.kDanmakuSettings,
      },
    );
  });

  test('menus: saved order, unknown and repeated ids dropped, the same on the bar and the rail', () {
    expect(HomeMenu.fromIds(['areas', 'bogus', 'favorites', 'areas']), [HomeMenu.areas, HomeMenu.favorites]);
    // U.3b c3: the recording centre is a destination on the rail too.
    expect(visibleHomeMenus(['record', 'popular']), [HomeMenu.record, HomeMenu.popular]);
    // Nothing usable saved: every destination (3.x showed an empty page).
    expect(visibleHomeMenus(['bogus']), HomeMenu.values);
  });

  testWidgets('A06.5 c1: Android system bars are see-through; their icons follow the theme, also when it changes', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final services = await _pump(tester, width: 400);
      for (final (mode, icons) in [('Light', Brightness.dark), ('Dark', Brightness.light)]) {
        await tester.runAsync(() => services.store.settings.set(Settings.themeMode, mode));
        await tester.pumpAndSettle();
        final style = SystemChrome.latestStyle!;
        expect(style.systemNavigationBarColor, const Color(0x00000000), reason: mode);
        expect(style.systemNavigationBarDividerColor, const Color(0x00000000), reason: mode);
        expect(style.systemNavigationBarIconBrightness, icons, reason: mode);
        expect(style.statusBarColor, const Color(0x00000000), reason: mode);
        expect(style.statusBarIconBrightness, icons, reason: mode);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('phone: bottom bar of the saved menus; follows again refreshes them', (tester) async {
    final services = await _pump(tester, width: 400);
    // A01.6: liquid glass by default.
    expect(find.byType(LiquidGlassBar), findsOneWidget);
    expect(find.byWidgetPredicate((widget) => '${widget.key}'.contains('home-nav-')), findsNWidgets(4));
    expect(find.widgetWithText(AppBar, '已开播'), findsOneWidget);

    await tester.tap(_navItem('热门'));
    await tester.pumpAndSettle();
    // U.4b: the popular page's title place holds its platform tabs (3.x).
    expect(find.byType(PopularPage), findsOneWidget);

    await tester.tap(_navItem('关注'));
    await tester.pumpAndSettle();
    final before = HomeSignals.favoritesReselected.value;
    await tester.tap(_navItem('关注'));
    await tester.pumpAndSettle();
    expect(HomeSignals.favoritesReselected.value, before + 1);

    // One destination: no bar (3.x).
    await tester.runAsync(() => services.store.settings.set(Settings.savedMenuIds, ['popular']));
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlassBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    // U.4b: the popular page's title place holds its platform tabs (3.x).
    expect(find.byType(PopularPage), findsOneWidget);
    await tester.runAsync(services.close);
  });

  testWidgets('phone bar: menu at the left; search and more at the right, in this order (U.3a c4)', (tester) async {
    final services = await _pump(tester, width: 393);
    final bar = find.widgetWithText(AppBar, '已开播');
    final menu = find.descendant(of: bar, matching: find.byTooltip('菜单'));
    final search = find.descendant(of: bar, matching: find.byTooltip('搜索直播'));
    final more = find.descendant(of: bar, matching: find.byTooltip('更多'));
    expect(menu, findsOneWidget);
    expect(search, findsOneWidget);
    expect(more, findsOneWidget);
    expect(find.descendant(of: menu, matching: find.byIcon(AppIcons.appMenu)), findsOneWidget);
    expect(find.descendant(of: search, matching: find.byIcon(AppIcons.search)), findsOneWidget);
    expect(find.descendant(of: more, matching: find.byIcon(AppIcons.more)), findsOneWidget);
    // 3.x's menu-and-magnifier button is gone.
    expect(find.byIcon(Remix.menu_search_line), findsNothing);
    expect(tester.getCenter(menu).dx, lessThan(60));
    expect(tester.getCenter(search).dx, lessThan(tester.getCenter(more).dx));
    expect(tester.getRect(more).right, greaterThan(380));
    // Touch targets of at least 48.
    for (final button in [menu, search, more]) {
      final target = find.ancestor(of: button, matching: find.byType(IconButton)).first;
      expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    }

    // Search is one tap.
    await tester.tap(search);
    await tester.pumpAndSettle();
    expect(liveRouteObserver.currentRoute.value, RoutePath.kSearch);
    AppNavigator.back();
    await tester.pumpAndSettle();
    await tester.runAsync(services.close);
  });

  testWidgets('phone bottom bar: four destinations, their order and icons; areas has the shapes (U.3a c7)', (
    tester,
  ) async {
    final services = await _pump(tester, width: 393);
    final ids = ['favorites', 'popular', 'areas', 'record'];
    final rects = [for (final id in ids) tester.getRect(find.byKey(ValueKey('home-nav-$id')))];
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left, greaterThan(rects[i - 1].left));
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-nav-favorites')),
        matching: find.byIcon(AppIcons.homeFavoritesSelected),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('home-nav-areas')), matching: find.byIcon(Remix.shapes_line)),
      findsOneWidget,
    );
    expect(find.byIcon(Remix.apps_2_line), findsNothing);
    expect(
      find.descendant(of: find.byKey(const ValueKey('home-nav-record')), matching: find.byIcon(Remix.download_2_line)),
      findsOneWidget,
    );
    await tester.runAsync(services.close);
  });

  testWidgets(
    'phone menus: the same small menu; settings, about, backup at the left, history, link, multi-view in more',
    (tester) async {
      final services = await _pump(tester, width: 393);
      final scheme = Theme.of(tester.element(find.byType(HomePage))).colorScheme;
      final bar = find.widgetWithText(AppBar, '已开播');

      Future<void> checkMenu(Finder button, List<(String, String, IconData)> rows, {required bool right}) async {
        await tester.tap(button);
        await tester.pumpAndSettle();
        final buttonRect = tester.getRect(find.ancestor(of: button, matching: find.byType(IconButton)).first);
        double? top;
        for (final (key, label, icon) in rows) {
          final row = find.byKey(ValueKey(key));
          expect(row, findsOneWidget, reason: label);
          final rect = tester.getRect(row);
          expect(rect.height, 48, reason: label);
          if (top != null) expect(rect.top, greaterThan(top), reason: label);
          top = rect.top;
          final text = tester.widget<Text>(find.descendant(of: row, matching: find.text(label)));
          expect(text.style?.fontSize, 14, reason: label);
          final iconWidget = tester.widget<Icon>(find.descendant(of: row, matching: find.byIcon(icon)));
          expect(iconWidget.size, 24, reason: label);
          expect(iconWidget.color, scheme.onSurfaceVariant, reason: label);
          // Next to the button, below it.
          expect(rect.top, greaterThan(buttonRect.bottom), reason: label);
          // Lined up with the button, but Material keeps menus 8 from the
          // screen's edge.
          if (right) {
            expect(rect.right, closeTo(math.min(buttonRect.right, 393 - 8), 1), reason: label);
          } else {
            expect(rect.left, closeTo(math.max(buttonRect.left, 8), 1), reason: label);
          }
        }
        final menuMaterial = tester.widget<Material>(
          find.ancestor(of: find.byKey(ValueKey(rows.first.$1)), matching: find.byType(Material)).first,
        );
        expect(menuMaterial.color, scheme.surfaceContainerHighest);
        expect((menuMaterial.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(8));
        await tester.tapAt(const Offset(200, 600));
        await tester.pumpAndSettle();
      }

      await checkMenu(find.descendant(of: bar, matching: find.byTooltip('菜单')), [
        ('home-menu-settings', '设置', AppIcons.settings),
        ('home-menu-about', '关于', AppIcons.about),
        ('home-menu-backup', '备份与恢复', AppIcons.backup),
      ], right: false);
      // The watch history moved to "more" (U.3a c3) and is called 观看记录 (U.5c).
      await tester.tap(find.descendant(of: bar, matching: find.byTooltip('菜单')));
      await tester.pumpAndSettle();
      expect(find.text('历史记录'), findsNothing);
      expect(find.text('观看记录'), findsNothing);
      await tester.tapAt(const Offset(200, 600));
      await tester.pumpAndSettle();

      await checkMenu(find.descendant(of: bar, matching: find.byTooltip('更多')), [
        ('home-more-history', '观看记录', AppIcons.watchHistory),
        ('home-more-openLink', '链接解析', AppIcons.openLink),
        ('home-more-multiview', '多画面', AppIcons.multiview),
      ], right: true);
      expect(find.text('链接访问'), findsNothing);

      // Multi-view off: two rows.
      await tester.runAsync(() => services.store.settings.set(Settings.enableMultiView, false));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: bar, matching: find.byTooltip('更多')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-more-multiview')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('home-more-history')));
      await tester.pumpAndSettle();
      expect(liveRouteObserver.currentRoute.value, RoutePath.kHistory);
      AppNavigator.back();
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(of: bar, matching: find.byTooltip('菜单')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-menu-about')));
      await tester.pumpAndSettle();
      expect(liveRouteObserver.currentRoute.value, RoutePath.kAbout);
      AppNavigator.back();
      await tester.pumpAndSettle();
      await tester.runAsync(services.close);
    },
  );

  test('the app menu: Windows with the setting adds the independent window last', () {
    expect(appMenuItems(newWindow: false), [AppMenuItem.settings, AppMenuItem.about, AppMenuItem.backup]);
    expect(appMenuItems(newWindow: true).last, AppMenuItem.newWindow);
    expect(AppMenuItem.newWindow.icon, AppIcons.newPlayerWindow);
    expect(homeActions(multiView: true), HomeAction.values);
    expect(homeActions(multiView: false), [HomeAction.search, HomeAction.history, HomeAction.openLink]);
  });

  testWidgets('phone recording tab: folder and settings, then search and more (U.3a c6)', (tester) async {
    final services = await _pump(tester, width: 393);
    await tester.tap(find.byKey(const ValueKey('home-nav-record')));
    await tester.pumpAndSettle();
    final bar = find.widgetWithText(AppBar, '录制中心');
    expect(find.descendant(of: bar, matching: find.byTooltip('菜单')), findsOneWidget);
    final settings = tester.getCenter(
      find.descendant(of: bar, matching: find.byKey(const ValueKey('recorder-settings'))),
    );
    final search = tester.getCenter(find.descendant(of: bar, matching: find.byTooltip('搜索直播')));
    final more = tester.getCenter(find.descendant(of: bar, matching: find.byTooltip('更多')));
    expect(settings.dx, lessThan(search.dx));
    expect(search.dx, lessThan(more.dx));
    await tester.runAsync(services.close);
  });

  testWidgets('rail from 600: menu, four tools with names, a line, then the four destinations (U.3b)', (tester) async {
    final services = await _pump(tester, width: 1280, height: 800);
    expect(find.byKey(const ValueKey('home-rail')), findsOneWidget);
    expect(find.byType(LiquidGlassBar), findsNothing);
    // The page bars have no menu buttons on the rail (3.x).
    expect(find.descendant(of: find.byType(AppBar), matching: find.byTooltip('更多')), findsNothing);
    final rail = find.byKey(const ValueKey('home-rail'));
    expect(tester.getSize(rail).width, 80);
    final order = [
      'home-menu',
      'home-rail-search',
      'home-rail-history',
      'home-rail-openLink',
      'home-rail-multiview',
      'home-rail-separator',
      'home-nav-favorites',
      'home-nav-popular',
      'home-nav-areas',
      'home-nav-record',
    ];
    final tops = [for (final key in order) tester.getRect(find.byKey(ValueKey(key))).top];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]), reason: order[i]);
    }
    // Tools carry their names under the icons (U.3b c2), same icons as the phone.
    for (final (key, label, icon) in [
      ('home-rail-search', '搜索直播', AppIcons.search),
      ('home-rail-history', '观看记录', AppIcons.watchHistory),
      ('home-rail-openLink', '链接解析', AppIcons.openLink),
      ('home-rail-multiview', '多画面', AppIcons.multiview),
    ]) {
      final tool = find.byKey(ValueKey(key));
      expect(find.descendant(of: tool, matching: find.text(label)), findsOneWidget);
      expect(
        tester.getCenter(find.descendant(of: tool, matching: find.text(label))).dy,
        greaterThan(tester.getCenter(find.descendant(of: tool, matching: find.byIcon(icon))).dy),
      );
    }
    expect(find.descendant(of: rail, matching: find.byIcon(Remix.shapes_line)), findsOneWidget);

    // The recording centre is a destination: the rail stays, no page is pushed.
    await tester.tap(find.byKey(const ValueKey('home-nav-record')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '录制中心'), findsOneWidget);
    expect(rail, findsOneWidget);
    expect(liveRouteObserver.currentRoute.value, RoutePath.kInitial);
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(BackButton)), findsNothing);

    // The rail's menu is the same small menu.
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-menu-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-menu-backup')), findsOneWidget);
    await tester.tapAt(const Offset(600, 600));
    await tester.pumpAndSettle();

    // A rail tool opens its page.
    await tester.tap(find.byKey(const ValueKey('home-rail-history')));
    await tester.pumpAndSettle();
    expect(liveRouteObserver.currentRoute.value, RoutePath.kHistory);
    AppNavigator.back();
    await tester.pumpAndSettle();

    // Only the recording centre saved: one destination, never an empty page.
    await tester.runAsync(() => services.store.settings.set(Settings.savedMenuIds, ['record']));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-nav-record')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-nav-favorites')), findsNothing);
    expect(find.text('尚未选择任何菜单'), findsNothing);
    await tester.runAsync(services.close);
  });

  testWidgets('the rail starts at 600 wide (U.3b c6; 3.x: above 680)', (tester) async {
    var services = await _pump(tester, width: 600);
    expect(find.byKey(const ValueKey('home-rail')), findsOneWidget);
    expect(find.byType(LiquidGlassBar), findsNothing);
    await tester.runAsync(services.close);
    await tester.pumpWidget(const SizedBox.shrink());

    services = await _pump(tester, width: 599);
    expect(find.byKey(const ValueKey('home-rail')), findsNothing);
    expect(find.byType(LiquidGlassBar), findsOneWidget);
    await tester.runAsync(services.close);
  });

  testWidgets('V02.6 (issue #4): a tablet may keep the bottom bar; the glass capsule stays narrow in the middle', (
    tester,
  ) async {
    var services = await _pump(tester, width: 1280, height: 800, bottomBarOnWide: true);
    expect(find.byKey(const ValueKey('home-rail')), findsNothing);
    final glass = find.byType(LiquidGlassBar);
    expect(glass, findsOneWidget);
    final capsule = tester.getRect(glass);
    expect(capsule.width, GlassMetrics.barMaxWidth);
    expect(capsule.center.dx, closeTo(640, 0.5));
    // The rail's tools are reached as on a phone: menu, search and more in
    // the page's bar.
    final bar = find.widgetWithText(AppBar, '已开播');
    for (final tooltip in ['菜单', '搜索直播', '更多']) {
      expect(
        find.descendant(of: bar, matching: find.byTooltip(tooltip)),
        findsOneWidget,
        reason: tooltip,
      );
    }
    await tester.tap(find.byKey(const ValueKey('home-nav-popular')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-rail')), findsNothing);
    await tester.runAsync(services.close);
    await tester.pumpWidget(const SizedBox.shrink());

    // A phone's capsule is as before: the width less the margins.
    services = await _pump(tester, width: 393, bottomBarOnWide: true);
    expect(tester.getRect(find.byType(LiquidGlassBar)).width, 393 - 2 * GlassMetrics.barMargin);
    await tester.runAsync(services.close);
    await tester.pumpWidget(const SizedBox.shrink());

    // Phones and tablets only: a desktop window keeps its rail.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      services = await _pump(tester, width: 1280, height: 800, bottomBarOnWide: true);
      expect(find.byKey(const ValueKey('home-rail')), findsOneWidget);
      expect(find.byType(LiquidGlassBar), findsNothing);
      await tester.runAsync(services.close);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('issue 14: dragging the lower rail scrolls the whole short landscape rail', (tester) async {
    final services = await _pump(tester, width: 852, height: 393);
    final menu = find.byKey(const ValueKey('home-menu'));
    final initialTop = tester.getTopLeft(menu).dy;
    await tester.dragFrom(const Offset(40, 330), const Offset(0, -280));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(menu).dy, lessThan(initialTop - 40));
    final record = find.byKey(const ValueKey('home-nav-record'));
    await tester.ensureVisible(record);
    await tester.pumpAndSettle();
    expect(record.hitTestable(), findsOneWidget);
    await tester.tap(record);
    await tester.pumpAndSettle();
    expect(find.byType(RecorderPage), findsOneWidget);
    await tester.dragFrom(const Offset(40, 150), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(menu.hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('home-rail-search')).hitTestable(), findsOneWidget);
    await tester.runAsync(services.close);
  });

  testWidgets('short landscape rail: every destination remains reachable with large text and safe areas', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 20);
    final services = await _pump(tester, width: 740, height: 280);
    expect(find.byKey(const ValueKey('home-rail')), findsOneWidget);
    final rail = tester.getRect(find.byKey(const ValueKey('home-rail')));
    for (final id in ['favorites', 'popular', 'areas', 'record']) {
      final target = find.byKey(ValueKey('home-nav-$id'));
      await tester.scrollUntilVisible(
        target,
        80,
        scrollable: find.descendant(of: find.byKey(const ValueKey('home-rail')), matching: find.byType(Scrollable)),
      );
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget, reason: id);
      final rect = tester.getRect(target);
      expect(rect.bottom, lessThanOrEqualTo(rail.bottom), reason: id);
      expect(rect.top, greaterThanOrEqualTo(rail.top), reason: id);
    }
    await tester.dragFrom(rail.center, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-menu')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(services.close);
  });

  testWidgets('A01.5, A01.6: liquid glass: the bar floats as a glass capsule over the page; off, the plain bar', (
    tester,
  ) async {
    // A status bar and a gesture area, as on a phone.
    tester.view.padding = const FakeViewPadding(top: 40, bottom: 20);
    tester.view.viewPadding = const FakeViewPadding(top: 40, bottom: 20);
    final services = await _pump(tester, width: 400);
    // On by default (A01.6). A capsule 12 in from the sides, 68 high, 6
    // above the gesture handle in the middle of the area (V02.11: 18 from
    // the bottom, not 20 + 12).
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.getRect(find.byType(LiquidGlassBar)), const Rect.fromLTRB(12, 814, 388, 882));
    // The page goes on under it, and its lists know how much it covers.
    expect(tester.getRect(find.byType(FavoritePage)).bottom, 900);
    final page = tester.element(find.byType(FavoritePage));
    expect(GlassBarInset.of(page), 86);
    await tester.tap(_navItem('热门'));
    await tester.pumpAndSettle();
    expect(find.byType(PopularPage), findsOneWidget);

    // Held and dragged along the bar, the drop follows; let go over the
    // next destination, that one is chosen.
    final from = tester.getCenter(_navItem('热门'));
    final to = tester.getCenter(_navItem('分区'));
    await tester.dragFrom(from, Offset(to.dx - from.dx, 0));
    await tester.pumpAndSettle();
    expect(find.byType(AreasPage), findsOneWidget);
    // Dragged far past the last one it stays on the last one.
    await tester.dragFrom(to, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.byType(RecorderPage), findsOneWidget);

    // A larger system font: no overflow.
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.platformDispatcher.clearTextScaleFactorTestValue();

    // The rail of a wide window has no glass.
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlassBar), findsNothing);
    tester.view.physicalSize = const Size(400, 900);
    await tester.pumpAndSettle();

    // A01.8: the "玻璃质感" slider reaches the glass.
    expect(tester.allRenderObjects.whereType<RenderLiquidGlass>().single.frost, 0.5);
    await tester.runAsync(() => services.store.settings.set(Settings.liquidGlassFrost, 0.9));
    await tester.pumpAndSettle();
    expect(tester.allRenderObjects.whereType<RenderLiquidGlass>().single.frost, 0.9);

    await tester.runAsync(() => services.store.settings.set(Settings.liquidGlass, false));
    await tester.pumpAndSettle();
    expect(find.byType(LiquidGlassBar), findsNothing);
    expect(tester.getRect(find.byType(NavigationBar)), const Rect.fromLTRB(0, 800, 400, 900));
    await tester.runAsync(services.close);
  });

  testWidgets('V02.11 (issue #9): the capsule sits just above the home indicator; the compact bars are lower', (
    tester,
  ) async {
    Rect capsule() => tester.getRect(find.byType(LiquidGlassBar));
    double inset() => GlassBarInset.of(tester.element(find.byType(FavoritePage)));
    // An iPhone: its home indicator at the bottom of the 34; the capsule 20
    // up instead of 34 + 12.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
      var services = await _pump(tester, width: 393, height: 852);
      expect(capsule(), const Rect.fromLTRB(12, 764, 381, 832));
      expect(inset(), 88);
      await tester.runAsync(() => services.store.settings.set(Settings.homeBottomBarCompact, true));
      await tester.pumpAndSettle();
      expect(capsule(), const Rect.fromLTRB(12, 776, 381, 832));
      expect(inset(), 76);
      // The plain bar: 64 instead of Material's 80, over the indicator's room.
      await tester.runAsync(() => services.store.settings.set(Settings.liquidGlass, false));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(NavigationBar)), const Rect.fromLTRB(0, 754, 393, 852));
      // A larger system font: neither compact bar overflows.
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => services.store.settings.set(Settings.liquidGlass, true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.runAsync(services.close);
      await tester.pumpWidget(const SizedBox.shrink());

      // Android's buttons: the capsule stays 12 above them.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.padding = const FakeViewPadding(top: 40, bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(top: 40, bottom: 48);
      services = await _pump(tester, width: 393, height: 852);
      expect(capsule(), const Rect.fromLTRB(12, 724, 381, 792));
      await tester.runAsync(services.close);
      await tester.pumpWidget(const SizedBox.shrink());

      // No room at the bottom (gestures without a handle): 12, as before.
      tester.view.resetPadding();
      tester.view.resetViewPadding();
      services = await _pump(tester, width: 393, height: 852, compactBar: true);
      expect(capsule(), const Rect.fromLTRB(12, 784, 381, 840));
      await tester.runAsync(services.close);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a larger system font: bar, menus and rail do not overflow', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    var services = await _pump(tester, width: 1280, height: 800);
    expect(tester.takeException(), isNull);
    await tester.runAsync(services.close);
    await tester.pumpWidget(const SizedBox.shrink());
    services = await _pump(tester, width: 393);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(200, 600));
    await tester.pumpAndSettle();
    await tester.runAsync(services.close);
  });

  testWidgets('Z05.3: a language picked in the settings reaches the home under them at once, its state kept', (
    tester,
  ) async {
    final services = await _pump(tester, width: 393);
    final before = tester.state(find.byType(FavoritePage));
    Finder label(String text) =>
        find.descendant(of: find.byKey(const ValueKey('home-nav-favorites')), matching: find.text(text));
    expect(label('关注'), findsOneWidget);
    unawaited(AppNavigator.toNamed<void>(RoutePath.kSettings));
    await tester.pumpAndSettle();
    await tester.runAsync(() => services.store.settings.set(Settings.language, AppLanguage.ja.displayName));
    // The words load from the asset bundle off the test's fake clock.
    for (var i = 0; i < 20 && currentStrings?.language != AppLanguage.ja; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(currentStrings?.language, AppLanguage.ja);
    AppNavigator.back<void>();
    await tester.pumpAndSettle();
    expect(label('フォロー'), findsOneWidget);
    expect(find.textContaining('オンライン'), findsWidgets);
    expect(tester.state(find.byType(FavoritePage)), same(before));
    await tester.runAsync(services.close);
  });

  testWidgets('crossing the rail width keeps the page (its state is not rebuilt)', (tester) async {
    final services = await _pump(tester, width: 393);
    final before = tester.state(find.byType(FavoritePage));
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-rail')), findsOneWidget);
    expect(tester.state(find.byType(FavoritePage)), same(before));
    await tester.runAsync(services.close);
  });

  testWidgets('a live room opens with its room; a retired platform is refused', (tester) async {
    final services = await _pump(tester, width: 400);
    final toasts = <String>[];
    AppNavigator.toast = toasts.add;

    await AppNavigator.toLiveRoomDetail(
      liveRoom: LiveRoom(platform: 'huajiao', roomId: 'x'),
    );
    await tester.pumpAndSettle();
    expect(toasts.single, contains('下线'));
    expect(find.byType(LivePlayPage), findsNothing);

    await AppNavigator.toLiveRoomDetail(
      liveRoom: LiveRoom(platform: 'Bilibili', roomId: '23030429', nick: '主播'),
    );
    // A second tap while the room comes in is ignored (3.x).
    await AppNavigator.toLiveRoomDetail(
      liveRoom: LiveRoom(platform: 'huya', roomId: '1'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LivePlayPage), findsOneWidget);
    expect(find.text('主播'), findsWidgets);

    AppNavigator.back();
    await tester.pumpAndSettle();
    expect(find.byType(LivePlayPage), findsNothing);
    await tester.pump(AppNavigator.openGuard);
    await tester.runAsync(services.close);
  });

  testWidgets('splash first when it is on, then home; start-up work and image settings are wired', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(testServices))!;
    final strings = (await tester.runAsync(loadStrings))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
      ),
    );
    await tester.pump();
    expect(find.text('欢迎使用'), findsOneWidget);
    // The follow check starts after the first frame; the splash waits for it.
    expect(AppStartup.followCheck, isNotNull);
    final config = LiveUiScope.of(tester.element(find.text('欢迎使用')));
    expect(config.imageHeaders?.call('https://i0.hdslb.com/a.jpg')?['Referer'], 'https://live.bilibili.com/');
    expect(config.imageHeaders?.call('https://img.example.com/a.jpg')?.containsKey('Referer'), isFalse);
    final epoch = config.imageCacheEpoch;
    imageCacheEpoch.value++;
    await tester.pump();
    expect(LiveUiScope.of(tester.element(find.text('欢迎使用'))).imageCacheEpoch, epoch + 1);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用'), findsNothing);
    expect(find.widgetWithText(AppBar, '已开播'), findsOneWidget);
    // The update check after two seconds stays quiet without a network.
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(services.close);
  });
}

/// A destination of the home page's liquid glass bar.
Finder _navItem(String label) => find.descendant(of: find.byType(LiquidGlassBar), matching: find.text(label));
