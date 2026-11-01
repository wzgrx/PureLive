import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_vod/live_vod.dart';
import 'package:test/test.dart';

String fixture(String name) => File('../../fixtures/huya/archive/$name').readAsStringSync();

String response(List<Object?> rows, {int total = 0, int code = 0}) =>
    '<script>window.HNF_GLOBAL_INIT = ${jsonEncode({
      'userPageLiveRecordVideoRsp': {
        'respHeader': {'code': code},
        'videoDataList': {'value': rows},
        'total': total,
      },
    })};</script>';

void main() {
  test('official captured pages retain distinct recordings, metadata, durations and paging units', () {
    final first = HuyaArchiveApi.parseList(fixture('page1.html'), uid: '294636272', page: 1);
    final second = HuyaArchiveApi.parseList(fixture('page2.html'), uid: '294636272', page: 2);
    expect(first.videos, hasLength(10));
    expect(second.videos, hasLength(10));
    expect(first.videos.first.id, '1131139550');
    expect(second.videos.first.id, '1129574858');
    expect(first.videos.map((v) => v.id).toSet().intersection(second.videos.map((v) => v.id).toSet()), isEmpty);
    expect(first.videos.first.duration, const Duration(hours: 11, minutes: 16, seconds: 36));
    expect(first.videos.first.date, '2026-10-31');
    expect(
      first.videos.every((v) => v.authorId == '294636272' && v.authorName.isNotEmpty && v.cover.startsWith('https://')),
      isTrue,
    );
    expect(first.hasMore && second.hasMore, isTrue);
  });

  test('empty archives, final pages, duplicate ids and foreign presenters are handled without fabricated videos', () {
    Map<String, Object?> row(String id, {String uid = '123'}) => {
      'videoData': {
        'vid': id,
        'videoTitle': 'A &amp; B',
        'duration': '01:02:03',
        'userInfo': {'uid': uid},
      },
    };
    final empty = HuyaArchiveApi.parseList(response([]), uid: '123', page: 1);
    expect(empty.videos, isEmpty);
    expect(empty.hasMore, isFalse);
    final page = HuyaArchiveApi.parseList(
      response([row('1'), row('1'), row('2', uid: '999'), row('bad')], total: 4),
      uid: '123',
      page: 1,
    );
    expect(page.videos.single.id, '1');
    expect(page.videos.single.title, 'A & B');
    expect(page.videos.single.duration, const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(page.hasMore, isFalse);
  });

  test('page scripts are data only; unknown functions, missing assignment and refused data fail explicitly', () {
    final valid = response([]);
    expect(
      HuyaArchiveApi.parseList('<script>throw new Error("must never run")</script>$valid', uid: '123', page: 1).videos,
      isEmpty,
    );
    for (final body in [
      '<script>alert("not an archive")</script>',
      valid.substring(0, valid.indexOf('respHeader')),
      response([], code: 1),
      valid.replaceFirst('"total":0', '"total":function(){return 1;}'),
    ]) {
      expect(() => HuyaArchiveApi.parseList(body, uid: '123', page: 1), throwsA(isA<ApiChanged>()));
    }
  });

  test('only public ids and official archive URLs are accepted', () {
    expect(HuyaArchiveApi.uidFromText('294636272'), '294636272');
    expect(HuyaArchiveApi.uidFromText('https://www.huya.com/video/u/294636272?tabName=live&pageIndex=1'), '294636272');
    for (final value in [
      '0',
      '../123',
      'https://evil.test/video/u/123',
      'file:///video/u/123',
      'https://www.huya.com/video/play/123.html',
    ]) {
      expect(HuyaArchiveApi.uidFromText(value), isNull);
    }
  });

  test('HTTP requests preserve platform, cancellation and pagination without sending cookies', () async {
    final http = _Http()..body = fixture('page2.html');
    final api = HuyaArchiveApi(http);
    final cancel = CancelToken();
    expect((await api.list('294636272', page: 2, cancel: cancel)).videos.first.id, '1129574858');
    expect(http.last.url.host, 'www.huya.com');
    expect(http.last.url.path, '/video/u/294636272');
    expect(http.last.url.queryParameters, {'tabName': 'live', 'pageIndex': '2'});
    expect(http.last.site, SiteIds.huya);
    expect(http.last.cancel, same(cancel));
    expect(http.last.headers.keys.any((k) => k.toLowerCase() == 'cookie'), isFalse);
    http.body = fixture('qualities.json');
    final qualities = await api.qualities('1131139550');
    expect(qualities, hasLength(3));
    expect(qualities.every((q) => q.playable), isTrue);
    expect(qualities.first.label, '原画');
    expect(http.last.url.host, 'liveapi.huya.com');
    expect(http.last.url.queryParameters, {'videoId': '1131139550'});
    for (final status in [401, 403, 404, 429, 500]) {
      http.status = status;
      await expectLater(api.list('123'), throwsA(isA<SiteError>()));
    }
  });

  test('presenter archives avoid the official mobile redirect to the unrelated video home page', () async {
    final http = _Http()
      ..body = fixture('page1.html')
      ..routeBrowserPage = true;
    final videos = (await HuyaArchiveApi(http).list('294636272')).videos;
    expect(videos, hasLength(10));
    expect(videos.first.id, '1131139550');
    // Keep media and moment requests on their existing policy.
    expect(HuyaArchiveApi.mediaHeaders['user-agent'], contains('Mobile'));
  });
}

final class _Http implements LiveHttp {
  late LiveRequest last;
  String body = '';
  int status = 200;
  bool routeBrowserPage = false;
  @override
  Future<LiveResponse> send(LiveRequest request) async {
    last = request;
    final mobileHome = routeBrowserPage && (request.headers['user-agent']?.contains('Mobile') ?? false);
    return LiveResponse(
      status: status,
      bytes: utf8.encode(mobileHome ? '<script>window.HNF_GLOBAL_INIT = {"pageData":[]};</script>' : body),
      url: request.url,
    );
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();
  @override
  void close() {}
}
