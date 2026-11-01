import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/music_player.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/live_play/logic/predictive_back.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/features/version/update_prompt.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/tv/music/music_panes.dart';
import 'package:pure_live/tv/pages/tv_areas_pane.dart';
import 'package:pure_live/tv/pages/tv_favorites_pane.dart';
import 'package:pure_live/tv/pages/tv_followed_areas_pane.dart';
import 'package:pure_live/tv/pages/tv_history_pane.dart';
import 'package:pure_live/tv/pages/tv_iptv_pane.dart';
import 'package:pure_live/tv/pages/tv_link_pane.dart';
import 'package:pure_live/tv/pages/tv_popular_pane.dart';
import 'package:pure_live/tv/pages/tv_search_page.dart';
import 'package:pure_live/tv/settings/tv_settings_catalog.dart';
import 'package:pure_live/tv/tv_navigation.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/video/video_panes.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focus_region.dart';
import 'package:pure_live/tv/widgets/tv_nav_item.dart';

/// The modes of the TV home (A17.2 X1, pure_live_TV's 直播 / 视频 / 音乐):
/// each has its own destinations; the mode button at the top of the menu
/// switches.
enum TvMode {
  /// Live rooms.
  live('tv_mode_live', TvIcons.menuIptv),

  /// Bilibili videos (A17.6).
  video('tv_mode_video', TvIcons.menuVideo),

  /// Music from Bilibili videos (A17.7).
  music('tv_mode_music', TvIcons.menuMusic);

  new(this.labelKey, this.icon);

  /// The label's translation key.
  final String labelKey;

  /// The icon.
  final IconData icon;

  /// The mode stored as [name], [live] when unknown.
  static TvMode of(String name) => values.asNameMap()[name] ?? live;
}

/// The destinations of the TV side menu (pure_live_TV `TvMenuType` and its
/// mode switch), in order; [settings] sits at the bottom.
enum TvPane {
  /// Follows (the landing destination, as on pure_live_TV and 3.x).
  favorites('tv_menu_favorites', TvIcons.menuFavorites),

  /// Recommended rooms per platform.
  popular('tv_menu_popular', TvIcons.menuPopular),

  /// Areas per platform.
  areas('tv_menu_areas', TvIcons.menuAreas),

  /// The followed areas (A17.3 c9).
  followedAreas('tv_menu_followed_areas', TvIcons.menuFollowedAreas),

  /// Link playback (A17.5 c12).
  link('tv_menu_link', TvIcons.menuLink),

  /// Search.
  search('tv_menu_search', TvIcons.menuSearch),

  /// Watch history.
  history('tv_menu_history', TvIcons.menuHistory),

  /// IPTV playlists and channels.
  iptv('tv_menu_iptv', TvIcons.menuIptv),

  /// Video search (A17.6, X4: the video mode's order).
  videoSearch('tv_menu_video_search', TvIcons.menuSearch, mode: TvMode.video),

  /// "我的": followings, watch later, favourites, history, followed seasons.
  videoMine('tv_menu_video_mine', TvIcons.videoMine, mode: TvMode.video),

  /// The video home: dynamics, recommended, popular.
  videoHome('tv_menu_video_home', TvIcons.videoHome, mode: TvMode.video),

  /// Partitions and their rankings.
  videoAreas('tv_menu_video_areas', TvIcons.menuAreas, mode: TvMode.video),

  /// Films and series (影视, c10: the film icon).
  videoCinema('tv_menu_video_cinema', TvIcons.menuVideo, mode: TvMode.video),

  /// Music: the song now and the queue (A17.7).
  musicNow('tv_menu_music_now', TvIcons.musicNow, mode: TvMode.music),

  /// Music search.
  musicSearch('tv_menu_music_search', TvIcons.menuSearch, mode: TvMode.music),

  /// Music playlists.
  musicPlaylists('tv_menu_music_playlists', TvIcons.musicPlaylist, mode: TvMode.music),

  /// Music picks: daily, the followed, the ranking.
  musicDiscover('tv_menu_music_discover', TvIcons.musicDiscover, mode: TvMode.music),

  /// "我的": follows, the account's follows, recent, cloud (the landing page).
  musicMine('tv_menu_music_mine', TvIcons.videoMine, mode: TvMode.music),

  /// The TV settings.
  settings('tv_menu_settings', TvIcons.menuSettings);

  new(this.labelKey, this.icon, {this.mode = TvMode.live});

