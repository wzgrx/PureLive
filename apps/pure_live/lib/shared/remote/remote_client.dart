import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pure_live/shared/net/lan_address.dart';
import 'package:pure_live/shared/net/mdns_peers.dart';
import 'package:pure_live/shared/remote/playback_remote.dart';
import 'package:pure_live/shared/remote/remote_access.dart';

/// A discovered receiver's public entry point; pairing is always separate.
typedef RemoteControlPeer = ({String name, Uri uri});

/// Validates a manual address or browser QR URL before making requests.
Uri? remoteControlUri(String text) {
  final uri = Uri.tryParse(text.contains('://') ? text.trim() : 'http://${text.trim()}');
  if (uri == null ||
      uri.scheme != 'http' ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.port < 1 ||
      uri.port > 65535 ||
      !isIpv4(uri.host)) {
    return null;
  }
  final parts = uri.host.split('.').map(int.parse).toList();
  if (!(parts[0] == 10 ||
      parts[0] == 127 ||
      (parts[0] == 192 && parts[1] == 168) ||
      (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) ||
      (parts[0] == 169 && parts[1] == 254))) {
    return null;
  }
  return uri.replace(path: '/');
}

/// A paired controller; token and target are scoped to one receiving origin.
final class PlaybackRemoteClient {
  /// Creates an unpaired client for a validated endpoint.
  new(this.uri);

  /// The exact origin this controller paired with.
  final Uri uri;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  String? _token;
  bool _closed = false;

  /// Whether a pair response has been accepted.
  bool get paired => _token != null && !_closed;

  /// Pairs with the code visible on the receiving screen.
  Future<void> pair(String code) async {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) throw const FormatException('invalid code');
    if (_closed || remoteControlUri(uri.toString()) == null) throw const SocketException('invalid receiver');
    await ensurePlaybackRemoteAccess();
    final data = await _request('pair', {'code': code});
    final token = data['token'];
    if (token is! String || token.length != 43) throw const FormatException('invalid pair response');
    _token = token;
  }

  /// Reads the current page identity and public playback state.
  Future<Map<String, dynamic>> status() => _request('status');

  /// Sends a command to the precise page read from [status].
  Future<void> command(String target, String command, {double? value}) async {
    await _request('command', {'targetId': target, 'command': command, 'value': ?value});
  }

  /// Pushes a supported live-room URL or share text.
  Future<void> sendLink(String text) async {
    await _request('link', {'text': text});
  }

  /// Fixed screen signaling; pixels flow peer-to-peer and are not HTTP uploads.
  Future<Map<String, dynamic>> screen(String action, Map<String, Object?> data) {
    if (!{'view', 'answer', 'push', 'stop'}.contains(action)) throw const FormatException('invalid screen action');
    return _request('screen/$action', data);
  }

  /// Writes only to the exact focused input reported by the receiving app.
  Future<void> insertText(String target, int inputId, String text) async {
    await _request('text', {'targetId': target, 'inputId': inputId, 'text': text});
  }

  Future<Map<String, dynamic>> _request(String path, [Map<String, Object?>? body]) async {
    if (_closed || remoteControlUri(uri.toString()) == null) throw const SocketException('invalid receiver');
    final request = await _http.openUrl(body == null ? 'GET' : 'POST', uri.resolve('/api/$path'));
    // The receiver deliberately closes each response; do not pool a closing socket.
    request
      ..persistentConnection = false
      ..followRedirects = false;
    if (_token != null) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(Duration(seconds: path.startsWith('screen/') ? 30 : 15));
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 5))) {
      bytes.addAll(chunk);
      if (bytes.length > (path.startsWith('screen/') ? 65536 : 32768)) {
        throw const FormatException('oversized response');
      }
    }
    if (response.statusCode == HttpStatus.unauthorized) _token = null;
    if (response.statusCode != HttpStatus.ok) throw HttpException('Remote ${response.statusCode}');
    if (bytes.isEmpty) return <String, dynamic>{};
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>) throw const FormatException('invalid response');
    return data;
  }

  /// Revokes this session on the receiver and releases the connection pool.
  Future<void> disconnect() async {
    try {
      if (paired) await _request('unpair', {});
    } finally {
      close();
    }
  }

  /// Releases only this client. Closing a page does not disable the receiver.
  void close() {
    _closed = true;
    _token = null;
    _http.close(force: true);
  }
}

/// Discovers current receivers over mDNS and IPv4 broadcast for five seconds.
/// No account identity, pairing code, or session token is announced.
Future<List<RemoteControlPeer>> discoverPlaybackRemotes({MdnsPeers? mdns}) async {
  await ensurePlaybackRemoteAccess();
  final peers = <String, RemoteControlPeer>{};
  final bonsoir = mdns ?? BonsoirPeers(type: '_purelive-remote._tcp');
  RawDatagramSocket? socket;
  void add(String id, String name, String ip, int port) {
    final uri = remoteControlUri('http://$ip:$port/');
    if (uri != null && peers.length < 32) peers[id] = (name: name, uri: uri);
  }

  try {
    await bonsoir.start(
      name: 'PureLive controller',
      port: 0,
      attributes: const {},
      found: (peer) => add(peer.id, peer.name, peer.ip, peer.port),
      lost: peers.remove,
    );
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket
        ..broadcastEnabled = true
        ..listen((event) {
          if (event != RawSocketEvent.read) return;
          Datagram? packet;
          while ((packet = socket!.receive()) != null) {
            final message = packet!;
            if (message.data.length > 2048) continue;
            try {
              final data = jsonDecode(utf8.decode(message.data));
              if (data is Map &&
                  data['protocol'] == 'purelive-remote-v1' &&
                  data['id'] is String &&
                  data['name'] is String &&
                  data['port'] is int) {
                add(data['id'] as String, data['name'] as String, message.address.address, data['port'] as int);
              }
            } on FormatException {
              // Ignore unrelated LAN datagrams.
            }
          }
        });
      socket.send(
        ascii.encode('purelive-remote-discover-v1'),
        InternetAddress('255.255.255.255'),
        PlaybackRemote.discoveryPort,
      );
    } on Object {
      // mDNS and manual input remain available without broadcast permission.
    }
    await Future<void>.delayed(const Duration(seconds: 5));
    return peers.values.toList(growable: false);
  } finally {
    socket?.close();
    await bonsoir.stop();
  }
}
