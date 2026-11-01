import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/shared/rooms/playback_lines.dart';
import 'package:pure_live/shared/rooms/playback_telemetry.dart';

import '../../features/live_play/live_play_support.dart';
import '../../support.dart';

const rawOne = LivePlayLine(
  'https://cdn-one.example.test/a.m3u8?token=synthetic-secret',
  lineId: 'raw|cdn-one.example.test|index',
  codec: 'hevc',
);
const rawTwo = LivePlayLine(
  'https://cdn-two.example.test/b.m3u8',
  lineId: 'raw|cdn-two.example.test|index',
  codec: 'avc',
);
const official = LivePlayLine('https://cdn.example.test/c.flv', codec: 'hevc');

PlaybackRequest request(List<LivePlayLine> lines) => PlaybackRequest(
  site: 'test',
  plan: PlaybackPlan(sources: [for (final line in lines) LineSource(line)]),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStrings);

  test('declared codecs are canonical; Raw transcode hints are never treated as original evidence', () {
    expect(playbackLineName(0, line: official), '线路1（H.265）');
    expect(playbackLineName(1, line: rawOne), '线路2（raw）');
    expect(playbackLineName(1, line: rawOne, detectedCodec: 'h264 (H.264 / AVC)'), '线路2（H.264, raw）');
    expect(playbackLineName(2), '线路3');
    expect(playbackCodecName('avc1.640028'), 'H.264');
    expect(playbackCodecName('HEVC (Main 10) / H.265'), 'H.265');
    expect(playbackCodecName('av01'), 'AV1');
    expect(playbackCodecName('vp09'), 'VP9');
    expect(playbackCodecName('private-token-or-unknown'), isNull);
  });

  test('CDN details expose hosts only, never credentials, paths, query strings or owned schemes', () {
    expect(playbackLineOrigin(rawOne), 'cdn-one.example.test');
    expect(
      playbackLineOrigin(const LivePlayLine('https://user:pass@cdn.example.test/private?key=secret')),
      'cdn.example.test',
    );
    expect(playbackLineOrigin(const LivePlayLine('file:///private/image.png')), isEmpty);
    expect(playbackLineOrigin(null), isEmpty);
  });

  testWidgets('only the decoded current line gains codec evidence; standby Raw lines and indexes stay unchanged', (
    tester,
  ) async {
    final engine = _StatsEngine();
    final session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
    final lines = PlaybackLinePresentation.of(session);
    void update() {}
    lines.addListener(update);
    await session.open(request([rawOne, rawTwo, official]));
    expect(engine.reads, 0, reason: 'no statistics before the first decoded dimensions');
    expect(lines.labels, ['线路1（raw）', '线路2（raw）', '线路3（H.265）']);
    engine.inner.emit(const EngineVideoSize(1920, 1080));
    await tester.pump();
    expect(lines.labels, ['线路1（H.264, raw）', '线路2（raw）', '线路3（H.265）']);
    expect(lines.origins, ['cdn-one.example.test', 'cdn-two.example.test', 'cdn.example.test']);
    expect(session.plan!.sources.cast<LineSource>().map((s) => s.line.url), [rawOne.url, rawTwo.url, official.url]);
    lines.removeListener(update);
    await session.dispose();
  });

  testWidgets('native evidence updates the current control without another playback-state event', (tester) async {
    final pending = Completer<PlaybackStats>();
    final engine = _StatsEngine()..read = () => pending.future;
    final session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
    var closed = false;
    Future<void> close() async {
      if (closed) return;
      closed = true;
      if (!pending.isCompleted) pending.complete(const PlaybackStats());
      await tester.pumpWidget(const SizedBox.shrink());
      await session.dispose();
    }

    addTearDown(close);
    await session.open(request([rawOne, official]));
    engine.inner.emit(const EngineVideoSize(1920, 1080));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackLineBuilder(
            session: session,
            builder: (_, state, lines) => Text(lines.name(state.lineIndex), key: const ValueKey('current-line')),
          ),
        ),
      ),
    );
    expect(find.text('线路1（raw）'), findsOneWidget);
    pending.complete(const PlaybackStats(videoFormat: 'hevc'));
    await tester.pump();
    expect(find.text('线路1（H.265, raw）'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close();
  });

  testWidgets('a late native codec from a previous source cannot label the next source', (tester) async {
    final pending = Completer<PlaybackStats>();
    final engine = _StatsEngine()..read = () => pending.future;
    final session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
    final lines = PlaybackLinePresentation.of(session);
    void update() {}
    lines.addListener(update);
    await session.open(request([rawOne]));
    engine.inner.emit(const EngineVideoSize(1920, 1080));
    await tester.pump();
    expect(engine.reads, 1);
    await session.open(request([rawTwo]));
    engine.inner.emit(const EngineVideoSize(1280, 720));
    engine.read = () async => const PlaybackStats(videoFormat: 'hevc');
    pending.complete(const PlaybackStats(videoFormat: 'h264'));
    await tester.pump();
    expect(lines.labels.single, '线路1（raw）');
    await tester.pump(const Duration(seconds: 1));
    expect(lines.labels.single, '线路1（H.265, raw）');
    lines.removeListener(update);
    await session.dispose();
  });

  testWidgets('unavailable native statistics stop within three seconds even without value notifications', (
    tester,
  ) async {
    final engine = _StatsEngine()..read = () async => throw StateError('unavailable');
    final session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
    final lines = PlaybackLinePresentation.of(session);
    void update() {}
    lines.addListener(update);
    await session.open(request([rawOne]));
    engine.inner.emit(const EngineVideoSize(1920, 1080));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    final count = engine.reads;
    await tester.pump(const Duration(seconds: 5));
    expect(engine.reads, count);
    expect(count, lessThanOrEqualTo(3));
    expect(lines.labels.single, '线路1（raw）');
    lines.removeListener(update);
    await session.dispose();
  });

  testWidgets('reopening the identical plan invalidates an earlier in-flight shared HUD sample', (tester) async {
    final pending = Completer<PlaybackStats>();
    final engine = _StatsEngine()..read = () => pending.future;
    final session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
    final sameRequest = request([rawOne]);
    await session.open(sameRequest);
    engine.inner.emit(const EngineVideoSize(1920, 1080));
    final previousInput = session.input;
    final telemetry = PlaybackTelemetry(
      read: engine.readStats,
      identity: () => (session.engine, session.state.source, session.state.line, session.input),
    );
    void hud() {}
    void update() {}
    telemetry.addListener(hud);
    final lines = PlaybackLinePresentation.of(session, telemetry: telemetry)..addListener(update);
    await tester.pump();
    await session.open(sameRequest);
    engine.inner.emit(const EngineVideoSize(1920, 1080));
    expect(session.input, isNot(same(previousInput)));
    engine.read = () async => const PlaybackStats(videoFormat: 'hevc');
    pending.complete(const PlaybackStats(videoFormat: 'h264'));
    await tester.pump();
    expect(lines.labels.single, '线路1（raw）');
    await tester.pump(const Duration(seconds: 1));
    expect(lines.labels.single, '线路1（H.265, raw）');
    lines.removeListener(update);
    telemetry.removeListener(hud);
    await session.dispose();
    telemetry.dispose();
  });

  testWidgets('line annotations reuse the HUD sampler instead of duplicating native reads', (tester) async {
    final engine = _StatsEngine();
    final session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
    await session.open(request([rawOne]));
    engine.inner.emit(const EngineVideoSize(1920, 1080));
    final telemetry = PlaybackTelemetry(
      read: engine.readStats,
      identity: () => (session.engine, session.state.source, session.state.line, session.input),
    );
    void hud() {}
    void update() {}
    telemetry.addListener(hud);
    final lines = PlaybackLinePresentation.of(session, telemetry: telemetry)..addListener(update);
    await tester.pump();
    expect(engine.reads, 1);
    expect(lines.labels.single, '线路1（H.264, raw）');
    await tester.pump(const Duration(seconds: 1));
    expect(engine.reads, 2);
    lines.removeListener(update);
    telemetry.removeListener(hud);
    await session.dispose();
    telemetry.dispose();
  });

  testWidgets('long annotated choices fit a narrow large-text row and keep selection indexes', (tester) async {
    var selected = -1;
    final labels = [playbackLineName(0, line: official), playbackLineName(1, line: rawOne, detectedCodec: 'h264')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: SizedBox(
                width: 280,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: StreamMenuButton(
                        label: '最高画质 1080P',
                        entries: const ['最高画质 1080P'],
                        current: 0,
                        onSelected: (_) {},
                        tooltip: 'quality',
                      ),
                    ),
                    Flexible(
                      child: StreamMenuButton(
                        key: const ValueKey('line'),
                        label: labels.first,
                        entries: labels,
                        descriptions: const ['cdn.example.test', 'cdn-one.example.test'],
                        current: 0,
                        onSelected: (i) => selected = i,
                        tooltip: 'line',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('line')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('stream-menu-item-1')));
    await tester.tap(find.byKey(const ValueKey('stream-menu-item-1')));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _StatsEngine extends Fake implements PlayerEngine, PlaybackStatsSource {
  final inner = FakeEngine();
  int reads = 0;
  Future<PlaybackStats> Function() read = () async => const PlaybackStats(videoFormat: 'h264');
  @override
  Future<PlaybackStats> readStats() {
    reads++;
    return read();
  }

  @override
  Stream<EngineEvent> get events => inner.events;
  @override
  bool get reportsFrames => false;
  @override
  Future<void> open(EngineMedia media) => inner.open(media);
  @override
  Future<void> play() => inner.play();
  @override
  Future<void> pause() => inner.pause();
  @override
  Future<void> stop() => inner.stop();
  @override
  Future<void> seek(Duration position) => inner.seek(position);
  @override
  Future<void> setVolume(double volume) => inner.setVolume(volume);
  @override
  Future<void> setAudioOnly({required bool enabled}) => inner.setAudioOnly(enabled: enabled);
  @override
  Future<void> dispose() => inner.dispose();
}
