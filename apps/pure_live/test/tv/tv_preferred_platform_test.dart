import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_catalog.dart';
import 'package:pure_live/features/settings/settings_editors.dart';
import 'package:pure_live/tv/settings/tv_settings_style.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';

import '../qa_capture.dart';
import '../support.dart';

String? get _focused =>
    (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvOptionRow>()?.key
            as ValueKey<String>?)
        ?.value;

void main() {
  testWidgets('issue #22: a remote chooses a visible preferred platform and Back keeps the stored value', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final services = (await tester.runAsync(testServices))!;
    addTearDown(() => tester.runAsync(services.close));
    await tester.runAsync(loadStrings);
    await tester.runAsync(() async {
      await services.store.settings.set(Settings.hotAreasList, ['bilibili', 'douyu']);
      await services.store.settings.set(Settings.preferPlatform, 'bilibili');
    });
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2196F3), brightness: Brightness.dark);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
              child: TvTheme(
                palette: TvPalette.of(scheme),
                child: TvSettingsStyle(
                  child: Scaffold(
                    body: PreferPlatformTile(
                      entry: settingsCatalog.firstWhere((entry) => entry.id == 'prefer_platform'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('settings-entry-prefer_platform'));
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tv-choice-0')), findsOneWidget);
    expect(find.byType(TextField), findsNothing, reason: 'the remote does not need a phone search field');
    expect(_focused, 'tv-choice-0');
    await captureQaFrame(tester, 'tv-preferred-platform-current');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_focused, 'tv-choice-1');
    await captureQaFrame(tester, 'tv-preferred-platform-focused');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(services.store.settings.get(Settings.preferPlatform), 'douyu');
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(_focused, 'tv-choice-1', reason: 'the saved current platform receives focus on reopening');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(services.store.settings.get(Settings.preferPlatform), 'douyu');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
