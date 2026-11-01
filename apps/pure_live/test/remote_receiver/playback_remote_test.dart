import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/shared/remote/playback_remote.dart';
import 'package:pure_live/shared/remote/remote_client.dart';

void main() {
  test('two paired app clients control the visible target and stale pages cannot receive input', () async {
    final remote = PlaybackRemote();
    final events = <String>[];
    var firstVisible = true;
    final first = RemotePlaybackTarget(
      available: () => firstVisible,
      snapshot: () => {
        'title': 'first',
        'commands': ['pause', 'volume'],
      },
      execute: (command, value) async {
        events.add('first:$command:$value');
        return true;
      },
    );
    final second = RemotePlaybackTarget(
      available: () => !firstVisible,
      snapshot: () => {
        'title': 'second',
        'commands': ['pause'],
      },
      execute: (command, value) async {
        events.add('second:$command');
        return true;
      },
    );
    remote
      ..register(first)
      ..register(second);
    await remote.start(bind: InternetAddress.loopbackIPv4, discovery: false);
    final a = PlaybackRemoteClient(Uri.parse('http://127.0.0.1:${remote.port}/'));
    final b = PlaybackRemoteClient(a.uri);
    try {
      await a.pair(remote.code);
      await b.pair(remote.code);
      expect(remote.pairedCount, 2);
      expect((await a.status())['targetId'], first.id);
      await a.command(first.id, 'volume', value: 0.3);
      firstVisible = false;
      await expectLater(a.command(first.id, 'pause'), throwsA(isA<HttpException>()));
      expect((await b.status())['targetId'], second.id);
      await b.command(second.id, 'pause');
      remote.unregister(second);
      expect((await a.status())['targetId'], isNull);
      expect(events, ['first:volume:0.3', 'second:pause']);
      await a.disconnect();
      expect(remote.pairedCount, 1);
      await b.command(first.id, 'pause').then<void>((_) => fail('removed target accepted'), onError: (Object _) {});
    } finally {
      a.close();
      b.close();
      await remote.stop();
      remote.dispose();
    }
  });

  test('revocation and twelve-hour expiry invalidate previously issued sessions', () async {
    var now = DateTime.utc(2026);
    final remote = PlaybackRemote(now: () => now);
    await remote.start(bind: InternetAddress.loopbackIPv4, discovery: false);
    final client = PlaybackRemoteClient(Uri.parse('http://127.0.0.1:${remote.port}/'));
    try {
      await client.pair(remote.code);
      remote.revoke();
      await expectLater(client.status(), throwsA(isA<HttpException>()));
      expect(client.paired, isFalse);
      await client.pair(remote.code);
      now = now.add(const Duration(hours: 12));
      await expectLater(client.status(), throwsA(isA<HttpException>()));
      expect(remote.pairedCount, 0);
    } finally {
      client.close();
      await remote.stop();
      remote.dispose();
    }
  });

  test('revoking while a link resolves prevents late playback navigation', () async {
    final entered = Completer<void>();
    final resolve = Completer<void>();
    var opened = false;
    final remote = PlaybackRemote()
      ..onLink = (text, authorized) async {
        entered.complete();
        await resolve.future;
        if (!authorized()) return false;
        opened = true;
        return true;
      };
    await remote.start(bind: InternetAddress.loopbackIPv4, discovery: false);
    final client = PlaybackRemoteClient(Uri.parse('http://127.0.0.1:${remote.port}/'));
    try {
      await client.pair(remote.code);
      final sending = client.sendLink('https://www.douyu.com/1');
      await entered.future;
      remote.revoke();
      resolve.complete();
      await expectLater(sending, throwsA(isA<HttpException>()));
      expect(opened, isFalse);
    } finally {
      client.close();
      await remote.stop();
      remote.dispose();
    }
  });

  test('native controller requests mirror the receiver non-persistent connection contract', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestedPersistence = <bool>[];
    server.listen((request) async {
      requestedPersistence.add(request.persistentConnection);
      await request.drain<void>();
      final response = request.response
        ..persistentConnection = false
        ..headers.contentType = ContentType.json;
      response.write(jsonEncode(request.uri.path == '/api/pair' ? {'token': 'a' * 43} : <String, Object?>{}));
      await response.close();
    });
    final client = PlaybackRemoteClient(Uri.parse('http://127.0.0.1:${server.port}/'));
    try {
      await client.pair('123456');
      for (var i = 0; i < 8; i++) {
        await client.status();
      }
      expect(requestedPersistence, hasLength(9));
      expect(
        requestedPersistence,
        everyElement(isFalse),
        reason: 'the receiver closes each response; do not offer old sockets back to a keep-alive pool',
      );
    } finally {
      client.close();
      await server.close(force: true);
    }
  });

  test('fragmented just-over-limit POST returns400 after a bounded body drain', () async {
    final remote = PlaybackRemote();
    await remote.start(bind: InternetAddress.loopbackIPv4, discovery: false);
    final http = HttpClient();
    try {
      final request = await http.postUrl(Uri.parse('http://127.0.0.1:${remote.port}/api/pair'));
      request
        ..persistentConnection = false
        ..headers.contentType = ContentType.json
        ..write('x' * 16384);
      await request.flush();
      await Future<void>.delayed(const Duration(seconds: 1));
      request.write('x');
      await request.flush();
      await Future<void>.delayed(const Duration(seconds: 1));
      final response = await request.close();
      expect(response.statusCode, HttpStatus.badRequest);
      await response.drain<void>();
      expect(remote.pairedCount, 0);
    } finally {
      http.close(force: true);
      await remote.stop();
      remote.dispose();
    }
  });

  test('a body beyond the drain budget is rejected and leaves the receiver usable', () async {
    final remote = PlaybackRemote();
    await remote.start(bind: InternetAddress.loopbackIPv4, discovery: false);
    final http = HttpClient();
    final client = PlaybackRemoteClient(Uri.parse('http://127.0.0.1:${remote.port}/'));
    try {
      try {
        final request = await http.postUrl(Uri.parse('http://127.0.0.1:${remote.port}/api/pair'));
        request
          ..persistentConnection = false
          ..headers.contentType = ContentType.json
          ..write('x' * 200000);
        final response = await request.close();
        expect(response.statusCode, HttpStatus.badRequest);
        await response.drain<void>();
      } on HttpException {
        // Rejecting beyond the bounded read budget may close the transport.
      } on SocketException {
        // The peer may still be writing when the read budget is exhausted.
      }
      expect(remote.pairedCount, 0);
      await client.pair(remote.code);
      expect(client.paired, isTrue);
    } finally {
      client.close();
      http.close(force: true);
      await remote.stop();
      remote.dispose();
    }
  });

  test('browser origin, wrong codes, body limits and invalid commands are enforced', () async {
    var now = DateTime.utc(2026);
    final remote = PlaybackRemote(now: () => now);
    var executed = 0;
    final target = RemotePlaybackTarget(
      available: () => true,
      snapshot: () => {
        'commands': ['pause'],
      },
      execute: (_, _) async {
        executed++;
        return true;
      },
    );
    remote.register(target);
    await remote.start(bind: InternetAddress.loopbackIPv4, discovery: false);
    final http = HttpClient();
    Future<({int status, String body})> send(
      String path, {
      String? origin,
      String? token,
      Object? data,
      String? raw,
    }) async {
      final request = await http.postUrl(Uri.parse('http://127.0.0.1:${remote.port}/api/$path'));
      request.persistentConnection = false;
      request.headers.contentType = ContentType.json;
      if (origin != null) request.headers.set('origin', origin);
      if (token != null) request.headers.set('authorization', 'Bearer $token');
      request.write(raw ?? jsonEncode(data));
      final response = await request.close();
      return (status: response.statusCode, body: await utf8.decoder.bind(response).join());
    }

    try {
      expect((await send('pair', origin: 'https://invalid.example', data: {'code': remote.code})).status, 403);
      expect((await send('pair', raw: 'x' * 16385)).status, 400);
      for (var n = 0; n < 10; n++) {
        expect((await send('pair', data: {'code': '000000'})).status, 403);
      }
      expect((await send('pair', data: {'code': remote.code})).status, 429);
      now = now.add(const Duration(minutes: 1));
      final pair = await send('pair', data: {'code': remote.code});
      expect(pair.status, 200);
      final token = (jsonDecode(pair.body) as Map)['token'] as String;
      expect((await send('command', token: token, data: {'targetId': target.id, 'command': 'delete'})).status, 400);
      expect(
        (await send('command', token: token, data: {'targetId': target.id, 'command': 'volume', 'value': 2})).status,
        400,
      );
      expect((await send('command', data: {'targetId': target.id, 'command': 'pause'})).status, 401);
      expect(executed, 0);
    } finally {
      http.close(force: true);
      await remote.stop();
      remote.dispose();
    }
  });

  test('controller addresses stay on literal LAN origins without redirects or credentials', () {
    expect(remoteControlUri('127.0.0.1:1234').toString(), 'http://127.0.0.1:1234/');
    expect(remoteControlUri('http://192.168.1.2:1234/'), isNotNull);
    for (final address in [
      'https://192.168.1.2/',
      'http://example.com/',
      'http://8.8.8.8/',
      'http://user:password@192.168.1.2/',
      'http://192.168.1.2/path',
      'http://192.168.1.2/?token=x',
    ]) {
      expect(remoteControlUri(address), isNull, reason: address);
    }
  });
}
