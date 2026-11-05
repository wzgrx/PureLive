import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/codec/messagepack.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';

/// A decoded CC packet; unrelated/account-specific services are not interpreted.
typedef CcPacket = ({int sid, int cid, Map<Object, Object?> body});

/// Anonymous public CC registration, channel join and text push framing.
abstract final class CcDanmakuProtocol {
  /// Public web push endpoint.
  static final Uri endpoint = Uri.parse('wss://weblink.cc.163.com/');

  /// Frames an outbound message. Identity fields stay integers, not floats.
  static Uint8List packet(int sid, int cid, Map<Object, Object?> body) {
    final content = MessagePack.encode(body);
    final out = Uint8List(8 + content.length);
    ByteData.sublistView(out)
      ..setUint16(0, sid, Endian.little)
      ..setUint16(2, cid, Endian.little);
    out.setRange(8, out.length, content);
    return out;
  }

  /// Current webpage visitor registration (8382); distinct from room client 4000.
  static Uint8List registration(String visitor, {int? millis}) {
    final token = '$visitor@web.cc.163.com';
    return packet(6144, 2, {
      'web-cc': millis ?? DateTime.now().millisecondsSinceEpoch,
      'macAdd': token,
      'device_token': token,
      'webccType': 8382,
      'page_uuid': visitor,
      'update_req_info': {
        '22': 1280,
        '23': 720,
        '24': 'web',
        '25': 'Windows NT',
        '29': '163_cc',
        '30': '',
        '31': CcApi.userAgent,
        '39': 0,
      },
      'memory': 1,
      'version': 1,
      'system': 'win',
      'client_type': 8382,
      'client_source': 8382,
      'account_id': token,
    });
  }

  /// Read-only channel subscription; no outgoing chat, reactions or gifts.
  static Uint8List join(CcDanmakuArgs args, String visitor) => packet(512, 1, {
    'roomId': args.roomId,
    'cid': args.channelId,
    'gametype': args.gameType,
    'hall_version': 1,
    'motive': '',
    'account_id': '$visitor@web.cc.163.com',
    'recom_token': '',
    'client_type': 4000,
  });

  /// Validates the entire bounded binary frame before exposing its body.
  static CcPacket? decode(Object? raw) {
    if (raw is! List<int> || raw.length < 8 || raw.length > 1024 * 1024) return null;
    try {
      final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
      final h = ByteData.sublistView(bytes);
      final sid = h.getUint16(0, Endian.little);
      final cid = h.getUint16(2, Endian.little);
      final flag = h.getUint32(4, Endian.little);
      Uint8List body;
      if (flag == 0) {
        body = Uint8List.sublistView(bytes, 8);
      } else if (flag == 1) {
        if (bytes.length < 12 || h.getUint32(8, Endian.little) != bytes.length - 12) return null;
        final sink = _Inflated();
        ZLibDecoder().startChunkedConversion(sink)
          ..add(Uint8List.sublistView(bytes, 12))
          ..close();
        body = sink.bytes.takeBytes();
      } else {
        return null;
      }
      final decoded = MessagePack.decode(body);
      return decoded is Map<Object, Object?> ? (sid: sid, cid: cid, body: decoded) : null;
    } on Object {
      return null;
    }
  }

  static String _text(Object? o) => o is String
      ? o
      : o is int
      ? '$o'
      : '';

