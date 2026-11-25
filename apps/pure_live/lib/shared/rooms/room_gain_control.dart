import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_gain.dart';

/// Shared signed-gain controls for a room and a multi-view cell.
class RoomGainControl extends StatefulWidget {
  /// Creates the persistent controls.
  const new({required this.settings, required this.room, super.key});

  /// Settings of this installation.
  final SettingsStore settings;

  /// Stable platform and room identity.
  final LiveRoom room;
  @override
  State<RoomGainControl> createState() => _RoomGainControlState();
}

class _RoomGainControlState extends State<RoomGainControl> {
  double? _dragging;
  @override
  Widget build(BuildContext context) => StreamBuilder<Object?>(
    stream: widget.settings.watch(Settings.roomVolumeGains),
    builder: (context, _) => StreamBuilder<int>(
      stream: widget.settings.watch(Settings.volumeBoostDb),
      builder: (context, _) {
        final gain = _dragging ?? RoomGain.effective(widget.settings, widget.room).toDouble();
        final label = '${gain > 0 ? '+' : ''}${gain.round()} dB';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i18n('room_gain'), style: Theme.of(context).textTheme.titleMedium),
            Text(i18n('room_gain_desc')),
            Slider(
              key: const ValueKey('room-gain-slider'),
              value: gain,
              min: -12,
              max: 12,
              divisions: 24,
              label: label,
              onChanged: (value) => setState(() => _dragging = value),
              onChangeEnd: (value) async {
                await RoomGain.save(widget.settings, widget.room, value.round());
                if (mounted) setState(() => _dragging = null);
              },
            ),
            Text(label, key: const ValueKey('room-gain-value')),
            TextButton(
              key: const ValueKey('room-gain-reset'),
              onPressed: () => unawaited(RoomGain.save(widget.settings, widget.room, null)),
              child: Text(i18n('room_gain_default')),
            ),
          ],
        );
      },
    ),
  );
}

/// Opens the same controls without rebuilding a player or another cell.
Future<void> showRoomGainDialog(BuildContext context, {required SettingsStore settings, required LiveRoom room}) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n('room_gain')),
        content: SizedBox(
          width: 360,
          child: RoomGainControl(settings: settings, room: room),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('close')))],
      ),
    );
