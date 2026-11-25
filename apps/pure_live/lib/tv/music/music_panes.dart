import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/music_catalog.dart';
import 'package:pure_live/app/music_library.dart';
import 'package:pure_live/app/music_player.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/tv/music/music_player_page.dart';
import 'package:pure_live/tv/music/music_widgets.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/video/video_panes.dart';
import 'package:pure_live/tv/video/video_widgets.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';
import 'package:pure_live/tv/widgets/tv_settings_rows.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

// The music mode (A17.7): five destinations (正在播放、搜索、歌单、推荐、我的),
// the login gate of the video mode in front, the mini bar under each.

Future<void> _push(BuildContext context, String name, WidgetBuilder builder) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    settings: RouteSettings(name: name),
    builder: builder,
  ),
);

/// Opens the music player.
Future<void> openMusicPlayer(BuildContext context) =>
    _push(context, 'tv-music-player', (_) => const TvMusicPlayerPage());

/// Plays [tracks] from [start] and opens the player.
Future<void> playMusic(BuildContext context, WidgetRef ref, List<MusicTrack> tracks, {int start = 0}) async {
  if (tracks.isEmpty) return;
  unawaited(ref.read(musicPlayerProvider).play(tracks, start: start));
  await openMusicPlayer(context);
}

/// Opens an archive's songs (its parts).
Future<void> openMusicAlbum(BuildContext context, VodArchive archive) =>
    _push(context, 'tv-music-album', (_) => TvMusicAlbumPage(archive: archive));

/// Opens an uploader's music page.
Future<void> openMusicUp(BuildContext context, VodOwner owner) =>
    _push(context, 'tv-music-up', (_) => TvMusicUpPage(owner: owner));

/// A music destination: the login gate in front (the video mode's, the
/// same Bilibili account), the mini bar under it while the queue has songs.
class TvMusicFrame extends StatelessWidget {
  /// Frames [child].
  const new({required this.child, super.key});

  /// The destination.
  final Widget child;

  @override
  Widget build(BuildContext context) => TvVideoGate(
    music: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: child),
        TvMusicMiniBar(onOpen: () => unawaited(openMusicPlayer(context))),
      ],
    ),
  );
}

/// A page of songs (g11: "播放全部" first with the focus), the rows of
/// [place] with their menu.
class _TrackList extends ConsumerWidget {
  const new({required this.tracks, this.place = MusicRowPlace.other, this.playlistId, this.actions = const []});

