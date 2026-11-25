import 'dart:async';

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
  for (final kind in ['Brightness', 'Volume']) {
    final baseline = kind == 'Brightness' ? 0.5 : 0.4;
    final x = kind == 'Brightness' ? 200.0 : 700.0;
    late List<Completer<double>> reads;
    late List<double> writes;
    late ValueNotifier<bool> enabled;

    Future<void> pump(WidgetTester tester) async {
      reads = [];
      writes = [];
      enabled = ValueNotifier(true);
      tester.view
        ..physicalSize = const Size(932, 430)
        ..devicePixelRatio = 1;
      const channel = MethodChannel('pure_live/device_controls');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'get$kind') {
          final read = Completer<double>();
          reads.add(read);
          return await read.future;
        }
        if (call.method == 'set$kind') {
          writes.add(((call.arguments as Map)['value'] as num).toDouble());
        }
        return null;
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
        enabled.dispose();
        tester.view.reset();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: const LiveTheme().light,
          home: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (context, value, child) =>
                PlayerGestureLayer(controller: const _Room(), enabled: value, child: const SizedBox.expand()),
          ),
        ),
      );
      expect(writes, isEmpty, reason: 'Entering the picture does not set native levels');
    }

    Future<TestGesture> start(WidgetTester tester) async {
      final gesture = await tester.startGesture(Offset(x, 300));
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      return gesture;
    }

    Future<void> resolve(WidgetTester tester, Completer<double> read, double value) async {
      read.complete(value);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('$kind: delayed native read preserves movement after release', (tester) async {
      await pump(tester);
      final gesture = await start(tester);
      expect(reads, hasLength(1));
      expect(writes, isEmpty);
      await gesture.up();
      await resolve(tester, reads.single, baseline);
      expect(writes, hasLength(1));
      expect(writes.single, closeTo(baseline + 80 / 430 * 1.2, 0.0001));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('$kind: delayed read retains movement before later drag updates', (tester) async {
      await pump(tester);
      final gesture = await start(tester);
      await resolve(tester, reads.single, baseline);
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      await gesture.up();
      expect(writes.last, closeTo(baseline + 120 / 430 * 1.2, 0.0001));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('$kind: a new drag invalidates the older read', (tester) async {
      await pump(tester);
      await (await start(tester)).up();
      final second = await start(tester);
      expect(reads, hasLength(2));
      await resolve(tester, reads.last, baseline);
      final count = writes.length;
      await resolve(tester, reads.first, 0.05);
      expect(writes, hasLength(count));
      await second.moveBy(const Offset(0, -40));
      await tester.pump();
      await second.up();
      expect(writes.last, closeTo(baseline + 120 / 430 * 1.2, 0.0001));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    for (final upper in [true, false]) {
      testWidgets('$kind: pending movement clamps each step before reversing ($upper)', (tester) async {
        await pump(tester);
        final gesture = await start(tester);
        await gesture.moveBy(Offset(0, upper ? -1000 : 1000));
        await gesture.moveBy(Offset(0, upper ? 100 : -100));
        await tester.pump();
        await gesture.up();
        await resolve(tester, reads.single, baseline);
        expect(writes, hasLength(1));
        expect(writes.single, closeTo(upper ? 1 - 100 / 430 * 1.2 : 100 / 430 * 1.2, 0.0001));
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    }

    testWidgets('$kind: unlocking before an old read returns does not revive it', (tester) async {
      await pump(tester);
      final gesture = await start(tester);
      enabled.value = false;
      await tester.pump();
      await gesture.up();
      enabled.value = true;
      await tester.pump();
      await resolve(tester, reads.single, baseline);
      expect(writes, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    for (final interruption in ['cancel', 'lock', 'dispose']) {
      testWidgets('$kind: $interruption discards a pending native read', (tester) async {
        await pump(tester);
        final gesture = await start(tester);
        if (interruption == 'cancel') {
          await gesture.cancel();
        } else if (interruption == 'lock') {
          enabled.value = false;
          await tester.pump();
          await gesture.up();
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
          await gesture.up();
        }
        await resolve(tester, reads.single, baseline);
        expect(writes, isEmpty);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
    }
  }
}
