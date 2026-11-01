import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_grid.dart';

void main() {
  testWidgets('a deferred offscreen request cannot steal later user focus', (tester) async {
    final grid = GlobalKey<TvGridState>();
    final outside = FocusNode(debugLabel: 'outside grid');
    addTearDown(outside.dispose);
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    await tester.pumpWidget(
      MaterialApp(
        home: TvTheme(
          palette: TvPalette.of(scheme),
          child: Scaffold(
            body: Column(
              children: [
                TvButton(label: '外部按钮', focusNode: outside, onTap: () {}),
                Expanded(
                  child: TvGrid(
                    key: grid,
                    itemCount: 100,
                    columns: 4,
                    aspectRatio: 2,
                    itemBuilder: (context, index, node, onKey) => TvFocusable(
                      key: ValueKey('pending-$index'),
                      focusNode: node,
                      onKey: onKey,
                      onTap: () {},
                      builder: (_, focused) => Text('卡片$index'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    grid.currentState!.focusIndex(0);
    await tester.pump(const Duration(seconds: 1));
    grid.currentState!.focusIndex(99);
    outside.requestFocus();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(outside.hasFocus, isTrue, reason: 'an old post-frame target no longer owns input after the user leaves');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an explicit return target overrides old grid focus memory', (tester) async {
    final grid = GlobalKey<TvGridState>();
    final outside = FocusNode(debugLabel: 'outside grid');
    addTearDown(outside.dispose);
    final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
    await tester.pumpWidget(
      MaterialApp(
        home: TvTheme(
          palette: TvPalette.of(scheme),
          child: Scaffold(
            body: Column(
              children: [
                TvButton(label: '外部按钮', focusNode: outside, onTap: () {}),
                Expanded(
                  child: TvGrid(
                    key: grid,
                    itemCount: 8,
                    columns: 4,
                    aspectRatio: 2,
                    itemBuilder: (context, index, node, onKey) => TvFocusable(
                      key: ValueKey('restore-$index'),
                      focusNode: node,
                      onKey: onKey,
                      onTap: () {},
                      builder: (_, focused) => Text('卡片$index'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    grid.currentState!.focusIndex(0);
    await tester.pump(const Duration(seconds: 1));
    outside.requestFocus();
    await tester.pump(const Duration(seconds: 1));
    grid.currentState!.focusIndex(5);
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<TvFocusable>(find.byKey(const ValueKey('restore-5'))).focusNode!.hasFocus,
      isTrue,
      reason: 'returning after a channel switch must focus the shown room, not the old remembered room',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
