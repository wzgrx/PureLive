import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/archive/archive_recording.dart';

/// Compatibility entry for the existing live-room shell in replay mode.
class ArchivePlayerPage extends StatelessWidget {
  /// Public metadata only; platform controllers resolve media independently.
  const new({
    required this.videoId,
    this.archiveVideo,
    this.bilibiliVideo,
    this.recordings = const [],
    this.room,
    this.onProgress,
    this.onRetire,
    super.key,
  });

  /// Official recording id.
  final String videoId;

  /// Huya metadata, when selected.
  final HuyaArchiveVideo? archiveVideo;

  /// Bilibili archive, when selected.
  final VodArchive? bilibiliVideo;

  /// Loaded creator recordings.
  final List<ArchiveRecording> recordings;

  /// Invoking live room, when verified.
  final LiveRoom? room;

  /// Actual runtime resource retirement, including time spent floating.
  final ValueChanged<Future<void>>? onRetire;

  /// Known part position for the catalog.
  final void Function(String id, int? part, Duration position)? onProgress;
  @override
  Widget build(BuildContext context) {
    final video = bilibiliVideo ?? archiveVideo ?? DouyuVodVideo(id: videoId, title: i18n('replay_title'));
    final selected =
        recordings.where((r) => r.id == videoId).firstOrNull ??
        ArchiveRecording(
          video,
          title: video is VodArchive
              ? video.title
              : video is HuyaArchiveVideo
              ? video.title
              : (video as DouyuVodVideo).title,
          cover: video is VodArchive
              ? video.cover
              : video is HuyaArchiveVideo
              ? video.cover
              : (video as DouyuVodVideo).cover,
          date: video is VodArchive
              ? video.publishedAt
              : video is HuyaArchiveVideo
              ? DateTime.tryParse(video.date)
              : (video as DouyuVodVideo).publishedAt,
          duration: video is VodArchive
              ? video.duration
              : video is HuyaArchiveVideo
              ? video.duration
              : (video as DouyuVodVideo).duration,
        );
    return LivePlayPage(
      route: RouteArgs(
        RoutePath.kLivePlay,
        arguments: ArchiveRoomArguments(
          selection: ArchiveSelection(recording: selected, recordings: recordings, room: room),
          onRetire: onRetire,
          onProgress: onProgress,
        ),
      ),
    );
  }
}
