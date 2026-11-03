import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_player/live_player.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/logic/room_runtime.dart';
import 'package:pure_live/shared/rooms/archive/archive_recording.dart';
import 'package:pure_live/shared/rooms/archive/bilibili_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive/douyu_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive/douyu_archive_progress.dart';
import 'package:pure_live/shared/rooms/archive/huya_archive_controller.dart';
import 'package:pure_live/shared/rooms/archive_playback.dart';

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

/// Official broadcast replay collections, sharing the local Bilibili account.
final Provider<BilibiliReplaySource> bilibiliReplayProvider = Provider(
  (ref) => BilibiliReplayApi(ref.watch(vodClientProvider)),
);

/// Public room identity lookup also works when a creator is offline.
final Provider<ReplayIdentityApi> replayIdentityProvider = Provider((ref) {
  final services = ref.watch(appServicesProvider);
  return ReplayIdentityApi(services.http, cookies: services.cookies);
});

/// Per-part positions; no signed URLs, cookies or names enter the progress store.
final Provider<HuyaArchiveProgress> bilibiliReplayProgressProvider = Provider((ref) {
  final meta = ref.watch(storeProvider).meta;
  return HuyaArchiveProgress(
    read: () => meta.get('bilibili-replay-progress-v1'),
    write: (value) => meta.set('bilibili-replay-progress-v1', value),
    idPattern: r'^BV[0-9A-Za-z]{10}:[1-9][0-9]{0,18}$',
  );
});

/// Stops an existing floating decoder before a standalone catalog starts another.
final beforeArchivePlaybackProvider = Provider<Future<void> Function()>((ref) => FloatingRoom.instance.close);

/// Captures app-owned services before the creating page can enter a mini window.
ArchivePlaybackController Function(ArchiveRecording) roomArchiveFactory(
  WidgetRef ref,
  PlaybackSession session, {
  double? firstVolume,
}) {
  final huya = ref.read(huyaArchiveProvider);
  final huyaProgress = ref.read(huyaArchiveProgressProvider);
  final douyu = ref.read(douyuVodProvider);
  final douyuProgress = ref.read(douyuVodProgressProvider);
  final bili = ref.read(bilibiliReplayProvider);
  final biliProgress = ref.read(bilibiliReplayProgressProvider);
  final proxy = ref.read(appServicesProvider).proxy;
  var initial = firstVolume;
  return (recording) {
    final volume = initial ?? session.state.volume;
    initial = null;
    return switch (recording.video) {
      final HuyaArchiveVideo video => HuyaArchiveController(
        source: huya,
        proxy: proxy,
        session: session,
        video: video,
        progress: huyaProgress,
        initialVolume: volume,
        ownsSession: false,
      ),
      VodArchive() => BilibiliArchiveController(
        source: bili,
        session: session,
        progress: biliProgress,
        initialVolume: volume,
        ownsSession: false,
      ),
      _ => DouyuVodController(
        source: douyu,
        session: session,
        progress: douyuProgress,
        initialVolume: volume,
        ownsSession: false,
      ),
    };
  };
}
