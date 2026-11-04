import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/menu_button.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/background/custom_background.dart';

/// The phone layout (3.x `HomeMobileView`): the page and a bottom bar; the
/// bar is hidden with one destination.
///
/// With [glass] (A01.5, A01.6) the bar floats over the page as a capsule
/// of liquid glass ([LiquidGlassBar]), the page scrolling on under it;
/// [glassBlur] off, the glass is a plain tint; [frost] (A01.8) is how
/// frosted it is. [compact] (V02.11) lowers either bar.
class HomeMobileView extends StatelessWidget {
  /// Creates the layout.
  const new({
    required this.menus,
    required this.selected,
    required this.onSelected,
    required this.body,
    this.glass = false,
    this.glassBlur = true,
    this.compact = false,
    this.frost = 0.5,
    this.hidden = false,
    this.showLabels = true,
    super.key,
  });

  /// The destinations.
  final List<HomeMenu> menus;

  /// The destination shown.
  final HomeMenu? selected;

  /// A destination was tapped.
  final ValueChanged<HomeMenu> onSelected;

  /// The page.
  final Widget body;

  /// The bar is liquid glass.
  final bool glass;

  /// The glass blurs the page behind it.
  final bool glassBlur;

  /// The bar is lower (`Settings.homeBottomBarCompact`).
  final bool compact;

  /// How frosted the glass is (`Settings.liquidGlassFrost`).
  final double frost;

  /// Hides both plain and glass bottom navigation while reading content.
  final bool hidden;

  /// Visible destination labels; semantic names always remain available.
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final index = selected == null ? 0 : menus.indexOf(selected!);
    NavigationBar bar({double? height, Color? background}) => NavigationBar(
      height: height,
      backgroundColor: background,
      elevation: background == null ? null : 0,
      surfaceTintColor: background,
      shadowColor: background,
      selectedIndex: index < 0 ? 0 : index,
      onDestinationSelected: (index) => onSelected(menus[index]),
      labelBehavior: showLabels
          ? NavigationDestinationLabelBehavior.alwaysShow
          : NavigationDestinationLabelBehavior.alwaysHide,
      destinations: [
        for (final menu in menus)
          NavigationDestination(
            key: ValueKey('home-nav-${menu.id}'),
            icon: Icon(menu.icon),
            selectedIcon: Icon(menu.selectedIcon),
            label: i18n(menu.titleKey),
          ),
      ],
    );
    // The tab's AppBar normally consumes the status-bar inset. While it is
    // hidden, the shell owns all system insets instead. Keep this wrapper
    // mounted so changing visibility does not recreate a tab or its scroll.
    final content = SafeArea(top: hidden, bottom: hidden, left: hidden, right: hidden, child: body);
    if (menus.length <= 1) return Scaffold(body: content);
    if (!glass) {
      return Scaffold(
        bottomNavigationBar: hidden ? null : bar(height: compact ? GlassMetrics.plainBarHeightCompact : null),
        body: content,
      );
    }
    final barHeight = compact ? GlassMetrics.barHeightCompact : GlassMetrics.barHeight;
    final gap = GlassMetrics.barGap(
      safeBottom: MediaQuery.viewPaddingOf(context).bottom,
      ios: defaultTargetPlatform == TargetPlatform.iOS,
    );
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: hidden
          ? null
          : Padding(
              key: const ValueKey('home-glass-bar'),
              padding: EdgeInsets.fromLTRB(GlassMetrics.barMargin, 0, GlassMetrics.barMargin, gap),
              child: Align(
                heightFactor: 1,
                child: SizedBox(
                  height: barHeight,
                  width: GlassMetrics.barMaxWidth,
                  // A01.6: refraction and the drop where the shader runs, frosted
                  // glass elsewhere, a plain tint on a phone with little memory.
                  child: LiquidGlassBar(
                    height: barHeight,
                    frost: frost,
                    blur: glassBlur,
                    refraction: glassBlur,
                    showLabels: showLabels,
                    selectedIndex: index < 0 ? 0 : index,
                    onSelected: (index) => onSelected(menus[index]),
                    items: [
                      for (final menu in menus)
                        LiquidGlassBarItem(
                          key: ValueKey('home-nav-${menu.id}'),
                          icon: menu.icon,
                          selectedIcon: menu.selectedIcon,
                          label: i18n(menu.titleKey),
                        ),
                    ],
                  ),
                ),
              ),
            ),
      body: GlassBarInset(inset: hidden ? 0 : gap + barHeight, child: content),
    );
  }
}

