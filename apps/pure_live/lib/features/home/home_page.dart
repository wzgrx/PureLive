import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/bootstrap.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/areas/areas_page.dart';
import 'package:pure_live/features/favorite/favorite_page.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/home_views.dart';
import 'package:pure_live/features/popular/popular_page.dart';
import 'package:pure_live/features/recorder/recorder_page.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/features/version/update_prompt.dart';
import 'package:pure_live/platform/system_ui.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';

/// The page of each home destination; the app replaces the placeholders as
/// M13 rebuilds the pages (3.x `FavoritePage`, `PopularPage`, `AreasPage`,
/// `RecorderPage`).
typedef HomeTabBuilder = Widget Function(BuildContext context, HomeMenu menu);

/// The home shell (3.x `HomePage`): a bottom bar on phones, a side rail from
/// [homeTabletBreakpoint] (600, U.3b c6; 3.x: above 680), the destinations of
/// the `savedMenuIds` setting on both (U.3b c3).
///
/// Kept from 3.x: selecting follows again refreshes them; back sends the app
/// to the background on Android; after 15 s or more in the background the
/// visible tab refreshes; a room given on the command line opens once the
/// page is up; the main window checks for an update
/// [startupUpdateCheckDelay] after its first frame. The update prompt opens
/// only while home is on top, after any other prompt (U.3c c7).
class HomePage extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({this.tabBuilder = buildHomeTab, super.key});

  /// Builds a destination's page.
  final HomeTabBuilder tabBuilder;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver, RouteAware {
  HomeMenu? _selected;
  DateTime? _backgroundedAt;
  Timer? _resumeTimer;
  Timer? _updateTimer;
  final Map<HomeMenu, Widget> _pages = {};
  bool _hideNavigation = false;
  bool _navigationCanHide = false;
  double _navigationDistance = 0;
  Size? _lastLayoutSize;
  PageRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _route) {
      liveRouteObserver.unsubscribe(this);
      _route = route;
      liveRouteObserver.subscribe(this, route);
    }
  }

  void _restoreNavigation() {
    _navigationDistance = 0;
    if (mounted && _hideNavigation) setState(() => _hideNavigation = false);
  }

  @override
  void didPushNext() => _restoreNavigation();

  @override
  void didPopNext() => _restoreNavigation();

  bool _navigationScroll(ScrollNotification notification) {
    if (!_navigationCanHide ||
        !(_route?.isCurrent ?? true) ||
        notification.metrics.axis != Axis.vertical ||
        notification is! ScrollUpdateNotification) {
      return false;
    }
    if (notification.metrics.pixels <= notification.metrics.minScrollExtent + 1) {
      _restoreNavigation();
      return false;
    }
    if (notification.dragDetails == null) return false;
    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;
    _navigationDistance = _navigationDistance.sign == delta.sign ? _navigationDistance + delta : delta;
    if (_navigationDistance.abs() < 12) return false;
    _navigationDistance = 0;
    final hide = delta > 0;
    if (hide != _hideNavigation) setState(() => _hideNavigation = hide);
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeSignals.select.addListener(_selectAsked);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Edge to edge (3.x); the bars' style is the app's SystemBarsScope
      // (A06.5).
      if (Platform.isAndroid) unawaited(SystemUiVisibility.restore());
      final launch = ref.read(appServicesProvider).launch;
      if (launch.room case final room?) unawaited(AppNavigator.toLiveRoomDetail(liveRoom: room));
      if (launch.isPrimary) _updateTimer = Timer(startupUpdateCheckDelay, _checkForUpdate);
    });
  }

  void _checkForUpdate() {
    if (!mounted) return;
    unawaited(
      checkForUpdateOnStartup(
        context,
        settings: ref.read(appServicesProvider).store.settings,
        feed: ref.read(updateFeedProvider),
      ),
    );
  }

  void _selectAsked() {
    if (HomeSignals.select.value case (final menu, _)) _select(menu);
  }

  @override
  void dispose() {
    liveRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    HomeSignals.select.removeListener(_selectAsked);
    _resumeTimer?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _resumeTimer?.cancel();
      _backgroundedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final away = _backgroundedAt;
    _backgroundedAt = null;
    final menu = _selected;
    if (away == null || menu == null || DateTime.now().difference(away) < HomeSignals.resumeRefreshAfter) return;
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final previous = HomeSignals.resumedAfterBackground.value;
      HomeSignals.resumedAfterBackground.value = (menu, (previous?.$2 ?? 0) + 1);
    });
  }

  void _select(HomeMenu menu) {
    if (menu == _selected && menu == HomeMenu.favorites) {
      HomeSignals.favoritesReselected.value++;
      return;
    }
    setState(() {
      _selected = menu;
      _hideNavigation = false;
      _navigationDistance = 0;
    });
  }

  Future<void> _onBack(bool didPop, Object? result) async {
    if (didPop || !Platform.isAndroid) return;
    try {
      await const MethodChannel('pure_live/app').invokeMethod<bool>('moveToBack');
    } on PlatformException {
      // Stay in front.
    } on MissingPluginException {
      // No activity.
    }
  }

  // A global key per page, so a page keeps its state when the window
  // crosses the rail width (UI_PLAN §5.1).
  Widget _page(HomeMenu menu) => _pages[menu] ??= KeyedSubtree(
    key: GlobalKey(debugLabel: menu.id),
    child: Builder(builder: (context) => widget.tabBuilder(context, menu)),
  );

  @override
  Widget build(BuildContext context) {
    final saved = watchSetting(ref, Settings.savedMenuIds);
    final glass = watchSetting(ref, Settings.liquidGlass);
    final compact = watchSetting(ref, Settings.homeBottomBarCompact);
    final frost = watchSetting(ref, Settings.liquidGlassFrost);
    final autoHide =
        watchSetting(ref, Settings.homeNavigationAutoHide) && defaultTargetPlatform == TargetPlatform.android;
    final mobileLabels = watchSetting(ref, Settings.mobileNavigationLabels);
    final labels =
        !(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) ||
        mobileLabels;
    // V02.6: a tablet may keep the bottom bar (phones and tablets only).
    final bottomOnWide =
        watchSetting(ref, Settings.homeBottomBarOnWide) &&
        (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: _onBack,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rail = isHomeRailWidth(constraints.maxWidth) && !bottomOnWide;
          _navigationCanHide = autoHide && !rail;
          if (!_navigationCanHide || _lastLayoutSize != constraints.biggest) _hideNavigation = false;
          _lastLayoutSize = constraints.biggest;
          final menus = visibleHomeMenus(saved);
          // A removed or hidden destination falls back to the first one (3.x).
          final selected = menus.contains(_selected) ? _selected! : menus.first;
          _selected = selected;
          final body = NotificationListener<ScrollNotification>(
            onNotification: _navigationScroll,
            child: HomeLayoutScope(phone: !rail, navigationHidden: _hideNavigation, child: _page(selected)),
          );
          return rail
              ? HomeTabletView(menus: menus, selected: selected, onSelected: _select, body: body)
              : HomeMobileView(
                  menus: menus,
                  selected: selected,
                  onSelected: _select,
                  body: body,
                  glass: glass,
                  compact: compact,
                  frost: frost,
                  hidden: _hideNavigation,
                  showLabels: labels,
                  glassBlur: liquidGlassBlurs(android: Platform.isAndroid, totalMemoryBytes: deviceMemoryBytes),
                );
        },
      ),
    );
  }
}

/// The page of each home destination (the same page classes the routes
/// open, as home tabs).
Widget buildHomeTab(BuildContext context, HomeMenu menu) => switch (menu) {
  HomeMenu.favorites => const FavoritePage(route: RouteArgs(RoutePath.kFavorite, inHome: true)),
  HomeMenu.popular => const PopularPage(route: RouteArgs(RoutePath.kPopular, inHome: true)),
  HomeMenu.areas => const AreasPage(route: RouteArgs(RoutePath.kAreas, inHome: true)),
  HomeMenu.record => const RecorderPage(route: RouteArgs(RoutePath.kRecordPage, inHome: true)),
};
