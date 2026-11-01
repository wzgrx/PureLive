import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/playback_hud_config.dart';
import 'package:pure_live/shared/rooms/playback_telemetry.dart';

/// Formats bytes actually read by this media session; unknown is not zero.
String playbackHudRate(double? rate) {
  if (rate == null || !rate.isFinite || rate < 0) return '—';
  if (rate < 1024) return '${rate.round()} B/s';
  if (rate < 1024 * 1024) return '${(rate / 1024).toStringAsFixed(1)} KiB/s';
  return '${(rate / (1024 * 1024)).toStringAsFixed(1)} MiB/s';
}

/// A minute-aligned local clock; it never ticks the player or its controls.
class PlayerClock extends StatefulWidget {
  /// Tests may supply a fixed [now].
  const new({this.now = DateTime.now, this.style, super.key});

  /// Local wall-clock source.
  final DateTime Function() now;

  /// The same configured style as the adjacent speed figure.
  final TextStyle? style;

  @override
  State<PlayerClock> createState() => _PlayerClockState();
}

class _PlayerClockState extends State<PlayerClock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final now = widget.now();
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _tick = Timer(next.difference(now) + const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now();
    String two(int number) => number.toString().padLeft(2, '0');
    return Text(
      '${two(now.hour)}:${two(now.minute)}',
      key: const ValueKey('live-play-clock'),
      style:
          widget.style ??
          Theme.of(context).textTheme.bodyMedium?.regular.tabular
              .copyWith(color: OnVideoColors.foreground, shadows: OnVideoColors.shadows),
    );
  }
}

/// Input-transparent information, placed independently of auto-hiding controls.
class PlaybackHud extends ConsumerWidget {
  /// [clearance] keeps information clear of bars, captions and other overlays.
  const new({required this.telemetry, required this.controls, this.clearance = EdgeInsets.zero, super.key});

  /// The room's one statistics sampler; only speed subscribes to it.
  final PlaybackTelemetry telemetry;

  /// Whether the playback controls currently show.
  final bool controls;

  /// Extra room-specific safe space, in logical pixels.
  final EdgeInsets clearance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = PlaybackHudConfig.fromJson(watchSetting(ref, Settings.playbackHud));
    return PlaybackHudView(config: config, telemetry: telemetry, controls: controls, clearance: clearance);
  }
}

/// Provider-independent presentation used by every room layout and previews.
class PlaybackHudView extends StatelessWidget {
  /// Creates an information layer without owning a playback session.
  const new({
    required this.config,
    required this.telemetry,
    required this.controls,
    this.clearance = EdgeInsets.zero,
    super.key,
  });

  /// Validated display preferences.
  final PlaybackHudConfig config;

  /// Shared native statistics; subscribed only when speed is visible.
  final PlaybackTelemetry telemetry;

  /// Whether controls currently show.
  final bool controls;

  /// Space reserved by room controls and captions.
  final EdgeInsets clearance;

  @override
  Widget build(BuildContext context) {
    if (!config.visible(controls: controls)) return const SizedBox.shrink();
    final base = Theme.of(context).textTheme.bodyMedium;
    final mono = switch (Theme.of(context).platform) {
      TargetPlatform.windows => 'Consolas',
      TargetPlatform.macOS || TargetPlatform.iOS => 'Menlo',
      TargetPlatform.linux => 'DejaVu Sans Mono',
      _ => 'monospace',
    };
    TextStyle style(PlaybackHudStyle item) => TextStyle(
      inherit: false,
      fontSize: item.size,
      fontFamily: switch (item.font) {
        'mono' => mono,
        'app' => base?.fontFamily,
        _ => null,
      },
      fontFamilyFallback: item.font == 'app' ? base?.fontFamilyFallback : null,
      fontWeight: FontWeight.w600,
      color: Color(item.color),
      shadows: OnVideoColors.shadows,
    ).tabular;
    Widget clock() => PlayerClock(style: style(config.styleFor('clock')));
    Widget rate(double? speed) => Text(
      '${i18n('playback_hud_speed')}: ${playbackHudRate(speed)}',
      key: const ValueKey('playback-hud-speed'),
      style: style(config.styleFor('speed')),
    );
    Widget contents(double? speed) {
      final groups = <String, List<Widget>>{};
      if (config.clock) (groups[config.styleFor('clock').corner] ??= []).add(clock());
      if (config.speed) (groups[config.styleFor('speed').corner] ??= []).add(rate(speed));
      final splitVertical =
          groups.keys.any((key) => key.startsWith('top')) && groups.keys.any((key) => key.startsWith('bottom'));
      return LayoutBuilder(
        builder: (_, area) => Stack(
          fit: StackFit.expand,
          children: [
            for (final entry in groups.entries)
              Align(
                alignment: PlaybackHudConfig.corners[entry.key]!,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: config.separate && groups.length > 1 && !splitVertical
                        ? ((area.maxWidth - 4) / 2).clamp(0, double.infinity)
                        : area.maxWidth,
                    maxHeight: config.separate && splitVertical
                        ? ((area.maxHeight - 4) / 2).clamp(0, double.infinity)
                        : area.maxHeight,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: config.separate
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: entry.key.endsWith('Left')
                                ? CrossAxisAlignment.start
                                : CrossAxisAlignment.end,
                            spacing: 4,
                            children: entry.value,
                          )
                        : Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            children: entry.value,
                          ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, box) {
          final vertical = clearance.top + clearance.bottom;
          final factor = vertical > box.maxHeight * 0.45 ? box.maxHeight * 0.45 / vertical : 1.0;
          final bounded = EdgeInsets.fromLTRB(
            clearance.left,
            clearance.top * factor,
            clearance.right,
            clearance.bottom * factor,
          );
          return IgnorePointer(
            child: ExcludeFocus(
              child: SafeArea(
                minimum: const EdgeInsets.all(12),
                child: Padding(
                  padding: bounded,
                  child: RepaintBoundary(
                    key: const ValueKey('playback-hud'),
                    child: config.speed
                        ? ListenableBuilder(
                            listenable: telemetry,
                            builder: (_, _) => contents(telemetry.downloadAverage),
                          )
                        : contents(null),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
