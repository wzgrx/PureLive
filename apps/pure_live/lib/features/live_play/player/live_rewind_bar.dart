import 'dart:async';

import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The live cache interval; no duration or seek controls are invented.
final class RoomLiveRewindBar extends StatefulWidget {
  /// Creates an optional bar tied to one playback session.
  const new({required this.session, required this.onInteract, super.key});

  /// The live playback session.
  final PlaybackSession session;

  /// Keeps the playback controls visible while the user interacts.
  final VoidCallback onInteract;

  @override
  State<RoomLiveRewindBar> createState() => _RoomLiveRewindBarState();
}

class _RoomLiveRewindBarState extends State<RoomLiveRewindBar> {
  ({LiveRewindRange range, Duration position})? _window;
  LiveRewindRange? _dragRange;
  double? _slider;
  Timer? _timer;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_read()));
  }

  Future<void> _read() async {
    if (_reading || _dragRange != null) return;
    _reading = true;
    final source = widget.session;
    try {
      final window = await source.liveRewindWindow();
      if (mounted && identical(source, widget.session)) setState(() => _window = window);
    } finally {
      _reading = false;
    }
  }

  Future<void> _seek(Duration position) async {
    widget.onInteract();
    await widget.session.seekLiveCache(position);
    if (mounted) await _read();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final window = _window;
    if (window == null) return const SizedBox.shrink();
    final range = _dragRange ?? window.range;
    final span = (range.end - range.start).inMilliseconds;
    final value = _slider ?? ((window.position - range.start).inMilliseconds / span).clamp(0, 1).toDouble();
    return Material(
      key: const ValueKey('room-live-rewind-bar'),
      color: OnVideoColors.ground.withValues(alpha: .68),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8),
            child: Text(
              i18n('live_rewind_title'),
              style: const TextStyle(color: OnVideoColors.foreground, fontSize: 12),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              onChangeStart: (_) {
                widget.onInteract();
                setState(() => _dragRange = window.range);
              },
              onChanged: (next) {
                widget.onInteract();
                setState(() => _slider = next);
              },
              onChangeEnd: (next) {
                final selected = _dragRange ?? window.range;
                final ms = (selected.end - selected.start).inMilliseconds;
                setState(() {
                  _slider = null;
                  _dragRange = null;
                });
                unawaited(_seek(selected.start + Duration(milliseconds: (next * ms).round())));
              },
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_seek(window.range.end - const Duration(milliseconds: 200))),
            child: Text(i18n('live_rewind_to_live'), style: const TextStyle(color: OnVideoColors.foreground)),
          ),
        ],
      ),
    );
  }
}