  /// The mode it belongs to (A17.2 X1).
  final TvMode mode;

  /// The label's translation key.
  final String labelKey;

  /// The icon.
  final IconData icon;

  /// The live mode's destinations in the menu's upper part, in the default
  /// order, all shown.
  static List<TvPane> get menu => menuOf();

  /// The live mode's destinations that can be in the menu's upper part, in
  /// the default order.
  static List<TvPane> get entries => entriesOf(TvMode.live);

  /// [mode]'s destinations that can be in the menu's upper part, in the
  /// default order.
  static List<TvPane> entriesOf(TvMode mode) => [
    for (final pane in values)
      if (pane != settings && pane.mode == mode) pane,
  ];

  /// [mode]'s entries in the user's [order] (`tvMenuOrder`: those first, the
  /// rest in the default order), without the [hidden] ones (`tvMenuHidden`;
  /// at least one stays), A17.9 c11.
  static List<TvPane> menuOf({
    List<String> order = const [],
    List<String> hidden = const [],
    TvMode mode = TvMode.live,
  }) {
    final ordered = orderOf(order, mode: mode);
    final shown = [
      for (final pane in ordered)
        if (!hidden.contains(pane.name)) pane,
    ];
    return shown.isEmpty ? [ordered.first] : shown;
  }

  /// [mode]'s entries in the user's [order], hidden ones included.
  static List<TvPane> orderOf(List<String> order, {TvMode mode = TvMode.live}) {
    final byName = {for (final pane in entriesOf(mode)) pane.name: pane};
    final ordered = <TvPane>[];
    for (final name in order) {
      final pane = byName.remove(name);
      if (pane != null) ordered.add(pane);
    }
    return [...ordered, ...byName.values];
  }

  /// This entry's icon: its own from `tvMenuIcons` (`pane:icon`), else
  /// [icon] (A17.9-31).
  IconData iconIn(List<String> icons) {
    for (final pair in icons) {
      final at = pair.indexOf(':');
      if (at > 0 && pair.substring(0, at) == name) {
        if (TvIcons.menuChoices[pair.substring(at + 1)] case final chosen?) return chosen;
      }
    }
    return icon;
  }
}

/// What a pane can ask of the TV home.
abstract interface class TvHomeHost {
  /// Puts the focus back on the side menu.
  void focusMenu();

  /// Sets what Back does inside [pane] first (search: back from the results
  /// to the field; areas: from the rooms to the areas); the handler returns
  /// whether it used the press. Null removes it.
  void setBackHandler(TvPane pane, bool Function()? handler);

  /// Whether [pane] is shown.
  bool isShown(TvPane pane);
}

/// The TV home host of the pane below (null for a page opened on its own).
class TvHomeScope extends InheritedWidget {
  /// Provides [host] to [pane]'s content.
  const new({required this.host, required this.pane, required this.shown, required super.child, super.key});

  /// The home.
  final TvHomeHost host;

  /// The pane this content is.
  final TvPane pane;

  /// Whether the pane is shown now.
  final bool shown;

  /// The scope above [context], if any.
  static TvHomeScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TvHomeScope>();

  @override
  bool updateShouldNotify(TvHomeScope oldWidget) => shown != oldWidget.shown || pane != oldWidget.pane;
}

/// The TV home (pure_live_TV `HomePage`): a side menu with a clock on the
/// left and the destination on the right.
///
/// The remote:
/// - Up and Down walk the menu; OK opens the destination and moves into it
///   (one press less than pure_live_TV, where OK only switched); Right
///   enters it too, back on the item focused there last;
/// - Back steps out one level at a time: the destination's own level (if it
///   has one), then the side menu, then the exit question (A17.2 c8).
///
/// The side menu is a rail of icons that opens over the page while the
/// focus is in it, unless "导航栏始终展开" is on (A17.2 c2). The first start
/// shows the notice once (A17.2 c10).
///
/// Destinations visited stay alive (pure_live_TV's keep-alive stack), so
/// coming back keeps their tab, scroll and focus.
class TvHomePage extends ConsumerStatefulWidget {
  /// Creates the home.
  const new({super.key});

  /// The meta key remembering that the notice was accepted (A17.2 c10).
  static const String noticeKey = 'tv.noticeAccepted';

  @override
  ConsumerState<TvHomePage> createState() => _TvHomePageState();
}

