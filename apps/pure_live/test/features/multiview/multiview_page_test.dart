// docs/A-界面设计/A13-网络电视和多画面界面/A13.2-多画面: the multi-view page in portrait, landscape and wide
// windows; the order, icons and places of its controls; the cells' states;
// UI_PLAN appendix A 7 (Back and Esc) and 13 (tap, 1+3, long press, empty
// cells).
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/record/record_panel.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/features/multiview/multiview_page.dart';
import 'package:pure_live/features/multiview/widgets/cell_controls.dart';
import 'package:pure_live/features/multiview/widgets/cell_view.dart';
import 'package:pure_live/features/multiview/widgets/toolbar.dart';
import 'package:pure_live/platform/display_mode.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';

import '../../qa_capture.dart';
import '../../support.dart';
import '../live_play/live_play_support.dart';
import 'multiview_support.dart';

final _recorders = <AppServices, (AppRecording, io.Directory)>{};

final class _NoRecordProcess implements FfmpegRunner {
  @override
  Future<FfmpegExecution> start(List<String> arguments) => throw UnsupportedError('no native recording in widgets');
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<(AppServices, RoomsSite)> _pump(
  WidgetTester tester,
  Size size, {
  List<String> rooms = const ['1', '2', '3'],
  ThemeMode theme = ThemeMode.light,
  bool routed = false,
  bool withRecorder = false,
  List<Override> overrides = const [],
  LiveFontSizes fontSizes = const LiveFontSizes(),
}) async {
  await prepareQaFonts(tester);
  String? reviewFamily;
  final reviewFont = io.Platform.environment['PURELIVE_QA_FONT'];
  if (io.Platform.environment['PURELIVE_QA_DIR'] != null && reviewFont != null && reviewFont.isNotEmpty) {
    reviewFamily = 'PureLiveQaCjk';
    await tester.runAsync(() async {
      final data = ByteData.sublistView(await io.File(reviewFont).readAsBytes());
      await (FontLoader(reviewFamily!)..addFont(Future.value(data))).load();
    });
  }
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  await tester.runAsync(() async {
    for (final id in rooms) {
      await services.store.follows.add(pickRoom(id));
    }
  });
  final site = RoomsSite();
  if (withRecorder) {
    await tester.runAsync(() async {
      final folder = await io.Directory.systemTemp.createTemp('purelive-multiview-record-');
      final recording = buildAppRecording(
        store: services.store,
        sites: services.sites,
        proxy: services.proxy,
        dataRoot: folder,
        ffmpeg: _NoRecordProcess(),
      );
      await recording.loadSettings();
      _recorders[services] = (recording, folder);
    });
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
        if (_recorders[services] case final pair?) recordingProvider.overrideWithValue(pair.$1),
        ...overrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: LiveTheme(fontSizes: fontSizes, fontFamily: reviewFamily).light,
        darkTheme: LiveTheme(fontSizes: fontSizes, fontFamily: reviewFamily).dark,
        themeMode: theme,
        home: routed
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MultiviewPage(route: RouteArgs(RoutePath.kMultiview)),
                      ),
                    ),
                    child: const Text('open-multi'),
                  ),
                ),
              )
            : const MultiviewPage(route: RouteArgs(RoutePath.kMultiview)),
      ),
    ),
  );
  if (routed) {
    await tester.tap(find.text('open-multi'));
    await tester.pumpAndSettle();
  }
  await _wait(tester);
  return (services, site);
}

Future<void> _wait(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _pick(WidgetTester tester, String id) async {
  await tester.ensureVisible(_key('multiview-pick-bilibili:$id'));
  await tester.tap(_key('multiview-pick-bilibili:$id'));
  await _wait(tester);
}

Future<void> _close(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(seconds: 5));
  if (_recorders.remove(services) case final pair?) {
    await tester.runAsync(() async {
      await pair.$1.dispose();
      await pair.$2.delete(recursive: true);
    });
  }
  await tester.runAsync(services.close);
}

Finder _inCell(int position, Finder finder) => find.descendant(of: _key('multiview-cell-$position'), matching: finder);

MultiviewCellView _cellView(WidgetTester tester, int position) => tester.widget<MultiviewCellView>(
  find.ancestor(of: _key('multiview-cell-$position'), matching: find.byType(MultiviewCellView)),
);

void _expectLeftToRight(WidgetTester tester, List<String> keys) {
  for (var i = 1; i < keys.length; i++) {
    expect(tester.getCenter(_key(keys[i])).dx, greaterThan(tester.getCenter(_key(keys[i - 1])).dx), reason: keys[i]);
  }
}

