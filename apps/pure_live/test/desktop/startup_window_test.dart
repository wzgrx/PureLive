import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/app/desktop/app_window_api.dart';
import 'package:pure_live/app/desktop/startup_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('X01.5: first-frame readiness waits for the entire saved layout', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final messages = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messages
      ..setMockMethodCallHandler(const MethodChannel('window_manager'), (call) async {
        calls.add(call.method);
        if (call.method.startsWith('is')) return false;
        return null;
      })
      ..setMockMethodCallHandler(const MethodChannel('pure_live/window_startup'), (call) async {
        calls.add(call.method);
        return null;
      });
    addTearDown(() {
      messages
        ..setMockMethodCallHandler(const MethodChannel('window_manager'), null)
        ..setMockMethodCallHandler(const MethodChannel('pure_live/window_startup'), null);
    });
    final maximized = Completer<void>();
    var ready = false;
    final restoring = restoreStartupWindow(const AppWindowOptions(), () async {
      calls.add('restore-begin');
      await maximized.future;
      calls.add('restore-finished');
    }, prepare: (_) async => calls.add('prepare')).then((_) => ready = true);
    await Future<void>.delayed(const Duration(seconds: 1));
    expect(calls, contains('restore-begin'));
    expect(calls, isNot(contains('layoutReady')));
    expect(ready, isFalse, reason: 'runApp must not race a saved maximize/position');
    maximized.complete();
    await restoring;
    expect(calls.indexOf('layoutReady'), greaterThan(calls.indexOf('restore-finished')));
    expect(ready, isTrue);
  });
}
