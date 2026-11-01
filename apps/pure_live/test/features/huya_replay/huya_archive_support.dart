import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_vod/live_vod.dart';

/// Synthetic public metadata, never a real room or remote request.
const firstArchive = HuyaArchiveVideo(
  id: '100000001',
  title: '第一场虎牙录像',
  authorId: '123',
  duration: Duration(hours: 2),
  date: '2026-11-01',
);

/// Another server page.
const secondArchive = HuyaArchiveVideo(id: '100000002', title: '第二场虎牙录像', authorId: '123');

/// Cancellable fake with independently delayed list and rendition replies.
final class FakeHuyaArchive implements HuyaArchiveSource {
  final calls = <String>[];
  final lists = <String, Completer<HuyaArchiveList>>{};
  Completer<List<HuyaArchiveQuality>>? pendingQualities;
  bool failList = false;
  bool failQualities = false;
  int revision = 0;
  @override
  Future<HuyaArchiveList> list(String uid, {int page = 1, CancelToken? cancel}) async {
    calls.add('list:$uid:$page');
    if (failList) throw const NetworkFailure('huya', 'Synthetic failure');
    if (lists['$uid:$page'] case final pending?) return await pending.future;
    return HuyaArchiveList(videos: [if (page == 1) firstArchive else secondArchive], hasMore: page == 1);
  }

  @override
  Future<List<HuyaArchiveQuality>> qualities(String videoId, {CancelToken? cancel}) async {
    calls.add('qualities:$videoId');
    if (failQualities) throw const StreamUnavailable('huya', 'Synthetic refusal');
    if (pendingQualities case final pending?) return await pending.future;
    revision++;
    return renditions(revision);
  }
}

/// Fresh synthetic URLs keep stable definition ids and never hit the network.
List<HuyaArchiveQuality> renditions(int revision) => [
  for (final id in ['yuanhua', '1300'])
    HuyaArchiveQuality(
      LivePlayQuality(
        quality: id == 'yuanhua' ? '原画' : '720P',
        id: id,
        data: 'https://record.example.test/archive.m3u8?definition=$id&revision=$revision',
      ),
    ),
];
