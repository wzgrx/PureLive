import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/playback_hud_page.dart';
import 'package:pure_live/shared/rooms/playback_hud_config.dart';

import '../../support.dart';
import 'settings_harness.dart';

void main() {
  testWidgets('settings edit each position independently, preserve combined settings and reset all overrides', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(500, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(testServices))!;
    final strings = (await tester.runAsync(loadStrings))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: LiveUiScope(
          config: LiveUiConfig(strings: strings.ui),
          child: const MaterialApp(home: PlaybackHudPage()),
        ),
      ),
    );
    Future<void> tapKey(String key) async {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await settleSettings(tester);
    }

    await tapKey('playback-hud-separate');
    await tapKey('playback-hud-corner');
    await tester.tap(find.text('左上角').last);
    await settleSettings(tester);
    await tapKey('playback-hud-edit');
    await tester.tap(find.text('直播流网速').last);
    await settleSettings(tester);
    await tapKey('playback-hud-corner');
    await tester.tap(find.text('右下角').last);
    await settleSettings(tester);
    final config = PlaybackHudConfig.fromJson(services.store.settings.get(Settings.playbackHud));
    expect(config.separate, isTrue);
    expect(config.styleFor('clock').corner, 'topLeft');
    expect(config.styleFor('speed').corner, 'bottomRight');
    expect(config.corner, 'topRight');
    await tapKey('playback-hud-separate');
    expect(
      PlaybackHudConfig.fromJson(services.store.settings.get(Settings.playbackHud)).styleFor('speed').corner,
      'topRight',
    );
    await tapKey('playback-hud-reset');
    expect(services.store.settings.get(Settings.playbackHud), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(services.close);
  });
}
