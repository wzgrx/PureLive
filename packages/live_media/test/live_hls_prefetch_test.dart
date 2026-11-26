import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

void main() {
  test('on-demand HLS and ordinary FLV keep their direct transport', () async {
    final opener = MediaOpener();
    addTearDown(opener.close);
    for (final (format, demand, site) in [
      (StreamFormat.hls, true, 'soop'),
      (StreamFormat.flv, false, 'soop'),
      (StreamFormat.hls, false, 'bilibili'),
    ]) {
      final input = await opener.open(
        LineSource(LivePlayLine('https://media.example.test/live', format: format)),
        site: site,
        onDemand: demand,
      );
      expect(input.route, MediaRoute.direct);
      expect(input.onDemand, demand);
      await input.close();
    }
  });

  for (final site in ['soop', 'twitch', 'youtube']) {
    test('issue240: $site starts bounded parallel HLS reads before the serial engine asks', () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final started = Completer<void>();
      final release = Completer<void>();
      final headers = <String?>[];
      var active = 0;
      var peak = 0;
      final subscription = upstream.listen((request) async {
        final response = request.response;
        if (request.uri.path.endsWith('.m3u8')) {
          response.write(
            '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:10\n'
            '#EXTINF:2,\n10.ts\n#EXTINF:2,\n11.ts\n#EXTINF:2,\n12.ts\n#EXTINF:2,\n13.ts\n',
          );
        } else if (request.uri.path.endsWith('/10.ts')) {
          response.add([1, 2, 3]);
        } else {
          headers.add(request.headers.value('x-purelive-fixture'));
          active++;
          if (active > peak) peak = active;
          if (active == 3 && !started.isCompleted) started.complete();
          await release.future;
          active--;
          response.add([1, 2, 3]);
        }
        await response.close().catchError((Object _) {});
      });
      final opener = MediaOpener();
      final client = HttpClient();
      MediaInput? input;
      addTearDown(() async {
        if (!release.isCompleted) release.complete();
        client.close(force: true);
        await input?.close();
        await opener.close();
        await subscription.cancel();
        await upstream.close(force: true);
      });
      input = await opener.open(
        LineSource(
          LivePlayLine(
            'http://127.0.0.1:${upstream.port}/live.m3u8',
            format: StreamFormat.hls,
            headers: const {'x-purelive-fixture': 'generated'},
          ),
        ),
        site: site,
      );
      final response = await (await client.getUrl(input.uri)).close();
      final playlist = await utf8.decoder.bind(response).join();
      // The existing window waits for a selected variant to deliver a
      // segment and reload; probing an unselected rendition must not prefetch.
      final first = const LineSplitter()
          .convert(playlist)
          .firstWhere((line) => line.isNotEmpty && !line.startsWith('#'));
      await (await (await client.getUrl(input.uri.resolve(first))).close()).drain<void>();
      await (await (await client.getUrl(input.uri)).close()).drain<void>();
      await started.future.timeout(const Duration(seconds: 2));
      expect(peak, 3);
      expect(input.route, MediaRoute.hlsRelay);
      expect(input.private, isTrue);
      expect(input.proxyUrl, isEmpty);
      expect(headers, everyElement('generated'));
      await input.close();
      expect(input.isUsable, isFalse);
      final stopped = headers.length;
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(headers, hasLength(stopped));
    });
  }
}
