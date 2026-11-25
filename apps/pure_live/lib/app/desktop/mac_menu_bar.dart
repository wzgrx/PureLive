import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/commands.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// The Mac's menu bar over [child] (docs/A-界面设计/A18-苹果平台界面/A18.2-macOS差异设计 c4,
/// c5): in the app's language, in the Mac's order — 纯粹直播, 文件, 编辑, 显示,
/// 播放 (only in a room), 窗口, 帮助 — with the ⌘ keys of [AppCommand].
/// Elsewhere [child] alone.
class MacMenuBar extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The app.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DesktopWindow.macStyle) return child;
    return ValueListenableBuilder<RoomCommands?>(
      valueListenable: RoomCommands.current,
      builder: (context, room, _) => PlatformMenuBar(
        menus: macMenus(room: room),
        child: child,
      ),
    );
  }
}

/// The menus, with [room]'s "播放" items enabled while a room is on top.
List<PlatformMenuItem> macMenus({RoomCommands? room}) {
  PlatformMenuItem command(String key, AppCommand command) =>
      PlatformMenuItem(label: i18n(key), shortcut: command.activator, onSelected: command.run);
  PlatformMenuItem page(String key, String path) =>
      PlatformMenuItem(label: i18n(key), onSelected: () => unawaited(AppNavigator.toNamed<void>(path)));
  // Text fields get the edit commands the menu now owns (the menu takes
  // ⌘C before the field sees the key).
  PlatformMenuItem edit(String key, Intent intent, SingleActivator shortcut) => PlatformMenuItem(
    label: i18n(key),
    shortcut: shortcut,
    onSelected: () {
      final context = primaryFocus?.context;
      if (context != null) Actions.maybeInvoke(context, intent);
    },
  );
  List<PlatformMenuItem> provided(List<PlatformProvidedMenuItemType> types) => [
    for (final type in types)
      if (PlatformProvidedMenuItem.hasMenu(type)) PlatformProvidedMenuItem(type: type),
  ];
  PlatformMenuItemGroup group(List<PlatformMenuItem> members) => PlatformMenuItemGroup(members: members);
  const cause = SelectionChangedCause.keyboard;
  return [
    PlatformMenu(
      label: i18n('app_name'),
      menus: [
        group([page('menu_about', RoutePath.kAbout), page('menu_check_update', RoutePath.kVersionPage)]),
        group([command('menu_settings', AppCommand.settings)]),
        group(provided([PlatformProvidedMenuItemType.servicesSubmenu])),
        group(
          provided([
            PlatformProvidedMenuItemType.hide,
            PlatformProvidedMenuItemType.hideOtherApplications,
            PlatformProvidedMenuItemType.showAllApplications,
          ]),
        ),
        // ⌘Q asks the app first while recording (DesktopShell).
        group(provided([PlatformProvidedMenuItemType.quit])),
      ],
    ),
    PlatformMenu(
      label: i18n('menu_file'),
      menus: [
        group([command('menu_open_link', AppCommand.openLink), page('multiview_title', RoutePath.kMultiview)]),
        group([
          PlatformMenuItem(
            label: i18n('window_close'),
            shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
            onSelected: () => unawaited(DesktopShell.current?.requestClose()),
          ),
        ]),
      ],
    ),
    PlatformMenu(
      label: i18n('menu_edit'),
      menus: [
        group([
          edit('menu_undo', const UndoTextIntent(cause), const SingleActivator(LogicalKeyboardKey.keyZ, meta: true)),
          edit(
            'menu_redo',
            const RedoTextIntent(cause),
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
          ),
        ]),
        group([
          edit(
            'menu_cut',
            const CopySelectionTextIntent.cut(cause),
            const SingleActivator(LogicalKeyboardKey.keyX, meta: true),
          ),
          edit('menu_copy', CopySelectionTextIntent.copy, const SingleActivator(LogicalKeyboardKey.keyC, meta: true)),
          edit('menu_paste', const PasteTextIntent(cause), const SingleActivator(LogicalKeyboardKey.keyV, meta: true)),
          edit(
            'menu_select_all',
            const SelectAllTextIntent(cause),
            const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
          ),
        ]),
        group([command('menu_search', AppCommand.search)]),
      ],
    ),
    PlatformMenu(
      label: i18n('menu_view'),
      menus: [
        group([
          command('favorites_title', AppCommand.favorites),
          command('popular_title', AppCommand.popular),
          command('areas_title', AppCommand.areas),
          command('record_center', AppCommand.record),
          command('watch_history', AppCommand.history),
        ]),
        group([command('menu_back', AppCommand.back)]),
        // ⌃⌘F, the system's full screen space.
        group(provided([PlatformProvidedMenuItemType.toggleFullScreen])),
      ],
    ),
    PlatformMenu(
      label: i18n('menu_playback'),
      menus: [
        PlatformMenuItem(
          label: i18n('menu_play_pause'),
          onSelected: room == null ? null : () => unawaited(room.togglePlay()),
        ),
        PlatformMenuItem(
          label: i18n('refresh'),
          shortcut: refreshActivator,
          onSelected: room == null ? null : () => unawaited(room.refresh()),
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(label: i18n('menu_volume'), onSelected: room?.volume),
            PlatformMenuItem(
              label: i18n('show_danmaku'),
              onSelected: room == null ? null : () => unawaited(room.toggleDanmaku()),
            ),
            PlatformMenuItem(label: i18n('danmaku_settings'), onSelected: room?.danmakuSettings),
            PlatformMenuItem(
              label: i18n('audio_only_mode'),
              onSelected: room == null ? null : () => unawaited(room.toggleAudioOnly()),
            ),
            PlatformMenuItem(label: i18n('record'), onSelected: room?.record),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(label: i18n('live_play_fullscreen'), onSelected: room?.toggleFullScreen),
            PlatformMenuItem(label: i18n('menu_window_fullscreen'), onSelected: room?.toggleWindowFullScreen),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: i18n('menu_window'),
      menus: [
        group(provided([PlatformProvidedMenuItemType.minimizeWindow, PlatformProvidedMenuItemType.zoomWindow])),
        group(provided([PlatformProvidedMenuItemType.arrangeWindowsInFront])),
      ],
    ),
    PlatformMenu(
      label: i18n('help'),
      menus: [
        PlatformMenuItem(
          label: i18n('project_page'),
          onSelected: () => unawaited(AppNavigator.openExternal(projectUrl)),
        ),
        page('update_log', RoutePath.kVersionPage),
      ],
    ),
  ];
}
