import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/shared/rooms/archive/archive_rate_dialog.dart';

import '../../support.dart';

Future<ValueNotifier<double?>> page(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double scale = 1,
  double rate = 1,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadStrings);
  final result = ValueNotifier<double?>(null);
  addTearDown(result.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: const LiveTheme().dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result.value = await showDialog<double>(
                context: context,
                builder: (_) => ArchiveRateDialog(rate: rate),
              );
            },
            child: const Text('打开速度'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开速度'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  for (final size in [const Size(360, 640), const Size(393, 852), const Size(740, 360), const Size(1280, 800)]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('12 presets and custom footer fit $size at $scale type', (tester) async {
        await page(tester, size: size, scale: scale);
        expect(find.byType(OutlinedButton), findsNWidgets(13));
        for (final rate in archiveRates) {
          final paragraph = tester.renderObject<RenderParagraph>(find.text(archiveRateLabel(rate)));
          expect(
            paragraph.size.height,
            closeTo(paragraph.getDryLayout(const BoxConstraints()).height, 0.1),
            reason: 'the complete speed label stays on one line',
          );
        }
        await tester.ensureVisible(find.byKey(const ValueKey('archive-rate-fine')));
        await tester.tap(find.byKey(const ValueKey('archive-rate-fine')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('archive-rate-input')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('archive-rate-apply')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets('a landscape keyboard leaves the custom panel scrollable and free of overflow', (tester) async {
    final result = await page(tester, size: const Size(740, 360), rate: 1.6);
    tester.view.viewInsets = const FakeViewPadding(bottom: 215);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('archive-rate-input')));
    await tester.enterText(find.byKey(const ValueKey('archive-rate-input')), '1.85');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('archive-rate-apply')));
    await tester.tap(find.byKey(const ValueKey('archive-rate-apply')));
    await tester.pumpAndSettle();
    expect(result.value, 1.85);
  });

  testWidgets('custom values are draft-only, validate range and step, and reset survives invalid input', (
    tester,
  ) async {
    final result = await page(tester);
    await tester.tap(find.byKey(const ValueKey('archive-rate-fine')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('archive-rate-input')), '1.60');
    await tester.pump();
    expect(result.value, isNull);
    await tester.tap(find.byKey(const ValueKey('archive-rate-apply')));
    await tester.pumpAndSettle();
    expect(result.value, 1.6);
    final other = await page(tester, rate: 1.6);
    for (final invalid in ['8', '0.1', '1.33', '']) {
      await tester.enterText(find.byKey(const ValueKey('archive-rate-input')), invalid);
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('archive-rate-apply'))).onPressed, isNull);
    }
    await tester.tap(find.byKey(const ValueKey('archive-rate-reset')));
    await tester.pumpAndSettle();
    expect(other.value, 1);
  });
  testWidgets('preset keyboard activation and Escape never apply a custom draft', (tester) async {
    final result = await page(tester);
    await tester.tap(find.byKey(const ValueKey('archive-rate-4.0')));
    await tester.pumpAndSettle();
    expect(result.value, 4);
    final canceled = await page(tester, rate: 1.6);
    await tester.enterText(find.byKey(const ValueKey('archive-rate-input')), '2.35');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(canceled.value, isNull);
  });
}
