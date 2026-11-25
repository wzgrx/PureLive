import 'package:live_ui/src/theme/live_theme.dart';
import 'package:material_ui/material_ui.dart';

/// The colours of the TV's colour grid (A17.9 c12): a row of common ones
/// (the brand blue first, pure_live_TV's presets, then the phone's
/// favourites) and a palette of 18 hues in three shades.
abstract final class LiveSwatches {
  /// The common row: 18 colours.
  static const List<Color> common = [
    LiveTheme.brandBlue,
    Color(0xFF00D4FF), // pure_live_TV tech blue
    Color(0xFFFF66CC), // anime pink
    Color(0xFF2AD39A), // cyberpunk green
    Color(0xFFFF9F43), // warm orange
    Color(0xFF9C6BFF), // violet
    Color(0xFF2196F3), // 3.x's blue
    Color(0xFFE53935),
    Color(0xFFD81B60),
    Color(0xFF8E24AA),
    Color(0xFF3949AB),
    Color(0xFF039BE5),
    Color(0xFF00897B),
    Color(0xFF43A047),
    Color(0xFFC0CA33),
    Color(0xFFFDD835),
    Color(0xFFFB8C00),
    Color(0xFF6D4C41),
  ];

  /// The palette: Material's 18 hues, each light (200), middle (500) and
  /// dark (800), as three rows.
  static List<List<Color>> get palette => [
    for (final shade in const [200, 500, 800]) [for (final swatch in Colors.primaries) swatch[shade]!],
  ];

  /// The built-in gradient backgrounds of the TV (A17.8 h1; the open
  /// "WebGradients" set, MIT, as pure_live_TV shows).
  static const List<LiveGradientSwatch> gradients = [
    LiveGradientSwatch('night_fade', 0, [Color(0xFFA18CD1), Color(0xFFFBC2EB)]),
    LiveGradientSwatch('winter_neva', 120, [Color(0xFFA1C4FD), Color(0xFFC2E9FB)]),
    LiveGradientSwatch('dusty_grass', 120, [Color(0xFFD4FC79), Color(0xFF96E6A1)]),
    LiveGradientSwatch('tempting_azure', 120, [Color(0xFF84FAB0), Color(0xFF8FD3F4)]),
    LiveGradientSwatch('amy_crisp', 120, [Color(0xFFA6C0FE), Color(0xFFF68084)]),
    LiveGradientSwatch('ripe_malinka', 120, [Color(0xFFF093FB), Color(0xFFF5576C)]),
    LiveGradientSwatch('malibu_beach', 0, [Color(0xFF4FACFE), Color(0xFF00F2FE)]),
    LiveGradientSwatch('new_life', 0, [Color(0xFF43E97B), Color(0xFF38F9D7)]),
    LiveGradientSwatch('morpheus_den', 0, [Color(0xFF30CFD0), Color(0xFF330867)]),
    LiveGradientSwatch('near_moon', 0, [Color(0xFF5EE7DF), Color(0xFFB490CA)]),
    LiveGradientSwatch('plum_plate', 135, [Color(0xFF667EEA), Color(0xFF764BA2)]),
    LiveGradientSwatch('happy_fisher', 120, [Color(0xFF89F7FE), Color(0xFF66A6FF)]),
    LiveGradientSwatch('itmeo_branding', 180, [Color(0xFF2AF598), Color(0xFF009EFD)]),
    LiveGradientSwatch('blue_velvet', 0, [Color(0xFF6A11CB), Color(0xFF2575FC)]),
    LiveGradientSwatch('fly_high', 0, [Color(0xFF48C6EF), Color(0xFF6F86D6)]),
    LiveGradientSwatch('mixed_hopes', 0, [Color(0xFFC471F5), Color(0xFFFA71CD)]),
    LiveGradientSwatch('deep_space', 0, [Color(0xFF141E30), Color(0xFF243B55)]),
    LiveGradientSwatch('royal', 135, [Color(0xFF141E30), Color(0xFF243B55), Color(0xFF141E30)]),
    LiveGradientSwatch('vicious_stance', 0, [Color(0xFF29323C), Color(0xFF485563)]),
    LiveGradientSwatch('night_sky', 0, [Color(0xFF1E3C72), Color(0xFF2A5298)]),
    LiveGradientSwatch('eternal_constance', 0, [Color(0xFF09203F), Color(0xFF537895)]),
    LiveGradientSwatch('premium_dark', 90, [Color(0xFF434343), Color(0xFF000000)]),
    LiveGradientSwatch('kind_steel', 90, [Color(0xFF243949), Color(0xFF517FA4)]),
    LiveGradientSwatch('cochiti_lake', 135, [Color(0xFF93A5CF), Color(0xFFE4EFE9)]),
  ];
}

/// One built-in gradient: its stored name, a CSS angle (0 up, clockwise)
/// and its colours, evenly spaced.
@immutable
final class LiveGradientSwatch {
  /// Creates the gradient.
  const new(this.name, this.degrees, this.colors);

  /// Its name (stored, not shown).
  final String name;

  /// The angle, CSS degrees.
  final int degrees;

  /// The colours.
  final List<Color> colors;
}
