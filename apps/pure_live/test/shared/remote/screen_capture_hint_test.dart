import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:pure_live/features/remote_receiver/screen_mirror_page.dart';
import 'package:pure_live/shared/remote/screen_capture_hint.dart';
import 'package:pure_live/shared/remote/screen_share.dart';

import '../../support.dart';

class _Track extends Fake implements MediaStreamTrack {
  @override
  String get kind => 'video';
  @override
  void Function()? onEnded;
  @override
  Future<void> stop() async {}
}

class _Stream extends Fake implements MediaStream {
  final track = _Track();
  @override
  List<MediaStreamTrack> getTracks() => [track];
  @override
  List<MediaStreamTrack> getVideoTracks() => [track];
  @override
  Future<void> dispose() async {}
}

void main() {
  test('untrusted modes retain the visible default', () {
    expect(ScreenCaptureHint.of('bad'), ScreenCaptureHint.full);
  });

  testWidgets('full, compact and hidden modes change only the app overlay; compact stop is functional', (tester) async {
    await tester.runAsync(loadStrings);
    final share = ScreenShare(capture: () async => _Stream(), endCapture: () async {});
    await share.startCapture();
    Future<void> show(ScreenCaptureHint hint) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenCaptureIndicatorView(share: share, hint: hint),
        ),
      ),
    );
    await show(ScreenCaptureHint.full);
    expect(find.byType(TextButton), findsOneWidget);
    await show(ScreenCaptureHint.hidden);
    await tester.pump();
    expect(find.byType(TextButton), findsNothing);
    expect(share.capturing, isTrue);
    await show(ScreenCaptureHint.compact);
    await tester.pump();
    final compact = find.byKey(const ValueKey('screen-capture-compact-stop'));
    expect(compact, findsOneWidget);
    expect(tester.getSize(compact).width, lessThanOrEqualTo(48));
    await tester.tap(compact);
    await tester.pump();
    expect(share.capturing, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    share.dispose();
  });

  testWidgets('pending local consent remains visible even with hidden preference and can be cancelled', (tester) async {
    await tester.runAsync(loadStrings);
    final captured = Completer<MediaStream>();
    final share = ScreenShare(capture: () => captured.future, endCapture: () async {});
    final starting = share.startCapture();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScreenCaptureIndicatorView(share: share, hint: ScreenCaptureHint.hidden),
        ),
      ),
    );
    expect(find.byType(TextButton), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    captured.complete(_Stream());
    await starting;
    expect(share.capturing, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    share.dispose();
  });
}
