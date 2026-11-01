import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_nav_item.dart';
import 'package:pure_live/tv/widgets/tv_room_grid.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';

/// One playlist of the IPTV pane: its name and its channels as rooms.
typedef TvPlaylist = ({String id, String name, List<LiveRoom> channels});

/// A channel (an IPTV area) as the room the TV room opens (the IPTV site
/// reads the channel by this id, like the phone's `openArea`).
LiveRoom tvChannelRoom(LiveArea channel) => LiveRoom(
  platform: SiteIds.iptv,
  roomId: channel.areaId,
  title: channel.areaName,
  nick: channel.typeName,
  cover: channel.areaPic,
  liveStatus: LiveStatus.live,
);

/// Loads the playlists of [site]: the built-in hot list first (none once it
/// was deleted, V02.9), then the imported ones with their channels (the
/// IPTV site's hot list and categories, M6; a site that is not the IPTV
/// site's class gives its recommendations). The hot list needs the network
/// on first use; without it the imported lists still show.
Future<List<TvPlaylist>> loadTvPlaylists(LiveSite site) async {
  var hot = const <LiveRoom>[];
  try {
    hot = site is IptvSite ? await site.hotRooms() : await site.getRecommendRooms(pageSize: 0);
  } on Object {
    // Offline or the built-in list moved: imported lists only.
  }
  final categories = await site.getCategories(1, 0);
  return [
    if (hot.isNotEmpty) (id: 'hot', name: i18n('iptv_hot_playlist'), channels: hot),
    for (final category in categories)
      (id: category.id, name: category.name, channels: [for (final area in category.children) tvChannelRoom(area)]),
  ];
}

/// IPTV on the TV (pure_live_TV `modules/live/iptv`, over v4's IPTV site):
/// the playlists on the left, the chosen one's channels numbered on the
/// right. A channel plays in the TV room with its playlist as the channel
/// list, so Up and Down zap through the playlist. Importing and managing
/// playlists and guides stays on the IPTV page ("manage").
class TvIptvPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const new({super.key});

  @override
  ConsumerState<TvIptvPane> createState() => TvIptvPaneState();
}

/// The IPTV pane state, allowing its parent tabs to refresh and enter the grid.
class TvIptvPaneState extends ConsumerState<TvIptvPane> {
  final Map<String, GlobalKey<TvRoomGridState>> _grids = {};
  final Map<String, FocusNode> _listNodes = {};
  final FocusNode _manage = FocusNode(debugLabel: 'iptv manage');
  Future<List<TvPlaylist>>? _playlists;
  String? _current;
  String? _shown;

  /// Reloads the playlists while preserving the selected list when present.
  void refresh() => setState(_load);

  /// Moves from the platform tabs to the current channel grid.
  bool enter() => _grids[_shown]?.currentState?.enter() ?? false;

  GlobalKey<TvRoomGridState> _grid(String id) => _grids[id] ??= GlobalKey();

  FocusNode _listNode(String id) => _listNodes[id] ??= FocusNode(debugLabel: 'playlist $id');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _manage.dispose();
    for (final node in _listNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _load() {
    final site = ref.read(sitesProvider).maybeOf(SiteIds.iptv);
    _playlists = site == null ? null : loadTvPlaylists(site);
  }

  @override
  Widget build(BuildContext context) {
    final playlists = _playlists;
    if (playlists == null) return TvStatusView(icon: TvIcons.menuIptv, title: i18n('tv_iptv_unavailable'));
    return FutureBuilder<List<TvPlaylist>>(
      future: playlists,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TvStatusView.failure(snapshot.error, onRetry: () => setState(_load));
        }
        final lists = snapshot.data;
        if (lists == null) return const TvSkeletonGrid();
        if (lists.isEmpty) {
          return TvStatusView(
            icon: TvIcons.noPlaylists,
            title: i18n('tv_iptv_empty'),
            actions: [
              TvStatusAction(
                icon: TvIcons.manage,
                label: i18n('iptv_manage'),
                onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kIptv)),
              ),
            ],
          );
        }
        final current = lists.firstWhere((list) => list.id == _current, orElse: () => lists.first);
        _shown = current.id;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: TvScale.of(context).pxText(150), child: _playlistColumn(lists, current)),
            Expanded(
              child: current.channels.isEmpty
                  ? TvStatusView(icon: TvIcons.menuIptv, title: i18n('tv_no_rooms'))
                  : TvRoomGrid(
                      key: _grid(current.id),
                      rooms: current.channels,
                      numbered: true,
                      onLeaveLeft: () => _listNode(current.id).requestFocus(),
                    ),
            ),
          ],
        );
      },
    );
  }

  KeyEventResult _playlistKey(String? id, KeyEvent event, List<TvPlaylist> lists, TvPlaylist current) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final entries = [...lists.map((list) => list.id), null];
    final index = entries.indexOf(id);
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      final next = index + (key == LogicalKeyboardKey.arrowUp ? -1 : 1);
      if (next >= 0 && next < entries.length) {
        final target = (entries[next] == null ? _manage : _listNode(entries[next]!))..requestFocus();
        if (target.context case final context?) Scrollable.ensureVisible(context);
      }
      return KeyEventResult.handled;
    }
    if (key != LogicalKeyboardKey.arrowRight) return KeyEventResult.ignored;
    final selected = id ?? current.id;
    if (selected == current.id) {
      _grid(selected).currentState?.enter();
    } else {
      final origin = _listNode(selected);
      setState(() => _current = selected);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _shown == selected && origin.hasFocus) _grid(selected).currentState?.enter();
      });
    }
    return KeyEventResult.handled;
  }

  Widget _playlistColumn(List<TvPlaylist> lists, TvPlaylist current) {
    final scale = TvScale.of(context);
    return ListView(
      padding: EdgeInsets.all(scale.px(12)),
      children: [
        for (final list in lists)
          Padding(
            padding: EdgeInsets.only(bottom: scale.px(6)),
            child: TvNavItem(
              key: ValueKey('tv-playlist-${list.id}'),
              focusNode: _listNode(list.id),
              label: list.name,
              subtitle: i18n('iptv_channel_count', args: {'count': '${list.channels.length}'}),
              selected: list.id == current.id,
              onTap: () => setState(() => _current = list.id),
              onKey: (node, event) => _playlistKey(list.id, event, lists, current),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: scale.px(6)),
          child: TvButton(
            key: const ValueKey('tv-iptv-manage'),
            focusNode: _manage,
            onKey: (_, event) => _playlistKey(null, event, lists, current),
            icon: TvIcons.manage,
            label: i18n('iptv_manage'),
            small: true,
            expand: true,
            onTap: () async {
              await AppNavigator.toNamed<void>(RoutePath.kIptv);
              if (mounted) setState(_load);
            },
          ),
        ),
      ],
    );
  }
}
