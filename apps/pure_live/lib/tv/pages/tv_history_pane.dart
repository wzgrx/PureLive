import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/history/history_limit_dialog.dart';
import 'package:pure_live/features/history/history_page.dart';
import 'package:pure_live/features/history/history_refresh.dart';
import 'package:pure_live/features/history/history_sections.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focus_region.dart';
import 'package:pure_live/tv/widgets/tv_room_dialog.dart';
import 'package:pure_live/tv/widgets/tv_room_grid.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

/// The watch history, newest first.
final StreamProvider<List<LiveRoom>> tvHistoryProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(storeProvider).history.watchAll(),
);

/// The sizes "保留数量" offers (the phone's presets; 0 is no limit).
const List<int> tvHistoryLimits = [20, 50, 100, 200, 0];

/// Watch history (pure_live_TV `HistoryPage` over v4's history store; A17.3
/// c10): "观看记录 18 / 50 条" with "刷新" (checks which still broadcast),
/// "保留数量 50" and "清空" (asked first, the focus on cancel); the platforms
/// that have entries and the days ("今天", "昨天", "近 7 天", "更早") as tabs
/// with their counts — tabs rather than headings, so the grid keeps moving
/// by index and remembering the focus. The card dialog deletes one entry
/// (asked first).
class TvHistoryPane extends ConsumerStatefulWidget {
  /// Creates the pane.
  const new({super.key});

  @override
  ConsumerState<TvHistoryPane> createState() => _TvHistoryPaneState();
}

class _TvHistoryPaneState extends ConsumerState<TvHistoryPane> {
  static const String _all = '';
  final Map<String, GlobalKey<TvRoomGridState>> _grids = {};
  final GlobalKey<TvFocusRegionState> _actions = GlobalKey();
  final FocusNode _clear = FocusNode(debugLabel: 'history clear');
  final GlobalKey<TvTabBarState> _platformTabs = GlobalKey();
  final GlobalKey<TvTabBarState> _dayTabs = GlobalKey();
  String _platform = _all;
  HistorySection? _day;
  bool _refreshing = false;

  GlobalKey<TvRoomGridState> _grid(String key) => _grids[key] ??= GlobalKey();

  @override
  void dispose() {
    _clear.dispose();
    super.dispose();
  }

  Future<void> _clearAll(List<LiveRoom> rooms) async {
    final confirmed = await showTvConfirm(
      context,
      title: i18n('tv_history_clear'),
      message: i18n('tv_history_clear_message', args: {'count': '${rooms.length}'}),
      confirmLabel: i18n('tv_history_clear'),
      danger: true,
    );
    if (!confirmed) return;
    await ref.read(storeProvider).history.clear(rooms);
  }

