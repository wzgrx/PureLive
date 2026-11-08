import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

final class _Segments implements HlsUpstream {
  final requests = <Uri>[];
  bool closed = false;
  @override
  Future<HlsUpstreamResponse> get(Uri url, Map<String, String> headers) async {
    requests.add(url);
    return HlsUpstreamResponse(status: 200, url: url, body: Stream.value(utf8.encode('one segment')));
  }

  @override
  void close() => closed = true;
}

void main() {
  test('a finite index stays private and forwards only its selected on-demand segments', () async {
    final upstream = _Segments();
    final relay = await LoopbackRelay.start(hlsUpstream: (_) => upstream);
    addTearDown(relay.close);
    final opener = MediaOpener(relay: () async => relay);
    final input = await opener.open(
      const LineSource(
        LivePlayLine('https://video.example.test/first.ts?private=synthetic', format: StreamFormat.hls),
        vodPlaylist:
            '#EXTM3U\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-TARGETDURATION:4\n'
            '#EXTINF:4,\nhttps://video.example.test/first.ts?private=synthetic\n#EXT-X-ENDLIST\n',
      ),
      site: SiteIds.chzzk,
      onDemand: true,
      start: const Duration(seconds: 2),
    );
    addTearDown(input.close);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    Future<String> read(Uri uri) async {
      final response = await (await client.getUrl(uri)).close();
      expect(response.statusCode, HttpStatus.ok);
      return await utf8.decoder.bind(response).join();
    }

    final playlist = await read(input.uri);
    expect(input.private, isTrue);
    expect(input.start, const Duration(seconds: 2));
    expect(playlist, isNot(contains('private=synthetic')));
    expect(upstream.requests, isEmpty);
    final segment = playlist.split('\n').firstWhere((line) => line.isNotEmpty && !line.startsWith('#'));
    expect(await read(input.uri.resolve(segment)), 'one segment');
    expect(upstream.requests.single.queryParameters, {'private': 'synthetic'});
    await input.close();
    expect(upstream.closed, isTrue);
  });
}
