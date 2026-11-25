import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/shared/rooms/broadcast_information.dart';

import '../../support.dart';
import '../multiview/multiview_support.dart';
import 'live_play_support.dart';

void main() {
  setUpAll(loadStrings);
  test('metadata updates stay out of chat, ignore old versions, and remove just the preview', () async {
    final store = await memoryStore();
    final room = liveRoom(platform: 'douyin');
    final site = FakeSite(room)..siteId = 'douyin';
    final danmaku = FakeDanmaku();
    final session = fakeSession(FakeEngine());
    final controller = LiveRoomController(
      room: room,
      site: site,
      session: session,
      danmaku: danmaku,
      danmakuSupported: true,
      store: store,
      refreshInterval: Duration.zero,
    );
    void update(LiveRoomInfoUpdate value) => danmaku.emit(
      DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.roomInfo,
          userName: '',
          message: '',
          color: LiveMessageColor.white,
          data: value,
        ),
      ),
    );
    try {
      await controller.start();
      const preview = LiveBroadcastPreview(id: '123', dateText: '每天', timeText: '16:00');
      update(
        const LiveRoomInfoUpdate(broadcastId: '1', section: LiveRoomInfoSection.preview, version: 10, preview: preview),
      );
      expect(controller.room.broadcastInfo?.preview?.text, '每天 16:00');
      update(
        const LiveRoomInfoUpdate(
          broadcastId: '1',
          section: LiveRoomInfoSection.dynamics,
          version: 1,
          dynamics: ['赛程更新'],
        ),
      );
      update(const LiveRoomInfoUpdate(broadcastId: '1', section: LiveRoomInfoSection.preview, version: 9));
      expect(controller.room.broadcastInfo?.preview, same(preview));
      update(const LiveRoomInfoUpdate(broadcastId: '1', section: LiveRoomInfoSection.preview, version: 11));
      expect(controller.room.broadcastInfo?.preview, isNull);
      expect(controller.room.broadcastInfo?.dynamics, ['赛程更新']);
      expect(controller.chat.lines.where((line) => line.message?.type == LiveMessageType.roomInfo), isEmpty);
    } finally {
      controller.dispose();
      await session.dispose();
      await store.close();
    }
  });

  testWidgets('platform schedule and dynamics have separate sections, unavailable is explicit', (tester) async {
    Future<void> show(LiveBroadcastInfo? value) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BroadcastInformation(information: value)),
      ),
    );
    await show(
      const LiveBroadcastInfo(
        preview: LiveBroadcastPreview(id: '1', dateText: '每天', timeText: '16:00'),
        dynamics: ['比赛时间调整'],
      ),
    );
    expect(find.text('直播预告'), findsOneWidget);
    expect(find.text('每天 16:00'), findsOneWidget);
    expect(find.text('直播动态'), findsOneWidget);
    expect(find.text('比赛时间调整'), findsOneWidget);
    await show(null);
    expect(find.byKey(const ValueKey('broadcast-unavailable')), findsOneWidget);
    expect(find.byKey(const ValueKey('broadcast-preview')), findsNothing);
  });
}
