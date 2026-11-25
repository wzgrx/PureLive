import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/permission_prompts.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Whether "开播提醒" exists here: Android only (O01.1); tests set it.
bool liveAlertsAvailable = !kIsWeb && Platform.isAndroid;

/// Whether [room] has its own "开播提醒" on (A09.13): the switch is on and
/// the room is in `liveAlertRoomKeys`.
bool roomLiveAlertOn(SettingsStore settings, LiveRoom room) =>
    settings.get(Settings.liveAlertEnabled) && settings.get(Settings.liveAlertRoomKeys).contains(room.identityKey);

/// Whether "开播提醒" covers every follow now: on, no tag chosen and no
/// follow given its own switch (V01.1 L3).
bool liveAlertCoversAll(SettingsStore settings) =>
    settings.get(Settings.liveAlertEnabled) &&
    settings.get(Settings.liveAlertTagIds).isEmpty &&
    settings.get(Settings.liveAlertRoomKeys).isEmpty;

/// Turns [room]'s own "开播提醒" on or off (A09.13: the card's menu and the
/// room's follow menu).
///
/// On: when "开播提醒" is off it is turned on, asking for the notification
/// permission first (the settings switch's words, O01.1); when it covered
/// every follow, the user is asked first, as from now on only the follows
/// with their own switch (and the chosen tags) are covered. Off: the room
/// leaves the list; with none left and no tag chosen, every follow is
/// covered again (V01.1 L3), so the toast says so.
Future<void> toggleRoomLiveAlert(
  BuildContext context, {
  required LiveStore store,
  required LiveRoom room,
  Future<bool> Function()? confirmNarrow,
}) async {
  final settings = store.settings;
  final keys = settings.get(Settings.liveAlertRoomKeys);
  final name = room.displayNick(platformName(room.platform));
  if (roomLiveAlertOn(settings, room)) {
    final rest = [
      for (final key in keys)
        if (key != room.identityKey) key,
    ];
    await settings.set(Settings.liveAlertRoomKeys, rest);
    AppNavigator.toast(
      i18n(liveAlertCoversAll(settings) ? 'room_live_alert_off_all' : 'room_live_alert_off', args: {'name': name}),
    );
    return;
  }
  if (liveAlertCoversAll(settings)) {
    final narrow =
        await (confirmNarrow?.call() ??
            showAppConfirmDialog(
              context: context,
              key: const ValueKey('room-live-alert-narrow'),
              title: i18n('room_live_alert_narrow_title'),
              message: i18n('room_live_alert_narrow_message'),
              confirmLabel: i18n('room_live_alert_narrow_confirm'),
              confirmKey: const ValueKey('room-live-alert-narrow-confirm'),
            ));
    if (!narrow) return;
  } else if (!settings.get(Settings.liveAlertEnabled)) {
    if (!context.mounted) return;
    final permissions = ProviderScope.containerOf(context).read(backgroundPermissionsProvider);
    if (permissions != null) {
      final answer = await permissions.confirmNotifications(
        content: i18n('permission_live_alert_content'),
        blockedContent: i18n('permission_live_alert_blocked_content'),
      );
      if (answer != PermissionAnswer.granted) return;
    }
    await settings.set(Settings.liveAlertEnabled, true);
  }
  await settings.set(Settings.liveAlertRoomKeys, [
    for (final key in keys)
      if (key != room.identityKey) key,
    room.identityKey,
  ]);
  AppNavigator.toast(i18n('room_live_alert_on', args: {'name': name}));
}

/// The card menu's "开播提醒" / "关闭开播提醒" for [room] (A09.13).
RoomMenuAction roomLiveAlertAction(BuildContext context, {required LiveStore store, required LiveRoom room}) {
  final on = roomLiveAlertOn(store.settings, room);
  return RoomMenuAction(
    key: const ValueKey('room-menu-live-alert'),
    icon: on ? AppIcons.liveAlertOff : AppIcons.settingsLiveAlert,
    label: i18n(on ? 'room_live_alert_turn_off' : 'room_live_alert_turn_on'),
    onSelected: () => toggleRoomLiveAlert(context, store: store, room: room),
  );
}

/// The bell on a follow's card while its own "开播提醒" is on (A09.13).
class RoomLiveAlertBell extends StatelessWidget {
  /// Creates the bell.
  const new({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('room-live-alert-bell'),
    decoration: const BoxDecoration(color: OnVideoColors.scrim, shape: BoxShape.circle),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(
        AppIcons.settingsLiveAlert,
        size: 14,
        color: OnVideoColors.foreground,
        semanticLabel: i18n('room_live_alert_bell'),
      ),
    ),
  );
}
