import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/super_chat_panel.dart';
import 'package:pure_live/features/live_play/danmaku/super_chat_unread.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/player/player_controls.dart';
import 'package:pure_live/i18n/i18n.dart';

/// A small fullscreen entry while the room has active paid messages.
class FullscreenSuperChatButton extends ConsumerWidget {
  /// Creates the entry.
  const new({required this.controller, super.key});

  /// The current room.
  final LiveRoomController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!watchSetting(ref, Settings.showFullscreenSuperChat)) return const SizedBox.shrink();
    return ListenableSelector<(bool, int)>(
      listenable: controller,
      selector: () => (controller.superChats.isNotEmpty, controller.unreadSuperChatCount),
      builder: (context, state, _) {
        final (active, unread) = state;
        if (!active) return const SizedBox.shrink();
        return Material(
          color: OnVideoColors.scrim,
          shape: const CircleBorder(),
          child: VideoIconButton(
            key: const ValueKey('live-play-fullscreen-super-chat'),
            tooltip: i18n('super_chat'),
            icon: SuperChatUnreadBadge(count: unread, child: const Icon(AppIcons.superChatMark)),
            onPressed: () {
              final panels = RoomPanelScope.maybeOf(context);
              if (panels != null) {
                panels.open(RoomPanelKind.superChat);
              } else {
                unawaited(
                  showRoomPanelSheet(
                    context,
                    builder: (context, close) => RoomSuperChatPanel(controller: controller, onClose: close),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }
}
