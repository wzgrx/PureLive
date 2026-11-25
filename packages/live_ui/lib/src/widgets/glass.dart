import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';

/// Liquid glass (A01.5): a pane of frosted, tinted glass with a light rim,
/// for a bar that floats over scrolling content. Off by default
/// (`Settings.liquidGlass`); never over the video (UI.md §9.3).
///
/// Without [blur] (a phone with little memory, A01.5 c4) the pane is the
/// same tint, more opaque, and nothing behind it is blurred.
class GlassSurface extends StatelessWidget {
  /// Creates the pane.
  const new({required this.child, this.radius = GlassMetrics.barRadius, this.blur = true, super.key});

  /// What sits on the glass.
  final Widget child;

  /// The corners' radius.
  final double radius;

  /// Whether what is behind is blurred.
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);
    final tint = scheme.surfaceContainer;
    final pane = DecoratedBox(
      key: const ValueKey('glass-pane'),
      decoration: BoxDecoration(
        borderRadius: shape,
        // Lighter at the top, as light falls on curved glass.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: blur
              ? [tint.withValues(alpha: dark ? 0.50 : 0.58), tint.withValues(alpha: dark ? 0.66 : 0.74)]
              : [tint.withValues(alpha: 0.92), tint.withValues(alpha: 0.96)],
        ),
      ),
      child: CustomPaint(
        foregroundPainter: _GlassRimPainter(radius: radius, dark: dark),
        child: child,
      ),
    );
    return DecoratedBox(
      // The shadow only floating layers have (§9.3), soft and close.
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.32 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: blur
            ? BackdropFilter(
                key: const ValueKey('glass-blur'),
                filter: ImageFilter.blur(sigmaX: GlassMetrics.blurSigma, sigmaY: GlassMetrics.blurSigma),
                child: pane,
              )
            : pane,
      ),
    );
  }
}

/// The sizes of liquid glass (A01.5).
abstract final class GlassMetrics {
  /// The blur behind the glass.
  static const double blurSigma = 24;

  /// What a bar on the glass paints behind itself: nothing, the glass
  /// shows through.
  static const Color clear = Color(0x00000000);

  /// A floating bar's corners: a capsule at [barHeight].
  static const double barRadius = 34;

  /// The floating bottom bar's height.
  static const double barHeight = 68;

  /// The floating bar's height when the bottom bar is compact (V02.11,
  /// issue #9: "底栏高度太高").
  static const double barHeightCompact = 56;

  /// The plain bar's height when the bottom bar is compact; Material's
  /// own is 80.
  static const double plainBarHeightCompact = 64;

  /// The gap at the floating bar's sides, and under it where the system
  /// leaves no room at the bottom.
  static const double barMargin = 12;

  /// The floating bar's widest: on a tablet (V02.6) the capsule stays this
  /// wide in the middle instead of spreading its few items across the
  /// screen; a phone is narrower anyway.
  static const double barMaxWidth = 560;

  /// The room under the floating bar, from the screen's bottom edge
  /// (V02.11, issue #9: "玻璃底栏下面空了好多"). Over a home indicator or a
  /// gesture handle the capsule sits just clear of it, as iOS 26's own bar
  /// does, rather than [barMargin] above the whole of [safeBottom]: iOS
  /// draws its indicator at the bottom of the 34 (the capsule 20 up),
  /// Android its handle in the middle of the inset (the capsule 6 above
  /// it). Android's buttons, a taller inset, keep [barMargin] above them.
  static double barGap({required double safeBottom, required bool ios}) {
    if (safeBottom <= 0) return barMargin;
    if (ios) return math.max(barMargin, safeBottom - 14);
    if (safeBottom > 40) return safeBottom + barMargin;
    return math.max(barMargin, safeBottom / 2 + 8);
  }
}

/// The light rim of [GlassSurface]: brighter along the top-left edge,
/// fading out, and a faint return along the bottom-right, the highlight a
/// curved edge catches.
class _GlassRimPainter extends CustomPainter {
  new({required this.radius, required this.dark});

  final double radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rim = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));
    const light = Colors.white;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          light.withValues(alpha: dark ? 0.30 : 0.75),
          light.withValues(alpha: 0),
          light.withValues(alpha: 0),
          light.withValues(alpha: dark ? 0.12 : 0.35),
        ],
        stops: const [0, 0.42, 0.62, 1],
      ).createShader(rect);
    canvas.drawRRect(rim, paint);
    // A soft sheen inside the top edge.
    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [
          light.withValues(alpha: dark ? 0.06 : 0.18),
          light.withValues(alpha: 0),
        ],
      ).createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), sheen);
  }

  @override
  bool shouldRepaint(_GlassRimPainter oldDelegate) => oldDelegate.radius != radius || oldDelegate.dark != dark;
}

/// How far a floating glass bar covers the bottom of the page under it
/// (A01.5): scrolling content adds it below its last item, so the end can
/// be scrolled clear of the bar. Zero without a floating bar.
class GlassBarInset extends InheritedWidget {
  /// Provides [inset] below.
  const new({required this.inset, required super.child, super.key});

  /// The height covered.
  final double inset;

  /// The height covered where [context] is: zero outside a floating bar.
  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassBarInset>()?.inset ?? 0;

  @override
  bool updateShouldNotify(GlassBarInset oldWidget) => oldWidget.inset != inset;
}

/// Room for a floating glass bar (A01.5).
extension GlassBarPadding on EdgeInsets {
  /// These insets with [GlassBarInset.of] added at the bottom.
  EdgeInsets withGlassBar(BuildContext context) => copyWith(bottom: bottom + GlassBarInset.of(context));
}
