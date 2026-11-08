import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/shared/rooms/archive/huya_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive/part_archive_controller.dart';

import '../live_play/live_play_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an unavailable initial CDN gets one fresh replay variant at the same resume point', () async {
    var loads = 0;
    const record = ChzzkArchiveVideo(
      id: '123',
      title: 'Public replay',
      channelId: '0123456789abcdef0123456789abcdef',
      authorName: 'Example',
      cover: '',
      publishedAt: null,
      duration: Duration(hours: 3),
    );
    String? stored;
    final progress = HuyaArchiveProgress(
      read: () async => stored,
      write: (value) async => stored = value,
      idPattern: r'^[0-9]+:1$',
    );
    final engine = FakeEngine()
      ..onOpen = (media) async {
        if (media.uri.path == '/144.mp4') throw const StreamUnavailable(SiteIds.chzzk, 'Synthetic refused CDN');
      };
    final initial = engine.onOpen!;
    engine.onOpen = (media) async {
      await initial(media);
      engine
        ..emit(const EngineBuffering(buffering: false))
        ..emit(const EnginePlaying(playing: true));
    };
    final controller = PartArchiveController<ChzzkArchivePart, ChzzkArchiveQuality>(
      site: SiteIds.chzzk,
      recordingId: record.id,
      loadParts: (id, {cancel}) async {
        final revision = ++loads;
        return [
          ChzzkArchivePart(record, [
            for (final height in [144, 720, 1080])
              ChzzkArchiveQuality(
                'https://video.example.test/$height.mp4?revision=$revision',
                id: 'mp4-$height',
                label: '${height}p',
                format: StreamFormat.other,
              ),
          ]),
        ];
      },
      qualitiesOf: (part) => part.qualities,
      lineFor: (q) => LivePlayLine(q.url, format: q.format),
      session: fakeSession(engine),
      progress: progress,
      restoreOnQualityFailure: true,
    );
    await controller.open(record.id, start: const Duration(minutes: 5));
    expect(controller.error, isNull);
    expect(controller.qualityId, 'mp4-720');
    expect(loads, 2);
    expect(engine.opens.map((media) => media.uri.path), ['/144.mp4', '/720.mp4']);
    expect(engine.opens.last.uri.queryParameters['revision'], '2');
    expect(engine.opens.map((media) => media.start), everyElement(const Duration(minutes: 5)));
    controller.dispose();
    await controller.retirement;
  });

  test('muxed replay resumes, selects a refreshed variant, and stores no media URL', () async {
    var loads = 0;
    String? saved;
    const record = ChzzkArchiveVideo(
      id: '123',
      title: 'Public replay',
      channelId: '0123456789abcdef0123456789abcdef',
      authorName: 'Example',
      cover: '',
      publishedAt: null,
      duration: Duration(minutes: 40),
    );
    final progress = HuyaArchiveProgress(
      read: () async => saved,
      write: (value) async => saved = value,
      idPattern: r'^[0-9]+:1$',
    );
    await progress.save('123:1', const Duration(seconds: 80));
    final engine = FakeEngine();
    final controller = PartArchiveController<ChzzkArchivePart, ChzzkArchiveQuality>(
      site: SiteIds.chzzk,
      recordingId: record.id,
      loadParts: (id, {cancel}) async {
        expect(id, record.id);
        final version = ++loads;
        return [
          ChzzkArchivePart(record, [
            for (final height in [144, 720, 1080])
              ChzzkArchiveQuality(
                'https://sample.akamaized.net/replay-$height.mp4?revision=$version',
                id: 'mp4-$height',
                label: '${height}p',
                format: StreamFormat.other,
              ),
          ]),
        ];
      },
      qualitiesOf: (part) => part.qualities,
      lineFor: (quality) => LivePlayLine(quality.url, format: quality.format),
      session: fakeSession(engine),
      progress: progress,
      restoreOnQualityFailure: true,
    );
    await controller.open(record.id);
    expect(controller.error, isNull);
    expect(controller.qualityId, 'mp4-144');
    expect(engine.opens.single.start, const Duration(seconds: 80));
    engine.emit(const EnginePosition(Duration(seconds: 80)));
    await pumpEventQueue();
    await controller.setRate(1.75);
    await controller.session.setVolume(.4);
    await controller.session.pause();
    await controller.selectQuality('mp4-720');
    expect(controller.error, isNull);
    expect(controller.qualityId, 'mp4-720');
    expect(loads, 2);
    expect(engine.opens.last.uri.path, '/replay-720.mp4');
    expect(engine.opens.last.uri.queryParameters['revision'], '2');
    expect(engine.opens.last.start, const Duration(seconds: 80));
    expect(controller.session.state.status, PlaybackStatus.paused);
    expect(controller.session.state.volume, .4);
    expect(engine.rates.last, 1.75);
    // Ignore a position not yet acknowledging the resume offset.
    engine.emit(const EnginePosition(Duration(seconds: 85)));
    await pumpEventQueue();
    await controller.record();
    expect(await progress.position('123:1'), const Duration(seconds: 80));
    engine.emit(const EnginePosition(Duration(seconds: 80)));
    await pumpEventQueue();
    engine.emit(const EnginePosition(Duration(seconds: 85)));
    await pumpEventQueue();
    await controller.record();
    expect(await progress.position('123:1'), const Duration(seconds: 85));
    expect(saved, isNot(contains('http')));

    // A CDN can refuse a high quality after resolving its signed URL.
    // Restore the same preceding variant, seek and user controls once.
    engine.onOpen = (media) async {
      if (media.uri.path.endsWith('-1080.mp4')) {
        throw const StreamUnavailable(SiteIds.chzzk, 'Synthetic unavailable variant');
      }
      engine
        ..emit(const EngineBuffering(buffering: false))
        ..emit(const EnginePlaying(playing: true));
    };
    await controller.selectQuality('mp4-1080');
    expect(engine.opens.map((media) => media.uri.path), [
      '/replay-144.mp4',
      '/replay-720.mp4',
      '/replay-1080.mp4',
      '/replay-720.mp4',
    ]);
    expect(engine.opens.last.uri.queryParameters['revision'], '4');
    expect(engine.opens.last.start, const Duration(seconds: 85));
    expect(controller.qualityId, 'mp4-720');
    expect(controller.error, isNull);
    expect(controller.session.state.status, PlaybackStatus.paused);
    expect(controller.session.state.volume, .4);
    expect(engine.rates.last, 1.75);
    controller.dispose();
    await controller.retirement;
    expect(engine.disposed, isTrue);
  });
}
