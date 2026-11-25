import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_settings_rows.dart';

/// One entry of a [TvOrderEditor].
@immutable
final class TvOrderItem {
  /// Creates the entry.
  const new({required this.id, required this.label, this.icon});

  /// What is stored.
  final String id;

  /// The words.
  final String label;

  /// The icon.
  final IconData? icon;
}

/// Which entries show and in what order, on one page (A17.9 c11, the
/// phone's one page of switches and dragging): OK shows or hides an entry
/// (the last one shown cannot be hidden, [lastShownMessage]); a held OK or
/// the menu key picks it up, ↑↓ move it, OK puts it down and Back puts it
/// back where it was. Every change goes to [onChanged] at once (the order
/// of all entries, the hidden ones).
class TvOrderEditor extends StatefulWidget {
  /// Creates the editor; [items] in their current order.
  const new({
    required this.items,
    required this.hidden,
    required this.onChanged,
    required this.lastShownMessage,
    super.key,
  });

  /// The entries, in order.
  final List<TvOrderItem> items;

  /// The ids hidden.
  final Set<String> hidden;

  /// Stores a change.
  final void Function(List<String> order, Set<String> hidden) onChanged;

  /// Said when the last entry shown would be hidden.
  final String lastShownMessage;

  @override
  State<TvOrderEditor> createState() => _TvOrderEditorState();
}

class _TvOrderEditorState extends State<TvOrderEditor> {
  late List<String> _order = [for (final item in widget.items) item.id];
  late Set<String> _hidden = {...widget.hidden};
  final Map<String, FocusNode> _nodes = {};
  String? _moving;
  List<String>? _before;

  FocusNode _node(String id) => _nodes[id] ??= FocusNode(debugLabel: 'tv order $id');

  @override
  void didUpdateWidget(TvOrderEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_moving == null) {
      _order = [for (final item in widget.items) item.id];
      _hidden = {...widget.hidden};
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _toggle(String id) {
    if (_moving != null) {
      _drop();
      return;
    }
    final hide = !_hidden.contains(id);
    if (hide && _order.where((other) => !_hidden.contains(other)).length <= 1) {
      AppNavigator.toast(widget.lastShownMessage);
      return;
    }
    setState(() => hide ? _hidden.add(id) : _hidden.remove(id));
    widget.onChanged(List.of(_order), {..._hidden});
  }

  void _pickUp(String id) {
    if (_moving != null) return;
    setState(() {
      _moving = id;
      _before = List.of(_order);
    });
  }

  void _drop() {
    setState(() {
      _moving = null;
      _before = null;
    });
    widget.onChanged(List.of(_order), {..._hidden});
  }

  void _cancel() {
    final id = _moving;
    setState(() {
      _order = _before ?? _order;
      _moving = null;
      _before = null;
    });
    if (id != null) WidgetsBinding.instance.addPostFrameCallback((_) => _nodes[id]?.requestFocus());
  }

  KeyEventResult _key(String id, KeyEvent event) {
    if (_moving != id || (event is! KeyDownEvent && event is! KeyRepeatEvent)) return KeyEventResult.ignored;
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowRight => 0,
      LogicalKeyboardKey.escape || LogicalKeyboardKey.goBack => null,
      _ => 2,
    };
    if (step == null) {
      _cancel();
      return KeyEventResult.handled;
    }
    if (step == 2) return KeyEventResult.ignored;
    final at = _order.indexOf(id);
    final to = at + step;
    if (step != 0 && to >= 0 && to < _order.length) {
      setState(() {
        _order
          ..removeAt(at)
          ..insert(to, id);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _nodes[id]?.requestFocus());
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final items = {for (final item in widget.items) item.id: item};
    return PopScope(
      // Back while moving puts the entry back (and stays on the page).
      canPop: _moving == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(left: scale.px(16), bottom: scale.px(12)),
            child: Text(
              _moving == null ? i18n('tv_order_hint') : i18n('tv_order_moving_hint'),
              key: const ValueKey('tv-order-hint'),
              style: scale.font(TvTextSize.small, color: palette.textSecondary, height: 1.4),
            ),
          ),
          TvSettingsGroup(
            children: [
              for (final id in _order)
                if (items[id] case final item?)
                  TvSettingsRow(
                    key: ValueKey('tv-order-$id'),
                    id: 'order-$id',
                    focusNode: _node(id),
                    icon: item.icon,
                    title: item.label,
                    subtitle: _moving == id
                        ? i18n('tv_order_moving')
                        : _hidden.contains(id)
                        ? i18n('tv_order_hidden')
                        : null,
                    trailing: (context, focused) => Icon(
                      _moving == id
                          ? TvIcons.menuMoving
                          : _hidden.contains(id)
                          ? TvIcons.menuHidden
                          : TvIcons.menuShown,
                      size: scale.pxText(24),
                      color: _moving == id
                          ? palette.accent
                          : _hidden.contains(id)
                          ? palette.textSecondary
                          : palette.text,
                    ),
                    onTap: () => _toggle(id),
                    onLongPress: () => _pickUp(id),
                    onKey: (node, event) => _key(id, event),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}
