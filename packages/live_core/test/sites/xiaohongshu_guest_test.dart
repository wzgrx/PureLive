import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

String _body(Object data) => jsonEncode({'code': 0, 'success': true, 'data': data});
Map<String, Object?> _row(String id, String cursor, {int? online = 7, int? total = 90}) => {
  'cursor_score': cursor,
  'type': 'live',
  'model_type': 'live_v2',
  'live': {
    't_room_info': {
      'room_id': 570000000000000000,
      'room_id_str': id,
      'name': 'Synthetic room',
      'cover': 'https://example.invalid/cover.webp',
      'member_count': online,
      'uv': total,
      'hot_value': 90000,
    },
    't_live_host_info': {
      'user_id': 'synthetic-host',
      'nickname': 'Test host',
      'avatar': 'https://example.invalid/avatar.jpg',
    },
  },
};

final class _Guest implements XiaohongshuGuest {
  final calls = <({String category, String cursor, CancelToken? cancel})>[];
  Completer<String>? pending;

  @override
  Future<String> categories({CancelToken? cancel}) async => _body({
    'categories': [
      {'id': 0, 'desc': '全部'},
      {'id': 1, 'desc': '游戏'},
    ],
  });

  @override
  Future<String> directory({required String category, required String cursor, CancelToken? cancel}) async {
    calls.add((category: category, cursor: cursor, cancel: cancel));
    if (pending != null) return await pending!.future;
    return _body({
      'feeds': cursor == '0' ? [_row('570000000000000001', '4.5')] : [_row('570000000000000002', '4.5')],
    });
  }

  @override
  Future<XiaohongshuPushIdentity> pushIdentity(String roomId, {bool refresh = false, CancelToken? cancel}) =>
      throw UnimplementedError();
}

final class _UnusedHttp implements LiveHttp {
  @override
  Future<LiveResponse> send(LiveRequest request) => throw StateError('Directory must use its visitor transport');
  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();
  @override
  void close() {}
}

