import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_vod/live_vod.dart';
import 'package:test/test.dart';

String envelope(Object data) => jsonEncode({'code': 0, 'data': data});
void main() {
  test('Douyu actual replay shape keeps start_time and falls through a zero numeric duration', () {
    final video = DouyuVodVideo.fromJson(const {
      'hash_id': 'Replay0000000001',
      'title': '回放',
      'start_time': 1793595515,
      'video_duration': 0,
      'video_str_duration': '120:01',
    });
    expect(video.duration, const Duration(hours: 2, seconds: 1));
    expect(video.publishedAt?.millisecondsSinceEpoch, 1793595515000);
  });
  test('only explicit replay collections owned by this creator enter the list; namespace ids stay distinct', () {
    Map<String, Object> row(int id, String name, {int mid = 7, int updated = 1, bool season = false}) => {
      'meta': {'mid': mid, season ? 'season_id' : 'series_id': id, 'name': name, 'mtime': updated},
    };
    final result = BilibiliReplayApi.parseCollections(
      envelope({
        'items_lists': {
          'page': {'total': 41},
          'series_list': [row(2, '直播回放', updated: 3), row(3, '日常视频'), row(4, '直播录像', mid: 9), row(5, '直播录像')],
          'seasons_list': [row(2, '直播回看', season: true, updated: 2)],
        },
      }),
      mid: 7,
      page: 1,
    );
    expect(result.items.map((v) => v.key), ['series:2', 'season:2', 'series:5']);
    expect(result.hasMore, isTrue);
  });
  test('pages preserve dates and duration, remove duplicate/malformed ids, and sort newest first', () {
    Map<String, Object> row(String id, int time) => {'bvid': id, 'title': '直播回放', 'duration': 36000, 'pubdate': time};
    final result = BilibiliReplayApi.parsePage(
      envelope({
        'page': {'total': 21},
        'archives': [row('BV1234567890', 10), row('BV1234567891', 20), row('BV1234567891', 20), row('invalid', 30)],
      }),
      page: 1,
    );
    expect(result.items.map((v) => v.bvid), ['BV1234567891', 'BV1234567890']);
    expect(result.items.first.duration, const Duration(hours: 10));
    expect(result.hasMore, isTrue);
    expect(() => BilibiliReplayApi.parsePage(envelope({}), page: 1), throwsA(isA<ApiChanged>()));
    expect(() => BilibiliReplayApi.parseCollections('{"code":-352}', mid: 7, page: 1), throwsA(isA<RiskControl>()));
  });
  test('room identities read distinct official envelopes; room numbers are never guessed as uids', () {
    expect(ReplayIdentityApi.identity('{"data":{"profileInfo":{"uid":123}}}', platform: SiteIds.huya), '123');
    expect(
      ReplayIdentityApi.identity('{"room":{"up_id":"Author001","owner_uid":123}}', platform: SiteIds.douyu),
      'Author001',
    );
    expect(ReplayIdentityApi.identity(envelope({'uid': 456}), platform: SiteIds.bilibili), '456');
    expect(
      () => ReplayIdentityApi.identity(envelope({'room_id': 456}), platform: SiteIds.bilibili),
      throwsA(isA<ApiChanged>()),
    );
    expect(
      () => ReplayIdentityApi.identity(envelope({'uid': 0}), platform: SiteIds.bilibili),
      throwsA(isA<ApiChanged>()),
    );
  });
  test('metadata requests keep platform/proxy identity, cancellation and host-specific cookies', () async {
    final http = _Http();
    final cancel = CancelToken();
    final api = BilibiliReplayApi(BilibiliVodClient(http));
    await api.collections(7, cancel: cancel);
    await api.list(7, const ReplayCollection(id: 2, name: '直播回放'), page: 2, cancel: cancel);
    final requests = http.requests.where((r) => r.url.path != '/x/frontend/finger/spi').toList();
    expect(requests.every((r) => r.site == SiteIds.bilibili && identical(r.cancel, cancel)), isTrue);
    expect(requests.last.url.queryParameters['sort'], 'desc');
    expect(requests.last.url.queryParameters['pn'], '2');
    expect(requests.last.headers['referer'], 'https://space.bilibili.com/7/');
    expect(() => api.collections(0), throwsFormatException);
  });
}

final class _Http implements LiveHttp {
  final requests = <LiveRequest>[];
  @override
  Future<LiveResponse> send(LiveRequest r) async {
    requests.add(r);
    final data = r.url.path.endsWith('/spi')
        ? {'b_3': 'guest', 'b_4': 'guest4'}
        : r.url.path.endsWith('seasons_series_list')
        ? {
            'items_lists': {
              'series_list': <Object>[],
              'seasons_list': <Object>[],
              'page': {'total': 0},
            },
          }
        : {
            'archives': <Object>[],
            'page': {'total': 0},
          };
    return LiveResponse(url: r.url, status: 200, bytes: utf8.encode(envelope(data)));
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest r) => throw UnimplementedError();
  @override
  void close() {}
}
