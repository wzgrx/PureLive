import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/iptv_playlists.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/paging.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';

/// IPTV rooms and playlist selection for a standalone browse destination.
class IptvRoomsView extends ConsumerStatefulWidget {
  /// Creates the playlist view.
  const new({super.key});

  @override
  ConsumerState<IptvRoomsView> createState() => _IptvRoomsViewState();
}

class _IptvRoomsViewState extends ConsumerState<IptvRoomsView> with WidgetsBindingObserver {
  late final RoomFeed _feed;
  final List<StreamSubscription<Object?>> _settings = [];

  @override
  void initState() {
    super.initState();
    _feed = RoomFeed(
      platform: SiteIds.iptv,
      source: popularSourceFor(ref.read(sitesProvider).of(SiteIds.iptv)),
      visible: (room) =>
          ref.read(storeProvider).settings.get(Settings.showUnplayableInDiscover) ||
          !cannotPlayHere(room, signedIn: false),
      precheck: () => MobileDataNotice.precheck(ref.read(networkProbeProvider)),
    );
    for (final key in <Setting<Object>>[Settings.iptvPopularPlaylist, Settings.iptvHotRemoved]) {
      _settings.add(
        ref.read(storeProvider).settings.watch(key).skip(1).listen((_) {
          if (mounted) unawaited(_feed.refresh(count: phonePageSize));
        }),
      );
    }
    _settings.add(
      ref
          .read(storeProvider)
          .settings
          .watch(Settings.showUnplayableInDiscover)
          .skip(1)
          .listen((_) => _feed.visibilityChanged()),
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_feed.refresh(count: phonePageSize));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _settings) {
      unawaited(subscription.cancel());
    }
    _feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const IptvPopularPlaylists(),
      Expanded(
        child: RoomFeedView(
          feed: _feed,
          keyPrefix: 'areas-iptv',
          openOnShow: true,
          empty: (
            icon: AppIcons.emptyPopular,
            title: i18n('empty_live_title'),
            subtitle: ({required desktop}) => i18n(desktop ? 'popular_empty_desktop' : 'popular_empty_phone'),
          ),
          hiddenNote: (count) => i18n('popular_hidden_count', args: {'count': '$count'}),
          onShowHidden: () => ref.read(storeProvider).settings.set(Settings.showUnplayableInDiscover, true).ignore(),
        ),
      ),
    ],
  );
}

/// The playlists of the IPTV tab (V02.9, issue #6; 3.x showed only the
/// built-in hot list here, the imported ones only under 分区): the hot list
/// unless it was deleted, then the imported ones in the IPTV page's order;
/// the one shown ticked ([shownIptvPlaylist]); a tap shows another and is
/// remembered. Hidden with fewer than two playlists.
class IptvPopularPlaylists extends ConsumerWidget {
  /// Creates the row.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(iptvPlaylistsProvider).value;
    final removed = watchSetting(ref, Settings.iptvHotRemoved);
    final wanted = watchSetting(ref, Settings.iptvPopularPlaylist);
    if (playlists == null) return const SizedBox.shrink();
    final options = <(String, String)>[
      if (!removed) (IptvPlaylist.hotId, i18n('iptv_hot_playlist')),
      for (final playlist in [...playlists]..sort(compareIptvPlaylists))
        if (!playlist.isHot) (playlist.id, iptvPlaylistName(playlist)),
    ];
    if (options.length < 2) return const SizedBox.shrink();
    final shown = shownIptvPlaylist(playlists, wanted: wanted, hotRemoved: removed);
    // The one chip of the app (U.1c c13), in the follows' tag row (U.4c c2).
    return SizedBox(
      key: const ValueKey('popular-iptv-playlists'),
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const PureLiveBoundedScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final (id, name) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: AppChip(
                  key: ValueKey('popular-iptv-playlist-$id'),
                  label: name,
                  selected: id == shown,
                  onSelected: id == shown
                      ? () {}
                      : () => ref.read(storeProvider).settings.set(Settings.iptvPopularPlaylist, id).ignore(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
