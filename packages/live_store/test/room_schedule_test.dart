import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('a due daily room is claimed once across concurrent callers and database reopen', () async {
    final dir = Directory.systemTemp.createTempSync('purelive_room_schedule');
    addTearDown(() => dir.deleteSync(recursive: true));
    final first = await LiveStore.open(dir, cipher: const FakeCipher());
    final room = LiveRoom(platform: SiteIds.bilibili, roomId: '123', httpHeaders: const {'cookie': 'synthetic'});
    final today = DateTime.utc(2026, 11, 8, 8);
    try {
      final tasks = first.roomSchedules;
      expect(await tasks.put(RoomOpenSchedule.daily(id: 'daily', room: room, minute: 480)), isTrue);
      expect(await tasks.claimDue(today.subtract(const Duration(seconds: 1))), isNull);
      final hits = await Future.wait([tasks.claimDue(today), tasks.claimDue(today)]);
      expect(hits.whereType<RoomOpenSchedule>().single.room.identityKey, 'bilibili:123');
      final stored = await first.meta.get('rooms.open-schedules.v1');
      expect(stored, isNotNull);
      expect(stored, isNot(contains('synthetic')));
    } finally {
      await first.close();
    }
    final second = await LiveStore.open(dir, cipher: const FakeCipher());
    try {
      expect(await second.roomSchedules.claimDue(today.add(const Duration(seconds: 1))), isNull);
      expect((await second.roomSchedules.claimDue(DateTime.utc(2026, 11, 9, 8)))?.id, 'daily');
    } finally {
      await second.close();
    }
  });

  test('a released claim can be retried but does not recreate an appointment removed during navigation', () async {
    final store = await LiveStore.memory(cipher: const FakeCipher());
    addTearDown(store.close);
    final tasks = store.roomSchedules;
    final now = DateTime.utc(2026, 11, 8, 9);
    final room = LiveRoom(platform: SiteIds.douyu, roomId: '9999');
    await tasks.put(RoomOpenSchedule.once(id: 'claimed', room: room, at: now));
    final first = (await tasks.claimDue(now))!;
    expect(await tasks.claimDue(now), isNull);
    await tasks.releaseClaim(first, now);
    final next = (await tasks.claimDue(now))!;
    expect(next.id, first.id);
    expect(await tasks.remove(next.id), isTrue);
    await tasks.releaseClaim(next, now);
    expect(await tasks.all(), isEmpty);
  });

  test('countdown deadlines survive timezone representation, but old missed tasks are not opened', () async {
    final store = await LiveStore.memory(cipher: const FakeCipher());
    addTearDown(store.close);
    final tasks = store.roomSchedules;
    final now = DateTime.utc(2026, 11, 8, 9);
    final room = LiveRoom(platform: SiteIds.douyu, roomId: '9999');
    await tasks.put(RoomOpenSchedule.once(id: 'missed', room: room, at: now.subtract(const Duration(minutes: 10))));
    await tasks.put(RoomOpenSchedule.once(id: 'countdown', room: room, at: now.toLocal()));
    expect((await tasks.claimDue(now))?.id, 'countdown');
    expect(await tasks.claimDue(now), isNull);
    expect(await tasks.remove('missed'), isTrue);
  });
}
