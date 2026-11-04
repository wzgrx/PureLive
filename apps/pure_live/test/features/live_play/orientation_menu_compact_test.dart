import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';

import '../../qa_capture.dart';
import '../../support.dart';

const _menuGap = 4.0;
const _edgeMargin = 8.0;

Future<RoomOrientationChoice> _pump(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double scale = 1,
  bool dark = false,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadStrings);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(services.close);
  final choice = RoomOrientationChoice(
    settings: services.store.settings,
    room: LiveRoom(platform: SiteIds.douyin, roomId: 'synthetic-room'),
  );
  addTearDown(choice.dispose);
  RoomOrientationChoice.clearSession();
  addTearDown(RoomOrientationChoice.clearSession);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? const LiveTheme().dark : const LiveTheme().light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Builder(
                    builder: (context) => IconButton(
                      key: const ValueKey('quality'),
                      tooltip: '画质',
                      onPressed: () =>
                          showSmallMenu(context, entries: const ['原画', '高清', '流畅'], current: 0, preferAbove: true),
                      icon: const Icon(AppIcons.dropDown, color: OnVideoColors.foreground),
                    ),
                  ),
                  Builder(
                    builder: (context) => IconButton(
                      key: const ValueKey('orientation'),
                      tooltip: '画面方向',
                      onPressed: () => showRoomOrientationMenu(context, choice),
                      icon: const Icon(AppIcons.orientationAuto, color: OnVideoColors.foreground),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await prepareQaFonts(tester);
  return choice;
}

Finder get _surface =>
    find.ancestor(of: find.byKey(const ValueKey('room-orientation-0')), matching: find.byType(Material)).first;

Future<void> _capture(WidgetTester tester, String name) async {
  final folder = Platform.environment['PURELIVE_QA_DIR'];
  if (folder == null || folder.isEmpty) return;
  final previousShadows = debugDisableShadows;
  debugDisableShadows = false;
  try {
    void repaint(RenderObject object) {
      object
        ..markNeedsPaint()
        ..visitChildren(repaint);
    }

    repaint(tester.binding.renderViews.first);
    await captureQaFrame(tester, name);
    final view = tester.binding.renderViews.first;
    final bounds = tester.getRect(_surface).inflate(12).intersect(view.paintBounds);
    final layer = view.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final frame = await layer.toImage(bounds, pixelRatio: 2);
      try {
        final data = (await frame.toByteData(format: ui.ImageByteFormat.png))!;
        await File('$folder/$name-menu.png').writeAsBytes(data.buffer.asUint8List());
      } finally {
        frame.dispose();
      }
    });
  } finally {
    debugDisableShadows = previousShadows;
  }
}

void main() {
  testWidgets('Douyin direction uses quality-menu rows and content width with a compact remember switch', (
    tester,
  ) async {
    final choice = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('quality')));
    await tester.pumpAndSettle();
    final qualityRowHeight = tester.getSize(find.byKey(const ValueKey('stream-menu-item-0'))).height;
    final qualitySurface = find
        .ancestor(of: find.byKey(const ValueKey('stream-menu-item-0')), matching: find.byType(Material))
        .first;
    final qualityHeight = tester.getSize(qualitySurface).height;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('orientation')));
    await tester.pumpAndSettle();
    final rect = tester.getRect(_surface);
    await _capture(tester, 'orientation-portrait-light');
    expect(rect.width, lessThanOrEqualTo(280));
    expect(rect.height, lessThanOrEqualTo(qualityHeight + 80));
    for (var i = 0; i < 3; i++) {
      expect(tester.getSize(find.byKey(ValueKey('room-orientation-$i'))).height, qualityRowHeight);
    }
    expect(find.byKey(const ValueKey('small-menu-title')), findsNothing);
    expect(find.text('按画面的实际尺寸判断是竖屏还是横屏直播'), findsNothing);
    expect(find.text('记住本直播间'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    final anchor = tester.getRect(find.byKey(const ValueKey('orientation')));
    expect(rect.bottom, closeTo(anchor.top - _menuGap, 0.1));
    expect(
      find.descendant(of: find.byKey(const ValueKey('room-orientation-0')), matching: find.byIcon(AppIcons.selected)),
      findsOneWidget,
    );
    final hold = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('room-orientation-1'))));
    await tester.pump(const Duration(seconds: 1));
    await hold.up();
    await tester.pump();
    expect(find.text('当作竖屏直播：画面加高、下面是可拖的面板，能进竖屏全屏'), findsOneWidget);
    expect(choice.value, RoomOrientation.automatic, reason: 'reading a long-press hint must not select the row');
    expect(find.byKey(const ValueKey('room-orientation-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room-orientation-remember-switch')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle();
    expect(choice.remember, isFalse);
    expect(find.byKey(const ValueKey('room-orientation-0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room-orientation-1')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle();
    expect(choice.value, RoomOrientation.portrait);
    expect(find.byKey(const ValueKey('room-orientation-0')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final scenario in [
    (name: 'portrait-dark', size: const Size(393, 852), scale: 1.0, dark: true),
    (name: 'landscape', size: const Size(852, 393), scale: 1.0, dark: true),
    (name: 'portrait-large', size: const Size(360, 740), scale: 2.0, dark: false),
    (name: 'narrow-large', size: const Size(280, 600), scale: 2.0, dark: false),
  ]) {
    testWidgets('compact orientation menu fits ${scenario.name} without changing on dismiss', (tester) async {
      final choice = await _pump(tester, size: scenario.size, scale: scenario.scale, dark: scenario.dark);
      await tester.tap(find.byKey(const ValueKey('orientation')));
      await tester.pumpAndSettle();
      final rect = tester.getRect(_surface);
      expect(rect.left, greaterThanOrEqualTo(_edgeMargin));
      expect(rect.right, lessThanOrEqualTo(scenario.size.width - _edgeMargin));
      expect(rect.top, greaterThanOrEqualTo(_edgeMargin));
      expect(rect.bottom, lessThanOrEqualTo(scenario.size.height - _edgeMargin));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'orientation-${scenario.name}');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(choice.value, RoomOrientation.automatic);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
