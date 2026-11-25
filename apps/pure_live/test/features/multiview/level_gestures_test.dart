import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/features/multiview/widgets/level_gestures.dart';
import 'package:pure_live/platform/device_controls.dart';

import 'multiview_support.dart';

void main() {
  for (final action in ['volume', 'brightness', 'horizontal', 'multitouch']) {
    testWidgets('issue106 landscape $action stays isolated from other cells', (tester) async {
      tester.view
        ..physicalSize = const Size(800, 400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      DeviceControls.debugAvailable = true;
      addTearDown(() => DeviceControls.debugAvailable = null);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('pure_live/device_controls'), (
        call,
      ) async {
        calls.add(call);
        return call.method == 'getBrightness' ? 0.4 : null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('pure_live/device_controls'),
          null,
        ),
      );
      final store = (await tester.runAsync(memoryStore))!;
      final controller = multiviewController(store, RoomsSite());
      await tester.runAsync(() async {
        await controller.start();
        await controller.setLayout(MultiviewLayout.dual);
        await controller.assign(0, pickRoom('a'));
        await controller.assign(1, pickRoom('b'));
        await controller.setVolume(0, 0.3);
        await controller.setVolume(1, 0.5);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiviewLevelGestures(
              controller: controller,
              selectedIndex: 1,
              enabled: true,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );
      switch (action) {
        case 'volume':
          await tester.dragFrom(const Offset(650, 220), const Offset(0, -80));
          await tester.pump();
          expect(controller.cells[1].volume, greaterThan(0.6));
          expect(controller.cells[0].volume, 0.3);
        case 'brightness':
          await tester.dragFrom(const Offset(150, 220), const Offset(0, -80));
          await tester.pump();
          expect(calls.where((c) => c.method == 'setBrightness'), isNotEmpty);
          expect(controller.cells[1].volume, 0.5);
        case 'horizontal':
          await tester.dragFrom(const Offset(650, 220), const Offset(-140, -20));
          await tester.pump();
          expect(controller.cells[1].volume, 0.5);
          expect(calls.where((c) => c.method == 'setBrightness'), isEmpty);
        case 'multitouch':
          final first = await tester.startGesture(const Offset(650, 220), pointer: 1);
          final second = await tester.startGesture(const Offset(550, 220), pointer: 2);
          await first.moveBy(const Offset(0, -90));
          await second.moveBy(const Offset(0, 70));
          await first.up();
          await second.up();
          await tester.pump();
          expect(controller.cells[1].volume, 0.5);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(seconds: 1));
        controller.dispose();
        await store.close();
      });
      expect(tester.takeException(), isNull);
    });
  }
}
