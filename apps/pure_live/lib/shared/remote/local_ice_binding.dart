import 'dart:io';
import 'dart:typed_data';

/// A receiver-local IPv4 STUN binding responder for already paired peers.
/// It only reports the source transport address back to its sender. It never
/// relays media, contacts the Internet, or opens a socket before LAN control.
final class LocalIceBinding {
  new _(this._socket, this._allows) {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = _socket.receive();
      if (packet == null || !_allows(packet.address)) return;
      if (_window.elapsedMilliseconds >= 1000) {
        _window.reset();
        _count = 0;
      }
      if (++_count > 100) return;
      final reply = response(packet.data, packet.address, packet.port);
      if (reply != null) {
        try {
          _socket.send(reply, packet.address, packet.port);
        } on SocketException {
          // A network switch must not interrupt playback or LAN control.
        }
      }
    }, onError: (Object _) {});
  }

  /// Binds only with the enabled LAN receiver and shares its bind address.
  static Future<LocalIceBinding> bind(
    InternetAddress address, {
    required bool Function(InternetAddress) allows,
  }) async => LocalIceBinding._(await RawDatagramSocket.bind(address, 0), allows);

  final RawDatagramSocket _socket;
  final bool Function(InternetAddress) _allows;
  final Stopwatch _window = Stopwatch()..start();
  int _count = 0;

  /// Only disclosed in an authenticated receiver status response.
  int get port => _socket.port;

  /// Releases the socket on receiver shutdown.
  void close() => _socket.close();

  /// RFC 8489 binding subset: magic cookie, transaction ID, aligned optional
  /// attributes and XOR-MAPPED-ADDRESS. Authentication/TURN requests and
  /// unknown comprehension-required attributes are not supported or answered.
  static Uint8List? response(Uint8List packet, InternetAddress address, int port) {
    if (address.type != InternetAddressType.IPv4 || packet.length < 20 || packet.length > 576) return null;
    final input = ByteData.sublistView(packet);
    if (input.getUint16(0) != 0x0001 || input.getUint32(4) != 0x2112a442) return null;
    final length = input.getUint16(2);
    if (length % 4 != 0 || length + 20 != packet.length) return null;
    var at = 20;
    while (at < packet.length) {
      if (at + 4 > packet.length) return null;
      final type = input.getUint16(at);
      final size = input.getUint16(at + 2);
      if (type < 0x8000) return null;
      at += 4 + ((size + 3) & ~3);
      if (at > packet.length) return null;
    }
    final result = Uint8List(32);
    final output = ByteData.sublistView(result)
      ..setUint16(0, 0x0101)
      ..setUint16(2, 12)
      ..setUint32(4, 0x2112a442);
    result.setRange(8, 20, packet, 8);
    output
      ..setUint16(20, 0x0020)
      ..setUint16(22, 8)
      ..setUint8(25, 1)
      ..setUint16(26, port ^ 0x2112);
    final ip = address.rawAddress;
    for (var i = 0; i < 4; i++) {
      result[28 + i] = ip[i] ^ packet[4 + i];
    }
    return result;
  }
}
