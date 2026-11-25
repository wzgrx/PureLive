import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/timed_room_rotation.dart';

/// User choices shared by the ordinary room and TV viewing queue.
typedef RoomRotationOptions = ({Duration interval, RoomRotationOrder order});

/// Asks for a time and order without starting playback behind the dialog.
Future<RoomRotationOptions?> showRoomRotationOptions(BuildContext context) {
  var seconds = '60';
  var order = RoomRotationOrder.ordered;
  var invalid = false;
  return showDialog<RoomRotationOptions>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: Text(i18n('room_rotation_start')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final mode in RoomRotationOrder.values)
                    ChoiceChip(
                      label: Text(
                        i18n(mode == RoomRotationOrder.ordered ? 'room_rotation_ordered' : 'room_rotation_random'),
                      ),
                      selected: order == mode,
                      onSelected: (_) => setLocal(() => order = mode),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('room-rotation-seconds'),
                initialValue: seconds,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: i18n('room_rotation_interval'),
                  errorText: invalid ? i18n('room_rotation_interval_invalid') : null,
                ),
                onChanged: (value) {
                  seconds = value;
                  if (invalid) setLocal(() => invalid = false);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('cancel'))),
          FilledButton(
            key: const ValueKey('room-rotation-confirm'),
            onPressed: () {
              final value = int.tryParse(seconds.trim());
              if (value == null || value < 5 || value > 86400) {
                setLocal(() => invalid = true);
                return;
              }
              Navigator.pop(context, (interval: Duration(seconds: value), order: order));
            },
            child: Text(i18n('room_rotation_start')),
          ),
        ],
      ),
    ),
  );
}
