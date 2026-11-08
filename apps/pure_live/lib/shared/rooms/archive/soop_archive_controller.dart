import 'package:live_core/live_core.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/shared/rooms/archive/part_archive_controller.dart';

/// Public SOOP files on the existing room session.
final class SoopArchiveController extends PartArchiveController<SoopArchivePart, SoopArchiveQuality> {
  /// Uses SOOP's current per-part renditions and media headers.
  new({
    required SoopArchiveSource source,
    required super.session,
    required SoopArchiveVideo recording,
    required super.progress,
    super.initialVolume,
    super.ownsSession,
  }) : super(
         site: SiteIds.soop,
         recordingId: recording.id,
         loadParts: source.detail,
         qualitiesOf: (part) => part.qualities,
         lineFor: (q) => LivePlayLine(
           q.url,
           headers: SoopArchiveApi.mediaHeaders(recording.id),
           format: Uri.parse(q.url).path.endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.other,
         ),
       );
}
