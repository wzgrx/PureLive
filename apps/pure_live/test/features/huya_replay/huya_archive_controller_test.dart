import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/features/huya_replay/huya_archive_controller.dart';

import '../live_play/live_play_support.dart';
import 'huya_archive_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('official archive playback resumes, seeks, refreshes qualities and preserves pause/volume', () async {
    var stored = '{}';
    final progress = HuyaArchiveProgress(read: () async => stored, write: (value) async => stored = value);
    await progress.save(firstArchive.id, const Duration(seconds: 93));
    final engine = FakeEngine();
    final source = FakeHuyaArchive();
    final controller = HuyaArchiveController(
      source: source,
      session: fakeSession(engine),
      video: firstArchive,
      progress: progress,
      initialVolume: 0.4,
    );
    await controller.open(firstArchive.id);
    expect(controller.error, isNull);
    expect(engine.opens.single.start, const Duration(seconds: 93));
    expect(controller.session.state.onDemand, isTrue);
    expect(engine.opens.single.headers['referer'], 'https://www.huya.com/');
    expect(controller.supportsDanmaku, isFalse, reason: 'current live comments cannot appear over a past recording');
    engine.emit(const EnginePosition(Duration(seconds: 93)));
    await pumpEventQueue();
    await controller.seek(const Duration(seconds: 150));
    engine.emit(const EnginePosition(Duration(seconds: 94)));
    await pumpEventQueue();
    expect(controller.position, const Duration(seconds: 150));
    engine.emit(const EnginePosition(Duration(seconds: 150)));
    await pumpEventQueue();
    await controller.session.setVolume(0.27);
    await controller.session.pause();
    final selected = controller.qualities.last.id;
    await controller.selectQuality(selected);
    expect(engine.opens.last.start, const Duration(seconds: 150));
    expect(engine.opens.last.uri.toString(), contains('revision=2'));
    expect(controller.session.state.status, PlaybackStatus.paused);
    expect(controller.session.state.volume, 0.27);
    expect(controller.qualityId, selected);
    await controller.record();
    expect(await progress.position(firstArchive.id), const Duration(seconds: 150));
    expect(stored, isNot(contains('http')));
    expect(stored, isNot(contains('revision')));
    controller.dispose();
    await controller.retirement;
    expect(engine.disposed, isTrue);
  });

  test('disposed and replaced requests cannot open media or mutate an active session', () async {
    final source = FakeHuyaArchive()..pendingQualities = Completer();
    final engine = FakeEngine();
    final controller = HuyaArchiveController(
      source: source,
      session: fakeSession(engine),
      video: firstArchive,
      progress: HuyaArchiveProgress(read: () async => null, write: (_) async {}),
    );
    final first = controller.open(firstArchive.id);
    await pumpEventQueue();
    controller.dispose();
    source.pendingQualities!.complete(renditions(1));
    await first;
    await controller.retirement;
    expect(engine.opens, isEmpty);
    expect(controller.qualities, isEmpty);
  });

  test('unplayable or failed archives show an error without inventing a fallback live stream', () async {
    final source = FakeHuyaArchive()..failQualities = true;
    final engine = FakeEngine();
    final controller = HuyaArchiveController(
      source: source,
      session: fakeSession(engine),
      video: firstArchive,
      progress: HuyaArchiveProgress(read: () async => null, write: (_) async {}),
    );
    await controller.open(firstArchive.id);
    expect(controller.error, isA<StreamUnavailable>());
    expect(engine.opens, isEmpty);
    expect(controller.busy, isFalse);
    source.failQualities = false;
    await controller.open(firstArchive.id);
    expect(controller.error, isNull);
    expect(engine.opens, hasLength(1));
    await expectLater(controller.open(secondArchive.id), throwsA(isA<NotFound>()));
    controller.dispose();
    await controller.retirement;
  });

  test('progress is bounded, rejects malformed values and serializes concurrent writes', () async {
    var stored = jsonEncode({'invalid': 12, '1': -1, '2': 31536000001, '3': 1200});
    final progress = HuyaArchiveProgress(read: () async => stored, write: (value) async => stored = value);
    expect(await progress.position('3'), const Duration(milliseconds: 1200));
    expect(await progress.position('1'), Duration.zero);
    await Future.wait([for (var i = 1; i <= 205; i++) progress.save('$i', Duration(seconds: i))]);
    expect((jsonDecode(stored) as Map).length, 200);
    expect(await progress.position('205'), const Duration(seconds: 205));
    expect(await progress.position('1'), Duration.zero);
    final before = stored;
    await progress.save('../secret', const Duration(seconds: 1));
    await progress.save('123', const Duration(seconds: -1));
    expect(stored, before);
  });
}
