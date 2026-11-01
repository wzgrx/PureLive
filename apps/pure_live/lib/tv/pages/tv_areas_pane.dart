import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/areas/area_catalog.dart';
import 'package:pure_live/features/areas/areas_common.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/pages/tv_iptv_pane.dart';
import 'package:pure_live/tv/pages/tv_popular_pane.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_area_card.dart';
import 'package:pure_live/tv/widgets/tv_area_dialog.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_grid.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

/// The tab of the followed areas.
/// Areas (pure_live_TV `AreasPage` over v4's area catalogues, M13.5; A17.3
/// c6, c7): one tab per platform, its categories in a secondary row (none
/// for one category) and the areas in a grid. OK opens an area's rooms (an
/// IPTV channel plays, CC's official entries open in the browser, as on the
/// phone); a held OK opens the area dialog. The followed areas are their
/// own destination (`TvFollowedAreasPane`, c9).
class TvAreasPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const new({super.key});

  @override
  ConsumerState<TvAreasPane> createState() => _TvAreasPaneState();
}

class _TvAreasPaneState extends ConsumerState<TvAreasPane> {
  final GlobalKey<TvIptvPaneState> _iptv = GlobalKey();
  final GlobalKey<TvTabBarState> _platformTabs = GlobalKey();
  final GlobalKey<TvTabBarState> _categoryTabs = GlobalKey();
  final Map<String, GlobalKey<TvGridState>> _grids = {};
  final Map<String, AreaCatalog> _catalogs = {};
  String? _current;
  final FocusNode _allPlatforms = FocusNode(debugLabel: 'tv areas all platforms');

  GlobalKey<TvGridState> _grid(String key) => _grids[key] ??= GlobalKey();

  AreaCatalog _catalog(String platform) => _catalogs[platform] ??= AreaCatalog(
    ref.read(sitesProvider).of(platform),
    pictures: ref.read(areaPicturesProvider),
  );

  @override
  void dispose() {
    for (final catalog in _catalogs.values) {
      catalog.dispose();
    }
    _allPlatforms.dispose();
    super.dispose();
  }

