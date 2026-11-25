import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/tv/home/tv_home_page.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/video/video_pages.dart';
import 'package:pure_live/tv/video/video_source.dart';
import 'package:pure_live/tv/video/video_store.dart';
import 'package:pure_live/tv/video/video_widgets.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

// The video mode's five destinations (A17.6; X4: 搜索、我的、首页、分区、影视)
// and the login gate in front of them.

/// The Bilibili partitions of "分区" (c8: words only), `rid` and the words.
const List<(int, String)> videoAreas = [
  (0, 'tv_video_area_all'),
  (1, 'tv_video_area_animation'),
  (3, 'tv_video_area_music'),
  (129, 'tv_video_area_dance'),
  (4, 'tv_video_area_game'),
  (36, 'tv_video_area_knowledge'),
  (188, 'tv_video_area_tech'),
  (234, 'tv_video_area_sports'),
  (223, 'tv_video_area_car'),
  (160, 'tv_video_area_life'),
  (211, 'tv_video_area_food'),
  (217, 'tv_video_area_animal'),
  (119, 'tv_video_area_kichiku'),
  (155, 'tv_video_area_fashion'),
  (5, 'tv_video_area_entertainment'),
  (181, 'tv_video_area_film'),
];

/// The kinds of "影视" (PGC), in order.
const List<(PgcType, String)> videoCinemaTypes = [
  (PgcType.anime, 'tv_video_cinema_anime'),
  (PgcType.guochuang, 'tv_video_cinema_guochuang'),
  (PgcType.movie, 'tv_video_cinema_movie'),
  (PgcType.tv, 'tv_video_cinema_tv'),
  (PgcType.documentary, 'tv_video_cinema_documentary'),
  (PgcType.variety, 'tv_video_cinema_variety'),
];

/// The card of anything a video list holds.
TvVideoCardData videoCardOf(Object item, VideoStore store) => switch (item) {
  VodArchive() => TvVideoCardData.archive(item, progress: store.progressOf(item.bvid)?.fraction),
  VodDynamic(:final archive) => TvVideoCardData.archive(archive, progress: store.progressOf(archive.bvid)?.fraction),
  VodFavItem(:final archive) => TvVideoCardData.archive(archive, progress: store.progressOf(archive.bvid)?.fraction),
  VodHistoryEntry(:final archive) => TvVideoCardData.archive(
    archive,
    progress: item.finished
        ? 1
        : archive.duration > Duration.zero
        ? item.progress.inMilliseconds / archive.duration.inMilliseconds
        : null,
  ),
  PgcCard() => TvVideoCardData.season(item),
  VodOwner() => TvVideoCardData(title: item.name, cover: item.face),
  VodSearchUser(:final owner) => TvVideoCardData(
    title: owner.name,
    cover: owner.face,
    subtitle: i18n('tv_video_followers', args: {'count': videoCount(item.fans)}),
  ),
  VodFavFolder() => TvVideoCardData(
    title: item.title,
    cover: item.cover,
    subtitle: i18n('tv_video_folder_count', args: {'count': '${item.mediaCount}'}),
  ),
  _ => const TvVideoCardData(title: '', cover: ''),
};

/// Opens anything a video list holds.
Future<void> openVideoThing(BuildContext context, Object item) => switch (item) {
  VodArchive() => openVideoArchive(context, item),
  VodDynamic(:final archive) => openVideoArchive(context, archive),
  VodFavItem(:final archive) => openVideoArchive(context, archive),
  VodHistoryEntry() when item.seasonId > 0 => openVideoSeason(
    context,
    seasonId: item.seasonId,
    epId: item.epId > 0 ? item.epId : null,
  ),
  VodHistoryEntry(:final archive) => openVideoArchive(context, archive),
  PgcCard() => openVideoSeason(context, seasonId: item.seasonId),
  VodOwner() => openVideoSpace(context, item),
  VodSearchUser(:final owner) => openVideoSpace(context, owner),
  VodFavFolder() => openVideoFolder(context, item),
  _ => Future.value(),
};

