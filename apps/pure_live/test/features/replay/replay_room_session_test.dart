import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/reconnect_watch.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/logic/room_runtime.dart';
import 'package:pure_live/shared/rooms/archive/archive_recording.dart';
import 'package:pure_live/shared/rooms/archive/huya_archive_controller.dart';

import '../../support.dart';
import '../huya_replay/huya_archive_support.dart';
import '../live_play/live_play_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LiveStore store;
  late FakeEngine engine;
  late PlaybackSession session;
  late FakeSite site;
  late FakeDanmaku danmaku;
  late FakeHuyaArchive source;
  late LiveRoomController controller;
  String? saved;
  ArchiveSelection choice() => ArchiveSelection(
    recording: const ArchiveRecording(
      firstArchive,
      title: 'Replay',
      cover: '',
      date: null,
      duration: Duration(hours: 2),
    ),
    room: liveRoom(platform: SiteIds.huya),
  );
  setUpAll(loadStrings);
  setUp(() async {
    saved = null;
    store = await LiveStore.memory(cipher: FakeCipher());
    engine = FakeEngine();
    session = fakeSession(engine);
    site = FakeSite(liveRoom(platform: SiteIds.huya))..siteId = SiteIds.huya;
    danmaku = FakeDanmaku();
    source = FakeHuyaArchive();
    final progress = HuyaArchiveProgress(read: () async => saved, write: (v) async => saved = v);
    controller = LiveRoomController(
      room: site.room,
      site: site,
      session: session,
      danmaku: danmaku,
      danmakuSupported: true,
      store: store,
      archiveFactory: (r) => HuyaArchiveController(
        source: source,
        session: session,
        video: r.video as HuyaArchiveVideo,
        progress: progress,
        ownsSession: false,
      ),
    );
  });
  tearDown(() async {
    if (!controller.isDisposed) controller.dispose();
    await controller.archiveRetirement;
    await session.dispose();
    await store.close();
  });

  test('replay uses the live session and excludes late live messages and refresh', () async {
    await controller.start();
    final details = site.detailCalls;
    await controller.playArchive(choice());
    expect(controller.session, same(session));
    expect(engine.opens, hasLength(2));
    expect(engine.opens.first.onDemand, isFalse);
    expect(engine.opens.last.onDemand, isTrue);
    danmaku.chat('late live message');
    await pumpEventQueue();
    expect(controller.chat.lines.any((l) => l.text.contains('late live message')), isFalse);
    await controller.refreshDetail();
    expect(site.detailCalls, details);
    expect(engine.disposed, isFalse);
  });

  test('rate and pause survive quality selection, and returning live restores normal speed', () async {
    await controller.start();
    await controller.playArchive(choice());
    expect(await controller.archive!.setRate(2), isTrue);
    engine.emit(const EnginePosition(Duration(seconds: 42)));
    await pumpEventQueue();
    await session.pause();
    await controller.selectQuality(1);
    expect(session.state.status, PlaybackStatus.paused);
    expect(engine.rates.last, 2);
    await controller.leaveArchive();
    expect(controller.isArchive, isFalse);
    expect(engine.rates.last, 1);
    expect(engine.opens.last.onDemand, isFalse);
    expect(engine.disposed, isFalse);
  });

  test('disposing during late archive resolution never opens its decoder', () async {
    await controller.start();
    final pending = source.pendingQualities = Completer();
    final enter = controller.playArchive(choice());
    await pumpEventQueue();
    controller.dispose();
    await session.dispose();
    pending.complete(renditions(1));
    await enter;
    await controller.archiveRetirement;
    expect(engine.opens, hasLength(1));
  });

  test('an unverified other creator never inherits the invoking room identity', () async {
    await controller.start();
    const other = HuyaArchiveVideo(
      id: '100000003',
      title: 'Other replay',
      authorId: '456',
      authorName: 'Other creator',
    );
    await controller.playArchive(
      const ArchiveSelection(
        recording: ArchiveRecording(other, title: 'Other replay', cover: '', date: null, duration: Duration.zero),
      ),
    );
    expect(controller.room.nick, 'Other creator');
    expect(controller.room.roomId, 'archive-100000003');
    expect(controller.room.effectiveLiveStatus, LiveStatus.replay);
    expect(controller.canReturnToLive, isTrue);
    await controller.leaveArchive();
    expect(controller.room.roomId, site.room.roomId);
    expect(controller.room.nick, site.room.nick);
  });

  test('runtime disposal callers wait for the same delayed native retirement', () async {
    await controller.start();
    await controller.playArchive(choice());
    final native = Completer<void>();
    engine.onDispose = () => native.future;
    final runtime = RoomRuntime(
      controller: controller,
      session: session,
      reconnect: ReconnectWatch(session.states),
      background: RoomBackgroundPolicy(controller: controller, settings: store.settings),
      orientation: RoomOrientationChoice(settings: store.settings, room: controller.room),
    );
    final first = runtime.dispose();
    final second = runtime.dispose();
    expect(second, same(first));
    var complete = false;
    unawaited(runtime.retirement.then((_) => complete = true));
    await pumpEventQueue();
    expect(complete, isFalse);
    native.complete();
    await first;
    await runtime.retirement;
    expect(complete, isTrue);
  });
}
