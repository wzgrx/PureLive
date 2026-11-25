import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/video/video_store.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_grid.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';

// The pieces every video page shares (A17.6 c5–c7, c16): one card, one
// paged grid with the A17.1 states, one card menu.

/// "1:02:03" / "12:34".
String videoClock(Duration value) {
  final seconds = value.inSeconds.abs();
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// A count in the platform's words ("12.3万").
String videoCount(int value) {
  if (value >= 100000000) return '${(value / 100000000).toStringAsFixed(1)}亿';
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return '$value';
}

/// What a video card shows.
@immutable
final class TvVideoCardData {
  /// Creates the data.
  const new({
    required this.title,
    required this.cover,
    this.subtitle = '',
    this.duration,
    this.badge = '',
    this.progress,
  });

  /// An archive's card: its uploader and views, its length, and how far it
  /// was watched here ([progress], 0–1).
  factory archive(VodArchive archive, {double? progress}) => TvVideoCardData(
    title: archive.title,
    cover: archive.cover,
    subtitle: [
      if (archive.owner.name.isNotEmpty) archive.owner.name,
      if (archive.stat.views > 0) i18n('tv_video_views', args: {'count': videoCount(archive.stat.views)}),
    ].join(' · '),
    duration: archive.duration > Duration.zero ? archive.duration : null,
    progress: progress,
  );

  /// A season's card (c5: the same frame): its update line and badge.
  factory season(PgcCard card) => TvVideoCardData(
    title: card.title,
    cover: card.cover,
    subtitle: [
      if (card.indexShow.isNotEmpty) card.indexShow,
      if (card.score.isNotEmpty) i18n('tv_video_score', args: {'score': card.score}),
    ].join(' · '),
    badge: card.badge,
  );

  /// The title.
  final String title;

  /// The cover.
  final String cover;

  /// The line under the title.
  final String subtitle;

  /// The length (bottom right of the cover).
  final Duration? duration;

  /// The platform's badge (会员, 独家…), top right.
  final String badge;

  /// How far it was watched (a line on the cover's bottom edge).
  final double? progress;
}

/// The video card (c5): the room card's frame and focus (A17.1) — a 16:9
/// cover with the length, the badge and the watched part, then the title
/// (it scrolls while focused) and one line.
class TvVideoCard extends StatelessWidget {
  /// Creates the card.
  const new({required this.data, this.onTap, this.onLongPress, this.onKey, this.focusNode, super.key});

  /// What it shows.
  final TvVideoCardData data;

  /// OK.
  final VoidCallback? onTap;

  /// A held OK or the menu key (c16).
  final VoidCallback? onLongPress;

  /// Keys first (the grid).
  final TvKeyHandler? onKey;

  /// The node (the grid's).
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final radius = Radius.circular(scale.px(TvRadius.card));
    final progress = data.progress;
    return TvFocusable(
      focusNode: focusNode,
      onTap: onTap,
      onLongPress: onLongPress,
      onKey: onKey,
      builder: (context, focused) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: focused ? palette.raised : palette.card,
          borderRadius: BorderRadius.all(radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TvCover(url: data.cover),
                  if (data.badge.isNotEmpty)
                    Positioned(
                      right: scale.px(8),
                      top: scale.px(8),
                      child: TvCoverChip(key: const ValueKey('tv-video-badge'), label: data.badge),
                    ),
                  if (data.duration case final duration?)
                    Positioned(
                      right: scale.px(8),
                      bottom: scale.px(8),
                      child: TvCoverChip(
                        key: const ValueKey('tv-video-duration'),
                        label: videoClock(duration),
                        tabular: true,
                      ),
                    ),
                  if (progress != null && progress > 0)
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: FractionallySizedBox(
                        key: const ValueKey('tv-video-progress'),
                        widthFactor: progress.clamp(0, 1).toDouble(),
                        child: SizedBox(
                          height: scale.px(6),
                          child: ColoredBox(color: palette.accent),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: scale.px(12), vertical: scale.px(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvMarquee(
                    text: data.title,
                    running: focused,
                    style: scale.font(TvTextSize.body, weight: FontWeight.w600, color: palette.text, height: 1.4),
                  ),
                  Text(
                    data.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: scale.font(TvTextSize.small, color: palette.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One page of a feed: the items and whether more follow.
typedef VideoPageResult<T> = ({List<T> items, bool hasMore});

/// A list that loads a page at a time (A17.1 c14 states: the first load,
/// a failure with its cause, empty).
final class TvPagedFeed<T> extends ChangeNotifier {
  /// Creates the feed over the loader (pages from 1).
  new(this._load);

  final Future<VideoPageResult<T>> Function(int page) _load;

  /// The items so far.
  final List<T> items = [];

  /// Whether the first page came.
  bool loaded = false;

  /// A page is loading.
  bool busy = false;

  /// The last failure, if the last load failed.
  Object? error;

  /// Whether more pages follow.
  bool hasMore = true;

  int _page = 0;
  bool _disposed = false;

  /// Loads the first page unless it is loaded.
  Future<void> open() => loaded || busy ? Future.value() : more();

  /// Loads the next page.
  Future<void> more() async {
    if (busy || !hasMore || _disposed) return;
    busy = true;
    _notify();
    try {
      final result = await _load(_page + 1);
      if (_disposed) return;
      _page++;
      items.addAll(result.items);
      hasMore = result.hasMore && result.items.isNotEmpty;
      error = null;
    } on Object catch (failure) {
      error = failure;
    } finally {
      loaded = true;
      busy = false;
      _notify();
    }
  }

  /// Starts over.
  Future<void> refresh() async {
    if (busy) return;
    items.clear();
    _page = 0;
    hasMore = true;
    loaded = false;
    error = null;
    await more();
  }

  /// Removes [item] (a deleted history row).
  void remove(T item) {
    items.remove(item);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// One action of a card's menu (c16: written out; c17: some ask first).
@immutable
final class TvVideoAction {
  /// Creates the action.
  const new({required this.id, required this.icon, required this.label, required this.run, this.confirm});

  /// Its id (the menu row's key `tv-video-action-<id>`).
  final String id;

  /// Its icon.
  final IconData icon;

  /// What it does.
  final String label;

  /// Does it.
  final Future<void> Function() run;

  /// Asked first (title, message), null for none.
  final (String, String)? confirm;
}

/// The card menu (A17.1 c9's dialog): [title] over the actions written out;
/// an action that asks first does after "确定".
Future<void> showTvVideoMenu(
  BuildContext context, {
  required String title,
  required List<TvVideoAction> actions,
}) async {
  if (actions.isEmpty) return;
  final picked = await showTvChoice<TvVideoAction>(
    context,
    title: title,
    options: [for (final action in actions) TvChoice(value: action, label: action.label, icon: action.icon)],
  );
  if (picked == null || !context.mounted) return;
  if (picked.confirm case (final confirmTitle, final message)) {
    final yes = await showTvConfirm(
      context,
      title: confirmTitle,
      message: message,
      confirmLabel: picked.label,
      danger: true,
    );
    if (!yes) return;
  }
  await picked.run();
}

/// A grid of [feed]'s items as video cards, four to a row (c2), with the
/// states of A17.1 c14; the next page loads near the end.
class TvVideoGrid<T> extends ConsumerStatefulWidget {
  /// Creates the grid.
  const new({
    required this.feed,
    required this.cardOf,
    required this.onOpen,
    this.actionsOf,
    this.menuTitleOf,
    this.onLeaveUp,
    this.emptyTitle,
    this.emptyHint,
    super.key,
  });

  /// The items.
  final TvPagedFeed<T> feed;

  /// The card of an item.
  final TvVideoCardData Function(T item, VideoStore store) cardOf;

  /// OK on an item.
  final void Function(T item, int index) onOpen;

  /// The card menu's actions (none: no menu).
  final List<TvVideoAction> Function(T item)? actionsOf;

  /// The card menu's title.
  final String Function(T item)? menuTitleOf;

  /// Up on the first row (the tabs).
  final VoidCallback? onLeaveUp;

  /// What an empty list says.
  final String? emptyTitle;

  /// What to do then.
  final String? emptyHint;

  @override
  ConsumerState<TvVideoGrid<T>> createState() => TvVideoGridState<T>();
}

/// The video grid's state: [enter] puts the focus in.
class TvVideoGridState<T> extends ConsumerState<TvVideoGrid<T>> {
  final GlobalKey<TvGridState> _grid = GlobalKey();

  /// Focuses the card focused last, else the first; false when empty.
  bool enter() => _grid.currentState?.enter() ?? false;

  @override
  void initState() {
    super.initState();
    // Not while building: the feed tells its listeners at once.
    scheduleMicrotask(() {
      if (mounted) unawaited(widget.feed.open());
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(videoStoreProvider);
    final scale = TvScale.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.feed, store]),
      builder: (context, _) {
        final feed = widget.feed;
        if (feed.items.isEmpty) {
          if (!feed.loaded || feed.busy) return const TvSkeletonGrid();
          if (feed.error != null) {
            return TvStatusView.failure(feed.error, onRetry: () => unawaited(feed.refresh()));
          }
          return TvStatusView(
            icon: TvIcons.noResults,
            title: widget.emptyTitle ?? i18n('tv_video_empty'),
            subtitle: widget.emptyHint,
            actions: [
              TvStatusAction(icon: AppIcons.refresh, label: i18n('tv_refresh'), onTap: () => unawaited(feed.refresh())),
            ],
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            const columns = 4;
            final spacing = scale.px(26);
            final width = (constraints.maxWidth - scale.px(24) - spacing * (columns - 1)) / columns;
            return TvGrid(
              key: _grid,
              itemCount: feed.items.length,
              columns: columns,
              aspectRatio: width > 0 ? width / TvRoomCard.heightFor(width, scale) : 1.2,
              crossSpacing: spacing,
              mainSpacing: spacing,
              onLeaveUp: widget.onLeaveUp,
              onEndReached: () => unawaited(feed.more()),
              itemBuilder: (context, index, node, onKey) {
                final item = feed.items[index];
                final actions = widget.actionsOf;
                return TvVideoCard(
                  key: ValueKey('tv-video-card-$index'),
                  data: widget.cardOf(item, store),
                  focusNode: node,
                  onKey: onKey,
                  onTap: () => widget.onOpen(item, index),
                  onLongPress: actions == null
                      ? null
                      : () => unawaited(
                          showTvVideoMenu(context, title: widget.menuTitleOf?.call(item) ?? '', actions: actions(item)),
                        ),
                );
              },
            );
          },
        );
      },
    );
  }
}
