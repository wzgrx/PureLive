import 'package:flutter/material.dart';

/// Accessible level-band fallback when Huya BadgeInfo has a name/level but
/// carries no native RGB. This is an app palette, not a custom badge skin.
Color huyaFanBadgeColor(int level, {required bool dark}) {
  final color = Color(switch (level) {
    <= 5 => 0xff45b977,
    <= 10 => 0xff369edb,
    <= 15 => 0xff8c6bdf,
    <= 20 => 0xffd661a0,
    <= 25 => 0xffe67648,
    <= 30 => 0xffcda13e,
    <= 35 => 0xffc259df,
    <= 40 => 0xffdf5360,
    _ => 0xffa58137,
  });
  return dark ? color : HSLColor.fromColor(color).withLightness(0.38).toColor();
}
