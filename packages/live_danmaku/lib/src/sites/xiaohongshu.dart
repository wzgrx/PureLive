import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_danmaku/src/socket_connection.dart';
import 'package:live_net/live_net.dart';

/// Pure RWP framing for public Xiaohongshu live rooms. No account messaging,
/// outgoing comments, reactions, purchases or private-message decoding.
abstract final class XiaohongshuDanmakuProtocol {
  /// The website's live push endpoint.
  static final Uri endpoint = Uri.parse('wss://apppush-rws.xiaohongshu.com/rwp');

  /// Transport control frame.
  static String control(String id, int operation, Map<String, Object?> body) => jsonEncode({
    'v': 1,
    't': 2,
    'm': id,
    'b': {
      'd': {'a': 1, 's': operation, 'b': body},
    },
  });

  /// Same guest handshake observed on the public website. The identity is
  /// obtained from an acknowledged, isolated visitor session at runtime.
  static String handshake(String id, XiaohongshuPushIdentity identity) => control(id, 0, {
    'appId': 'xhs-pc',
    'authInfo': {'authType': 'generic', 'sid': identity.sid, 'uid': identity.uid, 'domain': 'red'},
    'deviceInfo': {
      'deviceId': identity.deviceId,
      'fingerprint': identity.fingerprint,
      'platform': 'browser',
      'os': 'web',
      'osVersion': '10.15',
      'deviceName': 'Chrome',
      'appVersion': '131.0.0.0',
      'userAgent': identity.userAgent,
    },
    'serviceTag': '',
    'bizInfos': [
      {'bizName': 'push', 'serializeType': 'json'},
    ],
    'roomInfo': [],
    'roomInfos': [],
    'tagInfo': [],
    'extInfo': {},
    'state': 1,
  });

  /// Registers only the room JSON service.
  static String register(String id) => control(id, 1, {
    'bizInfo': {'bizName': 'room', 'serializeType': 'json'},
    'register': true,
  });

  /// Subscribes to exactly one broadcast.
  static String join(String id, String roomId) => control(id, 8, {
    'info': {'bizName': 'room', 'roomId': roomId, 'roomType': 'LIVE'},
  });

  /// A viewing heartbeat, carrying no chat content.
  static String viewerHeart(String id, String roomId, String uid) => jsonEncode({
    'v': 1,
    't': 3,
    'm': id,
    'b': {
      'd': {
        'a': 0,
        'c': 'liveHeartBeat',
        'biz': 'room',
        'b': base64Encode(
          utf8.encode(
            jsonEncode({
              'roomId': roomId,
              'roomType': 'LIVE',
              'command': 1,
              'customData': jsonEncode({
                'type': 'viewer_heart',
                'priority': 0,
                'profile': {'nickname': '', 'avatar': '', 'user_id': uid, 'role': 0},
                'source': 'web_live',
                'desc': '',
              }),
            }),
          ),
        ),
        'e': <String, Object?>{},
        's': 'rrmp.o.l',
      },
    },
  });

  static Map<Object?, Object?> _map(Object? value) => value is Map ? value : const {};
  static String _text(Object? value) => value is String
      ? value
      : value is int
      ? '$value'
      : '';
  static int? _count(Object? value) {
    final n = value is int
        ? value
        : value is String
        ? int.tryParse(value)
        : null;
    return n != null && n >= 0 && n <= 9007199254740991 ? n : null;
  }

  /// A bounded JSON envelope, or null. Malformed frames never escape into
  /// the shared socket callback and never contain diagnostic raw text.
  static Map<Object?, Object?>? envelope(Object? data) {
    if (data is! String || data.length > 1024 * 1024) return null;
    try {
      final value = jsonDecode(data);
      return value is Map ? value : null;
    } on FormatException {
      return null;
    }
  }

  /// Reads only room pushes for [roomId]. One corrupt item cannot hide the
  /// next message in a batch. Names are exactly those the server supplies;
  /// masked names and missing names are never reconstructed.
  static List<LiveMessage> messages(Map<Object?, Object?> frame, String roomId) {
    if (frame['t'] != 4) return const [];
    final data = _map(_map(frame['b'])['d']);
    final batch = data['b'];
    if (data['biz'] != 'room' || batch is! List || batch.length > 256) return const [];
    final out = <LiveMessage>[];
    for (final item in batch) {
      final encoded = _map(item)['d'];
      if (encoded is! String || encoded.length > 128 * 1024) continue;
      try {
        final payload = _map(jsonDecode(utf8.decode(base64Decode(encoded))));
        if (_text(payload['roomId']) != roomId || payload['roomType'] != 'LIVE') continue;
        final raw = payload['customData'];
        final custom = _map(raw is String ? jsonDecode(raw) : raw);
        final id = _text(payload['msgId']).isNotEmpty ? _text(payload['msgId']) : _text(custom['commentId']);
        if (custom['type'] == 'text') {
          final text = custom['desc'] is String ? custom['desc']! as String : '';
          if (text.trim().isEmpty || text.length > 8192) continue;
          final profile = _map(custom['profile']);
          final nick = profile['nickname'] is String ? profile['nickname']! as String : '';
          if (nick.length > 512) continue;
          final millis = _count(payload['ts']);
          out.add(
            LiveMessage(
              type: LiveMessageType.chat,
              userName: nick,
              userId: _text(profile['user_id']),
              message: text,
              messageId: id,
              sourceRoomId: roomId,
              color: LiveMessageColor.white,
              sentAt: millis == null || millis > 8640000000000000
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
            ),
          );
        } else if (custom['type'] == 'refresh') {
          final room = _map(custom['room_data']);
          for (final metric in [
            (room['member_count'], LiveAudienceMetricKind.onlineViewers),
            (room['uv'], LiveAudienceMetricKind.totalViewers),
          ]) {
            final count = _count(metric.$1);
            if (count == null) continue;
            out.add(
              LiveMessage(
                type: LiveMessageType.online,
                userName: '',
                message: '',
                color: LiveMessageColor.white,
                sourceRoomId: roomId,
                data: LiveAudienceUpdate(kind: metric.$2, value: count),
              ),
            );
          }
        }
      } on FormatException {
        continue;
      }
    }
    return out;
  }
}

