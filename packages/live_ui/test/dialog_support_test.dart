import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('DialogButtonsTheme puts the buttons on the 14-point role; DialogKeys: Enter and Esc', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: const LiveTheme().light,
        home: Scaffold(
          body: Column(
            children: [
              TextButton(onPressed: () {}, child: const Text('outside')),
              DialogButtonsTheme(
                child: DialogKeys(
                  onEnter: () => calls.add('enter'),
                  onEscape: () => calls.add('escape'),
                  child: Row(
                    children: [
                      TextButton(onPressed: () => calls.add('cancel'), child: const Text('取消')),
                      FilledButton(onPressed: () => calls.add('ok'), child: const Text('确定')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    double size(String text) => tester.renderObject<RenderParagraph>(find.text(text)).text.style!.fontSize!;
    // The theme's button label is 13 (3.x); inside a dialog it is 14.
    expect(size('outside'), 13);
    expect(size('取消'), 14);
    expect(size('确定'), 14);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(calls, ['enter', 'escape']);

    // A focused button keeps its own Enter.
    Focus.of(tester.element(find.text('取消'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls.last, 'cancel');
  });

  testWidgets('issue #8: a TV remote reaches the controls of a dialog that took the focus itself', (tester) async {
    final calls = <String>[];
    var ticked = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: const LiveTheme().light,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => StatefulBuilder(
                builder: (context, setState) => AppDialog(
                  title: '发送配置',
                  content: CheckboxListTile(
                    key: const ValueKey('box'),
                    value: ticked,
                    onChanged: (value) => setState(() => ticked = value!),
                    title: const Text('设置'),
                  ),
                  onEnter: () => calls.add('enter'),
                  actions: [
                    TextButton(
                      key: const ValueKey('cancel'),
                      onPressed: () => calls.add('cancel'),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      key: const ValueKey('send'),
                      onPressed: () => calls.add('send'),
                      child: const Text('发送'),
                    ),
                  ],
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    Future<void> open() async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    bool focusedIn(String key) {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) return false;
      final target = find.byKey(ValueKey(key));
      return find
              .descendant(of: target, matching: find.byElementPredicate((e) => e == focused))
              .evaluate()
              .isNotEmpty ||
          tester.element(target) == focused;
    }

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    await open();
    // The remote's arrows: into the dialog, through the box to the buttons.
    await press(LogicalKeyboardKey.arrowDown);
    expect(focusedIn('box'), isTrue, reason: 'down enters the dialog at its first control');
    await press(LogicalKeyboardKey.select);
    expect(ticked, isFalse, reason: 'OK on the focused box ticks it');
    await press(LogicalKeyboardKey.arrowDown);
    expect(focusedIn('cancel') || focusedIn('send'), isTrue);
    if (focusedIn('cancel')) await press(LogicalKeyboardKey.arrowRight);
    expect(focusedIn('send'), isTrue);
    await press(LogicalKeyboardKey.select);
    expect(calls, ['send'], reason: 'OK on 发送 sends; the dialog shell never did');

    // OK while the dialog itself holds the focus moves in and presses nothing.
    Navigator.of(tester.element(find.text('发送'))).pop();
    await tester.pumpAndSettle();
    await open();
    await press(LogicalKeyboardKey.select);
    expect(calls, ['send']);
    expect(focusedIn('box'), isTrue);
    // A keyboard's Enter on the dialog itself still presses the main action.
    Navigator.of(tester.element(find.text('发送'))).pop();
    await tester.pumpAndSettle();
    await open();
    await press(LogicalKeyboardKey.enter);
    expect(calls, ['send', 'enter']);
  });
}
