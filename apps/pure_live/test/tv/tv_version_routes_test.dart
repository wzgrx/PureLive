import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/routes/tv_router.dart';
import 'package:pure_live/tv/settings/tv_settings_section_page.dart';
import 'package:pure_live/tv/tv_app.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';

import '../support.dart';

final class _Feed extends UpdateFeed {
  new() : super(NoNetworkHttp(), githubOrigin: false, platform: 'android');

  UpdateSnapshot? snapshot = UpdateSnapshot(
    info: const UpdateInfo(version: appVersion, buildNumber: pubspecBuild, releaseUrl: 'https://example.com/release'),
  );
  Completer<UpdateSnapshot?>? gate;
  int checks = 0;
  List<ReleaseInfo>? history = const [ReleaseInfo(version: appVersion, date: '2026-10-27', changelog: 'Notes')];

  @override
  Future<UpdateSnapshot?> check() async {
    checks++;
    return gate == null ? snapshot : await gate!.future;
  }

  @override
  Future<List<ReleaseInfo>?> releases({Duration timeout = const Duration(seconds: 15), UpdateInfo? matching}) async =>
      history;
}

const _file = ReleaseFile(
  name: 'PureLive-9.0.0-5123-android-arm64-v8a-release.apk',
  size: '4 MB',
  downloads: 0,
  url: 'https://example.com/PureLive-9.0.0-5123-android-arm64-v8a-release.apk',
);

UpdateSnapshot _newer() => UpdateSnapshot(
  info: const UpdateInfo(version: '9.0.0', buildNumber: 5123, releaseUrl: 'https://example.com/release'),
  files: const [_file],
);

