import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/shared/rooms/archive/bilibili_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive/huya_archive_controller.dart';

import '../live_play/live_play_support.dart';

import 'replay_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Bilibili DASH audio, per-part resume, quality permission and playback intent stay coherent', () async {
    var stored = '{}';
    final engine = FakeEngine();
    final source = FakeBiliReplay();
    final progress = HuyaArchiveProgress(
      read: () async => stored,
      write: (v) async => stored = v,
      idPattern: r'^BV[0-9A-Za-z]{10}:[1-9][0-9]{0,18}$',
    );
    await progress.save('BV1234567890:100', const Duration(seconds: 93));
    final c = BilibiliArchiveController(
      source: source,
      session: fakeSession(engine),
      progress: progress,
      initialVolume: 0.4,
    );
    await c.open(archive.bvid);
    expect(c.error, isNull);
    expect(c.video!.id, 'BV1234567890:100');
    expect(c.segments, hasLength(2));
    expect(engine.opens.single.start, const Duration(seconds: 93));
    expect(engine.opens.single.audio?.uri.toString(), contains('/100/audio-'));
    expect(c.qualities.first.playable, isFalse, reason: 'server labels are not a granted media rendition');
    engine.emit(const EnginePosition(Duration(seconds: 93)));
    await pumpEventQueue();
    expect(await c.setRate(1.6), isTrue);
    await c.session.pause();
    await c.selectQuality('16');
    expect(c.rate, 1.6);
    expect(engine.rates.last, 1.6);
    expect(c.session.state.status, PlaybackStatus.paused);
    expect(c.session.state.volume, 0.4);
    expect(engine.opens.last.start, const Duration(seconds: 93));
    await c.open('BV1234567890:200');
    expect(c.video!.part.cid, 200);
    expect(engine.opens.last.start, Duration.zero);
    expect(await progress.position('BV1234567890:100'), const Duration(seconds: 93));
    expect(stored, isNot(contains('https')));
    expect(stored, isNot(contains('Cookie')));
    expect(await c.setRate(8), isFalse);
    expect(await c.setRate(1.33), isFalse);
    expect(c.rate, 1.6);
    c.dispose();
    await c.retirement;
    expect(engine.disposed, isTrue);
  });

  test(
    'a seek without native acknowledgement leaves a retryable error instead of a permanent pending position',
    () async {
      final engine = FakeEngine();
      final c = BilibiliArchiveController(
        source: FakeBiliReplay(),
        session: fakeSession(engine),
        progress: HuyaArchiveProgress(read: () async => '{}', write: (_) async {}),
      );
      await c.open(archive.bvid);
      await c.seek(const Duration(seconds: 900));
      expect(c.position, const Duration(seconds: 900));
      await Future<void>.delayed(const Duration(seconds: 11));
      expect(c.error, isA<TimeoutException>());
      expect(c.position, isNot(const Duration(seconds: 900)));
      c.dispose();
      await c.retirement;
    },
  );

  test('a disposed Bilibili resolution cannot open a late native decoder', () async {
    final source = FakeBiliReplay()..pending = Completer();
    final engine = FakeEngine();
    final c = BilibiliArchiveController(
      source: source,
      session: fakeSession(engine),
      progress: HuyaArchiveProgress(read: () async => '{}', write: (_) async {}),
    );
    final opening = c.open(archive.bvid);
    await pumpEventQueue();
    c.dispose();
    source.pending!.complete(archive);
    await opening;
    await c.retirement;
    expect(engine.opens, isEmpty);
  });
}
