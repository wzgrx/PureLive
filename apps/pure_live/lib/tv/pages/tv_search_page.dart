import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/search/search_history.dart';
import 'package:pure_live/features/search/search_model.dart';
import 'package:pure_live/features/search/search_ranking.dart';
import 'package:pure_live/features/search/search_scope.dart';
import 'package:pure_live/features/search/search_widgets.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/phone_bridge.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/home/tv_home_page.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_room_grid.dart';
import 'package:pure_live/tv/widgets/tv_room_row.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

/// Search as a page of its own (the phone's `RoutePath.kSearch` on the TV).
class TvSearchPage extends StatelessWidget {
  /// Creates the page for [route]; a `String` argument is searched at once.
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TvTheme.pageOf(context),
    body: TvBackground(child: TvSearchPane(initial: route.arguments is String ? route.arguments! as String : null)),
  );
}

/// Search with the remote on one page (A17.3 c11, C2 A; the phone's A09.7
/// over v4's search model):
///
/// - the field opens the system keyboard through a native input dialog on
///   Android ([TvTextInput]: the TV's IME and its voice input, where the box
///   has one), a text field elsewhere; "用手机输入" types on a phone that
///   scans a code (A17.9's LAN page);
/// - under it the phone's filters: "直播间 / 主播", "包含未开播", the
///   order (rooms), and the scope line that opens the scope panel;
/// - the platform tabs (all, then the platform list) search the same words
///   there; the results are below them (rooms in the grid, streamers as
///   rows, not as blown-up avatars) and up leaves them for the tabs;
/// - before a search, the recent words: OK searches one again, a held OK
///   removes it, "清空" asks first (c12);
/// - Back from the results goes back to the field and the recent words.
class TvSearchPane extends ConsumerStatefulWidget {
  /// Creates the pane; [initial] is searched at once.
  const new({this.initial, super.key});

  /// Words to search when the pane opens.
  final String? initial;

  @override
  ConsumerState<TvSearchPane> createState() => _TvSearchPaneState();
}

class _TvSearchPaneState extends ConsumerState<TvSearchPane> {
  late final SearchModel _model;
  late final SearchHistory _history;
  late final SearchScopeStore _scope;
  final FocusNode _field = FocusNode(debugLabel: 'tv search field');
  final GlobalKey<TvTabBarState> _tabs = GlobalKey();
  final GlobalKey<TvRoomGridState> _grid = GlobalKey();
  final GlobalKey<TvRoomRowsState> _rows = GlobalKey();
  bool _showResults = false;
  // An explicit search (OK on the field or a recent word) moves the focus to
  // its first result once there is one (c11); switching the mode or the
  // platform keeps the focus where it is.
  bool _focusResults = false;
  TvHomeHost? _host;

