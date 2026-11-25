// R01.3: a page turn blends the tab styles every frame; the label's weight
// snaps at the half way so the app bar is not laid out again each frame
// (on the K90 that was most of the 165 ms of text layout in 8 page turns).
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('the weight snaps to the nearer of the two', () {
    const theme = TabBarThemeData(
      labelStyle: TextStyle(fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w400),
    );
    expect(snapTabWeight(FontWeight.w400, theme), FontWeight.w400);
    expect(snapTabWeight(FontWeight.w600, theme), FontWeight.w600);
    expect(snapTabWeight(FontWeight.lerp(FontWeight.w400, FontWeight.w600, 0.3), theme), FontWeight.w400);
    expect(snapTabWeight(FontWeight.lerp(FontWeight.w400, FontWeight.w600, 0.7), theme), FontWeight.w600);
    expect(snapTabWeight(FontWeight.w800, theme), FontWeight.w800);
    expect(snapTabWeight(FontWeight.w500, const TabBarThemeData()), FontWeight.w500);
  });

  testWidgets('dragging the pages does not lay the app bar out every frame', (tester) async {
    final controller = TabController(length: 12, vsync: const TestVSync());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: const LiveTheme().light,
        home: Scaffold(
          appBar: AppBar(
            title: ScrollableTabBar(
              controller: controller,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (var i = 0; i < 12; i++) TabLabel(label: '平台$i')],
            ),
          ),
          body: TabBarView(controller: controller, children: [for (var i = 0; i < 12; i++) Text('$i')]),
        ),
      ),
    );
    var scaffoldLayouts = 0;
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null && message.startsWith('markNeedsLayout() called for RenderCustomMultiChildLayoutBox')) {
        scaffoldLayouts++;
      }
    };
    debugPrintMarkNeedsLayoutStacks = true;
    try {
      final gesture = await tester.startGesture(const Offset(400, 400));
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(const Offset(-12, 0));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    } finally {
      debugPrintMarkNeedsLayoutStacks = false;
      debugPrint = previous;
    }
    // Once when the weights swap half way, and a little around it; not
    // once a frame (it was every one of the 30-odd frames).
    expect(scaffoldLayouts, lessThanOrEqualTo(4));
    expect(controller.index, 1);
  });
}
