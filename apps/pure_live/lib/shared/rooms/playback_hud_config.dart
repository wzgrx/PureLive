import 'package:flutter/widgets.dart';

/// Persisted, bounded display preferences shared by phone, desktop and TV.
@immutable
final class PlaybackHudConfig {
  /// Creates display preferences without changing playback itself.
  const new({
    this.mode = 'fullscreen',
    this.clock = true,
    this.speed = false,
    this.corner = 'topLeft',
    this.size = 11,
    this.color = 0xffffffff,
    this.font = 'app',
    this.separate = false,
    this.clockStyle,
    this.speedStyle,
  });

  /// Safely reads imported or older configuration values.
  factory fromJson(Map<String, Object?> value) {
    T choice<T>(String key, Set<T> choices, T fallback) => choices.contains(value[key]) ? value[key]! as T : fallback;
    final rawSize = value['size'];
    final rawColor = value['color'];
    PlaybackHudStyle? style(Object? raw) {
      if (raw is! Map) return null;
      const fields = {'corner', 'size', 'color', 'font'};
      return PlaybackHudStyle.fromJson({
        for (final key in fields)
          if (value.containsKey(key)) key: value[key],
        for (final entry in raw.entries)
          if (entry.key is String && fields.contains(entry.key)) entry.key as String: entry.value,
      });
    }

    return .new(
      mode: choice('mode', modes, 'fullscreen'),
      clock: value['clock'] != false,
      speed: value['speed'] == true,
      corner: choice('corner', corners.keys.toSet(), 'topLeft'),
      size: rawSize is num && rawSize.isFinite ? rawSize.toDouble().clamp(11, 48) : 11,
      color: rawColor is int && rawColor >= 0 && rawColor <= 0xffffffff ? rawColor : 0xffffffff,
      font: choice('font', fonts, 'app'),
      separate: value['separate'] == true,
      clockStyle: style(value['clockStyle']),
      speedStyle: style(value['speedStyle']),
    );
  }

  /// Visibility: disabled, follows the controls, or always visible.
  final String mode;

  /// Whether to show local wall-clock time.
  final bool clock;

  /// Whether to show the current media input rate.
  final bool speed;

  /// The preferred safe corner.
  final String corner;

  /// Logical font size before accessibility scaling.
  final double size;

  /// ARGB text color; an outline preserves contrast over video.
  final int color;

  /// Application, system sans-serif, or monospace font.
  final String font;

  /// Whether clock and speed have independent styling and placement.
  final bool separate;

  /// Optional clock overrides; null inherits the legacy combined appearance.
  final PlaybackHudStyle? clockStyle;

  /// Optional speed overrides; null inherits the legacy combined appearance.
  final PlaybackHudStyle? speedStyle;

  /// Combined presentation retained for older settings and backups.
  PlaybackHudStyle get combinedStyle => PlaybackHudStyle(corner: corner, size: size, color: color, font: font);

  /// Resolved independent appearance without changing stored legacy values.
  PlaybackHudStyle styleFor(String field) =>
      !separate ? combinedStyle : (field == 'clock' ? clockStyle : speedStyle) ?? combinedStyle;

  /// Supported visibility modes.
  static const Set<String> modes = {'off', 'fullscreen', 'controls', 'always'};

  /// Default status information fits alongside the fullscreen battery.
  bool get compactHeader => !separate && corner == 'topLeft' && size <= 18;

  /// Positions use the same geometry in every layout.
  static const Map<String, Alignment> corners = {
    'topLeft': Alignment.topLeft,
    'topRight': Alignment.topRight,
    'bottomLeft': Alignment.bottomLeft,
    'bottomRight': Alignment.bottomRight,
  };

  /// Portable fonts do not fetch or install anything.
  static const Set<String> fonts = {'app', 'system', 'mono'};

  /// Whether any information should currently be drawn.
  bool visible({required bool controls, bool fullscreen = true}) =>
      (clock || speed) && (mode == 'always' || mode == 'controls' && controls || mode == 'fullscreen' && fullscreen);

  /// Stable values for settings backup and persistence.
  Map<String, Object?> toJson() => {
    'mode': mode,
    'clock': clock,
    'speed': speed,
    'corner': corner,
    'size': size,
    'color': color,
    'font': font,
    'separate': separate,
    'clockStyle': ?clockStyle?.toJson(),
    'speedStyle': ?speedStyle?.toJson(),
  };
}

/// Appearance of one information item. Uses the same bounds as combined HUDs.
@immutable
final class PlaybackHudStyle {
  /// Creates one item's appearance.
  const new({this.corner = 'topLeft', this.size = 11, this.color = 0xffffffff, this.font = 'app'});

  /// Validates nested imported values through the existing shared rules.
  factory fromJson(Map<String, Object?> value) {
    final config = PlaybackHudConfig.fromJson(
      {...value}
        ..remove('clockStyle')
        ..remove('speedStyle'),
    );
    return config.combinedStyle;
  }

  /// Safe corner.
  final String corner;

  /// Logical font size, 11 to 48.
  final double size;

  /// ARGB text colour.
  final int color;

  /// Portable font choice.
  final String font;

  /// Stable nested representation.
  Map<String, Object?> toJson() => {'corner': corner, 'size': size, 'color': color, 'font': font};
}
