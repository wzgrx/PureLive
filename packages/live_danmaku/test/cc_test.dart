import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_danmaku/src/codec/messagepack.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const args = CcDanmakuArgs(roomId: 15, channelId: 5515810, gameType: 9045, publicRoomId: '123456');

class Channel implements SocketChannel {
  final incoming = StreamController<Object?>.broadcast(sync: true);
  final sent = <CcPacket>[];
  bool closed = false;
  @override
  Stream<Object?> get stream => incoming.stream;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  void add(Object data) {
    final p = CcDanmakuProtocol.decode(data);
    if (p != null) sent.add(p);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
  }

  void ack(int sid, int cid, Map<Object, Object?> body) => incoming.add(CcDanmakuProtocol.packet(sid, cid, body));
}

Future<void> settle() async {
  for (var n = 0; n < 50; n++) {
    await Future<void>.value();
  }
}

void main() {
  test('CC gift broadcasts scope the receiver, decode quantity alphabets and never invent prices', () {
    const receiver = CcDanmakuArgs(
      roomId: 15,
      channelId: 5515810,
      gameType: 9045,
      publicRoomId: '123456',
      anchorId: 999,
    );
    final payload = <Object, Object?>{
      'toid': 999,
      'fromid': 11,
      'fromnick': '发送者',
      'tonick': '主播',
      'saleid': 12,
      'gift_name': '礼物',
      'num': 'bc',
      'key': 'abcdefghij',
      'sn_id': 'synthetic-gift',
      'comboid': 'synthetic-combo',
      'icon': 'https://cc.res.netease.com/example.png',
    };
    CcPacket frame() => CcDanmakuProtocol.decode(CcDanmakuProtocol.packet(41016, 4, {'data': payload}))!;
    final gift = CcDanmakuProtocol.messages(frame(), receiver).single.gift!;
    expect(gift.count, 12);
    expect(gift.name, '礼物');
    expect(gift.unitPrice, isNull);
    expect(gift.totalValue, isNull);
    expect(gift.iconUrl!.scheme, 'https');
    payload['toid'] = 888;
    expect(CcDanmakuProtocol.messages(frame(), receiver), isEmpty);
    payload['toid'] = 999;
    payload['num'] = '?';
    expect(CcDanmakuProtocol.messages(frame(), receiver), isEmpty);
    payload['num'] = 2;
    payload
      ..remove('gift_name')
      ..remove('icon');
    final unknown = CcDanmakuProtocol.messages(frame(), receiver).single.gift!;
    expect(unknown.name, isEmpty);
    expect(unknown.displayName, '12');
    expect(unknown.iconUrl, isNull);
  });

  test('MessagePack uses UTF8 byte lengths and big endian integer fields, including 128..255', () {
    expect(MessagePack.encode({'a': 300}), [0x81, 0xa1, 0x61, 0xcd, 1, 44]);
    expect(MessagePack.encode(128), [0xcc, 128]);
    final object = {
      197: '中文😀',
      4: 'literal {4: not a parser}',
      9: [null, true, false, -40, 65536, 1793790000000],
    };
    expect(MessagePack.decode(MessagePack.encode(object)), object);
    expect(MessagePack.decode(Uint8List.fromList([0xcb, 0x3f, 0xf8, 0, 0, 0, 0, 0, 0])), 1.5);
  });
  test('registration and join preserve current anonymous routing types and contain no login cookie', () {
    final reg = CcDanmakuProtocol.decode(CcDanmakuProtocol.registration('synthetic-visitor', millis: 1793790000000))!;
    expect((reg.sid, reg.cid), (6144, 2));
    expect(reg.body['client_type'], 8382);
    expect(reg.body['webccType'], 8382);
    final join = CcDanmakuProtocol.decode(CcDanmakuProtocol.join(args, 'synthetic-visitor'))!;
    expect(join.body['cid'], 5515810);
    expect(join.body['cid'], isA<int>());
    expect(join.body['client_type'], 4000);
    expect(reg.body.keys.map((k) => '$k'.toLowerCase()), isNot(contains('cookie')));
  });
  test('chat maps are decoded structurally; names and text can contain delimiters and braces', () {
    final packet = CcDanmakuProtocol.decode(
      CcDanmakuProtocol.packet(515, 32785, {
        'msg': [
          {197: '昵称, 4: text', 4: '内容 {197: stays literal}', 'uid': 42},
          {197: 'broken', 4: 12},
          {197: '第二条', 4: '下一条正常'},
        ],
      }),
    )!;
    final rows = CcDanmakuProtocol.messages(packet, args);
    expect(rows, hasLength(2));
    expect(rows.first.userName, '昵称, 4: text');
    expect(rows.first.message, '内容 {197: stays literal}');
    expect(rows.first.sourceRoomId, '123456');
    final game = CcDanmakuProtocol.decode(
      CcDanmakuProtocol.packet(535, 32769, {
        'msg': [
          {
            7: jsonEncode({'nickname': '游戏昵称'}),
            4: '游戏弹幕',
          },
        ],
      }),
    )!;
    expect(CcDanmakuProtocol.messages(game, args).single.userName, '游戏昵称');
    final entry = CcDanmakuProtocol.decode(
      CcDanmakuProtocol.packet(512, 32784, {
        'data': {
          'msg_list': [
            {'name': '游客'},
          ],
        },
      }),
    )!;
    expect(
      CcDanmakuProtocol.messages(entry, args),
      isEmpty,
      reason: 'a presence notification is not a fabricated comment',
    );
  });
  test('compression is length checked and inflated/parser complexity is bounded', () {
    final body = MessagePack.encode({
      'msg': [
        {197: '测试', 4: '压缩'},
      ],
    });
    final compressed = zlib.encode(body);
    Uint8List packed(List<int> data) {
      final out = Uint8List(12 + data.length);
      ByteData.sublistView(out)
        ..setUint16(0, 515, Endian.little)
        ..setUint16(2, 32785, Endian.little)
        ..setUint32(4, 1, Endian.little)
        ..setUint32(8, data.length, Endian.little);
      out.setRange(12, out.length, data);
      return out;
    }

    expect(CcDanmakuProtocol.messages(CcDanmakuProtocol.decode(packed(compressed))!, args).single.message, '压缩');
    final mismatch = packed(compressed);
    mismatch[8]++;
    expect(CcDanmakuProtocol.decode(mismatch), isNull);
    expect(CcDanmakuProtocol.decode(packed(zlib.encode(List.filled(2 * 1024 * 1024, 0)))), isNull);
    for (final b in [
      [0xd9, 20, 1],
      [0xdd, 255, 255, 255, 255],
      [0xc1],
      [0x81, 0xc0, 1],
    ]) {
      expect(() => MessagePack.decode(Uint8List.fromList(b)), throwsFormatException);
    }
    expect(() => MessagePack.decode(Uint8List.fromList([...List.filled(20, 0x91), 0])), throwsFormatException);
  });
  test('ready follows valid registration and channel ack; denied/wrong channels cannot feed chat', () async {
    final channel = Channel();
    final events = <DanmakuEvent>[];
    final connection = CcDanmakuConnection(
      connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) async {
        expect(headers.containsKey('Cookie'), isFalse);
        return channel;
      },
    );
    final subscription = connection.events.listen(events.add);
    await connection.connect(args);
    await settle();
    expect(channel.sent.single.sid, 6144);
    expect(events.whereType<DanmakuReady>(), isEmpty);
    channel.ack(6144, 2, {'result': 0});
    await settle();
    expect(channel.sent.map((p) => (p.sid, p.cid)), [(6144, 2), (513, 4), (512, 1)]);
    channel.ack(512, 1, {'result': 0, 'cid': 1, 'roomId': 15});
    await settle();
    expect(connection.isConnected, isFalse);
    channel.ack(512, 1, {'result': 0, 'cid': 5515810, 'roomId': 15, 'usercount': 12});
    await settle();
    expect(connection.isConnected, isTrue);
    channel.ack(515, 32785, {
      'msg': [
        {197: '用户', 4: '正常消息'},
      ],
    });
    await settle();
    expect(events.whereType<DanmakuReady>(), hasLength(1));
    expect(events.whereType<DanmakuReceived>().last.message.message, '正常消息');
    await connection.close();
    expect(channel.closed, isTrue);
    await subscription.cancel();
    await channel.incoming.close();
  });
}
