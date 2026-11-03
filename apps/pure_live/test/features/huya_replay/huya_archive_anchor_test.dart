import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/shared/rooms/archive/huya_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive/huya_manifest_entry.dart';

import '../live_play/live_play_support.dart';
import 'huya_archive_support.dart';

final class _AnchoredSource implements HuyaArchiveSource, HuyaArchiveAnchorSource {
  final fake = FakeHuyaArchive();
  Completer<HuyaArchiveAnchor?>? pending;
  @override
  Future<HuyaArchiveList> list(String uid, {int page = 1, CancelToken? cancel}) =>
      fake.list(uid, page: page, cancel: cancel);
  @override
  Future<List<HuyaArchiveQuality>> qualities(String id, {CancelToken? cancel}) => fake.qualities(id, cancel: cancel);
  @override
  Future<HuyaArchiveAnchor?> anchor(String url, Duration at, {CancelToken? cancel}) async => pending == null
      ? HuyaArchiveAnchor(
          playlist:
              '#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nhttps://record.example.test/target.ts\n#EXT-X-ENDLIST\n',
          offset: at - const Duration(seconds: 2),
          start: const Duration(seconds: 2),
          duration: const Duration(hours: 2),
        )
      : await pending!.future;
}

final class _Upstream implements HlsUpstream {
  bool closed = false;
  Map<String, String>? headers;
  @override
  Future<HlsUpstreamResponse> get(Uri url, Map<String, String> headers) async {
    this.headers = headers;
    return HlsUpstreamResponse(status: 200, url: url, body: Stream.value([1, 2, 3]), contentLength: 3);
  }

  @override
  void close() {
    closed = true;
  }
}

final class _RealHttp extends HttpOverrides;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a seek reopens near its segment and maps native position/duration to the full recording', () async {
    final engine = FakeEngine();
    final upstreams = <_Upstream>[];
    final entry = HuyaManifestEntry(
      upstreamFor: (_) {
        final u = _Upstream();
        upstreams.add(u);
        return u;
      },
    );
    final progress = HuyaArchiveProgress(read: () async => null, write: (_) async {});
    final controller = HuyaArchiveController(
      source: _AnchoredSource(),
      session: fakeSession(engine),
      video: firstArchive,
      progress: progress,
      manifestEntry: entry,
    );
    final client = _RealHttp().createHttpClient(null);
    try {
      await controller.open(firstArchive.id);
      await controller.setRate(1.75);
      await controller.session.setVolume(.27);
      await controller.session.pause();
      await controller.seek(const Duration(seconds: 3905));
      expect(engine.opens.last.start, const Duration(seconds: 2));
      expect(engine.opens.last.uri.host, '127.0.0.1');
      expect(engine.opens.last.proxyUrl, isEmpty);
      expect(controller.duration, const Duration(hours: 2));
      expect(controller.position, const Duration(seconds: 3905));
      expect(controller.session.state.status, PlaybackStatus.paused);
      expect(controller.session.state.volume, .27);
      expect(engine.rates.last, 1.75);
      engine.emit(const EnginePosition(Duration(seconds: 2)));
      await pumpEventQueue();
      await controller.session.resume();
      engine.emit(const EnginePosition(Duration(seconds: 4)));
      await pumpEventQueue();
      expect(controller.position, const Duration(seconds: 3907));
      final response = await (await client.getUrl(engine.opens.last.uri)).close();
      final text = await utf8.decodeStream(response);
      final segment = text.split('\n').firstWhere((s) => s.startsWith('http://127.0.0.1:'));
      final bytes = await (await (await client.getUrl(
        Uri.parse(segment),
      )).close()).fold<List<int>>([], (a, b) => [...a, ...b]);
      expect(bytes, [1, 2, 3]);
      expect(upstreams.single.headers!['referer'], 'https://www.huya.com/');
      final previous = engine.opens.last.uri;
      await controller.seek(const Duration(seconds: 100));
      expect(upstreams.first.closed, isTrue);
      expect((await (await client.getUrl(previous)).close()).statusCode, 404);
    } finally {
      client.close(force: true);
      controller.dispose();
      await controller.retirement;
    }
    expect(upstreams.every((u) => u.closed), isTrue);
  });
  test('retirement cancels a delayed anchor without a new native open', () async {
    final engine = FakeEngine();
    final source = _AnchoredSource();
    final controller = HuyaArchiveController(
      source: source,
      session: fakeSession(engine),
      video: firstArchive,
      progress: HuyaArchiveProgress(read: () async => null, write: (_) async {}),
    );
    await controller.open(firstArchive.id);
    source.pending = Completer();
    final seek = controller.seek(const Duration(seconds: 90));
    await pumpEventQueue();
    controller.dispose();
    source.pending!.complete(null);
    await seek;
    await controller.retirement;
    expect(engine.opens, hasLength(1));
  });
}
