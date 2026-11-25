import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/tv/settings/tv_settings_section_page.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';

import '../support.dart';

void main() {
  testWidgets('issue131 native-path directional traversal can adjust a shared slider', (tester) async {
    await tester.runAsync(loadStrings);
    var value = 0.5;
    final changes = <double>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
          child: child!,
        ),
        home: TvSettingsScaffold(
          title: 'Settings',
          child: StatefulBuilder(
            builder: (context, setState) => ListView(
              children: [
                SettingsLinkRow(title: 'Before', onTap: () {}),
                SettingsSliderRow(
                  title: 'Volume',
                  value: value,
                  min: 0,
                  max: 1,
                  label: '${(value * 100).round()}%',
                  onChanged: (next) => setState(() {
                    value = next;
                    changes.add(next);
                  }),
                ),
                SettingsLinkRow(title: 'After', onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final sliderFocus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(value, greaterThan(.5));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(value, closeTo(.5, .001));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(value, closeTo(.5, .001));
    expect(FocusManager.instance.primaryFocus, isNot(sliderFocus));
    expect(changes, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('settings replace a focused loading row with their real first row', (tester) async {
    await tester.runAsync(loadStrings);
    final ready = ValueNotifier(0);
    final temporary = FocusNode(debugLabel: 'temporary settings row');
    final first = FocusNode(debugLabel: 'loaded first row');
    final second = FocusNode(debugLabel: 'loaded second row');
    addTearDown(ready.dispose);
    addTearDown(temporary.dispose);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TvSettingsScaffold(
          title: 'Settings',
          child: ValueListenableBuilder<int>(
            valueListenable: ready,
            builder: (context, loaded, _) => loaded > 0
                ? Column(
                    key: const ValueKey('loaded'),
                    children: [
                      TextButton(focusNode: first, onPressed: () {}, child: const Text('First row')),
                      TextButton(focusNode: second, onPressed: () {}, child: const Text('Second row')),
                    ],
                  )
                : TextButton(
                    key: const ValueKey('loading'),
                    focusNode: temporary,
                    onPressed: () {},
                    child: const Text('Temporary row while loading'),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(temporary.hasFocus, isTrue);
    ready.value = 1;
    await tester.pumpAndSettle();
    expect(first.hasFocus, isTrue, reason: 'removing the loading target must not leave the scope without a row');
    second.requestFocus();
    await tester.pumpAndSettle();
    ready.value = 2;
    await tester.pumpAndSettle();
    expect(second.hasFocus, isTrue, reason: 'ordinary rebuilds must keep the selected row');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('settings loaded under a dialog receive their initial focus when it closes', (tester) async {
    await tester.runAsync(loadStrings);
    final navigator = GlobalKey<NavigatorState>();
    final ready = ValueNotifier(false);
    final first = FocusNode(debugLabel: 'loaded settings row');
    final second = FocusNode(debugLabel: 'user selected row');
    addTearDown(ready.dispose);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
          child: TvTheme(palette: TvPalette.of(Theme.of(context).colorScheme), child: child!),
        ),
        home: const Scaffold(body: Text('Home')),
      ),
    );
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (context) => TvSettingsScaffold(
          title: 'Settings',
          child: ValueListenableBuilder<bool>(
            valueListenable: ready,
            builder: (context, loaded, _) => loaded
                ? Column(
                    children: [
                      TvButton(label: 'Loaded row', focusNode: first, onTap: () {}),
                      TvButton(label: 'Second row', focusNode: second, onTap: () {}),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
    await tester.pump();

    showDialog<void>(
      context: navigator.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('Temporary dialog'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    ready.value = true;
    await tester.pump();
    expect(first.hasFocus, isFalse, reason: 'the loading page must not steal the dialog focus');
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(first.hasFocus, isTrue, reason: 'the first usable row is now attached and uncovered');
    second.requestFocus();
    await tester.pump();

    showDialog<void>(
      context: navigator.currentContext!,
      builder: (context) => const AlertDialog(title: Text('Another dialog')),
    );
    await tester.pump(const Duration(seconds: 1));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(second.hasFocus, isTrue, reason: 'returning later must preserve the user selected row');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
