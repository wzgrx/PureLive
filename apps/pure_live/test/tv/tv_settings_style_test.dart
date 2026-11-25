import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/tv/settings/tv_settings_style.dart';

void main() {
  for (final tv in [true, false]) {
    for (final kind in ['filled', 'outlined', 'elevated', 'text', 'icon']) {
      testWidgets('settings $kind focus remains visible with touch highlight mode: tv=$tv', (tester) async {
        final strategy = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
        addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
        final focus = FocusNode();
        addTearDown(focus.dispose);
        const key = ValueKey('target');
        final button = switch (kind) {
          'filled' => FilledButton(key: key, focusNode: focus, onPressed: () {}, child: const Text('Action')),
          'outlined' => OutlinedButton(key: key, focusNode: focus, onPressed: () {}, child: const Text('Action')),
          'elevated' => ElevatedButton(key: key, focusNode: focus, onPressed: () {}, child: const Text('Action')),
          'text' => TextButton(key: key, focusNode: focus, onPressed: () {}, child: const Text('Action')),
          _ => IconButton(key: key, focusNode: focus, onPressed: () {}, icon: const Icon(Icons.more_vert)),
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: const LiveTheme().dark,
            home: Scaffold(
              body: Center(child: tv ? TvSettingsStyle(child: button) : button),
            ),
          ),
        );
        final material = find.descendant(of: find.byKey(key), matching: find.byType(Material)).first;
        BorderSide side() => (tester.widget<Material>(material).shape! as OutlinedBorder).side;
        final idle = side();
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        expect(
          FocusManager.instance.highlightMode,
          FocusHighlightMode.touch,
          reason: 'TV styling must not change global phone/desktop highlight behavior',
        );
        if (tv) {
          expect(side(), const BorderSide(color: TvColors.focusRing, width: 2));
        } else {
          expect(side(), idle, reason: 'ordinary touch-mode buttons keep their existing appearance');
        }
        focus.unfocus();
        await tester.pumpAndSettle();
        expect(side(), idle, reason: 'unfocused and outlined appearances must be preserved');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