void main() {
  testWidgets('issue214: remember projection display, primary tap toggles, secondary opens settings', (tester) async {
    final (services, _) = await _pump(
      tester,
      const Size(1280, 800),
      rooms: [],
      overrides: [projectionDisplaysProvider.overrideWithValue(() => [])],
    );
    final button = _key('multiview-projection');
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.tap(_key('projection-current'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle();
    expect(services.store.settings.get(Settings.multiviewProjectionDisplay), '');
    expect(tester.widget<ToolbarToggle>(button).on, isTrue);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.widget<ToolbarToggle>(button).on, isFalse);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    expect(tester.widget<ToolbarToggle>(button).on, isTrue);
    await tester.tap(button, buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _close(tester, services);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('issue123 F F11 and I toggle display modes and leave text entry alone', (tester) async {
    final (services, _) = await _pump(tester, const Size(1280, 800));
    await _pick(tester, '1');
    final session = _cellView(tester, 1).cell.session;
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await _wait(tester);
    expect(_key('multiview-fullscreen-exit'), findsOneWidget);
    expect(_cellView(tester, 1).cell.session, same(session));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await _wait(tester);
    expect(_key('multiview-fullscreen'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await _wait(tester);
    expect(_key('multiview-immersive-exit'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await _wait(tester);
    expect(_key('multiview-fullscreen-exit'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _wait(tester);
    await tester.tap(_key('multiview-picker-search'));
    for (final key in [LogicalKeyboardKey.keyF, LogicalKeyboardKey.keyI, LogicalKeyboardKey.f11]) {
      await tester.sendKeyEvent(key);
      await _wait(tester);
      expect(_key('multiview-fullscreen'), findsOneWidget);
    }
    await _close(tester, services);
  });

  testWidgets('issue #85: an open recording panel stays bound when its cell switches rooms', (tester) async {
    final (services, _) = await _pump(tester, const Size(393, 852), withRecorder: true);
    await _pick(tester, '1');
    final controls = tester.widget<MultiviewCellControls>(find.byType(MultiviewCellControls));
    await tester.tap(_key('multiview-control-record'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => controls.controller.assign(controls.index, pickRoom('3')));
    await _wait(tester);
    final panel = tester.widget<RoomRecordPanel>(find.byType(RoomRecordPanel));
    expect(panel.room().roomId, '1', reason: 'record the room the user selected, not an automatic replacement');
    expect(controls.controller.cells[controls.index].room?.roomId, '3');
    panel.onClose();
    await tester.pumpAndSettle();
    await _close(tester, services);
  });

  for (final size in [const Size(393, 852), const Size(740, 360), const Size(1280, 800)]) {
    testWidgets('issue #85: selected cell opens its own shared recorder at $size', (tester) async {
      final (services, _) = await _pump(tester, size, withRecorder: true);
      await _pick(tester, '1');
      await _pick(tester, '2');
      final sessions = [_cellView(tester, 1).cell.session, _cellView(tester, 2).cell.session];
      for (final position in [1, 2]) {
        await tester.tap(_key('multiview-cell-$position'));
        await _wait(tester);
        await tester.ensureVisible(_key('multiview-control-record'));
        await tester.tap(_key('multiview-control-record'));
        await tester.pumpAndSettle();
        final panel = tester.widget<RoomRecordPanel>(find.byType(RoomRecordPanel));
        expect(panel.room().roomId, '$position');
        expect(find.text('开始录制'), findsOneWidget);
        expect(tester.takeException(), isNull);
        panel.onClose();
        await tester.pumpAndSettle();
        expect(_cellView(tester, 1).cell.session, same(sessions[0]));
        expect(_cellView(tester, 2).cell.session, same(sessions[1]));
      }
      await _close(tester, services);
    });
  }
  testWidgets('issue #85: iOS edge back safely exits multiview after removing video', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final (services, _) = await _pump(tester, const Size(393, 852), routed: true);
    await _pick(tester, '1');
    await tester.dragFrom(const Offset(6, 300), const Offset(150, 0));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(MultiviewPage), findsNothing);
    expect(find.text('open-multi'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
    expect(tester.takeException(), isNull);
    await _close(tester, services);
  });

  for (final mode in ['immersive', 'fullscreen']) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('issue #43: direct picker targets the right-clicked cell in $mode, ${theme.name}', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final (services, _) = await _pump(tester, const Size(1280, 800), theme: theme);
        try {
          await _pick(tester, '1');
          await _pick(tester, '2');
          await tester.tap(_key('multiview-cell-1'));
          await _wait(tester);
          final firstSession = _cellView(tester, 1).cell.session;
          final firstVolume = _cellView(tester, 1).cell.volume;
          await tester.tap(_key('multiview-$mode'));
          await _wait(tester);
          await tester.tap(_key('multiview-cell-2'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
          await _wait(tester);
          await captureQaFrame(tester, 'multiview-direct-$mode-${theme.name}');
          expect(_key('multiview-cell-panel'), findsOneWidget);
          expect(
            _key('multiview-picker-search'),
            findsOneWidget,
            reason: 'pick directly below volume, without another icon',
          );
          expect(find.text('第 2 格换台'), findsOneWidget, reason: 'do not target empty cell 3');
          expect(_inCell(3, _key('multiview-pick-frame')), findsNothing);
          expect(_inCell(1, _key('multiview-audio-badge')), findsOneWidget, reason: 'right click keeps audio focus');
          expect(
            tester.getBottomLeft(_key('multiview-volume-slider')).dy,
            lessThan(tester.getTopLeft(_key('multiview-picker-title')).dy),
          );
          await _pick(tester, '3');
          expect(_cellView(tester, 2).cell.room!.roomId, '3');
          expect(_cellView(tester, 3).cell.stage, CellStage.empty);
          expect(_cellView(tester, 1).cell.session, same(firstSession));
          expect(_cellView(tester, 1).cell.volume, firstVolume);
          expect(_key('multiview-cell-panel'), findsNothing);
          expect(_key('multiview-$mode-exit'), findsOneWidget, reason: 'selection keeps the viewing mode');
          await tester.tap(_key('multiview-cell-2'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
          await _wait(tester);
          await _pick(tester, '1');
          expect(
            _cellView(tester, 2).cell.room!.roomId,
            '3',
            reason: 'an already-shown room is selected, not duplicated',
          );
          expect(_cellView(tester, 1).cell.session, same(firstSession));
          expect(_inCell(1, _key('multiview-audio-badge')), findsOneWidget);
          expect(_key('multiview-cell-panel'), findsNothing);
          await tester.tap(_key('multiview-cell-2'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
          await _wait(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _wait(tester);
          expect(_key('multiview-cell-panel'), findsNothing);
          expect(_key('multiview-$mode-exit'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _wait(tester);
          expect(find.text('多画面'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await _close(tester, services);
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  testWidgets('issue #43: direct picker remains reachable in a short panel with large text', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    const largest = LiveFontSizes(bodySmall: 15, bodyMedium: 17, bodyLarge: 18, titleMedium: 20, titleLarge: 26);
    final (services, _) = await _pump(tester, const Size(740, 360), fontSizes: largest);
    try {
      await _pick(tester, '1');
      await tester.tap(_key('multiview-immersive'));
      await _wait(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pump();
      await tester.tap(_key('multiview-cell-1'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await _wait(tester);
      expect(_key('multiview-picker-search'), findsOneWidget);
      await tester.ensureVisible(_key('multiview-volume-slider'));
      await _wait(tester);
      expect(_key('multiview-volume-slider').hitTestable(), findsOneWidget);
      final percent = tester.renderObject<RenderParagraph>(_key('multiview-volume-value'));
      final percentStyle = percent.text.style!;
      expect(
        percent.size.height,
        lessThanOrEqualTo(percent.textScaler.scale(percentStyle.fontSize!) * (percentStyle.height ?? 1.5) + 1),
        reason: 'the volume percentage stays on one line with two-times system text',
      );
      await captureQaFrame(tester, 'multiview-direct-short-large');
      await _pick(tester, '3');
      expect(_cellView(tester, 1).cell.room!.roomId, '3');
      expect(_cellView(tester, 2).cell.stage, CellStage.empty);
      expect(tester.takeException(), isNull);
    } finally {
      await _close(tester, services);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('issue #43: a wide upright window keeps both controls and the direct picker', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final (services, _) = await _pump(tester, const Size(1080, 1920));
    try {
      await _pick(tester, '1');
      await tester.tap(_key('multiview-fullscreen'));
      await _wait(tester);
      await tester.tap(_key('multiview-cell-1'), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await _wait(tester);
      expect(_key('multiview-picker-search'), findsOneWidget);
      expect(
        tester.getBottomLeft(_key('multiview-volume-slider')).dy,
        lessThan(tester.getTopLeft(_key('multiview-picker-title')).dy),
      );
      await captureQaFrame(tester, 'multiview-direct-upright');
      await _pick(tester, '3');
      expect(_cellView(tester, 1).cell.room!.roomId, '3');
      expect(tester.takeException(), isNull);
    } finally {
      await _close(tester, services);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('issue #87: four audio badges follow normal and bare mode controls', (tester) async {
    final (services, _) = await _pump(tester, const Size(1280, 800), rooms: ['1', '2', '3', '4']);
    for (final room in ['1', '2', '3', '4']) {
      await _pick(tester, room);
    }
    expect(_key('multiview-audio-badge'), findsOneWidget);
    await tester.tap(_key('multiview-mix-audio'));
    await _wait(tester);
    expect(_key('multiview-audio-badge'), findsNWidgets(4));
    expect(services.store.settings.get(Settings.multiviewMixAudio), isTrue);
    await tester.tap(_key('multiview-mute-all'));
    await _wait(tester);
    expect(_key('multiview-audio-badge'), findsNothing);
    await tester.tap(_key('multiview-mute-all'));
    await _wait(tester);
    expect(_key('multiview-audio-badge'), findsNWidgets(4));
    for (final mode in ['immersive', 'fullscreen']) {
      await tester.tap(_key('multiview-$mode'));
      await _wait(tester);
      final mix = _key('multiview-bare-mix-audio');
      expect(tester.getSize(mix), const Size.square(48));
      expect(tester.getRect(mix).overlaps(tester.getRect(_key('multiview-bare-mute-all'))), isFalse);
      await tester.tap(mix);
      await _wait(tester);
      expect(_key('multiview-audio-badge'), findsOneWidget);
      await tester.tap(mix);
      await _wait(tester);
      expect(_key('multiview-audio-badge'), findsNWidgets(4));
      await tester.tap(_key('multiview-$mode-exit'));
      await _wait(tester);
    }
    expect(tester.takeException(), isNull);
    await _close(tester, services);
  });

  testWidgets('issue #87: multi-audio has an explicit opt-in control', (tester) async {
    final (services, _) = await _pump(tester, const Size(1280, 800));
    expect(_key('multiview-mix-audio'), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('issue #32: choose vertical, keep sessions on resize and enter fullscreen', (tester) async {
    final (services, _) = await _pump(tester, const Size(1080, 1920));
    await _pick(tester, '1');
    final session = _cellView(tester, 1).cell.session;
    await captureQaFrame(tester, 'multiview-before-quad-portrait-monitor');
    final vertical = _key('multiview-layout-vertical');
    expect(vertical, findsOneWidget);
    await tester.ensureVisible(vertical);
    await tester.tap(vertical);
    await _wait(tester);
    void expectStack() {
      for (var position = 2; position <= 4; position++) {
        final before = tester.getRect(_key('multiview-cell-${position - 1}'));
        final cell = tester.getRect(_key('multiview-cell-$position'));
        expect(cell.left, before.left);
        expect(cell.top, greaterThan(before.bottom));
      }
      expect(_cellView(tester, 1).cell.session, same(session));
    }

    expectStack();
    await captureQaFrame(tester, 'multiview-vertical-portrait-monitor');
    tester.view.physicalSize = const Size(1280, 800);
    await _wait(tester);
    expectStack();
    await tester.tap(_key('multiview-fullscreen'));
    await _wait(tester);
    expectStack();
    expect(tester.takeException(), isNull);
    await _close(tester, services);
  });

  testWidgets('issue #32: narrow phones can scroll to vertical without overlapping toolbar switches', (tester) async {
    final (services, _) = await _pump(tester, const Size(360, 800));
    final vertical = _key('multiview-layout-vertical');
    await tester.ensureVisible(vertical);
    await tester.tap(vertical);
    await _wait(tester);
    final segments = tester.widget<SegmentedButton<MultiviewLayout>>(find.byType(SegmentedButton<MultiviewLayout>));
    expect(segments.selected, {MultiviewLayout.vertical});
    expect(tester.getRect(vertical).right, lessThan(tester.getRect(_key('multiview-danmaku')).left));
    expect(tester.takeException(), isNull);
    await captureQaFrame(tester, 'multiview-vertical-narrow');
    await _close(tester, services);
  });

  testWidgets('issue #21: both bare modes keep a mute button and restore the same audio session', (tester) async {
    for (final mode in ['immersive', 'fullscreen']) {
      final (services, _) = await _pump(tester, const Size(1280, 800));
      await _pick(tester, '1');
      final session = _cellView(tester, 1).cell.session;
      final volume = _cellView(tester, 1).cell.volume;
      expect(_cellView(tester, 1).audible, isTrue);
      await tester.tap(_key('multiview-$mode'));
      await _wait(tester);
      final mute = _key('multiview-bare-mute-all');
      expect(mute, findsOneWidget);
      await captureQaFrame(tester, 'multiview-$mode-audible');
      expect(tester.getSize(mute), const Size.square(48));
      expect(tester.getRect(mute).overlaps(tester.getRect(_key('multiview-$mode-exit'))), isFalse);
      await tester.tap(mute);
      await _wait(tester);
      expect(_cellView(tester, 1).audible, isFalse);
      expect(session!.state.volume, 0);
      await captureQaFrame(tester, 'multiview-$mode-muted');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await _wait(tester);
      expect(_cellView(tester, 1).audible, isTrue);
      expect(_cellView(tester, 1).cell.session, same(session));
      expect(session.state.volume, volume);
      await _close(tester, services);
    }
  });

  testWidgets('issue #21: M toggles once while editing and system combinations keep their keys', (tester) async {
    final (services, _) = await _pump(tester, const Size(1280, 800));
    await _pick(tester, '1');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
    await _wait(tester);
    expect(_cellView(tester, 1).audible, isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await _wait(tester);
    expect(_cellView(tester, 1).audible, isFalse);
    await tester.tap(_key('multiview-picker-search'));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.enterText(_key('multiview-picker-search'), 'm');
    await _wait(tester);
    expect(_cellView(tester, 1).audible, isFalse, reason: 'typing in the room filter must not change sound');
    await _close(tester, services);
  });

  late List<String> toasts;
  setUp(() {
    toasts = [];
    AppNavigator.toast = toasts.add;
  });

  testWidgets('portrait: toolbar, 16:9 cells above, the selected cell and the picker below', (tester) async {
    final (services, _) = await _pump(tester, const Size(393, 852));
    expect(find.text('多画面'), findsOneWidget);

    // c10: one row; the words alone on a phone; the live room's danmaku
    // pictures; no saver outside 1+3.
    _expectLeftToRight(tester, [
      'multiview-layout-single',
      'multiview-layout-dual',
      'multiview-layout-quad',
      'multiview-layout-focus',
      'multiview-danmaku',
      'multiview-danmaku-settings',
      'multiview-mute-all',
    ]);
    expect(tester.getCenter(_key('multiview-layout-single')).dy, tester.getCenter(_key('multiview-mute-all')).dy);
    expect(find.descendant(of: _key('multiview-layouts'), matching: find.byType(Icon)), findsNothing);
    expect(
      tester
          .widget<DanmakuIcon>(find.descendant(of: _key('multiview-danmaku'), matching: find.byType(DanmakuIcon)))
          .kind,
      DanmakuIconKind.off,
    );
    expect(
      tester
          .widget<DanmakuIcon>(
            find.descendant(of: _key('multiview-danmaku-settings'), matching: find.byType(DanmakuIcon)),
          )
          .kind,
      DanmakuIconKind.settings,
    );
    expect(find.descendant(of: _key('multiview-mute-all'), matching: find.byIcon(AppIcons.muteAll)), findsOneWidget);
    expect(_key('multiview-saver'), findsNothing);

    // c2, c6, c7: numbered 16:9 cells in a 2×2 wall, black in a light theme;
    // the first empty cell is the picker's target.
    for (var position = 1; position <= 4; position++) {
      final size = tester.getSize(_key('multiview-cell-$position'));
      expect(size.width / size.height, moreOrLessEquals(16 / 9, epsilon: 0.02));
      expect(_key('multiview-cell-number-$position'), findsOneWidget);
    }
    expect(tester.getTopLeft(_key('multiview-cell-2')).dx, greaterThan(tester.getTopLeft(_key('multiview-cell-1')).dx));
    expect(tester.getTopLeft(_key('multiview-cell-3')).dy, greaterThan(tester.getTopLeft(_key('multiview-cell-1')).dy));
    final ground = tester.widget<ColoredBox>(
      find.ancestor(of: _key('multiview-cell-4'), matching: find.byType(ColoredBox)).first,
    );
    expect(ground.color, OnVideoColors.ground);
    expect(_inCell(1, find.text('正在为这一格选台')), findsOneWidget);
    expect(_inCell(1, _key('multiview-pick-frame')), findsOneWidget);
    expect(find.text('点击选台'), findsNWidgets(3));
    expect(find.text('为第 1 格选台'), findsOneWidget);
    expect(find.text('点直播间放进这一格'), findsOneWidget);
    expect(
      tester.getTopLeft(_key('multiview-picker-title')).dy,
      greaterThan(tester.getBottomLeft(_key('multiview-cell-3')).dy),
    );

    // Picking fills the cell, the next empty one becomes the target.
    await _pick(tester, '1');
    expect(_inCell(1, find.text('主播1')), findsOneWidget);
    expect(_inCell(1, _key('multiview-audio-badge')), findsOneWidget);
    expect(_inCell(1, _key('multiview-audio-outline')), findsOneWidget);
    expect(_inCell(1, find.text('声音来源')), findsOneWidget);
    expect(find.text('为第 2 格选台'), findsOneWidget);
    expect(_inCell(2, _key('multiview-pick-frame')), findsOneWidget);

    // c4: the selected cell's controls under the picture: the room, "原画 ⌄"
    // "线路1 ⌄" on its row; pause, refresh, change, open, close; the volume.
    expect(_key('multiview-cell-controls-1'), findsOneWidget);
    expect(find.descendant(of: _key('multiview-controls-number'), matching: find.text('1')), findsOneWidget);
    expect(find.text('哔哩哔哩 · 标题1'), findsOneWidget);
    _expectLeftToRight(tester, ['multiview-quality', 'multiview-line']);
    expect(find.descendant(of: _key('multiview-quality'), matching: find.text('原画')), findsOneWidget);
    expect(find.descendant(of: _key('multiview-line'), matching: find.text('线路1')), findsOneWidget);
    final buttons = [
      'multiview-control-play',
      'multiview-control-refresh',
      'multiview-control-change',
      'multiview-control-room',
      'multiview-control-close',
    ];
    _expectLeftToRight(tester, [...buttons, 'multiview-volume-slider']);
    final icons = [
      AppIcons.cellPause,
      AppIcons.cellRefresh,
      AppIcons.changeRoom,
      AppIcons.enterRoom,
      AppIcons.closeCell,
    ];
    for (final (index, key) in buttons.indexed) {
      expect(
        find.descendant(of: _key(key), matching: find.byIcon(icons[index])),
        findsOneWidget,
        reason: key,
      );
    }
    expect(tester.getCenter(_key('multiview-quality')).dy, lessThan(tester.getCenter(_key(buttons.first)).dy));
    expect(
      tester.getBottomLeft(_key('multiview-cell-controls-1')).dy,
      lessThan(tester.getTopLeft(_key('multiview-picker-title')).dy),
    );

    // W4: a room in a cell is marked, listed last, and selects its cell.
    expect(_key('multiview-shown-bilibili:1'), findsOneWidget);
    expect(
      tester.getTopLeft(_key('multiview-pick-bilibili:1')).dy,
      greaterThan(tester.getTopLeft(_key('multiview-pick-bilibili:3')).dy),
    );
    await _pick(tester, '1');
    expect(toasts, ['这个直播间已在第 1 格播放']);
    expect(_inCell(2, find.text('点击选台')), findsNothing, reason: 'still the target');

    // A 13: the new cell takes the sound; a tap gives it back; a long press
    // shows a cell's controls without moving the sound.
    await _pick(tester, '2');
    expect(_inCell(2, _key('multiview-audio-badge')), findsOneWidget);
    expect(_key('multiview-cell-controls-2'), findsOneWidget);
    await tester.tap(_key('multiview-cell-1'));
    await _wait(tester);
    expect(_inCell(1, _key('multiview-audio-badge')), findsOneWidget);
    expect(_inCell(2, _key('multiview-audio-badge')), findsNothing);
    expect(_key('multiview-cell-controls-1'), findsOneWidget);
    await tester.longPress(_key('multiview-cell-2'));
    await _wait(tester);
    expect(_key('multiview-cell-controls-2'), findsOneWidget);
    expect(_inCell(1, _key('multiview-audio-badge')), findsOneWidget);

    // U.2f's quality menu.
    await tester.tap(_key('multiview-quality'));
    await tester.pumpAndSettle();
    expect(_key('multiview-quality-item-1'), findsOneWidget);
    expect(
      tester.getTopLeft(_key('multiview-quality-item-0')).dy,
      greaterThan(tester.getBottomLeft(_key('multiview-quality')).dy),
    );
    await tester.tap(_key('multiview-quality-item-1'));
    await tester.pumpAndSettle();
    await _wait(tester);
    expect(find.descendant(of: _key('multiview-quality'), matching: find.text('超清')), findsOneWidget);

    // c8: a paused cell says so; the button plays it again.
    await tester.tap(_key('multiview-control-play'));
    await _wait(tester);
    expect(_inCell(2, _key('multiview-paused')), findsOneWidget);
    expect(_inCell(2, find.text('已暂停')), findsOneWidget);
    expect(
      find.descendant(of: _key('multiview-control-play'), matching: find.byIcon(AppIcons.cellPlay)),
      findsOneWidget,
    );

    // 换台 makes the cell the target; 关闭这一格 empties it.
    await tester.tap(_key('multiview-control-change'));
    await _wait(tester);
    expect(find.text('第 2 格换台'), findsOneWidget);
    expect(find.text('点直播间换掉“主播2”'), findsOneWidget);
    await tester.tap(_key('multiview-control-close'));
    await _wait(tester);
    expect(_inCell(2, find.text('主播2')), findsNothing);
    expect(_key('multiview-cell-controls-1'), findsOneWidget, reason: 'back to the audible cell');

    // c11: the danmaku settings under the picture, U.2f's content.
    await tester.tap(_key('multiview-danmaku-settings'));
    await tester.pumpAndSettle();
    final panel = tester.getRect(_key('multiview-danmaku-panel'));
    expect(panel.top, greaterThanOrEqualTo(tester.getBottomLeft(_key('multiview-cell-4')).dy));
    expect(panel.bottom, 852);
    expect(find.text('只在声音来源这一格显示 · 改动立即生效'), findsOneWidget);
    expect(find.text('观看模板'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_key('multiview-danmaku-panel'), findsNothing, reason: 'Back closes the panel first');
    expect(find.text('多画面'), findsOneWidget);

    // c12: immersive: the cells alone, the exit in the top-left corner; Back
    // returns (A 7).
    await tester.tap(_key('multiview-immersive'));
    await tester.pump();
    expect(find.text('多画面'), findsNothing);
    expect(tester.getTopLeft(_key('multiview-immersive-exit')), const Offset(12, 12));
    expect(
      find.descendant(of: _key('multiview-immersive-exit'), matching: find.byIcon(AppIcons.exitImmersive)),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('多画面'), findsOneWidget);

    await _close(tester, services);
  });

  testWidgets('B02 c3: the danmaku stand while their cell is paused, or fly on as "暂停时的弹幕" says', (tester) async {
    final (services, _) = await _pump(tester, const Size(393, 852));
    await _pick(tester, '1');
    await tester.tap(_key('multiview-danmaku'));
    await _wait(tester);
    DanmakuOverlay overlay() => tester.widget<DanmakuOverlay>(_inCell(1, find.byType(DanmakuOverlay)));
    expect(overlay().running, isTrue);
    await tester.tap(_key('multiview-control-play'));
    await _wait(tester);
    expect(_inCell(1, _key('multiview-paused')), findsOneWidget);
    expect(overlay().running, isFalse, reason: 'with the video, the default');
    await tester.runAsync(() => services.store.settings.set(Settings.danmakuPausedBehavior, 'continue'));
    await _wait(tester);
    expect(overlay().running, isTrue);
    await tester.tap(_key('multiview-control-play'));
    await _wait(tester);
    expect(overlay().running, isTrue);
    await _close(tester, services);
  });

  testWidgets('tap targets (UI_PLAN 5.4): 48 around the 40 buttons and the 38 switches in every arrangement', (
    tester,
  ) async {
    const toggles = ['multiview-danmaku', 'multiview-danmaku-settings', 'multiview-mute-all'];
    const buttons = [
      'multiview-control-play',
      'multiview-control-refresh',
      'multiview-control-change',
      'multiview-control-room',
      'multiview-control-close',
    ];
    Rect circle(String key) => tester.getRect(find.descendant(of: _key(key), matching: find.byType(Material)).first);
    // Each 48 square around its circle, side by side without overlapping,
    // on one row.
    void expectTargets(List<String> keys, double visible) {
      for (final (index, key) in keys.indexed) {
        final target = tester.getRect(_key(key));
        expect(target.size, const Size.square(48), reason: key);
        expect(circle(key).size, Size.square(visible), reason: key);
        expect(circle(key).center, target.center, reason: key);
        if (index == 0) continue;
        final previous = tester.getRect(_key(keys[index - 1]));
        expect(target.left, greaterThanOrEqualTo(previous.right), reason: key);
        expect(target.center.dy, previous.center.dy, reason: key);
      }
    }

    // Narrower segments where the row is short (the words then keep about
    // their size: each segment 48 instead of 56 with a phone's font).
    bool dense() => tester.widget<LayoutSegments>(find.byType(LayoutSegments)).dense;

    // Portrait 393: the circles where they were (12 in, 8 from the end, the
    // toolbar 56 high), the volume after the buttons.
    var (services, _) = await _pump(tester, const Size(393, 852));
    await _pick(tester, '1');
    expectTargets(toggles, 38);
    expectTargets(buttons, 40);
    expect(circle(buttons.first).left, 12);
    expect(circle(toggles.last).right, 393 - 8);
    expect(tester.getSize(_key('multiview-toolbar')).height, 56);
    expect(dense(), isFalse);
    expect(tester.getCenter(_key('multiview-volume-slider')).dy, tester.getCenter(_key(buttons.first)).dy);
    expect(tester.getRect(_key('multiview-volume-slider')).left - circle(buttons.last).right, greaterThanOrEqualTo(8));
    // A tap between the circle and the target's edge counts.
    await tester.tapAt(tester.getRect(_key('multiview-mute-all')).centerLeft + const Offset(2, 0));
    await _wait(tester);
    expect(find.descendant(of: _key('multiview-mute-all'), matching: find.byIcon(AppIcons.mutedAll)), findsOneWidget);
    await tester.tapAt(tester.getRect(_key('multiview-control-play')).topLeft + const Offset(2, 2));
    await _wait(tester);
    expect(_inCell(1, _key('multiview-paused')), findsOneWidget);

    // 1+3: the saver's target too, so narrower segments.
    await tester.tap(_key('multiview-layout-focus'));
    await _wait(tester);
    expectTargets([...toggles, 'multiview-saver'], 38);
    expect(dense(), isTrue);
    await _close(tester, services);

    // Portrait 360: the volume takes a row of its own rather than a slider
    // too short to use; narrower segments.
    (services, _) = await _pump(tester, const Size(360, 780));
    await _pick(tester, '1');
    expectTargets(toggles, 38);
    expectTargets(buttons, 40);
    expect(dense(), isTrue);
    expect(
      tester.getRect(_key('multiview-volume-slider')).top,
      greaterThan(tester.getRect(_key(buttons.first)).bottom),
    );
    await _close(tester, services);

    // A narrow landscape phone: the column fits the five targets on a row.
    (services, _) = await _pump(tester, const Size(740, 360));
    await _pick(tester, '1');
    await tester.tap(_key('multiview-cell-1'));
    await _wait(tester);
    final column = tester.getRect(_key('multiview-column'));
    expect(column.width, 256);
    expectTargets(toggles, 38);
    expectTargets(buttons, 40);
    expect(circle(buttons.first).left, column.left + 12);
    expect(tester.getRect(_key(buttons.last)).right, lessThanOrEqualTo(column.right));
    await _close(tester, services);

    // Wide: the same targets; the last circle 16 from the end as before.
    (services, _) = await _pump(tester, const Size(1280, 800));
    await _pick(tester, '1');
    expectTargets(toggles, 38);
    expectTargets(buttons, 40);
    expect(circle(toggles.last).right, 1280 - 16);
    await _close(tester, services);
  });

  testWidgets('portrait 1+3: the large cell above, three small ones in a row; the saver marks them', (tester) async {
    final (services, _) = await _pump(tester, const Size(393, 852));
    await _pick(tester, '1');
    await _pick(tester, '2');
    await _pick(tester, '3');
    await tester.tap(_key('multiview-layout-focus'));
    await _wait(tester);
    _expectLeftToRight(tester, ['multiview-mute-all', 'multiview-saver']);
    final large = tester.getRect(_key('multiview-cell-3'));
    expect(large.width, moreOrLessEquals(393 - 6, epsilon: 1));
    for (final position in [1, 2, 4]) {
      final small = tester.getRect(_key('multiview-cell-$position'));
      expect(small.top, greaterThan(large.bottom));
      expect(small.width / small.height, moreOrLessEquals(16 / 9, epsilon: 0.02));
    }
    _expectLeftToRight(tester, ['multiview-cell-1', 'multiview-cell-2', 'multiview-cell-4']);
    // W3: no control bar on the large cell outside immersive and fullscreen.
    await tester.tap(_key('multiview-cell-3'));
    await _wait(tester);
    expect(_key('multiview-control-bar'), findsNothing);

    await tester.tap(_key('multiview-saver'));
    await _wait(tester);
    expect(_key('multiview-saver-mark'), findsNWidgets(2));
    expect(_inCell(3, _key('multiview-saver-mark')), findsNothing);

    // A 13: a tap on a small cell makes it the large one.
    await tester.tap(_key('multiview-cell-1'));
    await _wait(tester);
    expect(tester.getRect(_key('multiview-cell-1')).width, moreOrLessEquals(393 - 6, epsilon: 1));
    expect(_inCell(1, _key('multiview-audio-badge')), findsOneWidget);

    // No cell decodes video while the app is out of sight (UI_PLAN §9.3).
    expect(_cellView(tester, 1).cell.offscreen, isFalse);
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await _wait(tester);
    for (final position in [1, 2, 3, 4]) {
      expect(_cellView(tester, position).cell.offscreen, isTrue);
    }
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _wait(tester);
    expect(_cellView(tester, 1).cell.offscreen, isFalse);
    expect(_cellView(tester, 1).cell.session!.state.audioOnly, isFalse);
    await _close(tester, services);
  });

  testWidgets('A01.4 c5: a small empty cell says "点击选台" at 12 with a 20 icon, not shrunk to fit', (tester) async {
    final (services, _) = await _pump(tester, const Size(393, 852));
    await tester.tap(_key('multiview-layout-focus'));
    await _wait(tester);
    final hints = find.byKey(const ValueKey('multiview-cell-hint'));
    expect(hints, findsNWidgets(3));
    for (final hint in hints.evaluate()) {
      final text = hint.widget as Text;
      expect(text.style!.fontSize, 12);
      // Drawn at its size: nothing scales it down.
      expect(tester.getSize(find.byWidget(text)).height, greaterThanOrEqualTo(12));
    }
    expect(find.text('点击选台'), findsNWidgets(3));
    final icons = find.descendant(of: _key('multiview-cell-2'), matching: find.byIcon(AppIcons.addCell));
    expect(tester.getSize(icons).width, 20);
    await _close(tester, services);
  });

  testWidgets('A01.2: the picker and the cells follow the font settings, the same size by default', (tester) async {
    double size(Finder finder) => tester.renderObject<RenderParagraph>(finder).text.style!.fontSize!;
    final name = find.descendant(of: _key('multiview-pick-bilibili:1'), matching: find.text('主播1'));
    var (services, _) = await _pump(tester, const Size(393, 852));
    expect(size(_key('multiview-picker-title')), 15);
    expect(size(name), 14);
    expect(size(find.text('点击选台').first), 13);
    await _close(tester, services);

    // Every size at its largest (Settings.fontSize*).
    const largest = LiveFontSizes(bodySmall: 15, bodyMedium: 17, bodyLarge: 18, titleMedium: 20, titleLarge: 26);
    (services, _) = await _pump(tester, const Size(393, 852), fontSizes: largest);
    expect(size(_key('multiview-picker-title')), 20);
    expect(size(name), 18);
    expect(size(find.text('点击选台').first), 17);
    expect(tester.takeException(), isNull);
    await _close(tester, services);
    // A landscape phone and a wide window: nothing overflows either.
    for (final window in const [Size(852, 393), Size(1280, 800)]) {
      (services, _) = await _pump(tester, window, fontSizes: largest);
      expect(size(_key('multiview-picker-title')), 20, reason: '$window');
      expect(tester.takeException(), isNull, reason: '$window');
      await _close(tester, services);
    }
  });

  testWidgets("a phone's split screen is not a landscape phone: the toolbar stays under the app bar (A04.1)", (
    tester,
  ) async {
    // Upright split (400×420) and half of a phone held sideways (410×392):
    // short, but compact both ways.
    for (final size in const [Size(400, 420), Size(410, 392)]) {
      final (services, _) = await _pump(tester, size);
      expect(_key('multiview-toolbar'), findsOneWidget, reason: '$size');
      expect(
        find.descendant(of: find.byType(AppBar), matching: _key('multiview-layouts')),
        findsNothing,
        reason: '$size',
      );
      expect(_key('multiview-column'), findsNothing, reason: '$size');
      await _close(tester, services);
    }
  });

  testWidgets('landscape phone: toolbar in the app bar, the column on the right, the picker in turn', (tester) async {
    final (services, _) = await _pump(tester, const Size(852, 393));
    // c10: the toolbar joins the app bar.
    expect(find.descendant(of: find.byType(AppBar), matching: _key('multiview-layouts')), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: _key('multiview-mute-all')), findsOneWidget);
    _expectLeftToRight(tester, [
      'multiview-layouts',
      'multiview-mute-all',
      'multiview-immersive',
      'multiview-fullscreen',
    ]);

    final column = tester.getRect(_key('multiview-column'));
    expect(column.left, greaterThanOrEqualTo(tester.getRect(_key('multiview-cell-2')).right));
    expect(column.right, 852);
    expect(column.width, inInclusiveRange(240, 360));
    expect(find.text('为第 1 格选台'), findsOneWidget);
    expect(_key('multiview-picker-close'), findsNothing, reason: 'nothing to go back to');

    // Picking goes on while cells are empty.
    await _pick(tester, '1');
    expect(find.text('为第 2 格选台'), findsOneWidget);
    expect(_key('multiview-picker-close'), findsOneWidget);
    // A tap on a playing cell shows its controls.
    await tester.tap(_key('multiview-cell-1'));
    await _wait(tester);
    expect(_key('multiview-cell-controls-1'), findsOneWidget);
    expect(_key('multiview-picker-title'), findsNothing);
    // Compact: the quality and line on a row of their own, under the room.
    expect(tester.getCenter(_key('multiview-quality')).dy, greaterThan(tester.getCenter(find.text('主播1').last).dy));

    // An empty cell: the picker in the column, ✕ and Back return.
    await tester.tap(_key('multiview-cell-4'));
    await _wait(tester);
    expect(find.text('为第 4 格选台'), findsOneWidget);
    expect(_inCell(4, _key('multiview-pick-frame')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _wait(tester);
    expect(_key('multiview-cell-controls-1'), findsOneWidget);
    expect(_inCell(4, _key('multiview-pick-frame')), findsNothing);

    // 22: the column folds away and back.
    await tester.tap(_key('multiview-fold'));
    await _wait(tester);
    expect(_key('multiview-column'), findsNothing);
    expect(find.descendant(of: _key('multiview-fold'), matching: find.byIcon(AppIcons.unfoldLeft)), findsOneWidget);
    // A04.1: the tab looks 22 wide and answers 48; a tap on its clear
    // part, over the wall's edge, unfolds it too.
    final tab = tester.getRect(_key('multiview-fold'));
    expect(tab.width, 22);
    await tester.tapAt(tab.centerLeft - const Offset(12, 0));
    await _wait(tester);
    expect(_key('multiview-column'), findsOneWidget);
    await tester.tap(_key('multiview-fold'));
    await _wait(tester);
    expect(_key('multiview-column'), findsNothing);
    await tester.tap(_key('multiview-fold'));
    await _wait(tester);
    expect(_key('multiview-column'), findsOneWidget);

    // c12, c13: fullscreen; the same exit place; a long press opens the
    // cell's panel on the right; Esc closes it, then leaves.
    await tester.tap(_key('multiview-fullscreen'));
    await _wait(tester);
    expect(tester.getTopLeft(_key('multiview-fullscreen-exit')), const Offset(12, 12));
    expect(
      tester.getTopLeft(_key('multiview-cell-1')).dx,
      greaterThan(12 + 48),
      reason: 'the exit button sits in the black side',
    );
    await tester.longPress(_key('multiview-cell-1'));
    await _wait(tester);
    final panel = tester.getRect(_key('multiview-cell-panel'));
    expect(panel, const Rect.fromLTRB(852 - 360, 0, 852, 393));
    expect(
      tester.widget<Text>(find.descendant(of: _key('multiview-cell-panel'), matching: _key('room-panel-title'))).data,
      '第 1 格',
    );
    expect(
      find.descendant(of: _key('multiview-cell-panel'), matching: _key('multiview-control-close')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _wait(tester);
    expect(_key('multiview-cell-panel'), findsNothing);
    expect(_key('multiview-fullscreen-exit'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _wait(tester);
    expect(find.text('多画面'), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('O05.3: leaving the fullscreen turns the phone upright, then lets go', (tester) async {
    final orientations = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') orientations.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    const systemAccess = MethodChannel('pure_live/system_access');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(systemAccess, (call) async {
      if (call.method == 'sensorLandscape') orientations.add(call.method);
      // Auto-rotate off.
      return call.method != 'autoRotate';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(systemAccess, null));
    final (services, _) = await _pump(tester, const Size(393, 852));
    await tester.tap(_key('multiview-fullscreen'));
    await _wait(tester);
    tester.view.physicalSize = const Size(852, 393);
    await _wait(tester);
    await tester.tap(_key('multiview-fullscreen-exit'));
    await _wait(tester);
    const sideways = ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'];
    const upright = ['DeviceOrientation.portraitUp'];
    expect(orientations, [sideways, 'sensorLandscape', upright], reason: 'upright first');
    tester.view.physicalSize = const Size(393, 852);
    await tester.pump(const Duration(seconds: 4));
    expect(orientations, [sideways, 'sensorLandscape', upright, <Object?>[]], reason: 'then free again');
    await _close(tester, services);
  });

  for (final size in [const Size(926, 428), const Size(393, 852), const Size(1280, 800)]) {
    for (final mode in ['immersive', 'fullscreen']) {
      testWidgets('issue178 $size $mode keeps main chrome synchronized without replacing sessions', (tester) async {
        debugDefaultTargetPlatformOverride = size.width > 1000 ? TargetPlatform.windows : TargetPlatform.iOS;
        try {
          final (services, _) = await _pump(tester, size);
          await _pick(tester, '1');
          await _pick(tester, '2');
          await _pick(tester, '3');
          await tester.tap(_key('multiview-layout-focus'));
          await _wait(tester);
          final sessions = [
            for (final n in [1, 2, 3]) _cellView(tester, n).cell.session,
          ];
          await tester.tap(_key('multiview-$mode'));
          await _wait(tester);
          final main = _key('multiview-cell-3');
          final element = tester.element(main);
          void expectHidden() {
            expect(_key('multiview-control-bar'), findsNothing);
            expect(_key('multiview-$mode-exit'), findsNothing);
            expect(_key('multiview-bare-mute-all'), findsNothing);
            expect(_key('multiview-bare-mix-audio'), findsNothing);
            expect(_key('multiview-corner-marks-3'), findsNothing);
            expect(_key('multiview-corner-marks-1'), findsOneWidget);
            expect(_key('multiview-corner-marks-2'), findsOneWidget);
          }

          expectHidden();
          await captureQaFrame(tester, 'issue178-${size.width.toInt()}-$mode-hidden');
          await tester.tap(main);
          await _wait(tester);
          expect(_key('multiview-control-bar'), findsOneWidget);
          expect(_key('multiview-$mode-exit'), findsOneWidget);
          expect(_key('multiview-bare-mute-all'), findsOneWidget);
          expect(_key('multiview-bare-mix-audio'), findsOneWidget);
          expect(_key('multiview-corner-marks-3'), findsOneWidget);
          await captureQaFrame(tester, 'issue178-${size.width.toInt()}-$mode-shown');
          await tester.tap(main);
          await _wait(tester);
          expectHidden();
          expect(tester.element(main), same(element));
          for (var i = 0; i < sessions.length; i++) {
            expect(_cellView(tester, i + 1).cell.session, same(sessions[i]));
          }
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _wait(tester);
          expect(_key('multiview-$mode'), findsOneWidget);
          expect(_key('multiview-corner-marks-3'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _close(tester, services);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  testWidgets('wide: icons on the layouts, a 360 column; 1+3 grows; the large cell bar in fullscreen', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final processors = MultiviewPage.processors;
    MultiviewPage.processors = () => 8;
    addTearDown(() => MultiviewPage.processors = processors);
    final (services, _) = await _pump(tester, const Size(1280, 800));
    expect(find.descendant(of: _key('multiview-layouts'), matching: find.byIcon(AppIcons.layoutFocus)), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: _key('multiview-layouts')), findsNothing);
    final column = tester.getRect(_key('multiview-column'));
    expect(column.width, 360);
    expect(column.right, 1280);
    expect(find.text('为第 1 格选台'), findsOneWidget);

    await _pick(tester, '1');
    await _pick(tester, '2');
    // The controls above the picker in the same column.
    expect(
      tester.getBottomLeft(_key('multiview-cell-controls-2')).dy,
      lessThan(tester.getTopLeft(_key('multiview-picker-title')).dy),
    );
    expect(tester.getTopLeft(_key('multiview-cell-controls-2')).dx, greaterThanOrEqualTo(column.left));

    await tester.tap(_key('multiview-layout-focus'));
    await _wait(tester);
    // Desktops add cells up to their limit (3.x: 9).
    expect(_key('multiview-add-cell'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.ensureVisible(_key('multiview-add-cell'));
      await tester.tap(_key('multiview-add-cell'));
      await _wait(tester);
    }
    expect(_key('multiview-add-cell'), findsNothing);
    expect(_key('multiview-cell-9'), findsOneWidget);
    // Cells scrolled out of the rail decode no video (UI_PLAN §9.3).
    // The rail ends with cells 7 to 9 in sight; the large cell is cell 2.
    expect(_cellView(tester, 1).cell.offscreen, isTrue);
    expect(_cellView(tester, 6).cell.offscreen, isTrue);
    expect(_cellView(tester, 9).cell.offscreen, isFalse);
    expect(_cellView(tester, 2).cell.offscreen, isFalse);
    await tester.drag(_key('multiview-rail'), const Offset(2000, 0));
    await _wait(tester);
    expect(_cellView(tester, 1).cell.offscreen, isFalse);
    expect(_cellView(tester, 9).cell.offscreen, isTrue);

    await tester.tap(_key('multiview-fullscreen'));
    await _wait(tester);
    await tester.tap(_key('multiview-cell-2'));
    await _wait(tester);
    // c14: the large cell's bar, U.2f's quality and line buttons in it.
    _expectLeftToRight(tester, [
      'multiview-bar-play',
      'multiview-bar-refresh',
      'multiview-bar-danmaku',
      'multiview-bar-danmaku-settings',
      'multiview-bar-quality',
      'multiview-bar-line',
      'multiview-bar-volume',
      'multiview-bar-fullscreen',
    ]);
    await tester.tap(_key('multiview-bar-volume'));
    await _wait(tester);
    expect(_key('multiview-cell-panel'), findsOneWidget);
    expect(_key('multiview-volume-slider'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _wait(tester);
    await tester.tap(_key('multiview-bar-danmaku-settings'));
    await _wait(tester);
    expect(tester.getRect(_key('multiview-danmaku-panel')).width, 360);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _wait(tester);
    expect(find.text('多画面'), findsOneWidget);
    await _close(tester, services);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('cells: offline and failed say why on black in a dark theme', (tester) async {
    final (services, site) = await _pump(tester, const Size(393, 852), theme: ThemeMode.dark);
    site
      ..offline.add('2')
      ..failing.add('3');
    await _pick(tester, '2');
    expect(_inCell(1, find.text('该直播间未开播')), findsOneWidget);
    expect(_inCell(1, find.text('点击此格可重新选台')), findsOneWidget);
    expect(_inCell(1, find.byIcon(AppIcons.roomOffline)), findsOneWidget);
    await _pick(tester, '3');
    expect(_inCell(2, find.text('播放失败')), findsOneWidget);
    expect(_inCell(2, find.text('重试')), findsOneWidget);
    expect(tester.widget<Icon>(_inCell(2, find.byIcon(AppIcons.cellFailed))).color, OnVideoColors.error);
    // A 13: tapping an offline cell picks for it again.
    await tester.tap(_key('multiview-cell-1'));
    await _wait(tester);
    expect(find.text('第 1 格换台'), findsOneWidget);
    expect(_inCell(1, _key('multiview-pick-frame')), findsOneWidget);
    // Its controls are a long press away (close, refresh).
    await tester.longPress(_key('multiview-cell-2'));
    await _wait(tester);
    expect(_key('multiview-cell-controls-2'), findsOneWidget);
    site.failing.clear();
    await tester.tap(_key('multiview-control-refresh'));
    await _wait(tester);
    expect(_inCell(2, find.text('播放失败')), findsNothing);
    await _close(tester, services);
  });

  testWidgets('E06.2 c1: a carousel cell offers "播放轮播", which plays it', (tester) async {
    final (services, site) = await _pump(tester, const Size(393, 852));
    site.carousel.add('2');
    await _pick(tester, '2');
    expect(_inCell(1, find.text('主播未开播，正在轮播往期视频')), findsOneWidget);
    expect(_inCell(1, find.text('播放轮播')), findsOneWidget);
    await tester.tap(_inCell(1, find.text('播放轮播')));
    await _wait(tester);
    expect(_inCell(1, find.text('主播未开播，正在轮播往期视频')), findsNothing);
    expect(_cellView(tester, 1).cell.stage, CellStage.playing);
    await _close(tester, services);
  });

  group("N01.2: the cells' flying danmaku follow the danmaku settings, as in the room", () {
    tearDown(() => DisplayMode.info.value = null);

    testWidgets('the danmaku frame rate: manual, changed without leaving, and following the refresh rate', (
      tester,
    ) async {
      final (services, _) = await _pump(tester, const Size(393, 852));
      await tester.runAsync(
        () => services.store.settings.setAll({Settings.danmakuAutoFps: false, Settings.danmakuFps: 30}),
      );
      await _pick(tester, '1');
      await tester.tap(_key('multiview-danmaku'));
      await _wait(tester);
      DanmakuOverlay overlay() => tester.widget<DanmakuOverlay>(_inCell(1, find.byType(DanmakuOverlay)));
      expect(overlay().fps, 30);

      // c1: a change applies at once, without leaving the multi-view.
      await tester.runAsync(() => services.store.settings.set(Settings.danmakuFps, 45));
      await _wait(tester);
      expect(overlay().fps, 45);

      // Following the refresh rate: "省电" is 60 on a 120 Hz display,
      // "性能" the display's highest; the display's rate is passed on.
      DisplayMode.info.value = const DisplayModeInfo(
        currentRefreshRate: 120,
        maxRefreshRate: 120,
        supportedRefreshRates: [60, 120],
      );
      await tester.runAsync(
        () => services.store.settings.setAll({Settings.danmakuAutoFps: true, Settings.refreshRateMode: 'powerSaving'}),
      );
      await _wait(tester);
      expect(overlay().fps, 60);
      expect(overlay().refreshRate, 120);
      await tester.runAsync(() => services.store.settings.set(Settings.refreshRateMode, 'performance'));
      await _wait(tester);
      expect(overlay().fps, 120);
      await _close(tester, services);
    });

    testWidgets("c3 (D-035): the selected cell's bundled emoticons fly as pictures", (tester) async {
      // The app's lists, read from the files (the room's library reads the
      // same assets).
      final library = EmoteLibrary(bundle: FileAssetBundle());
      final bilibili = (await tester.runAsync(() => library.load(SiteIds.bilibili)))!;
      expect(bilibili.codes, isNotEmpty);
      final (services, _) = await _pump(
        tester,
        const Size(393, 852),
        overrides: [emoteLibraryProvider.overrideWithValue(library)],
      );
      await _pick(tester, '1');
      await tester.tap(_key('multiview-danmaku'));
      await _wait(tester);
      final overlay = tester.widget<DanmakuOverlay>(_inCell(1, find.byType(DanmakuOverlay)));
      // The Bilibili table, the same one the room uses.
      expect(overlay.emotes, same(bilibili));
      await _close(tester, services);
    });

    testWidgets('D05.2: the cell\'s danmaku follow "同屏最大弹幕条数" (48 by default, 3.x)', (tester) async {
      final (services, _) = await _pump(tester, const Size(393, 852));
      await _pick(tester, '1');
      await tester.tap(_key('multiview-danmaku'));
      await _wait(tester);
      DanmakuOverlay overlay() => tester.widget<DanmakuOverlay>(_inCell(1, find.byType(DanmakuOverlay)));
      expect(overlay().maxVisible, 48);
      await tester.runAsync(() => services.store.settings.set(Settings.danmakuMaxVisibleCount, 20));
      await _wait(tester);
      expect(overlay().maxVisible, 20);
      await _close(tester, services);
    });

    testWidgets('c4 (D-035): the cells follow "屏幕常亮"', (tester) async {
      final (services, _) = await _pump(tester, const Size(393, 852));
      await _pick(tester, '1');
      LiveVideoView video() => tester.widget<LiveVideoView>(_inCell(1, find.byType(LiveVideoView)));
      expect(video().keepScreenOn, isTrue);
      await tester.runAsync(() => services.store.settings.set(Settings.enableScreenKeepOn, false));
      await _wait(tester);
      expect(video().keepScreenOn, isFalse);
      await _close(tester, services);
    });
  });
}
