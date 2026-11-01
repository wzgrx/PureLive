import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/shared/remote/local_ice_binding.dart';
import 'package:pure_live/shared/remote/playback_remote.dart';
import 'package:pure_live/shared/remote/remote_client.dart';

Uint8List request() => Uint8List.fromList([0, 1, 0, 0, 0x21, 0x12, 0xa4, 0x42, ...List.generate(12, (i) => i)]);

void main() {
  test('binding keeps transaction identity and XOR-encodes only the observed transport address', () {
    final reply = LocalIceBinding.response(request(), InternetAddress('192.0.2.1'), 32853)!;
    expect(reply.length, 32);
    expect(reply.take(8), [1, 1, 0, 12, 0x21, 0x12, 0xa4, 0x42]);
    expect(reply.sublist(8, 20), List.generate(12, (i) => i));
    expect(reply.sublist(20), [0, 0x20, 0, 8, 0, 1, 0xa1, 0x47, 0xe1, 0x12, 0xa6, 0x43]);
  });

  test('truncated, oversized, non-binding, bad-cookie and required-attribute packets are discarded', () {
    final malformed = <Uint8List>[
      Uint8List(0),
      request().sublist(0, 19),
      Uint8List.fromList([...request(), ...List.filled(600, 0)]),
      request()..[0] = 1,
      request()..[4] = 0,
      request()..[3] = 1,
      Uint8List.fromList([...request()..[3] = 4, 0, 6, 0, 0]),
      Uint8List.fromList([...request()..[3] = 4, 0x80, 0x22, 0, 8]),
    ];
    for (final packet in malformed) {
      expect(LocalIceBinding.response(packet, InternetAddress.loopbackIPv4, 12345), isNull);
    }
    final optional = Uint8List.fromList([...request()..[3] = 8, 0x80, 0x22, 0, 1, 65, 0, 0, 0]);
    expect(LocalIceBinding.response(optional, InternetAddress.loopbackIPv4, 12345), isNotNull);
    expect(LocalIceBinding.response(request(), InternetAddress.loopbackIPv6, 12345), isNull);
  });

  test('actual receiver binding is available only to paired peers and closes with the receiver', () async {
    final receiver = PlaybackRemote();
    await receiver.start(bind: InternetAddress.loopbackIPv4, discovery: false);
    final client = PlaybackRemoteClient(Uri.parse('http://127.0.0.1:${receiver.port}/'));
    final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final packets = <Datagram>[];
    final subscription = socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final packet = socket.receive();
        if (packet != null) packets.add(packet);
      }
    });
    try {
      await client.pair(receiver.code);
      final port = (await client.status())['localIcePort'] as int;
      socket.send(request(), InternetAddress.loopbackIPv4, port);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(packets, hasLength(1));
      final reply = ByteData.sublistView(packets.single.data);
      expect(reply.getUint16(26) ^ 0x2112, socket.port);
      receiver.revoke();
      packets.clear();
      socket.send(request(), InternetAddress.loopbackIPv4, port);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(packets, isEmpty, reason: 'pairing revocation also revokes address binding');
      await client.pair(receiver.code);
      socket.send(request(), InternetAddress.loopbackIPv4, port);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(packets, hasLength(1));
      await receiver.stop();
      final rebound = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, port);
      rebound.close();
    } finally {
      await subscription.cancel();
      socket.close();
      client.close();
      await receiver.stop();
      receiver.dispose();
    }
  });
}
