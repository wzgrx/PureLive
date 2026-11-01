import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/shared/rooms/archive/douyu_archive_progress.dart';
import 'package:pure_live/shared/rooms/archive/huya_archive_controller.dart';

/// The Bilibili video-on-demand plumbing (M14.0 `live_vod`): the app's HTTP
/// client (same proxy and rate rules as the live platform, site id
/// `bilibili`) and the live login cookie, so signing in once serves live
/// rooms and videos alike.
final Provider<BilibiliVodClient> vodClientProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  return BilibiliVodClient(services.http, cookies: services.cookies);
});

/// Video (UGC) endpoints: catalogs, detail, streams, comments, spaces,
/// favourites, history, search.
final Provider<BilibiliUgcApi> vodUgcProvider = Provider((ref) => BilibiliUgcApi(ref.watch(vodClientProvider)));

/// PGC endpoints: anime and film index, seasons, episode streams, followed
/// seasons.
final Provider<BilibiliPgcApi> vodPgcProvider = Provider((ref) => BilibiliPgcApi(ref.watch(vodClientProvider)));

/// Douyu's official public replay/video endpoints share the live transport/login.
final Provider<DouyuVodSource> douyuVodProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  return DouyuVodApi(services.http, cookies: services.cookies);
});

/// Local-only bounded VOD resume history; signed URLs are never stored.
final Provider<DouyuVodProgressStore> douyuVodProgressProvider = Provider((ref) {
  final meta = ref.watch(storeProvider).meta;
  return DouyuVodProgressStore(
    read: () => meta.get('douyu-vod-history-v1'),
    write: (value) => meta.set('douyu-vod-history-v1', value),
  );
});

/// Public Huya broadcast recordings, resolved independently of live streams.
final Provider<HuyaArchiveSource> huyaArchiveProvider = Provider(
  (ref) => HuyaArchiveApi(ref.watch(appServicesProvider).http),
);

/// Separate local progress namespace; contains ids and millisecond positions only.
final Provider<HuyaArchiveProgress> huyaArchiveProgressProvider = Provider((ref) {
  final meta = ref.watch(storeProvider).meta;
  return HuyaArchiveProgress(
    read: () => meta.get('huya-archive-progress-v1'),
    write: (value) => meta.set('huya-archive-progress-v1', value),
  );
});
