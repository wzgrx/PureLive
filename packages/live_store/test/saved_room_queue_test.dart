import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test(
    'the saved queue persists order and identity across database reopen without storing playback credentials',
    () async {
      final dir = Directory.systemTemp.createTempSync('purelive_saved_queue');
      addTearDown(() => dir.deleteSync(recursive: true));
      final first = await LiveStore.open(dir, cipher: const FakeCipher());
      final one = LiveRoom(
        platform: SiteIds.bilibili,
        roomId: '224',
        nick: 'Example',
        httpHeaders: const {'cookie': 'synthetic'},
      );
      final two = LiveRoom(platform: SiteIds.douyu, roomId: '9999');
      try {
        expect(await first.savedRoomQueue.all(), isEmpty);
        expect(await first.savedRoomQueue.add(one), isTrue);
        expect(await first.savedRoomQueue.add(two), isTrue);
        expect(await first.savedRoomQueue.add(one), isFalse);
        expect(await first.savedRoomQueue.move(two, 0), isTrue);
        expect(
          await first.savedRoomQueue.add(LiveRoom(platform: SiteIds.douyu, roomId: 'https://example.test/a?key=demo')),
          isFalse,
        );
        final raw = jsonDecode((await first.meta.get('rooms.saved-queue.v1'))!);
        expect(raw, [
          {'platform': 'douyu', 'roomId': '9999', 'nick': ''},
          {'platform': 'bilibili', 'roomId': '224', 'nick': 'Example'},
        ]);
        expect(await first.follows.count(), 0);
      } finally {
        await first.close();
      }
      final second = await LiveStore.open(dir, cipher: const FakeCipher());
      try {
        expect((await second.savedRoomQueue.all()).map((room) => room.identityKey), ['douyu:9999', 'bilibili:224']);
        expect(await second.savedRoomQueue.remove(two), isTrue);
        expect(await second.savedRoomQueue.remove(two), isFalse);
        expect((await second.savedRoomQueue.all()).single.identityKey, 'bilibili:224');
      } finally {
        await second.close();
      }
    },
  );
}