/// The title of an item's card menu.
String videoTitleOf(Object item) => switch (item) {
  VodArchive(:final title) => title,
  VodDynamic(:final archive) || VodFavItem(:final archive) || VodHistoryEntry(:final archive) => archive.title,
  PgcCard(:final title) => title,
  VodOwner(:final name) => name,
  VodSearchUser(:final owner) => owner.name,
  VodFavFolder(:final title) => title,
  _ => '',
};

/// "登录哔哩哔哩" in front of the video mode (A17.6 acceptance 12, shared with
/// music): the live login (the same cookie) by its QR page; signing in
/// anywhere opens the mode.
class TvVideoGate extends ConsumerWidget {
  /// Guards [child]; [music] words it for the music mode.
  const new({required this.child, this.music = false, super.key});

  /// The destination.
  final Widget child;

  /// In front of the music mode ("登录哔哩哔哩后听音乐").
  final bool music;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(videoSourceProvider);
    return StreamBuilder<void>(
      stream: source.loginChanges,
      builder: (context, _) => source.signedIn
          ? child
          : TvStatusView(
              key: const ValueKey('tv-video-login-gate'),
              icon: TvIcons.needsLogin,
              title: i18n(music ? 'tv_music_login_title' : 'tv_video_login_title'),
              subtitle: i18n(music ? 'tv_music_login_desc' : 'tv_video_login_desc'),
              actions: [
                TvStatusAction(
                  icon: AppIcons.login,
                  label: i18n('tv_video_login_action'),
                  onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kBiliBiliQRLogin)),
                ),
              ],
            ),
    );
  }
}

/// One tab of a video destination: its feed and what its cards do.
@immutable
final class _VideoTab {
  const new(this.id, this.label, this.feed, {this.actions, this.emptyTitle});

  final String id;
  final String label;
  final TvPagedFeed<Object> Function() feed;
  final List<TvVideoAction> Function(BuildContext context, Object item, TvPagedFeed<Object> feed)? actions;
  final String? emptyTitle;
}

/// Tabs over grids (c6: one tab bar); OK on the current tab reloads it;
/// each tab keeps its feed while the destination lives.
class _TabbedVideoPane extends ConsumerStatefulWidget {
  const new({required this.paneKey, required this.tabs, super.key});

  final String paneKey;
  final List<_VideoTab> tabs;

  @override
  ConsumerState<_TabbedVideoPane> createState() => _TabbedVideoPaneState();
}

class _TabbedVideoPaneState extends ConsumerState<_TabbedVideoPane> {
  final GlobalKey<TvTabBarState> _tabBar = GlobalKey();
  final Map<String, GlobalKey<TvVideoGridState<Object>>> _grids = {};
  final Map<String, TvPagedFeed<Object>> _feeds = {};
  int _selected = 0;

  TvPagedFeed<Object> _feed(_VideoTab tab) => _feeds[tab.id] ??= tab.feed();

  GlobalKey<TvVideoGridState<Object>> _grid(String id) => _grids[id] ??= GlobalKey();

  @override
  void dispose() {
    for (final feed in _feeds.values) {
      feed.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    final index = _selected.clamp(0, tabs.length - 1);
    final tab = tabs[index];
    final feed = _feed(tab);
    return Column(
      key: ValueKey(widget.paneKey),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListenableBuilder(
          listenable: feed,
          builder: (context, _) => TvTabBar(
            key: _tabBar,
            tabs: [for (final tab in tabs) TvTab(id: tab.id, label: tab.label)],
            selected: index,
            busy: feed.busy,
            onSelect: (next) => setState(() => _selected = next),
            onRefresh: () => unawaited(feed.refresh()),
            onDown: () => _grid(tab.id).currentState?.enter() ?? false,
          ),
        ),
        Expanded(
          child: TvVideoGrid<Object>(
            key: _grid(tab.id),
            feed: feed,
            cardOf: videoCardOf,
            onOpen: (item, _) => unawaited(openVideoThing(context, item)),
            actionsOf: tab.actions == null ? null : (item) => tab.actions!(context, item, feed),
            menuTitleOf: videoTitleOf,
            onLeaveUp: () => _tabBar.currentState?.focusSelected(),
            emptyTitle: tab.emptyTitle,
          ),
        ),
      ],
    );
  }
}

