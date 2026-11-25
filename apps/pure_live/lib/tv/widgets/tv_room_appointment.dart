import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_schedule_dialog.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';

/// Adds or removes an appointment using the same remote dialog from cards and playback.
Future<void> showTvRoomAppointment(BuildContext context, RoomScheduleStore store, LiveRoom room) async {
  try {
    final saved = (await store.all()).where((item) => item.room.hasSameIdentity(room)).toList();
    if (!context.mounted) return;
    final choice = await showTvChoice<Object>(
      context,
      title: i18n('room_schedule_title'),
      subtitle: i18n('room_schedule_foreground_hint'),
      options: [
        TvChoice(value: RoomScheduleInput.daily, label: i18n('room_schedule_daily')),
        TvChoice(value: RoomScheduleInput.countdown, label: i18n('room_schedule_countdown')),
        for (final item in saved) TvChoice(value: item, label: roomAppointmentLabel(item)),
      ],
    );
    if (!context.mounted || choice == null) return;
    if (choice is RoomOpenSchedule) {
      final remove = await showTvChoice<bool>(
        context,
        title: i18n('room_schedule_remove'),
        options: [
          TvChoice(value: true, label: i18n('confirm')),
          TvChoice(value: false, label: i18n('cancel')),
        ],
      );
      if (remove ?? false) await store.remove(choice.id);
      return;
    }
    if (choice is! RoomScheduleInput) return;
    final daily = choice == RoomScheduleInput.daily;
    final input = await showTvInput(
      context,
      title: i18n(daily ? 'room_schedule_daily_input' : 'room_schedule_countdown_input'),
      text: daily ? '0800' : '60',
      numeric: true,
      maxLength: 5,
    );
    if (!context.mounted || input == null) return;
    final task = parseRoomAppointment(room, choice, input, DateTime.now());
    if (task == null) {
      AppNavigator.toast(i18n('room_schedule_invalid'));
      return;
    }
    final stored = await store.put(task);
    if (context.mounted) AppNavigator.toast(i18n(stored ? 'room_schedule_saved' : 'room_schedule_edit_failed'));
  } on Object {
    if (context.mounted) AppNavigator.toast(i18n('room_schedule_edit_failed'));
  }
}
