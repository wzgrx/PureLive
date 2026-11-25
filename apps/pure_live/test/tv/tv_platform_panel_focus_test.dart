import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/tv/pages/tv_popular_pane.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

import '../qa_capture.dart';
import '../support.dart';

final GlobalKey _frame = GlobalKey();
final Finder _panel = find.byKey(const ValueKey('tv-platform-panel'));
final Finder _opener = find.byKey(const ValueKey('tv-tab-${TvPopularPane.allPlatforms}'));
final _scheme = ColorScheme.fromSeed(seedColor: LiveTheme.brandBlue, brightness: Brightness.dark);

Finder _button(String id) => find.byKey(ValueKey('tv-platform-panel-$id'));

FocusNode _node(WidgetTester tester, Finder target) =>
    tester.widget<Focus>(find.descendant(of: target, matching: find.byType(Focus)).first).focusNode!;

String? get _focused =>
    (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>()?.key as ValueKey<String>?)
        ?.value;

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<List<String>> _pump(
  WidgetTester tester, {
  Size size = const Size(1920, 1080),
  double ratio = 2,
  double textScale = 1,
  bool zoom = true,
  bool currentAtEnd = true,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await prepareQaFonts(tester);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(services.close);
  });
  await tester.runAsync(loadStrings);
  // Reverse the saved list: "first" means the configured visible order,
  // not a hard-coded platform, and the last selection starts off screen.
  final ids = services.sites.availableIds(services.store.settings.get(Settings.hotAreasList)).reversed.toList();
  expect(ids.length, greaterThan(20));
  await tester.runAsync(() async {
    await services.store.settings.set(Settings.hotAreasList, ids);
    await services.store.settings.set(Settings.preferPlatform, currentAtEnd ? ids.last : ids.first);
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        networkProbeProvider.overrideWithValue(() async => NetworkKind.none),
      ],
      child: MaterialApp(
        theme: ThemeData(colorScheme: _scheme),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(navigationMode: NavigationMode.directional, textScaler: TextScaler.linear(textScale)),
          child: TvTheme(
            palette: TvPalette.of(_scheme),
            zoom: zoom,
            child: RepaintBoundary(key: _frame, child: child),
          ),
        ),
        home: const Scaffold(body: TvPopularPane()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ids;
}

Future<void> _open(WidgetTester tester) async {
  _node(tester, _opener).requestFocus();
  await tester.pumpAndSettle();
  await _press(tester, LogicalKeyboardKey.select);
  expect(_panel, findsOneWidget);
}

Rect _ringRect(WidgetTester tester, String id) {
  final target = _button(id);
  final ring = find.descendant(
    of: target,
    matching: find.byWidgetPredicate(
      (widget) => widget is DecoratedBox && widget.position == DecorationPosition.foreground,
    ),
  );
  final box = tester.renderObject<RenderBox>(ring.first);
  // getRect adds the untransformed size to the global top-left. Include the
  // AnimatedScale transform and the outside stroke explicitly instead.
  return MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
}

void _expectVisible(WidgetTester tester, String id) {
  expect(_focused, 'tv-platform-panel-$id');
  final context = tester.element(_button(id));
  final zoom = TvTheme.zoomOf(context) ? tvFocusZoom : 1.0;
  final paint = _ringRect(tester, id).inflate(TvScale.of(context).px(tvFocusRingWidth) * zoom);
  final viewport = tester.getRect(find.descendant(of: _panel, matching: find.byType(SingleChildScrollView)));
  expect(
    paint.left,
    greaterThanOrEqualTo(viewport.left - 0.01),
    reason: 'the complete left ring stays inside the clip',
  );
  expect(
    paint.right,
    lessThanOrEqualTo(viewport.right + 0.01),
    reason: 'the complete right ring stays inside the clip',
  );
  expect(paint.top, greaterThanOrEqualTo(viewport.top - 0.01), reason: 'the complete top ring stays inside the clip');
  expect(
    paint.bottom,
    lessThanOrEqualTo(viewport.bottom + 0.01),
    reason: 'the complete bottom ring stays inside the clip',
  );
}

Future<void> _expectRingPixels(WidgetTester tester, String id) async {
  final context = tester.element(_button(id));
  final zoom = TvTheme.zoomOf(context) ? tvFocusZoom : 1.0;
  final halfStroke = TvScale.of(context).px(tvFocusRingWidth) * zoom / 2;
  final rect = _ringRect(tester, id);
  final origin = tester.getTopLeft(find.byKey(_frame));
  final points = [
    Offset(rect.left - halfStroke, rect.center.dy),
    Offset(rect.right + halfStroke, rect.center.dy),
    Offset(rect.center.dx, rect.top - halfStroke),
    Offset(rect.center.dx, rect.bottom + halfStroke),
  ];
  final render = _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final colors = (await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    try {
      final bytes = (await image.toByteData())!;
      return points.map((point) {
        final x = ((point.dx - origin.dx) * 2).round();
        final y = ((point.dy - origin.dy) * 2).round();
        final offset = (y * image.width + x) * 4;
        return Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }).toList();
    } finally {
      image.dispose();
    }
  }))!;
  expect(colors, everyElement(TvTheme.of(context).focusRing), reason: 'all four sides are painted, not just laid out');
}

