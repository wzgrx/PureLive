import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

class Http implements LiveHttp {
  final calls = <LiveRequest>[];
  bool allFail = false;
  int active = 0;
  int maxActive = 0;
  @override
  Future<LiveResponse> send(LiveRequest r) async {
    calls.add(r);
    Object body;
    if (r.url.path.endsWith('player_live_api.php')) {
      body = {
        'CHANNEL': {'RESULT': 1, 'AID': 'synthetic-key'},
      };
    } else {
      final cdn = r.url.queryParameters['return_type'];
      active++;
      if (active > maxActive) maxActive = active;
      await Future<void>.delayed(const Duration(seconds: 1));
      active--;
      body = allFail || cdn == 'gcp_cdn'
          ? {'result': 0}
          : {
              'result': 1,
              'view_url': 'https://${cdn == 'azure_cdn' || cdn == 'aws_cf' ? 'global' : cdn}.sooplive.com/stream.m3u8',
            };
    }
    return LiveResponse(status: 200, bytes: utf8.encode(jsonEncode(body)), url: r.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest r) => throw UnimplementedError();
  @override
  void close() {}
}

LiveRoom room() => LiveRoom(
  platform: 'soop',
  roomId: 'creator',
  data: SoopRoomData(
    bno: '123',
    rmd: 'https://livestream-manager.sooplive.com',
    cdn: 'gcp_cdn',
    presets: const [SoopPreset(name: 'hd', codec: 'avc')],
  ),
);
void main() {
  test('issue195: failed assigned CDN retains distinct official alternatives, one aid, stable order and bounded concurrency', () async {
    final http = Http();
    final site = SoopSite(http);
    final result = await site.resolvePlayUrls(
      detail: room(),
      quality: const LivePlayQuality(quality: '高清', id: 'hd'),
    );
    expect(result.lines.map((l) => l.lineId), [
      'gs_cdn_mobile_web',
      'gs_cdn_pc_web',
      'lg_cdn_pc_web',
      'lg_cdn_mobile_web',
      'azure_cdn',
    ]);
    expect(result.lines.every((l) => l.url.endsWith('aid=synthetic-key')), isTrue);
    expect(result.lines.every((l) => l.codec == 'avc' && l.format == StreamFormat.hls), isTrue);
    expect(http.calls.where((r) => r.url.path.endsWith('player_live_api.php')), hasLength(1));
    expect(http.calls.where((r) => r.url.path.endsWith('broad_stream_assign.html')), hasLength(7));
    expect(http.maxActive, lessThanOrEqualTo(3));
    expect(result.appliedQualityData, 'hd');
  });
  test('issue195: mobile assignments stay mobile; every failed assignment reports failure', () async {
    expect(SoopApi.returnType('gs_cdn_mobile_web'), 'gs_cdn_mobile_web');
    final http = Http()..allFail = true;
    await expectLater(
      SoopSite(http).resolvePlayUrls(
        detail: room(),
        quality: const LivePlayQuality(quality: '高清', id: 'hd'),
      ),
      throwsA(isA<StreamUnavailable>()),
    );
  });
}
