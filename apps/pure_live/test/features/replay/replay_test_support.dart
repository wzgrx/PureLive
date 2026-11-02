import 'dart:async';

import 'package:live_net/live_net.dart';
import 'package:live_vod/live_vod.dart';

const archive = VodArchive(
  bvid: 'BV1234567890',
  title: '公开直播回放',
  parts: [
    VodPart(cid: 100, title: '第一部分', duration: Duration(hours: 3)),
    VodPart(cid: 200, title: '第二部分', duration: Duration(hours: 2)),
  ],
);

class FakeBiliReplay implements BilibiliReplaySource {
  Completer<VodArchive>? pending;
  int requests = 0;
  @override
  Future<VodArchive> detail(String bvid) async => pending == null ? archive : await pending!.future;
  @override
  Future<VodPage<ReplayCollection>> collections(int mid, {int page = 1, CancelToken? cancel}) async =>
      const VodPage([ReplayCollection(id: 1, name: '直播回放')]);
  @override
  Future<VodPage<VodArchive>> list(int mid, ReplayCollection collection, {int page = 1, CancelToken? cancel}) async =>
      const VodPage([archive]);
  @override
  Future<VodStreams> streams(String bvid, int cid, {int qn = 0}) async {
    requests++;
    return VodStreams(
      quality: qn == 0 ? 32 : qn,
      headers: const {'referer': 'https://www.bilibili.com/video/BV1234567890/'},
      qualities: const [
        VodQuality(qn: 80, label: '1080P'),
        VodQuality(qn: 32, label: '480P'),
        VodQuality(qn: 16, label: '360P'),
      ],
      videos: [
        for (final q in [32, 16])
          VodRendition(id: q, url: 'https://video.example.test/$cid/$q-$requests.m4s', codecs: 'avc1.64001F'),
      ],
      audios: [VodRendition(id: 30280, url: 'https://video.example.test/$cid/audio-$requests.m4s')],
    );
  }
}
