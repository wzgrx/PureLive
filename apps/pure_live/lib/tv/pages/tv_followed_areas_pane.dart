import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/areas/areas_common.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/pages/tv_areas_pane.dart';
import 'package:pure_live/tv/widgets/tv_grid.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

/// "关注的分区" (A17.3 c9, its own destination): "全部" and the platforms
/// that have followed areas, with their counts; in "全部" each card says its
/// platform and category. Empty, the phone's words and the remote's way.
class TvFollowedAreasPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const new({super.key});

  @override
  ConsumerState<TvFollowedAreasPane> createState() => _TvFollowedAreasPaneState();
}

class _TvFollowedAreasPaneState extends ConsumerState<TvFollowedAreasPane> {
  static const String _all = '';
  final GlobalKey<TvTabBarState> _tabs = GlobalKey();
  final Map<String, GlobalKey<TvGridState>> _grids = {};
  String _platform = _all;

  GlobalKey<TvGridState> _grid(String id) => _grids[id] ??= GlobalKey();

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(followedAreasProvider).value;
    if (areas == null) return const TvSkeletonGrid(columns: 6);
    if (areas.isEmpty) {
      return TvStatusView(
        icon: TvIcons.followArea,
        title: i18n('empty_areas_title'),
        subtitle: i18n('tv_no_followed_areas'),
      );
    }
    final counts = <String, int>{};
    for (final area in areas) {
      counts[area.platform] = (counts[area.platform] ?? 0) + 1;
    }
    final platforms = counts.keys.toList();
    if (_platform != _all && !counts.containsKey(_platform)) _platform = _all;
    final shown = <LiveArea>[
      for (final area in areas)
        if (_platform == _all || area.platform == _platform) area,
    ];
    final tabs = [_all, ...platforms];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TvTabBar(
          key: _tabs,
          tabs: [
            for (final id in tabs)
              if (id == _all)
                TvTab(id: 'all', label: i18n('tv_all_platforms'), icon: TvIcons.allPlatforms, badge: areas.length)
              else
                TvTab(id: id, label: platformName(id), logo: id, badge: counts[id]),
          ],
          selected: tabs.indexOf(_platform),
          onSelect: (index) => setState(() => _platform = tabs[index]),
          onDown: () => _grid(_platform).currentState?.enter() ?? false,
        ),
        Expanded(
          child: TvAreaGrid(
            key: ValueKey('tv-followed-areas-$_platform'),
            gridKey: _grid(_platform),
            areas: shown,
            showPlatform: _platform == _all,
            onLeaveUp: () => _tabs.currentState?.focusSelected(),
          ),
        ),
      ],
    );
  }
}
