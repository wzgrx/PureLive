// The settings page over an in-memory store, shared by the settings tests.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_editors.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';

/// What a test reads back: the services, the toasts, the routes opened.
final class SettingsHarness {
  /// Creates the harness.
  new(this.services, this.toasts, this.opened);

  /// The services.
  final AppServices services;

  /// The toasts shown.
  final List<String> toasts;

  /// The routes opened.
  final List<String> opened;

  /// The settings.
  SettingsStore get settings => services.store.settings;
}

/// Pumps the settings page over an in-memory store at [width] × [height];
/// other routes show their path (so links can be checked).
Future<SettingsHarness> pumpSettings(
  WidgetTester tester, {
  double width = 400,
  double height = 1600,
  Object? arguments,
  Future<void> Function(SettingsStore settings)? seed,
  List<Override> overrides = const [],
  Widget? page,
  double? textScale,
  bool dark = false,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The floating-window danmaku preview stands still (as with the system's
  // "remove animations"), so frames settle.
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    await seed?.call(services.store.settings);
    return services;
  }))!;
  addTearDown(() => tester.runAsync(services.close));
  addTearDown(AutoExitTimer.instance.detach);
  final strings = (await tester.runAsync(loadStrings))!;
  final toasts = <String>[];
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previousToast);
  final opened = <String>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => page ?? SettingsPage(route: RouteArgs(RoutePath.kSettings, arguments: arguments)),
      ),
      for (final path in [
        RoutePath.kSettingsDanmuShield,
        RoutePath.kSettingsAccount,
        RoutePath.kBackup,
        RoutePath.kIptv,
        RoutePath.kRecordSettings,
        RoutePath.kLocalInteraction,
        RoutePath.kLogs,
        RoutePath.kWebDavPage,
        RoutePath.kSettingsHotAreas,
        RoutePath.kSettingsTags,
      ])
        GoRoute(
          path: path,
          builder: (_, _) {
            opened.add(path);
            return Scaffold(body: Text('page $path'));
          },
        ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() => AppNavigator.router = null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services), ...overrides],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp.router(
          theme: const LiveTheme(primaryColor: LiveTheme.brandBlue, schemeVariant: DynamicSchemeVariant.fidelity).light,
          darkTheme: const LiveTheme(
            primaryColor: LiveTheme.brandBlue,
            schemeVariant: DynamicSchemeVariant.fidelity,
          ).dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: textScale == null
              ? null
              : (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
          routerConfig: router,
        ),
      ),
    ),
  );
  if (page == null) {
    await settleSettings(tester);
  } else {
    await settleSettingsFiles(tester);
  }
  return SettingsHarness(services, toasts, opened);
}

/// Lets the store's writes (real async work) finish, then the frames.
Future<void> settleSettings(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}

/// Lets a local directory read finish between fake-clock frames. [where]
/// names the page being waited on, so a stall says which one and how.
Future<void> settleSettingsFiles(WidgetTester tester, {String? where}) async {
  var spinners = 0;
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump(const Duration(seconds: 1));
    spinners = find.byType(CircularProgressIndicator).evaluate().length;
    if (spinners == 0 && !tester.binding.hasScheduledFrame) return;
  }
  fail(
    'the generated-data settings page did not finish its local reads'
    '${where == null ? '' : ' ($where)'}: $spinners spinner(s), '
    'a frame still scheduled: ${tester.binding.hasScheduledFrame}, '
    'status views: ${_statusTypes(tester)}, holders: ${_spinnerHolders(tester)}',
  );
}

/// The status cards on screen, by their type.
String _statusTypes(WidgetTester tester) {
  final views = tester.widgetList<AppStatusView>(find.byType(AppStatusView)).toList();
  return views.isEmpty ? 'none' : views.map((view) => view.type.name).join('+');
}

/// The public widget classes above each spinner, with the keys on the way and
/// the words of the row that holds it, so a stall names the exact busy row.
String _spinnerHolders(WidgetTester tester) {
  final spinner = find.byType(CircularProgressIndicator);
  if (spinner.evaluate().isEmpty) return 'none';
  final names = <String>[];
  final keys = <String>[];
  Element? row;
  for (final element in tester.elementList(spinner)) {
    var depth = 0;
    element.visitAncestorElements((ancestor) {
      final name = ancestor.widget.runtimeType.toString();
      if (!name.startsWith('_')) names.add(name);
      final key = ancestor.widget.key;
      if (key is ValueKey<String>) keys.add(key.value);
      if (row == null && ancestor.widget is Row) row = ancestor;
      // Enough to name the page; the chain goes on up to the app root.
      return ++depth < 14;
    });
  }
  final words = row == null ? '' : ' words: ${_words(row!).join('/')}';
  return '${keys.isEmpty ? 'no keys' : keys.join('+')}$words < ${names.take(8).join(' < ')}';
}

/// The words below [root], a bounded walk, so a busy row can be read back.
List<String> _words(Element root, {int limit = 4}) {
  final found = <String>[];
  void walk(Element node) {
    if (found.length >= limit) return;
    final widget = node.widget;
    if (widget is Text && widget.data?.isNotEmpty == true) found.add(widget.data!);
    node.visitChildren(walk);
  }

  walk(root);
  return found;
}

/// The row of a catalogue entry.
Finder settingsRow(String id) => find.byKey(ValueKey('settings-entry-$id'));

/// The overview row of a page.
Finder settingsSection(SettingsSection section) => find.byKey(ValueKey('settings-section-${section.name}'));

/// Taps [finder] after scrolling it into view, then settles.
Future<void> tapSettings(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await settleSettings(tester);
}

/// Types a search.
Future<void> searchSettingsFor(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('settings-search')), text);
  // The search waits for a pause in typing.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// The top of [finder].
double topOf(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

/// [finders] from top to bottom.
void expectInOrder(WidgetTester tester, List<Finder> finders) {
  for (var i = 1; i < finders.length; i++) {
    expect(topOf(tester, finders[i]), greaterThan(topOf(tester, finders[i - 1])), reason: '$i');
  }
}

/// Runs [body] as if on [platform].
Future<void> withPlatform(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