String _selected(WidgetTester tester) {
  final tabs = tester.widget<TvTabBar>(find.byType(TvTabBar));
  return tabs.tabs[tabs.selected].id;
}

void main() {
  testWidgets('issue #74: every opening starts at the first platform; selection and Back restore the opener', (
    tester,
  ) async {
    final ids = await _pump(tester);
    await _open(tester);
    _expectVisible(tester, ids.first);
    expect(tester.widget<TvButton>(_button(ids.last)).selected, isTrue);
    expect(tester.widget<TvButton>(_button(ids.first)).selected, isFalse);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _expectVisible(tester, ids[1]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_selected(tester), ids.last);
    expect(_node(tester, _opener).hasPrimaryFocus, isTrue);

    await _press(tester, LogicalKeyboardKey.select);
    _expectVisible(tester, ids.first);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.select);
    expect(_panel, findsNothing);
    expect(_selected(tester), ids[1]);
    expect(_node(tester, _opener).hasPrimaryFocus, isTrue);

    await _press(tester, LogicalKeyboardKey.select);
    _expectVisible(tester, ids.first);
    expect(tester.widget<TvButton>(_button(ids[1])).selected, isTrue);
    await captureQaFrame(tester, 'tv-platform-panel-first-after-selection');
    // Dismiss during a pending focus reveal, then dispose the whole route.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.binding.handlePopRoute();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  for (final (name, size, ratio, textScale, zoom) in [
    ('1080p', const Size(1920, 1080), 2.0, 1.0, true),
    ('720p lifted no zoom', const Size(1280, 720), 1.0, 1.5, false),
    ('720p lifted zoom', const Size(1280, 720), 1.0, 1.5, true),
    ('short dialog', const Size(1280, 480), 1.0, 1.3, true),
    ('narrow dialog', const Size(960, 720), 1.0, 1.3, true),
  ]) {
    testWidgets('issue #74: $name D-pad reaches every platform with a complete ring and owned scrolling', (
      tester,
    ) async {
      final ids = await _pump(tester, size: size, ratio: ratio, textScale: textScale, zoom: zoom, currentAtEnd: false);
      final openerScroll = Scrollable.of(_node(tester, _opener).context!).position;
      await _open(tester);
      final openerOffset = openerScroll.pixels;
      _expectVisible(tester, ids.first);
      await _expectRingPixels(tester, ids.first);
      var lastId = ids.first;
      for (var row = 0; row * 3 < ids.length; row++) {
        final cells = ids.skip(row * 3).take(3).toList();
        final ordered = row.isEven ? cells : cells.reversed.toList();
        if (row > 0) await _press(tester, LogicalKeyboardKey.arrowDown);
        for (var column = 0; column < ordered.length; column++) {
          if (column > 0) {
            await _press(tester, row.isEven ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft);
          }
          lastId = ordered[column];
          _expectVisible(tester, lastId);
        }
      }
      _expectVisible(tester, lastId);
      await _expectRingPixels(tester, lastId);
      expect(openerScroll.pixels, openerOffset, reason: 'the underlying horizontal tabs do not follow dialog focus');
      final scroll = tester.state<ScrollableState>(find.descendant(of: _panel, matching: find.byType(Scrollable)));
      expect(scroll.position.pixels, greaterThan(0));
      await captureQaFrame(tester, 'tv-platform-panel-last-$name');
      // Reverse direction through the same rows; Up must reveal rows above
      // the current scroll position just as Down reveals rows below it.
      final lastRow = (ids.length - 1) ~/ 3;
      for (var row = lastRow - 1; row >= 0; row--) {
        await _press(tester, LogicalKeyboardKey.arrowUp);
        final id = _focused!.substring('tv-platform-panel-'.length);
        expect(ids.indexOf(id) ~/ 3, row);
        _expectVisible(tester, id);
      }
      for (var row = 1; row <= lastRow; row++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
        final id = _focused!.substring('tv-platform-panel-'.length);
        expect(ids.indexOf(id) ~/ 3, row);
        _expectVisible(tester, id);
      }
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final action = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>();
      expect(action, isNotNull, reason: 'the footer actions remain reachable');
      if (action!.key == const ValueKey('tv-platform-panel-display')) {
        await _press(tester, LogicalKeyboardKey.arrowRight);
      }
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>()?.label, '关闭');
      await _press(tester, LogicalKeyboardKey.select);
      expect(_panel, findsNothing);
      expect(_selected(tester), ids.first, reason: 'Close does not select the focused platform');
      expect(_node(tester, _opener).hasPrimaryFocus, isTrue);
      await _press(tester, LogicalKeyboardKey.select);
      _expectVisible(tester, ids.first);
      expect(tester.takeException(), isNull);
    });
  }
}
