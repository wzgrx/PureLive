import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/archive/archive_time.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// Public metadata passed between a creator catalog and the shared player.
@immutable
final class ArchiveRecording {
  /// No media credentials or URLs are retained here.
  const new(this.video, {required this.title, required this.cover, required this.date, required this.duration});

  /// Original platform metadata used to select its resolver.
  final Object video;

  /// Original title, before presentation-only cleanup.
  final String title;

  /// Public cover image.
  final String cover;

  /// Platform-supplied publish/record date when known.
  final DateTime? date;

  /// Known duration, never guessed from a title.
  final Duration duration;

  /// Stable public id.
  String get id => switch (video) {
    final HuyaArchiveVideo v => v.id,
    final DouyuVodVideo v => v.id,
    final VodArchive v => v.bvid,
    _ => throw StateError('Unknown archive'),
  };

  /// Platform proxy/account namespace.
  String get platform => switch (video) {
    HuyaArchiveVideo() => SiteIds.huya,
    DouyuVodVideo() => SiteIds.douyu,
    _ => SiteIds.bilibili,
  };

  /// Creator name supplied with metadata, if present.
  String get author => switch (video) {
    final HuyaArchiveVideo v => v.authorName,
    final DouyuVodVideo v => v.authorName,
    final VodArchive v => v.owner.name,
    _ => '',
  };
}

/// Removes repeated replay/date wrappers only from visible titles.
String archiveDisplayTitle(String raw, {String author = ''}) {
  var title = raw.trim().replaceFirst(RegExp(r'^【直播回放】\s*'), '');
  title = title.replaceFirst(RegExp(r'\s*\d{4}年\d{2}月\d{2}日\d{2}点场\s*$'), '');
  title = title.replaceFirst(RegExp(r'^【\d{4}-\d{2}-\d{2}[^】]*】\s*'), '');
  if (author.isNotEmpty && title.startsWith('$author：')) title = title.substring(author.length + 1).trim();
  return title.isEmpty ? raw : title;
}

/// One compact, focusable recording row shared by player and catalog.
class ArchiveRecordingTile extends StatelessWidget {
  /// Creates a row, preserving complete metadata for playback.
  const new({
    required this.recording,
    required this.onTap,
    this.position,
    this.tv = false,
    this.autofocus = false,
    super.key,
  });

  /// Public metadata.
  final ArchiveRecording recording;

  /// Opens this recording.
  final VoidCallback? onTap;

  /// Per-recording/part local position when known.
  final Duration? position;

  /// Uses the application's established TV focus ring.
  final bool tv;

  /// Initial remote target.
  final bool autofocus;
  @override
  Widget build(BuildContext context) {
    final date = recording.date;
    final subtitle = [
      if (date != null) '${date.month}.${date.day}',
      vodTime(recording.duration),
      if (position != null && position! > Duration.zero)
        i18n(
          recording.video is VodArchive ? 'archive_part_resume_position' : 'replay_position',
          args: {'position': vodTime(position!)},
        ),
    ].join('  ');
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          if (recording.cover.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                recording.cover,
                width: 100,
                height: 60,
                cacheWidth: 300,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(width: 100, height: 60, child: Icon(AppIcons.vodCatalog)),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  archiveDisplayTitle(recording.title, author: recording.author),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.t14,
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: context.textStyles.t12.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return tv
        ? TvFocusable(autofocus: autofocus, zoom: false, onTap: onTap, builder: (_, _) => content)
        : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: content);
  }
}