VideoPageResult<Object> _all(List<Object> items) => (items: items, hasMore: false);

List<TvVideoAction> _archiveMenu(BuildContext context, VideoSource source, Object item) => switch (item) {
  VodArchive() => archiveActions(context, source, item),
  VodDynamic(:final archive) || VodFavItem(:final archive) => archiveActions(context, source, archive),
  _ => const [],
};

/// "首页" (A17.6): dynamics of the followed uploaders, recommended, popular.
class TvVideoHomePane extends ConsumerWidget {
  /// Creates the destination.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(videoSourceProvider);
    String? cursor;
    return _TabbedVideoPane(
      paneKey: 'tv-video-home',
      tabs: [
        _VideoTab('dynamics', i18n('tv_video_dynamics'), () {
          cursor = null;
          return TvPagedFeed((page) async {
            final result = await source.dynamics(page == 1 ? null : cursor);
            cursor = result.cursor;
            return (items: <Object>[...result.items], hasMore: result.hasMore);
          });
        }, actions: (context, item, _) => _archiveMenu(context, source, item)),
        _VideoTab(
          'recommended',
          i18n('tv_video_recommended'),
          () => TvPagedFeed((page) async => (items: <Object>[...await source.recommended(page)], hasMore: true)),
          actions: (context, item, _) => _archiveMenu(context, source, item),
        ),
        _VideoTab('popular', i18n('tv_video_popular'), () {
          return TvPagedFeed((page) async {
            final result = await source.popular(page);
            return (items: <Object>[...result.items], hasMore: result.hasMore);
          });
        }, actions: (context, item, _) => _archiveMenu(context, source, item)),
      ],
    );
  }
}

/// "分区" (A17.6 c8): a partition per tab (words only), its ranking.
class TvVideoAreasPane extends ConsumerWidget {
  /// Creates the destination.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(videoSourceProvider);
    return _TabbedVideoPane(
      paneKey: 'tv-video-areas',
      tabs: [
        for (final (rid, key) in videoAreas)
          _VideoTab(
            'area-$rid',
            i18n(key),
            () => TvPagedFeed((page) async => _all(<Object>[...await source.ranking(rid)])),
            actions: (context, item, _) => _archiveMenu(context, source, item),
          ),
      ],
    );
  }
}

/// "影视" (A17.6 c10): anime, guochuang, films, series, documentaries,
/// variety shows, from the PGC index.
class TvVideoCinemaPane extends ConsumerWidget {
  /// Creates the destination.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(videoSourceProvider);
    return _TabbedVideoPane(
      paneKey: 'tv-video-cinema',
      tabs: [
        for (final (type, key) in videoCinemaTypes)
          _VideoTab('cinema-${type.name}', i18n(key), () {
            return TvPagedFeed((page) async {
              final result = await source.pgcIndex(type, page);
              return (items: <Object>[...result.items], hasMore: result.hasMore);
            });
          }),
      ],
    );
  }
}

/// "我的" (A17.6): followed uploaders, watch later, favourites, history
/// (deleting asks first, c17), followed anime and series (unfollowing asks
/// first).
class TvVideoMinePane extends ConsumerWidget {
  /// Creates the destination.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(videoSourceProvider);
    String? cursor;
    Future<void> unfollowSeason(TvPagedFeed<Object> feed, PgcCard card) async {
      await source.setSeasonFollowing(card.seasonId, follow: false);
      feed.remove(card);
      AppNavigator.toast(i18n('tv_video_season_unfollowed'));
    }

