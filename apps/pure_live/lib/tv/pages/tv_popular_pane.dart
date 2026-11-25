import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/popular/popular_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_room_grid.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

/// How many rooms a TV page asks for at a time (pure_live_TV pages 12 at a
/// time; a 1080p grid shows about twelve, so two screens).
const int tvPageSize = 24;

/// Shows [feed]'s rooms in a [TvRoomGrid], with the states of
/// docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件 c14: a static skeleton on the first load, the
/// cause of a failure in words (and "前往登录" when the platform wants a
/// login), an empty list saying what to do with the remote; the grid asks
/// for the next [tvPageSize] rooms near its end.
class TvFeedGrid extends StatelessWidget {
  /// Creates the view of [feed].
  const new({
    required this.feed,
    required this.gridKey,
    this.onLeaveUp,
    this.emptyHint = 'tv_empty_platform',
    this.columns = 4,
    super.key,
  });

  /// The rooms.
  final RoomFeed feed;

  /// The grid's key (the page puts the focus in it).
  final GlobalKey<TvRoomGridState> gridKey;

  /// Up on the first row.
  final VoidCallback? onLeaveUp;

  /// The key of what an empty list says to do with the remote.
  final String emptyHint;

  /// The columns of the first load's skeleton.
  final int columns;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: feed,
    builder: (context, _) {
      final rooms = feed.rooms;
      if (rooms.isEmpty) {
        if (!feed.loaded || feed.busy) return TvSkeletonGrid(columns: columns);
        if (feed.error != null) {
          return TvStatusView.failure(feed.error, onRetry: () => unawaited(feed.retry(count: tvPageSize)));
        }
        return TvStatusView(
          icon: TvIcons.noRooms,
          title: i18n('empty_live_title'),
          subtitle: i18n(emptyHint),
          actions: [
            TvStatusAction(
              icon: AppIcons.refresh,
              label: i18n('tv_refresh'),
              onTap: () => unawaited(feed.refresh(count: tvPageSize)),
            ),
          ],
        );
      }
      return TvRoomGrid(
        key: gridKey,
        rooms: rooms,
        onLeaveUp: onLeaveUp,
        onEndReached: () {
          if (feed.hasMore && !feed.busy) unawaited(feed.ensure(rooms.length + tvPageSize));
        },
      );
    },
  );
}

/// Recommended rooms (pure_live_TV `HotPage`, v4's popular catalogue): one
/// tab per platform of the platform list, the feeds shared with the phone
/// page (`popularCatalogProvider`, M12.2), so the ranking, the hidden
/// unplayable rooms and the per-platform paging are the same.
class TvPopularPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const new({super.key});

  /// The id of the last tab, "全部平台" (opens the panel of every platform).
  static const String allPlatforms = '__all';

  @override
  ConsumerState<TvPopularPane> createState() => _TvPopularPaneState();
}

class _TvPopularPaneState extends ConsumerState<TvPopularPane> {
  late final PopularCatalog _catalog = ref.read(popularCatalogProvider);
  final GlobalKey<TvTabBarState> _tabs = GlobalKey();
  final Map<String, GlobalKey<TvRoomGridState>> _grids = {};
  String? _current;

  GlobalKey<TvRoomGridState> _grid(String platform) => _grids[platform] ??= GlobalKey();

  @override
  void initState() {
    super.initState();
    HomeSignals.resumedAfterBackground.addListener(_resumed);
  }

  @override
  void dispose() {
    HomeSignals.resumedAfterBackground.removeListener(_resumed);
    super.dispose();
  }

  void _resumed() {
    final signal = HomeSignals.resumedAfterBackground.value;
    final current = _current;
    if (signal != null && signal.$1 == HomeMenu.popular && current != null) {
      unawaited(_catalog.feedOf(current).refresh(count: tvPageSize));
    }
  }

  /// The panel of every platform (A17.3 c5, the phone's A09.2 panel in the
  /// TV's look): three to a row, OK switches at once; "平台显示" at the top
  /// right edits the list.
  Future<void> _platformPanel(List<String> ids) async {
    final sites = ref.read(sitesProvider);
    final picked = await showTvPlatformPicker(
      context,
      ids: ids,
      current: _current,
      labelFor: (id) => platformName(id, fallback: sites.of(id).name),
    );
    if (picked != null && mounted) _select(picked);
  }

