import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/platform/system_ui.dart';

const _access = MethodChannel('pure_live/system_access');

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
  testWidgets('Android restores Flutter layout before applying the old-system visibility fallback', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') calls.add('${call.arguments}');
      if (call.method == 'SystemChrome.setEnabledSystemUIOverlays') calls.add('visible:${call.arguments}');
      return null;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_access, (call) async {
      calls.add(call.method);
      return true;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_access, null);
    });
    await SystemUiVisibility.restore();
    expect(calls, [
      'SystemUiMode.edgeToEdge',
      'needsLegacySystemBars',
      'visible:[SystemUiOverlay.top, SystemUiOverlay.bottom]',
    ]);
  });

  testWidgets('a newer fullscreen request prevents a late restore from exposing its bars', (tester) async {
    final normal = Completer<Object?>();
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method != 'SystemChrome.setEnabledSystemUIMode') return null;
      calls.add('${call.arguments}');
      if (call.arguments == 'SystemUiMode.edgeToEdge') return await normal.future;
      return null;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_access, (call) async {
      calls.add(call.method);
      return true;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_access, null);
    });
    final restoration = SystemUiVisibility.restore();
    await tester.pump();
    await SystemUiVisibility.fullscreen();
    normal.complete();
    await restoration;
    expect(calls, ['SystemUiMode.edgeToEdge', 'SystemUiMode.immersiveSticky']);
  });

  testWidgets('a new fullscreen also supersedes a delayed old-Android capability answer', (tester) async {
    final answer = Completer<Object?>();
    final overlays = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_access, (_) async => await answer.future);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIOverlays') overlays.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_access, null));
    final restoration = SystemUiVisibility.restore();
    await tester.pump();
    await SystemUiVisibility.fullscreen();
    answer.complete(true);
    await restoration;
    expect(overlays, isEmpty);
  });

  testWidgets('modern Android does not receive the legacy manual overlay mode', (tester) async {
    final overlays = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_access, (_) async => false);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setEnabledSystemUIOverlays') overlays.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_access, null));
    await SystemUiVisibility.restore();
    expect(overlays, isEmpty);
  });

  testWidgets('other platforms retain their normal Flutter policy without Android calls', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_access, (call) async {
      calls.add(call.method);
      return true;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_access, null);
    });
    try {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux]) {
        debugDefaultTargetPlatformOverride = platform;
        await SystemUiVisibility.restore();
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    expect(calls, isEmpty);
  });

  testWidgets('missing or detached old plugins do not break navigation', (tester) async {
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_access, null));
    for (final error in [MissingPluginException(), PlatformException(code: 'detached')]) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_access, (_) async => throw error);
      await SystemUiVisibility.restore();
    }
  });
}
