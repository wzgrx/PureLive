import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';

/// A08.17: a bounded bottom-left chat stack on portrait fullscreen video.
/// It consumes the room's already filtered stream, never another connection.
class PortraitChatOverlay extends StatefulWidget {
  /// Uses the same appearance, pause policy and moderation as flying chat.
  const new({
    required this.messages,
    required this.retractions,
    required this.look,
    this.visible = true,
    this.running = true,
    this.held = false,
    this.maxVisible = 6,
    this.clearance = EdgeInsets.zero,
    this.emotes = EmoteTable.empty,
    super.key,
  });

  /// Filtered incoming chat and optional flying gifts.
  final Stream<LiveMessage> messages;

  /// Moderation events of that same room.
  final Stream<LiveRetraction> retractions;

  /// Existing danmaku font, opacity and colour presentation.
  final DanmakuLook look;

  /// Whether the layer may show messages.
  final bool visible;

  /// Whether remote chat advances under the playback pause policy.
  final bool running;

  /// A message action sheet is open.
  final bool held;

  /// Further capped to six readable rows, independently of stream density.
  final int maxVisible;

  /// Player bars and device safe areas kept clear.
  final EdgeInsets clearance;

  /// The same platform emotes used by the room's other chat views.
  final EmoteTable emotes;

  @override
  State<PortraitChatOverlay> createState() => PortraitChatOverlayState();
}

/// Hit testing remains in the player's shared tap/long-press gesture chain.
class PortraitChatOverlayState extends State<PortraitChatOverlay> implements DanmakuHitTarget {
  final List<_PortraitLine> _rows = [];
  StreamSubscription<LiveMessage>? _messages;
  StreamSubscription<LiveRetraction>? _retractions;
  Timer? _expiry;
  Duration _media = Duration.zero;
  Duration _free = Duration.zero;
  LiveMessage? _pinned;

  /// Bounded row count for verification.
  int get visibleCount => _rows.length;

