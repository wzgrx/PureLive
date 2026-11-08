import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_vod/live_vod.dart';
import 'package:test/test.dart';

const channel = '0123456789abcdef0123456789abcdef';
Map<String, Object?> row({int no = 101, bool adult = false, Object? paid}) => {
  'videoNo': no,
  'videoTitle': 'Public rehearsal',
  'videoType': 'REPLAY',
  'channel': {'channelId': channel, 'channelName': 'Example'},
  'publishDateAt': 1793782000000,
  'duration': 1200,
  'exposure': true,
  'adult': adult,
  'paidProductId': paid,
};

Map<String, Object?> detail(String url) => {
  ...row(),
  'liveRewindPlaybackJson': jsonEncode({
    'media': [
      {'mediaId': 'HLS', 'path': url},
    ],
  }),
};

void main() {
  test('public contiguous TS entries make a finite VOD index at the original quality', () {
    final recording = ChzzkArchiveApi.parseDetail(
      detail('https://sample.akamaized.net/live/index.m3u8'),
      id: '101',
    ).single.recording;
    final timeline = [
      {'t': 0, 'd': 4000, 'r': 299},
    ];
    final ts = {
      'id': 'rendition_144',
      'height': 144,
      'codecs': 'avc1.4dc00c,mp4a.40.2',
      'baseURL': [
        {'value': 'https://sample.akamaized.net/video/'},
      ],
      'segmentTemplate': {
        'media': r'$RepresentationID$/seg_$Number%06d$.ts?sig=synthetic',
        'timescale': 1000,
        'startNumber': 0,
        'segmentTimeline': {'s': timeline},
      },
    };
    Map<String, Object?> manifest(Map<String, Object?> variant) => {
      'type': 'STATIC',
      'period': [
        {
          'adaptationSet': [
            {
              'mimeType': 'video/mp2t',
              'representation': [variant],
            },
            {
              'mimeType': 'video/mp4',
              'representation': [
                {
                  'height': 144,
                  'codecs': 'avc1.4dc00c,mp4a.40.2',
                  'baseURL': [
                    {'value': 'https://sample.akamaized.net/replay.mp4'},
                  ],
                },
              ],
            },
          ],
        },
      ],
    };
    final quality = ChzzkArchiveApi.parseMediaManifest(recording, manifest(ts)).single.qualities.single;
    expect(quality.id, 'mp4-144');
    expect(quality.url, endsWith('replay.mp4'));
    final playlist = quality.segments!.render();
    expect(quality.segments!.firstUrl, endsWith('/rendition_144/seg_000000.ts?sig=synthetic'));
    expect(playlist, contains('/rendition_144/seg_000075.ts?sig=synthetic'));
    expect(playlist, contains('#EXT-X-TARGETDURATION:4'));
    expect('#EXTINF:'.allMatches(playlist), hasLength(300));
    expect(playlist, endsWith('#EXT-X-ENDLIST\n'));
    timeline[0]['r'] = -1;
    expect(ChzzkArchiveApi.parseMediaManifest(recording, manifest(ts)).single.qualities.single.segments, isNull);
    timeline[0]['r'] = 299;
    final protected = {
      ...ts,
      'contentProtection': [
        {'schemeIdUri': 'urn:test'},
      ],
    };
    expect(ChzzkArchiveApi.parseMediaManifest(recording, manifest(protected)).single.qualities.single.segments, isNull);
    final offCdn = {
      ...ts,
      'baseURL': [
        {'value': 'https://sample.akamaized.net.example.test/'},
      ],
    };
    expect(ChzzkArchiveApi.parseMediaManifest(recording, manifest(offCdn)).single.qualities.single.segments, isNull);
  });

  test('finished public VOD offers only muxed allowlisted MP4 with stable quality ids', () {
    final recording = ChzzkArchiveApi.parseDetail(
      detail('https://sample.akamaized.net/live/index.m3u8'),
      id: '101',
    ).single.recording;
    Map<String, Object?> variant(int height, String host, {String codecs = 'avc1.64002a,mp4a.40.2'}) => {
      'codecs': codecs,
      'height': height,
      'baseURL': [
        {'value': 'https://$host/public/video.mp4'},
      ],
    };
    final manifest = {
      'type': 'STATIC',
      'period': [
        {
          'adaptationSet': [
            {
              'mimeType': 'video/mp4',
              'representation': [
                variant(1080, 'sample.akamaized.net'),
                variant(144, 'sample.akamaized.net'),
                variant(480, 'sample.akamaized.net.example'),
                variant(720, 'sample.akamaized.net', codecs: 'avc1.64002a'),
                {...variant(360, 'sample.akamaized.net'), 'segmentList': <String, Object?>{}},
                {
                  ...variant(240, 'sample.akamaized.net'),
                  'contentProtection': [
                    {'schemeIdUri': 'urn:example'},
                  ],
                },
              ],
            },
          ],
        },
      ],
    };
    final part = ChzzkArchiveApi.parseProgressive(recording, manifest).single;
    expect(part.id, '101:1');
    expect(part.qualities.map((q) => (q.id, q.format)), [
      ('mp4-144', StreamFormat.other),
      ('mp4-1080', StreamFormat.other),
    ]);
    expect(
      () => ChzzkArchiveApi.parseProgressive(recording, {...manifest, 'type': 'dynamic'}),
      throwsA(isA<ApiChanged>()),
    );
  });

  test('catalog pagination is server-driven, duplicates and restricted entries omitted', () {
    final page = ChzzkArchiveApi.parseList(
      {
        'page': 0,
        'totalPages': 2,
        'data': [row(), row(), row(no: 102, adult: true), row(no: 103, paid: 1)],
      },
      channel: channel,
      page: 1,
    );
    expect(page.videos.map((v) => v.id), ['101']);
    expect(page.videos.single.duration, const Duration(seconds: 1200));
    expect(page.hasMore, isTrue);
  });

  test('only an official link and a matching public HLS response are playable', () {
    expect(ChzzkArchiveApi.channelFromText('https://chzzk.naver.com/$channel/videos?page=1'), channel);
    expect(ChzzkArchiveApi.videoFromText('https://chzzk.naver.com/video/101'), '101');
    expect(ChzzkArchiveApi.videoFromText('https://chzzk.naver.com.example/video/101'), isNull);
    final parts = ChzzkArchiveApi.parseDetail(detail('https://sample.akamaized.net/live/index.m3u8'), id: '101');
    expect(parts.single.id, '101:1');
    expect(parts.single.qualities.single.id, 'auto');
    expect(
      () => ChzzkArchiveApi.parseDetail(detail('https://sample.akamaized.net/live/index.m3u8'), id: '102'),
      throwsA(isA<ApiChanged>()),
    );
    expect(
      () => ChzzkArchiveApi.parseDetail(detail('https://sample.akamaized.net.example/live/index.m3u8'), id: '101'),
      throwsA(isA<StreamUnavailable>()),
    );
    expect(
      () => ChzzkArchiveApi.parseDetail({
        ...detail('https://sample.akamaized.net/live/index.m3u8'),
        'adult': true,
      }, id: '101'),
      throwsA(isA<StreamUnavailable>()),
    );
  });
}
