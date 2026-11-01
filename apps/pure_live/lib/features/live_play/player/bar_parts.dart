import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/logic/device_battery.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/features/live_play/player/player_gestures.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_gain_control.dart';

export 'package:pure_live/shared/rooms/playback_hud.dart' show PlayerClock;

// The smaller pieces of the fullscreen and wide bars (docs/A-界面设计/A07-直播间界面/A07.2-竖屏流和竖屏全屏,
// U.2c, U.2d): the clock and battery, the desktop volume, the fit and
// portrait-mode menus, the lock and the portrait fullscreen's entry hint.

/// The battery figure's size (B09 c5, audit B-18: at least 11; it was 9).
const double batteryFontSize = 11;

/// The battery of the fullscreen bars (3.x `BatteryInfo`): a 36 × 17 outline
/// (3.x 35 × 15, a little more for the larger figure) with the percentage;
/// nothing on a device without a battery (U.2c change 4). Read once and then
/// every minute; redrawn only when it changes.
class PlayerBattery extends StatefulWidget {
  /// Creates the battery.
  const new({this.read = DeviceBattery.level, super.key});

  /// Reads the level (percent), null for none.
  final Future<int?> Function() read;

  // Keep the last figure through control-bar/floating-row transitions.
  static final Expando<int> _recentLevels = Expando();

  @override
  State<PlayerBattery> createState() => _PlayerBatteryState();
}

