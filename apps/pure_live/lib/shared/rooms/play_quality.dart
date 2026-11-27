import 'package:live_core/live_core.dart';

/// The quality to start with (3.x `_setDefaultResolution`; the live room
/// and every multi-view cell): the one named like the preference, else the
/// same relative position in the list (3.x's five names from best to
/// worst). 3.x's multi-view always took the best one.
///
/// With [codec] (the "优先视频编码" setting, `h264` by default) a name
/// match whose codec hint is another codec is passed over while the room
/// offers the chosen one: the relative position decides, and should it land
/// on another codec too the nearest chosen one is taken (the better one on
/// a tie). A codec other than `auto` is then played only when picked by
/// hand or when nothing else is on offer (G01.3).
int defaultQualityIndex(
  List<LivePlayQuality> qualities,
  String preferred, {
  String codec = VideoCodecs.auto,
}) {
  if (qualities.isEmpty) return 0;
  // A quality is passed over only when its codec is known to be another
  // one than the preference asks for; one with no hint may be the wanted
  // codec, so it is kept (as "优先 H.264" did with HLS-only qualities).
  bool acceptable(int index) => !VideoCodecs.knownOther(qualities[index].codec, codec);
  bool anyAcceptable() => qualities.any((quality) => !VideoCodecs.knownOther(quality.codec, codec));
  final exact = qualities.indexWhere((q) => q.quality == preferred);
  final skip = exact >= 0 && !acceptable(exact) && anyAcceptable();
  if (exact >= 0 && !skip) return exact;
  final position = _relativePosition(qualities.length, preferred);
  if (!anyAcceptable() || acceptable(position)) return position;
  for (var distance = 1; distance < qualities.length; distance++) {
    for (final index in [position - distance, position + distance]) {
      if (index >= 0 && index < qualities.length && acceptable(index)) return index;
    }
  }
  return position;
}

/// The index at [preferred]'s place among 3.x's five names, scaled to
/// [length] qualities; the first for a name not among them.
int _relativePosition(int length, String preferred) {
  const names = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅'];
  final level = names.indexOf(preferred);
  if (level < 0) return 0;
  final ratio = level / (names.length - 1);
  return (ratio * (length - 1)).round().clamp(0, length - 1);
}

/// The platforms whose carousel the app can play (UPGRADES 1-1: Bilibili's
/// loop of old videos, which a guest plays from the video itself).
const Set<String> carouselPlatforms = {SiteIds.bilibili};

/// Whether [room] is a carousel the user may start (E06.2 G1 A: a
/// "播放轮播" button, not at once). The room itself stays not playable
/// ([LiveRoom.isPlayableNow]): follows keep it under "未开播" and recording
/// does not record it.
bool carouselPlayable(LiveRoom room) =>
    room.effectiveLiveStatus == LiveStatus.carousel && carouselPlatforms.contains(room.platform);
