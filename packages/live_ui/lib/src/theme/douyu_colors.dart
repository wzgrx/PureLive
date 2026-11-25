import 'package:material_ui/material_ui.dart';

/// Douyu's fan-medal colour by level (3.x `DanmakuItem`): light blue through
/// level 5, then green-blue, orange, red, purple and finally deep purple. The
/// palette is made for Douyu's dark surface; on a light theme it is darkened
/// to 40 % lightness so the lowest levels stay readable.
Color douyuFanBadgeColor(int level, {required bool dark}) {
  final color = switch (level) {
    <= 5 => 0xFF7DD0FD,
    <= 10 => 0xFF4CD5E1,
    <= 15 => 0xFFFB9D23,
    <= 20 => 0xFFFA791F,
    <= 25 => 0xFFFA4C1C,
    <= 30 => 0xFFAC38D3,
    _ => 0xFF7C00E3,
  };
  return dark ? Color(color) : HSLColor.fromColor(Color(color)).withLightness(0.4).toColor();
}

/// Douyu's user-level colour by level (3.x `DanmakuItem`): beige, green,
/// steel blue, blue, purple, pink, red and yellow; darkened on a light
/// theme like [douyuFanBadgeColor].
Color douyuUserLevelColor(int level, {required bool dark}) {
  final color = switch (level) {
    <= 19 => 0xFFDED9C6,
    <= 29 => 0xFF94D256,
    <= 39 => 0xFF97B3D5,
    <= 69 => 0xFF3980F9,
    <= 79 => 0xFFB42CF4,
    <= 89 => 0xFFFA7B83,
    <= 99 => 0xFFF94D55,
    _ => 0xFFF5F241,
  };
  return dark ? Color(color) : HSLColor.fromColor(Color(color)).withLightness(0.4).toColor();
}
