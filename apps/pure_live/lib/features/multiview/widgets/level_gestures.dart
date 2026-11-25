import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/platform/device_controls.dart';

/// Landscape picture gestures: left brightness, right the selected cell's volume.
class MultiviewLevelGestures extends StatefulWidget {
  /// Wraps the wall without replacing its cell keys or video widgets.
  const new({
    required this.controller,
    required this.selectedIndex,
    required this.enabled,
    required this.child,
    super.key,
  });

  /// Playback and per-cell volume controls.
  final MultiviewController controller;

  /// Cell selected by the page's controls.
  final int selectedIndex;

  /// Enabled only for a visible landscape mobile picture with no open panel.
  final bool enabled;

  /// The existing picture wall and its tap/long-press handling.
  final Widget child;
  @override
  State<MultiviewLevelGestures> createState() => _MultiviewLevelGesturesState();
}

class _MultiviewLevelGesturesState extends State<MultiviewLevelGestures> {
  Offset? _down;
  Offset? _pointer;
  bool? _brightness;
  int? _cellId;
  String? _roomKey;
  int _epoch = 0;
  double? _base;
  double? _shown;
  double _delta = 0;
  bool _ended = false;
  bool _changedBrightness = false;
  final Set<int> _pointers = {};
  bool _multiple = false;
  Timer? _hide;
  int? _frame;
  double? _unsent;

  @override
  void didUpdateWidget(MultiviewLevelGestures oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _cancel();
  }

  int get _target =>
      widget.controller.cells.indexWhere((cell) => cell.id == _cellId && cell.room?.identityKey == _roomKey);
  bool get _horizontal {
    final from = _down;
    final to = _pointer;
    return from != null && to != null && (to.dx - from.dx).abs() > (to.dy - from.dy).abs();
  }

  void _cancel() {
    _epoch++;
    _brightness = null;
    _base = null;
    _unsent = null;
    if (_frame case final id?) SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    _frame = null;
  }

  Future<void> _start(DragStartDetails details) async {
    if (!widget.enabled || _horizontal || _multiple) return;
    final epoch = ++_epoch;
    final size = context.size;
    if (size == null) return;
    _brightness = details.localPosition.dx < size.width / 2;
    _base = null;
    _delta = 0;
    _ended = false;
    if (_brightness!) {
      if (!DeviceControls.available) {
        _cancel();
        return;
      }
      final value = await DeviceControls.brightness();
      if (!mounted || epoch != _epoch || !widget.enabled) return;
      if (value == null) {
        _cancel();
        return;
      }
      _base = value;
    } else {
      final cells = widget.controller.cells;
      final index = widget.selectedIndex;
      if (index < 0 || index >= cells.length || !cells[index].playing) {
        _cancel();
        return;
      }
      _cellId = cells[index].id;
      _roomKey = cells[index].room?.identityKey;
      _base = cells[index].volume;
    }
    if (_delta != 0) {
      _queue();
      if (_ended) _commit();
    }
  }

  void _update(DragUpdateDetails details) {
    if (_brightness == null) return;
    if (_horizontal) {
      _cancel();
      return;
    }
    final height = context.size?.height ?? 0;
    if (height <= 0) return;
    _delta -= details.delta.dy / height * 1.2;
    if (_base != null) _queue();
  }

  void _queue() {
    final value = (_base! + _delta).clamp(0.0, 1.0);
    _hide?.cancel();
    setState(() => _shown = value);
    _unsent = value;
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      _send();
    });
    _hide = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _shown = null);
    });
  }

  void _send() {
    final value = _unsent;
    _unsent = null;
    if (value == null || !mounted || !widget.enabled) return;
    if (_brightness == true) {
      _changedBrightness = true;
      unawaited(DeviceControls.setBrightness(value));
    } else if (_target >= 0) {
      unawaited(widget.controller.setVolume(_target, value));
    }
  }

  void _commit() {
    _send();
    if (_brightness == false && _target >= 0 && _shown != null) {
      unawaited(widget.controller.setVolume(_target, _shown!, save: true));
    }
  }

  @override
  void dispose() {
    _cancel();
    _hide?.cancel();
    if (_changedBrightness) unawaited(DeviceControls.resetBrightness());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (event) {
        _pointers.add(event.pointer);
        if (_pointers.length > 1) {
          _multiple = true;
          _cancel();
        }
      },
      onPointerUp: (event) {
        _pointers.remove(event.pointer);
        if (_pointers.isEmpty) _multiple = false;
      },
      onPointerMove: (event) => _pointer = event.position,
      onPointerCancel: (event) {
        _pointers.remove(event.pointer);
        if (_pointers.isEmpty) _multiple = false;
        _cancel();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragDown: (details) {
          _down = details.globalPosition;
          _pointer = details.globalPosition;
        },
        onHorizontalDragStart: (_) => _cancel(),
        onVerticalDragStart: (details) => unawaited(_start(details)),
        onVerticalDragUpdate: _update,
        onVerticalDragEnd: (_) {
          _ended = true;
          if (_base != null) _commit();
        },
        onVerticalDragCancel: _cancel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (_shown case final value?)
              IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: OnVideoColors.panel, borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _brightness == true ? AppIcons.brightnessMedium : AppIcons.volumeUp,
                            color: OnVideoColors.foreground,
                          ),
                          const SizedBox(width: 8),
                          Text('${(value * 100).round()}%', style: const TextStyle(color: OnVideoColors.foreground)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
