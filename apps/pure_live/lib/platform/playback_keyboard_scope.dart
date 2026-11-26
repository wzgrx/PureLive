import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pure_live/routes/route_observer.dart';

/// Keeps Windows IME composition out of non-editing playback shortcuts.
/// Only the Flutter view's context is detached; the input language and
/// native dialogs remain unchanged. Editable text and covered routes restore
/// the exact native context, including when two playback routes overlap.
class PlaybackKeyboardScope extends StatefulWidget {
  /// Wraps an existing playback keyboard owner.
  const new({required this.child, super.key});

  /// Existing room or multi-view keyboard handling.
  final Widget child;

  @override
  State<PlaybackKeyboardScope> createState() => _PlaybackKeyboardScopeState();
}

class _PlaybackKeyboardScopeState extends State<PlaybackKeyboardScope> {
  static const _channel = MethodChannel('pure_live/playback_keyboard');
  static final Set<Object> _owners = {};
  static bool _requested = false;
  bool get _windows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (_windows) {
      FocusManager.instance.addListener(_sync);
      liveRouteObserver.addListener(_routeChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _routeChanged(RouteEvent _) => _sync();

  void _sync() {
    if (!_windows || !mounted) return;
    final focus = FocusManager.instance.primaryFocus?.context;
    final editor = focus?.widget is EditableText
        ? focus!.widget as EditableText
        : focus?.findAncestorWidgetOfExactType<EditableText>();
    final suppress = ModalRoute.of(context)?.isCurrent == true && (editor == null || editor.readOnly);
    if (suppress) {
      _owners.add(this);
    } else {
      _owners.remove(this);
    }
    _publish();
  }

  static void _publish() {
    final next = _owners.isNotEmpty;
    if (next == _requested) return;
    _requested = next;
    // MethodChannel preserves FIFO, and the native handler applies the
    // association synchronously. Do not delay an editor behind old replies.
    unawaited(_send(next));
  }

  static Future<void> _send(bool next) async {
    try {
      await _channel.invokeMethod<void>('setPlaybackKeyboardMode', next);
    } on Object {
      // Old runners and widget hosts keep the existing keyboard path.
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_sync);
    liveRouteObserver.removeListener(_routeChanged);
    _owners.remove(this);
    _publish();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
