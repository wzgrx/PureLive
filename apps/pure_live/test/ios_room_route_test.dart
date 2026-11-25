import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/routes/app_router.dart';

void main() {
  testWidgets('issue #85: the production live-room route supports a cancellable iOS edge swipe', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var removed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Navigator(
          pages: [
            const MaterialPage<void>(
              key: ValueKey('home'),
              child: Scaffold(body: Text('home')),
            ),
            liveRoomPage(
              key: const ValueKey('room'),
              child: const Scaffold(body: Text('room')),
            ),
          ],
          onDidRemovePage: (_) => removed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final short = await tester.startGesture(const Offset(6, 300));
    await short.moveBy(const Offset(35, 0));
    await tester.pump(const Duration(seconds: 1));
    await short.up();
    await tester.pumpAndSettle();
    expect(removed, isFalse, reason: 'a short cancelled swipe must keep the player route');
    await tester.dragFrom(const Offset(6, 300), const Offset(310, 0));
    await tester.pumpAndSettle();
    expect(removed, isTrue, reason: 'the production route must install the iOS pop recognizer');
    debugDefaultTargetPlatformOverride = null;
  });
}
