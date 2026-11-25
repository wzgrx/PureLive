import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/shared/rooms/foreground_room_scheduler.dart';

void main() {
  testWidgets('a modal arriving during claim releases the occurrence for the next free route', (tester) async {
    final now = DateTime(2026, 11, 8, 19);
    final task = RoomOpenSchedule.once(
      id: 'race',
      room: LiveRoom(platform: SiteIds.bilibili, roomId: '21'),
      at: now,
    );
    final tasks = StreamController<List<RoomOpenSchedule>>.broadcast(sync: true);
    final firstClaim = Completer<RoomOpenSchedule?>.sync();
    final opened = Completer<void>();
    var allowed = true;
    var claims = 0;
    final releases = <(RoomOpenSchedule, DateTime)>[];
    final scheduler =
        ForegroundRoomScheduler(
            schedules: tasks.stream,
            claim: (_) => ++claims == 1 ? firstClaim.future : Future.value(task),
            releaseClaim: (value, at) async => releases.add((value, at)),
            canOpen: () => allowed,
            openRoom: (_) async => opened.complete(),
            now: () => now,
          )
          ..setForeground(value: true)
          ..start();
    tasks.add([task]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(claims, 1);
    allowed = false;
    firstClaim.complete(task);
    await tester.pump(const Duration(milliseconds: 20));
    expect(releases, [(task, now)]);
    expect(opened.isCompleted, isFalse);
    allowed = true;
    await tester.pump(const Duration(seconds: 1));
    expect(opened.isCompleted, isTrue);
    scheduler.dispose();
    final closed = tasks.close();
    await tester.pump();
    await closed;
  });

  testWidgets('a background or modal window never claims a task and open room pages never stack', (tester) async {
    final now = DateTime(2026, 11, 8, 19);
    final tasks = StreamController<List<RoomOpenSchedule>>.broadcast(sync: true);
    final task = RoomOpenSchedule.once(
      id: 'first',
      room: LiveRoom(platform: SiteIds.bilibili, roomId: '21'),
      at: now,
    );
    final closed = Completer<void>();
    var modal = true;
    var claims = 0;
    final opened = <String>[];
    final scheduler = ForegroundRoomScheduler(
      schedules: tasks.stream,
      claim: (_) async {
        claims++;
        return task;
      },
      releaseClaim: (_, _) async {},
      canOpen: () => !modal,
      openRoom: (room) async {
        opened.add(room.roomId);
        await closed.future;
      },
      now: () => now,
    )..start();
    tasks.add([task]);
    await tester.pump(const Duration(seconds: 5));
    expect(claims, 0);
    scheduler.setForeground(value: true);
    await tester.pump(const Duration(seconds: 5));
    expect(claims, 0);
    modal = false;
    await tester.pump(const Duration(seconds: 1));
    expect(opened, ['21']);
    await tester.pump(const Duration(seconds: 5));
    expect(claims, 1);
    scheduler.dispose();
    closed.complete();
    final done = tasks.close();
    await tester.pump();
    await done;
  });
}
