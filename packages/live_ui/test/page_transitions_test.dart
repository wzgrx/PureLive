// A03.5 / R01.3: pages come and go with a spring slide; nothing fades

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
// (fade-forwards drew both pages into offscreen layers every frame).
import 'package:material_ui/material_ui.dart';

void main() {
  test('the spring curve starts at 0, ends at exactly 1, never passes it and is fast at first', () {
    final curve = SpringCurve(AppMotion.pageTransitionSpring, SpringPageTransitionsBuilder.duration);
    expect(curve.transform(0), 0);
    expect(curve.transform(1), 1);
    var last = 0.0;
    for (var i = 1; i <= 100; i++) {
      final v = curve.transform(i / 100);
      expect(v, greaterThanOrEqualTo(last));
      expect(v, lessThanOrEqualTo(1));
      last = v;
    }
    // Most of the way in the first third, as a thrown page would be.
    expect(curve.transform(1 / 3), greaterThan(0.7));
  });

  testWidgets('push: the page slides in from the right, the page under moves a quarter left, no opacity layers', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: const LiveTheme().light.copyWith(platform: TargetPlatform.android),
        home: const Scaffold(body: Text('first')),
      ),
    );
    final route = MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('second')));
    navigator.currentState!.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final second = tester.getTopLeft(find.text('second')).dx;
    final first = tester.getTopLeft(find.text('first')).dx;
    expect(second, inExclusiveRange(0, 400));
    expect(first, lessThan(0));
    expect(tester.layers.whereType<OpacityLayer>(), isEmpty, reason: 'nothing fades');
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('second')).dx, 0);
    expect(route.transitionDuration, SpringPageTransitionsBuilder.duration);
    expect(route.reverseTransitionDuration, SpringPageTransitionsBuilder.reverseDuration);
    // Settled within the push's duration.
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(SpringPageTransitionsBuilder.reverseDuration + const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('second'), findsNothing);
    expect(tester.getTopLeft(find.text('first')).dx, 0);
  });
}
