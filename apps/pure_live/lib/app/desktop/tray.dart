import 'dart:async';

import 'package:nativeapi/nativeapi.dart' show Size;
import 'package:pure_live/app/desktop/app_window_api.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:tray_manager/tray_manager.dart';

/// The rows of the tray menu (3.x `DesktopTrayService`; docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口
/// c9, T4): while recording, "正在录制 N 个直播间" (greyed) and a separator
/// first; then "隐藏窗口 / 显示窗口", a separator and "退出应用".
enum TrayRow {
  /// "正在录制 N 个直播间", not clickable.
  recording,

  /// "录制中心…" under it (the Mac's menu bar icon, A18.2 c7).
  recordCenter,

  /// A line.
  separator,

  /// "隐藏窗口" or "显示窗口".
  window,

  /// "退出应用" (asks first while recording).
  exit,
}

/// The tray menu's rows while [recording] rooms record; [mac] adds
/// "录制中心…" under the count (A18.2 c7).
List<TrayRow> trayMenuRows({required int recording, bool mac = false}) => [
  if (recording > 0) ...[TrayRow.recording, if (mac) TrayRow.recordCenter, TrayRow.separator],
  TrayRow.window,
  TrayRow.separator,
  TrayRow.exit,
];

/// The words of [row] ([visible]: the window is showing).
String trayRowLabel(TrayRow row, {required bool visible, required int recording}) => switch (row) {
  TrayRow.recording => i18n('recording_rooms_count', args: {'count': '$recording'}),
  TrayRow.recordCenter => '${i18n('record_center')}…',
  TrayRow.separator => '',
  TrayRow.window => i18n(visible ? 'hide_window' : 'show_window'),
  TrayRow.exit => i18n('exit_app'),
};

/// The tray icon's hint: "纯粹直播", and how many rooms record (T4).
String trayTooltip({required int recording}) =>
    recording > 0 ? i18n('tray_tooltip_recording', args: {'count': '$recording'}) : i18nOr('app_name', 'PureLive');

/// The tray icon of the main window (3.x `DesktopTrayService`): a click
/// shows the window, the menu shows or hides it and exits; while recording
/// the hint and the menu's first row say how many rooms (U.13 c9). The
/// native objects are made once and reused (3.x: new items per right-click
/// piled up callbacks).
///
/// On a Mac (A18.2 c7) it sits in the menu bar: a one-colour (template)
/// icon that follows the bar's light or dark, the app icon with a red dot
/// while recording; either button opens the menu, which also has
/// "录制中心…" while recording.
final class DesktopTray {
  new _(
    this._icon,
    this._image,
    this._menu,
    this._recordingItem,
    this._windowItem,
    this._exitItem, {
    required this.mac,
    this._recordCenterItem,
    this._recordingImage,
  });

