import 'package:material_ui/material_ui.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// The shared destinations that can stay in the settings content navigator.
class SettingsContentNavigation extends InheritedWidget {
  /// Provides the page factory to settings-like pages below the navigator.
  const new({required this.pageBuilder, required super.child, super.key});

  /// Builds a supported settings destination, or null for a global route.
  final Widget? Function(RouteArgs route) pageBuilder;

  @override
  bool updateShouldNotify(SettingsContentNavigation oldWidget) => pageBuilder != oldWidget.pageBuilder;
}

/// Opens a settings destination inside its content pane when present.
/// Standalone pages and destinations outside settings keep the root route.
Future<T?> openSettingsDestination<T extends Object?>(BuildContext context, String path, {Object? arguments}) {
  final scope = context.getInheritedWidgetOfExactType<SettingsContentNavigation>();
  final page = scope?.pageBuilder(RouteArgs(path, arguments: arguments));
  if (page == null) return AppNavigator.toNamed<T>(path, arguments: arguments);
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      settings: RouteSettings(name: path, arguments: arguments),
      builder: (_) => page,
    ),
  );
}
