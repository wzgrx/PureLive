import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/commands.dart';
import 'package:pure_live/app/desktop/mac_menu_bar.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/settings/settings_page.dart';
import 'package:pure_live/i18n/i18n.dart';

import 'support.dart';

/// A room that records what the menu asked of it.
final class _FakeRoom implements RoomCommands {
  final List<String> calls = [];

  @override
  Future<void> togglePlay() async => calls.add('play');

  @override
  Future<void> refresh() async => calls.add('refresh');

  @override
  void toggleFullScreen() => calls.add('fullscreen');

  @override
  void toggleWindowFullScreen() => calls.add('window');

  @override
  Future<void> toggleDanmaku() async => calls.add('danmaku');

  @override
  void danmakuSettings() => calls.add('danmaku settings');

  @override
  Future<void> toggleAudioOnly() async => calls.add('audio');

  @override
  void volume() => calls.add('volume');

  @override
  void record() => calls.add('record');
}

String _keys(MenuSerializableShortcut? shortcut) {
  if (shortcut is! SingleActivator) return '';
  return '${shortcut.control ? '⌃' : ''}${shortcut.shift ? '⇧' : ''}${shortcut.meta ? '⌘' : ''}${shortcut.trigger.keyLabel}';
}

/// "label ⌘K" for every item of [menu], groups flattened.
List<String> _items(PlatformMenuItem menu) => [
  for (final item in (menu as PlatformMenu).menus)
    if (item is PlatformMenuItemGroup)
      for (final member in item.members) '${member.label} ${_keys(member.shortcut)}'.trim()
    else
      '${item.label} ${_keys(item.shortcut)}'.trim(),
];

void main() {
  setUpAll(() async => currentStrings = await loadStrings());
  tearDown(() => RoomCommands.current.value = null);

  test('A18.2 c4: the menus in the Mac order, in the app language, with the ⌘ keys of one table (c5)', () {
    final menus = macMenus();
    expect([for (final menu in menus) menu.label], ['纯粹直播', '文件', '编辑', '显示', '播放', '窗口', '帮助']);
    // The system's own items (services, hide, quit, full screen, the window
    // menu) are only there on a Mac; the app's are everywhere.
    expect(_items(menus[0]), ['关于纯粹直播', '检查更新…', '设置… ⌘,']);
    expect(_items(menus[1]), ['链接解析… ⌘L', '多画面', '关闭窗口 ⌘W']);
    expect(_items(menus[2]), ['撤销 ⌘Z', '重做 ⇧⌘Z', '剪切 ⌘X', '拷贝 ⌘C', '粘贴 ⌘V', '全选 ⌘A', '搜索直播… ⌘F']);
    expect(_items(menus[3]), ['关注 ⌘1', '热门 ⌘2', '分区 ⌘3', '录制中心 ⌘4', '观看记录 ⌘Y', '返回 ⌘[']);
    expect(_items(menus[4]), ['播放 / 暂停', '刷新 ⌘R', '音量', '显示弹幕', '弹幕设置', '纯音频模式', '录制', '全屏', '窗口内全屏']);
    expect(_items(menus[6]), ['项目主页', '更新日志']);
  });

  test('A18.2 c4: "播放" works only in a room; there each item does its button\'s thing', () {
    List<PlatformMenuItem> playback(RoomCommands? room) => [
      for (final item in (macMenus(room: room)[4] as PlatformMenu).menus)
        if (item is PlatformMenuItemGroup) ...item.members else item,
    ];
    expect([for (final item in playback(null)) item.onSelected], everyElement(isNull), reason: 'greyed elsewhere');
    final room = _FakeRoom();
    for (final item in playback(room)) {
      item.onSelected!();
    }
    expect(room.calls, [
      'play',
      'refresh',
      'volume',
      'danmaku',
      'danmaku settings',
      'audio',
      'record',
      'fullscreen',
      'window',
    ]);
  });

  testWidgets('A18.2 c4: on a Mac the menus go to the system, and change when a room opens', (tester) async {
    final sent = <List<String>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.menu, (call) async {
      if (call.method == 'Menu.setMenus') {
        final menus = ((call.arguments as Map)['0'] as List).cast<Map<Object?, Object?>>();
        sent.add([for (final menu in menus) '${menu['label']}${menu['enabled'] == false ? ' (off)' : ''}']);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.menu, null));
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(const MaterialApp(home: MacMenuBar(child: Text('app'))));
      expect(sent.last, ['纯粹直播', '文件', '编辑', '显示', '播放', '窗口', '帮助']);
      final before = sent.length;
      RoomCommands.current.value = _FakeRoom();
      await tester.pump();
      expect(sent.length, greaterThan(before), reason: 'the "播放" items are enabled anew');
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('A18.1 c10: an iPad keyboard has the same ⌘ keys; ⌘R reloads the room on top', (tester) async {
    final room = _FakeRoom();
    RoomCommands.current.value = room;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppCommandShortcuts(child: Focus(autofocus: true, child: Text('app'))),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(room.calls, ['refresh']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('A18.1 c10: the iPad lists the ⌘ keys through the system, which runs them; a key does not run twice', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('pure_live/key_commands');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'set' ? true : null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      IosKeyCommands.debugReset();
      RoomCommands.current.value = null;
    });
    IosKeyCommands.debugReset();
    final room = _FakeRoom();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppCommandShortcuts(child: Focus(autofocus: true, child: Text('app'))),
        ),
      );
      await tester.pump();
      final set = calls.firstWhere((call) => call.method == 'set').arguments as Map;
      expect(set['title'], '纯粹直播');
      expect(
        [
          for (final command in (set['commands'] as List).cast<Map<Object?, Object?>>())
            '${command['group']} ${command['input']} ${command['title']}',
        ],
        [
          'go f 搜索直播…',
          'go l 链接解析…',
          'go , 设置…',
          'pages 1 关注',
          'pages 2 热门',
          'pages 3 分区',
          'pages 4 录制中心',
          'pages y 观看记录',
          'back [ 返回',
          'room r 刷新',
        ],
      );
      expect(IosKeyCommands.active.value, isTrue);
      expect(calls.last, isMethodCall('room', arguments: false));
      RoomCommands.current.value = room;
      await tester.pump();
      expect(calls.last, isMethodCall('room', arguments: true), reason: '⌘R is offered in a room');

      // The system runs ⌘R once; the key no longer reaches the Dart shortcuts.
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'pure_live/key_commands',
        const StandardMethodCodec().encodeMethodCall(const MethodCall('run', 'refresh')),
        (_) {},
      );
      expect(room.calls, ['refresh']);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(room.calls, ['refresh'], reason: 'the system already has the key');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('A18.2 c5: ⌘, opens the settings; ⌘2 goes back home to popular; ⌘[ goes back', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(() async {
      final services = await testServices();
      await services.store.settings.set(Settings.showSplashPage, false);
      return services;
    }))!;
    final strings = (await tester.runAsync(loadStrings))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
      ),
    );
    await tester.pumpAndSettle();

    AppCommand.settings.run();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    AppCommand.back.run();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);

    AppCommand.settings.run();
    await tester.pumpAndSettle();
    AppCommand.popular.run();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(HomeSignals.select.value?.$1, HomeMenu.popular);
  });
}
