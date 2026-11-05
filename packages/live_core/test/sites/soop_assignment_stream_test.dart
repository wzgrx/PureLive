import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

class PendingBodyHttp implements LiveHttp {
  new(List<List<int>> chunks) {
    body = StreamController<List<int>>(
      onListen: () {
        chunks.forEach(body.add);
      },
      onCancel: () {
        cancelled = true;
      },
    );
  }
  late final StreamController<List<int>> body;
  bool cancelled = false;
  @override
  Future<LiveResponse> send(LiveRequest r) async {
    if (r.url.host == 'manager.invalid') return await (await open(r)).collect();
    return LiveResponse(
      status: 200,
      url: r.url,
      bytes: utf8.encode(
        jsonEncode({
          'CHANNEL': {'RESULT': 1, 'AID': 'synthetic-key'},
        }),
      ),
    );
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest r) async =>
      LiveStreamedResponse(status: 200, url: r.url, body: body.stream);
  @override
  void close() {
    unawaited(body.close());
  }
}

LiveRoom room() => LiveRoom(
  platform: 'soop',
  roomId: 'creator',
  data: SoopRoomData(
    bno: '123',
    rmd: 'https://manager.invalid',
    cdn: 'gcp_cdn',
    presets: const [SoopPreset(name: 'sd')],
  ),
);
void main() {
  test('RMD complete JSON is consumed and connection cancelled without waiting for missing HTTP EOF', () async {
    final bytes = utf8.encode(
      jsonEncode({'result': 1, 'view_url': 'https://cdn.example/live.m3u8', 'note': '中文 } [ " quote'}),
    );
    final http = PendingBodyHttp([bytes.sublist(0, 7), bytes.sublist(7, 35), bytes.sublist(35)]);
    final site = SoopSite(http, cdnCandidates: const []);
    try {
      final result = await site
          .resolvePlayUrls(
            detail: room(),
            quality: const LivePlayQuality(quality: '标清', id: 'sd'),
          )
          .timeout(const Duration(seconds: 1));
      expect(result.urls, ['https://cdn.example/live.m3u8?aid=synthetic-key']);
      expect(
        http.cancelled,
        isTrue,
        reason: 'the endpoint keeps its unframed response alive about10s; release after the complete object',
      );
    } finally {
      http.close();
    }
  });
  test('oversized or invalid assignment objects cancel their streams instead of inventing a line', () async {
    for (final bytes in [List<int>.filled(65537, 32), utf8.encode('not JSON')]) {
      final http = PendingBodyHttp([bytes]);
      try {
        await expectLater(
          SoopSite(http, cdnCandidates: const []).resolvePlayUrls(
            detail: room(),
            quality: const LivePlayQuality(quality: '标清', id: 'sd'),
          ),
          throwsA(isA<ApiChanged>()),
        );
        expect(http.cancelled, isTrue);
      } finally {
        http.close();
      }
    }
  });
}
