import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/shared/remote/application_remote.dart';

void main() {
  testWidgets('remote navigation reenters the app after platform-level focus restoration', (tester) async {
    final platformFocus = FocusNode();
    final navigator = GlobalKey<NavigatorState>();
    var pressed = 0;
    final remote = ApplicationRemote(
      revision: () => 1,
      back: () async => true,
      home: () {},
      available: () => true,
      focusRoot: () => navigator.currentState?.focusNode,
    );
    await tester.pumpWidget(
      Focus(
        focusNode: platformFocus,
        child: MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: TextButton(onPressed: () => pressed++, child: const Text('First action')),
          ),
        ),
      ),
    );
    platformFocus.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(platformFocus));
    await remote.execute('down');
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, isNot(platformFocus));
    await remote.execute('ok');
    await tester.pump();
    expect(pressed, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    remote.dispose();
    platformFocus.dispose();
  });

  testWidgets('application OK uses ordinary focused button activation', (tester) async {
    var pressed = 0;
    final remote = ApplicationRemote(revision: () => 1, back: () async => true, home: () {}, available: () => true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextButton(autofocus: true, onPressed: () => pressed++, child: const Text('Action')),
        ),
      ),
    );
    await tester.pump();
    await remote.execute('ok');
    await tester.pump();
    expect(pressed, 1);
    remote.dispose();
  });

  testWidgets('platform focus recovery enters the covering dialog instead of the page below', (tester) async {
    final platformFocus = FocusNode();
    final navigator = GlobalKey<NavigatorState>();
    var pagePressed = 0;
    var dialogPressed = 0;
    final remote = ApplicationRemote(
      revision: () => 1,
      back: () async => true,
      home: () {},
      available: () => true,
      focusRoot: () => navigator.currentState?.focusNode,
    );
    await tester.pumpWidget(
      Focus(
        focusNode: platformFocus,
        child: MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: TextButton(onPressed: () => pagePressed++, child: const Text('Covered page')),
          ),
        ),
      ),
    );
    final closed = showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => AlertDialog(
        title: const Text('Covering dialog'),
        actions: [TextButton(onPressed: () => dialogPressed++, child: const Text('Dialog action'))],
      ),
    );
    await tester.pumpAndSettle();
    platformFocus.requestFocus();
    await tester.pump();
    await remote.execute('down');
    await tester.pump();
    await remote.execute('ok');
    await tester.pump();
    expect(dialogPressed, 1);
    expect(pagePressed, 0);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await closed;
    await tester.pumpWidget(const SizedBox.shrink());
    remote.dispose();
    platformFocus.dispose();
  });

  testWidgets('text requires the same focused field and never appears in status', (tester) async {
    final first = TextEditingController(text: 'private-value');
    final second = TextEditingController();
    final remote = ApplicationRemote(revision: () => 1, back: () async => true, home: () {}, available: () => true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(key: const ValueKey('first'), controller: first, obscureText: true),
              TextField(key: const ValueKey('second'), controller: second),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('first')));
    await tester.pump();
    final state = remote.target.snapshot();
    final input = state['inputId']! as int;
    expect(state.toString(), isNot(contains('private-value')));
    expect(state['secretInput'], isTrue);
    first.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
    expect(await remote.insertText('local', input), isTrue);
    expect(first.text, 'local-value');
    await tester.tap(find.byKey(const ValueKey('second')));
    await tester.pump();
    expect(await remote.insertText('late', input), isFalse);
    expect(second.text, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    remote.dispose();
    first.dispose();
    second.dispose();
  });

  testWidgets('page, dialog and removal change the application command identity', (tester) async {
    final observer = LiveRouteObserver();
    final key = GlobalKey<NavigatorState>();
    final remote = ApplicationRemote(
      revision: () => observer.revision,
      back: () async => true,
      home: () {},
      available: () => true,
    );
    await tester.pumpWidget(MaterialApp(navigatorKey: key, navigatorObservers: [observer], home: const Scaffold()));
    final home = remote.target.id;
    final route = MaterialPageRoute<void>(builder: (_) => const Scaffold());
    final pending = key.currentState!.push(route);
    await tester.pumpAndSettle();
    expect(remote.target.id, isNot(home));
    final page = remote.target.id;
    final dialog = showDialog<void>(
      context: key.currentContext!,
      builder: (_) => const AlertDialog(title: Text('Modal')),
    );
    await tester.pumpAndSettle();
    expect(remote.target.id, isNot(page));
    key.currentState!.pop();
    await tester.pumpAndSettle();
    await dialog;
    expect(remote.target.id, isNot(page));
    key.currentState!.removeRoute(route);
    await tester.pumpAndSettle();
    await pending;
    remote.dispose();
  });
}
