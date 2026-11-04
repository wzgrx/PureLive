import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _room = '570000000000000017';
const _identity = XiaohongshuPushIdentity(
  sid: 'synthetic-visitor-sid',
  uid: 'synthetic-visitor',
  deviceId: 'synthetic-device',
  fingerprint: 'synthetic-fingerprint',
  userAgent: 'Synthetic browser',
);

Map<String, Object?> _item(
  Map<String, Object?> custom, {
  String room = _room,
  String id = 'synthetic-message',
  Object? ts = 1793753000000,
  bool stringify = true,
}) => {
  'd': base64Encode(
    utf8.encode(
      jsonEncode({
        'roomId': room,
        'roomType': 'LIVE',
        'msgId': id,
        'ts': ts,
        'customData': stringify ? jsonEncode(custom) : custom,
      }),
    ),
  ),
};
Map<String, Object?> _chat({String nick = '测试昵称', String text = '真实文本🙂'}) => {
  'type': 'text',
  'profile': {'nickname': nick, 'user_id': 'synthetic-sender'},
  'desc': text,
};
String _push(List<Object?> items, {String biz = 'room'}) => jsonEncode({
  'v': 1,
  't': 4,
  'b': {
    'd': {'biz': biz, 'b': items},
  },
});
List<LiveMessage> _decode(String data) =>
    XiaohongshuDanmakuProtocol.messages(XiaohongshuDanmakuProtocol.envelope(data) ?? {}, _room);

final class _Guest implements XiaohongshuGuest {
  final requests = <({String room, bool refresh, CancelToken? cancel})>[];
  Completer<XiaohongshuPushIdentity>? pending;
  @override
  Future<XiaohongshuPushIdentity> pushIdentity(String roomId, {bool refresh = false, CancelToken? cancel}) async {
    requests.add((room: roomId, refresh: refresh, cancel: cancel));
    return pending == null ? _identity : await pending!.future;
  }

  @override
  Future<String> categories({CancelToken? cancel}) => throw UnimplementedError();
  @override
  Future<String> directory({required String category, required String cursor, CancelToken? cancel}) =>
      throw UnimplementedError();
}

final class _Channel implements SocketChannel {
  final incoming = StreamController<Object?>.broadcast(sync: true);
  final sent = <Map<String, Object?>>[];
  bool closed = false;
  @override
  Stream<Object?> get stream => incoming.stream;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  void add(Object data) => sent.add(Map<String, Object?>.from(jsonDecode(data as String) as Map));
  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
  }

  void ack({int code = 0}) => incoming.add(
    jsonEncode({
      'v': 1,
      't': 2,
      'm': sent.last['m'],
      'b': {
        'a': {'c': code, 'm': 'synthetic ack'},
      },
    }),
  );
}

final class _Connector {
  final channels = <_Channel>[];
  Future<SocketChannel> call(
    Uri endpoint, {
    required Map<String, String> headers,
    required Iterable<String>? protocols,
    required ProxyRoute route,
    required Duration connectTimeout,
  }) async {
    expect(endpoint, XiaohongshuDanmakuProtocol.endpoint);
    expect(headers.keys, isNot(contains('Cookie')));
    final channel = _Channel();
    channels.add(channel);
    return channel;
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.value();
  }
}

Future<void> _join(_Channel channel) async {
  for (var i = 0; i < 3; i++) {
    channel.ack();
    await _settle();
  }
}

int _operation(Map<String, Object?> frame) => ((frame['b']! as Map)['d'] as Map)['s'] as int;

