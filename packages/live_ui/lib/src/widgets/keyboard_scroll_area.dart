import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:live_ui/src/theme/metrics.dart';
import 'package:live_ui/src/widgets/focus_ring.dart';
import 'package:material_ui/material_ui.dart';

/// A keyboard target for a long read-only scroll view. Arrows scroll while
/// the viewport itself has focus; Right enters its controls and Left returns
/// to the viewport after the focused control declines the key.
class KeyboardScrollArea extends StatefulWidget {
  /// Wraps the scroll view attached to [controller].
  const new({
    required this.controller,
    required this.label,
    required this.child,
    this.autofocus = false,
    this.ringColor,
    super.key,
  });

  /// The wrapped scroll view's controller.
  final ScrollController controller;

  /// The viewport's accessible name.
  final String label;

  /// The scrolling content, including its interactive descendants.
  final Widget child;

  /// Takes focus when the read-only content first arrives.
  final bool autofocus;

  /// The enclosing shell's focus ring color.
  final Color? ringColor;

  @override
  State<KeyboardScrollArea> createState() => _KeyboardScrollAreaState();
}

class _KeyboardScrollAreaState extends State<KeyboardScrollArea> {
  final FocusNode _focus = FocusNode(debugLabel: 'settings keyboard scroll');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (!_focus.hasPrimaryFocus) {
      if (key != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
      _focus.requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select) {
      final first = _focus.traversalDescendants.where((child) => child is! FocusScopeNode).firstOrNull;
      if (first == null) return KeyEventResult.ignored;
      first.requestFocus();
      return KeyEventResult.handled;
    }
    final controller = widget.controller;
    if (!controller.hasClients) return KeyEventResult.ignored;
    final position = controller.position;
    final step = math.max(48, position.viewportDimension / 4);
    final target = switch (key) {
      LogicalKeyboardKey.arrowDown => position.pixels + step,
      LogicalKeyboardKey.arrowUp => position.pixels - step,
      LogicalKeyboardKey.pageDown => position.pixels + position.viewportDimension * 0.8,
      LogicalKeyboardKey.pageUp => position.pixels - position.viewportDimension * 0.8,
      LogicalKeyboardKey.home => position.minScrollExtent,
      LogicalKeyboardKey.end => position.maxScrollExtent,
      _ => null,
    };
    if (target == null) return KeyEventResult.ignored;
    final bounded = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (bounded != position.pixels) {
      controller.animateTo(bounded, duration: const Duration(milliseconds: 160), curve: Curves.easeOut).ignore();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      onKeyEvent: _key,
      onFocusChange: (_) => setState(() {}),
      child: CustomPaint(
        foregroundPainter: _focus.hasPrimaryFocus
            ? FocusRingPainter(
                color: widget.ringColor ?? Theme.of(context).colorScheme.primary,
                borderRadius: AppRadii.button,
                gap: -3,
              )
            : null,
        child: widget.child,
      ),
    ),
  );
}
