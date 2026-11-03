import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/fonts.dart';
import 'package:pure_live/features/settings/font_manager_page.dart';

import '../../local_fonts_test.dart' show fontBytes;
import '../../support.dart';
import 'settings_harness.dart';

Future<({Directory temp, FontLibrary library, File source})> fixture(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final temp = await Directory.systemTemp.createTemp('purelive-font-ui-');
      final source = File(p.join(temp.path, '示例字体.ttf'))..writeAsBytesSync(fontBytes());
      final library = FontLibrary(
        root: Directory(p.join(temp.path, 'fonts')),
        http: NoNetworkHttp(),
        manifest: () async => '[]',
        register: (_, fonts) async {
          await Future.wait(fonts);
        },
      );
      addTearDown(() async {
        library.dispose();
        expect(p.isWithin(Directory.systemTemp.absolute.path, temp.absolute.path), isTrue);
        await temp.delete(recursive: true);
      });
      return (temp: temp, library: library, source: source);
    }))!;

Future<void> tapFontWithIo(WidgetTester tester, Finder finder) async {
  final widget = tester.widget(finder);
  final VoidCallback? action;
  if (widget is ButtonStyleButton) {
    action = widget.onPressed;
  } else if (widget is IconButton) {
    action = widget.onPressed;
  } else if (widget is MenuItemButton) {
    action = widget.onPressed;
  } else {
    throw StateError('Expected a real action button, found ${widget.runtimeType}');
  }
  expect(action, isNotNull);
  await tester.runAsync(() async {
    // Real file I/O must start outside the fake pointer-router zone. The
    // cancel test and native smoke still exercise actual pointer activation.
    action!();
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  await tester.pump();
  await settleSettingsFiles(tester);
}

void main() {
  testWidgets('canceling a native picker preserves selection and restores the import action', (tester) async {
    final data = await fixture(tester);
    final pick = Completer<LocalFontSelection?>();
    final harness = await pumpSettings(
      tester,
      page: const FontManagerPage(),
      overrides: [
        fontLibraryProvider.overrideWithValue(data.library),
        localFontPickerProvider.overrideWithValue(() => pick.future),
      ],
    );
    await settleSettingsFiles(tester);
    await tester.tap(find.byKey(const ValueKey('font-import')));
    await tester.pump();
    expect(find.text('导入中'), findsOneWidget);
    pick.complete(null);
    await tester.pumpAndSettle();
    expect(harness.settings.get(Settings.fontFamilyName), 'Default');
    expect(harness.toasts, isEmpty);
    expect(tester.widget<TextButton>(find.byKey(const ValueKey('font-import'))).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
  for (final danmaku in [false, true]) {
    testWidgets(
      'imported local font can be selected for ${danmaku ? 'danmaku' : 'app'} without changing the other role',
      (tester) async {
        final data = await fixture(tester);
        final harness = await pumpSettings(
          tester,
          page: FontManagerPage(danmaku: danmaku),
          overrides: [
            fontLibraryProvider.overrideWithValue(data.library),
            localFontPickerProvider.overrideWithValue(() async => (file: data.source, name: '示例字体.ttf')),
          ],
        );
        await settleSettingsFiles(tester);
        await tapFontWithIo(tester, find.byKey(const ValueKey('font-import')));
        final family = (await tester.runAsync(data.library.families))!.single;
        expect(find.text('示例字体'), findsOneWidget);
        expect(harness.toasts.last, contains('示例字体'));
        expect(harness.settings.get(Settings.fontFamilyName), 'Default');
        expect(harness.settings.get(Settings.danmakuFontFamilyName), 'Default');
        await tapFontWithIo(tester, find.byKey(ValueKey('font-apply-${family.id}')));
        expect(harness.settings.get(danmaku ? Settings.danmakuFontFamilyName : Settings.fontFamilyName), family.id);
        expect(harness.settings.get(danmaku ? Settings.fontFamilyName : Settings.danmakuFontFamilyName), 'Default');
        expect(find.byKey(ValueKey('font-active-${family.id}')), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('font-more-${family.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('font-delete-${family.id}')));
        await tester.pumpAndSettle();
        await tapFontWithIo(
          tester,
          find
              .ancestor(of: find.text('删除').last, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
              .first,
        );
        // The confirmation route completes on the next fake frame, and only
        // then starts the real file deletion and settings writes.
        for (var attempt = 0; attempt < 10; attempt++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
          await tester.pump(const Duration(seconds: 1));
          if (find.byKey(ValueKey('font-family-${family.id}')).evaluate().isEmpty) break;
        }
        expect(find.byKey(ValueKey('font-family-${family.id}')), findsNothing);
        expect(harness.settings.get(Settings.fontFamilyName), 'Default');
        expect(harness.settings.get(Settings.danmakuFontFamilyName), 'Default');
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [280.0, 400.0, 960.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('local font management fits width $width, dark=$dark and 2x text', (tester) async {
        final data = await fixture(tester);
        final family = (await tester.runAsync(
          () => data.library.importLocal(data.source, fileName: '${'长字体名称' * 12}.ttf'),
        ))!.family;
        await pumpSettings(
          tester,
          width: width,
          height: 900,
          textScale: 2,
          dark: dark,
          page: const FontManagerPage(),
          seed: (settings) => settings.set(Settings.fontFamilyName, family.id),
          overrides: [fontLibraryProvider.overrideWithValue(data.library)],
        );
        await settleSettingsFiles(tester);
        expect(find.byKey(const ValueKey('font-import')), findsOneWidget);
        expect(find.byType(IconButton).evaluate().any((e) => (e.widget as IconButton).tooltip == '导入字体'), isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
