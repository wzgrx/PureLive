import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/video/video_comments.dart';
import 'package:pure_live/tv/video/video_player_page.dart';
import 'package:pure_live/tv/video/video_source.dart';
import 'package:pure_live/tv/video/video_store.dart';
import 'package:pure_live/tv/video/video_widgets.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';

Future<void> _push(BuildContext context, String name, WidgetBuilder builder) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    settings: RouteSettings(name: name),
    builder: builder,
  ),
);

/// Opens an archive's detail page.
Future<void> openVideoArchive(BuildContext context, VodArchive archive) =>
    _push(context, 'tv-video-detail', (_) => TvVideoDetailPage(bvid: archive.bvid, archive: archive));

/// Opens a season (番剧, 影视) by its id or one of its episodes.
Future<void> openVideoSeason(BuildContext context, {int? seasonId, int? epId}) =>
    _push(context, 'tv-video-season', (_) => TvVideoSeasonPage(seasonId: seasonId, epId: epId));

/// Opens an uploader's space.
Future<void> openVideoSpace(BuildContext context, VodOwner owner) =>
    _push(context, 'tv-video-space', (_) => TvVideoSpacePage(owner: owner));

/// Opens a favourites folder.
Future<void> openVideoFolder(BuildContext context, VodFavFolder folder) =>
    _push(context, 'tv-video-folder', (_) => TvVideoFolderPage(folder: folder));

/// Plays [items] from [index].
Future<void> playVideoItems(BuildContext context, List<VideoItem> items, int index, {Duration? start}) =>
    _push(context, 'tv-video-player', (_) => TvVideoPlayerPage(items: items, index: index, start: start));

/// The card menu of an archive (c16: written out): watch later and the
/// uploader's space.
List<TvVideoAction> archiveActions(BuildContext context, VideoSource source, VodArchive archive) => [
  if (source.signedIn)
    TvVideoAction(
      id: 'to-view',
      icon: TvIcons.videoLater,
      label: i18n('tv_video_watch_later'),
      run: () async {
        try {
          await source.addToView(archive.aid);
          AppNavigator.toast(i18n('tv_video_watch_later_added'));
        } on Object catch (error) {
          AppNavigator.toast(describeVideoError(error));
        }
      },
    ),
  if (archive.owner.mid > 0)
    TvVideoAction(
      id: 'space',
      icon: TvIcons.videoMine,
      label: i18n('tv_video_space_of', args: {'name': archive.owner.name}),
      run: () => openVideoSpace(context, archive.owner),
    ),
];

/// A failure in words (the platform's refusals by kind, never its text).
String describeVideoError(Object error) => switch (error) {
  NeedsLogin() => i18n('tv_video_login_needed'),
  _ => i18n('tv_video_failed'),
};