  bool get _held => widget.held || _pinned != null;
  Duration _clock(LiveMessage message) => message.isLocal ? _free : _media;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _messages = widget.messages.listen(_take);
    _retractions = widget.retractions.listen((event) {
      if (!mounted) return;
      setState(() {
        _rows.removeWhere((row) => retracts(event, row.message));
        if (_pinned != null && retracts(event, _pinned!)) _pinned = null;
      });
      _syncTimer();
    });
  }

  List<ChatSegment> _segments(LiveMessage message) {
    final parts = chatSegments(message, widget.emotes);
    return widget.look.textOnly ? parts.whereType<ChatTextSegment>().toList() : parts;
  }

  void _take(LiveMessage message) {
    if (!mounted || !widget.visible || _held || (!widget.running && !message.isLocal)) return;
    final parts = _segments(message);
    if (EmoteText.plainText(parts).trim().isEmpty) return;
    final limit = widget.maxVisible.clamp(0, 6);
    if (limit == 0) return;
    final row = _PortraitLine(message, _clock(message))..parts = parts;
    _rows.add(row);
    if (_rows.length > limit) _rows.removeRange(0, _rows.length - limit);
    // A message sent on this device is what the user just did; the build
    // waits for no frame (D04.2 c2).
    _changed(now: message.isLocal);
    _syncTimer();
  }

  bool _notified = false;

  /// Tells the overlay of its rows at most once a frame (D04.2 c2: a busy
  /// room's 200 messages a second used to be 200 `setState` calls). The rows
  /// change at once, as [ChatFeed] does; [now] builds them at once.
  void _changed({bool now = false}) {
    if (!mounted) return;
    if (now) {
      _notified = false;
      setState(() {});
      return;
    }
    if (_notified) return;
    _notified = true;
    scheduleChatFlushForNextFrame(() {
      _notified = false;
      if (mounted) setState(() {});
    });
  }

  void _syncTimer() {
    final active = widget.visible && !_held && _rows.any((row) => widget.running || row.message.isLocal);
    if (!active) {
      _expiry?.cancel();
      _expiry = null;
      return;
    }
    _expiry ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _held) return;
      _free += const Duration(seconds: 1);
      if (widget.running) _media += const Duration(seconds: 1);
      final before = _rows.length;
      _rows.removeWhere((row) => _clock(row.message) - row.born >= const Duration(seconds: 8));
      if (_rows.length != before) setState(() {});
      _syncTimer();
    });
  }

  @override
  void didUpdateWidget(PortraitChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages != widget.messages || oldWidget.retractions != widget.retractions) {
      unawaited(_messages?.cancel());
      unawaited(_retractions?.cancel());
      _rows.clear();
      _pinned = null;
      _listen();
    }
    if (!widget.visible) {
      _rows.clear();
      _pinned = null;
    }
    if (!identical(oldWidget.emotes, widget.emotes) || oldWidget.look.textOnly != widget.look.textOnly) {
      // The rows keep what they were parsed and measured for; these two are
      // not part of that, so the next build takes them anew (D04.2 c2).
      for (final row in _rows) {
        row.invalidate();
      }
    }
    _rows.removeWhere((row) => (row.text ??= EmoteText.plainText(row.parts ??= _segments(row.message))).trim().isEmpty);
    final limit = widget.maxVisible.clamp(0, 6);
    if (_rows.length > limit) _rows.removeRange(0, _rows.length - limit);
    _syncTimer();
  }

  @override
  LiveMessage? messageAt(Offset position) {
    if (!widget.visible || widget.look.opacity <= 0) return null;
    final root = context.findRenderObject();
    if (root is! RenderBox) return null;
    for (final row in _rows.reversed) {
      final box = row.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final origin = box.localToGlobal(Offset.zero, ancestor: root);
      if ((origin & box.size).inflate(3).contains(position)) return row.message;
    }
    return null;
  }

  @override
  LiveMessage? pinAt(Offset position) {
    _pinned = messageAt(position);
    _syncTimer();
    return _pinned;
  }

  @override
  void unpin() {
    _pinned = null;
    _syncTimer();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    unawaited(_messages?.cancel());
    unawaited(_retractions?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ClipRect(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final scheme = Theme.of(context).colorScheme;
          final padding = MediaQuery.paddingOf(context);
          final left = math.max(12, padding.left + widget.clearance.left).toDouble();
          final bottom = math.max(padding.bottom, widget.clearance.bottom) + widget.look.bottomMargin + 12;
          final width = math.max(0, math.min(340, bounds.maxWidth * 0.82 - left - padding.right)).toDouble();
          final height = math
              .max(0, math.min(320, bounds.maxHeight * math.min(0.36, widget.look.area.clamp(0.0, 1.0))))
              .toDouble();
          final size = widget.look.fontSize.clamp(10.0, 32.0);
          final scale = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
          final base = Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: size,
            height: 1.4,
            fontFamily: widget.look.fontFamily,
            fontWeight: FontWeight.values[(widget.look.fontWeight ~/ 100 - 1).clamp(0, 8)],
            shadows: widget.look.stroke ? [Shadow(color: scheme.scrim, blurRadius: 3)] : null,
          );
          var offset = 0.0;
          final children = <Widget>[];
          for (final row in _rows.reversed) {
            final named = row.message.userName.trim();
            final nameWidth = (named.isEmpty ? 0 : math.min(width * 0.30, 90)).toDouble();
            final bodyWidth = math.max(1, width - nameWidth - 16).toDouble();
            final parts = row.parts ??= _segments(row.message);
            final text = row.text ??= EmoteText.plainText(parts);
            // D04.2 c2: a row measured for this same look and width keeps its
            // height — a busy room used to lay every visible row out again on
            // every frame, and the rows never changed between two of them.
            final measured = (
              text: text,
              bodyWidth: bodyWidth,
              size: size,
              scaled: scale.scale(size),
              font: base?.fontFamily,
              weight: base?.fontWeight?.value,
              direction: Directionality.of(context),
            );
            if (row.measured != measured) {
              final painter = TextPainter(
                text: TextSpan(text: text, style: base),
                maxLines: 2,
                textDirection: measured.direction,
                textScaler: scale,
              )..layout(maxWidth: bodyWidth);
              row
                ..height = math.max(measured.scaled * 1.4, painter.height) + 8
                ..measured = measured;
              painter.dispose();
            }
            final rowHeight = row.height;
            if (offset + rowHeight > height || width < 40) break;
            final color = row.message.color;
            children.add(
              AnimatedPositioned(
                key: ObjectKey(row),
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                left: 0,
                bottom: offset,
                width: width,
                child: Container(
                  key: row.key,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.scrim.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (named.isNotEmpty)
                        SizedBox(
                          width: nameWidth,
                          child: Text(
                            '$named：',
                            style: base?.copyWith(color: Color.lerp(scheme.primary, OnVideoColors.foreground, 0.65)),
                            textScaler: scale,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      Expanded(
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(textScaler: scale),
                          child: EmoteText(
                            parts,
                            style: base?.copyWith(color: Color.fromARGB(255, color.r, color.g, color.b)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            emoteScale: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            offset += rowHeight + 4;
          }
          return Stack(
            children: [
              Positioned(
                left: left,
                bottom: bottom,
                width: width,
                height: height,
                child: Opacity(
                  opacity: widget.look.opacity.clamp(0.0, 1.0),
                  child: Stack(children: children),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

final class _PortraitLine {
  new(this.message, this.born);
  final LiveMessage message;
  final Duration born;
  final GlobalKey key = GlobalKey();

  /// The row's pieces and their text, taken once: the parse of the message
  /// itself is already shared with the chat list and the flying layer (B09
  /// c7), so this only keeps it off the next build (D04.2 c2).
  List<ChatSegment>? parts;
  String? text;

  /// What [height] was measured for: the row's text, the width it has for it
  /// and what the text is drawn with. A build that asks for the same thing
  /// lays no text out again.
  Object? measured;
  double height = 0;

  void invalidate() {
    parts = null;
    text = null;
    measured = null;
  }
}
