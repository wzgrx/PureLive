import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_vod/live_vod.dart';
import 'package:test/test.dart';

Map<String, dynamic> detail({List<Object>? files, String adult = 'pass', bool paid = false, String id = '123'}) => {
  'result': 1,
  'data': {
    'title_no': id,
    'title': 'Replay',
    'bj_id': 'presenter',
    'writer_nick': 'Creator',
    'adult_status': adult,
    'is_paid': paid,
    'files': files ?? [file(2), file(1)],
  },
};
Map<String, Object?> file(int order, {String host = 'vod-archive-global-cdn-z02.sooplive.com'}) => {
  'file_order': order,
  'duration': 600000,
  'file': 'https://$host/a.mp4',
  'quality_info': [
    {'name': 'original', 'label': '1080p', 'file': 'https://$host/1080.m3u8'},
    {'name': 'hd4k', 'label': '720p', 'file': 'https://$host/720.m3u8'},
    {'name': 'bad', 'label': 'malicious', 'file': 'https://sooplive.com.evil.invalid/a.m3u8'},
  ],
};
void main() {
  test('official author/recording URLs do not confuse station, video or foreign host identities', () {
    expect(SoopArchiveApi.authorFromText('https://www.sooplive.com/station/creator/vod/'), 'creator');
    expect(SoopArchiveApi.authorFromText('https://play.sooplive.co.kr/creator/123'), 'creator');
    expect(SoopArchiveApi.authorFromText('https://www.sooplive.com.evil.invalid/station/creator/vod/'), isNull);
    expect(SoopArchiveApi.authorFromText('https://vod.sooplive.com/player/123'), isNull);
    expect(SoopArchiveApi.videoFromText('https://vod.sooplive.com/player/123'), '123');
    expect(SoopArchiveApi.videoFromText('https://vod.sooplive.com@evil.invalid/player/123'), isNull);
  });
  test('station pagination survives dropped rows and dates use KST', () {
    final root = <String, dynamic>{
      'meta': {'current_page': 1, 'last_page': 3},
      'data': [
        {
          'title_no': 123,
          'title_name': 'A &amp; B',
          'user_id': 'creator',
          'user_nick': 'C',
          'reg_date': '2026-01-01 00:30:00',
          'ucc': {'total_file_duration': 65000},
        },
        {'title_no': 124, 'title_name': 'foreign', 'user_id': 'other', 'ucc': <String, Object?>{}},
        {'title_no': 123, 'title_name': 'duplicate', 'user_id': 'creator', 'ucc': <String, Object?>{}},
      ],
    };
    final page = SoopArchiveApi.parseList(root, author: 'creator', page: 1);
    expect(page.hasMore, isTrue);
    expect(page.videos, hasLength(1));
    expect(page.videos.single.title, 'A & B');
    expect(page.videos.single.duration, const Duration(seconds: 65));
    expect(page.videos.single.publishedAt, DateTime.utc(2025, 12, 31, 15, 30));
    expect(() => SoopArchiveApi.parseList(root, author: 'creator', page: 2), throwsA(isA<ApiChanged>()));
  });
  test('only actual, ordered parts and server renditions are offered, without guessed URLs', () {
    final parts = SoopArchiveApi.parseDetail(detail(), id: '123');
    expect(parts.map((p) => p.id), ['123:1', '123:2']);
    expect(parts.first.qualities.map((q) => q.id), ['original', 'hd4k']);
    expect(parts.first.duration, const Duration(minutes: 10));
    expect(jsonEncode({'id': parts.first.id}), isNot(contains('http')));
    expect(SoopArchiveApi.mediaHeaders('123').containsKey('cookie'), isFalse);
  });
  test('private, paid, age-gated, removed, changed and non-public files remain explicit failures', () {
    expect(() => SoopArchiveApi.parseDetail(detail(adult: 'notLogin'), id: '123'), throwsA(isA<NeedsLogin>()));
    expect(() => SoopArchiveApi.parseDetail(detail(paid: true), id: '123'), throwsA(isA<NeedsLogin>()));
    expect(() => SoopArchiveApi.parseDetail(detail(id: '999'), id: '123'), throwsA(isA<ApiChanged>()));
    expect(() => SoopArchiveApi.parseDetail(detail(files: []), id: '123'), throwsA(isA<StreamUnavailable>()));
    expect(
      () => SoopArchiveApi.parseDetail(
        detail(files: [file(1, host: 'evil.invalid')]),
        id: '123',
      ),
      throwsA(isA<StreamUnavailable>()),
    );
    final removed = detail();
    (removed['data'] as Map)['code'] = -6221;
    expect(() => SoopArchiveApi.parseDetail(removed, id: '123'), throwsA(isA<NotFound>()));
  });
}
