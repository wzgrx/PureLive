import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_router.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/tv/home/tv_home_page.dart';
import 'package:pure_live/tv/pages/tv_area_rooms_page.dart';
import 'package:pure_live/tv/pages/tv_search_page.dart';
import 'package:pure_live/tv/room/tv_live_play_page.dart';
import 'package:pure_live/tv/settings/tv_platform_settings_page.dart';
import 'package:pure_live/tv/settings/tv_settings_section_page.dart';
import 'package:pure_live/tv/settings/tv_settings_style.dart';

const Set<String> _tvSettingsRoots = {
  RoutePath.kMine,
  RoutePath.kWebDavPage,
  RoutePath.kRemoteSync,
  RoutePath.kIptv,
  RoutePath.kRecordSettings,
  RoutePath.kLocalInteraction,
  RoutePath.kBackup,
  RoutePath.kLogs,
  RoutePath.kAbout,
  RoutePath.kVersionPage,
  RoutePath.kVersionHistory,
};

/// The pages the TV interface (M14.1) puts on the phone's paths, so every
/// `AppNavigator` call (a card, the room switcher, a deep link) lands on the
/// TV page: the live room, an area's rooms and search.
final Map<String, PageBuilder> tvPageRoutes = {
  RoutePath.kLivePlay: (route) => TvLivePlayPage(route: route),
  RoutePath.kAreaRooms: (route) => TvAreaRoomsPage(route: route),
  RoutePath.kSearch: (route) => TvSearchPage(route: route),
  // A17.9 c11: show, hide and move on one page with the remote.
  RoutePath.kSettingsHotAreas: (route) => TvPlatformSettingsPage(route: route),
};

/// The router of the TV interface: the TV home ([TvHomePage]) at the root,
/// [tvPageRoutes] on their paths and every other page of [pageRoutes]
/// (accounts, backups, IPTV: the TV settings open them) with the phone's
/// settings rows and choices in their TV look ([TvSettingsStyle]); they
/// work with the remote through Flutter's directional focus.
GoRouter buildTvRouter({
  String initialLocation = RoutePath.kInitial,
  List<NavigatorObserver> observers = const [],
  GlobalKey<NavigatorState>? navigatorKey,
}) => GoRouter(
  navigatorKey: navigatorKey,
  initialLocation: initialLocation,
  observers: [liveRouteObserver, ...observers],
  routes: [
    GoRoute(
      path: RoutePath.kInitial,
      pageBuilder: (context, state) =>
          MaterialPage<Object?>(key: state.pageKey, name: RoutePath.kInitial, child: const TvHomePage()),
    ),
    for (final MapEntry(key: path, value: builder) in {...pageRoutes, ...tvPageRoutes}.entries)
      GoRoute(
        path: path,
        pageBuilder: (context, state) => MaterialPage<Object?>(
          key: state.pageKey,
          name: path,
          arguments: state.extra,
          // The phone's pages in their TV look: settings rows and choices
          // (A17.9 c2, c7).
          child: PureLiveRouteScrollScope(
            child: tvPageRoutes.containsKey(path)
                ? builder(RouteArgs(path, arguments: state.extra))
                : _tvSettingsRoots.contains(path)
                ? TvSettingsScaffold(
                    title: i18n(
                      SettingsSection.values.where((section) => section.route == path).firstOrNull?.titleKey ?? 'about',
                    ),
                    pageKey: ValueKey('tv-settings-root-$path'),
                    contentHasHeader: true,
                    child: builder(RouteArgs(path, arguments: state.extra)),
                  )
                : TvSettingsStyle(child: builder(RouteArgs(path, arguments: state.extra))),
          ),
        ),
      ),
  ],
);