  void _select(String platform) {
    setState(() => _current = platform);
    _catalog.currentPlatform = platform;
    unawaited(_catalog.feedOf(platform).open(count: tvPageSize));
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.read(sitesProvider);
    final ids = sites.availableIds(watchSetting(ref, Settings.hotAreasList));
    if (ids.isEmpty) return TvStatusView(icon: TvIcons.noPlatforms, title: i18n('tv_no_platforms'));
    var current = _current;
    if (current == null || !ids.contains(current)) {
      final preferred = _catalog.currentPlatform ?? ref.read(storeProvider).settings.get(Settings.preferPlatform);
      current = _current = ids.contains(preferred) ? preferred : ids.first;
      _catalog.currentPlatform = current;
      final first = current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_catalog.feedOf(first).open(count: tvPageSize));
      });
    }
    final feed = _catalog.feedOf(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: feed,
          builder: (context, _) => TvTabBar(
            key: _tabs,
            tabs: [
              for (final id in ids)
                TvTab(
                  id: id,
                  label: platformName(id, fallback: sites.of(id).name),
                  logo: id,
                ),
              // c5: "全部平台" at the end opens the panel of every platform.
              TvTab(id: TvPopularPane.allPlatforms, label: i18n('tv_all_platforms'), icon: TvIcons.allPlatforms),
            ],
            selected: ids.indexOf(current!),
            busy: feed.busy,
            onSelect: (index) {
              if (index < ids.length) {
                _select(ids[index]);
              } else {
                unawaited(_platformPanel(ids));
              }
            },
            onRefresh: () => unawaited(feed.refresh(count: tvPageSize)),
            onDown: () => _grid(current!).currentState?.enter() ?? false,
          ),
        ),
        Expanded(
          child: TvFeedGrid(
            key: ValueKey('tv-popular-$current'),
            feed: feed,
            gridKey: _grid(current),
            onLeaveUp: () => _tabs.currentState?.focusSelected(),
          ),
        ),
      ],
    );
  }
}

/// The picker starts at the first visible platform, independently of the
/// selected fill. Its scroll offset belongs to this opening of the dialog.
class _TvPlatformGrid extends StatefulWidget {
  const new({required this.ids, required this.current, required this.labelFor, required this.onPick});

  final List<String> ids;
  final String? current;
  final String Function(String id) labelFor;
  final ValueChanged<String> onPick;

  @override
  State<_TvPlatformGrid> createState() => _TvPlatformGridState();
}

class _TvPlatformGridState extends State<_TvPlatformGrid> {
  final ScrollController _scroll = ScrollController(keepScrollOffset: false);
  BuildContext? _focused;

  void _focusChanged(BuildContext target, bool focused) {
    if (!focused) {
      if (_focused == target) _focused = null;
      return;
    }
    _focused = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !target.mounted || _focused != target || !_scroll.hasClients) return;
      final object = target.findRenderObject();
      if (object == null || !object.attached) return;
      // Directional traversal reveals layout bounds, not the zoom and ring.
      // Centre the button in this viewport only, with edge paint space below.
      _scroll.position.ensureVisible(object, alignment: 0.5);
    });
  }

  @override
  void dispose() {
    _focused = null;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = scale.px(12);
        final ring = scale.px(tvFocusRingWidth) * tvFocusZoom;
        // Use the widest possible cell as a conservative bound; the final
        // button is narrower after padding and gaps. Reserve space even when
        // zoom is disabled so toggling the setting does not move the grid.
        final horizontal = math.max(scale.px(6), constraints.maxWidth / 3 * (tvFocusZoom - 1) / 2 + ring);
        final height = scale.px(40) * math.max(1.0, scale.textScale);
        final vertical = math.max(scale.px(6), height * (tvFocusZoom - 1) / 2 + ring);
        final width = (constraints.maxWidth - horizontal * 2 - gap * 2) / 3;
        return SingleChildScrollView(
          key: const ValueKey('tv-platform-panel-scroll'),
          controller: _scroll,
          padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final (index, id) in widget.ids.indexed)
                SizedBox(
                  width: width,
                  child: Builder(
                    builder: (context) => TvButton(
                      key: ValueKey('tv-platform-panel-$id'),
                      autofocus: index == 0,
                      expand: true,
                      selected: id == widget.current,
                      label: widget.labelFor(id),
                      leading: PlatformLogo(id, size: scale.pxText(20)),
                      onFocusChange: (focused) => _focusChanged(context, focused),
                      onTap: () => widget.onPick(id),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The shared platform chooser for TV popular and area pages.
Future<String?> showTvPlatformPicker(
  BuildContext context, {
  required List<String> ids,
  required String? current,
  required String Function(String) labelFor,
}) => showTvDialog<String>(
  context,
  builder: (context) {
    return TvDialog(
      key: const ValueKey('tv-platform-panel'),
      title: i18n('tv_all_platforms'),
      width: 1200,
      actions: [
        TvButton(
          key: const ValueKey('tv-platform-panel-display'),
          label: i18n('platform_display'),
          onTap: () {
            Navigator.pop(context);
            unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsHotAreas));
          },
        ),
        TvButton(label: i18n('close'), onTap: () => Navigator.pop(context)),
      ],
      child: _TvPlatformGrid(
        ids: ids,
        current: current,
        labelFor: labelFor,
        onPick: (id) => Navigator.pop(context, id),
      ),
    );
  },
);
