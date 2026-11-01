import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/shared/background/custom_background.dart';

import '../../support.dart';

void main() {
  test('imported preferences cannot escape the owned folder or select invalid appearance', () {
    for (final path in ['/tmp/private.png', '../background-a.png', 'background-a.png/../secret', 'file:///secret']) {
      expect(CustomBackgroundConfig.fromJson({'kind': 'image', 'file': path}).file, isEmpty);
    }
    final config = CustomBackgroundConfig.fromJson(const {
      'kind': 'bad',
      'mask': double.nan,
      'fit': 'invalid',
      'color': -1,
    });
    expect(config.toJson(), const CustomBackgroundConfig().toJson());
    expect(CustomBackgroundConfig.fromJson(const {'mask': 99}).mask, 1);
    expect(CustomBackgroundConfig.fromJson(const {'mask': -1}).mask, 0);
    expect(CustomBackgroundConfig.fromJson(const {'color': 0}).color, 0xff000000);
  });

  testWidgets('image import resizes once, keeps originals and deletes only obsolete owned copies', (tester) async {
    await tester.runAsync(() async {
      final directory = Directory.systemTemp.createTempSync('purelive-background-test-');
      try {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawColor(const ui.Color(0xff123456), ui.BlendMode.src);
        final sourceImage = await recorder.endRecording().toImage(3000, 100);
        final png = await sourceImage.toByteData(format: ui.ImageByteFormat.png);
        sourceImage.dispose();
        final source = File('${directory.path}/original.png')..writeAsBytesSync(png!.buffer.asUint8List());
        final original = source.readAsBytesSync();
        final files = CustomBackgroundFiles(Future.value(Directory('${directory.path}/owned')));
        final name = await files.importImage(source);
        final copy = (await files.resolve(name))!;
        final codec = await ui.instantiateImageCodec(copy.readAsBytesSync());
        final frame = await codec.getNextFrame();
        expect((frame.image.width, frame.image.height), (2560, 85));
        frame.image.dispose();
        codec.dispose();
        expect(source.readAsBytesSync(), original);
        expect(await files.resolve('../original.png'), isNull);
        final unrelated = File('${copy.parent.path}/do-not-delete.txt')..writeAsStringSync('keep');
        final second = await files.importImage(source);
        await files.keepOnly(second);
        expect(copy.existsSync(), isFalse);
        expect((await files.resolve(second))!.existsSync(), isTrue);
        await files.keepOnly('');
        expect(await files.resolve(second), isNull);
        expect(unrelated.readAsStringSync(), 'keep');
        expect(source.readAsBytesSync(), original);
      } finally {
        directory.deleteSync(recursive: true);
      }
    });
  });

  testWidgets('invalid or oversized input does not remove the previous background', (tester) async {
    await tester.runAsync(() async {
      final directory = Directory.systemTemp.createTempSync('purelive-background-reject-');
      try {
        final files = CustomBackgroundFiles(Future.value(directory));
        final previous = File('${directory.path}/background-abc.png')..writeAsStringSync('previous');
        final invalid = File('${directory.path}/invalid.png')..writeAsStringSync('not an image');
        await expectLater(files.importImage(invalid), throwsA(isA<Exception>()));
        final large = File('${directory.path}/large.png')..writeAsBytesSync([1]);
        large.openSync(mode: FileMode.write)
          ..truncateSync(CustomBackgroundFiles.maxBytes + 1)
          ..closeSync();
        await expectLater(files.importImage(large), throwsFormatException);
        expect(previous.readAsStringSync(), 'previous');
      } finally {
        directory.deleteSync(recursive: true);
      }
    });
  });

  testWidgets(
    'disabled theme stays identical; enabled background is below transparent pages and never intercepts taps',
    (tester) async {
      final services = (await tester.runAsync(testServices))!;
      var taps = 0;
      const themeColor = Color(0xff102030);
      Widget app() => ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          theme: ThemeData(scaffoldBackgroundColor: themeColor),
          builder: (_, child) => CustomBackgroundFrame(child: child!),
          home: Scaffold(
            body: Center(
              child: TextButton(onPressed: () => taps++, child: const Text('button')),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      expect(Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor, themeColor);
      await tester.runAsync(
        () => services.store.settings.set(Settings.customBackground, {'kind': 'color', 'color': 0xff663399}),
      );
      await tester.pump();
      expect(Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor, Colors.transparent);
      expect(find.byWidgetPredicate((w) => w is ColoredBox && w.color == const Color(0xff663399)), findsOneWidget);
      await tester.tap(find.text('button'));
      expect(taps, 1);
      await tester.runAsync(() => services.store.settings.set(Settings.customBackground, <String, Object?>{}));
      await tester.pump();
      expect(Theme.of(tester.element(find.byType(Scaffold))).scaffoldBackgroundColor, themeColor);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(services.close);
    },
  );
}
