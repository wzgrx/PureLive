import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/version/download_directory_dialog.dart';

import '../../support.dart';

Future<List<DownloadDirectoryChoice?>> _open(WidgetTester tester, {required bool canPick}) async {
  final strings = (await tester.runAsync(loadStrings))!;
  final answers = <DownloadDirectoryChoice?>[];
  await tester.pumpWidget(
    LiveUiScope(
      config: LiveUiConfig(strings: strings.ui),
      child: MaterialApp(
        theme: const LiveTheme(primaryColor: Colors.blue).light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => unawaited(
                showDownloadDirectoryDialog(
                  context,
                  defaultPath: '/generated/downloads',
                  canPick: canPick,
                ).then(answers.add),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return answers;
}

bool _focusedIn(String key) {
  final context = FocusManager.instance.primaryFocus?.context;
  return context != null &&
      find
          .descendant(of: find.byKey(ValueKey(key)), matching: find.byElementPredicate((e) => e == context))
          .evaluate()
          .isNotEmpty;
}

void main() {
  for (final (name, canPick, moveLeft, answer) in [
    ('picker', true, false, DownloadDirectoryChoice.pick),
    ('default folder after left', true, true, DownloadDirectoryChoice.useDefault),
    ('no system picker', false, false, DownloadDirectoryChoice.useDefault),
  ]) {
    testWidgets('issue132 first-use download folder has immediate TV action focus: $name', (tester) async {
      final answers = await _open(tester, canPick: canPick);
      expect(answers, isEmpty);
      expect(_focusedIn(canPick ? 'download-directory-pick' : 'download-directory-use-default'), isTrue);
      if (moveLeft) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(_focusedIn('download-directory-use-default'), isTrue);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(answers, [answer]);
    });
  }
}
