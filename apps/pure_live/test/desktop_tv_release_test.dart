import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/iptv/iptv_cards.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';
import 'package:pure_live/tv/settings/tv_settings_style.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';

import 'qa_capture.dart';
import 'support.dart';

void main() {
  testWidgets('the room settings toggle persists the existing fullscreen SC preference', (tester) async {
    await prepareQaFonts(tester);
    final services = (await tester.runAsync(testServices))!;
    await tester.runAsync(loadStrings);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          theme: const LiveTheme().light,
          home: const Scaffold(body: SingleChildScrollView(child: ChatListSettings())),
        ),
      ),
    );
    final toggle = find.byKey(const ValueKey('danmaku-switch-fullscreenSuperChat'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pump();
    expect(services.store.settings.get(Settings.showFullscreenSuperChat), isFalse);
    await tester.pump(const Duration(seconds: 1));
    await captureQaFrame(tester, 'sc-setting-off');
    await tester.tap(toggle);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pump();
    expect(services.store.settings.get(Settings.showFullscreenSuperChat), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(services.close);
  });

  for (final guide in [false, true]) {
    testWidgets('TV auto sync is one focus stop with a visible frame: guide=$guide', (tester) async {
      await tester.runAsync(loadStrings);
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var changes = 0;
      var saving = false;
      var autoUpdate = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: const LiveTheme().dark,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 900,
                child: TvSettingsStyle(
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return IptvSourceCard(
                        id: 'sample',
                        isGuide: guide,
                        name: 'Sample',
                        address: 'https://example.com/list',
                        badge: 'M3U',
                        isRemote: true,
                        details: '',
                        autoUpdate: autoUpdate,
                        busy: saving,
                        blocked: saving,
                        onSync: () {},
                        onDelete: () {},
                        onAutoUpdate: (value) {
                          changes++;
                          update(() {
                            saving = true;
                            autoUpdate = value;
                          });
                        },
                        onAction: (_) {},
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      const rowKey = ValueKey('iptv-auto-row-sample');
      Key? focusedRow() =>
          FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<SettingsRow>()?.key;
      for (var i = 0; i < 10 && focusedRow() != rowKey; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusedRow(), rowKey);
      final containers = tester.widgetList<DecoratedBox>(
        find.descendant(of: find.byKey(rowKey), matching: find.byType(DecoratedBox)),
      );
      expect(
        containers.any(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).border == Border.all(color: LiveTvColors.focusFrame, width: 3),
        ),
        isTrue,
      );
      await captureQaFrame(tester, 'tv-auto-sync-$guide');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(changes, 1);
      expect(focusedRow(), rowKey, reason: 'saving must not move focus to an adjacent destructive action');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(changes, 1, reason: 'a second confirmation while saving must be ignored');
      update(() => saving = false);
      await tester.pump();
      expect(focusedRow(), rowKey, reason: 'focus must still identify the row after saving');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(focusedRow(), isNot(rowKey), reason: 'one left press exits the whole row, without stopping on the switch');
      expect(changes, 1, reason: 'navigation does not toggle');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('TV option presenter preserves the platform leading image', (tester) async {
    await tester.runAsync(loadStrings);
    await tester.pumpWidget(
      MaterialApp(
        theme: const LiveTheme().dark,
        home: Scaffold(
          body: TvSettingsStyle(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppOptionDialog<String>(
                  context: context,
                  title: 'Platform',
                  selected: 'sample',
                  options: const [
                    AppDialogOption(
                      value: 'sample',
                      label: 'Sample',
                      leading: SizedBox(key: ValueKey('platform-logo-proof'), width: 24, height: 24),
                    ),
                  ],
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(TvOptionRow), findsOneWidget);
    expect(find.byKey(const ValueKey('platform-logo-proof')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
