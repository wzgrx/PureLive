import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';

import 'support/fake_engine.dart';

PlaybackRequest _live(String room) => PlaybackRequest(
  site: SiteIds.bilibili,
  plan: PlaybackPlan(sources: [LineSource(LivePlayLine('https://example.test/$room.m3u8'))]),
);

void main() {
  test('live seek uses the confirmed containing interval, not gaps or the VOD API', () async {
    final engine = FakeEngine()
      ..liveRanges = () async => const [
        LiveRewindRange(Duration(seconds: 7), Duration(seconds: 15)),
        LiveRewindRange(Duration(seconds: 18), Duration(seconds: 22)),
      ];
    final session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
    addTearDown(session.dispose);
    await session.open(_live('one'));
    engine.emit(const EnginePosition(Duration(seconds: 12)));
    expect((await session.liveRewindWindow())?.position, const Duration(seconds: 12));
    await session.seek(const Duration(seconds: 8));
    expect(await session.seekLiveCache(const Duration(seconds: 17)), isFalse);
    expect(await session.seekLiveCache(const Duration(seconds: 19)), isFalse);
    expect(await session.seekLiveCache(const Duration(seconds: 8)), isTrue);
    expect(engine.calls.where((call) => call.startsWith('seek')), ['seek 8']);
  });

  test('a late cached range cannot seek a different open on the same engine', () async {
    final old = Completer<List<LiveRewindRange>>();
    final engine = FakeEngine()..liveRanges = () => old.future;
    final session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
    addTearDown(session.dispose);
    await session.open(_live('first'));
    engine.emit(const EnginePosition(Duration(seconds: 12)));
    final seek = session.seekLiveCache(const Duration(seconds: 8));
    await session.open(_live('second'));
    old.complete(const [LiveRewindRange(Duration(seconds: 6), Duration(seconds: 20))]);
    expect(await seek, isFalse);
    expect(engine.calls.where((call) => call.startsWith('seek')), isEmpty);
    expect(await session.liveRewindWindow(), isNull, reason: 'the new source has not reported position');
  });
}