/// The frame of a video page: the page colour (or the background), the safe
/// area, the header.
class _VideoPage extends StatelessWidget {
  const new({required this.title, required this.child, this.pageKey, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;
  final Key? pageKey;

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    return Scaffold(
      key: pageKey,
      backgroundColor: TvTheme.pageOf(context),
      body: TvBackground(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: scale.px(96), vertical: scale.px(56)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TvPageHeader(title: title, subtitle: subtitle),
              SizedBox(height: scale.px(16)),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// A video's page (A17.6 c3, c4): the cover and what it is, the main button
/// ("播放", or "继续 P1 · 01:46" where it was left; it has the focus), the
/// actions written out, the parts when there are several ("看到 01:46"), and
/// related videos.
class TvVideoDetailPage extends ConsumerStatefulWidget {
  /// Creates the page of [bvid]; [archive] shows at once while the detail
  /// loads.
  const new({required this.bvid, this.archive, super.key});

  /// The archive id.
  final String bvid;

  /// What is known already (the card).
  final VodArchive? archive;

  @override
  ConsumerState<TvVideoDetailPage> createState() => _TvVideoDetailPageState();
}

class _TvVideoDetailPageState extends ConsumerState<TvVideoDetailPage> {
  late final VideoSource _source = ref.read(videoSourceProvider);
  VodArchive? _archive;
  List<VodArchive> _related = const [];
  ({bool liked, int coins, bool favorited})? _relation;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _archive = widget.archive;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final archive = await _source.detail(widget.bvid);
      if (!mounted) return;
      setState(() {
        _archive = archive;
        _error = null;
      });
      unawaited(_extras(archive));
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _extras(VodArchive archive) async {
    try {
      final related = await _source.related(archive.bvid);
      if (mounted) setState(() => _related = related);
    } on Object {
      // Related videos are extras.
    }
    if (!_source.signedIn) return;
    try {
      final relation = await _source.relation(archive.bvid);
      if (mounted) setState(() => _relation = relation);
    } on Object {
      // So is the relation.
    }
  }

  Future<void> _act(Future<void> Function() action, String done) async {
    try {
      await action();
      AppNavigator.toast(done);
      final archive = _archive;
      if (archive != null) unawaited(_extras(archive));
    } on Object catch (error) {
      AppNavigator.toast(describeVideoError(error));
    }
  }

  Future<void> _favorite(VodArchive archive) async {
    try {
      final folders = await _source.favFolders(aid: archive.aid);
      if (!mounted || folders.isEmpty) return;
      final folder = await showTvChoice<VodFavFolder>(
        context,
        title: i18n('tv_video_favorite'),
        options: [
          for (final folder in folders)
            TvChoice(
              value: folder,
              label: folder.title,
              description: folder.containsTarget ? i18n('tv_video_favorite_in') : null,
            ),
        ],
      );
      if (folder == null) return;
      await _act(
        () => folder.containsTarget
            ? _source.setFavorites(archive.aid, remove: [folder.id])
            : _source.setFavorites(archive.aid, add: [folder.id]),
        i18n(folder.containsTarget ? 'tv_video_favorite_removed' : 'tv_video_favorite_added'),
      );
    } on Object catch (error) {
      AppNavigator.toast(describeVideoError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final archive = _archive;
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final store = ref.watch(videoStoreProvider);
    if (archive == null) {
      return _VideoPage(
        title: i18n('tv_video_detail'),
        child: _error != null
            ? TvStatusView.failure(_error, onRetry: () => unawaited(_load()), autofocus: true)
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final items = VideoItem.partsOf(archive);
    final relation = _relation;
    final signedIn = _source.signedIn;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final progress = store.progressOf(archive.bvid);
        final resumeIndex = progress == null ? -1 : items.indexWhere((item) => item.cid == progress.cid);
        final resume = resumeIndex < 0 ? null : progress;
        return _VideoPage(
          pageKey: const ValueKey('tv-video-detail'),
          title: archive.title,
          subtitle: [archive.owner.name, if (archive.typeName.isNotEmpty) archive.typeName].join(' · '),
          child: ListView(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: scale.px(480),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
                        child: TvCover(url: archive.cover),
                      ),
                    ),
                  ),
                  SizedBox(width: scale.px(32)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            i18n('tv_video_views', args: {'count': videoCount(archive.stat.views)}),
                            i18n('tv_video_danmaku_count', args: {'count': videoCount(archive.stat.danmaku)}),
                            if (archive.duration > Duration.zero) videoClock(archive.duration),
                          ].join(' · '),
                          style: scale.font(TvTextSize.small, color: palette.textSecondary),
                        ),
                        SizedBox(height: scale.px(12)),
                        Text(
                          archive.description.isEmpty ? i18n('tv_video_no_description') : archive.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: scale.font(TvTextSize.body, color: palette.text, height: 1.5),
                        ),
                        SizedBox(height: scale.px(20)),
                        Wrap(
                          spacing: scale.px(12),
                          runSpacing: scale.px(12),
                          children: [
                            TvButton(
                              key: const ValueKey('tv-video-detail-play'),
                              autofocus: true,
                              kind: TvButtonKind.primary,
                              icon: AppIcons.play,
                              label: resume == null
                                  ? i18n('tv_video_play')
                                  : i18n(
                                      'tv_video_resume',
                                      args: {
                                        'part': 'P${items[resumeIndex].page}',
                                        'time': videoClock(resume.position),
                                      },
                                    ),
                              onTap: () => unawaited(
                                playVideoItems(
                                  context,
                                  items,
                                  resume == null ? 0 : resumeIndex,
                                  start: resume?.position,
                                ),
                              ),
                            ),
                            if (signedIn) ...[
                              TvButton(
                                key: const ValueKey('tv-video-like'),
                                selected: relation?.liked ?? false,
                                label: i18n(
                                  relation?.liked ?? false ? 'tv_video_liked' : 'tv_video_like',
                                  args: {'count': videoCount(archive.stat.likes)},
                                ),
                                onTap: () => unawaited(
                                  _act(
                                    () => _source.setLike(archive.aid, like: !(relation?.liked ?? false)),
                                    i18n(relation?.liked ?? false ? 'tv_video_unliked_toast' : 'tv_video_liked_toast'),
                                  ),
                                ),
                              ),
                              TvButton(
                                key: const ValueKey('tv-video-coin'),
                                selected: (relation?.coins ?? 0) > 0,
                                label: i18n('tv_video_coin', args: {'count': videoCount(archive.stat.coins)}),
                                onTap: () =>
                                    unawaited(_act(() => _source.addCoin(archive.aid), i18n('tv_video_coin_toast'))),
                              ),
                              TvButton(
                                key: const ValueKey('tv-video-favorite'),
                                selected: relation?.favorited ?? false,
                                label: i18n(
                                  'tv_video_favorite_count',
                                  args: {'count': videoCount(archive.stat.favorites)},
                                ),
                                onTap: () => unawaited(_favorite(archive)),
                              ),
                              TvButton(
                                key: const ValueKey('tv-video-later'),
                                label: i18n('tv_video_watch_later'),
                                onTap: () => unawaited(
                                  _act(() => _source.addToView(archive.aid), i18n('tv_video_watch_later_added')),
                                ),
                              ),
                            ],
                            if (archive.owner.mid > 0)
                              TvButton(
                                key: const ValueKey('tv-video-owner'),
                                label: i18n('tv_video_space_of', args: {'name': archive.owner.name}),
                                onTap: () => unawaited(openVideoSpace(context, archive.owner)),
                              ),
                            TvButton(
                              key: const ValueKey('tv-video-detail-comments'),
                              label: i18n('tv_video_comments_count', args: {'count': videoCount(archive.stat.replies)}),
                              onTap: () => unawaited(
                                _push(
                                  context,
                                  'tv-video-comments',
                                  (_) => _VideoPage(
                                    title: i18n('tv_video_comments'),
                                    subtitle: archive.title,
                                    child: TvVideoComments(oid: archive.aid, autofocus: true),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // c4: a single part lists nothing.
              if (items.length > 1) ...[
                SizedBox(height: scale.px(24)),
                Text(
                  i18n('tv_video_parts_count', args: {'count': '${items.length}'}),
                  style: scale.font(TvTextSize.small, weight: FontWeight.w600, color: palette.accent),
                ),
                SizedBox(height: scale.px(8)),
                Wrap(
                  spacing: scale.px(12),
                  runSpacing: scale.px(12),
                  children: [
                    for (final (index, item) in items.indexed)
                      TvButton(
                        key: ValueKey('tv-video-detail-part-$index'),
                        selected: index == resumeIndex,
                        label: index == resumeIndex
                            ? i18n(
                                'tv_video_part_seen',
                                args: {'part': 'P${item.page} ${item.title}', 'time': videoClock(resume!.position)},
                              )
                            : 'P${item.page} ${item.title}',
                        onTap: () => unawaited(
                          playVideoItems(context, items, index, start: index == resumeIndex ? resume?.position : null),
                        ),
                      ),
                  ],
                ),
              ],
              if (_related.isNotEmpty) ...[
                SizedBox(height: scale.px(32)),
                Text(
                  i18n('tv_video_related'),
                  style: scale.font(TvTextSize.small, weight: FontWeight.w600, color: palette.accent),
                ),
                SizedBox(height: scale.px(8)),
                SizedBox(
                  height: scale.px(330),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: _related.length,
                    separatorBuilder: (_, _) => SizedBox(width: scale.px(24)),
                    itemBuilder: (context, index) {
                      final related = _related[index];
                      return SizedBox(
                        width: scale.px(380),
                        child: TvVideoCard(
                          key: ValueKey('tv-video-related-$index'),
                          data: TvVideoCardData.archive(related, progress: store.progressOf(related.bvid)?.fraction),
                          onTap: () => unawaited(openVideoArchive(context, related)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A season (A17.6 c3, c9): what it is, "追番", and its episodes as "第 1
/// 话 title" with the member ones marked; the first episode (or the one
/// left) has the focus.
class TvVideoSeasonPage extends ConsumerStatefulWidget {
  /// Creates the page of the season [seasonId] (or the one of [epId]).
  const new({this.seasonId, this.epId, super.key});

  /// The season.
  final int? seasonId;

  /// One of its episodes.
  final int? epId;

  @override
  ConsumerState<TvVideoSeasonPage> createState() => _TvVideoSeasonPageState();
}

class _TvVideoSeasonPageState extends ConsumerState<TvVideoSeasonPage> {
  late final VideoSource _source = ref.read(videoSourceProvider);
  PgcSeason? _season;
  Object? _error;
  bool? _following;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final season = await _source.season(seasonId: widget.seasonId, epId: widget.epId);
      if (mounted) {
        setState(() {
          _season = season;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _follow(PgcSeason season) async {
    final following = _following ?? false;
    if (following) {
      final yes = await showTvConfirm(
        context,
        title: i18n('tv_video_unfollow_season'),
        message: i18n('tv_video_unfollow_season_confirm', args: {'title': season.title}),
        confirmLabel: i18n('tv_video_unfollow_season'),
        danger: true,
      );
      if (!yes) return;
    }
    try {
      await _source.setSeasonFollowing(season.seasonId, follow: !following);
      if (!mounted) return;
      setState(() => _following = !following);
      AppNavigator.toast(i18n(following ? 'tv_video_season_unfollowed' : 'tv_video_season_followed'));
    } on Object catch (error) {
      AppNavigator.toast(describeVideoError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final season = _season;
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final store = ref.watch(videoStoreProvider);
    if (season == null) {
      return _VideoPage(
        title: i18n('tv_video_season'),
        child: _error != null
            ? TvStatusView.failure(_error, onRetry: () => unawaited(_load()), autofocus: true)
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final items = VideoItem.episodesOf(season);
    final progress = store.progressOf('ss${season.seasonId}');
    final resumeIndex = progress == null ? -1 : items.indexWhere((item) => item.cid == progress.cid);
    final focus = resumeIndex < 0 ? 0 : resumeIndex;
    return _VideoPage(
      pageKey: const ValueKey('tv-video-season'),
      title: season.title,
      subtitle: [
        if (season.score > 0) i18n('tv_video_score', args: {'score': season.score.toStringAsFixed(1)}),
        ...season.styles,
        if (season.publishTime.isNotEmpty) season.publishTime,
      ].join(' · '),
      child: ListView(
        children: [
          Text(
            season.evaluate,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: scale.font(TvTextSize.body, color: palette.text, height: 1.5),
          ),
          SizedBox(height: scale.px(16)),
          if (_source.signedIn)
            Align(
              alignment: Alignment.centerLeft,
              child: TvButton(
                key: const ValueKey('tv-video-season-follow'),
                selected: _following ?? false,
                label: i18n(_following ?? false ? 'tv_video_season_following' : 'tv_video_follow_season'),
                onTap: () => unawaited(_follow(season)),
              ),
            ),
          SizedBox(height: scale.px(24)),
          if (items.isEmpty)
            TvStatusView(icon: TvIcons.noResults, title: i18n('tv_video_no_episodes'))
          else
            Wrap(
              spacing: scale.px(12),
              runSpacing: scale.px(12),
              children: [
                for (final (index, item) in items.indexed)
                  TvButton(
                    key: ValueKey('tv-video-episode-$index'),
                    autofocus: index == focus,
                    selected: index == resumeIndex,
                    label: [
                      item.title,
                      if (item.needsVip) i18n('tv_video_vip_badge'),
                      if (index == resumeIndex) i18n('tv_video_seen', args: {'time': videoClock(progress!.position)}),
                    ].join(' · '),
                    onTap: () => unawaited(
                      playVideoItems(context, items, index, start: index == resumeIndex ? progress?.position : null),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// An uploader's space (A17.6 c3, c18): who it is, "＋ 关注 / ✓ 已关注"
/// (unfollowing asks first), the sort ("最新发布 ⌄") and the uploads; the
/// first upload has the focus.
class TvVideoSpacePage extends ConsumerStatefulWidget {
  /// Creates the space of [owner].
  const new({required this.owner, super.key});

  /// The uploader.
  final VodOwner owner;

  @override
  ConsumerState<TvVideoSpacePage> createState() => _TvVideoSpacePageState();
}

class _TvVideoSpacePageState extends ConsumerState<TvVideoSpacePage> {
  late final VideoSource _source = ref.read(videoSourceProvider);
  String _order = 'pubdate';
  late TvPagedFeed<VodArchive> _feed = _feedOf(_order);
  VodUserSpace? _space;
  final GlobalKey<TvVideoGridState<VodArchive>> _grid = GlobalKey();

  static const Map<String, String> _orders = {
    'pubdate': 'tv_video_order_latest',
    'click': 'tv_video_order_views',
    'stow': 'tv_video_order_favorites',
  };

  TvPagedFeed<VodArchive> _feedOf(String order) => TvPagedFeed((page) async {
    final result = await _source.uploads(widget.owner.mid, page: page, order: order);
    if (page == 1 && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _grid.currentState?.enter());
    }
    return (items: result.items, hasMore: result.hasMore);
  });

  @override
  void initState() {
    super.initState();
    unawaited(_loadSpace());
  }

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  Future<void> _loadSpace() async {
    try {
      final space = await _source.userSpace(widget.owner.mid);
      if (mounted) setState(() => _space = space);
    } on Object {
      // The header falls back to the card's name.
    }
  }

  Future<void> _follow() async {
    final space = _space;
    final following = space?.isFollowed ?? false;
    if (following) {
      final yes = await showTvConfirm(
        context,
        title: i18n('tv_video_unfollow'),
        message: i18n('tv_video_unfollow_confirm', args: {'name': widget.owner.name}),
        confirmLabel: i18n('tv_video_unfollow'),
        danger: true,
      );
      if (!yes) return;
    }
    try {
      await _source.setFollowing(widget.owner.mid, follow: !following);
      AppNavigator.toast(i18n(following ? 'tv_video_unfollowed' : 'tv_video_followed'));
      await _loadSpace();
    } on Object catch (error) {
      AppNavigator.toast(describeVideoError(error));
    }
  }

  Future<void> _chooseOrder() async {
    final order = await showTvChoice<String>(
      context,
      title: i18n('tv_video_order'),
      current: _order,
      options: [for (final MapEntry(:key, :value) in _orders.entries) TvChoice(value: key, label: i18n(value))],
    );
    if (order == null || order == _order) return;
    final old = _feed;
    setState(() {
      _order = order;
      _feed = _feedOf(order);
    });
    old.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final space = _space;
    final scale = TvScale.of(context);
    final following = space?.isFollowed ?? false;
    return _VideoPage(
      pageKey: const ValueKey('tv-video-space'),
      title: space?.owner.name ?? widget.owner.name,
      subtitle: space == null
          ? null
          : [
              i18n('tv_video_followers', args: {'count': videoCount(space.followers)}),
              if (space.sign.isNotEmpty) space.sign,
            ].join(' · '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_source.signedIn) ...[
                TvButton(
                  key: const ValueKey('tv-video-space-follow'),
                  selected: following,
                  label: i18n(following ? 'tv_video_following' : 'tv_video_follow'),
                  onTap: () => unawaited(_follow()),
                ),
                SizedBox(width: scale.px(12)),
              ],
              TvButton(
                key: const ValueKey('tv-video-space-order'),
                label: '${i18n(_orders[_order]!)} ⌄',
                onTap: () => unawaited(_chooseOrder()),
              ),
            ],
          ),
          SizedBox(height: scale.px(16)),
          Expanded(
            child: TvVideoGrid<VodArchive>(
              key: ValueKey('tv-video-space-$_order'),
              feed: _feed,
              cardOf: (archive, store) =>
                  TvVideoCardData.archive(archive, progress: store.progressOf(archive.bvid)?.fraction),
              onOpen: (archive, _) => unawaited(openVideoArchive(context, archive)),
              actionsOf: (archive) => archiveActions(context, _source, archive),
              menuTitleOf: (archive) => archive.title,
              emptyTitle: i18n('tv_video_no_uploads'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One favourites folder's videos.
class TvVideoFolderPage extends ConsumerStatefulWidget {
  /// Creates the page of [folder].
  const new({required this.folder, super.key});

  /// The folder.
  final VodFavFolder folder;

  @override
  ConsumerState<TvVideoFolderPage> createState() => _TvVideoFolderPageState();
}

class _TvVideoFolderPageState extends ConsumerState<TvVideoFolderPage> {
  late final VideoSource _source = ref.read(videoSourceProvider);
  late final TvPagedFeed<VodFavItem> _feed = TvPagedFeed((page) async {
    final result = await _source.favItems(widget.folder.id, page);
    return (
      items: [
        for (final item in result.items)
          if (!item.invalid) item,
      ],
      hasMore: result.hasMore,
    );
  });

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _VideoPage(
    pageKey: const ValueKey('tv-video-folder'),
    title: widget.folder.title,
    subtitle: i18n('tv_video_folder_count', args: {'count': '${widget.folder.mediaCount}'}),
    child: TvVideoGrid<VodFavItem>(
      feed: _feed,
      cardOf: (item, store) =>
          TvVideoCardData.archive(item.archive, progress: store.progressOf(item.archive.bvid)?.fraction),
      onOpen: (item, _) => unawaited(openVideoArchive(context, item.archive)),
      actionsOf: (item) => archiveActions(context, _source, item.archive),
      menuTitleOf: (item) => item.archive.title,
      emptyTitle: i18n('tv_video_folder_empty'),
      emptyHint: i18n('tv_video_back_to_folders'),
    ),
  );
}
