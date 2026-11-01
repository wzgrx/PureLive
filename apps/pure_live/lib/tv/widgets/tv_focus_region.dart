import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Signals newly available focus targets without polling frames or timers.
class TvFocusReady extends InheritedWidget {
  /// Provides the owning destination's coalesced readiness callback.
  const new({required this.onReady, required super.child, super.key});

  /// A target was mounted or became enabled; the host decides whether to enter.
  final VoidCallback onReady;

  /// Lets a target notify its owner without subscribing to unrelated rebuilds.
  static void notify(BuildContext context) => context.getInheritedWidgetOfExactType<TvFocusReady>()?.onReady();

  @override
  bool updateShouldNotify(TvFocusReady oldWidget) => false;
}

/// Enters a region in reading order, excluding scopes, disabled and detached nodes.
bool tvFocusFirst(FocusNode region) {
  final nodes = region.traversalDescendants.where(
    (node) => node is! FocusScopeNode && node.context != null && node.context!.mounted && node.canRequestFocus,
  );
  final target = ReadingOrderTraversalPolicy.sort(nodes).firstOrNull;
  if (target == null) return false;
  target.requestFocus();
  return true;
}

/// Logical boundaries between rows/columns; children keep their own key handling.
class TvFocusRegion extends StatefulWidget {
  /// Creates an optional horizontal row and its explicit neighbouring regions.
  const new({
    required this.child,
    this.horizontal = false,
    this.onUp,
    this.onDown,
    this.onLeft,
    this.onRight,
    super.key,
  });

  /// Region content.
  final Widget child;

  /// Left/Right stay in this row unless an explicit neighbour is supplied.
  final bool horizontal;

  /// Logical upper neighbour, or a boundary when the callback does nothing.
  final VoidCallback? onUp;

  /// Logical lower neighbour.
  final VoidCallback? onDown;

  /// Left boundary; null retains the home rail's handling.
  final VoidCallback? onLeft;

  /// Right boundary; null keeps a horizontal row at its last item.
  final VoidCallback? onRight;

  @override
  State<TvFocusRegion> createState() => TvFocusRegionState();
}

/// Access to a region's stable entry target.
class TvFocusRegionState extends State<TvFocusRegion> {
  final FocusNode _region = FocusNode(skipTraversal: true, canRequestFocus: false);

  /// Enters the first currently enabled control in reading order.
  bool enter() => tvFocusFirst(_region);

  @override
  void dispose() {
    _region.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (widget.horizontal && (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight)) {
      final nodes = ReadingOrderTraversalPolicy.sort(
        _region.traversalDescendants.where((node) => node is! FocusScopeNode && node.context != null),
      ).toList();
      final index = nodes.indexWhere((node) => node.hasPrimaryFocus);
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final next = index + ((key == LogicalKeyboardKey.arrowRight) != rtl ? 1 : -1);
      if (index >= 0 && next >= 0 && next < nodes.length) {
        nodes[next].requestFocus();
        return KeyEventResult.handled;
      }
      final boundary = key == LogicalKeyboardKey.arrowLeft ? widget.onLeft : widget.onRight;
      if (boundary != null) boundary();
      return boundary != null || key == LogicalKeyboardKey.arrowRight ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    final move = switch (key) {
      LogicalKeyboardKey.arrowUp => widget.onUp,
      LogicalKeyboardKey.arrowDown => widget.onDown,
      LogicalKeyboardKey.arrowLeft => widget.onLeft,
      LogicalKeyboardKey.arrowRight => widget.onRight,
      _ => null,
    };
    if (move == null) return KeyEventResult.ignored;
    move();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _region, canRequestFocus: false, skipTraversal: true, onKeyEvent: _key, child: widget.child);
}