Future<GoRouter> _pump(
  WidgetTester tester,
  _Feed feed, {
  Size size = const Size(960, 540),
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final router = buildTvRouter(initialLocation: RoutePath.kAbout);
  AppNavigator.router = router;
  addTearDown(() {
    AppNavigator.router = null;
    router.dispose();
    foundUpdate.value = null;
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services), updateFeedProvider.overrideWithValue(feed)],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp.router(
          theme: const LiveTheme().dark,
          routerConfig: router,
          builder: (context, child) => RepaintBoundary(
            key: const ValueKey('tv-version-frame'),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: TvAppFrame(child: child!),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

bool _focused(WidgetTester tester, Finder target) {
  final element = tester.element(target);
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var found = identical(context, element);
  context.visitAncestorElements((ancestor) {
    if (identical(ancestor, element)) found = true;
    return !found;
  });
  return found;
}

void main() {
  for (final path in [RoutePath.kVersionPage, RoutePath.kVersionHistory]) {
    testWidgets('issue 70: $path keeps the TV settings shell and header', (tester) async {
      final router = await _pump(tester, _Feed());
      unawaited(router.push<void>(path));
      await tester.pumpAndSettle();
      final shell = find.byKey(ValueKey('tv-settings-root-$path'));
      expect(shell, findsOneWidget);
      expect(find.byType(TvPageHeader), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      final scaffold = tester.widget<Scaffold>(shell);
      expect(scaffold.backgroundColor, TvTheme.pageOf(tester.element(shell)));
      expect(find.byType(TvSettingsScaffold), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('about-online-update')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('issue 70: delayed update focuses content, refresh is reachable and Back returns to about', (
    tester,
  ) async {
    final feed = _Feed()..gate = Completer<UpdateSnapshot?>();
    final router = await _pump(tester, feed);
    unawaited(router.push<void>(RoutePath.kVersionPage));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('version-checking')), findsOneWidget);
    expect(find.byType(TvPageHeader), findsOneWidget);
    feed.gate!.complete(feed.snapshot);
    feed.gate = null;
    await tester.pumpAndSettle();
    final open = find.byKey(const ValueKey('version-open-release'));
    expect(_focused(tester, open), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(tester, find.byKey(const ValueKey('version-refresh'))), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(feed.checks, 2);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('about-online-update')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('issue 70: update failure retries with the remote in the same TV shell', (tester) async {
    final feed = _Feed()..snapshot = null;
    final router = await _pump(tester, feed);
    unawaited(router.push<void>(RoutePath.kVersionPage));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('version-update-error')), findsOneWidget);
    expect(find.byType(TvPageHeader), findsOneWidget);
    feed.snapshot = UpdateSnapshot(
      info: const UpdateInfo(version: appVersion, buildNumber: pubspecBuild, releaseUrl: 'https://example.com/release'),
    );
    await _press(tester, LogicalKeyboardKey.select);
    expect(feed.checks, 2);
    expect(find.byKey(const ValueKey('version-open-release')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('issue 70: remote opens sources and dismisses a nested source dialog', (tester) async {
    final feed = _Feed()..snapshot = _newer();
    final router = await _pump(tester, feed);
    unawaited(router.push<void>(RoutePath.kVersionPage));
    await tester.pumpAndSettle();
    final install = find.byKey(ValueKey('version-download-${_file.name}'));
    final sources = find.byKey(ValueKey('version-sources-${_file.name}'));
    expect(_focused(tester, sources), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(tester, install), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(tester, sources), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    final source = find.byKey(ValueKey('version-source-${_file.name}-0'));
    expect(_focused(tester, source), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('version-source-dialog')), findsOneWidget);
    expect(
      _focused(tester, find.byKey(const ValueKey('version-source-download'))),
      isTrue,
      reason: 'issue 132: opening the source dialog already focuses a visible action',
    );
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('version-source-dialog')), findsNothing);
    expect(_focused(tester, source), isTrue);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('about-online-update')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('issue 70: history remote selects a release and Back restores its row', (tester) async {
    String? copied;
    final toasts = <String>[];
    final previousToast = AppNavigator.toast;
    AppNavigator.toast = toasts.add;
    addTearDown(() => AppNavigator.toast = previousToast);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final feed = _Feed()
      ..history = const [
        ReleaseInfo(version: '9.0.0', date: '2026-10-27', changelog: 'First', github: 'https://example.com/release/9'),
        ReleaseInfo(
          version: '8.0.0',
          date: '2026-10-26',
          changelog: 'Second',
          github: 'https://example.com/release/8',
          files: [_file],
        ),
      ];
    final router = await _pump(tester, feed, size: const Size(800, 540));
    unawaited(router.push<void>(RoutePath.kVersionHistory));
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('release-history-mobile-9.0.0'));
    final second = find.byKey(const ValueKey('release-history-mobile-8.0.0'));
    expect(_focused(tester, first), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(tester, second), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('release-history-detail-dialog')), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(tester, find.byKey(const ValueKey('release-history-open-release'))), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-link-dialog')), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(_focused(tester, find.byKey(const ValueKey('release-history-open-release'))), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(tester, find.byKey(const ValueKey('release-file-copy'))), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(copied, _file.url);
    expect(toasts.last, i18n('copied_to_clipboard'));
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused(tester, find.byKey(const ValueKey('release-file-download'))), isTrue);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('release-download-confirm')), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('release-download-confirm')), findsNothing);
    expect(find.byKey(const ValueKey('release-history-detail-dialog')), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(const ValueKey('release-history-detail-dialog')), findsNothing);
    expect(_focused(tester, second), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [800.0, 1280.0]) {
    testWidgets('issue 70: history focus frame is visible independently of selection at $width', (tester) async {
      final strategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
      final feed = _Feed()
        ..history = const [
          ReleaseInfo(
            version: '9.0.0',
            date: '2026-10-27',
            changelog: 'First',
            github: 'https://example.com/release/9',
          ),
          ReleaseInfo(
            version: '8.0.0',
            date: '2026-10-26',
            changelog: 'Second',
            github: 'https://example.com/release/8',
          ),
        ];
      final router = await _pump(tester, feed, size: Size(width, 540));
      unawaited(router.push<void>(RoutePath.kVersionHistory));
      await tester.pumpAndSettle();
      if (width == 1280) {
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        final first = find.byKey(const ValueKey('release-history-desktop-9.0.0'));
        if (!_focused(tester, first)) await _press(tester, LogicalKeyboardKey.arrowUp);
        expect(_focused(tester, first), isTrue);
      }
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final layout = width == 800 ? 'mobile' : 'desktop';
      final second = find.byKey(ValueKey('release-history-$layout-8.0.0'));
      expect(_focused(tester, second), isTrue);
      if (layout == 'desktop') {
        expect(find.byKey(const ValueKey('release-history-detail-9.0.0')), findsOneWidget);
      }
      final boundary = find.byKey(const ValueKey('tv-version-frame'));
      final render = tester.renderObject<RenderRepaintBoundary>(boundary);
      final rect = tester.getRect(second);
      final origin = tester.getTopLeft(boundary);
      final x = (rect.left - origin.dx + 2).round();
      final y = (rect.center.dy - origin.dy).round();
      final color = (await tester.runAsync(() async {
        final image = await render.toImage();
        final bytes = (await image.toByteData())!;
        final offset = (y * image.width + x) * 4;
        final value = Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
        image.dispose();
        return value;
      }))!;
      expect(
        color,
        TvColors.focusRing,
        reason: 'the remote target needs its own visible frame, not only selection fill',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final hasLog in [false, true]) {
    testWidgets('issue 70: delayed update cannot steal a covering dialog focus (log=$hasLog)', (tester) async {
      final feed = _Feed()
        ..gate = Completer<UpdateSnapshot?>()
        ..snapshot = UpdateSnapshot(
          info: UpdateInfo(
            version: appVersion,
            buildNumber: pubspecBuild,
            releaseUrl: 'https://example.com/release',
            log: hasLog ? '## Update notes\nNew readable content' : '',
          ),
        );
      final router = await _pump(tester, feed);
      unawaited(router.push<void>(RoutePath.kVersionPage));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final focus = FocusNode();
      addTearDown(focus.dispose);

      showDialog<void>(
        context: AppNavigator.navigatorContext!,
        builder: (context) => AlertDialog(
          title: const Text('Covering dialog'),
          actions: [TextButton(focusNode: focus, autofocus: true, onPressed: () {}, child: const Text('Keep focus'))],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(focus.hasFocus, isTrue);
      feed.gate!.complete(feed.snapshot);
      feed.gate = null;
      await tester.pump(const Duration(seconds: 1));
      expect(focus.hasFocus, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_focused(tester, find.byKey(const ValueKey('version-open-release'))), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final width in [800.0, 1280.0]) {
    testWidgets('issue 70: long history keeps each D-pad target visible at $width', (tester) async {
      final feed = _Feed()
        ..history = [
          for (var i = 0; i < 24; i++)
            ReleaseInfo(
              version: '9.0.$i',
              date: '2026-10-27',
              changelog: 'Notes',
              github: 'https://example.com/release/$i',
            ),
        ];
      final router = await _pump(tester, feed, size: Size(width, 540));
      unawaited(router.push<void>(RoutePath.kVersionHistory));
      await tester.pumpAndSettle();
      final layout = width == 800 ? 'mobile' : 'desktop';
      if (layout == 'desktop') {
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'settings keyboard scroll');
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        final first = find.byKey(const ValueKey('release-history-desktop-9.0.0'));
        for (var step = 0; step < 24 && !_focused(tester, first); step++) {
          await _press(tester, LogicalKeyboardKey.arrowUp);
        }
        expect(_focused(tester, first), isTrue);
      }
      for (var i = 0; i < 24; i++) {
        if (i > 0) await _press(tester, LogicalKeyboardKey.arrowDown);
        final row = find.byKey(ValueKey('release-history-$layout-9.0.$i'));
        expect(row, findsOneWidget, reason: 'row $i is built using only directional keys');
        expect(_focused(tester, row), isTrue, reason: 'row $i is the actual remote target');
        final viewport = tester.getRect(find.byKey(ValueKey('release-history-$layout-list')));
        final bounds = tester.getRect(row);
        expect(bounds.top, greaterThanOrEqualTo(viewport.top - 1));
        expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom + 1));
      }
      for (var i = 22; i >= 0; i--) {
        await _press(tester, LogicalKeyboardKey.arrowUp);
        final row = find.byKey(ValueKey('release-history-$layout-9.0.$i'));
        expect(_focused(tester, row), isTrue);
        final viewport = tester.getRect(find.byKey(ValueKey('release-history-$layout-list')));
        final bounds = tester.getRect(row);
        expect(bounds.top, greaterThanOrEqualTo(viewport.top - 1));
        expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom + 1));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final width in [800.0, 1280.0]) {
    testWidgets('issue 70: read-only long release notes scroll with D-pad at $width', (tester) async {
      final feed = _Feed()
        ..history = [
          ReleaseInfo(
            version: '9.0.0',
            date: '2026-10-27',
            github: 'https://example.com/release',
            changelog: List.generate(40, (i) => '## Section $i\nRelease notes paragraph $i').join('\n\n'),
          ),
          const ReleaseInfo(version: '8.0.0', date: '2026-10-26', changelog: 'Other release'),
        ];
      final router = await _pump(tester, feed, size: Size(width, 540));
      unawaited(router.push<void>(RoutePath.kVersionHistory));
      await tester.pumpAndSettle();
      if (width == 800) {
        await _press(tester, LogicalKeyboardKey.select);
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_focused(tester, find.byKey(const ValueKey('release-history-open-release'))), isTrue);
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      final detail = width == 800
          ? find.byKey(const ValueKey('release-history-detail-dialog'))
          : find.byKey(const ValueKey('release-history-detail-9.0.0'));
      final scroll = find.descendant(of: detail, matching: find.byType(Scrollable));
      final position = tester.state<ScrollableState>(scroll).position;
      expect(position.maxScrollExtent, greaterThan(position.viewportDimension));
      final initial = position.pixels;
      for (var i = 0; i < 5; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(position.pixels, greaterThan(initial), reason: 'read-only notes need a remote scroll target');
      final lower = position.pixels;
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(position.pixels, lessThan(lower));
      for (var step = 0; step < 100 && position.pixels < position.maxScrollExtent; step++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(position.pixels, position.maxScrollExtent, reason: 'the complete notes remain remotely readable');
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_focused(tester, find.byKey(const ValueKey('release-history-open-release'))), isTrue);
      if (width == 800) {
        await _press(tester, LogicalKeyboardKey.select);
        expect(find.byKey(const ValueKey('tv-link-dialog')), findsOneWidget);
        await _press(tester, LogicalKeyboardKey.escape);
        await _press(tester, LogicalKeyboardKey.escape);
        expect(find.byKey(const ValueKey('release-history-detail-dialog')), findsNothing);
        await _press(tester, LogicalKeyboardKey.select);
        final reopened = find.descendant(
          of: find.byKey(const ValueKey('release-history-detail-dialog')),
          matching: find.byType(Scrollable),
        );
        expect(tester.state<ScrollableState>(reopened).position.pixels, 0);
      } else {
        await _press(tester, LogicalKeyboardKey.arrowUp);
        expect(_focused(tester, find.byKey(const ValueKey('release-history-refresh'))), isTrue);
        await _press(tester, LogicalKeyboardKey.arrowDown);
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        final second = find.byKey(const ValueKey('release-history-desktop-8.0.0'));
        if (!_focused(tester, second)) await _press(tester, LogicalKeyboardKey.arrowDown);
        expect(_focused(tester, second), isTrue);
        await _press(tester, LogicalKeyboardKey.select);
        final other = find.descendant(
          of: find.byKey(const ValueKey('release-history-detail-8.0.0')),
          matching: find.byType(Scrollable),
        );
        expect(tester.state<ScrollableState>(other).position.pixels, 0);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final hasUrl in [false, true]) {
    testWidgets('issue 70: long update notes are readable with D-pad (URL=$hasUrl)', (tester) async {
      final feed = _Feed()
        ..snapshot = UpdateSnapshot(
          info: UpdateInfo(
            version: appVersion,
            buildNumber: pubspecBuild,
            releaseUrl: hasUrl ? 'https://example.com/release' : '',
            log: List.generate(40, (i) => '## Section $i\nUpdate notes paragraph $i').join('\n\n'),
          ),
        );
      final withNotes = feed.snapshot;
      final router = await _pump(tester, feed);
      unawaited(router.push<void>(RoutePath.kVersionPage));
      await tester.pumpAndSettle();
      final scroll = find.descendant(
        of: find.byKey(const ValueKey('version-update-scroll')),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scroll).position;
      expect(position.maxScrollExtent, greaterThan(position.viewportDimension));
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      final initial = position.pixels;
      for (var i = 0; i < 5; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(position.pixels, greaterThan(initial));
      for (var step = 0; step < 100 && position.pixels < position.maxScrollExtent; step++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(position.pixels, position.maxScrollExtent);
      final lower = position.pixels;
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(position.pixels, lessThan(lower));
      await _press(tester, LogicalKeyboardKey.arrowRight);
      final refresh = find.byKey(const ValueKey('version-refresh'));
      if (!_focused(tester, refresh)) await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_focused(tester, refresh), isTrue);
      feed.snapshot = UpdateSnapshot(
        info: UpdateInfo(
          version: appVersion,
          buildNumber: pubspecBuild,
          releaseUrl: hasUrl ? 'https://example.com/release' : '',
        ),
      );
      await _press(tester, LogicalKeyboardKey.select);
      expect(feed.checks, 2);
      expect(find.byKey(const ValueKey('version-keyboard-scroll')), findsNothing);
      expect(_focused(tester, refresh), isTrue);
      feed.snapshot = withNotes;
      await _press(tester, LogicalKeyboardKey.select);
      expect(feed.checks, 3);
      expect(_focused(tester, refresh), isTrue);
      expect(find.byKey(const ValueKey('version-keyboard-scroll')), findsOneWidget);
      final restored = tester.state<ScrollableState>(scroll).position;
      expect(restored.pixels, inInclusiveRange(restored.minScrollExtent, restored.maxScrollExtent));
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      final before = restored.pixels;
      await _press(
        tester,
        before == restored.maxScrollExtent ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown,
      );
      expect(restored.pixels, isNot(before));
      expect(tester.takeException(), isNull);
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const ValueKey('about-online-update')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final (size, scale) in [(const Size(640, 360), 1.0), (const Size(960, 540), 1.5)]) {
    testWidgets('issue 70: update and nested release actions fit $size at text scale $scale', (tester) async {
      final feed = _Feed()
        ..snapshot = _newer()
        ..history = const [
          ReleaseInfo(
            version: appVersion,
            date: '2026-10-27',
            github: 'https://example.com/release',
            changelog: '## Release notes\nReadable content',
            files: [_file],
          ),
        ];
      final router = await _pump(tester, feed, size: size, textScale: scale);
      unawaited(router.push<void>(RoutePath.kVersionPage));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      unawaited(router.push<void>(RoutePath.kVersionHistory));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('release-history-mobile-$appVersion'));
      if (row.evaluate().isNotEmpty) {
        await tester.tap(row);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('release-history-open-release')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tv-link-dialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byKey(const ValueKey('tv-link-dialog')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
