import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// Ways to enter a room appointment on a phone, desktop or TV.
enum RoomScheduleInput {
  /// A local time repeated daily.
  daily,

  /// A delay, stored as an absolute deadline.
  countdown,
}

/// Parses the numeric entry used by the standard and TV dialogs.
RoomOpenSchedule? parseRoomAppointment(LiveRoom room, RoomScheduleInput kind, String input, DateTime now) {
  final text = input.trim();
  final id = '${now.microsecondsSinceEpoch}';
  if (kind == RoomScheduleInput.countdown) {
    final seconds = int.tryParse(text);
    if (seconds == null || seconds < 5 || seconds > 86400) return null;
    return RoomOpenSchedule.once(
      id: id,
      room: room,
      at: now.add(Duration(seconds: seconds)),
    );
  }
  final match = RegExp(r'^(\d{2}):?(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final hour = int.parse(match[1]!);
  final minute = int.parse(match[2]!);
  if (hour > 23 || minute > 59) return null;
  return RoomOpenSchedule.daily(id: id, room: room, minute: hour * 60 + minute);
}

/// The current local deadline shown when managing an appointment.
String roomAppointmentLabel(RoomOpenSchedule item) {
  String hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  if (item.dailyMinute case final minutes?) {
    return '${i18n('room_schedule_daily')} ${hhmm(minutes)}';
  }
  final at = item.onceAt!.toLocal();
  return '${at.month}/${at.day} ${hhmm(at.hour * 60 + at.minute)}';
}

/// Prompts before removing a stored room appointment.
Future<void> confirmRemoveRoomAppointment(BuildContext context, RoomScheduleStore store, RoomOpenSchedule item) async {
  final remove = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(i18n('room_schedule_remove')),
      content: Text(roomAppointmentLabel(item)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(i18n('confirm'))),
      ],
    ),
  );
  if (remove ?? false) await store.remove(item.id);
}

/// Shows the ordinary room's appointment choices and its saved schedules.
Future<void> showRoomAppointmentMenu(BuildContext context, RoomScheduleStore store, LiveRoom room) async {
  try {
    final saved = (await store.all()).where((item) => item.room.hasSameIdentity(room)).toList();
    if (!context.mounted) return;
    final action = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(i18n('room_schedule_title')),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: Text(i18n('room_schedule_foreground_hint')),
          ),
          SimpleDialogOption(
            key: const ValueKey('room-schedule-daily'),
            onPressed: () => Navigator.pop(context, RoomScheduleInput.daily),
            child: Text(i18n('room_schedule_daily')),
          ),
          SimpleDialogOption(
            key: const ValueKey('room-schedule-countdown'),
            onPressed: () => Navigator.pop(context, RoomScheduleInput.countdown),
            child: Text(i18n('room_schedule_countdown')),
          ),
          for (final item in saved)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, item), child: Text(roomAppointmentLabel(item))),
        ],
      ),
    );
    if (!context.mounted || action == null) return;
    if (action is RoomOpenSchedule) {
      await confirmRemoveRoomAppointment(context, store, action);
      return;
    }
    if (action is! RoomScheduleInput) return;
    final daily = action == RoomScheduleInput.daily;
    var value = daily ? '0800' : '60';
    var invalid = false;
    final appointment = await showDialog<RoomOpenSchedule>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(i18n(daily ? 'room_schedule_daily' : 'room_schedule_countdown')),
          content: TextFormField(
            key: const ValueKey('room-schedule-value'),
            initialValue: value,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: i18n(daily ? 'room_schedule_daily_input' : 'room_schedule_countdown_input'),
              errorText: invalid ? i18n('room_schedule_invalid') : null,
            ),
            onChanged: (input) {
              value = input;
              if (invalid) setLocal(() => invalid = false);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('cancel'))),
            FilledButton(
              key: const ValueKey('room-schedule-save'),
              onPressed: () {
                final task = parseRoomAppointment(room, action, value, DateTime.now());
                if (task == null) {
                  setLocal(() => invalid = true);
                  return;
                }
                Navigator.pop(context, task);
              },
              child: Text(i18n('confirm')),
            ),
          ],
        ),
      ),
    );
    if (appointment == null) return;
    final stored = await store.put(appointment);
    if (context.mounted) AppNavigator.toast(i18n(stored ? 'room_schedule_saved' : 'room_schedule_edit_failed'));
  } on Object {
    if (context.mounted) AppNavigator.toast(i18n('room_schedule_edit_failed'));
  }
}