/// One native socket per requested chat. Browser resources are released
/// before this socket starts; normal reconnects reuse the visitor identity.
final class XiaohongshuDanmakuConnection extends DanmakuSocketConnection<XiaohongshuDanmakuArgs> {
  /// Creates the read-only connection.
  new({
    required this.guest,
    super.proxy,
    super.connector,
    super.policy = const DanmakuSocketPolicy(
      heartbeatInterval: Duration(seconds: 30),
      joinTimeout: Duration(seconds: 10),
    ),
  }) : super(site: 'xiaohongshu');

  /// Visitor bootstrap shared with the platform adapter.
  final XiaohongshuGuest guest;
  late XiaohongshuPushIdentity _identity;
  late XiaohongshuDanmakuArgs _args;
  CancelToken? _cancel;
  int _serial = 0;
  int _step = 0;
  int _renewals = 0;
  String _expected = '';
  final LinkedHashSet<String> _seen = LinkedHashSet();
  String _id() => 'pl-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';

  DanmakuSocketTarget _target() => DanmakuSocketTarget(
    endpoints: [XiaohongshuDanmakuProtocol.endpoint],
    headers: {'Origin': 'https://www.xiaohongshu.com', 'User-Agent': _identity.userAgent},
  );

  @override
  Future<DanmakuSocketTarget> target(XiaohongshuDanmakuArgs args, DanmakuRun run) async {
    if (!XiaohongshuApi.isRoomId(args.roomId)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable);
    }
    final cancel = _cancel = CancelToken();
    unawaited(run.ended.then((_) => cancel.cancel()));
    _args = args;
    final XiaohongshuPushIdentity identity;
    try {
      identity = await guest.pushIdentity(args.roomId, cancel: cancel);
    } on Object {
      throw const DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable);
    }
    if (!run.isActive) throw const DanmakuStartFailure(DanmakuCloseReason.credentialsUnavailable);
    _identity = identity;
    return _target();
  }

  @override
  void onOpen(DanmakuSocketSession session) {
    _step = 0;
    _expected = _id();
    session.send(XiaohongshuDanmakuProtocol.handshake(_expected, _identity));
  }

  @override
  void onData(DanmakuSocketSession session, Object? data) {
    final frame = XiaohongshuDanmakuProtocol.envelope(data);
    if (frame == null) return;
    if (frame['t'] == 2 && frame['m'] == _expected) {
      final b = frame['b'];
      final ack = b is Map ? b['a'] : null;
      if (ack is! Map || ack['c'] is! int) return;
      if (ack['c'] != 0) {
        if (_step == 0 && _renewals++ == 0) {
          _expected = '';
          _step = -1;
          session.cancelJoinTimeout();
          session.run.reconnecting(DanmakuInterruption.disconnected);
          unawaited(_renew(session));
        } else {
          session.run.closed(DanmakuCloseReason.credentialsUnavailable);
        }
        return;
      }
      _expected = _id();
      if (_step == 0) {
        _step = 1;
        session.send(XiaohongshuDanmakuProtocol.register(_expected));
      } else if (_step == 1) {
        _step = 2;
        session.send(XiaohongshuDanmakuProtocol.join(_expected, _args.roomId));
      } else if (_step == 2) {
        _step = 3;
        _renewals = 0;
        session
          ..ready()
          ..send(XiaohongshuDanmakuProtocol.viewerHeart(_id(), _args.roomId, _identity.uid));
      }
    }
    if (!session.isConnected) return;
    for (final message in XiaohongshuDanmakuProtocol.messages(frame, _args.roomId)) {
      if (message.type == LiveMessageType.chat && message.messageId.isNotEmpty) {
        if (!_seen.add(message.messageId)) continue;
        if (_seen.length > 512) _seen.remove(_seen.first);
      }
      session.message(message);
    }
  }

  Future<void> _renew(DanmakuSocketSession session) async {
    final args = _args;
    final cancel = _cancel!;
    try {
      final identity = await guest.pushIdentity(args.roomId, refresh: true, cancel: cancel);
      if (!session.isActive || cancel.isCancelled) return;
      _identity = identity;
      await session.reopen(_target());
    } on Object {
      if (session.isActive) session.run.closed(DanmakuCloseReason.credentialsUnavailable);
    }
  }

  @override
  Object? heartbeatFrame(DanmakuSocketSession session) {
    if (session.isConnected) {
      session
        ..send(XiaohongshuDanmakuProtocol.control(_id(), 6, {}))
        ..send(XiaohongshuDanmakuProtocol.viewerHeart(_id(), _args.roomId, _identity.uid));
    }
    return '{"v":1,"t":0}';
  }

  @override
  Future<void> stop() async {
    _cancel?.cancel();
    _cancel = null;
    _seen.clear();
    _renewals = 0;
    await super.stop();
  }
}