void main() {
  group('bounded public room decoder', () {
    test('text with actual nickname, masked nickname, Unicode and exact ids', () {
      final messages = _decode(_push([_item(_chat()), _item(_chat(nick: '游****客'), id: 'second', stringify: false)]));
      expect(messages.map((m) => m.userName), ['测试昵称', '游****客']);
      expect(messages.first.message, '真实文本🙂');
      expect(messages.first.messageId, 'synthetic-message');
      expect(messages.first.userId, 'synthetic-sender');
      expect(messages.first.sourceRoomId, _room);
      expect(messages.first.sentAt, DateTime.fromMillisecondsSinceEpoch(1793753000000, isUtc: true));
    });
    test('one broken item cannot hide following messages; room and service are filtered', () {
      expect(
        _decode(
          _push([
            null,
            {'d': 'invalid base64!'},
            _item(_chat(), room: '570000000000000018'),
            _item(_chat()),
          ]),
        ).length,
        1,
      );
      expect(_decode(_push([_item(_chat())], biz: 'im')), isEmpty);
      expect(_decode('{"v":1,"t":0}'), isEmpty);
    });
    test('refresh separates online and cumulative counts; heat and praise are not online', () {
      final messages = _decode(
        _push([
          _item({
            'type': 'refresh',
            'room_data': {'member_count': 0, 'uv': '92', 'hot_value': 900000, 'praise_count': 8000},
          }),
        ]),
      );
      final online = messages[0].data! as LiveAudienceUpdate;
      final total = messages[1].data! as LiveAudienceUpdate;
      expect((online.kind, online.value), (LiveAudienceMetricKind.onlineViewers, 0));
      expect((total.kind, total.value), (LiveAudienceMetricKind.totalViewers, 92));
      expect(
        _decode(
          _push([
            _item({
              'type': 'refresh',
              'room_data': {'viewers': 10, 'display_count': 10, 'member_count': -1, 'uv': 'NaN'},
            }),
          ]),
        ),
        isEmpty,
      );
    });
    test('joins, likes and unknown notifications are never fabricated chat', () {
      for (final type in ['audience_join_v2', 'praise', 'follow_emcee', 'light', 'live_banner_resource']) {
        expect(
          _decode(
            _push([
              _item({..._chat(), 'type': type}),
            ]),
          ),
          isEmpty,
        );
      }
    });
    test('oversized and malformed inputs are bounded; invalid time does not lose text', () {
      expect(XiaohongshuDanmakuProtocol.envelope('x' * (1024 * 1024 + 1)), isNull);
      expect(XiaohongshuDanmakuProtocol.envelope('{'), isNull);
      expect(_decode(_push(List.filled(257, _item(_chat())))), isEmpty);
      expect(
        _decode(
          _push([
            _item(_chat(text: 'x' * 8193)),
            {'d': 'x' * (128 * 1024 + 1)},
          ]),
        ),
        isEmpty,
      );
      expect(_decode(_push([_item(_chat(), ts: 9007199254740991)])).single.sentAt, isNull);
    });
  });

  group('native connection lifecycle', () {
    test('auth, register and join need their own acknowledgements; text dedup and heartbeats', () async {
      final guest = _Guest();
      final connector = _Connector();
      final connection = XiaohongshuDanmakuConnection(guest: guest, connector: connector.call);
      final events = <DanmakuEvent>[];
      final sub = connection.events.listen(events.add);
      addTearDown(() async {
        await connection.close();
        await sub.cancel();
      });
      await connection.connect(const XiaohongshuDanmakuArgs(roomId: _room));
      final channel = connector.channels.single;
      expect(_operation(channel.sent.single), 0);
      channel.incoming.add(_push([_item(_chat())]));
      expect(events, isEmpty);
      channel.incoming.add('{"v":1,"t":2,"m":"wrong-id","b":{"a":{"c":0}}}');
      expect(channel.sent.length, 1);
      channel.ack();
      await _settle();
      expect(_operation(channel.sent.last), 1);
      expect(connection.isConnected, isFalse);
      channel.ack();
      await _settle();
      expect(_operation(channel.sent.last), 8);
      expect(connection.isConnected, isFalse);
      channel.ack();
      await _settle();
      expect(connection.isConnected, isTrue);
      expect(events.whereType<DanmakuReady>().length, 1);
      final push = _push([_item(_chat())]);
      channel.incoming.add(push);
      channel.incoming.add(push);
      await _settle();
      expect(events.whereType<DanmakuReceived>().length, 1);
      connection.heartbeat();
      expect(channel.sent.last, {'v': 1, 't': 0});
      expect(jsonEncode(channel.sent), isNot(contains('"c":"sendMessage"')));
      await connection.close();
      expect(channel.closed, isTrue);
      expect(guest.requests.single.cancel!.isCancelled, isTrue);
      final count = events.length;
      channel.incoming.add(_push([_item(_chat(), id: 'late')]));
      await _settle();
      expect(events.length, count);
    });

    test('authentication refusal renews once; a second refusal ends without a ready event', () async {
      final guest = _Guest();
      final connector = _Connector();
      final connection = XiaohongshuDanmakuConnection(guest: guest, connector: connector.call);
      final events = <DanmakuEvent>[];
      final sub = connection.events.listen(events.add);
      addTearDown(() async {
        await connection.close();
        await sub.cancel();
      });
      await connection.connect(const XiaohongshuDanmakuArgs(roomId: _room));
      connector.channels.first.ack(code: 3100001);
      await _settle();
      expect(guest.requests.map((r) => r.refresh), [false, true]);
      expect(connector.channels.first.closed, isTrue);
      expect(connector.channels.length, 2);
      connector.channels.last.ack(code: 3100001);
      await _settle();
      expect(events.whereType<DanmakuReady>(), isEmpty);
      expect(events.whereType<DanmakuClosed>().single.reason, DanmakuCloseReason.credentialsUnavailable);
      expect(guest.requests.length, 2);
    });

    test('registration refusal cannot report ready or endlessly bootstrap', () async {
      final guest = _Guest();
      final connector = _Connector();
      final connection = XiaohongshuDanmakuConnection(guest: guest, connector: connector.call);
      addTearDown(connection.close);
      await connection.connect(const XiaohongshuDanmakuArgs(roomId: _room));
      connector.channels.single.ack();
      await _settle();
      connector.channels.single.ack(code: 3100001);
      await _settle();
      expect(connection.isConnected, isFalse);
      expect(connection.status, DanmakuStatus.closed);
      expect(guest.requests.length, 1);
    });

    test('close during bootstrap suppresses old completion and opens no socket', () async {
      final guest = _Guest()..pending = Completer<XiaohongshuPushIdentity>();
      final connector = _Connector();
      final connection = XiaohongshuDanmakuConnection(guest: guest, connector: connector.call);
      final events = <DanmakuEvent>[];
      final sub = connection.events.listen(events.add);
      addTearDown(sub.cancel);
      final connecting = connection.connect(const XiaohongshuDanmakuArgs(roomId: _room));
      await _settle();
      await connection.close();
      expect(guest.requests.single.cancel!.isCancelled, isTrue);
      guest.pending!.complete(_identity);
      await connecting;
      expect(connector.channels, isEmpty);
      expect(events, isEmpty);
    });

    test('dedup storage is bounded and resets for a new room run', () async {
      final guest = _Guest();
      final connector = _Connector();
      final connection = XiaohongshuDanmakuConnection(guest: guest, connector: connector.call);
      final messages = <LiveMessage>[];
      final sub = connection.events.listen((e) {
        if (e is DanmakuReceived) messages.add(e.message);
      });
      addTearDown(() async {
        await connection.close();
        await sub.cancel();
      });
      await connection.connect(const XiaohongshuDanmakuArgs(roomId: _room));
      await _join(connector.channels.last);
      for (var i = 0; i < 513; i++) {
        connector.channels.last.incoming.add(_push([_item(_chat(), id: 'message-$i')]));
      }
      connector.channels.last.incoming.add(_push([_item(_chat(), id: 'message-0')]));
      await _settle();
      expect(messages.length, 514);
      await connection.connect(const XiaohongshuDanmakuArgs(roomId: _room));
      await _join(connector.channels.last);
      connector.channels.last.incoming.add(_push([_item(_chat(), id: 'message-0')]));
      await _settle();
      expect(messages.length, 515);
    });

    test('ordinary reconnect repeats auth and join, reuses the visitor and preserves dedup', () {
      fakeAsync((clock) {
        final guest = _Guest();
        final connector = _Connector();
        final connection = XiaohongshuDanmakuConnection(guest: guest, connector: connector.call);
        final events = <DanmakuEvent>[];
        final sub = connection.events.listen(events.add);
        unawaited(connection.connect(const XiaohongshuDanmakuArgs(roomId: _room)));
        clock.flushMicrotasks();
        for (var i = 0; i < 3; i++) {
          connector.channels.last.ack();
          clock.flushMicrotasks();
        }
        connector.channels.last.incoming.add(_push([_item(_chat())]));
        clock.flushMicrotasks();
        unawaited(connector.channels.last.incoming.close());
        clock
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 3))
          ..flushMicrotasks();
        expect(connector.channels.length, 2);
        expect(_operation(connector.channels.last.sent.single), 0);
        for (var i = 0; i < 3; i++) {
          connector.channels.last.ack();
          clock.flushMicrotasks();
        }
        connector.channels.last.incoming.add(_push([_item(_chat())]));
        clock.flushMicrotasks();
        expect(events.whereType<DanmakuReady>().length, 2);
        expect(events.whereType<DanmakuReceived>().length, 1);
        expect(guest.requests.length, 1);
        unawaited(connection.close());
        unawaited(sub.cancel());
        clock.flushMicrotasks();
      });
    });
  });
}
