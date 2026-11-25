// A01.6: the liquid glass bar. The shader does not run here (no Impeller),
// so this is the frosted fallback; the choices and the drag are the same.
import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<List<int>> pump(
    WidgetTester tester, {
    int selected = 0,
    bool still = false,
    double height = GlassMetrics.barHeight,
    double frost = 0.5,
  }) async {
    final chosen = <int>[];
    var index = selected;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: still),
          child: child!,
        ),
        theme: const LiveTheme().light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 400,
              height: height,
              child: StatefulBuilder(
                builder: (context, setState) => LiquidGlassBar(
                  height: height,
                  frost: frost,
                  selectedIndex: index,
                  onSelected: (next) => setState(() {
                    chosen.add(next);
                    index = next;
                  }),
                  items: [
                    for (final name in ['关注', '热门', '分区', '录制中心'])
                      LiquidGlassBarItem(icon: Icons.circle_outlined, selectedIcon: Icons.circle, label: name),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return chosen;
  }

  Finder item(String name) => find.text(name);

  testWidgets('a tap chooses; the chosen one tapped again is told too', (tester) async {
    final chosen = await pump(tester);
    await tester.tap(item('分区'));
    await tester.pumpAndSettle();
    await tester.tap(item('分区'));
    await tester.pumpAndSettle();
    expect(chosen, [2, 2]);
  });

  testWidgets('dragged along the bar the choice follows the finger; far past the end it is the last', (tester) async {
    final chosen = await pump(tester);
    await tester.dragFrom(tester.getCenter(item('关注')), tester.getCenter(item('分区')) - tester.getCenter(item('关注')));
    await tester.pumpAndSettle();
    expect(chosen, [2]);
    await tester.dragFrom(tester.getCenter(item('分区')), const Offset(800, 0));
    await tester.pumpAndSettle();
    expect(chosen, [2, 3]);
    // A drag that ends over the chosen one changes nothing.
    await tester.dragFrom(tester.getCenter(item('录制中心')), const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(chosen, [2, 3]);
  });

  testWidgets('each destination is a labelled button at least 48 high, the chosen one selected', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, selected: 1);
    final hot = tester.getSemantics(find.bySemanticsLabel('热门'));
    expect(hot.flagsCollection.isSelected, Tristate.isTrue);
    expect(hot.flagsCollection.isButton, isTrue);
    expect(hot.rect.height, greaterThanOrEqualTo(48));
    expect(tester.getSemantics(find.bySemanticsLabel('关注')).flagsCollection.isSelected, Tristate.isFalse);
    handle.dispose();
  });

  double held(WidgetTester tester) => tester
      .renderObject<RenderLiquidGlass>(
        find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_LiquidGlass'),
      )
      .held();

  testWidgets('A01.7: held, the pill turns into a lens and back when let go; the bar swells a little', (tester) async {
    await pump(tester);
    expect(held(tester), 0);
    final touch = await tester.startGesture(tester.getCenter(item('关注')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(held(tester), greaterThan(0.9));
    final scale = tester.widget<Transform>(
      find.descendant(of: find.byType(LiquidGlassBar), matching: find.byType(Transform)).at(1),
    );
    expect(scale.transform.getMaxScaleOnAxis(), greaterThan(1));
    await touch.up();
    await tester.pumpAndSettle();
    expect(held(tester), closeTo(0, 0.01));
  });

  testWidgets('A01.7: chosen elsewhere, the drop goes there as a lens and rests as a pill', (tester) async {
    await pump(tester);
    await tester.tap(item('录制中心'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(held(tester), greaterThan(0.5));
    await tester.pumpAndSettle();
    expect(held(tester), closeTo(0, 0.01));
  });

  testWidgets('A01.7: with animations off the drop is always a pill', (tester) async {
    final chosen = await pump(tester, still: true);
    final touch = await tester.startGesture(tester.getCenter(item('热门')));
    await tester.pump(const Duration(milliseconds: 150));
    expect(held(tester), 0);
    await touch.up();
    await tester.pump();
    expect(chosen, [1]);
    expect(held(tester), 0);
  });

  testWidgets('A01.7: one name and one pair of icons per destination (the chosen colour only under the drop)', (
    tester,
  ) async {
    await pump(tester, selected: 2);
    for (final name in ['关注', '热门', '分区', '录制中心']) {
      expect(item(name), findsOneWidget);
    }
    expect(find.byIcon(Icons.circle), findsNWidgets(4));
    expect(find.byIcon(Icons.circle_outlined), findsNWidgets(4));
  });

  testWidgets('A01.7: pressed, the drop goes under the finger at once; slid off, it goes back', (tester) async {
    final chosen = await pump(tester);
    Rect drop() => tester
        .renderObject<RenderLiquidGlass>(
          find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_LiquidGlass'),
        )
        .drop();
    final start = drop().center.dx;
    final touch = await tester.startGesture(tester.getCenter(item('分区')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final left = tester.getTopLeft(find.byType(LiquidGlassBar)).dx;
    expect((drop().center.dx + left - tester.getCenter(item('分区')).dx).abs(), lessThan(4));
    expect(chosen, isEmpty);
    // Up and away: no tap, no drag along the bar.
    await touch.moveBy(const Offset(0, -200));
    await touch.up();
    await tester.pumpAndSettle();
    expect(chosen, isEmpty);
    expect((drop().center.dx - start).abs(), lessThan(1));
  });

  testWidgets('issue #11: a finger that moves every frame moves the drop every frame', (tester) async {
    await pump(tester);
    double drop() => tester.allRenderObjects.whereType<RenderLiquidGlass>().single.drop().center.dx;
    final gesture = await tester.startGesture(tester.getCenter(item('关注')));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(20, 0)); // past the touch slop
    await tester.pump(const Duration(milliseconds: 8));
    // The first move starts the spring (its first frame is at time 0).
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump(const Duration(milliseconds: 8));
    final seen = <double>[drop()];
    // One move per frame, as a phone delivers them: each frame the drop is
    // further on (a new spring per move held it still).
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump(const Duration(milliseconds: 8));
      seen.add(drop());
    }
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThan(seen[i - 1]), reason: 'frame $i: $seen');
    }
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('A01.8 (iOS 27): no shadow, the frost reaches the glass, the held lens magnifies its icon', (
    tester,
  ) async {
    await pump(tester, frost: 0.8);
    final glass = tester.allRenderObjects.whereType<RenderLiquidGlass>().single;
    expect(glass.frost, 0.8);
    final shadows = tester
        .widgetList<DecoratedBox>(find.descendant(of: find.byType(LiquidGlassBar), matching: find.byType(DecoratedBox)))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where((decoration) => decoration.boxShadow?.isNotEmpty ?? false);
    expect(shadows, isEmpty);

    double lensIcon() => tester
        .widget<Transform>(find.ancestor(of: find.byIcon(Icons.circle).first, matching: find.byType(Transform)).first)
        .transform
        .getMaxScaleOnAxis();
    expect(lensIcon(), 1);
    final gesture = await tester.startGesture(tester.getCenter(item('关注')));
    await tester.pumpAndSettle();
    expect(lensIcon(), closeTo(1.14, 0.01));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(lensIcon(), closeTo(1, 0.001));
  });

  test('V02.11 (issue #9): the room under the capsule', () {
    // Nothing at the bottom (gestures without a handle, a window): 12.
    expect(GlassMetrics.barGap(safeBottom: 0, ios: false), GlassMetrics.barMargin);
    expect(GlassMetrics.barGap(safeBottom: 0, ios: true), GlassMetrics.barMargin);
    // An iPhone's home indicator: 20, not 34 + 12; an iPad's: at least 12.
    expect(GlassMetrics.barGap(safeBottom: 34, ios: true), 20);
    expect(GlassMetrics.barGap(safeBottom: 20, ios: true), GlassMetrics.barMargin);
    // Android's handle, in the middle of its inset: 6 above it.
    expect(GlassMetrics.barGap(safeBottom: 24, ios: false), 20);
    expect(GlassMetrics.barGap(safeBottom: 16, ios: false), 16);
    // Android's buttons: 12 above them, as before.
    expect(GlassMetrics.barGap(safeBottom: 48, ios: false), 60);
  });

  testWidgets('V02.11: the compact capsule is 56 high and round; a large font fits', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final chosen = await pump(tester, height: GlassMetrics.barHeightCompact);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(LiquidGlassBar)).height, GlassMetrics.barHeightCompact);
    // The glass is a capsule of that height: its corners are half of it.
    expect(tester.allRenderObjects.whereType<RenderLiquidGlass>().single.size.height, GlassMetrics.barHeightCompact);
    await tester.tap(item('热门'));
    await tester.pumpAndSettle();
    expect(chosen, [1]);
  });
}