    List<TvVideoAction> seasonMenu(BuildContext context, Object item, TvPagedFeed<Object> feed) => [
      if (item is PgcCard)
        TvVideoAction(
          id: 'unfollow-season',
          icon: TvIcons.delete,
          label: i18n('tv_video_unfollow_season'),
          confirm: (
            i18n('tv_video_unfollow_season'),
            i18n('tv_video_unfollow_season_confirm', args: {'title': item.title}),
          ),
          run: () => unfollowSeason(feed, item),
        ),
    ];

    return _TabbedVideoPane(
      paneKey: 'tv-video-mine',
      tabs: [
        _VideoTab(
          'followings',
          i18n('tv_video_followings'),
          () => TvPagedFeed((page) async {
            final result = await source.followings(page);
            return (items: <Object>[...result.items], hasMore: result.hasMore);
          }),
          actions: (context, item, feed) => [
            if (item is VodOwner)
              TvVideoAction(
                id: 'unfollow',
                icon: TvIcons.delete,
                label: i18n('tv_video_unfollow'),
                confirm: (i18n('tv_video_unfollow'), i18n('tv_video_unfollow_confirm', args: {'name': item.name})),
                run: () async {
                  await source.setFollowing(item.mid, follow: false);
                  feed.remove(item);
                  AppNavigator.toast(i18n('tv_video_unfollowed'));
                },
              ),
          ],
        ),
        _VideoTab(
          'to-view',
          i18n('tv_video_watch_later'),
          () => TvPagedFeed((page) async => _all(<Object>[...await source.toView()])),
          actions: (context, item, feed) => [
            if (item is VodArchive)
              TvVideoAction(
                id: 'remove-to-view',
                icon: TvIcons.delete,
                label: i18n('tv_video_watch_later_remove'),
                run: () async {
                  await source.removeToView(item.aid);
                  feed.remove(item);
                },
              ),
          ],
          emptyTitle: i18n('tv_video_watch_later_empty'),
        ),
        _VideoTab(
          'favorites',
          i18n('tv_video_favorites'),
          () => TvPagedFeed((page) async => _all(<Object>[...await source.favFolders()])),
        ),
        _VideoTab(
          'history',
          i18n('tv_video_history'),
          () {
            cursor = null;
            return TvPagedFeed((page) async {
              final result = await source.history(page == 1 ? null : cursor);
              cursor = result.cursor;
              return (items: <Object>[...result.items], hasMore: result.hasMore);
            });
          },
          actions: (context, item, feed) => [
            if (item is VodHistoryEntry)
              TvVideoAction(
                id: 'delete-history',
                icon: TvIcons.delete,
                label: i18n('tv_video_history_delete'),
                confirm: (
                  i18n('tv_video_history_delete'),
                  i18n('tv_video_history_delete_confirm', args: {'title': item.archive.title}),
                ),
                run: () async {
                  final kid = item.seasonId > 0 ? 'pgc_${item.seasonId}' : 'archive_${item.archive.aid}';
                  await source.deleteHistory([kid]);
                  feed.remove(item);
                },
              ),
          ],
        ),
        _VideoTab(
          'followed-anime',
          i18n('tv_video_followed_anime'),
          () => TvPagedFeed((page) async {
            final result = await source.followedSeasons(1, page);
            return (items: <Object>[...result.items], hasMore: result.hasMore);
          }),
          actions: seasonMenu,
        ),
        _VideoTab(
          'followed-series',
          i18n('tv_video_followed_series'),
          () => TvPagedFeed((page) async {
            final result = await source.followedSeasons(2, page);
            return (items: <Object>[...result.items], hasMore: result.hasMore);
          }),
          actions: seasonMenu,
        ),
      ],
    );
  }
}

/// "搜索" (A17.6 c11): the field ("输入关键词搜索视频"), recent words and
/// what is trending; then videos, uploaders and seasons. Back goes from the
/// results to the field.
class TvVideoSearchPane extends ConsumerStatefulWidget {
  /// Creates the destination.
  const new({super.key});

  @override
  ConsumerState<TvVideoSearchPane> createState() => _TvVideoSearchPaneState();
}

