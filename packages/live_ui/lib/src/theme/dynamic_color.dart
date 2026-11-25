import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart' as flutter;
import 'package:material_ui/material_ui.dart' as material;

// From 3.x lib/common/styles/dynamic_color_adapter.dart.

/// Harmonizes the system palette while preserving every Material 3 role.
/// The legacy function name remains available to callers after the migration
/// to the shared material_ui model.
flutter.ColorScheme toFlutterColorScheme(material.ColorScheme source) {
  final scheme = source.harmonized();
  return flutter.ColorScheme(
    brightness: scheme.brightness,
    primary: scheme.primary,
    onPrimary: scheme.onPrimary,
    primaryContainer: scheme.primaryContainer,
    onPrimaryContainer: scheme.onPrimaryContainer,
    primaryFixed: scheme.primaryFixed,
    primaryFixedDim: scheme.primaryFixedDim,
    onPrimaryFixed: scheme.onPrimaryFixed,
    onPrimaryFixedVariant: scheme.onPrimaryFixedVariant,
    secondary: scheme.secondary,
    onSecondary: scheme.onSecondary,
    secondaryContainer: scheme.secondaryContainer,
    onSecondaryContainer: scheme.onSecondaryContainer,
    secondaryFixed: scheme.secondaryFixed,
    secondaryFixedDim: scheme.secondaryFixedDim,
    onSecondaryFixed: scheme.onSecondaryFixed,
    onSecondaryFixedVariant: scheme.onSecondaryFixedVariant,
    tertiary: scheme.tertiary,
    onTertiary: scheme.onTertiary,
    tertiaryContainer: scheme.tertiaryContainer,
    onTertiaryContainer: scheme.onTertiaryContainer,
    tertiaryFixed: scheme.tertiaryFixed,
    tertiaryFixedDim: scheme.tertiaryFixedDim,
    onTertiaryFixed: scheme.onTertiaryFixed,
    onTertiaryFixedVariant: scheme.onTertiaryFixedVariant,
    error: scheme.error,
    onError: scheme.onError,
    errorContainer: scheme.errorContainer,
    onErrorContainer: scheme.onErrorContainer,
    surface: scheme.surface,
    onSurface: scheme.onSurface,
    surfaceDim: scheme.surfaceDim,
    surfaceBright: scheme.surfaceBright,
    surfaceContainerLowest: scheme.surfaceContainerLowest,
    surfaceContainerLow: scheme.surfaceContainerLow,
    surfaceContainer: scheme.surfaceContainer,
    surfaceContainerHigh: scheme.surfaceContainerHigh,
    surfaceContainerHighest: scheme.surfaceContainerHighest,
    onSurfaceVariant: scheme.onSurfaceVariant,
    outline: scheme.outline,
    outlineVariant: scheme.outlineVariant,
    shadow: scheme.shadow,
    scrim: scheme.scrim,
    inverseSurface: scheme.inverseSurface,
    onInverseSurface: scheme.onInverseSurface,
    inversePrimary: scheme.inversePrimary,
    surfaceTint: scheme.surfaceTint,
  );
}

/// Preserves the shared Material palette without regenerating its roles.
/// Flutter 3.50 applications and dynamic_color now use the same model.
material.ColorScheme toMaterialUiColorScheme(flutter.ColorScheme source) => source;

/// Preserves the complete shared theme, including component styles and
/// extensions. The old cross-library field copy would discard those styles.
material.ThemeData toMaterialUiThemeData(flutter.ThemeData source) => source;

/// Compatibility boundary for callers which used the pre-3.50 theme bridge.
/// Both sides now share material_ui's inherited theme, so no copy is needed.
class MaterialUiThemeBridge extends flutter.StatelessWidget {
  /// Leaves the complete inherited theme available to [child].
  const new({required this.child, super.key});

  /// The subtree.
  final flutter.Widget child;

  @override
  flutter.Widget build(flutter.BuildContext context) => child;
}

/// [DynamicColorBuilder] with the system palettes already converted by
/// [toFlutterColorScheme] (3.x `main.dart`).
///
/// Both schemes are null where the platform has no dynamic colour or has not
/// answered yet; then the app builds its theme from the user's colour.
class LiveDynamicColorBuilder extends flutter.StatelessWidget {
  /// Builds [builder] with the system's light and dark palettes.
  const new({required this.builder, super.key});

  /// Builds the app from the palettes.
  final flutter.Widget Function(flutter.ColorScheme? light, flutter.ColorScheme? dark) builder;

  @override
  flutter.Widget build(flutter.BuildContext context) {
    return DynamicColorBuilder(
      builder: (light, dark) {
        if (light == null || dark == null) return builder(null, null);
        return builder(toFlutterColorScheme(light), toFlutterColorScheme(dark));
      },
    );
  }
}
