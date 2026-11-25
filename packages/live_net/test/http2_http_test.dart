// Http2LiveHttp against a local HTTP/2 server (TLS with a certificate made
// for the run by openssl) and a local CONNECT proxy: Kick's API refuses
// HTTP/1.1 since 2026-10, so its requests go over HTTP/2 (S02.4).
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http2/http2.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

void main() {
  late Directory folder;
  late SecurityContext serverContext;
  late SecurityContext clientContext;
  var openssl = true;

  setUpAll(() async {
    folder = Directory.systemTemp.createTempSync('http2_test');
    try {
      final made = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-days',
        '2',
        '-subj',
        '/CN=localhost',
        '-addext',
        'subjectAltName=DNS:localhost,IP:127.0.0.1',
        '-keyout',
        '${folder.path}/key.pem',
        '-out',
        '${folder.path}/cert.pem',
      ]);
      openssl = made.exitCode == 0;
    } on ProcessException {
      openssl = false;
    }
    if (!openssl) return;
    serverContext = SecurityContext()
      ..useCertificateChain('${folder.path}/cert.pem')
      ..usePrivateKey('${folder.path}/key.pem')
      ..setAlpnProtocols(['h2'], true);
    clientContext = SecurityContext()..setTrustedCertificates('${folder.path}/cert.pem');
  });

  tearDownAll(() => folder.deleteSync(recursive: true));

  /// An HTTP/2 server that answers every request with [answer]'s status and
  /// body, recording the request headers in [seen].
  Future<SecureServerSocket> h2Server(
    List<Map<String, String>> seen, {
    int status = 200,
    String body = '{"ok":true}',
    Duration delay = Duration.zero,
    Map<String, String> extra = const {},
  }) async {
    final server = await SecureServerSocket.bind('localhost', 0, serverContext);
    server.listen((socket) {
      final connection = ServerTransportConnection.viaSocket(socket);
      connection.incomingStreams.listen((stream) async {
        final headers = <String, String>{};
        await for (final message in stream.incomingMessages) {
          if (message is HeadersStreamMessage) {
            for (final header in message.headers) {
              headers[ascii.decode(header.name)] = utf8.decode(header.value);
            }
          }
        }
        seen.add(headers);
        await Future<void>.delayed(delay);
        try {
          stream
            ..sendHeaders([
              Header.ascii(':status', '$status'),
              for (final MapEntry(:key, :value) in extra.entries) Header.ascii(key, value),
            ])
            ..sendData(utf8.encode(body), endStream: true);
        } on Object {
          // The client went away (cancelled).
        }
      });
    });
    return server;
  }

  /// A CONNECT proxy that tunnels to localhost and counts its tunnels.
  Future<(ServerSocket, List<String>)> connectProxy() async {
    final tunnels = <String>[];
    final proxy = await ServerSocket.bind('127.0.0.1', 0);
    proxy.listen((client) {
      final head = <int>[];
      // ignore: ended with the tunnel
      // ignore: cancel_subscriptions, ended with the tunnel
      late StreamSubscription<List<int>> sub;
      sub = client.listen((data) async {
        head.addAll(data);
        final text = latin1.decode(head);
        if (!text.contains('\r\n\r\n')) return;
        sub.pause();
        final target = text.split(' ')[1];
        tunnels.add(target);
        final port = int.parse(target.split(':').last);
        final upstream = await Socket.connect('localhost', port);
        client.add(latin1.encode('HTTP/1.1 200 Connection established\r\n\r\n'));
        sub
          ..onData(upstream.add)
          ..onDone(upstream.destroy)
          ..resume();
        upstream.listen(client.add, onDone: client.destroy, onError: (Object _) => client.destroy());
      });
    });
    return (proxy, tunnels);
  }

  test('a request over HTTP/2: status, body and headers (names in lower case, no connection headers)', () async {
    if (!openssl) return markTestSkipped('no openssl');
    final seen = <Map<String, String>>[];
    final server = await h2Server(seen, extra: {'x-answer': 'yes'});
    addTearDown(server.close);
    final http = Http2LiveHttp(context: clientContext);
    final response = await http.send(
      LiveRequest(
        site: 'kick',
        url: Uri.parse('https://localhost:${server.port}/stream/livestreams/en?page=1&limit=2'),
        headers: const {'User-Agent': 'probe', 'Accept': 'application/json', 'Connection': 'keep-alive'},
      ),
    );
    expect(response.status, 200);
    expect(response.text, '{"ok":true}');
    expect(response.header('x-answer'), 'yes');
    expect(seen.single[':path'], '/stream/livestreams/en?page=1&limit=2');
    expect(seen.single[':method'], 'GET');
    expect(seen.single['user-agent'], 'probe');
    expect(seen.single.containsKey('connection'), isFalse);
  });

  test('through an HTTP proxy: a CONNECT tunnel, then the same answer; a 403 is a response', () async {
    if (!openssl) return markTestSkipped('no openssl');
    final seen = <Map<String, String>>[];
    final server = await h2Server(seen, status: 403, body: '{"error":"Request blocked by security policy."}');
    addTearDown(server.close);
    final (proxy, tunnels) = await connectProxy();
    addTearDown(proxy.close);
    final http = Http2LiveHttp(
      proxy: FixedProxyPolicy(global: HttpProxyRoute('127.0.0.1', proxy.port)),
      context: clientContext,
    );
    final response = await http.send(
      LiveRequest(site: 'kick', url: Uri.parse('https://localhost:${server.port}/api/v1/categories')),
    );
    expect(tunnels.single, 'localhost:${server.port}');
    expect(response.status, 403);
    expect(response.text, contains('security policy'));
  });

  test('a server without HTTP/2 is a protocol failure, not a hang', () async {
    if (!openssl) return markTestSkipped('no openssl');
    final context = SecurityContext()
      ..useCertificateChain('${folder.path}/cert.pem')
      ..usePrivateKey('${folder.path}/key.pem')
      ..setAlpnProtocols(['http/1.1'], true);
    final server = await SecureServerSocket.bind('localhost', 0, context);
    addTearDown(server.close);
    server.listen((socket) => socket.listen((_) {}));
    final http = Http2LiveHttp(context: clientContext);
    await expectLater(
      http.send(LiveRequest(site: 'kick', url: Uri.parse('https://localhost:${server.port}/'))),
      throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.protocol)),
    );
  });

  test('cancel and timeout end the request', () async {
    if (!openssl) return markTestSkipped('no openssl');
    final server = await h2Server([], delay: const Duration(seconds: 5));
    addTearDown(server.close);
    final http = Http2LiveHttp(context: clientContext);
    final url = Uri.parse('https://localhost:${server.port}/slow');
    final cancel = CancelToken();
    final cancelled = http.send(LiveRequest(site: 'kick', url: url, cancel: cancel));
    Timer(const Duration(milliseconds: 200), cancel.cancel);
    await expectLater(
      cancelled,
      throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
    );
    await expectLater(
      http.send(LiveRequest(site: 'kick', url: url, timeout: const Duration(milliseconds: 300))),
      throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.timeout)),
    );
  });
}
