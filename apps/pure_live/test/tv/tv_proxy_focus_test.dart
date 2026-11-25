// A17.17: disabled proxy fields must not swallow directional TV focus.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/tv/settings/tv_settings_section_page.dart';
import 'package:pure_live/tv/tv_theme.dart';

import '../support.dart';

Future<AppServices> _pump(WidgetTester tester, {required double width, bool appEnabled = false}) async {
  tester.view
    ..physicalSize = Size(width, 1080)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    await services.store.settings.setAll({Settings.enableAppProxy: appEnabled, Settings.enableProxy: false});
    return services;
  }))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final colors = ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: ThemeData(colorScheme: colors),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
              child: TvTheme(
                palette: TvPalette.of(colors),
                child: const TvSettingsSectionPage(section: SettingsSection.network),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return services;
}

FocusNode _switch(WidgetTester tester, String proxy) => Focus.of(
  tester.element(
    find.descendant(of: find.byKey(ValueKey('settings-proxy-$proxy-switch')), matching: find.byType(Text)).first,
  ),
);

FocusNode _field(WidgetTester tester, String field) => tester
    .widget<EditableText>(
      find.descendant(of: find.byKey(ValueKey('settings-proxy-$field')), matching: find.byType(EditableText)),
    )
    .focusNode;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    testWidgets('issue52: disabled fields at $width do not hide Down/Up focus', (tester) async {
      final services = await _pump(tester, width: width);
      expect(_switch(tester, 'app').hasPrimaryFocus, isTrue);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_switch(tester, 'player').hasPrimaryFocus, isTrue, reason: 'skip disabled app host and port');
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_switch(tester, 'app').hasPrimaryFocus, isTrue, reason: 'Up returns to the visible app switch');
      expect(services.store.settings.get(Settings.enableAppProxy), isFalse);
      expect(services.store.settings.get(Settings.enableProxy), isFalse);
    });
  }

  testWidgets('issue52: enabled address and port remain reachable, disabled player fields do not', (tester) async {
    await _pump(tester, width: 1920, appEnabled: true);
    expect(_switch(tester, 'app').hasPrimaryFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_field(tester, 'app-host').hasPrimaryFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.tab);
    expect(_field(tester, 'app-port').hasPrimaryFocus, isTrue);
    await _press(tester, LogicalKeyboardKey.tab);
    expect(_switch(tester, 'player').hasPrimaryFocus, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await _press(tester, LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(_field(tester, 'app-port').hasPrimaryFocus || _field(tester, 'app-host').hasPrimaryFocus, isTrue);
  });
}