  Future<void> _refresh(List<LiveRoom> rooms) async {
    if (_refreshing || rooms.isEmpty) return;
    setState(() => _refreshing = true);
    final store = ref.read(storeProvider);
    try {
      final result = await refreshHistoryRooms(
        rooms,
        load: ref.read(historyLoaderProvider),
        maxConcurrent: store.settings.get(Settings.maxConcurrentRefresh),
        isCancelled: () => !mounted,
      );
      await store.history.update(result.rooms);
    } on Object {
      AppNavigator.toast(i18n('tv_history_refresh_failed'));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// "保留数量" (the phone's presets and "自定义"): a smaller number than the
  /// entries asks first, as the oldest go.
  Future<void> _limit(int current, int count) async {
    const custom = -1;
    final picked = await showTvChoice<int>(
      context,
      title: i18n('history_limit'),
      subtitle: i18n('history_limit_desc'),
      current: tvHistoryLimits.contains(current) ? current : custom,
      options: [
        for (final value in tvHistoryLimits) TvChoice(value: value, label: historyLimitLabel(value)),
        TvChoice(value: custom, label: i18n('history_limit_custom')),
      ],
    );
    if (picked == null || !mounted) return;
    var limit = picked;
    if (picked == custom) {
      final text = await TvTextInput.prompt(
        context,
        title: i18n('history_limit_custom'),
        text: '$current',
        numeric: true,
      );
      final value = int.tryParse(text?.trim() ?? '');
      if (value == null || value < 0) {
        if (text != null) AppNavigator.toast(i18n('history_limit_invalid'));
        return;
      }
      limit = value;
    }
    if (limit != unlimitedHistoryLimit && limit < count) {
      if (!mounted) return;
      final yes = await showTvConfirm(
        context,
        title: i18n('history_limit'),
        message: i18n('history_limit_trim_warning', args: {'count': '${count - limit}'}),
        confirmLabel: i18n('save'),
        danger: true,
      );
      if (!yes) return;
    }
    await ref.read(storeProvider).history.setLimit(limit);
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    final history = ref.watch(tvHistoryProvider);
    final limit = watchSetting(ref, Settings.historyLimit);
    final rooms = history.value ?? const <LiveRoom>[];
    final now = DateTime.now();
    if (!history.hasValue) return const TvSkeletonGrid();
    if (rooms.isEmpty) {
      // c4: the phone's words; "浏览热门" points the way.
      return TvStatusView(icon: TvIcons.noHistory, title: i18n('tv_no_history'), subtitle: i18n('tv_no_history_hint'));
    }
    final counts = <String, int>{};
    for (final room in rooms) {
      counts[room.platform] = (counts[room.platform] ?? 0) + 1;
    }
    final platforms = [_all, ...counts.keys];
    if (!platforms.contains(_platform)) _platform = _all;
    final ofPlatform = [
      for (final room in rooms)
        if (_platform == _all || room.platform == _platform) room,
    ];
    final sections = historySections(ofPlatform, now);
    final days = [for (final (section, _) in sections) section];
    final day = _day != null && days.contains(_day) ? _day : null;
    final shown = day == null ? ofPlatform : sections.firstWhere((entry) => entry.$1 == day).$2;
    final gridKey = _grid('$_platform/${day?.name ?? ''}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(scale.px(12), scale.px(8), scale.px(12), 0),
          child: TvFocusRegion(
            key: _actions,
            horizontal: true,
            onUp: () {},
            onDown: () {
              if (!(_platformTabs.currentState?.focusRemembered() ?? false)) {
                _dayTabs.currentState?.focusRemembered();
              }
            },
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    i18n(
                      limit == unlimitedHistoryLimit ? 'tv_history_count' : 'tv_history_count_limit',
                      args: {'count': '${rooms.length}', 'limit': '$limit'},
                    ),
                    key: const ValueKey('tv-history-count'),
                    style: scale.font(TvTextSize.body, color: palette.textSecondary),
                  ),
                ),
                TvButton(
                  key: const ValueKey('tv-history-refresh'),
                  icon: AppIcons.refresh,
                  label: i18n(_refreshing ? 'tv_history_refreshing' : 'tv_refresh'),
                  onTap: _refreshing ? null : () => unawaited(_refresh(shown)),
                ),
                SizedBox(width: scale.px(12)),
                TvButton(
                  key: const ValueKey('tv-history-limit'),
                  label: i18n('tv_history_limit', args: {'limit': historyLimitLabel(limit)}),
                  onTap: () => unawaited(_limit(limit, rooms.length)),
                ),
                SizedBox(width: scale.px(12)),
                TvButton(
                  key: const ValueKey('tv-history-clear'),
                  focusNode: _clear,
                  icon: TvIcons.clearAll,
                  label: i18n('tv_history_clear'),
                  kind: TvButtonKind.danger,
                  onTap: () => unawaited(_clearAll(shown)),
                ),
              ],
            ),
          ),
        ),
        if (counts.length > 1)
          TvTabBar(
            key: _platformTabs,
            small: true,
            tabs: [
              for (final id in platforms)
                if (id == _all)
                  TvTab(id: 'all', label: i18n('tv_all_platforms'), icon: TvIcons.allPlatforms, badge: rooms.length)
                else
                  TvTab(id: id, label: platformName(id), logo: id, badge: counts[id]),
            ],
            selected: platforms.indexOf(_platform),
            onSelect: (index) => setState(() => _platform = platforms[index]),
            onUp: () => _actions.currentState?.enter() ?? false,
            onDown: () => _dayTabs.currentState?.focusRemembered() ?? false,
          ),
        TvTabBar(
          key: _dayTabs,
          secondary: true,
          tabs: [
            TvTab(id: 'all-days', label: i18n('tv_history_all_days'), badge: ofPlatform.length),
            for (final (section, list) in sections)
              TvTab(id: section.name, label: historySectionTitle(section), badge: list.length),
          ],
          selected: day == null ? 0 : days.indexOf(day) + 1,
          onSelect: (index) => setState(() => _day = index == 0 ? null : days[index - 1]),
          onUp: () =>
              (_platformTabs.currentState?.focusRemembered() ?? false) || (_actions.currentState?.enter() ?? false),
          onDown: () => gridKey.currentState?.enter() ?? false,
        ),
        Expanded(
          child: TvRoomGrid(
            key: gridKey,
            rooms: shown,
            onLeaveUp: () => _dayTabs.currentState?.focusRemembered(),
            showPlatform: _platform == _all,
            detail: (room) => historyWatchedLabel(room.lastWatchedAt, now),
            actions: (room) => [
              TvRoomAction(
                key: const ValueKey('tv-history-delete'),
                icon: TvIcons.delete,
                label: i18n('tv_history_delete'),
                confirmTitle: i18n('tv_history_delete'),
                confirmMessage: i18n('tv_history_delete_message', args: {'name': roomLabel(room)}),
                onSelected: () => unawaited(ref.read(storeProvider).history.remove(room)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
