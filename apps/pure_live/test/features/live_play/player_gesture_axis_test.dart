import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/player/player_gestures.dart';

final class _Room implements LiveRoomController {
  const new();

  @override
  double get volume => 0.4;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final size in [const Size(393, 852), const Size(852, 393)]) {
      for (final left in [true, false]) {
        for (final coalesced in [true, false]) {
          testWidgets('issue 93: horizontal drift is ignored $size left=$left coalesced=$coalesced', (tester) async {
            tester.view
              ..physicalSize = size
              ..devicePixelRatio = 1;
            final writes = <String>[];
            const channel = MethodChannel('pure_live/device_controls');
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
              if (call.method.startsWith('get')) return 0.4;
              if (call.method.startsWith('set')) writes.add(call.method);
              return null;
            });
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump(const Duration(seconds: 2));
              tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
              tester.view.reset();
            });
            await tester.pumpWidget(
              MaterialApp(
                theme: const LiveTheme().light,
                home: const PlayerGestureLayer(controller: _Room(), child: SizedBox.expand()),
              ),
            );
            final start = Offset(left ? 60 : size.width - 60, size.height / 2);
            final sign = left ? 1.0 : -1.0;
            final drag = await tester.startGesture(start);
            if (coalesced) {
              // Both axis thresholds are crossed in the same pointer event.
              await drag.moveBy(Offset(100 * sign, 24));
            } else {
              for (var i = 0; i < 5; i++) {
                await drag.moveBy(Offset(20 * sign, 5));
                await tester.pump();
              }
            }
            await tester.pump();
            await drag.moveBy(Offset(30 * sign, 10));
            await tester.pump();
            await drag.up();
            await tester.pumpAndSettle();
            expect(writes, isEmpty, reason: 'A mainly horizontal swipe must not adjust native brightness or volume.');
            expect(find.byKey(const ValueKey('gesture-level-volume')), findsNothing);
            expect(find.byKey(const ValueKey('gesture-level-brightness')), findsNothing);

            // The normal left/right vertical gesture must still work afterwards.
            final vertical = await tester.startGesture(start);
            await vertical.moveBy(const Offset(2, -25));
            await tester.pump();
            await vertical.moveBy(const Offset(2, -60));
            await tester.pump();
            await vertical.up();
            await tester.pump();
            expect(writes, isNotEmpty);
            expect(writes.every((method) => method == (left ? 'setBrightness' : 'setVolume')), isTrue);
          }, variant: TargetPlatformVariant.only(platform));
        }
      }
    }
  }
}