void main() {
  test('category ids and names come from the response, with safe identity', () {
    final categories = XiaohongshuDirectory.categories(
      _body({
        'categories': [
          {'id': 0, 'desc': '全部'},
          {'id': '8', 'desc': 'New category'},
          {'id': 8, 'desc': 'Duplicate'},
          {'id': '../bad', 'desc': 'Bad'},
          null,
        ],
      }),
    );
    expect(categories.single.children.map((c) => c.areaId), ['0', '8']);
    expect(categories.single.children.last.platform, 'xiaohongshu');
    expect(categories.single.children.last.areaName, 'New category');
  });

  test('exact string broadcast id wins; no tokens or streams enter the card', () {
    final row = _row('570000000000000017', '9.75');
    final live = row['live']! as Map<String, Object?>;
    (live['t_room_info']! as Map<String, Object?>)['xsec_token'] = 'synthetic-token-not-for-storage';
    final result = XiaohongshuDirectory.page(
      _body({
        'feeds': [row],
      }),
      page: 1,
      cursor: '0',
    );
    final room = result.rooms.single;
    expect(room.roomId, '570000000000000017');
    expect(room.userId, 'synthetic-host');
    expect(room.onlineViewers, '7');
    expect(room.totalViewers, '90');
    expect(room.popularity, isEmpty);
    expect(room.link, 'https://www.xiaohongshu.com/livestream/570000000000000017');
    expect(jsonEncode(room.toJson()), isNot(contains('synthetic-token')));
    expect(room.data, isNull);
    expect(result.nextCursor, '9.75');
    expect(result.hasMore, isTrue); // A short page still has a real cursor.
  });

  test('inclusive tail cursor terminates; invalid cards do not stall paging', () {
    final result = XiaohongshuDirectory.page(
      _body({
        'feeds': [_row('bad', '2.25')],
      }),
      page: 1,
      cursor: '0',
    );
    expect(result.rooms, isEmpty);
    expect(result.nextCursor, '2.25');
    final end = XiaohongshuDirectory.page(
      _body({
        'feeds': [_row('570000000000000001', '2.25')],
      }),
      page: 2,
      cursor: '2.25',
    );
    expect(end.hasMore, isFalse);
    expect(end.nextCursor, isNull);
    expect(XiaohongshuDirectory.page(_body({'feeds': <Object?>[]}), page: 1, cursor: '0').hasMore, isFalse);
  });

  test('missing audience values stay unknown; zero is explicit; heat is not online', () {
    final rooms = XiaohongshuDirectory.page(
      _body({
        'feeds': [
          _row('570000000000000001', '3', online: null, total: null),
          _row('570000000000000002', '2', online: 0, total: 0),
        ],
      }),
      page: 1,
      cursor: '0',
    ).rooms;
    expect(rooms.first.onlineViewers, isEmpty);
    expect(rooms.first.watching, isEmpty);
    expect(rooms.last.onlineViewers, '0');
    expect(rooms.last.totalViewers, '0');
  });

  test('refusals, missing fields, non-JSON and huge payloads are errors, not empty', () {
    for (final body in [
      '<html>captcha</html>',
      '{}',
      '{"code":-1,"success":false}',
      _body({}),
      _body({'feeds': <String, Object?>{}}),
      'x' * (2 * 1024 * 1024 + 1),
    ]) {
      expect(() => XiaohongshuDirectory.page(body, page: 1, cursor: '0'), throwsA(isA<ApiChanged>()));
    }
  });

  test('independent category cursors and refresh never share page state', () async {
    final guest = _Guest();
    final site = XiaohongshuSite(_UnusedHttp(), guest: guest);
    final categories = await site.getCategories(1, 30);
    final game = categories.single.children.last;
    final first = await site.getDirectoryPageAtCursor(page: 1, category: game);
    await site.getDirectoryPageAtCursor(page: 1);
    await site.getDirectoryPageAtCursor(page: 2, category: game, cursor: first.nextCursor);
    await site.getDirectoryPageAtCursor(page: 1, category: game);
    expect(guest.calls.map((c) => (c.category, c.cursor)), [('1', '0'), ('0', '0'), ('1', '4.5'), ('1', '0')]);
    expect(site.directoryNoticeKey, 'xiaohongshu_guest_directory_scope');
    await expectLater(site.getDirectoryPageAtCursor(page: 2), throwsArgumentError);
    await expectLater(site.getDirectoryPageAtCursor(page: 1, cursor: 'bad'), throwsArgumentError);
    await expectLater(
      site.getDirectoryPageAtCursor(
        page: 1,
        category: const LiveArea(platform: 'huya', areaId: '1'),
      ),
      throwsArgumentError,
    );
  });

  test('compatibility paging replays cursors and stops at the inclusive tail', () async {
    final guest = _Guest();
    final site = XiaohongshuSite(_UnusedHttp(), guest: guest);
    final result = await site.getDirectoryPage(page: 3);
    expect(result.rooms, isEmpty);
    expect(result.hasMore, isFalse);
    expect(guest.calls.map((c) => c.cursor), ['0', '4.5']);
    expect(guest.calls.every((c) => c.cancel!.isCancelled), isTrue);
  });

  test('cancellation suppresses an in-flight response and avoids pre-cancel requests', () async {
    final guest = _Guest()..pending = Completer<String>();
    final site = XiaohongshuSite(_UnusedHttp(), guest: guest);
    final cancel = CancelToken();
    final future = site.getDirectoryPageAtCursor(page: 1, cancel: cancel);
    cancel.cancel();
    final expected = expectLater(
      future,
      throwsA(isA<TransportFailure>().having((e) => e.reason, 'reason', TransportReason.cancelled)),
    );
    guest.pending!.complete(_body({'feeds': <Object?>[]}));
    await expected;
    await expectLater(site.getDirectoryPageAtCursor(page: 1, cancel: cancel), throwsA(isA<TransportFailure>()));
    expect(guest.calls.length, 1);
  });
}
