import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/dialogs/playback_info_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';

import '../../support.dart';
import 'live_play_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppServices services;
  late FakeEngine engine;
  late PlaybackSession session;

  setUpAll(() async {
    await loadStrings();
  });

  setUp(() async {
    services = await testServices();
    engine = FakeEngine();
    session = fakeSession(engine);
  });

  tearDown(() async {
    await session.dispose();
    await services.close();
  });

  LiveRoomController controllerFor() => LiveRoomController(
    room: liveRoom(),
    site: FakeSite(liveRoom()),
    session: session,
    danmaku: FakeDanmaku(),
    danmakuSupported: false,
    store: services.store,
    refreshInterval: Duration.zero,
  );

  Future<void> pumpPanel(
    WidgetTester tester,
    LiveRoomController controller,
    Future<PlaybackStats?> Function() reader,
  ) async {
    tester.view
      ..physicalSize = const Size(400, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: const LiveTheme().light,
        home: Scaffold(
          body: PlaybackInfoPanel(controller: controller, onClose: () {}, statsReader: reader),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  const stats = PlaybackStats(
    width: 2560,
    height: 1440,
    videoFormat: 'hevc',
    videoCodec: 'hevc (Main) / H.265',
    encoder: 'obs-output module (libobs version 32.2.1)',
    sampleRate: 48000,
    channels: 2,
    audioBitrate: 160000,
    audioCodec: 'aac (LC)',
    droppedFrames: 2,
    decodedFrames: 503,
    bufferSeconds: 6.4,
    downloadBytesPerSecond: 375000,
    mpvVersion: 'mpv 0.41.0',
    ffmpegVersion: '9.0.2',
  );

  testWidgets('the panel shows the nine rows and the player versions', (tester) async {
    final controller = controllerFor();
    addTearDown(controller.dispose);
    await pumpPanel(tester, controller, () async => stats);
    expect(find.byKey(const ValueKey('panel-playback-info')), findsOneWidget);
    for (final id in [
      'resolution',
      'frame-rate',
      'codec',
      'encoder',
      'audio',
      'frames',
      'buffer',
      'download',
      'host',
    ]) {
      expect(find.byKey(ValueKey('playback-info-$id')), findsOneWidget, reason: id);
    }
    expect(find.text('2560 × 1440'), findsOneWidget);
    expect(find.text('H.265'), findsOneWidget);
    expect(find.text('obs-output module (libobs version 32.2.1)'), findsOneWidget);
    expect(find.text('48 kHz · 立体声 · 160 kbps'), findsOneWidget);
    expect(find.text('2 / 503'), findsOneWidget);
    expect(find.text('6.40 s'), findsOneWidget);
    expect(find.text('3.0 Mbps'), findsOneWidget);
    expect(find.text('播放器内核 · mpv 0.41.0 · FFmpeg 9.0.2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('missing stats leave every value as “—”', (tester) async {
    final controller = controllerFor();
    addTearDown(controller.dispose);
    await pumpPanel(tester, controller, () async => null);
    expect(find.text('—'), findsNWidgets(9));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the panel polls once a second and updates the values', (tester) async {
    final controller = controllerFor();
    addTearDown(controller.dispose);
    var current = stats;
    var reads = 0;
    await pumpPanel(tester, controller, () async {
      reads++;
      return current;
    });
    expect(find.text('2560 × 1440'), findsOneWidget);
    expect(reads, 1);
    current = const PlaybackStats(width: 1920, height: 1080);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    expect(find.text('1920 × 1080'), findsOneWidget);
    expect(reads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a stalled stream clears the previous positive download speed', (tester) async {
    final controller = controllerFor();
    addTearDown(controller.dispose);
    var current = stats;
    await pumpPanel(tester, controller, () async => current);
    expect(find.text('3.0 Mbps'), findsOneWidget);
    for (final missing in [false, true]) {
      current = missing ? const PlaybackStats() : const PlaybackStats(downloadBytesPerSecond: 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('3.0 Mbps'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('closing the panel stops the polling', (tester) async {
    final controller = controllerFor();
    addTearDown(controller.dispose);
    var reads = 0;
    await pumpPanel(tester, controller, () async {
      reads++;
      return stats;
    });
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(reads, 1);
  });
}
