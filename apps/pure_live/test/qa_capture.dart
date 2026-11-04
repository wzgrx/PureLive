import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads optional review fonts before the widgets create their paragraphs.
/// Functional tests without PURELIVE_QA_DIR keep the standard test fonts.
Future<void> prepareQaFonts(WidgetTester tester) async {
  final folder = Platform.environment['PURELIVE_QA_DIR'];
  if (folder == null || folder.isEmpty) return;
  final font = Platform.environment['PURELIVE_QA_FONT'];
  if (font != null && font.isNotEmpty) {
    await tester.runAsync(() async {
      final bytes = ByteData.sublistView(await File(font).readAsBytes());
      for (final family in [
        'Ahem',
        'Roboto',
        'Segoe UI',
        '.AppleSystemUIFont',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
      await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader(
        'packages/remixicon/remix',
      )..addFont(rootBundle.load('packages/remixicon/fonts/remix.ttf'))).load();
      await (FontLoader(
        'packages/live_ui/CustomIcons',
      )..addFont(rootBundle.load('packages/live_ui/assets/fonts/CustomIcons.ttf'))).load();
    });
    await tester.pump();
  }
}

/// Optional synthetic widget frames for a local review, never a device claim.
Future<void> captureQaFrame(WidgetTester tester, String name) async {
  final folder = Platform.environment['PURELIVE_QA_DIR'];
  if (folder == null || folder.isEmpty) return;
  await prepareQaFonts(tester);
  await tester.pump();
  if (Platform.environment['PURELIVE_QA_FONT']?.isNotEmpty ?? false) {
    // The TV's inherited styles do not name a family. Use the loaded
    // review font for inherited text, preserving explicit icon families.
    // This affects only optional synthetic frames, never app font choices.
    for (final element in find.byType(RichText).evaluate()) {
      final paragraph = element.renderObject! as RenderParagraph;
      if (paragraph.text.style?.fontFamily == null) {
        paragraph.text = TextSpan(
          style: const TextStyle(fontFamily: 'Roboto'),
          children: [paragraph.text],
        );
      }
    }
    await tester.pump();
  }
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(view.paintBounds, pixelRatio: math.min(1, 1080 / view.paintBounds.width));
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('The widget frame has no PNG data');
      final target = File('$folder/$name.png');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
