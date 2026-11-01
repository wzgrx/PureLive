import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/favorite/favorite_controller.dart';
import 'package:pure_live/features/favorite/favorite_rules.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/home/tv_home_page.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focus_region.dart';
import 'package:pure_live/tv/widgets/tv_room_grid.dart';
import 'package:pure_live/tv/widgets/tv_room_row.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

/// Follows (pure_live_TV `FavoritePage` over v4's follows; A17.3 c2–c4):
/// one line of the states "已开播 / 录播 / 未开播" and, after a bar, the
/// platforms that have follows, all with their counts; the tags in a line
/// of small pills when there are tags; the follows off air as compact
/// rows, two to a line. OK on the current tab refreshes. The state, the
/// refresh rules and the order are the phone page's
/// (`favoriteControllerProvider`, M13.2).
class TvFavoritesPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const new({super.key});

  @override
  ConsumerState<TvFavoritesPane> createState() => _TvFavoritesPaneState();
}

class _TvFavoritesPaneState extends ConsumerState<TvFavoritesPane> {
  final GlobalKey<TvTabBarState> _groupTabs = GlobalKey();
  final GlobalKey<TvTabBarState> _platformTabs = GlobalKey();
  final GlobalKey<TvTabBarState> _tagTabs = GlobalKey();
  final Map<String, GlobalKey<TvRoomGridState>> _grids = {};
  final Map<String, GlobalKey<TvRoomRowsState>> _rows = {};
  FollowGroup _group = FollowGroup.live;
  String _platform = allPlatforms;
  String _tag = allTags;
  GlobalKey<TvTabBarState>? _lastHeader;
  final FocusNode _bodyFocus = FocusNode(debugLabel: 'tv favorites content');
  TvHomeHost? _host;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = TvHomeScope.maybeOf(context)?.host;
    if (identical(host, _host)) return;
    _host?.setBackHandler(TvPane.favorites, null);
    _host = host;
    host?.setBackHandler(TvPane.favorites, _back);
  }

  @override
  void dispose() {
    _host?.setBackHandler(TvPane.favorites, null);
    _bodyFocus.dispose();
    super.dispose();
  }

  bool _focusHeader() =>
      (_lastHeader?.currentState?.focusRemembered() ?? false) || (_groupTabs.currentState?.focusRemembered() ?? false);

  /// Back leaves the content or tag row first. The header and side menu
  /// keep the home's next levels, including its exit confirmation.
  bool _back() {
    if (!(_host?.isShown(TvPane.favorites) ?? false)) return false;
    if (!_bodyFocus.hasFocus && !(_tagTabs.currentState?.hasFocus ?? false)) return false;
    return _focusHeader();
  }

  GlobalKey<TvRoomGridState> _grid(String key) => _grids[key] ??= GlobalKey();

  GlobalKey<TvRoomRowsState> _rowsKey(String key) => _rows[key] ??= GlobalKey();

  static const List<(FollowGroup, String)> _groups = [
    (FollowGroup.live, 'tv_follow_live'),
    (FollowGroup.replay, 'tv_follow_replay'),
    (FollowGroup.offline, 'tv_follow_offline'),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(favoriteControllerProvider);
    final platformOrder = watchSetting(ref, Settings.hotAreasList);
    final preferReal = watchSetting(ref, Settings.preferRealOnlineCounts);
    final realOnline = watchSetting(ref, Settings.realOnlinePlatforms).toSet();
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final platforms = platformTabs(controller.rooms, platformOrder);
        if (!platforms.contains(_platform)) _platform = allPlatforms;
        final tags = controller.tags;
        if (_tag != allTags && !tags.any((tag) => tag.id == _tag)) _tag = allTags;
        final order = FollowOrder(preferRealOnline: preferReal, realOnlinePlatforms: realOnline, tags: tags);
        final counts = groupCounts(controller.rooms, _platform);
        List<LiveRoom> listOf(String platform) => roomsOf(
          controller.rooms,
          group: _group,
          platform: platform,
          tagId: _tag,
          assignments: controller.assignments,
          order: order,
        );
        final rooms = listOf(_platform);
        final key = '${_group.name}/$_platform/$_tag';
        final gridKey = _grid(key);
        final rowsKey = _rowsKey(key);
        final offline = _group == FollowGroup.offline;
        final rtl = Directionality.of(context) == TextDirection.rtl;
        bool enter() =>
            (offline ? rowsKey.currentState?.enter() ?? false : gridKey.currentState?.enter() ?? false) ||
            tvFocusFirst(_bodyFocus);
        bool enterFrom(GlobalKey<TvTabBarState> header) {
          _lastHeader = header;
          if (_tagTabs.currentState?.focusRemembered() ?? false) return true;
          return enter();
        }

        void leaveUp() {
          if (_tagTabs.currentState?.focusRemembered() ?? false) return;
          _focusHeader();
        }

        void refresh() => unawaited(controller.refreshVisible());
        final Widget body;
        if (!controller.loaded) {
          body = const TvSkeletonGrid();
        } else if (controller.rooms.isEmpty) {
          // c4: the phone's words, the remote's way.
          body = TvStatusView(
            icon: TvIcons.noFollows,
            title: i18n('empty_favorite_title'),
            subtitle: i18n('tv_empty_follows_hint'),
            actions: [
              TvStatusAction(
                icon: TvIcons.menuSearch,
                label: i18n('search_live'),
                onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSearch)),
              ),
            ],
          );
        } else if (rooms.isEmpty) {
          body = TvStatusView(
            icon: TvIcons.noFollows,
            title: i18n('tv_no_rooms'),
            subtitle: i18n('tv_empty_follow_group'),
            actions: [TvStatusAction(icon: AppIcons.refresh, label: i18n('tv_refresh'), onTap: refresh)],
          );
        } else if (offline) {
          body = TvRoomRows(key: rowsKey, rooms: rooms, onLeaveUp: leaveUp);
        } else {
          body = TvRoomGrid(
            key: gridKey,
            rooms: rooms,
            showPlatform: _platform == allPlatforms,
            showFollowed: false,
            onLeaveUp: leaveUp,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  flex: 2,
                  child: TvTabBar(
                    key: _groupTabs,
                    tabs: [
                      for (final (group, label) in _groups)
                        TvTab(id: group.name, label: i18n(label), badge: counts[group]),
                    ],
                    selected: _groups.indexWhere((entry) => entry.$1 == _group),
                    busy: controller.refreshing || controller.verifying,
                    onSelect: (index) => setState(() => _group = _groups[index].$1),
                    onRefresh: refresh,
                    onDown: () => enterFrom(_groupTabs),
                    onLeft: rtl && platforms.length > 2
                        ? () => _platformTabs.currentState?.focusRemembered() ?? false
                        : null,
                    onRight: !rtl && platforms.length > 2
                        ? () => _platformTabs.currentState?.focusRemembered() ?? false
                        : null,
                  ),
                ),
                if (platforms.length > 2) ...[
                  SizedBox(
                    key: const ValueKey('tv-follow-divider'),
                    height: scale.pxText(28),
                    child: VerticalDivider(width: scale.px(16), thickness: scale.px(2), color: palette.divider),
                  ),
                  Expanded(
                    flex: 3,
                    child: TvTabBar(
                      key: _platformTabs,
                      small: true,
                      tabs: [
                        for (final id in platforms)
                          if (id == allPlatforms)
                            TvTab(id: id, label: i18n('tv_all_platforms'), icon: TvIcons.allPlatforms)
                          else
                            TvTab(id: id, label: platformName(id), logo: id, badge: listOf(id).length),
                      ],
                      selected: platforms.indexOf(_platform),
                      onSelect: (index) => setState(() => _platform = platforms[index]),
                      onRefresh: refresh,
                      onDown: () => enterFrom(_platformTabs),
                      onLeft: !rtl ? () => _groupTabs.currentState?.focusRemembered() ?? false : null,
                      onRight: rtl ? () => _groupTabs.currentState?.focusRemembered() ?? false : null,
                    ),
                  ),
                ],
              ],
            ),
            if (tags.isNotEmpty)
              TvTabBar(
                key: _tagTabs,
                small: true,
                tabs: [
                  TvTab(id: allTags, label: i18n('tv_all_tags')),
                  for (final tag in tags) TvTab(id: tag.id, label: tag.name),
                ],
                selected: _tag == allTags ? 0 : tags.indexWhere((tag) => tag.id == _tag) + 1,
                onSelect: (index) => setState(() => _tag = index == 0 ? allTags : tags[index - 1].id),
                onRefresh: refresh,
                onDown: enter,
                onUp: _focusHeader,
              ),
            Expanded(
              child: Focus(
                focusNode: _bodyFocus,
                skipTraversal: true,
                canRequestFocus: false,
                onKeyEvent: (_, event) {
                  if (event is KeyUpEvent) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    leaveUp();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: body,
              ),
            ),
          ],
        );
      },
    );
  }
}