  final List<MusicTrack> tracks;
  final MusicRowPlace place;
  final String? playlistId;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(musicPlayerProvider);
    final scale = TvScale.of(context);
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) => ListView(
        children: [
          Wrap(
            spacing: scale.px(12),
            runSpacing: scale.px(12),
            children: [
              TvButton(
                key: const ValueKey('tv-music-play-all'),
                autofocus: true,
                kind: TvButtonKind.primary,
                icon: AppIcons.play,
                label: i18n('tv_music_play_all', args: {'count': '${tracks.length}'}),
                onTap: tracks.isEmpty ? null : () => unawaited(playMusic(context, ref, tracks)),
              ),
              ...actions,
            ],
          ),
          SizedBox(height: scale.px(16)),
          if (tracks.isEmpty)
            TvStatusView(icon: TvIcons.noResults, title: i18n('tv_music_no_songs'))
          else
            for (final (index, track) in tracks.indexed)
              TvSongRow(
                key: ValueKey('tv-song-$index'),
                track: track,
                number: index + 1,
                playing: player.current?.id == track.id,
                onTap: () => unawaited(playMusic(context, ref, tracks, start: index)),
                onLongPress: () => unawaited(
                  showSongMenu(
                    context,
                    ref: ref,
                    track: track,
                    place: place,
                    playlistId: playlistId,
                    openUp: (owner) => unawaited(openMusicUp(context, owner)),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _MusicPage extends StatelessWidget {
  const new({required this.title, required this.child, this.subtitle, this.pageKey});

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

/// An archive's songs; "收藏专辑" keeps it under 我的 · 关注.
class TvMusicAlbumPage extends ConsumerStatefulWidget {
  /// Creates the page of [archive].
  const new({required this.archive, super.key});

  /// The archive.
  final VodArchive archive;

  @override
  ConsumerState<TvMusicAlbumPage> createState() => _TvMusicAlbumPageState();
}

class _TvMusicAlbumPageState extends ConsumerState<TvMusicAlbumPage> {
  VodArchive? _archive;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final archive = await ref.read(musicCatalogProvider).detail(widget.archive.bvid);
      if (mounted) setState(() => _archive = archive);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(musicLibraryProvider);
    final archive = _archive;
    return _MusicPage(
      pageKey: const ValueKey('tv-music-album'),
      title: widget.archive.title,
      subtitle: widget.archive.owner.name,
      child: archive == null
          ? (_error != null
                ? TvStatusView.failure(_error, onRetry: () => unawaited(_load()), autofocus: true)
                : const Center(child: CircularProgressIndicator()))
          : ListenableBuilder(
              listenable: library,
              builder: (context, _) => _TrackList(
                tracks: MusicTrack.of(archive),
                actions: [
                  TvButton(
                    key: const ValueKey('tv-music-follow-album'),
                    selected: library.isAlbumFollowed(archive.bvid),
                    label: i18n(
                      library.isAlbumFollowed(archive.bvid) ? 'tv_music_album_followed' : 'tv_music_follow_album',
                    ),
                    onTap: () => unawaited(library.toggleAlbum(archive)),
                  ),
                  TvButton(
                    key: const ValueKey('tv-music-album-add'),
                    label: i18n('tv_music_add_to_playlist'),
                    onTap: () =>
                        unawaited(showAddToPlaylist(context, library: library, tracks: MusicTrack.of(archive))),
                  ),
                  if (archive.owner.mid > 0)
                    TvButton(
                      key: const ValueKey('tv-music-album-up'),
                      label: i18n('tv_video_space_of', args: {'name': archive.owner.name}),
                      onTap: () => unawaited(openMusicUp(context, archive.owner)),
                    ),
                ],
              ),
            ),
    );
  }
}

/// An uploader's music: "关注" (this device, g9 "关注的UP主") and the uploads.
class TvMusicUpPage extends ConsumerStatefulWidget {
  /// Creates the page of [owner].
  const new({required this.owner, super.key});

  /// The uploader.
  final VodOwner owner;

  @override
  ConsumerState<TvMusicUpPage> createState() => _TvMusicUpPageState();
}

class _TvMusicUpPageState extends ConsumerState<TvMusicUpPage> {
  late final TvPagedFeed<Object> _feed = TvPagedFeed((page) async {
    final result = await ref.read(musicCatalogProvider).uploads(widget.owner.mid, page: page);
    return (items: <Object>[...result.items], hasMore: result.hasMore);
  });

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(musicLibraryProvider);
    final scale = TvScale.of(context);
    return _MusicPage(
      pageKey: const ValueKey('tv-music-up'),
      title: widget.owner.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: library,
            builder: (context, _) => Align(
              alignment: Alignment.centerLeft,
              child: TvButton(
                key: const ValueKey('tv-music-follow-up'),
                selected: library.isUpFollowed(widget.owner.mid),
                label: i18n(library.isUpFollowed(widget.owner.mid) ? 'tv_video_following' : 'tv_video_follow'),
                onTap: () => unawaited(library.toggleUp(widget.owner)),
              ),
            ),
          ),
          SizedBox(height: scale.px(16)),
          Expanded(
            child: TvVideoGrid<Object>(
              feed: _feed,
              cardOf: videoCardOf,
              onOpen: (item, _) => unawaited(openMusicAlbum(context, item as VodArchive)),
              emptyTitle: i18n('tv_video_no_uploads'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A playlist of the user's, the liked songs or a synced folder: its songs.
class TvMusicPlaylistPage extends ConsumerWidget {
  /// Creates the page of playlist [id] (or a synced folder's [folder]).
  const new({this.id, this.folder, super.key});

  /// The playlist.
  final String? id;

  /// The synced folder.
  final int? folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(musicLibraryProvider);
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final folderEntry = folder == null ? null : library.folder(folder!);
        final playlist = id == null ? null : library.playlist(id!);
        final liked = id == MusicLibrary.likedId;
        final title = folderEntry?.folder.title ?? (liked ? i18n('tv_music_liked_songs') : playlist?.name ?? '');
        final tracks = folderEntry?.tracks ?? playlist?.tracks ?? const <MusicTrack>[];
        return _MusicPage(
          pageKey: const ValueKey('tv-music-playlist'),
          title: title,
          subtitle: i18n('tv_music_song_count', args: {'count': '${tracks.length}'}),
          child: _TrackList(
            tracks: tracks,
            place: folderEntry != null
                ? MusicRowPlace.other
                : liked
                ? MusicRowPlace.liked
                : MusicRowPlace.playlist,
            playlistId: id,
            actions: [
              if (playlist != null && !liked) ...[
                TvButton(
                  key: const ValueKey('tv-music-playlist-rename'),
                  label: i18n('tv_music_rename'),
                  onTap: () async {
                    final name = await TvTextInput.prompt(context, title: i18n('tv_music_rename'), text: playlist.name);
                    if (name != null) await library.renamePlaylist(playlist.id, name);
                  },
                ),
                TvButton(
                  key: const ValueKey('tv-music-playlist-delete'),
                  kind: TvButtonKind.danger,
                  label: i18n('tv_music_delete_playlist'),
                  onTap: () async {
                    final yes = await showTvConfirm(
                      context,
                      title: i18n('tv_music_delete_playlist'),
                      message: i18n('tv_music_delete_playlist_confirm', args: {'name': playlist.name}),
                      confirmLabel: i18n('tv_music_delete_playlist'),
                      danger: true,
                    );
                    if (!yes) return;
                    await library.deletePlaylist(playlist.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ],
              if (folderEntry != null)
                TvButton(
                  key: const ValueKey('tv-music-folder-sync'),
                  label: i18n('tv_music_sync'),
                  onTap: () async {
                    try {
                      await library.syncFolder(folderEntry.folder);
                      AppNavigator.toast(i18n('tv_music_synced'));
                    } on Object catch (error) {
                      AppNavigator.toast(describeVideoErrorShort(error));
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A failure in words, short.
String describeVideoErrorShort(Object error) => i18n('tv_video_failed');

/// "正在播放": the song now with its controls and the queue; empty, what to
/// do.
class TvMusicNowPane extends ConsumerWidget {
  /// Creates the destination.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(musicPlayerProvider);
    final scale = TvScale.of(context);
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        if (!player.hasQueue) {
          return TvStatusView(
            icon: TvIcons.musicNow,
            title: i18n('tv_music_nothing'),
            subtitle: i18n('tv_music_nothing_hint'),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TvButton(
                key: const ValueKey('tv-music-open-player'),
                kind: TvButtonKind.primary,
                label: i18n('tv_music_open_player'),
                onTap: () => unawaited(openMusicPlayer(context)),
              ),
            ),
            SizedBox(height: scale.px(12)),
            Expanded(child: TvMusicQueue(player: player)),
          ],
        );
      },
    );
  }
}

/// "搜索": words, recent and trending; the results are archives (albums).
class TvMusicSearchPane extends ConsumerStatefulWidget {
  /// Creates the destination.
  const new({super.key});

  @override
  ConsumerState<TvMusicSearchPane> createState() => _TvMusicSearchPaneState();
}

class _TvMusicSearchPaneState extends ConsumerState<TvMusicSearchPane> {
  String _keyword = '';
  List<VodHotword> _hot = const [];
  TvPagedFeed<Object>? _feed;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHot());
  }

  @override
  void dispose() {
    _feed?.dispose();
    super.dispose();
  }

  Future<void> _loadHot() async {
    try {
      final hot = await ref.read(musicCatalogProvider).hotwords();
      if (mounted) setState(() => _hot = hot);
    } on Object {
      // Extras.
    }
  }

  void _search(String word) {
    final text = word.trim();
    if (text.isEmpty) return;
    final catalog = ref.read(musicCatalogProvider);
    final old = _feed;
    setState(() {
      _keyword = text;
      _feed = TvPagedFeed((page) async {
        final result = await catalog.search(text, page: page);
        return (items: <Object>[...result.items], hasMore: result.hasMore);
      });
    });
    old?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    final feed = _feed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(scale.px(12), scale.px(16), scale.px(12), scale.px(12)),
          child: TvInputField(text: _keyword, hint: i18n('tv_music_search_hint'), onSubmitted: _search),
        ),
        Expanded(
          child: feed == null
              ? ListView(
                  padding: EdgeInsets.symmetric(horizontal: scale.px(12)),
                  children: [
                    if (_hot.isNotEmpty) ...[
                      Text(
                        i18n('tv_video_search_hot'),
                        style: scale.font(TvTextSize.small, weight: FontWeight.w600, color: palette.accent),
                      ),
                      SizedBox(height: scale.px(8)),
                      Wrap(
                        spacing: scale.px(12),
                        runSpacing: scale.px(12),
                        children: [
                          for (final word in _hot) TvButton(label: word.keyword, onTap: () => _search(word.keyword)),
                        ],
                      ),
                    ],
                  ],
                )
              : TvVideoGrid<Object>(
                  key: ValueKey('tv-music-search-$_keyword'),
                  feed: feed,
                  cardOf: videoCardOf,
                  onOpen: (item, _) => unawaited(openMusicAlbum(context, item as VodArchive)),
                ),
        ),
      ],
    );
  }
}

/// "歌单": the liked songs, the user's playlists, the synced folders; new,
/// import, sync.
class TvMusicPlaylistsPane extends ConsumerWidget {
  /// Creates the destination.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(musicLibraryProvider);
    final catalog = ref.watch(musicCatalogProvider);
    final scale = TvScale.of(context);
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) => ListView(
        children: [
          Wrap(
            spacing: scale.px(12),
            runSpacing: scale.px(12),
            children: [
              TvButton(
                key: const ValueKey('tv-music-new-playlist'),
                label: i18n('tv_music_new_playlist'),
                onTap: () async {
                  final name = await TvTextInput.prompt(
                    context,
                    title: i18n('tv_music_new_playlist'),
                    hint: i18n('tv_music_playlist_name'),
                  );
                  if (name != null) await library.createPlaylist(name);
                },
              ),
              TvButton(
                key: const ValueKey('tv-music-import'),
                label: i18n('tv_music_import'),
                onTap: () => unawaited(_push(context, 'tv-music-import', (_) => const TvMusicImportPage())),
              ),
              TvButton(
                key: const ValueKey('tv-music-sync-folders'),
                label: i18n('tv_music_sync_folders'),
                onTap: () async {
                  try {
                    await library.syncAll();
                    AppNavigator.toast(i18n('tv_music_synced'));
                  } on Object catch (error) {
                    AppNavigator.toast(describeVideoErrorShort(error));
                  }
                },
              ),
            ],
          ),
          SizedBox(height: scale.px(16)),
          TvSettingsGroup(
            title: i18n('tv_music_my_playlists'),
            children: [
              TvLinkRow(
                id: 'playlist-liked',
                icon: TvIcons.followedMark,
                title: i18n('tv_music_liked_songs'),
                subtitle: i18n('tv_music_song_count', args: {'count': '${library.liked.length}'}),
                onTap: () => unawaited(
                  _push(context, 'tv-music-playlist', (_) => const TvMusicPlaylistPage(id: MusicLibrary.likedId)),
                ),
              ),
              for (final playlist in library.playlists)
                TvLinkRow(
                  id: 'playlist-${playlist.id}',
                  icon: TvIcons.musicPlaylist,
                  title: playlist.name,
                  subtitle: i18n('tv_music_song_count', args: {'count': '${playlist.tracks.length}'}),
                  onTap: () =>
                      unawaited(_push(context, 'tv-music-playlist', (_) => TvMusicPlaylistPage(id: playlist.id))),
                ),
            ],
          ),
          if (library.folders.isNotEmpty)
            TvSettingsGroup(
              title: i18n('tv_video_favorites'),
              children: [
                for (final entry in library.folders)
                  TvLinkRow(
                    id: 'folder-${entry.folder.id}',
                    icon: TvIcons.musicPlaylist,
                    title: entry.folder.title,
                    subtitle: i18n('tv_music_song_count', args: {'count': '${entry.tracks.length}'}),
                    onTap: () => unawaited(
                      _push(context, 'tv-music-playlist', (_) => TvMusicPlaylistPage(folder: entry.folder.id)),
                    ),
                  ),
              ],
            ),
          if (!catalog.isLoggedIn) TvStatusView(icon: TvIcons.needsLogin, title: i18n('tv_video_login_needed')),
        ],
      ),
    );
  }
}

/// Tabs over content (the video panes' look) for the music destinations.
class _MusicTabs extends StatefulWidget {
  const new({required this.tabs, required this.paneKey});

  final List<(String, Widget Function())> tabs;
  final String paneKey;

  @override
  State<_MusicTabs> createState() => _MusicTabsState();
}

class _MusicTabsState extends State<_MusicTabs> {
  int _selected = 0;
  final Map<int, Widget> _built = {};

  @override
  Widget build(BuildContext context) {
    final index = _selected.clamp(0, widget.tabs.length - 1);
    final content = _built[index] ??= widget.tabs[index].$2();
    return Column(
      key: ValueKey(widget.paneKey),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TvTabBar(
          tabs: [for (final (index, (label, _)) in widget.tabs.indexed) TvTab(id: '$index', label: label)],
          selected: index,
          onSelect: (next) => setState(() => _selected = next),
        ),
        Expanded(child: content),
      ],
    );
  }
}

/// A grid of archives that open as albums.
class _AlbumGrid extends ConsumerStatefulWidget {
  const new({required this.load, this.actionsOf, this.emptyTitle, super.key});

  final Future<VideoPageResult<Object>> Function(int page) load;
  final List<TvVideoAction> Function(BuildContext context, Object item, TvPagedFeed<Object> feed)? actionsOf;
  final String? emptyTitle;

  @override
  ConsumerState<_AlbumGrid> createState() => _AlbumGridState();
}

class _AlbumGridState extends ConsumerState<_AlbumGrid> {
  late final TvPagedFeed<Object> _feed = TvPagedFeed(widget.load);

  @override
  void dispose() {
    _feed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TvVideoGrid<Object>(
    feed: _feed,
    cardOf: videoCardOf,
    onOpen: (item, _) => unawaited(switch (item) {
      VodArchive() => openMusicAlbum(context, item),
      VodHistoryEntry(:final archive) => openMusicAlbum(context, archive),
      VodOwner() => openMusicUp(context, item),
      _ => Future<void>.value(),
    }),
    actionsOf: widget.actionsOf == null ? null : (item) => widget.actionsOf!(context, item, _feed),
    menuTitleOf: videoTitleOf,
    emptyTitle: widget.emptyTitle,
  );
}

/// "推荐": daily picks from a chosen folder, the newest of the followed
/// uploaders, the music ranking.
class TvMusicDiscoverPane extends ConsumerWidget {
  /// Creates the destination.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(musicCatalogProvider);
    final library = ref.watch(musicLibraryProvider);
    return _MusicTabs(
      paneKey: 'tv-music-discover',
      tabs: [
        (i18n('tv_music_daily'), () => const _DailyPicks()),
        (
          i18n('tv_video_dynamics'),
          () => _AlbumGrid(
            emptyTitle: i18n('tv_music_no_ups'),
            load: (page) async {
              if (page > 1) return (items: const <Object>[], hasMore: false);
              final lists = await Future.wait([
                for (final up in library.ups.take(8))
                  catalog.uploads(up.mid).then((value) => value.items).catchError((Object _) => const <VodArchive>[]),
              ]);
              final all = [for (final list in lists) ...list]
                ..sort((a, b) => (b.publishedAt ?? DateTime(2000)).compareTo(a.publishedAt ?? DateTime(2000)));
              return (items: <Object>[...all], hasMore: false);
            },
          ),
        ),
        (
          i18n('tv_music_ranking'),
          () => _AlbumGrid(load: (page) async => (items: <Object>[...await catalog.ranking()], hasMore: false)),
        ),
      ],
    );
  }
}

class _DailyPicks extends ConsumerStatefulWidget {
  const new();

  @override
  ConsumerState<_DailyPicks> createState() => _DailyPicksState();
}

class _DailyPicksState extends ConsumerState<_DailyPicks> {
  List<VodArchive>? _picks;
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool force = false}) async {
    try {
      final picks = await ref.read(musicLibraryProvider).daily.today(force: force);
      if (mounted) {
        setState(() {
          _picks = picks;
          _loaded = true;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loaded = true;
        });
      }
    }
  }

  Future<void> _chooseFolder() async {
    try {
      final folders = await ref.read(musicCatalogProvider).favFolders();
      if (!mounted || folders.isEmpty) return;
      final folder = await showTvChoice<VodFavFolder>(
        context,
        title: i18n('tv_music_daily_folder'),
        options: [for (final folder in folders) TvChoice(value: folder, label: folder.title)],
      );
      if (folder == null) return;
      await ref.read(musicLibraryProvider).daily.setDefaultFolder(folder.id, folder.title);
      await _load(force: true);
    } on Object catch (error) {
      AppNavigator.toast(describeVideoErrorShort(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final picks = _picks;
    if (!_loaded) return const TvSkeletonGrid();
    if (_error != null) return TvStatusView.failure(_error, onRetry: () => unawaited(_load()));
    if (picks == null || picks.isEmpty) {
      return TvStatusView(
        icon: TvIcons.musicDiscover,
        title: i18n('tv_music_daily_none'),
        subtitle: i18n('tv_music_daily_none_hint'),
        actions: [
          TvStatusAction(icon: TvIcons.musicPlaylist, label: i18n('tv_music_daily_folder'), onTap: _chooseFolder),
        ],
      );
    }
    final tracks = [for (final archive in picks) ...MusicTrack.of(archive).take(1)];
    return _TrackList(
      tracks: tracks,
      actions: [
        TvButton(
          key: const ValueKey('tv-music-daily-refresh'),
          label: i18n('tv_music_daily_refresh'),
          onTap: () => unawaited(_load(force: true)),
        ),
        TvButton(
          key: const ValueKey('tv-music-daily-folder'),
          label: i18n('tv_music_daily_folder'),
          onTap: () => unawaited(_chooseFolder()),
        ),
      ],
    );
  }
}

/// "我的" (g9): 关注 (this device's followed uploaders and albums), B站关注
/// (the account's), 最近 (clearing asks first, g8), 云端 (the account's
/// history; deleting asks first).
class TvMusicMinePane extends ConsumerWidget {
  /// Creates the destination.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(musicCatalogProvider);
    final library = ref.watch(musicLibraryProvider);
    String? cursor;
    return _MusicTabs(
      paneKey: 'tv-music-mine',
      tabs: [
        (
          i18n('tv_music_follows'),
          () => ListenableBuilder(
            listenable: library,
            builder: (context, _) => _AlbumGrid(
              key: ValueKey('tv-music-follows-${library.ups.length}-${library.albums.length}'),
              emptyTitle: i18n('tv_music_follows_empty'),
              load: (page) async => (items: <Object>[...library.ups, ...library.albums], hasMore: false),
            ),
          ),
        ),
        (
          i18n('tv_music_bilibili_follows'),
          () => _AlbumGrid(
            load: (page) async {
              final result = await catalog.followings(page: page);
              return (items: <Object>[...result.items], hasMore: result.hasMore);
            },
          ),
        ),
        (
          i18n('tv_music_recent'),
          () => ListenableBuilder(
            listenable: library,
            builder: (context, _) => _TrackList(
              tracks: library.recents,
              place: MusicRowPlace.recent,
              actions: [
                TvButton(
                  key: const ValueKey('tv-music-clear-recent'),
                  kind: TvButtonKind.danger,
                  label: i18n('tv_music_clear_recent'),
                  onTap: library.recents.isEmpty
                      ? null
                      : () async {
                          final yes = await showTvConfirm(
                            context,
                            title: i18n('tv_music_clear_recent'),
                            message: i18n('tv_music_clear_recent_confirm'),
                            confirmLabel: i18n('tv_music_clear_recent'),
                            danger: true,
                          );
                          if (yes) await library.clearRecents();
                        },
                ),
              ],
            ),
          ),
        ),
        (
          i18n('tv_music_cloud'),
          () => _AlbumGrid(
            load: (page) async {
              final result = await catalog.history(cursor: page == 1 ? null : cursor);
              cursor = result.cursor;
              return (items: <Object>[...result.items], hasMore: result.hasMore);
            },
            actionsOf: (context, item, feed) => [
              if (item is VodHistoryEntry)
                TvVideoAction(
                  id: 'delete-cloud',
                  icon: TvIcons.delete,
                  label: i18n('tv_video_history_delete'),
                  confirm: (
                    i18n('tv_video_history_delete'),
                    i18n('tv_video_history_delete_confirm', args: {'title': item.archive.title}),
                  ),
                  run: () async {
                    await catalog.deleteHistory(item.archive);
                    feed.remove(item);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "导入歌单" (three steps): which platform and the link or id, then the
/// matching (one search every 1.2 s, with the progress; "停止" keeps what
/// matched), then done — a new playlist of the matched songs.
class TvMusicImportPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const new({this.importer, super.key});

  /// The matcher (tests pass one with a short pause).
  final PlaylistImporter? importer;

  @override
  ConsumerState<TvMusicImportPage> createState() => _TvMusicImportPageState();
}

class _TvMusicImportPageState extends ConsumerState<TvMusicImportPage> {
  PlaylistPlatform _platform = PlaylistPlatform.netease;
  ImportProgress? _progress;
  ImportResult? _result;
  bool _running = false;
  bool _cancelled = false;
  Object? _error;

  String _platformName(PlaylistPlatform platform) => i18n(switch (platform) {
    PlaylistPlatform.netease => 'tv_music_netease',
    PlaylistPlatform.kugou => 'tv_music_kugou',
    PlaylistPlatform.tencent => 'tv_music_qq',
  });

  Future<void> _start() async {
    final input = await TvTextInput.prompt(
      context,
      title: i18n('tv_music_import_link'),
      hint: i18n('tv_music_import_hint'),
    );
    if (input == null || !mounted) return;
    final parsed = PlaylistImportSource.parse(input, platform: _platform);
    if (parsed == null) {
      AppNavigator.toast(i18n('tv_music_import_bad'));
      return;
    }
    final catalog = ref.read(musicCatalogProvider);
    setState(() {
      _running = true;
      _cancelled = false;
      _progress = null;
      _result = null;
      _error = null;
    });
    try {
      final songs = await catalog.importTracks(parsed.platform, parsed.id);
      final importer =
          widget.importer ?? PlaylistImporter(search: (keyword) async => (await catalog.search(keyword)).items);
      final result = await importer.run(
        songs,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        isCancelled: () => _cancelled || !mounted,
      );
      if (!mounted) return;
      final tracks = [for (final item in result.matched) ...MusicTrack.of(item.match.archive).take(1)];
      if (tracks.isNotEmpty) {
        await ref
            .read(musicLibraryProvider)
            .createPlaylist(
              i18n('tv_music_imported_name', args: {'platform': _platformName(parsed.platform)}),
              tracks: tracks,
            );
      }
      setState(() => _result = result);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    final progress = _progress;
    final result = _result;
    return _MusicPage(
      pageKey: const ValueKey('tv-music-import'),
      title: i18n('tv_music_import'),
      subtitle: i18n(
        result != null
            ? 'tv_music_import_step_done'
            : _running
            ? 'tv_music_import_step_matching'
            : 'tv_music_import_step_source',
      ),
      child: ListView(
        children: [
          if (!_running && result == null) ...[
            Wrap(
              spacing: scale.px(12),
              children: [
                for (final platform in PlaylistPlatform.values)
                  TvButton(
                    key: ValueKey('tv-music-import-${platform.name}'),
                    autofocus: platform == _platform,
                    selected: platform == _platform,
                    label: _platformName(platform),
                    onTap: () => setState(() => _platform = platform),
                  ),
              ],
            ),
            SizedBox(height: scale.px(16)),
            Align(
              alignment: Alignment.centerLeft,
              child: TvButton(
                key: const ValueKey('tv-music-import-start'),
                kind: TvButtonKind.primary,
                label: i18n('tv_music_import_link'),
                onTap: () => unawaited(_start()),
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: scale.px(16)),
              Text(i18n('tv_music_import_failed'), style: scale.font(TvTextSize.body, color: palette.danger)),
            ],
          ],
          if (_running) ...[
            Text(
              progress == null
                  ? i18n('tv_music_import_reading')
                  : i18n(
                      'tv_music_import_progress',
                      args: {
                        'done': '${progress.done}',
                        'total': '${progress.total}',
                        'matched': '${progress.matched}',
                      },
                    ),
              key: const ValueKey('tv-music-import-progress'),
              style: scale.font(TvTextSize.body, color: palette.text),
            ),
            SizedBox(height: scale.px(16)),
            Align(
              alignment: Alignment.centerLeft,
              child: TvButton(
                key: const ValueKey('tv-music-import-stop'),
                autofocus: true,
                label: i18n('tv_music_import_stop'),
                onTap: () => setState(() => _cancelled = true),
              ),
            ),
          ],
          if (result != null)
            Text(
              i18n(
                'tv_music_import_done',
                args: {'matched': '${result.matched.length}', 'missed': '${result.unmatched.length}'},
              ),
              key: const ValueKey('tv-music-import-done'),
              style: scale.font(TvTextSize.body, color: palette.text),
            ),
        ],
      ),
    );
  }
}
