import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/platform/playback_keyboard_scope.dart';
import 'package:pure_live/routes/route_observer.dart';

void main() {
  const channel = MethodChannel('pure_live/playback_keyboard');
  testWidgets('issue238: native playback IME mode restores for editors, dialogs and route exit', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final calls = <bool>[];
    final methods = <String>[];
    final control = FocusNode();
    final editor = FocusNode();
    final text = TextEditingController();
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        calls.add(call.arguments as bool);
        return null;
      });
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [liveRouteObserver],
        home: PlaybackKeyboardScope(
          child: Scaffold(
            body: Column(
              children: [
                TextField(key: const ValueKey('editor'), focusNode: editor, controller: text),
                TextButton(focusNode: control, autofocus: true, onPressed: () {}, child: const Text('Playback')),
              ],
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(calls.last, isTrue);
    editor.requestFocus();
    await _settle(tester);
    expect(calls.last, isFalse);
    await tester.enterText(find.byKey(const ValueKey('editor')), '中文 F/M 输入');
    expect(text.text, '中文 F/M 输入');
    control.requestFocus();
    await _settle(tester);
    expect(calls.last, isTrue);
    final context = tester.element(find.text('Playback'));
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: TextField(autofocus: true)),
    );
    await _settle(tester);
    expect(calls.last, isFalse);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await _settle(tester);
    control.requestFocus();
    await _settle(tester);
    expect(calls.last, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    expect(calls.last, isFalse);
    expect(tester.takeException(), isNull);
    expect(methods.every((method) => method == 'setPlaybackKeyboardMode'), isTrue);
    messenger.setMockMethodCallHandler(channel, null);
    control.dispose();
    editor.dispose();
    text.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('issue238: overlapping playback owners cannot suppress IME on a covered text route', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final calls = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.arguments as bool);
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [liveRouteObserver],
        home: PlaybackKeyboardScope(
          child: PlaybackKeyboardScope(
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(context)
                      .push<void>(MaterialPageRoute(builder: (_) => const Scaffold(body: TextField(autofocus: true)))),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(calls.last, isTrue);
    await tester.tap(find.text('Open editor'));
    await _settle(tester);
    expect(calls.last, isFalse);
    await tester.enterText(find.byType(TextField), '普通页面中文输入');
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
    expect(calls.last, isFalse);
    expect(tester.takeException(), isNull);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(pumpEventQueue);
  await tester.pump();
}