class _TvHomePageState extends ConsumerState<TvHomePage> with WidgetsBindingObserver implements TvHomeHost {
  TvPane _pane = TvPane.favorites;
  List<String> _icons = const [];
  final Set<TvPane> _visited = {TvPane.favorites};
  final Map<TvPane, FocusNode> _menuNodes = {};
  final Map<TvPane, FocusNode> _paneNodes = {};
  final Map<TvPane, FocusNode> _memory = {};
  final Map<TvPane, bool Function()> _backHandlers = {};
  DateTime? _backgroundedAt;
  Timer? _updateTimer;
  bool _menuFocused = false;
  bool _asking = false;

  final FocusNode _modeNode = FocusNode(debugLabel: 'tv menu mode');

  FocusNode _menuNode(TvPane pane) => _menuNodes[pane] ??= FocusNode(debugLabel: 'tv menu ${pane.name}');

  FocusNode _paneNode(TvPane pane) =>
      _paneNodes[pane] ??= FocusNode(debugLabel: 'tv pane ${pane.name}', skipTraversal: true, canRequestFocus: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_remember);
    // The first destination shown when "关注" is hidden (A17.9 c11).
    final settings = ref.read(storeProvider).settings;
    final shown = TvPane.menuOf(
      order: settings.get(Settings.tvMenuOrder),
      hidden: settings.get(Settings.tvMenuHidden),
      mode: TvMode.of(settings.get(Settings.tvMode)),
    );
    if (!shown.contains(_pane)) {
      _pane = shown.first;
      _visited.add(_pane);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(RoomBackChannel.instance.hold(this, _nativeBack));
      _menuNode(_pane).requestFocus();
      unawaited(_start());
    });
  }

  Future<void> _start() async {
    final services = ref.read(appServicesProvider);
    if (await services.store.meta.get(TvHomePage.noticeKey) != '1') {
      if (!mounted) return;
      final agreed = await showTvNotice(context);
      if (!agreed) {
        await SystemNavigator.pop();
        return;
      }
      await services.store.meta.set(TvHomePage.noticeKey, '1');
      if (!mounted) return;
      _menuNode(_pane).requestFocus();
    }
    final launch = services.launch;
    if (launch.room case final room?) unawaited(openTvRoom(room));
    if (launch.isPrimary) _updateTimer = Timer(startupUpdateCheckDelay, _checkForUpdate);
  }

  /// Android's Back (key or gesture) on the TV (K90, 2026-10-15): the root
  /// route's PopScope is not reached there (the home is the only route and
  /// Android leaves the app), so the home takes Back the way the live room
  /// does ([RoomBackChannel]): something open on top (a dialog, a page) is
  /// popped as usual, its own PopScope deciding; on the home itself the
  /// steps of [_back] run, and leaving ends the app.
  Future<void> _nativeBack() async {
    if (!mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      await Navigator.of(context).maybePop();
      return;
    }
    if (await _back()) await SystemNavigator.pop();
  }

  @override
  void dispose() {
    unawaited(RoomBackChannel.instance.release(this));
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_remember);
    _updateTimer?.cancel();
    for (final node in [_modeNode, ..._menuNodes.values, ..._paneNodes.values]) {
      node.dispose();
    }
    super.dispose();
  }

  void _checkForUpdate() {
    if (!mounted) return;
    unawaited(
      checkForUpdateOnStartup(
        context,
        settings: ref.read(appServicesProvider).store.settings,
        feed: ref.read(updateFeedProvider),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    final away = _backgroundedAt;
    _backgroundedAt = null;
    if (away == null || DateTime.now().difference(away) < HomeSignals.resumeRefreshAfter) return;
    // The phone's signal: follows refresh themselves, popular and areas
    // refresh the platform shown (3.x).
    final menu = switch (_pane) {
      TvPane.favorites => HomeMenu.favorites,
      TvPane.popular => HomeMenu.popular,
      TvPane.areas => HomeMenu.areas,
      _ => null,
    };
    if (menu == null) return;
    final previous = HomeSignals.resumedAfterBackground.value;
    HomeSignals.resumedAfterBackground.value = (menu, (previous?.$2 ?? 0) + 1);
  }

  /// Remembers the focused item of each destination.
  /// Also sends a focus that left the destination for the menu (Left on
  /// its first column, by geometry) to the selected entry, not to whichever
  /// entry happened to be level with it.
  void _remember() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || primary is FocusScopeNode) return;
    if (_pendingEntry != null && primary != _menuNode(_pane)) _pendingEntry = null;
    final paneNode = _paneNodes[_pane];
    final inPane = paneNode != null && paneNode.hasFocus;
    final cameFromPane = _inPane;
    _inPane = inPane;
    if (inPane) {
      _memory[_pane] = primary;
      return;
    }
    final selected = _menuNode(_pane);
    if (cameFromPane && primary != selected && _menuNodes.containsValue(primary)) selected.requestFocus();
  }

  bool _inPane = false;
  TvPane? _pendingEntry;
  bool _entryQueued = false;

  void _queueEntry() {
    if (_pendingEntry != _pane || _entryQueued) return;
    _entryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entryQueued = false;
      if (!mounted || _pendingEntry != _pane) return;
      final primary = FocusManager.instance.primaryFocus;
      if (!(ModalRoute.of(context)?.isCurrent ?? true) ||
          (primary != null && primary is! FocusScopeNode && primary != _menuNode(_pane))) {
        _pendingEntry = null;
        return;
      }
      if (_enter()) _pendingEntry = null;
    });
  }

  void _requestEntry() {
    _pendingEntry = _pane;
    _queueEntry();
  }

  @override
  void focusMenu() => _menuNode(_pane).requestFocus();

  @override
  void setBackHandler(TvPane pane, bool Function()? handler) {
    if (handler == null) {
      _backHandlers.remove(pane);
    } else {
      _backHandlers[pane] = handler;
    }
  }

  @override
  bool isShown(TvPane pane) => pane == _pane;

  /// Moves the focus into the destination: back on its last item, else on
  /// its first. False when it has nothing to focus yet.
  bool _enter() {
    final remembered = _memory[_pane];
    if (remembered != null && remembered.context != null && remembered.canRequestFocus) {
      remembered.requestFocus();
      return true;
    }
    return tvFocusFirst(_paneNode(_pane));
  }

  void _select(TvPane pane) {
    if (pane == _pane) {
      if (pane == TvPane.favorites) HomeSignals.favoritesReselected.value++;
      if (!_enter()) _requestEntry();
      return;
    }
    setState(() {
      _pane = pane;
      _visited.add(pane);
    });
    // A loading placeholder has no target. Resume only when content notifies
    // readiness, while this destination and the user's entry intent still own it.
    _requestEntry();
  }

  /// Back on the home: the destination's own level, then the menu, then
  /// the exit question; true when the user chose to leave.
  Future<bool> _back() async {
    final handler = _backHandlers[_pane];
    if (handler != null && handler()) return false;
    if (_paneNode(_pane).hasFocus) {
      focusMenu();
      return false;
    }
    if (_asking) return false;
    _asking = true;
    final leave = await showTvConfirm(
      context,
      title: i18n('tv_exit_title'),
      message: i18n('tv_exit_message'),
      confirmLabel: i18n('tv_exit'),
    );
    _asking = false;
    if (!leave && mounted) focusMenu();
    return leave;
  }

  void _revealMenuFocus() {
    if (!mounted || !_menuFocused) return;
    final node = FocusManager.instance.primaryFocus;
    if (node == null || !_menuNodes.containsValue(node)) return;
    final context = node.context;
    if (context != null) Scrollable.ensureVisible(context, alignment: 0.5);
  }

  /// The rail's entries top to bottom (the mode button is `null`), as last
  /// built.
  List<TvPane?> _rail = const [];

  /// Keys on the rail: → enters the page; ↑↓ move along the rail in its own
  /// order. Flutter's directional search would pick the page's rows, which
  /// lie under the opened rail and can be nearer than the next entry.
  KeyEventResult _menuKey(TvPane? pane, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      if (!_enter()) _requestEntry();
      return KeyEventResult.handled;
    }
    _pendingEntry = null;
    if (key != LogicalKeyboardKey.arrowUp && key != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
    final index = _rail.indexOf(pane);
    if (index < 0) return KeyEventResult.ignored;
    final next = index + (key == LogicalKeyboardKey.arrowUp ? -1 : 1);
    if (next < 0 || next >= _rail.length) return KeyEventResult.handled;
    final target = _rail[next];
    final node = target == null ? _modeNode : _menuNode(target)
      ..requestFocus();
    // An entry scrolled out of the rail comes into view.
    if (node.context case final context?) Scrollable.ensureVisible(context, alignment: 0.5);
    return KeyEventResult.handled;
  }

  Widget _content(TvPane pane) => switch (pane) {
    TvPane.favorites => const TvFavoritesPane(),
    TvPane.popular => const TvPopularPane(),
    TvPane.areas => const TvAreasPane(),
    TvPane.followedAreas => const TvFollowedAreasPane(),
    TvPane.history => const TvHistoryPane(),
    TvPane.search => const TvSearchPane(),
    TvPane.link => const TvLinkPane(),
    TvPane.iptv => const TvIptvPane(),
    TvPane.settings => const TvSettingsCatalog(),
    TvPane.videoSearch => const TvVideoGate(child: TvVideoSearchPane()),
    TvPane.videoMine => const TvVideoGate(child: TvVideoMinePane()),
    TvPane.videoHome => const TvVideoGate(child: TvVideoHomePane()),
    TvPane.videoAreas => const TvVideoGate(child: TvVideoAreasPane()),
    TvPane.videoCinema => const TvVideoGate(child: TvVideoCinemaPane()),
    TvPane.musicNow => const TvMusicFrame(child: TvMusicNowPane()),
    TvPane.musicSearch => const TvMusicFrame(child: TvMusicSearchPane()),
    TvPane.musicPlaylists => const TvMusicFrame(child: TvMusicPlaylistsPane()),
    TvPane.musicDiscover => const TvMusicFrame(child: TvMusicDiscoverPane()),
    TvPane.musicMine => const TvMusicFrame(child: TvMusicMinePane()),
  };

  /// The mode button (A17.2 X1): OK offers the modes; another mode opens
  /// its first destination.
  Future<void> _chooseMode(TvMode mode) async {
    final chosen = await showTvChoice<TvMode>(
      context,
      title: i18n('tv_mode'),
      current: mode,
      options: [
        for (final value in TvMode.values) TvChoice(value: value, label: i18n(value.labelKey), icon: value.icon),
      ],
    );
    if (chosen == null || chosen == mode || !mounted) return;
    final settings = ref.read(storeProvider).settings;
    // Leaving music stops it (A17.2 c7).
    if (mode == TvMode.music) unawaited(yieldMusicToOtherPlayback(ref));
    await settings.set(Settings.tvMode, chosen.name);
    if (!mounted) return;
    final shown = TvPane.menuOf(
      order: settings.get(Settings.tvMenuOrder),
      hidden: settings.get(Settings.tvMenuHidden),
      mode: chosen,
    );
    // Music lands on "我的" (A17.7 g1).
    final first = chosen == TvMode.music && shown.contains(TvPane.musicMine) ? TvPane.musicMine : shown.first;
    setState(() {
      _pane = first;
      _visited.add(first);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _menuNode(first).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    const panes = TvPane.values;
    final alwaysExpanded = watchSetting(ref, Settings.tvMenuAlwaysExpanded);
    final mode = TvMode.of(watchSetting(ref, Settings.tvMode));
    final menuPanes = TvPane.menuOf(
      order: watchSetting(ref, Settings.tvMenuOrder),
      hidden: watchSetting(ref, Settings.tvMenuHidden),
      mode: mode,
    );
    _icons = watchSetting(ref, Settings.tvMenuIcons);
    _rail = [null, ...menuPanes.where((pane) => pane != TvPane.settings), TvPane.settings];
    final expanded = alwaysExpanded || _menuFocused;
    final railWidth = scale.pxText(84);
    final expandedWidth = scale.pxText(200);
    final menu = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused != _menuFocused) {
          setState(() => _menuFocused = focused);
          // The clock changes the rail's viewport height. Reveal only after
          // that layout, and only the item that still owns menu focus.
          if (focused) WidgetsBinding.instance.addPostFrameCallback((_) => _revealMenuFocus());
        }
      },
      child: FocusTraversalGroup(
        child: Container(
          key: const ValueKey('tv-home-menu'),
          width: expanded ? expandedWidth : railWidth,
          decoration: BoxDecoration(
            color: palette.low,
            border: Border(right: BorderSide(color: palette.divider)),
          ),
          padding: expanded
              ? EdgeInsets.fromLTRB(scale.px(24), scale.px(28), scale.px(16), scale.px(28))
              : EdgeInsets.symmetric(horizontal: scale.px(10), vertical: scale.px(28)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (expanded) ...[const _Clock(), SizedBox(height: scale.px(16))],
              Padding(
                padding: EdgeInsets.only(bottom: scale.px(12)),
                child: TvNavItem(
                  key: const ValueKey('tv-menu-mode'),
                  focusNode: _modeNode,
                  icon: mode.icon,
                  label: i18n(mode.labelKey),
                  compact: !expanded,
                  onTap: () => unawaited(_chooseMode(mode)),
                  onKey: (node, event) => _menuKey(null, event),
                ),
              ),
              // Entries past the height scroll; clipped above and below only
              // (the focused entry grows past the sides).
              Expanded(
                child: Padding(
                  // Reserve paint space outside the scrolling viewport for
                  // the focused row's growth and outside ring at either edge.
                  padding: EdgeInsets.symmetric(vertical: scale.pxText(8)),
                  child: ClipRect(
                    clipper: _VerticalClip(overflow: scale.pxText(8)),
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [for (final pane in menuPanes) _menuItem(pane, compact: !expanded)],
                      ),
                    ),
                  ),
                ),
              ),
              _menuItem(TvPane.settings, compact: !expanded),
            ],
          ),
        ),
      ),
    );
    final page = FocusTraversalGroup(
      child: IndexedStack(
        index: panes.indexOf(_pane),
        sizing: StackFit.expand,
        children: [
          for (final pane in panes)
            if (_visited.contains(pane))
              Focus(
                focusNode: _paneNode(pane),
                skipTraversal: true,
                canRequestFocus: false,
                child: TvFocusReady(
                  onReady: () {
                    if (_pendingEntry == pane) _queueEntry();
                  },
                  child: TvHomeScope(
                    host: this,
                    pane: pane,
                    shown: pane == _pane,
                    child: KeyedSubtree(key: ValueKey('tv-pane-${pane.name}'), child: _content(pane)),
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
        ],
      ),
    );
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(
            _back().then((leave) async {
              if (leave && Platform.isAndroid) await SystemNavigator.pop();
            }),
          );
        }
      },
      child: Scaffold(
        backgroundColor: TvTheme.pageOf(context),
        body: TvBackground(
          // One tree for both layouts, so switching keeps the pages: always
          // expanded, the page sits beside the menu; else the rail opens over
          // the page, which stays put and dims.
          child: Stack(
            children: [
              Positioned.fill(left: alwaysExpanded ? expandedWidth : railWidth, child: page),
              if (_menuFocused && !alwaysExpanded)
                Positioned.fill(
                  left: railWidth,
                  child: IgnorePointer(
                    child: ColoredBox(
                      key: const ValueKey('tv-home-menu-scrim'),
                      color: palette.background.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              Positioned(left: 0, top: 0, bottom: 0, child: menu),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItem(TvPane pane, {required bool compact}) => Padding(
    padding: EdgeInsets.only(bottom: TvScale.of(context).px(4)),
    child: TvNavItem(
      key: ValueKey('tv-menu-${pane.name}'),
      focusNode: _menuNode(pane),
      icon: pane.iconIn(_icons),
      label: i18n(pane.labelKey),
      compact: compact,
      selected: pane == _pane,
      onTap: () => _select(pane),
      onKey: (node, event) => _menuKey(pane, event),
    ),
  );
}

/// The wall clock at the top of the menu (pure_live_TV `TvDigitalClock`):
/// hours and minutes, the date below.
class _Clock extends StatefulWidget {
  const new();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = DateTime.now();
    _timer = Timer(Duration(seconds: 60 - now.second), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    String two(int value) => value.toString().padLeft(2, '0');
    return Column(
      children: [
        Text(
          '${two(_now.hour)}:${two(_now.minute)}',
          style: scale.font(TvTextSize.title, weight: FontWeight.w600, color: palette.text, height: 1).tabular,
        ),
        SizedBox(height: scale.px(4)),
        Text(
          '${_now.year}/${two(_now.month)}/${two(_now.day)}',
          style: scale.font(TvTextSize.small, color: palette.textSecondary).tabular,
        ),
      ],
    );
  }
}

/// Clips above and below a box, not at its sides.
class _VerticalClip extends CustomClipper<Rect> {
  const new({required this.overflow});

  final double overflow;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-size.width, -overflow, size.width * 2, size.height + overflow);

  @override
  bool shouldReclip(_VerticalClip oldClipper) => overflow != oldClipper.overflow;
}
