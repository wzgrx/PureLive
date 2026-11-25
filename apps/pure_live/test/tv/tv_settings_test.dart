// A17.9 stage 3: the TV's show-and-move editor, the side menu's order,
// hidden entries and icons, and the colour grid.
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/tv/home/tv_home_page.dart';
import 'package:pure_live/tv/settings/tv_order_editor.dart';
import 'package:pure_live/tv/settings/tv_settings_style.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_settings_rows.dart';

import '../qa_capture.dart';
import '../support.dart';

final ColorScheme _scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2196F3), brightness: Brightness.dark);

Future<void> _pump(WidgetTester tester, Widget child, {Size size = const Size(1920, 1080), double ratio = 2}) async {
  await prepareQaFonts(tester);
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadStrings);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorScheme: _scheme),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
          child: TvTheme(
            palette: TvPalette.of(_scheme),
            child: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

String? get _row =>
    (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvFocusable>()?.key
            as ValueKey<String>?)
        ?.value;

void main() {
  for (final (panel, size, ratio) in [
    ('720p', const Size(1280, 720), 1.0),
    ('1080p', const Size(1920, 1080), 2.0),
    ('4K', const Size(3840, 2160), 2.0),
  ]) {
    for (final shared in [false, true]) {
      testWidgets('issue #39: $panel ${shared ? "shared" : "TV"} settings ring fills the group boundary', (
        tester,
      ) async {
        final boundary = GlobalKey();
        await _pump(
          tester,
          Align(
            alignment: Alignment.topCenter,
            child: RepaintBoundary(
              key: boundary,
              child: shared
                  ? TvSettingsStyle(
                      child: SettingsGroup(
                        children: [SettingsLinkRow(title: 'Platform', onTap: () {})],
                      ),
                    )
                  : TvSettingsGroup(
                      children: [TvSettingsRow(id: 'frame', title: 'Platform', autofocus: true, onTap: () {})],
                    ),
            ),
          ),
          size: size,
          ratio: ratio,
        );
        if (shared) {
          Focus.of(tester.element(find.text('Platform'))).requestFocus();
        }
        await tester.pumpAndSettle();
        final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final colors = (await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final bytes = (await image.toByteData())!;
          // Ignore the group's bottom spacing; sample through the focused row's centre.
          final target = find.text('Platform');
          final y = ((tester.getCenter(target).dy - tester.getTopLeft(find.byKey(boundary)).dy) * 2).round();
          final result = [
            for (final x in [1, image.width - 2])
              Color.fromARGB(
                bytes.getUint8((y * image.width + x) * 4 + 3),
                bytes.getUint8((y * image.width + x) * 4),
                bytes.getUint8((y * image.width + x) * 4 + 1),
                bytes.getUint8((y * image.width + x) * 4 + 2),
              ),
          ];
          image.dispose();
          return result;
        }))!;
        expect(
          colors,
          everyElement(shared ? LiveTvColors.focusFrame : TvPalette.of(_scheme).focusRing),
          reason: 'all settings groups use the full row width',
        );
        if (panel == '1080p') {
          await captureQaFrame(tester, shared ? 'settings-shared-full-frame' : 'settings-tv-full-frame');
        }
      });
    }
  }

  for (final (panel, size, ratio) in [
    ('720p', const Size(1280, 720), 1.0),
    ('1080p', const Size(1920, 1080), 2.0),
    ('4K', const Size(3840, 2160), 2.0),
  ]) {
    testWidgets('issue 30: $panel full-width choices keep both sides of the focus frame inside the viewport', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await _pump(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: RepaintBoundary(
            key: boundary,
            child: TvOptionRow(label: '斗鱼', current: true, autofocus: true, onTap: () {}),
          ),
        ),
        size: size,
        ratio: ratio,
      );
      await tester.pumpAndSettle();
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final colors = (await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = (await image.toByteData())!;
        final y = image.height ~/ 2;
        final result = [
          for (final x in [1, image.width - 2])
            Color.fromARGB(
              bytes.getUint8((y * image.width + x) * 4 + 3),
              bytes.getUint8((y * image.width + x) * 4),
              bytes.getUint8((y * image.width + x) * 4 + 1),
              bytes.getUint8((y * image.width + x) * 4 + 2),
            ),
        ];
        image.dispose();
        return result;
      }))!;
      for (final color in colors) {
        expect(
          color,
          TvPalette.of(_scheme).focusRing,
          reason: 'a clipped outside stroke leaves only the row background',
        );
      }
    });
  }

  test('the side menu: the order stored first, the rest by default; hidden left out, one always stays', () {
    expect(TvPane.menuOf(), TvPane.entries);
    expect(TvPane.menuOf(order: ['history', 'nope', 'favorites']).take(3), [
      TvPane.history,
      TvPane.favorites,
      TvPane.popular,
    ]);
    expect(TvPane.menuOf(hidden: ['favorites', 'popular']).first, TvPane.areas);
    expect(TvPane.menuOf(hidden: [for (final pane in TvPane.entries) pane.name]), [TvPane.entries.first]);
    expect(TvPane.favorites.iconIn(const []), TvPane.favorites.icon);
    expect(TvPane.favorites.iconIn(const ['favorites:star']), TvIcons.menuChoices['star']);
    expect(TvPane.favorites.iconIn(const ['favorites:gone', 'areas:star']), TvPane.favorites.icon);
  });

  testWidgets('the editor: OK hides and shows (not the last one); a held OK moves, OK drops, Back undoes', (
    tester,
  ) async {
    final toasts = <String>[];
    final previous = AppNavigator.toast;
    AppNavigator.toast = toasts.add;
    addTearDown(() => AppNavigator.toast = previous);
    final changes = <(List<String>, Set<String>)>[];
    await _pump(
      tester,
      TvOrderEditor(
        items: const [
          TvOrderItem(id: 'a', label: '甲'),
          TvOrderItem(id: 'b', label: '乙'),
          TvOrderItem(id: 'c', label: '丙'),
        ],
        hidden: const {'c'},
        lastShownMessage: '至少一个',
        onChanged: (order, hidden) => changes.add((order, hidden)),
      ),
    );
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_row, 'tv-setting-order-a');

    await _press(tester, LogicalKeyboardKey.select);
    expect(changes.last.$1, ['a', 'b', 'c']);
    expect(changes.last.$2, {'c', 'a'});
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    expect(changes, hasLength(1), reason: '乙 is the last one shown');
    expect(toasts, ['至少一个']);

    // The menu key picks 乙 up; Down moves it under 丙, OK puts it there.
    await _press(tester, LogicalKeyboardKey.contextMenu);
    expect(find.text('移动中'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_row, 'tv-setting-order-b', reason: 'the focus moves with it');
    await _press(tester, LogicalKeyboardKey.select);
    expect(changes.last.$1, ['a', 'c', 'b']);
    expect(changes.last.$2, {'c', 'a'});

    // Picked up again, moved up twice, then Escape (Back) puts it back.
    await _press(tester, LogicalKeyboardKey.contextMenu);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.text('移动中'), findsNothing);
    expect(changes, hasLength(2), reason: 'nothing stored');
    final order = [
      for (final element in find.byType(TvFocusable).evaluate())
        (element.widget.key! as ValueKey<String>).value.substring('tv-setting-order-'.length),
    ];
    expect(order, ['a', 'c', 'b']);
  });

  testWidgets('the colour grid: no names, the current one focused, codes shown; OK picks, Back keeps', (tester) async {
    Color? picked;
    var answered = false;
    await _pump(
      tester,
      TvSettingsStyle(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await showColorDialog(context: context, title: '主题颜色', current: LiveSwatches.common[3]);
              answered = true;
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tv-color-grid')), findsOneWidget);
    expect(find.byType(TvFocusable), findsNWidgets(18 * 4 + 1), reason: '18 common, 18 × 3, "取消"');
    expect(LiveSwatches.common.first, LiveTheme.brandBlue);
    expect(_row, 'tv-color-0-3');
    expect(find.textContaining('#2AD39A'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_row, 'tv-color-0-4');
    expect(find.text('焦点颜色 #FF9F43 · 当前 #2AD39A'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(answered, isTrue);
    expect(picked, LiveSwatches.common[4]);

    answered = false;
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(answered, isTrue);
    expect(picked, isNull);
  });
}