  @override
  void initState() {
    super.initState();
    final store = ref.read(storeProvider);
    final registry = ref.read(sitesProvider);
    final settings = store.settings;
    final realOnline = settings.get(Settings.realOnlinePlatforms).toSet();
    _model = SearchModel(
      sites: [for (final id in registry.availableIds(settings.get(Settings.hotAreasList))) registry.of(id)],
      audienceCompare: (left, right) => LiveRoom.compareAudienceRanking(
        left,
        right,
        preferRealOnline: settings.get(Settings.preferRealOnlineCounts),
        platformEnabled: realOnline.contains,
      ),
    )..addListener(_changed);
    _history = SearchHistory(store.meta)..addListener(_changed);
    _scope = SearchScopeStore(store.meta);
    unawaited(_history.load());
    final scopeLoaded = _scope.load().then((excluded) {
      if (mounted) _model.setExcluded(excluded);
    });
    if (widget.initial case final word? when word.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await scopeLoaded;
        if (mounted) _search(word);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = TvHomeScope.maybeOf(context);
    final host = scope?.host;
    if (host != null && host != _host) {
      _host = host;
      host.setBackHandler(TvPane.search, _back);
    }
  }

  @override
  void dispose() {
    _host?.setBackHandler(TvPane.search, null);
    _model
      ..removeListener(_changed)
      ..dispose();
    _history
      ..removeListener(_changed)
      ..dispose();
    _field.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_focusResults && _showResults && _model.resultCount > 0) {
      _focusResults = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enterResults();
      });
    }
  }

  /// Back inside the pane: from the results to the field.
  bool _back() {
    if (!_showResults) return false;
    _focusResults = false;
    setState(() => _showResults = false);
    _field.requestFocus();
    return true;
  }

  /// Clears the recent words after asking (pure_live_TV asked; the focus
  /// starts on cancel, A17.3 c12).
  Future<void> _clearRecent(int count) async {
    final confirmed = await showTvConfirm(
      context,
      title: i18n('tv_search_clear_title'),
      message: i18n('tv_search_clear_message', args: {'count': '$count'}),
      confirmLabel: i18n('tv_search_clear'),
      danger: true,
    );
    if (confirmed) await _history.clear();
  }

  void _search(String word) {
    final text = word.trim();
    if (text.isEmpty) return;
    setState(() {
      _showResults = true;
      _focusResults = true;
    });
    unawaited(_history.add(text));
    unawaited(
      _model.search(text).whenComplete(() {
        // A search that found nothing gives the focus nowhere.
        if (mounted && _model.resultCount == 0) _focusResults = false;
      }),
    );
  }

  /// "用手机输入": the words come from a phone that scans the code.
  Future<void> _phoneInput(PhoneBridge bridge) async {
    final values = await bridge.input(
      context,
      PhoneInputRequest(
        title: i18n('tv_search_phone'),
        fields: [
          PhoneInputField(
            key: 'keyword',
            label: i18n('tv_menu_search'),
            initial: _model.keyword,
            hint: i18n('tv_search_hint'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (values?['keyword'] case final word? when word.trim().isNotEmpty) _search(word);
  }

  Future<void> _chooseSort() async {
    final chosen = await showTvChoice<SearchSortMode>(
      context,
      title: i18n('search_sort'),
      current: _model.sort,
      options: [
        for (final mode in SearchSortMode.values) TvChoice(value: mode, label: SearchOptionsBar.sortLabel(mode)),
      ],
    );
    if (chosen != null) _model.setSort(chosen);
  }

  /// The phone's scope panel: which platforms "全部" searches.
  Future<void> _openScope() async {
    final excluded = await showSearchScopePanel(context, sites: _model.sites, excluded: _model.excluded);
    if (!mounted || setEquals(excluded, _model.excluded)) return;
    unawaited(_scope.save(excluded));
    _model.setExcluded(excluded, draft: _model.keyword);
  }

  bool _enterResults() {
    if (!_showResults) return false;
    return _model.mode == SearchMode.rooms
        ? _grid.currentState?.enter() ?? false
        : _rows.currentState?.enter() ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final standalone = TvHomeScope.maybeOf(context) == null;
    final bridge = PhoneBridge.maybeOf(context);
    final rooms = _model.mode == SearchMode.rooms;
    return PopScope<Object?>(
      canPop: !standalone || !_showResults,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(scale.px(12), scale.px(16), scale.px(12), scale.px(4)),
            child: TvInputField(
              focusNode: _field,
              autofocus: standalone,
              text: _model.keyword,
              hint: i18n('tv_search_hint'),
              onSubmitted: _search,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: scale.px(12), vertical: scale.px(4)),
            child: Row(
              children: [
                for (final mode in SearchMode.values) ...[
                  TvButton(
                    key: ValueKey('tv-search-mode-${mode.name}'),
                    icon: mode == SearchMode.rooms ? TvIcons.searchRooms : TvIcons.searchAnchors,
                    label: i18n(mode == SearchMode.rooms ? 'search_mode_rooms' : 'search_mode_anchors'),
                    selected: _model.mode == mode,
                    small: true,
                    onTap: () => _model.setMode(mode, draft: _model.keyword),
                  ),
                  SizedBox(width: scale.px(8)),
                ],
                SizedBox(width: scale.px(8)),
                TvButton(
                  key: const ValueKey('tv-search-offline'),
                  icon: _model.includeOffline ? TvIcons.ticked : null,
                  label: i18n('search_include_offline'),
                  selected: _model.includeOffline,
                  small: true,
                  onTap: () => _model.setIncludeOffline(value: !_model.includeOffline),
                ),
                if (rooms) ...[
                  SizedBox(width: scale.px(16)),
                  TvButton(
                    key: const ValueKey('tv-search-sort'),
                    icon: TvIcons.sort,
                    label: SearchOptionsBar.sortShortLabel(_model.sort),
                    small: true,
                    onTap: () => unawaited(_chooseSort()),
                  ),
                ],
                if (bridge != null) ...[
                  SizedBox(width: scale.px(16)),
                  TvButton(
                    key: const ValueKey('tv-search-phone'),
                    icon: TvIcons.phoneInput,
                    label: i18n('tv_search_phone'),
                    small: true,
                    onTap: () => unawaited(_phoneInput(bridge)),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: scale.px(12), vertical: scale.px(4)),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TvButton(
                key: const ValueKey('tv-search-scope'),
                icon: TvIcons.searchScope,
                label: SearchCoverageLine.textOf(_model),
                small: true,
                onTap: () => unawaited(_openScope()),
              ),
            ),
          ),
          TvTabBar(
            key: _tabs,
            small: true,
            tabs: [
              TvTab(id: SiteIds.all, label: i18n('tv_all_platforms'), icon: TvIcons.allPlatforms),
              for (final site in _model.sites)
                TvTab(
                  id: site.id,
                  label: platformName(site.id, fallback: site.name),
                  logo: site.id,
                ),
            ],
            selected: _model.selected,
            busy: _model.loading || _model.loadingMore,
            onSelect: (index) => _model.select(index, draft: _model.keyword),
            onRefresh: () => _search(_model.keyword),
            onDown: _showResults ? _enterResults : null,
          ),
          Expanded(child: _showResults ? _results() : _recent()),
        ],
      ),
    );
  }

  void _loadMore() {
    if (_model.hasMore && !_model.loadingMore && !_model.loading) unawaited(_model.loadMore());
  }

  Widget _results() {
    if (_model.resultCount == 0) {
      if (_model.loading) return const TvSkeletonGrid();
      final unsupported = _model.unsupported;
      if (unsupported == null && _model.hidesAllOffline) {
        return TvStatusView(
          icon: TvIcons.noResults,
          title: i18n('search_no_live_results'),
          subtitle: i18n('search_offline_hidden_desc'),
          actions: [
            TvStatusAction(
              label: i18n('search_show_offline'),
              icon: TvIcons.ticked,
              onTap: () => _model.setIncludeOffline(value: true),
            ),
          ],
        );
      }
      return TvStatusView(
        icon: TvIcons.noResults,
        title: unsupported != null
            ? i18n('tv_search_unsupported', args: {'platform': platformName(unsupported.id)})
            : i18n('tv_search_empty'),
        subtitle: _model.failed.isEmpty
            ? i18n('tv_search_empty_hint')
            : i18n('tv_search_failed', args: {'platforms': _model.failed.map(platformName).join('、')}),
      );
    }
    if (_model.mode == SearchMode.anchors) {
      final live = {
        for (final anchor in _model.anchors)
          if (anchor.isLive) anchor.key,
      };
      return TvRoomRows(
        key: _rows,
        rooms: [for (final anchor in _model.anchors) anchor.toRoom()],
        subtitleOf: (room) =>
            '${platformName(room.platform)} · ${i18n(live.contains(room.identityKey) ? 'live' : 'offline')}',
        onLeaveUp: () => _tabs.currentState?.focusSelected(),
        onEndReached: _loadMore,
      );
    }
    return TvRoomGrid(
      key: _grid,
      rooms: _model.results,
      showPlatform: _model.selected == 0,
      onLeaveUp: () => _tabs.currentState?.focusSelected(),
      onEndReached: _loadMore,
    );
  }

  Widget _recent() {
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    final words = _history.words;
    if (words.isEmpty) {
      return TvStatusView(icon: TvIcons.searchIntro, title: i18n('tv_menu_search'), subtitle: i18n('tv_search_intro'));
    }
    return SingleChildScrollView(
      padding: EdgeInsets.all(scale.px(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                i18n('tv_search_recent'),
                style: scale.font(TvTextSize.body, weight: FontWeight.w600, color: palette.text),
              ),
              SizedBox(width: scale.px(12)),
              Text(i18n('tv_search_recent_hint'), style: scale.font(TvTextSize.small, color: palette.textSecondary)),
              const Spacer(),
              TvButton(
                key: const ValueKey('tv-search-clear'),
                icon: TvIcons.clearAll,
                label: i18n('tv_search_clear'),
                kind: TvButtonKind.danger,
                onTap: () => unawaited(_clearRecent(words.length)),
              ),
            ],
          ),
          SizedBox(height: scale.px(12)),
          Wrap(
            spacing: scale.px(12),
            runSpacing: scale.px(12),
            children: [
              for (final word in words)
                TvButton(
                  key: ValueKey('tv-search-word-$word'),
                  icon: TvIcons.recentWord,
                  label: word,
                  small: true,
                  onTap: () => _search(word),
                  onLongPress: () => unawaited(_history.remove(word)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