/// Sizes of the side rail (docs/A-界面设计/A06-首页和全局/A06.2-宽屏首页, Material 3's rail).
abstract final class HomeRailMetrics {
  /// The rail's width.
  static const double width = 80;

  /// The menu button's row: the 48 button with 12 above and 8 below.
  static const double menuHeight = 68;

  /// A tool button's row: the 48 button, its name and 6 below.
  static const double toolHeight = 66;

  /// The line between the tools and the destinations.
  static const double separatorHeight = 21;

  /// A destination: the 56 × 32 indicator, its name, 4 above and 12 below.
  static const double destinationHeight = 68;
}

/// The tablet and desktop layout (3.x `HomeTabletView`): a side rail with
/// the menu, the tool buttons with their names (search, watch history, link
/// parser, multi-view), a short line, then the destinations, the recording
/// centre among them (U.3b c2–c5); a vertical line; the page.
///
/// The whole rail scrolls in short windows, as in 3.x. Every entry shares
/// one drag area, including the destinations, rather than leaving only a
/// small tool viewport above fixed destinations.
class HomeTabletView extends ConsumerWidget {
  /// Creates the layout.
  const new({required this.menus, required this.selected, required this.onSelected, required this.body, super.key});

  /// The destinations.
  final List<HomeMenu> menus;

  /// The destination shown.
  final HomeMenu? selected;

  /// A destination was tapped.
  final ValueChanged<HomeMenu> onSelected;

  /// The page.
  final Widget body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multiView = watchSetting(ref, Settings.enableMultiView);
    final desktopLabels = watchSetting(ref, Settings.desktopNavigationLabels);
    final mobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    final showLabels = mobile || desktopLabels;
    final scheme = Theme.of(context).colorScheme;
    final top = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, 8), child: MenuButton()),
        for (final action in homeActions(multiView: multiView))
          _RailTool(
            key: ValueKey('home-rail-${action.name}'),
            icon: action.icon,
            label: i18n(action.labelKey),
            onTap: () => unawaited(action.run()),
            showLabels: showLabels,
          ),
      ],
    );
    final destinations = [
      for (final menu in menus)
        _RailDestination(
          key: ValueKey('home-nav-${menu.id}'),
          menu: menu,
          selected: menu == selected,
          onTap: () => onSelected(menu),
          showLabels: showLabels,
        ),
    ];
    final separator = Container(
      key: const ValueKey('home-rail-separator'),
      width: 40,
      height: 1,
      margin: const EdgeInsets.only(top: 6, bottom: 14),
      color: scheme.outlineVariant,
    );
    final rail = _HomeRailScroll(child: Column(children: [top, separator, ...destinations]));
    final background = CustomBackgroundFrame.activeOf(context);
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Paint through this rail's safe areas so the status-bar corner
          // and bottom inset cannot reveal a different rectangle.
          CustomBackgroundSurface(
            key: const ValueKey('home-rail-surface'),
            child: SafeArea(
              right: false,
              child: PrimaryScrollController.none(
                child: Material(
                  key: const ValueKey('home-rail'),
                  color: background ? OnVideoColors.clear : scheme.surface,
                  child: SizedBox(
                    width: HomeRailMetrics.width,
                    child: FocusTraversalGroup(child: rail),
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: SafeArea(left: false, child: body)),
        ],
      ),
    );
  }
}

/// One owned controller connects desktop thumb gestures to this rail only.
class _HomeRailScroll extends StatefulWidget {
  const new({required this.child});
  final Widget child;

  @override
  State<_HomeRailScroll> createState() => _HomeRailScrollState();
}

class _HomeRailScrollState extends State<_HomeRailScroll> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _scroll,
    child: SingleChildScrollView(controller: _scroll, primary: false, child: widget.child),
  );
}

