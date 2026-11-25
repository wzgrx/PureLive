import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/startup.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/menu_button.dart';
import 'package:pure_live/features/popular/popular_catalog.dart';
import 'package:pure_live/features/popular/popular_grid.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/paging.dart';
import 'package:pure_live/shared/rooms/platform_picker.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

export 'package:pure_live/shared/rooms/platform_picker.dart';

/// Popular rooms (3.x `lib/modules/popular`): one tab per platform of the
/// "platform display" setting, each with its recommended rooms.
///
/// Routes: `RoutePath.kPopular`; also the home tab.
///
/// Kept from 3.x (docs/A-界面设计/A09-浏览界面/A09.2-热门 c1): the platform tabs sit where the
/// title would be, the first tab is the preferred platform, a changed
/// platform list keeps the platform shown, a tab loads once it settles
/// (80 ms) and the next platform is fetched 700 ms later, a changed
/// audience setting refreshes the platform shown, and a return after 15 s
/// in the background refreshes it. New: the ⌄ at the end of the tabs opens
/// "all platforms" (c2), and an empty platform list says where to choose
/// them (c3). See docs/I-浏览和发现/I02-热门/I02.1-推荐首页/record.md for earlier changes.
class PopularPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<PopularPage> createState() => _PopularPageState();
}

class _PopularPageState extends ConsumerState<PopularPage> with TickerProviderStateMixin {
  late final PopularCatalog _catalog = ref.read(popularCatalogProvider);
  TabController? _tabs;
  List<String> _ids = const [];
  Timer? _settleTimer;
  Timer? _warmTimer;
  bool _firstContentWatched = false;

  @override
  void initState() {
    super.initState();
    HomeSignals.resumedAfterBackground.addListener(_resumed);
    _catalog.onRankingChanged = _refreshCurrent;
  }

  @override
  void dispose() {
    HomeSignals.resumedAfterBackground.removeListener(_resumed);
    if (_catalog.onRankingChanged == _refreshCurrent) _catalog.onRankingChanged = null;
    _settleTimer?.cancel();
    _warmTimer?.cancel();
    _tabs?.dispose();
    super.dispose();
  }

  String? get _current {
    final tabs = _tabs;
    if (tabs == null || _ids.isEmpty) return null;
    return _ids[tabs.index.clamp(0, _ids.length - 1)];
  }

  int get _firstCount {
    final width = MediaQuery.sizeOf(context).width;
    if (!usesDesktopPages(width)) return phonePageSize;
    final picked = _catalog.pageSize;
    if (picked != null && picked > 0) return picked;
    return pageSizesOf(ref.read(storeProvider).settings, width).size;
  }

  void _resumed() {
    final signal = HomeSignals.resumedAfterBackground.value;
    if (widget.route.inHome && signal != null && signal.$1 == HomeMenu.popular) _refreshCurrent();
  }

  void _refreshCurrent() {
    final current = _current;
    if (!mounted || current == null) return;
    unawaited(_catalog.feedOf(current).refresh(count: _firstCount));
  }

  /// Rebuilds the tabs when the platform list changes, keeping the platform
  /// shown (3.x `_initTabController`).
  void _syncTabs(List<String> ids) {
    if (listEquals(ids, _ids) && _tabs != null) return;
    final old = _tabs;
    final oldPlatform = _catalog.currentPlatform ?? _current;
    _ids = ids;
    if (ids.isEmpty) {
      _tabs = null;
      if (_watchFirstContent()) unawaited(_firstContentShown(null));
    } else {
      var index = oldPlatform == null ? -1 : ids.indexOf(oldPlatform);
      if (index < 0 && old == null) {
        index = ids.indexOf(ref.read(storeProvider).settings.get(Settings.preferPlatform));
      }
      if (index < 0) index = old == null ? 0 : old.index.clamp(0, ids.length - 1);
      final tabs = TabController(
        length: ids.length,
        vsync: this,
        initialIndex: index,
        animationDuration: pureLiveTabTransitionDuration,
      )..addListener(_tabChanged);
      _tabs = tabs;
      _catalog.currentPlatform = ids[index];
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(index));
    }
    if (old != null) {
      old.removeListener(_tabChanged);
      // The old bar lets go of it in this frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  void _tabChanged() {
    final tabs = _tabs;
    if (tabs == null || tabs.indexIsChanging) return;
    final settled = ((tabs.animation?.value ?? tabs.index.toDouble()) - tabs.index).abs() < 0.001;
    if (!settled) return;
    final platform = _ids[tabs.index];
    if (_catalog.currentPlatform == platform) return;
    _catalog.currentPlatform = platform;
    _settleTimer?.cancel();
    _warmTimer?.cancel();
    final index = tabs.index;
    _settleTimer = Timer(const Duration(milliseconds: 80), () => _load(index));
  }

