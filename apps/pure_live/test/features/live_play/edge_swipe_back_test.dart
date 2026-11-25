import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/live_play/layout/edge_swipe_back.dart';

void main() {
  Future<List<String>> pump(WidgetTester tester, {required bool enabled}) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: EdgeSwipeBack(
          enabled: enabled,
          onBack: () => calls.add('back'),
          child: GestureDetector(
            onHorizontalDragEnd: (_) => calls.add('picture'),
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );
    return calls;
  }

  testWidgets('A18.1 c3: a swipe in from the left edge goes back (full screen off, a panel closes)', (tester) async {
    final calls = await pump(tester, enabled: true);
    await tester.dragFrom(const Offset(6, 300), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(calls, ['back']);
  });

  testWidgets("a short one, or one starting inside the picture, is the picture's own", (tester) async {
    final calls = await pump(tester, enabled: true);
    await tester.dragFrom(const Offset(6, 300), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(calls, isEmpty, reason: 'too short');
    await tester.dragFrom(const Offset(200, 300), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(calls, ['picture']);
  });

  testWidgets('off (Android, or the system swipe pops the room): nothing caught', (tester) async {
    final calls = await pump(tester, enabled: false);
    await tester.dragFrom(const Offset(6, 300), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(calls, ['picture']);
  });
}
