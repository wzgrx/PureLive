import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/theme/live_theme.dart';
import 'package:live_ui/src/theme/text_styles.dart';
import 'package:live_ui/src/widgets/scrolling.dart';
import 'package:live_ui/src/widgets/settings_tiles.dart';
import 'package:live_ui/src/widgets/window_layout.dart';
import 'package:material_ui/material_ui.dart';

// The frame of the settings-like pages outside the settings feature
// (recording settings, backup, WebDAV, device sync; docs/A-界面设计/A10-录制界面/A10.2-录制设置,
// U.11a–c): the same app bar and reading column as the settings pages.

/// Builds the header of a shared settings page in its enclosing shell.
typedef SettingsPageHeaderBuilder = PreferredSizeWidget Function(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<Widget> actions,
  PreferredSizeWidget? bottom,
});

/// Lets another shell supply a settings header without replacing the page's
/// content or losing its actions. The regular phone and desktop header stays
/// unchanged when no scope is present.
class SettingsPageHeaderScope extends InheritedWidget {
  /// Supplies [builder] to the shared settings pages below.
  const new({required this.builder, required super.child, super.key});

  /// Builds the enclosing shell's header.
  final SettingsPageHeaderBuilder builder;

  /// The header supplied by the enclosing shell, if any.
  static SettingsPageHeaderScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsPageHeaderScope>();

  @override
  bool updateShouldNotify(SettingsPageHeaderScope oldWidget) => builder != oldWidget.builder;
}

/// The app bar of a settings-like page: the title at the platform's place
/// (3.x: the start on Android; [centerTitle] centres it), 20 px semi-bold, [subtitle] under it when given (the WebDAV server); a
/// compact height when the area is short (a phone held sideways or in split
/// screen, U.6a; [WindowClassScope]).
PreferredSizeWidget settingsPageAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<Widget> actions = const [],
  PreferredSizeWidget? bottom,
  bool centerTitle = false,
  VoidCallback? onBack,
}) {
  final custom = SettingsPageHeaderScope.maybeOf(context);
  if (custom != null) {
    return custom.builder(context, title: title, subtitle: subtitle, actions: actions, bottom: bottom);
  }
  final heading = Text(
    title,
    style: context.textStyles.t20.emphasis.copyWith(
      fontSize: SettingsPane.of(context) ? LiveFontSizes.of(Theme.of(context).textTheme).titleLarge * 18 / 20 : null,
    ),
  );
  return AppBar(
    leading: onBack == null ? null : BackButton(onPressed: onBack),
    title: subtitle == null
        ? heading
        : Column(
            crossAxisAlignment: centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              heading,
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.t12.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
    centerTitle: centerTitle,
    toolbarHeight: WindowClassScope.toolbarHeightOf(context),
    scrolledUnderElevation: 0,
    bottom: bottom,
    actions: [...actions, if (actions.isNotEmpty) const SizedBox(width: 4)],
  );
}

/// The scrolling body of a settings-like page: [children] (groups) in one
/// column at most [readableContentMaxWidth] wide, centred (UI_PLAN §5.3).
class SettingsPageList extends StatelessWidget {
  /// Creates the body.
  const new({required this.children, this.controller, this.physics, this.start = false, super.key});

  /// The groups and notes.
  final List<Widget> children;

  /// The scroll position.
  final ScrollController? controller;

  /// The scroll physics (pull to refresh needs an always scrollable one).
  final ScrollPhysics? physics;

  /// Keeps a reading column at the start, as the enclosing settings pane does.
  final bool start;

  @override
  Widget build(BuildContext context) {
    final embedded = start || SettingsPane.of(context);
    return SingleChildScrollView(
      controller: controller,
      physics: physics ?? const PureLiveScrollPhysics(),
      padding: EdgeInsets.fromLTRB(embedded ? 24 : 16, 0, embedded ? 24 : 16, 32),
      child: Align(
        alignment: embedded ? AlignmentDirectional.topStart : Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: readableContentMaxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}
