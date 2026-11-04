import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/shared/rooms/archive/huya_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive/soop_archive_controller.dart';

import '../live_play/live_play_support.dart';

const metadata = SoopArchiveVideo(id: '123', title: 'Recording', authorId: 'creator');

class Source implements SoopArchiveSource {
  int requests = 0;
  Completer<List<SoopArchivePart>>? pending;
  bool fail = false;
  @override
  Future<SoopArchiveList> list(String author, {int page = 1, CancelToken? cancel}) async =>
      (videos: [metadata], hasMore: false);
  @override
  Future<List<SoopArchivePart>> detail(String id, {CancelToken? cancel}) async {
    requests++;
    if (fail) throw const StreamUnavailable('soop', 'restricted');
    if (pending != null) return await pending!.future;
    return [
      for (var n = 1; n <= 2; n++)
        SoopArchivePart(
          recording: metadata,
          order: n,
          duration: const Duration(minutes: 10),
          qualities: [
            for (final q in ['original', 'hd4k'])
              SoopArchiveQuality(id: q, label: q, url: 'https://vod.sooplive.com/$n-$q.m3u8?revision=$requests'),
          ],
        ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('resume selects the stored part; quality retains position, pause, volume and rate on one session', () async {
    String? saved;
    final progress = HuyaArchiveProgress(
      read: () async => saved,
      write: (s) async => saved = s,
      idPattern: r'^[0-9]+:[0-9]+$',
    );
    await progress.save('123:2', const Duration(seconds: 80));
    final source = Source();
    final engine = FakeEngine();
    final c = SoopArchiveController(
      source: source,
      session: fakeSession(engine),
      recording: metadata,
      progress: progress,
      initialVolume: .4,
    );
    await c.open('123');
    expect(c.error, isNull);
    expect(c.video!.id, '123:2');
    expect(engine.opens.single.start, const Duration(seconds: 80));
    engine.emit(const EnginePosition(Duration(seconds: 80)));
    await pumpEventQueue();
    await c.setRate(1.75);
    await c.session.setVolume(.27);
    await c.session.pause();
    await c.selectQuality('hd4k');
    expect(engine.opens.last.start, const Duration(seconds: 80));
    expect(engine.opens.last.uri.toString(), contains('revision=2'));
    expect(c.session.state.status, PlaybackStatus.paused);
    expect(c.session.state.volume, .27);
    expect(engine.rates.last, 1.75);
    engine.emit(const EnginePosition(Duration(seconds: 85)));
    await pumpEventQueue();
    await c.record();
    expect(saved, isNot(contains('http')));
    expect(c.supportsDanmaku, isFalse);
    await c.open('123:1');
    expect(c.video!.id, '123:1');
    expect(c.segments, hasLength(2));
    c.dispose();
    await c.retirement;
    expect(engine.disposed, isTrue);
  });
  testWidgets('an unacknowledged seek cannot overwrite watched progress; timeout exposes an error', (tester) async {
    String? saved;
    final progress = HuyaArchiveProgress(
      read: () async => saved,
      write: (s) async => saved = s,
      idPattern: r'^[0-9]+:[0-9]+$',
    );
    final engine = FakeEngine();
    final c = SoopArchiveController(
      source: Source(),
      session: fakeSession(engine),
      recording: metadata,
      progress: progress,
    );
    await c.open('123:1');
    engine.emit(const EnginePosition(Duration(seconds: 50)));
    await tester.pump();
    await c.record();
    await c.seek(const Duration(seconds: 500));
    await c.record();
    expect(await progress.position('123:1'), const Duration(seconds: 50));
    await tester.pump(const Duration(seconds: 10));
    expect(c.error, isA<TimeoutException>());
    c.dispose();
    await c.retirement;
  });
  test('disposing a room-owned controller drops late metadata and never releases another owner decoder', () async {
    final source = Source()..pending = Completer();
    final engine = FakeEngine();
    final session = fakeSession(engine);
    final c = SoopArchiveController(
      source: source,
      session: session,
      recording: metadata,
      progress: HuyaArchiveProgress(read: () async => null, write: (_) async {}),
      ownsSession: false,
    );
    final opening = c.open('123');
    await pumpEventQueue();
    c.dispose();
    source.pending!.complete([]);
    await opening;
    await c.retirement;
    expect(engine.opens, isEmpty);
    expect(engine.disposed, isFalse);
    await session.dispose();
  });
}