  /// Makes the tray icon; throws when the system refuses. [onExit] is the
  /// menu's "退出应用".
  factory create({
    required Future<void> Function() onShow,
    required Future<void> Function() onHide,
    required Future<void> Function() onExit,
    bool mac = false,
    Future<void> Function()? onRecordCenter,
  }) {
    final icon = TrayIcon.create() ?? (throw StateError('No tray icon'));
    Image asset(String path) => ImageAsset.fromAsset(path) ?? (throw StateError('No tray image'));
    final image = asset(mac ? 'assets/icons/tray_template.png' : 'assets/icons/icon.png');
    final menu = Menu.create() ?? (throw StateError('No tray menu'));
    MenuItem item() => MenuItem.createWithLabelAndType('', MenuItemType.normal) ?? (throw StateError('No menu item'));
    final recordingItem = item()..isEnabled = false;
    final windowItem = item();
    final exitItem = item();
    final recordCenterItem = mac ? item() : null;
    final tray = DesktopTray._(
      icon,
      image,
      menu,
      recordingItem,
      windowItem,
      exitItem,
      mac: mac,
      recordCenterItem: recordCenterItem,
      recordingImage: mac ? asset('assets/icons/tray_recording.png') : null,
    );
    icon
      ..icon = image
      // The menu is relabelled before it opens (the window may have been
      // hidden meanwhile), so it is not opened by the system on release.
      ..setContextMenuTrigger(ContextMenuTrigger.none);
    if (mac) {
      icon
        ..isIconTemplate = true
        ..iconSize = const Size(width: 18, height: 18);
    }
    tray._listeners.add(() {
      final id = icon.addListener((event) {
        // The Mac's menu bar icons open their menu with either button.
        if (event is TrayIconClickedEvent) unawaited(mac ? tray._openMenu() : onShow());
        if (event is TrayIconRightClickedEvent) unawaited(tray._openMenu());
      });
      return () => icon.removeListener(id);
    }());
    if (recordCenterItem != null && onRecordCenter != null) {
      tray._listeners.add(() {
        final id = recordCenterItem.addListener((event) {
          if (event is MenuItemClickedEvent) unawaited(onRecordCenter());
        });
        return () => recordCenterItem.removeListener(id);
      }());
    }
    Future<void> toggle() async {
      if (await appWindow.isVisible()) {
        await onHide();
      } else {
        await onShow();
      }
    }

    tray._listeners.add(() {
      final id = windowItem.addListener((event) {
        if (event is MenuItemClickedEvent) unawaited(toggle());
      });
      return () => windowItem.removeListener(id);
    }());
    tray._listeners.add(() {
      final id = exitItem.addListener((event) {
        if (event is MenuItemClickedEvent) unawaited(onExit());
      });
      return () => exitItem.removeListener(id);
    }());
    tray._fill(visible: true);
    icon.setContextMenu(menu);
    if (!icon.setVisible(true)) {
      tray.dispose();
      throw StateError('The tray icon was not shown');
    }
    return tray;
  }

  /// The Mac's menu bar icon.
  final bool mac;

  final TrayIcon _icon;
  final Image _image;
  final Menu _menu;
  final MenuItem _recordingItem;
  final MenuItem _windowItem;
  final MenuItem _exitItem;
  final MenuItem? _recordCenterItem;
  final Image? _recordingImage;
  final List<void Function()> _listeners = [];
  int _recording = 0;

  /// Fills the menu with [trayMenuRows] and their words.
  void _fill({required bool visible}) {
    _menu.clear();
    for (final row in trayMenuRows(recording: _recording, mac: mac)) {
      final item = switch (row) {
        TrayRow.recording => _recordingItem,
        TrayRow.recordCenter => _recordCenterItem,
        TrayRow.window => _windowItem,
        TrayRow.exit => _exitItem,
        TrayRow.separator => null,
      };
      if (item == null) {
        _menu.addSeparator();
      } else {
        item.label = trayRowLabel(row, visible: visible, recording: _recording);
        _menu.addItem(item);
      }
    }
    _icon.setTooltip(trayTooltip(recording: _recording));
  }

  /// How many rooms record: only the hint changes now, the menu when it
  /// opens.
  void setRecording(int count) {
    if (count == _recording) return;
    final was = _recording;
    _recording = count;
    _icon.setTooltip(trayTooltip(recording: count));
    // The Mac: the red dot while recording, the one-colour icon otherwise.
    if (_recordingImage case final recording? when (was > 0) != (count > 0)) {
      _icon
        ..isIconTemplate = count == 0
        ..icon = count > 0 ? recording : _image;
    }
  }

  /// Updates the words (the language may have changed).
  void relabel({bool visible = true}) => _fill(visible: visible);

  Future<void> _openMenu() async {
    relabel(visible: await appWindow.isVisible());
    _icon.openContextMenu();
  }

  /// Removes the icon.
  void dispose() {
    for (final remove in _listeners) {
      remove();
    }
    _listeners.clear();
    _icon
      ..setContextMenu(null)
      ..setVisible(false)
      ..dispose();
    _menu.dispose();
    _recordingItem.dispose();
    _windowItem.dispose();
    _exitItem.dispose();
    _recordCenterItem?.dispose();
    _image.dispose();
    _recordingImage?.dispose();
  }
}