class _PlayerBatteryState extends State<PlayerBattery> {
  int? _level;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _level = PlayerBattery._recentLevels[widget.read];
    unawaited(_refresh());
    _poll = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    final read = widget.read;
    final level = await read();
    PlayerBattery._recentLevels[read] = level;
    if (mounted && widget.read == read && level != _level) setState(() => _level = level);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = _level;
    if (level == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      // The case grows with larger text instead of cutting the figure.
      child: ConstrainedBox(
        key: const ValueKey('live-play-battery'),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 17),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: OnVideoColors.chipOutline,
            border: Border.all(color: OnVideoColors.foreground),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                '$level',
                key: const ValueKey('live-play-battery-level'),
                style: Theme.of(context).textTheme.labelSmall?.regular.tabular
                    .copyWith(fontSize: batteryFontSize, color: OnVideoColors.foreground, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The desktop volume (3.x `OverlayVolumeControl`, U.2c 21 and U.2d 13): the
/// level's icon (a tap mutes or restores), a slider and the level in words;
/// the room's volume is kept when the slider is let go. The arrow keys and
/// the wheel change it too, and the words show while the slider is dragged
/// and for a moment after any change (issue #12).
class VolumeSlider extends StatefulWidget {
  /// Creates the slider for [controller].
  const new({required this.controller, this.onInteract, this.onHolding, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Keeps the controls up while it is used.
  final VoidCallback? onInteract;

  /// Keeps the controls visible until the slider is released.
  final ValueChanged<bool>? onHolding;

  @override
  State<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<VolumeSlider> {
  StreamSubscription<PlaybackState>? _states;
  late double _volume = widget.controller.session.state.volume.clamp(0.0, 1.0);

  /// The level's words show: dragged, or changed a moment ago.
  bool _dragging = false;
  bool _changed = false;
  Timer? _fade;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(VolumeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) _listen();
  }

  @override
  void dispose() {
    unawaited(_states?.cancel());
    _fade?.cancel();
    // A layout change may remove a held slider. Balance the hold after the
    // tree finishes disposing; the player ignores it if it has gone too.
    final onHolding = widget.onHolding;
    if (_dragging && onHolding != null) scheduleMicrotask(() => onHolding(false));
    super.dispose();
  }

  void _listen() {
    unawaited(_states?.cancel());
    _states = widget.controller.session.states.listen((state) {
      final volume = state.volume.clamp(0.0, 1.0);
      if (volume == _volume || !mounted) return;
      setState(() {
        _volume = volume;
        _changed = true;
      });
      _fade?.cancel();
      _fade = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _changed = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final volume = _volume;
    final percent = '${(volume * 100).round()}%';
    return Row(
      key: const ValueKey('live-play-volume'),
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('live-play-gain'),
          tooltip: i18n('room_gain'),
          color: OnVideoColors.foreground,
          onPressed: () async {
            widget.onInteract?.call();
            final onHolding = widget.onHolding;
            onHolding?.call(true);
            try {
              await showRoomGainDialog(
                context,
                settings: widget.controller.store.settings,
                room: widget.controller.room,
              );
            } finally {
              onHolding?.call(false);
            }
          },
          icon: const Icon(AppIcons.roomGain, size: 22),
        ),
        IconButton(
          tooltip: i18n(volume <= 0 ? 'live_play_unmute' : 'live_play_mute'),
          color: OnVideoColors.foreground,
          constraints: const BoxConstraints(minWidth: kMinInteractiveDimension, minHeight: kMinInteractiveDimension),
          onPressed: () {
            widget.onInteract?.call();
            unawaited(widget.controller.toggleMute());
          },
          icon: Icon(gestureLevelIcon(GestureLevel.volume, volume), size: 22),
        ),
        SizedBox(
          width: 96,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: OnVideoColors.foreground,
              inactiveTrackColor: OnVideoColors.track,
              thumbColor: OnVideoColors.foreground,
              overlayColor: OnVideoColors.chip,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              key: const ValueKey('live-play-volume-slider'),
              value: volume,
              semanticFormatterCallback: (value) => '${(value * 100).round()}%',
              onChangeStart: (_) {
                setState(() => _dragging = true);
                widget.onHolding?.call(true);
                widget.onInteract?.call();
              },
              onChanged: (value) {
                widget.onInteract?.call();
                unawaited(widget.controller.setVolume(value));
              },
              onChangeEnd: (value) {
                setState(() => _dragging = false);
                widget.onHolding?.call(false);
                unawaited(widget.controller.setVolume(value, save: true));
              },
            ),
          ),
        ),
        // Its own width, so nothing moves as the words come and go.
        SizedBox(
          width: 40,
          child: AnimatedOpacity(
            opacity: _dragging || _changed ? 1 : 0,
            duration: AppDurations.fast,
            child: ExcludeSemantics(
              child: Text(
                percent,
                key: const ValueKey('live-play-volume-percent'),
                maxLines: 1,
                style: Theme.of(context).textTheme.labelMedium?.tabular.copyWith(color: OnVideoColors.foreground),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The fullscreen bar's fit (U.2c change 6, 18): the "画面比例" icon, the same
/// small menu as the strip's quality, above the button; the room menu's
/// "画面比例" opens the same menu next to its own button
/// ([showVideoFitMenu], docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一 c5).
class VideoFitButton extends ConsumerWidget {
  /// Creates the button.
  const new({this.onMenu, super.key});

  /// Told when the menu opens and closes.
  final ValueChanged<bool>? onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = watchSetting(ref, Settings.videoFitIndex).clamp(0, videoFits.length - 1);
    return Builder(
      builder: (anchor) => IconButton(
        key: const ValueKey('live-play-video-fit'),
        tooltip: '${i18n('settings_video_fit')}：${videoFitName(index)}',
        color: OnVideoColors.foreground,
        constraints: const BoxConstraints(minWidth: kMinInteractiveDimension, minHeight: kMinInteractiveDimension),
        onPressed: () async {
          onMenu?.call(true);
          // The room menu's "画面比例" opens the same menu (U.2n c5).
          await showVideoFitMenu(anchor, ref.read(storeProvider).settings, preferAbove: true);
          onMenu?.call(false);
        },
        icon: const Icon(AppIcons.aspectRatio, size: 22),
      ),
    );
  }
}

/// The names of [PortraitDisplayMode]s (3.x's keys).
String portraitModeName(PortraitDisplayMode mode) => i18n('portrait_fullscreen_display_${mode.name}');

/// The line under a mode's name.
String portraitModeDescription(PortraitDisplayMode mode) => i18n('portrait_fullscreen_display_${mode.name}_desc');

/// The portrait fullscreen's picture mode (U.2b changes 8 and 9, 23): always
/// the "画面比例" icon, yellow when not "沉浸背景"; a small menu above it
/// titled "竖屏全屏画面模式", each mode with its line, the current one in the
/// primary colour with a tick. The picture is not dimmed and changes at once.
class PortraitModeButton extends ConsumerWidget {
  /// Creates the button.
  const new({this.onMenu, super.key});

  /// Told when the menu opens and closes.
  final ValueChanged<bool>? onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = PortraitDisplayMode.of(watchSetting(ref, Settings.portraitFullscreenDisplayMode));
    return Builder(
      builder: (anchor) => IconButton(
        key: const ValueKey('live-play-portrait-mode'),
        tooltip: '${i18n('portrait_fullscreen_display_mode')}：${portraitModeName(mode)}',
        color: mode == PortraitDisplayMode.ambient ? OnVideoColors.foreground : OnVideoColors.active,
        constraints: const BoxConstraints(minWidth: kMinInteractiveDimension, minHeight: kMinInteractiveDimension),
        onPressed: () async {
          onMenu?.call(true);
          final width = MediaQuery.sizeOf(anchor).width;
          final chosen = await showSmallMenu(
            anchor,
            title: i18n('portrait_fullscreen_display_mode'),
            entries: [for (final value in PortraitDisplayMode.values) portraitModeName(value)],
            descriptions: [for (final value in PortraitDisplayMode.values) portraitModeDescription(value)],
            current: mode.index,
            entryKey: 'portrait-mode',
            preferAbove: true,
            width: (width - 24).clamp(200.0, 340.0),
          );
          onMenu?.call(false);
          if (chosen != null && chosen != mode.index) {
            await ref
                .read(storeProvider)
                .settings
                .set(Settings.portraitFullscreenDisplayMode, PortraitDisplayMode.values[chosen].name);
          }
        },
        icon: const Icon(AppIcons.aspectRatio, size: 22),
      ),
    );
  }
}

/// The lock at the right of a fullscreen picture (3.x `LockButton`, U.2c
/// 20, U.2b 24): a 50 × 50 round button on 38 % black; locked, the bars
/// hide, the gestures stop and only this button shows (a tap on the picture
/// shows or hides it).
class LockButton extends StatelessWidget {
  /// Creates the button.
  const new({required this.locked, required this.onPressed, super.key});

  /// Whether the controls are locked.
  final bool locked;

  /// Locks or unlocks.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: ValueKey(locked ? 'live-play-unlock' : 'live-play-lock'),
    tooltip: i18n(locked ? 'live_play_unlock' : 'live_play_lock'),
    onPressed: onPressed,
    color: OnVideoColors.foreground,
    iconSize: 28,
    style: IconButton.styleFrom(
      backgroundColor: OnVideoColors.lockBacking,
      shape: const CircleBorder(),
      minimumSize: const Size(50, 50),
      fixedSize: const Size(50, 50),
    ),
    icon: Icon(locked ? AppIcons.locked : AppIcons.unlocked),
  );
}

/// The hint after entering the portrait fullscreen (3.x
/// `PortraitFullscreenEntryHint`): "已进入竖屏全屏 · 上滑恢复弹幕栏" above the
/// bottom rows, fading out after three seconds.
class PortraitEntryHint extends StatefulWidget {
  /// Creates the hint, [bottom] above the screen's lower edge.
  const new({required this.bottom, this.visibleFor = const Duration(seconds: 3), super.key});

  /// The distance from the lower edge.
  final double bottom;

  /// How long it shows.
  final Duration visibleFor;

  @override
  State<PortraitEntryHint> createState() => _PortraitEntryHintState();
}

class _PortraitEntryHintState extends State<PortraitEntryHint> {
  bool _visible = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _hide = Timer(widget.visibleFor, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Positioned(
      left: 12,
      right: 12,
      bottom: widget.bottom,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: still ? Duration.zero : const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            child: DecoratedBox(
              key: const ValueKey('live-play-portrait-hint'),
              decoration: BoxDecoration(
                color: OnVideoColors.hint,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: OnVideoColors.hintOutline),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(AppIcons.portraitFullscreenRestore, color: OnVideoColors.foreground, size: 20),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        i18n('portrait_fullscreen_restore_hint'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.emphasis
                            .copyWith(fontSize: 13, color: OnVideoColors.foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