/// The state a rail item draws: the hover or press layer and the keyboard
/// focus.
typedef _RailState = ({Color? layer, bool focused});

/// Hover, focus (keyboard only) and press of a rail item, drawn by the item
/// on its indicator rather than over the whole cell (Material 3's rail).
class _RailItem extends StatefulWidget {
  const new({required this.label, required this.onTap, required this.builder, this.selected, this.showTooltip = false});

  final String label;
  final VoidCallback onTap;
  final bool? selected;
  final bool showTooltip;

  /// Builds the item from its state: the layer to put on the indicator and
  /// whether the keyboard focus is here.
  final Widget Function(BuildContext context, _RailState state) builder;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyboard = _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final layer = _pressed || keyboard
        ? scheme.onSurface.withValues(alpha: 0.1)
        : (_hovered ? scheme.onSurface.withValues(alpha: 0.08) : null);
    final item = Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hovered = value),
        onHighlightChanged: (value) => setState(() => _pressed = value),
        onFocusChange: (value) => setState(() => _focused = value),
        overlayColor: WidgetStatePropertyAll(scheme.onSurface.withValues(alpha: 0)),
        splashFactory: NoSplash.splashFactory,
        child: widget.builder(context, (layer: layer, focused: keyboard)),
      ),
    );
    return widget.showTooltip ? Tooltip(message: widget.label, excludeFromSemantics: true, child: item) : item;
  }
}

/// The text of a rail item: 12 points, one line, 16 high (taller when the
/// system font is larger).
Widget _railLabel(BuildContext context, String label, {required Color color, FontWeight? weight}) => Text(
  label,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: context.textStyles.t12.copyWith(color: color, fontWeight: weight, height: 16 / 12),
);

/// A tool button of the rail: a round 48 button with its name under it
/// (U.3b c2; 3.x showed the name only on hover or a long press).
class _RailTool extends StatelessWidget {
  const new({required this.icon, required this.label, required this.onTap, this.showLabels = true, super.key});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _RailItem(
      label: label,
      onTap: onTap,
      showTooltip: !showLabels,
      builder: (context, state) => ConstrainedBox(
        constraints: const BoxConstraints.tightFor(width: HomeRailMetrics.width),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: kMinInteractiveDimension,
                height: kMinInteractiveDimension,
                decoration: BoxDecoration(
                  color: state.layer,
                  shape: BoxShape.circle,
                  border: state.focused ? Border.all(color: scheme.primary, width: 2) : null,
                ),
                child: Icon(icon, color: scheme.onSurfaceVariant),
              ),
              if (showLabels)
                Transform.translate(
                  offset: const Offset(0, -4),
                  child: _railLabel(context, label, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A destination of the rail, as Material 3 draws it: the icon in a 56 × 32
/// indicator (filled when selected) and the name under it.
class _RailDestination extends StatelessWidget {
  const new({required this.menu, required this.selected, required this.onTap, this.showLabels = true, super.key});

  final HomeMenu menu;
  final bool selected;
  final VoidCallback onTap;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = i18n(menu.titleKey);
    return _RailItem(
      label: label,
      selected: selected,
      showTooltip: !showLabels,
      onTap: onTap,
      builder: (context, state) => ConstrainedBox(
        constraints: const BoxConstraints.tightFor(width: HomeRailMetrics.width),
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                width: 56,
                height: 32,
                decoration: BoxDecoration(
                  color: selected ? scheme.secondaryContainer : null,
                  borderRadius: BorderRadius.circular(16),
                  border: state.focused ? Border.all(color: scheme.primary, width: 2) : null,
                ),
                foregroundDecoration: state.layer == null
                    ? null
                    : BoxDecoration(color: state.layer, borderRadius: BorderRadius.circular(16)),
                child: Icon(
                  selected ? menu.selectedIcon : menu.icon,
                  color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
                ),
              ),
              if (showLabels) ...[
                const SizedBox(height: 4),
                _railLabel(
                  context,
                  label,
                  color: scheme.onSurface,
                  weight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
