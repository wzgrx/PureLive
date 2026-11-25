import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/tv_navigation.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_grid.dart';
import 'package:pure_live/tv/widgets/tv_room_dialog.dart';

/// A follow that is off air as a compact row (A17.3 c3, C3 A; the phone's
/// A09.3): the avatar, the streamer, the platform and the last title.
class TvRoomRow extends StatelessWidget {
  /// Creates the row of [room].
  const new({required this.room, this.subtitle, this.onTap, this.onLongPress, this.onKey, this.focusNode, super.key});

  /// The room.
  final LiveRoom room;

  /// The second line instead of the last title (a streamer found by
  /// search: "正在直播" / "未直播").
  final String? subtitle;

  /// OK.
  final VoidCallback? onTap;

  /// A held OK or the menu key.
  final VoidCallback? onLongPress;

  /// Keys first (the grid).
  final TvKeyHandler? onKey;

  /// The grid's node.
  final FocusNode? focusNode;

  /// The height of a row at [scale].
  static double heightFor(TvScale scale) => scale.px(24) + scale.pxText((TvTextSize.body + TvTextSize.small) * 1.4);

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final name = room.displayNick(platformName(room.platform));
    return TvFocusable(
      focusNode: focusNode,
      onTap: onTap,
      onLongPress: onLongPress,
      onKey: onKey,
      zoom: false,
      builder: (context, focused) => Container(
        padding: EdgeInsets.symmetric(horizontal: scale.px(16), vertical: scale.px(12)),
        decoration: BoxDecoration(
          color: focused ? palette.raised : palette.card,
          borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
        ),
        child: Row(
          children: [
            CommonAvatar(avatarUrl: room.avatar, fallbackName: name, radius: scale.pxText(20)),
            SizedBox(width: scale.px(16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: scale.font(TvTextSize.body, weight: FontWeight.w600, color: palette.text, height: 1.4),
                        ),
                      ),
                      SizedBox(width: scale.px(8)),
                      PlatformLogo(room.platform, size: scale.pxText(18)),
                    ],
                  ),
                  Text(
                    subtitle ?? room.title.trim(),
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

/// [rooms] as compact rows, two to a line (C3 A), on the TV grid (moves by
/// index, remembers the focus); OK opens a room with the list as the
/// channel list, a held OK opens the card dialog.
class TvRoomRows extends ConsumerStatefulWidget {
  /// Creates the rows.
  const new({required this.rooms, this.onLeaveUp, this.onEndReached, this.subtitleOf, super.key});

  /// The rooms.
  final List<LiveRoom> rooms;

  /// Up on the first line.
  final VoidCallback? onLeaveUp;

  /// Near the last line (load more).
  final VoidCallback? onEndReached;

  /// The second line of a room ([TvRoomRow.subtitle]).
  final String Function(LiveRoom room)? subtitleOf;

  @override
  ConsumerState<TvRoomRows> createState() => TvRoomRowsState();
}

/// The rows' state: [enter] puts the focus in.
class TvRoomRowsState extends ConsumerState<TvRoomRows> {
  final GlobalKey<TvGridState> _grid = GlobalKey();

  /// Focuses the row focused last, else the first.
  bool enter() => _grid.currentState?.enter() ?? false;

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = scale.px(16);
        final width = (constraints.maxWidth - scale.px(24) - spacing) / 2;
        return TvGrid(
          key: _grid,
          itemCount: widget.rooms.length,
          columns: 2,
          aspectRatio: width > 0 ? width / TvRoomRow.heightFor(scale) : 4,
          crossSpacing: spacing,
          mainSpacing: spacing,
          onLeaveUp: widget.onLeaveUp,
          onEndReached: widget.onEndReached,
          itemBuilder: (context, index, node, onKey) {
            final room = widget.rooms[index];
            return TvRoomRow(
              key: ValueKey('tv-room-row-${room.identityKey}'),
              room: room,
              subtitle: widget.subtitleOf?.call(room),
              focusNode: node,
              onKey: onKey,
              onTap: () => unawaited(openTvRoom(room, playlist: widget.rooms)),
              onLongPress: () => unawaited(showTvRoomDialog(context, store: ref.read(storeProvider), room: room)),
            );
          },
        );
      },
    );
  }
}
