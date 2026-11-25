import 'package:material_ui/material_ui.dart';

// 3.x's settings builders (`AppLayoutFactory`: `buildGroupTitle`,
// `buildModernCard`, `buildSwitchTile`, `buildTile`, `buildSliderTile`,
// `SectionTitle`, `MenuListTile`) are gone: every page uses the one settings
// row ([SettingsGroup], [SettingsLinkRow], [SettingsSwitchRow] …,
// docs/A-界面设计/A02-组件/A02.1-通用组件 c16), and reading columns are at most 720 wide
// instead of 3.x's 960 (U.1c c18).

/// The widest a reading column gets on large screens (settings-like pages,
/// details; docs/specs/UI.md §5.3): one column, centred.
const double readableContentMaxWidth = 720;

/// Marks the content side of a wide settings window for all shared pages.
class SettingsPane extends InheritedWidget {
  /// Marks [child] as inside the right pane.
  const new({required super.child, super.key});

  /// Whether a page belongs to the wide settings content pane.
  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SettingsPane>() != null;

  @override
  bool updateShouldNotify(SettingsPane oldWidget) => false;
}

/// [child] in a centred column at most [readableContentMaxWidth] wide (the
/// whole width on narrower screens).
class ReadableContent extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, this.alignment, this.maxWidth = readableContentMaxWidth, super.key});

  /// The column.
  final Widget child;

  /// Placement in its enclosing page.
  final AlignmentGeometry? alignment;

  /// Width including any padding supplied by [child].
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment ?? (SettingsPane.of(context) ? AlignmentDirectional.topStart : Alignment.topCenter),
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