  Future<void> _load(int index) async {
    if (!mounted || index >= _ids.length || _tabs?.index != index) return;
    final count = _firstCount;
    final feed = _catalog.feedOf(_ids[index]);
    if (_watchFirstContent()) unawaited(_firstContentShown(feed));
    await feed.open(count: count);
    if (!mounted || _tabs?.index != index || feed.rooms.isEmpty || _ids.length < 2) return;
    // Fetch the next platform while the user looks at this one (3.x).
    _warmTimer?.cancel();
    _warmTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || _tabs?.index != index) return;
      final next = index + 1 < _ids.length ? index + 1 : index - 1;
      unawaited(_catalog.feedOf(_ids[next]).open(count: count));
    });
  }

  /// Whether this page, as home's tab, still has to report its first
  /// content (R04.1, once per page).
  bool _watchFirstContent() {
    if (_firstContentWatched || !widget.route.inHome || StartupTiming.current == null) return false;
    return _firstContentWatched = true;
  }

  /// R04.1: tells [StartupTiming] when the first platform's first rooms (or
  /// its empty or error state; without platforms the empty page) are drawn.
  Future<void> _firstContentShown(RoomFeed? feed) async {
    final timing = StartupTiming.current;
    if (timing == null) return;
    final content = feed == null ? 'empty' : await popularFirstContent(feed);
    await WidgetsBinding.instance.endOfFrame;
    await timing.firstContent(tab: HomeMenu.popular.id, content: content);
  }

  Future<void> _pickPlatform() async {
    final tabs = _tabs;
    if (tabs == null) return;
    final screen = MediaQuery.sizeOf(context);
    final side = screen.width >= 600;
    // A09.12 c3: a long list opens at the design's height (half the screen
    // and a bit) and drags up to the full height; a short one fits itself.
    final tall =
        !side &&
        PlatformPicker.heightOf(_ids.length, width: screen.width, textScaler: MediaQuery.textScalerOf(context)) >
            screen.height * platformPickerOpenHeight;
    final picked = await showAdaptivePanel<int>(
      context,
      side: side,
      openHeight: tall ? platformPickerOpenHeight : null,
      builder: (context) => PlatformPicker(ids: _ids, current: tabs.index),
    );
    if (picked != null && mounted && _tabs == tabs) tabs.animateTo(picked);
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.read(sitesProvider);
    final ids = sites.availableIds(watchSetting(ref, Settings.hotAreasList));
    _syncTabs(ids);
    final phoneTab = showsHomeBarButtons(context, inHome: widget.route.inHome);
    final tabs = _tabs;
    return Scaffold(
      appBar: hidesHomeBar(context, inHome: widget.route.inHome)
          ? null
          : AppBar(
              centerTitle: centredPageTitle,
              automaticallyImplyLeading: !widget.route.inHome,
              leading: phoneTab ? const MenuButton() : null,
              actions: phoneTab ? const [CommonAppBarActions()] : null,
              titleSpacing: phoneTab ? 4 : 16,
              // The platform tabs take the title's place (3.x).
              title: tabs == null
                  ? null
                  : Row(
                      children: [
                        Expanded(
                          child: ScrollableTabBar(
                            key: const ValueKey('popular-platform-tabs'),
                            controller: tabs,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            dividerHeight: 0,
                            physics: const PureLiveBoundedScrollPhysics(),
                            // A09.12 c1: the tab cut by ⌄ fades.
                            endFade: tabStripEndFade,
                            tabs: [
                              for (final id in ids)
                                TabLabel(
                                  leading: PlatformLogo(id, size: 20),
                                  label: platformName(id, fallback: sites.of(id).name),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('popular-all-platforms'),
                          tooltip: i18n('popular_all_platforms'),
                          icon: const Icon(AppIcons.dropDown, size: 22),
                          onPressed: _pickPlatform,
                        ),
                      ],
                    ),
            ),
      body: tabs == null
          ? AppStatusView(
              type: AppStatusType.empty,
              icon: AppIcons.coverPlaceholder,
              title: i18n('popular_no_platforms'),
              subtitle: i18n('popular_no_platforms_hint'),
              buttonText: i18n('platform_display'),
              buttonIcon: AppIcons.platformSettings,
              onButtonPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsHotAreas)),
            )
          : TabBarView(
              controller: tabs,
              physics: const PureLivePageScrollPhysics(),
              children: [for (final id in ids) PopularPlatformView(key: ValueKey('popular-$id'), platform: id)],
            ),
    );
  }
}

/// What [feed] first shows (R04.1): `rooms` once it has any to show, `error`
/// when its first load failed, `empty` when the platform answered without
/// any; null while the first answer is coming.
String? popularContentOf(RoomFeed feed) {
  if (feed.rooms.isNotEmpty) return 'rooms';
  if (feed.error != null) return 'error';
  if (feed.loaded && !feed.busy) return 'empty';
  return null;
}

/// Waits until [feed] shows its first content ([popularContentOf]): the
/// first chunk's rooms show before the rest of the page arrives.
Future<String> popularFirstContent(RoomFeed feed) async {
  if (popularContentOf(feed) case final content?) return content;
  final shown = Completer<String>();
  void changed() {
    if (popularContentOf(feed) case final content? when !shown.isCompleted) shown.complete(content);
  }

  feed.addListener(changed);
  try {
    return await shown.future;
  } finally {
    feed.removeListener(changed);
  }
}
