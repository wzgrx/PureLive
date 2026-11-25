import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/live_play/danmaku/super_chat_unread.dart';
import 'package:pure_live/features/live_play/danmaku/super_chats.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The room's existing super-chat list alongside fullscreen video.
class RoomSuperChatPanel extends StatelessWidget {
  /// Creates the panel without another session or message store.
  const new({
    required this.controller,
    required this.onClose,
    this.dragToClose = false,
    this.scrollController,
    this.historyControlBuilder,
    super.key,
  });

  /// The current room and its session history.
  final LiveRoomController controller;

  /// Closes only this panel.
  final VoidCallback onClose;

  /// Portrait panels can be dragged down.
  final bool dragToClose;

  /// Optional external scrolling, used by the TV remote.
  final ScrollController? scrollController;

  /// Optional input-specific control for the list's own history switch.
  final Widget Function({required bool shown, required VoidCallback toggle})? historyControlBuilder;

  @override
  Widget build(BuildContext context) => RoomSidePanel(
    title: i18n('super_chat'),
    onClose: onClose,
    dragToClose: dragToClose,
    child: ListenableSelector<(List<LiveSuperChatMessage>, List<LiveSuperChatMessage>)>(
      listenable: controller,
      selector: () => (controller.superChats, controller.superChatHistory),
      builder: (context, messages, _) => SuperChatReadScope(
        controller: controller,
        child: SuperChatList(
          key: ObjectKey(controller),
          messages: messages.$1,
          history: messages.$2,
          scrollController: scrollController,
          historyControlBuilder: historyControlBuilder,
          now: controller.now,
          platformName: platformName(controller.site.id, fallback: controller.site.name),
          platformHasSuperChats: controller.site.hasSuperChats,
        ),
      ),
    ),
  );
}
