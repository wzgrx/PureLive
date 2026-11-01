import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// One tab of a [TvTabBar].
@immutable
final class TvTab {
  /// Creates a tab.
  const new({required this.id, required this.label, this.logo, this.icon, this.badge});

  /// Stable identity (the platform id, a group name).
  final String id;

  /// The text.
  final String label;

  /// A platform id whose logo leads the tab.
  final String? logo;

  /// An icon leading the tab.
  final IconData? icon;

  /// A count after the label.
  final int? badge;
}

/// A row of tabs for the remote (pure_live_TV `TvTabBar` in the style of
/// docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件): pills 36 high, the current one filled with the
/// primary container, the focused one ringed and grown; a count after the
/// label in equal-width figures. Walking across the tabs only moves the
/// focus, OK switches (so browsing does not load every platform), OK on the
/// current tab refreshes it, and a thin line shows while the content loads.
/// Down leaves for the content ([onDown]).
class TvTabBar extends StatefulWidget {
  /// Creates the bar.
  const new({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    this.onRefresh,
    this.onDown,
    this.onUp,
    this.onLeft,
    this.onRight,
    this.busy = false,
    this.small = false,
    this.secondary = false,
    super.key,
  });

  /// The tabs.
  final List<TvTab> tabs;

  /// The current tab.
  final int selected;

  /// OK on another tab.
  final ValueChanged<int> onSelect;

  /// OK on the current tab.
  final VoidCallback? onRefresh;

  /// Down from a tab: returns whether it moved the focus (else the focus
  /// moves by geometry).
  final bool Function()? onDown;

  /// Up returns to a parent filter row when supplied.
  final bool Function()? onUp;

  /// Left at the first tab; null leaves for the home rail by geometry.
  final bool Function()? onLeft;

  /// Right at the last tab; null keeps the focus at the row boundary.
  final bool Function()? onRight;

  /// The content is loading.
  final bool busy;

  /// The smaller row (32 high, 14): a second row under the main tabs.
  final bool small;

  /// The secondary look (A17.3 c6, an area's categories): words without
  /// pills, the selected one underlined, a rule under the row.
  final bool secondary;

  @override
  State<TvTabBar> createState() => TvTabBarState();
}

/// The bar's state: [focusSelected] puts the focus on the current tab.
class TvTabBarState extends State<TvTabBar> {
  final Map<String, FocusNode> _nodes = {};
  final ScrollController _scroll = ScrollController();
  String? _remembered;