  void _select(String tab) {
    setState(() => _current = tab);
    if (tab != SiteIds.iptv) unawaited(_catalog(tab).ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.read(sitesProvider);
    final platforms = sites.availableIds(watchSetting(ref, Settings.hotAreasList));
    final tabs = platforms;
    if (tabs.isEmpty) return TvStatusView(icon: TvIcons.noPlatforms, title: i18n('popular_no_platforms'));
    var current = _current;
    if (current == null || !tabs.contains(current)) {
      final preferred = ref.read(storeProvider).settings.get(Settings.preferPlatform);
      current = _current = platforms.contains(preferred) ? preferred : platforms.first;
      final first = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && first != SiteIds.iptv) unawaited(_catalog(first).ensureLoaded());
      });
    }
    final tab = current;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    bool enterContent() {
      if (tab == SiteIds.iptv) return _iptv.currentState?.enter() ?? false;
      final catalog = _catalog(tab);
      if (catalog.categories.length > 1) return _categoryTabs.currentState?.focusSelected() ?? false;
      final categories = catalog.categories;
      if (categories.isEmpty) return false;
      return _grid('$tab/${categories[catalog.selected].id}').currentState?.enter() ?? false;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TvTabBar(
                key: _platformTabs,
                tabs: [
                  for (final id in tabs)
                    TvTab(
                      id: id,
                      label: platformName(id, fallback: sites.of(id).name),
                      logo: id,
                    ),
                ],
                selected: tabs.indexOf(tab),
                onSelect: (index) => _select(tabs[index]),
                onRefresh: () {
                  if (tab == SiteIds.iptv) {
                    _iptv.currentState?.refresh();
                  } else {
                    unawaited(_catalog(tab).refresh());
                  }
                },
                onLeft: rtl
                    ? () {
                        _allPlatforms.requestFocus();
                        return true;
                      }
                    : null,
                onRight: !rtl
                    ? () {
                        _allPlatforms.requestFocus();
                        return true;
                      }
                    : null,
                onDown: enterContent,
              ),
            ),
            TvButton(
              key: const ValueKey('tv-areas-all-platforms'),
              focusNode: _allPlatforms,
              onKey: (_, event) {
                if (event is KeyUpEvent) return KeyEventResult.ignored;
                if (event.logicalKey == (rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft)) {
                  _platformTabs.currentState?.focusRemembered();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                    event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.arrowDown && enterContent()) return KeyEventResult.handled;
                return KeyEventResult.ignored;
              },
              label: i18n('tv_all_platforms'),
              small: true,
              onTap: () async {
                final picked = await showTvPlatformPicker(
                  context,
                  ids: tabs,
                  current: tab,
                  labelFor: (id) => platformName(id, fallback: sites.of(id).name),
                );
                if (mounted && picked != null) _select(picked);
              },
            ),
          ],
        ),
        Expanded(child: tab == SiteIds.iptv ? TvIptvPane(key: _iptv) : _platformAreas(tab)),
      ],
    );
  }

  Widget _platformAreas(String platform) {
    final catalog = _catalog(platform);
    return ListenableBuilder(
      listenable: catalog,
      builder: (context, _) {
        final categories = catalog.categories;
        if (categories.isEmpty) {
          if (!catalog.hasLoaded || catalog.isLoading) return const TvSkeletonGrid(columns: 6);
          if (catalog.error != null) {
            return TvStatusView.failure(catalog.error, onRetry: () => unawaited(catalog.refresh()));
          }
          return TvStatusView(
            icon: TvIcons.noAreas,
            title: i18n('tv_no_areas'),
            actions: [
              TvStatusAction(icon: AppIcons.refresh, label: i18n('retry'), onTap: () => unawaited(catalog.refresh())),
            ],
          );
        }
        final selected = catalog.selected;
        final areas = categories[selected].children;
        final gridKey = _grid('$platform/${categories[selected].id}');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // c6: a secondary row (words underlined), none for one category.
            if (categories.length > 1)
              TvTabBar(
                key: _categoryTabs,
                secondary: true,
                tabs: [
                  for (final (index, category) in categories.indexed)
                    TvTab(id: '$index:${category.id}', label: category.name),
                ],
                selected: selected,
                busy: catalog.isLoading,
                onSelect: catalog.select,
                onRefresh: () => unawaited(catalog.refresh()),
                onUp: () => _platformTabs.currentState?.focusRemembered() ?? false,
                onDown: () => gridKey.currentState?.enter() ?? false,
              ),
            Expanded(
              child: areas.isEmpty
                  ? TvStatusView(icon: TvIcons.noAreas, title: i18n('tv_no_areas'))
                  : TvAreaGrid(
                      key: ValueKey(gridKey),
                      gridKey: gridKey,
                      areas: areas,
                      onLeaveUp: () {
                        if (_categoryTabs.currentState?.focusSelected() ?? false) return;
                        _platformTabs.currentState?.focusSelected();
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Areas in a [TvGrid] (U.15a c6 `TvAreaCard`): six columns (fewer as the
/// text grows), the picture over the name, a heart on the followed ones; a
/// held OK opens the area dialog (A17.3 c7).
class TvAreaGrid extends ConsumerWidget {
  /// Creates the grid.
  const new({required this.gridKey, required this.areas, this.showPlatform = false, this.onLeaveUp, super.key});

  /// The grid's key.
  final GlobalKey<TvGridState> gridKey;

  /// The areas.
  final List<LiveArea> areas;

  /// Areas of several platforms: the platform and category under each.
  final bool showPlatform;

  /// Up on the first row.
  final VoidCallback? onLeaveUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = TvScale.of(context);
    final pictures = ref.watch(areaPicturesProvider);
    final followed = ref.watch(followedAreaKeysProvider).value ?? const <String>{};
    final columns = tvRoomColumns(watchSetting(ref, Settings.textScaleFactor), base: 6);
    return TvGrid(
      key: gridKey,
      itemCount: areas.length,
      columns: columns,
      aspectRatio: showPlatform ? 0.7 : 0.78,
      crossSpacing: scale.px(16),
      mainSpacing: scale.px(16),
      onLeaveUp: onLeaveUp,
      itemBuilder: (context, index, node, onKey) {
        final area = areas[index];
        final picture = pictures.pictureFor(area);
        return TvAreaCard(
          key: ValueKey('tv-area-$index'),
          focusNode: node,
          onKey: onKey,
          name: areaDisplayName(area),
          picture: picture.isEmpty ? null : picture,
          subtitle: showPlatform ? areaPlatformAndCategory(area) : null,
          followed: followed.contains(area.identityKey),
          onTap: () => openArea(ref, area),
          // c7 by the cross-task rule: the unified card dialog.
          onLongPress: () => unawaited(showTvAreaDialog(context, ref, area)),
        );
      },
    );
  }
}