  /// Actual text services. Entry notices without text are not invented chats.
  static List<LiveMessage> messages(CcPacket packet, CcDanmakuArgs args) {
    if ((packet.sid == 40961 || packet.sid == 41016) && packet.cid == 4) {
      final value = packet.sid == 41016 ? packet.body['data'] : packet.body;
      final gift = value is Map ? _gift(value, args) : null;
      return gift == null ? const [] : [gift];
    }
    if (!((packet.sid == 515 && packet.cid == 32785) || (packet.sid == 535 && packet.cid == 32769))) return const [];
    final rows = packet.body['msg'];
    if (rows is! List || rows.length > 1024) return const [];
    final result = <LiveMessage>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final text = row[4];
      if (text is! String || text.trim().isEmpty || text.length > 8192) continue;
      var name = _text(row[197]);
      if (packet.sid == 535) {
        try {
          final raw = row[7];
          final profile = raw is String ? jsonDecode(raw) : raw;
          if (profile is Map) name = _text(profile['nickname']);
        } on FormatException {
          continue;
        }
      }
      if (name.length > 512) continue;
      result.add(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: name,
          message: text,
          userId: _text(row['uid']),
          messageId: _text(row['msgid']),
          sourceRoomId: args.publicRoomId,
          color: LiveMessageColor.white,
        ),
      );
    }
    return result;
  }

  static LiveMessage? _gift(Map<Object?, Object?> payload, CcDanmakuArgs args) {
    // These services also carry site-wide banners: only the actual receiver
    // of this room may produce a local gift line.
    if (args.anchorId <= 0 ||
        int.tryParse(_text(payload['toid'])) != args.anchorId ||
        payload['hide_chat_msg'] == true ||
        payload['hide_chat_msg'] == 1) {
      return null;
    }
    final id = _text(payload['saleid']);
    final sender = _text(payload['fromid']);
    if (id.isEmpty || id.length > 64 || sender.isEmpty) return null;
    final raw = payload['num'];
    int? quantity;
    if (raw is int) {
      quantity = raw;
    } else if (raw is String && raw.length <= 9) {
      final key = payload['key'];
      if (key is String && key.length == 10 && key.split('').toSet().length == 10) {
        final digits = <int>[];
        for (final char in raw.split('')) {
          final n = key.indexOf(char);
          if (n < 0) return null;
          digits.add(n);
        }
        quantity = int.tryParse(digits.join());
      } else if (key == null || key == '') {
        quantity = int.tryParse(raw);
      }
    }
    if (quantity == null || quantity < 1 || quantity > 1000000) return null;
    final name = _text(payload['gift_name']);
    final nick = _text(payload['fromnick']);
    final receiver = _text(payload['tonick']);
    if (name.length > 512 || nick.length > 512 || receiver.length > 512) return null;
    final image = Uri.tryParse(normalizeImageUrl(payload['icon'] ?? payload['pic']));
    final combo = _text(payload['comboid']);
    final gift = LiveGift(
      id: id,
      name: name,
      count: quantity,
      receiverName: receiver,
      comboKey: combo.isEmpty ? '' : 'cc:${args.publicRoomId}:$sender:${args.anchorId}:$id:$combo',
      iconUrl: image != null && image.scheme == 'https' && image.host.isNotEmpty && image.userInfo.isEmpty
          ? image
          : null,
    );
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: nick,
      userId: sender,
      message: gift.plainText,
      messageId: _text(payload['sn_id']),
      sourceRoomId: args.publicRoomId,
      color: LiveMessageColor.white,
      data: gift,
    );
  }
}

final class _Inflated implements Sink<List<int>> {
  final bytes = BytesBuilder(copy: false);
  int count = 0;
  @override
  void add(List<int> data) {
    count += data.length;
    if (count > 1024 * 1024) throw const FormatException('CC inflate limit');
    bytes.add(data);
  }

  @override
  void close() {}
}

/// One anonymous connection, ready only after the channel's successful ack.
final class CcDanmakuConnection extends DanmakuSocketConnection<CcDanmakuArgs> {
  /// Uses the app's CC proxy; all reconnect and cancellation resources are shared.
  new({
    super.proxy,
    super.connector,
    super.policy = const DanmakuSocketPolicy(
      heartbeatInterval: Duration(seconds: 30),
      joinTimeout: Duration(seconds: 15),
    ),
  }) : super(site: SiteIds.cc);
  late CcDanmakuArgs _args;
  String _visitor = '';
  bool _joined = false;
  static String _newVisitor() {
    final r = Random.secure();
    final b = List.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final s = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  @override
  Future<DanmakuSocketTarget> target(CcDanmakuArgs args, DanmakuRun run) async {
    if (args.channelId <= 0 || args.roomId <= 0 || args.gameType < 0) {
      throw const DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable);
    }
    _args = args;
    _visitor = _newVisitor();
    return DanmakuSocketTarget(
      endpoints: [CcDanmakuProtocol.endpoint],
      headers: const {'Origin': CcApi.origin, 'User-Agent': CcApi.userAgent},
    );
  }

  @override
  void onOpen(DanmakuSocketSession session) {
    _joined = false;
    session.send(CcDanmakuProtocol.registration(_visitor));
  }

  @override
  void onData(DanmakuSocketSession session, Object? data) {
    final packet = CcDanmakuProtocol.decode(data);
    if (packet == null) return;
    if (packet.sid == 6144 && packet.cid == 2) {
      if (packet.body['result'] != 0) {
        session.run.closed(DanmakuCloseReason.credentialsUnavailable);
        return;
      }
      session
        ..send(CcDanmakuProtocol.packet(513, 4, {}))
        ..send(CcDanmakuProtocol.join(_args, _visitor));
    } else if (packet.sid == 512 && packet.cid == 1) {
      if (packet.body['result'] != 0) {
        session.run.closed(DanmakuCloseReason.connectionFailed);
        return;
      }
      // Reject a stale/different channel acknowledgement.
      if (packet.body['cid'] != _args.channelId || packet.body['roomId'] != _args.roomId) return;
      if (!_joined) {
        _joined = true;
        session.ready();
      }
      final count = packet.body['usercount'];
      if (count is int && count >= 0) {
        session.message(
          LiveMessage(
            type: LiveMessageType.online,
            userName: '',
            message: '',
            sourceRoomId: _args.publicRoomId,
            data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: count),
            color: LiveMessageColor.white,
          ),
        );
      }
    }
    if (session.isConnected) {
      CcDanmakuProtocol.messages(packet, _args).forEach(session.message);
    }
  }

  @override
  Object? heartbeatFrame(DanmakuSocketSession session) => CcDanmakuProtocol.packet(6144, 5, {});
}
