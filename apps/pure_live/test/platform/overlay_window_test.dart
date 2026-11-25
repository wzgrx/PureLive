import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/overlay_window.dart';

import '../features/settings/settings_harness.dart';
import '../support.dart';

const _pip = MethodChannel('pure_live/pip');
const _overlay = MethodChannel('pure_live/overlay');

void main() {
  setUpAll(() async => currentStrings = await loadStrings());

  test(
    'D-042: the mini window is the app floating window unless the system one is chosen; leaving only when asked',
    () async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      final settings = store.settings;
      expect(
        miniWindowKind(settings),
        LeaveAppWindow.overlay,
        reason: 'the button: the app floating window by default',
      );
      expect(
        leaveAppWindow(settings),
        LeaveAppWindow.none,
        reason: 'leaving the app does nothing unless asked, as before',
      );
      await settings.set(Settings.autoPipOnLeave, true);
      expect(leaveAppWindow(settings), LeaveAppWindow.overlay);
      await settings.set(Settings.useSystemPip, true);
      expect((miniWindowKind(settings), leaveAppWindow(settings)), (LeaveAppWindow.pip, LeaveAppWindow.pip));
    },
  );

  test('once: who had "离开应用时自动画中画" on keeps the picture-in-picture; others get the floating window', () async {
    final store = await LiveStore.memory(cipher: FakeCipher());
    addTearDown(store.close);
    final settings = store.settings;
    await settings.set(Settings.autoPipOnLeave, true);
    await keepPictureInPicture(settings);
    expect(settings.get(Settings.useSystemPip), isTrue);
    // Chosen since: never overwritten.
    await settings.set(Settings.useSystemPip, false);
    await keepPictureInPicture(settings);
    expect(settings.get(Settings.useSystemPip), isFalse);

    final fresh = await LiveStore.memory(cipher: FakeCipher());
    addTearDown(fresh.close);
    await keepPictureInPicture(fresh.settings);
    expect(fresh.settings.get(Settings.useSystemPip), isFalse);
    expect(fresh.settings.isSet(Settings.useSystemPip), isTrue);
  });

  group('arming', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      PictureInPicture.debugAndroid = true;
      OverlayWindow.debugAndroid = true;
      for (final channel in [_pip, _overlay]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          calls.add(call);
          return null;
        });
      }
    });

    tearDown(() {
      PictureInPicture.debugAndroid = null;
      OverlayWindow.debugAndroid = null;
      OverlayWindow.permitted.value = false;
      for (final channel in [_pip, _overlay]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      }
    });

    /// Whether the last [method] call armed it; false when there was none
    /// (a disarm by someone who did not arm sends nothing).
    bool armed(String method) {
      final call = calls.where((call) => call.method == method).lastOrNull;
      return (call?.arguments as Map?)?['enabled'] == true;
    }

    final owner = Object();

    Future<void> arm(LeaveAppWindow choice, {bool playing = true}) => armLeaveWindow(
      choice: choice,
      playing: playing,
      width: 16,
      height: 9,
      window: const Rect.fromLTWH(10, 20, 320, 180),
      pixelRatio: 3,
      owner: owner,
    );

    test('the floating window, with the permission: armed at the place in pixels, the system one not', () async {
      OverlayWindow.permitted.value = true;
      await arm(LeaveAppWindow.overlay);
      expect(armed('setAutoEnter'), isFalse);
      expect(calls.lastWhere((call) => call.method == 'arm').arguments, {
        'enabled': true,
        'x': 30,
        'y': 60,
        'width': 960,
        'height': 540,
      });
    });

    test('the floating window without the permission: neither (nothing appears, as before)', () async {
      await arm(LeaveAppWindow.overlay);
      expect(armed('setAutoEnter'), isFalse);
      expect(armed('arm'), isFalse);
    });

    test('A07.25 c8: where the native window went comes back in logical pixels, with its tucked side', () {
      expect(OverlayWindow.placedFrom({'x': 30, 'y': 60, 'width': 660, 'height': 372, 'tucked': 'right'}, 3), (
        rect: const Rect.fromLTWH(10, 20, 220, 124),
        tucked: 'right',
      ));
      expect(
        OverlayWindow.placedFrom({'x': -3, 'y': 6, 'width': 300, 'height': 150, 'tucked': null}, 3)?.tucked,
        isNull,
      );
      expect(OverlayWindow.placedFrom({'x': 0, 'y': 0, 'width': 0, 'height': 0}, 3), isNull);
      expect(OverlayWindow.placedFrom('junk', 3), isNull);
    });

    test("the system's picture-in-picture: that one, not the floating window; nothing while not playing", () async {
      OverlayWindow.permitted.value = true;
      await arm(LeaveAppWindow.pip);
      expect(armed('setAutoEnter'), isTrue);
      expect(armed('arm'), isFalse);
      await arm(LeaveAppWindow.pip, playing: false);
      expect(armed('setAutoEnter'), isFalse);
    });
  });

  testWidgets(
    'A07.25: the video settings: automatic mini window, the system picture-in-picture switch, the permission',
    (tester) async {
      OverlayWindow.permitted.value = false;
      final h = await pumpSettings(tester, height: 2600, arguments: 'video');
      for (final (id, text) in [
        ('auto_pip', '离开应用时自动小窗'),
        ('overlay_permission', '在其他应用上层显示小窗'),
        ('system_pip', '改用系统画中画'),
      ]) {
        await tester.ensureVisible(settingsRow(id));
        expect(
          find.descendant(of: settingsRow(id), matching: find.text(text)),
          findsOneWidget,
          reason: id,
        );
      }
      expect(find.descendant(of: settingsRow('overlay_permission'), matching: find.text('未开启')), findsOneWidget);
      await tapSettings(tester, find.descendant(of: settingsRow('system_pip'), matching: find.byType(Switch)));
      expect(h.services.store.settings.get(Settings.useSystemPip), isTrue);
    },
  );
}
