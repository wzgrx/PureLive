import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/backup/log_page.dart';
import 'package:pure_live/shared/phone_bridge.dart';

import '../../support.dart';

void main() {
  setUpAll(loadStrings);
  for (final television in [true, false]) {
    testWidgets('issue54: ${television ? 'TV uses its phone bridge' : 'phone keeps native sharing'} for the full log', (
      tester,
    ) async {
      final directory = (await tester.runAsync(() => Directory.systemTemp.createTemp('purelive516-log-')))!;
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => directory.path,
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
      );
      final services = (await tester.runAsync(testServices))!;
      addTearDown(() => tester.runAsync(services.close));
      final log = AppLog()
        ..info('generated', 'full-log-fixture')
        ..warning('generated', 'visible warning fixture');
      final dispatched = Completer<void>();
      var nativeCalls = 0;
      String? bridgeText;
      String? nativeText;
      Widget page = LogPage(log: log);
      if (television) {
        page = PhoneBridge(
          input: (_, _) async => null,
          view: (_, {required title, required text}) async {
            bridgeText = text;
            dispatched.complete();
          },
          child: page,
        );
      }
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appServicesProvider.overrideWithValue(services),
            logSharerProvider.overrideWithValue((file) async {
              nativeCalls++;
              nativeText = file.readAsStringSync();
              dispatched.complete();
              return true;
            }),
          ],
          child: MaterialApp(home: page),
        ),
      );
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('log-filter')), matching: find.text('警告')));
      await tester.pump();
      expect(find.textContaining('full-log-fixture'), findsNothing);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('log-share'))).onPressed, isNotNull);
      await tester.tap(find.byKey(const ValueKey('log-share')));
      // The widget runs in fake async while export uses real file I/O.
      // Advance both until a handler is reached, with a bounded wait.
      for (var attempt = 0; attempt < 10 && !dispatched.isCompleted; attempt++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        await tester.pump();
      }
      expect(dispatched.isCompleted, isTrue, reason: 'export must reach either the bridge or the native sharer');
      await tester.pump();
      expect(nativeCalls, television ? 0 : 1);
      expect(television ? bridgeText : nativeText, contains('full-log-fixture'));
      await tester.pumpWidget(const SizedBox.shrink());
      log.dispose();
    });
  }
}
