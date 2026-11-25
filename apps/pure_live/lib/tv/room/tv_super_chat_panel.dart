import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/live_play/danmaku/super_chat_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';

/// The same super-chat panel with remote scrolling, without channel keys.
class TvSuperChatPanel extends StatefulWidget {
  /// Creates the panel.
  const new({required this.controller, required this.onClose, this.focusNode, super.key});

  /// The current room; the panel never opens another playback session.
  final LiveRoomController controller;

  /// Closes only the panel.
  final VoidCallback onClose;

  /// The page focuses this after mounting the panel.
  final FocusNode? focusNode;

  @override
  State<TvSuperChatPanel> createState() => _TvSuperChatPanelState();
}

class _TvSuperChatPanelState extends State<TvSuperChatPanel> {
  final ScrollController _scroll = ScrollController();
  final FocusNode _history = FocusNode(debugLabel: 'tv super chat history');

  @override
  void dispose() {
    _scroll.dispose();
    _history.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      _history.requestFocus();
      return KeyEventResult.handled;
    }
    final down = key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.pageDown;
    final up = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp;
    if (!down && !up) return KeyEventResult.ignored;
    if (up && (!_scroll.hasClients || _scroll.offset == 0)) {
      _history.requestFocus();
      return KeyEventResult.handled;
    }
    widget.focusNode?.requestFocus();
    if (_scroll.hasClients) {
      final page = key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.pageUp;
      final step = page ? _scroll.position.viewportDimension * 0.8 : 120.0;
      _scroll.jumpTo((_scroll.offset + (down ? step : -step)).clamp(0.0, _scroll.position.maxScrollExtent));
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = TvScale.of(context).px(1);
    // Scale the shared panel's complete canvas, including its header and
    // hit targets. Scaling only text clips the fixed-height header at 4K.
    return LayoutBuilder(
      builder: (context, bounds) => FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: bounds.maxWidth / scale,
          height: bounds.maxHeight / scale,
          child: MediaQuery(
            data: media.copyWith(
              size: media.size / scale,
              padding: media.padding / scale,
              viewPadding: media.viewPadding / scale,
              viewInsets: media.viewInsets / scale,
            ),
            child: Focus(
              focusNode: widget.focusNode,
              autofocus: true,
              onKeyEvent: _key,
              child: RoomSuperChatPanel(
                key: const ValueKey('panel-super-chats'),
                controller: widget.controller,
                scrollController: _scroll,
                historyControlBuilder: ({required shown, required toggle}) => TvButton(
                  key: const ValueKey('super-chat-history-toggle'),
                  focusNode: _history,
                  label: i18n(shown ? 'super_chat_hide_history' : 'super_chat_show_history'),
                  icon: AppIcons.watchHistory,
                  onTap: toggle,
                ),
                onClose: widget.onClose,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
