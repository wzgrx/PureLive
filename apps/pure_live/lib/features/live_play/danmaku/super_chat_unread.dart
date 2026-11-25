import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The same unread count on touch, desktop and TV entries.
class SuperChatUnreadBadge extends StatelessWidget {
  /// Creates a badge; zero leaves the original child unchanged.
  const new({required this.count, required this.child, this.scale = 1, super.key});

  /// Active messages that have not been viewed.
  final int count;

  /// The original entry icon or TV button.
  final Widget child;

  /// TV canvas scale; ordinary layouts use logical pixels directly.
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final theme = Theme.of(context);
    return Semantics(
      label: i18n('super_chat_unread_count', args: {'count': '$count'}),
      child: Badge(
        key: const ValueKey('super-chat-unread-badge'),
        label: ExcludeSemantics(child: Text(count > 99 ? '99+' : '$count')),
        backgroundColor: theme.colorScheme.primary,
        textColor: theme.colorScheme.onPrimary,
        textStyle: theme.textTheme.labelSmall?.copyWith(fontSize: 12 * scale),
        largeSize: 18 * scale,
        padding: EdgeInsets.symmetric(horizontal: 4 * scale),
        child: child,
      ),
    );
  }
}

/// Reads messages after their visible list has reached a frame. Offscreen tabs,
/// covered routes and outgoing layouts do not consume another layout's badge.
class SuperChatReadScope extends StatefulWidget {
  /// Creates a view of the room's shared unread state.
  const new({required this.controller, required this.child, this.visible = true, super.key});

  /// The room whose messages are being viewed.
  final LiveRoomController controller;

  /// The rendered list.
  final Widget child;

  /// Whether this is the selected tab and not covered by the room details.
  final bool visible;

  @override
  State<SuperChatReadScope> createState() => _SuperChatReadScopeState();
}

class _SuperChatReadScopeState extends State<SuperChatReadScope> {
  bool _scheduled = false;
  bool _presented = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scheduleRead);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _presented = TickerMode.valuesOf(context).enabled && (ModalRoute.isCurrentOf(context) ?? true);
    _scheduleRead();
  }

  @override
  void didUpdateWidget(SuperChatReadScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_scheduleRead);
      widget.controller.addListener(_scheduleRead);
    }
    _scheduleRead();
  }

  void _scheduleRead() {
    if (_scheduled || !widget.visible || !_presented || widget.controller.unreadSuperChatCount == 0) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted && widget.visible && _presented) widget.controller.markSuperChatsRead();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scheduleRead);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
