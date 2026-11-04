import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// Read-only visitor requests supplied by the platform shell. A short-lived
/// browser obtains the website's current guest credentials; account cookies
/// and signatures are never part of room data or persisted settings.
abstract interface class XiaohongshuGuest {
  /// The public category response, as JSON text.
  Future<String> categories({CancelToken? cancel});

  /// The public feed response. [cursor] is the server's opaque score, not a
  /// room number; each UI listing owns its cursor.
  Future<String> directory({required String category, required String cursor, CancelToken? cancel});

  /// A visitor identity for the independent room socket. A refused identity
  /// may be renewed once through [refresh]. No chat is posted.
  Future<XiaohongshuPushIdentity> pushIdentity(String roomId, {bool refresh = false, CancelToken? cancel});
}

/// Ephemeral RWP credentials. Deliberately has no serialization or diagnostic
/// representation: logs and stored rooms must never contain the SID.
@immutable
final class XiaohongshuPushIdentity {
  /// Creates an identity obtained from a successful visitor handshake.
  const new({
    required this.sid,
    required this.uid,
    required this.deviceId,
    required this.fingerprint,
    required this.userAgent,
  });

  /// Short-lived guest token.
  final String sid;

  /// Visitor id, not the streamer's stable id.
  final String uid;

  /// Browser device id.
  final String deviceId;

  /// RWP client fingerprint.
  final String fingerprint;

  /// User agent of the initializing browser.
  final String userAgent;
}

/// Non-secret room arguments; credentials are obtained only on connection.
@immutable
final class XiaohongshuDanmakuArgs {
  /// Creates the arguments.
  const new({required this.roomId});

  /// Exact broadcast id, preserved as text.
  final String roomId;
}