class _TvVideoSearchPaneState extends ConsumerState<TvVideoSearchPane> {
  late final VideoSource _source = ref.read(videoSourceProvider);
  final FocusNode _field = FocusNode(debugLabel: 'tv video search field');
  String _keyword = '';
  List<VodHotword> _hot = const [];
  TvHomeHost? _host;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHot());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = TvHomeScope.maybeOf(context)?.host;
    if (host != null && host != _host) {
      _host = host;
      host.setBackHandler(TvPane.videoSearch, _back);
    }
  }

  @override
  void dispose() {
    _host?.setBackHandler(TvPane.videoSearch, null);
    _field.dispose();
    super.dispose();
  }

  Future<void> _loadHot() async {
    try {
      final hot = await _source.hotwords();
      if (mounted) setState(() => _hot = hot);
    } on Object {
      // Trending words are extras.
    }
  }

  bool _back() {
    if (_keyword.isEmpty) return false;
    setState(() => _keyword = '');
    _field.requestFocus();
    return true;
  }

  void _search(String word) {
    final text = word.trim();
    if (text.isEmpty) return;
    unawaited(ref.read(videoStoreProvider).addSearch(text));
    setState(() => _keyword = text);
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    final store = ref.watch(videoStoreProvider);
    final keyword = _keyword;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(scale.px(12), scale.px(16), scale.px(12), scale.px(12)),
          child: TvInputField(
            key: const ValueKey('tv-video-search-field'),
            focusNode: _field,
            text: keyword,
            hint: i18n('tv_video_search_hint'),
            onSubmitted: _search,
          ),
        ),
        Expanded(
          child: keyword.isEmpty
              ? ListenableBuilder(
                  listenable: store,
                  builder: (context, _) => ListView(
                    padding: EdgeInsets.symmetric(horizontal: scale.px(12)),
                    children: [
                      for (final (title, words) in [
                        (i18n('tv_video_search_recent'), store.searches),
                        (i18n('tv_video_search_hot'), [for (final word in _hot) word.keyword]),
                      ])
                        if (words.isNotEmpty) ...[
                          Padding(
                            padding: EdgeInsets.only(top: scale.px(16), bottom: scale.px(8)),
                            child: Text(
                              title,
                              style: scale.font(TvTextSize.small, weight: FontWeight.w600, color: palette.accent),
                            ),
                          ),
                          Wrap(
                            spacing: scale.px(12),
                            runSpacing: scale.px(12),
                            children: [
                              for (final word in words)
                                TvButton(key: ValueKey('tv-video-word-$word'), label: word, onTap: () => _search(word)),
                            ],
                          ),
                        ],
                    ],
                  ),
                )
              : _TabbedVideoPane(
                  key: ValueKey('tv-video-search-$keyword'),
                  paneKey: 'tv-video-search-results',
                  tabs: [
                    _VideoTab(
                      'videos',
                      i18n('tv_video_search_videos'),
                      () => TvPagedFeed((page) async {
                        final result = await _source.searchVideos(keyword, page);
                        return (items: <Object>[...result.items], hasMore: result.hasMore);
                      }),
                      actions: (context, item, _) => _archiveMenu(context, _source, item),
                    ),
                    _VideoTab(
                      'users',
                      i18n('tv_video_search_users'),
                      () => TvPagedFeed((page) async {
                        final result = await _source.searchUsers(keyword, page);
                        return (items: <Object>[...result.items], hasMore: result.hasMore);
                      }),
                    ),
                    _VideoTab(
                      'anime',
                      i18n('tv_video_cinema_anime'),
                      () => TvPagedFeed((page) async {
                        final result = await _source.searchSeasons(keyword, page, movies: false);
                        return (items: <Object>[...result.items], hasMore: result.hasMore);
                      }),
                    ),
                    _VideoTab(
                      'movies',
                      i18n('tv_video_search_movies'),
                      () => TvPagedFeed((page) async {
                        final result = await _source.searchSeasons(keyword, page, movies: true);
                        return (items: <Object>[...result.items], hasMore: result.hasMore);
                      }),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