  /// Puts the tab of [id] in the middle of the line (only this line
  /// scrolls), so the first and last are never cut at the screen's edge.
  void _center(String id) {
    final box = _node(id).context?.findRenderObject();
    if (box == null || !_scroll.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final position = _scroll.position;
    final offset = viewport
        .getOffsetToReveal(box, 0.5)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((offset - position.pixels).abs() > 0.5) _scroll.jumpTo(offset);
  }

  FocusNode _node(String id) => _nodes[id] ??= FocusNode(debugLabel: 'tab $id');

  /// Whether one of the tabs has the focus.
  bool get hasFocus => _nodes.values.any((node) => node.hasFocus);

  /// Focuses the current tab; false when there is none.
  bool focusSelected() {
    if (widget.tabs.isEmpty) return false;
    final tab = widget.tabs[widget.selected.clamp(0, widget.tabs.length - 1)];
    final node = _node(tab.id);
    if (node.context == null) return false;
    node.requestFocus();
    return true;
  }

  /// Restores the last focused tab, falling back to the selected one if
  /// that tab was removed (focus and selection are independent on TV).
  bool focusRemembered() {
    final previous = widget.tabs.where((tab) => tab.id == _remembered).firstOrNull;
    if (previous == null) return focusSelected();
    final node = _node(previous.id);
    if (node.context == null) return focusSelected();
    node.requestFocus();
    return true;
  }

  @override
  void didUpdateWidget(TvTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = {for (final tab in widget.tabs) tab.id};
    final gone = _nodes.keys.where((id) => !ids.contains(id)).toList();
    for (final id in gone) {
      _nodes.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      final index = widget.tabs.indexWhere((tab) => _nodes[tab.id] == node);
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final next = index + ((key == LogicalKeyboardKey.arrowRight) != rtl ? 1 : -1);
      if (index >= 0 && next >= 0 && next < widget.tabs.length) {
        _node(widget.tabs[next].id).requestFocus();
        return KeyEventResult.handled;
      }
      final boundary = key == LogicalKeyboardKey.arrowLeft ? widget.onLeft : widget.onRight;
      if (boundary != null) {
        boundary();
        return KeyEventResult.handled;
      }
      return key == LogicalKeyboardKey.arrowRight ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    final move = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => widget.onDown,
      LogicalKeyboardKey.arrowUp => widget.onUp,
      _ => null,
    };
    return move != null && move() ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final height = scale.pxText(widget.small ? 32 : 36);
    final fontSize = widget.small ? TvTextSize.small : TvTextSize.body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: scale.px(8), vertical: scale.px(6)),
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final (index, tab) in widget.tabs.indexed)
                Padding(
                  padding: EdgeInsets.only(right: scale.px(8)),
                  child: TvFocusable(
                    key: ValueKey('tv-tab-${tab.id}'),
                    focusNode: _node(tab.id),
                    radius: TvRadius.pill,
                    onKey: _key,
                    onFocusChange: (focused) {
                      if (focused) {
                        _remembered = tab.id;
                        _center(tab.id);
                      }
                    },
                    onTap: () => index == widget.selected ? widget.onRefresh?.call() : widget.onSelect(index),
                    builder: (context, focused) {
                      // Selected is a fill, focus is the ring (U.15a c3): the
                      // two read apart and can be on the same tab.
                      final selected = index == widget.selected;
                      if (widget.secondary) {
                        return Container(
                          height: height,
                          padding: EdgeInsets.symmetric(horizontal: scale.px(10)),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: selected ? palette.accent : OnVideoColors.clear,
                                width: scale.px(3),
                              ),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tab.label,
                            style: scale.font(
                              TvTextSize.small,
                              weight: selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? palette.accent : palette.textSecondary,
                            ),
                          ),
                        );
                      }
                      final foreground = selected ? palette.onSelected : palette.textSecondary;
                      return Container(
                        height: height,
                        padding: EdgeInsets.symmetric(horizontal: scale.px(widget.small ? 14 : 16)),
                        decoration: ShapeDecoration(
                          color: selected ? palette.selected : palette.card,
                          shape: const StadiumBorder(),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (tab.logo != null) ...[
                              PlatformLogo(tab.logo!, size: scale.pxText(20)),
                              SizedBox(width: scale.px(6)),
                            ] else if (tab.icon != null) ...[
                              Icon(tab.icon, size: scale.pxText(20), color: foreground),
                              SizedBox(width: scale.px(6)),
                            ],
                            Text(
                              tab.label,
                              style: scale.font(
                                fontSize,
                                weight: selected ? FontWeight.w600 : FontWeight.w400,
                                color: foreground,
                              ),
                            ),
                            if (tab.badge case final badge?) ...[
                              SizedBox(width: scale.px(6)),
                              Text(
                                '$badge',
                                key: ValueKey('tv-tab-${tab.id}-count'),
                                style: scale.font(TvTextSize.small, weight: FontWeight.w600, color: foreground).tabular,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        if (widget.secondary) Divider(height: scale.px(1), thickness: scale.px(1), color: palette.divider),
        // The refresh line under the tabs (pure_live_TV's, kept by c1).
        SizedBox(
          height: scale.px(3),
          child: widget.busy
              ? LinearProgressIndicator(
                  key: const ValueKey('tv-tabs-busy'),
                  color: palette.accent,
                  backgroundColor: palette.selected,
                  borderRadius: BorderRadius.circular(scale.px(2)),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
