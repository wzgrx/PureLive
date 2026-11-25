import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/shared/rooms/timed_room_rotation.dart';

void main() {
  final rooms = [
    for (final id in ['1', '2', '3']) LiveRoom(platform: SiteIds.bilibili, roomId: id),
  ];
  const interval = Duration(seconds: 10);

  testWidgets('pause cancels the countdown and no second switch is dispatched while replacement is pending', (
    tester,
  ) async {
    final switched = <String>[];
    final rotation = TimedRoomRotation(
      switchTo: (room) {
        switched.add(room.roomId);
        return true;
      },
    )..start(rooms, interval: interval, order: RoomRotationOrder.ordered);
    addTearDown(rotation.dispose);
    rotation.observe(rooms.first, eligible: true);
    await tester.pump(const Duration(seconds: 6));
    rotation.observe(rooms.first, eligible: false);
    await tester.pump(interval);
    expect(switched, isEmpty);
    rotation.observe(rooms.first, eligible: true);
    await tester.pump(const Duration(seconds: 5));
    // Progress snapshots must not postpone the deadline indefinitely.
    rotation.observe(rooms.first, eligible: true);
    await tester.pump(const Duration(seconds: 5));
    expect(switched, ['2']);
    await tester.pump(interval);
    expect(switched, ['2']);
    rotation.observe(rooms[1], eligible: true);
    await tester.pump(interval);
    expect(switched, ['2', '3']);
    rotation.stop();
    await tester.pump(interval);
    expect(switched, ['2', '3']);
  });

  testWidgets('shuffled rotation visits distinct rooms before starting another cycle', (tester) async {
    final switched = <LiveRoom>[];
    final rotation = TimedRoomRotation(
      random: Random(42),
      switchTo: (room) {
        switched.add(room);
        return true;
      },
    )..start(rooms, interval: interval, order: RoomRotationOrder.shuffled);
    addTearDown(rotation.dispose);
    rotation.observe(rooms.first, eligible: true);
    for (var index = 0; index < 3; index++) {
      await tester.pump(interval);
      rotation.observe(switched.last, eligible: true);
    }
    expect(switched.take(2).map((room) => room.roomId), unorderedEquals(['2', '3']));
    expect(switched.last.hasSameIdentity(switched[1]), isFalse);
    rotation.stop();
  });
}
