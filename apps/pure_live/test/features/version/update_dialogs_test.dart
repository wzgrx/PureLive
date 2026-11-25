import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/downloads.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/features/version/update_download.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/features/version/update_prompt.dart';
import 'package:pure_live/features/version/version_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/app_prompts.dart';

import '../../qa_capture.dart';
import '../../support.dart';

Map<String, Object?> _versionJson() =>
    jsonDecode(File('../../assets/version.json').readAsStringSync()) as Map<String, Object?>;

final class _FakeFeed extends UpdateFeed {
  new({this.info, this.history}) : super(NoNetworkHttp(), githubOrigin: false, platform: 'android');

  UpdateInfo? info;
  List<ReleaseInfo>? history;

  @override
  Future<UpdateInfo?> latest({Duration timeout = const Duration(seconds: 10)}) async => info;

  @override
  Future<List<ReleaseInfo>?> releases({Duration timeout = const Duration(seconds: 15), UpdateInfo? matching}) async =>
      history;
}

UpdateInfo _info(String version, {int? build}) => UpdateInfo.fromJson({
  ..._versionJson(),
  'version': version,
  'build_number': build ?? appBuild + 1,
  'version_desc': '- 斗鱼原画不再每 5 分钟断流\n- **更快**的播放',
  'platforms': const <String, Object?>{},
}, platform: 'android');

final _downloadBytes = [...List<int>.filled(1024 * 1024, 1), ...List<int>.filled(2 * 1024 * 1024, 2)];
final _downloadDigest = crypto.sha256.convert(_downloadBytes).toString();

ReleaseFile _apk(String version, {int? build, List<int>? bytes}) {
  final number = build ?? appBuild + 1;
  final content = bytes ?? _downloadBytes;
  return ReleaseFile(
    sizeBytes: content.length,
    sha256: bytes == null ? _downloadDigest : crypto.sha256.convert(content).toString(),
    name: 'PureLive-$version-$number-android-arm64-v8a-release.apk',
    size: '3mb',
    downloads: 1,
    url:
        'https://github.com/wzgrx/pure_live/releases/download/v$version/PureLive-$version-$number-android-arm64-v8a-release.apk',
  );
}

List<ReleaseInfo> _history(String version) => [
  ReleaseInfo(version: version, date: '2027-01-01', changelog: '-', files: [_apk(version)]),
];

/// Answers every download with [body], [size] long.
final class _GatedHttp implements LiveHttp {
  new({this.size});

  final int? size;
  final StreamController<List<int>> body = StreamController();
  int opens = 0;

  @override
  Future<LiveResponse> send(LiveRequest request) async => await (await open(request)).collect();

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    opens++;
    return LiveStreamedResponse(status: 200, body: body.stream, url: request.url, contentLength: size);
  }

  @override
  void close() {}
}

final class _PayloadHttp implements LiveHttp {
  new(this.bytes);

  List<int> bytes;
  int opens = 0;

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    opens++;
    return LiveStreamedResponse(status: 200, body: Stream.value(bytes), url: request.url, contentLength: bytes.length);
  }

  @override
  Future<LiveResponse> send(LiveRequest request) async => await (await open(request)).collect();

  @override
  void close() {}
}

final class _HeldFirstWrite extends DownloadFileOperations {
  final release = Completer<void>();
  RandomAccessFile? oldHandle;
  bool oldClosed = false;

  @override
  Future<void> write(RandomAccessFile file, List<int> bytes) async {
    if (oldHandle == null) {
      oldHandle = file;
      await release.future;
    }
    await super.write(file, bytes);
  }

  @override
  Future<void> close(RandomAccessFile file) async {
    await super.close(file);
    if (identical(file, oldHandle)) oldClosed = true;
  }
}

final class _Harness {
  new(this.services, this.toasts, this.opened, this.router);

  final AppServices services;
  final List<String> toasts;
  final List<String> opened;
  final GoRouter router;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  double width = 393,
  double height = 852,
  bool directional = false,
  String? nativePackage = 'arch_arm64',
  List<Override> overrides = const [],
  LiveRouteObserver? observer,
}) async {
  await prepareQaFonts(tester);
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final toasts = <String>[];
  final opened = <String>[];
  final previous = (AppNavigator.toast, AppNavigator.openExternal, AppNavigator.openFile);
  AppNavigator.toast = toasts.add;
  AppNavigator.openExternal = (uri) async {
    opened.add('$uri');
    return false;
  };
  AppNavigator.openFile = (path) async {
    opened.add(path);
    return false;
  };
  addTearDown(() {
    AppNavigator.toast = previous.$1;
    AppNavigator.openExternal = previous.$2;
    AppNavigator.openFile = previous.$3;
  });
  final router = GoRouter(
    observers: [?observer],
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: '/room',
        builder: (_, _) => const Scaffold(body: Text('room')),
      ),
      GoRoute(
        path: RoutePath.kVersionPage,
        builder: (_, _) => const Scaffold(body: Text('version page')),
      ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() => AppNavigator.router = null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        nativePackageTitleProvider.overrideWithValue(nativePackage),
        ...overrides,
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp.router(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(navigationMode: directional ? NavigationMode.directional : NavigationMode.traditional),
            child: child!,
          ),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(services, toasts, opened, router);
}

/// Lets real file and stream work run until [done] (or 50 rounds).
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      // A later directory decision can create the download dialog on this frame.
      await tester.pump();
    });
  }
}

final class _DownloadLaunch {
  Future<void>? closed;
  bool completed = false;
}

// Every launched dialog is dismissed through its real Navigator even when an
// assertion fails; never reset the production singleton to hide leaked routes.
Future<_DownloadLaunch> _showUpdateDownload(
  WidgetTester tester,
  BuildContext context, {
  required ReleaseFile file,
  required List<String> sources,
  String? version,
  UpdateInfo? update,
  bool historical = false,
  ReleaseInfo? historicalRelease,
}) async {
  final launch = _DownloadLaunch();
  addTearDown(() async {
    final publicClose = launch.closed;
    if (launch.completed || publicClose == null) return;
    for (var i = 0; i < 50 && !launch.completed; i++) {
      for (final navigator in tester.stateList<NavigatorState>(find.byType(Navigator)).toList().reversed) {
        navigator.popUntil((route) => route.isFirst);
      }
      await tester.pumpAndSettle();
      if (!launch.completed) await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    }
    expect(launch.completed, isTrue, reason: 'the real dialog route must close before test teardown');
    await publicClose;
  });
  // Await setup, not the dialog lifetime. Both the public operation and first
  // creation frame begin in real I/O; callers cannot overlap runAsync scopes.
  await tester.runAsync(() async {
    launch.closed = showUpdateDownload(
      context,
      file: file,
      sources: sources,
      version: version,
      update: update,
      historical: historical,
      historicalRelease: historicalRelease,
    ).whenComplete(() => launch.completed = true);
    await Future<void>.delayed(const Duration(seconds: 1));
    await tester.pump();
  });
  return launch;
}

UpdateDownloadTools _tools(LiveHttp http, Directory folder, {SettingsStore? settings, Directory? fallback}) =>
    UpdateDownloadTools(
      downloader: FileDownloader(http),
      folder: () async => folder,
      pickFastest: false,
      settings: settings,
      defaultFolder: fallback == null ? null : () async => fallback,
      pickFolder: () async => null,
    );

Directory _temp() {
  final dir = Directory.systemTemp.createTempSync('u3d_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// The text's left edge (for the order of a button row).
double _x(WidgetTester tester, String text) => tester.getCenter(find.text(text)).dx;

void main() {
  group('new version (U.3d c2–c5)', () {
    for (final longNotes in [false, true]) {
      testWidgets('issue #37: remote leaves ${longNotes ? "long" : "short"} notes and activates footer controls', (
        tester,
      ) async {
        final h = await _pump(tester, width: 1280, height: 720, directional: true);
        final info = UpdateInfo.fromJson({
          ..._versionJson(),
          'version': '9.0.0',
          'build_number': appBuild + 1,
          'version_desc': longNotes ? [for (var i = 0; i < 45; i++) '- Release note $i'].join('\n') : '- Short note',
          'platforms': const <String, Object?>{},
        }, platform: 'android');
        unawaited(
          checkForUpdateOnStartup(
            tester.element(find.text('home')),
            settings: h.services.store.settings,
            feed: _FakeFeed(info: info, history: _history('9.0.0')),
            prompts: AppPrompts(),
          ),
        );
        await tester.pumpAndSettle();

        bool focusedIn(String key) {
          final focused = FocusManager.instance.primaryFocus?.context;
          if (focused == null) return false;
          final target = find.byKey(ValueKey(key));
          return find
              .descendant(of: target, matching: find.byElementPredicate((e) => e == focused))
              .evaluate()
              .isNotEmpty;
        }

        Future<void> press(LogicalKeyboardKey key) async {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }

        final project = find.byKey(const ValueKey('new-version-open-project'));
        Focus.of(tester.element(find.descendant(of: project, matching: find.byType(Text)).first)).requestFocus();
        await tester.pumpAndSettle();
        expect(focusedIn('new-version-open-project'), isTrue);
        await press(LogicalKeyboardKey.arrowDown);
        if (longNotes) {
          await captureQaFrame(tester, 'update-long-notes-focus');
          await press(LogicalKeyboardKey.arrowUp);
          expect(focusedIn('new-version-open-project'), isTrue, reason: 'Up at the top leaves the notes');
          await press(LogicalKeyboardKey.arrowDown);
          final log = find.byKey(const ValueKey('new-version-log'));
          final scroll = tester.state<ScrollableState>(
            find.descendant(of: log, matching: find.byType(Scrollable)).first,
          );
          final before = scroll.position.pixels;
          await press(LogicalKeyboardKey.arrowDown);
          expect(scroll.position.pixels, greaterThan(before), reason: 'the remote scrolls a long changelog');
          await press(LogicalKeyboardKey.select);
          expect(
            find.byKey(const ValueKey('new-version-dialog')),
            findsOneWidget,
            reason: 'OK in the notes cannot install',
          );
        }
        final footer = ['new-version-skip', 'new-version-details', 'new-version-cancel', 'new-version-update'];
        for (var i = 0; i < 80 && !footer.any(focusedIn); i++) {
          await press(LogicalKeyboardKey.arrowDown);
        }
        expect(footer.any(focusedIn), isTrue, reason: 'Down must leave the notes and reach a visible action');

        Focus.of(tester.element(find.text('不再提醒这个版本'))).requestFocus();
        await tester.pumpAndSettle();
        await press(LogicalKeyboardKey.select);
        expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
        expect(h.services.store.settings.get(Settings.skippedUpdateVersion), info.skipToken);
        await press(LogicalKeyboardKey.select);
        expect(h.services.store.settings.get(Settings.skippedUpdateVersion), '');

        // The two neighbouring action keys remain reachable and OK acts on the focused one.
        Focus.of(tester.element(find.text('取消'))).requestFocus();
        await tester.pumpAndSettle();
        await press(LogicalKeyboardKey.arrowLeft);
        expect(focusedIn('new-version-details'), isTrue);
        await press(LogicalKeyboardKey.arrowRight);
        expect(focusedIn('new-version-cancel'), isTrue);
        await press(LogicalKeyboardKey.arrowRight);
        expect(focusedIn('new-version-update'), isTrue);
        await captureQaFrame(tester, longNotes ? 'update-long-download-focus' : 'update-short-download-focus');
        await press(LogicalKeyboardKey.arrowLeft);
        await press(LogicalKeyboardKey.select);
        expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);
        expect(h.opened, isEmpty);
      });
    }

    testWidgets('title, installed version, the link that keeps the dialog, notes, buttons in order', (tester) async {
      final h = await _pump(tester);
      final context = tester.element(find.text('home'));
      final feed = _FakeFeed(info: _info('9.0.0'), history: _history('9.0.0'));
      unawaited(
        checkForUpdateOnStartup(context, settings: h.services.store.settings, feed: feed, prompts: AppPrompts()),
      );
      await tester.pumpAndSettle();

      expect(find.text('发现新版本 v9.0.0'), findsOneWidget);
      expect(find.text('当前 v$appVersion'), findsOneWidget);
      expect(find.text('更新内容'), findsOneWidget);
      expect(find.textContaining('断流'), findsOneWidget);
      // 3.x's title and its link button that closed the dialog.
      expect(find.text('检查更新'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('new-version-open-project')));
      await tester.pumpAndSettle();
      expect(h.opened.single, projectUrl.toString());
      expect(find.byKey(const ValueKey('new-version-dialog')), findsOneWidget);

      // Narrow: the skip box on its own row above the buttons.
      final skip = tester.getRect(find.byKey(const ValueKey('new-version-skip')));
      final buttons = tester.getRect(find.byKey(const ValueKey('new-version-update')));
      expect(skip.bottom, lessThanOrEqualTo(buttons.top));
      expect(_x(tester, '其他下载方式'), lessThan(_x(tester, '取消')));
      expect(_x(tester, '取消'), lessThan(_x(tester, '下载并安装')));
      for (final label in ['其他下载方式', '取消', '下载并安装', '不再提醒这个版本']) {
        expect(tester.renderObject<RenderParagraph>(find.text(label)).text.style?.fontSize, 14, reason: label);
      }

      // "其他下载方式" goes to the version page.
      await tester.tap(find.text('其他下载方式'));
      await tester.pumpAndSettle();
      expect(find.text('version page'), findsOneWidget);
    });

    testWidgets('A18.1 c13: on an iPhone or iPad the main button is "去下载页" and opens the release page', (tester) async {
      final h = await _pump(tester);
      final context = tester.element(find.text('home'));
      final info = _info('9.0.0');
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        showDialog<void>(
          context: context,
          builder: (_) =>
              NewVersionDialog(info: info, package: _apk('9.0.0'), sources: const ['https://a.example/x.apk']),
        );
        await tester.pumpAndSettle();
        expect(find.text('下载并安装'), findsNothing, reason: 'an IPA is not installed from the app');
        await tester.tap(find.text('去下载页'));
        await tester.pumpAndSettle();
        expect(info.releaseUrl, startsWith('https://github.com/'));
        expect(h.opened, [info.releaseUrl]);
        expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('wide: the skip box at the left of the button row; Enter is the main button, Esc cancels', (
      tester,
    ) async {
      final h = await _pump(tester, width: 1280, height: 800);
      final context = tester.element(find.text('home'));
      // No package for this device: the main button is "更新" (the version page).
      final feed = _FakeFeed(info: _info('9.0.0'));
      unawaited(
        checkForUpdateOnStartup(context, settings: h.services.store.settings, feed: feed, prompts: AppPrompts()),
      );
      await tester.pumpAndSettle();
      final dialog = tester.getRect(
        find.descendant(of: find.byKey(const ValueKey('new-version-dialog')), matching: find.byType(Material)).first,
      );
      expect(dialog.width, lessThanOrEqualTo(560 + 0.5));
      final skip = tester.getCenter(find.byKey(const ValueKey('new-version-skip')));
      final update = tester.getCenter(find.byKey(const ValueKey('new-version-update')));
      expect((skip.dy - update.dy).abs(), lessThan(4));
      expect(skip.dx, lessThan(_x(tester, '取消')));
      expect(find.text('其他下载方式'), findsNothing);
      expect(find.text('更新'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);

      unawaited(
        checkForUpdateOnStartup(context, settings: h.services.store.settings, feed: feed, prompts: AppPrompts()),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('version page'), findsOneWidget);
    });

    testWidgets('landscape phone: a long log scrolls on its own, the buttons stay on screen', (tester) async {
      final h = await _pump(tester, width: 852, height: 393);
      final context = tester.element(find.text('home'));
      final long = UpdateInfo.fromJson({
        ..._versionJson(),
        'version': '9.0.0',
        'build_number': appBuild + 1,
        'version_desc': [for (var i = 0; i < 30; i++) '- 第 $i 条改动'].join('\n'),
        'platforms': const <String, Object?>{},
      }, platform: 'android');
      unawaited(
        checkForUpdateOnStartup(
          context,
          settings: h.services.store.settings,
          feed: _FakeFeed(info: long, history: _history('9.0.0')),
          prompts: AppPrompts(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final update = tester.getRect(find.byKey(const ValueKey('new-version-update')));
      expect(update.bottom, lessThanOrEqualTo(393));
      expect(find.text('发现新版本 v9.0.0'), findsOneWidget);
      final log = find.byKey(const ValueKey('new-version-log'));
      expect(tester.getRect(log).bottom, lessThanOrEqualTo(update.top));
      await tester.drag(log, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('new-version-update'))), update);
    });

    testWidgets('"不再提醒这个版本" silences this version only', (tester) async {
      final h = await _pump(tester);
      final context = tester.element(find.text('home'));
      final settings = h.services.store.settings;
      final feed = _FakeFeed(info: _info('9.0.0'));
      unawaited(checkForUpdateOnStartup(context, settings: settings, feed: feed, prompts: AppPrompts()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不再提醒这个版本'));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        settings.get(Settings.skippedUpdateVersion),
        '9.0.0+${_info('9.0.0').buildNumber}',
        reason: 'with its build (Y02.1)',
      );

      await checkForUpdateOnStartup(context, settings: settings, feed: feed, prompts: AppPrompts());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);

      feed.info = _info('9.0.1');
      unawaited(checkForUpdateOnStartup(context, settings: settings, feed: feed, prompts: AppPrompts()));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v9.0.1'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });

    testWidgets(
      'the same version with a newer build is offered, its build named; skipping it skips that build (Y02.1)',
      (tester) async {
        final h = await _pump(tester);
        final context = tester.element(find.text('home'));
        final settings = h.services.store.settings;
        final feed = _FakeFeed(info: _info(appVersion, build: appBuild + 1));
        unawaited(checkForUpdateOnStartup(context, settings: settings, feed: feed, prompts: AppPrompts()));
        await tester.pumpAndSettle();
        expect(find.text('发现新版本 v$appVersion（构建号 ${appBuild + 1}）'), findsOneWidget);
        await tester.tap(find.text('不再提醒这个版本'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(settings.get(Settings.skippedUpdateVersion), '$appVersion+${appBuild + 1}');

        await checkForUpdateOnStartup(context, settings: settings, feed: feed, prompts: AppPrompts());
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);

        feed.info = _info(appVersion, build: appBuild + 2);
        unawaited(checkForUpdateOnStartup(context, settings: settings, feed: feed, prompts: AppPrompts()));
        await tester.pumpAndSettle();
        expect(find.text('发现新版本 v$appVersion（构建号 ${appBuild + 2}）'), findsOneWidget);
        expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();

        // A version skipped before builds counted (only the version) skips every build of it.
        await settings.set(Settings.skippedUpdateVersion, appVersion);
        await checkForUpdateOnStartup(context, settings: settings, feed: feed, prompts: AppPrompts());
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);
      },
    );

    testWidgets('waits while another page is on top and opens when home is back (U.3c c7, K2)', (tester) async {
      final observer = LiveRouteObserver();
      final h = await _pump(tester, observer: observer);
      final prompts = AppPrompts(listenRoutes: observer.addListener);
      final context = tester.element(find.text('home'));
      unawaited(h.router.push<void>('/room'));
      await tester.pumpAndSettle();
      final feed = _FakeFeed(info: _info('9.0.0'));
      unawaited(checkForUpdateOnStartup(context, settings: h.services.store.settings, feed: feed, prompts: prompts));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);
      expect(prompts.waiting, 1);

      h.router.pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-version-dialog')), findsOneWidget);
    });
  });

  testWidgets('Y02.2: a queued startup prompt cannot recommend an already superseded snapshot', (tester) async {
    final observer = LiveRouteObserver();
    final h = await _pump(tester, observer: observer);
    final context = tester.element(find.text('home'));
    final prompts = AppPrompts(listenRoutes: observer.addListener);
    final feed = _FakeFeed(info: _info('9.0.0'), history: _history('9.0.0'));
    unawaited(h.router.push<void>('/room'));
    await tester.pumpAndSettle();
    unawaited(checkForUpdateOnStartup(context, settings: h.services.store.settings, feed: feed, prompts: prompts));
    await tester.pumpAndSettle();
    expect(prompts.waiting, 1);
    feed.info = const UpdateInfo(version: '10.0.0', buildNumber: 6000);
    noteCheckedUpdate((await feed.check())!.info);
    h.router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);
    expect(foundUpdate.value?.version, '10.0.0');
  });

  testWidgets('Y02.2: a queued startup prompt is discarded after its source policy changes', (tester) async {
    final observer = LiveRouteObserver();
    final h = await _pump(tester, observer: observer);
    final context = tester.element(find.text('home'));
    final prompts = AppPrompts(listenRoutes: observer.addListener);
    final feed = _FakeFeed(info: _info('9.0.0'), history: _history('9.0.0'));
    unawaited(h.router.push<void>('/room'));
    await tester.pumpAndSettle();
    unawaited(checkForUpdateOnStartup(context, settings: h.services.store.settings, feed: feed, prompts: prompts));
    await tester.pumpAndSettle();
    expect(prompts.waiting, 1);
    await tester.runAsync(() => h.services.store.settings.set(Settings.useGitHubOriginForUpdates, true));
    feed.deactivate();
    foundUpdate.value = null;
    h.router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);
    expect(foundUpdate.value, isNull);
  });

  testWidgets('Y02.2: missing native ABI opens details instead of offering another APK', (tester) async {
    final h = await _pump(tester, nativePackage: 'arch_arm32');
    final context = tester.element(find.text('home'));
    final feed = _FakeFeed(info: _info('9.0.0'), history: _history('9.0.0'));
    unawaited(checkForUpdateOnStartup(context, settings: h.services.store.settings, feed: feed, prompts: AppPrompts()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-version-dialog')), findsOneWidget);
    expect(find.text('下载并安装'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('new-version-update')));
    await tester.pumpAndSettle();
    expect(find.text('version page'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
  });

  testWidgets('Y02.2: the download entry rejects missing, older, current and mismatched update identities', (
    tester,
  ) async {
    final folder = _temp();
    final http = _GatedHttp(size: 1024);
    final h = await _pump(tester, overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(http, folder))]);
    final context = tester.element(find.text('home'));
    for (final info in <UpdateInfo?>[
      null,
      const UpdateInfo(version: '1.0.0', buildNumber: 99999),
      UpdateInfo(version: appVersion, buildNumber: appBuild),
      const UpdateInfo(version: '9.0.0', buildNumber: 1),
    ]) {
      await _showUpdateDownload(tester, context, file: _apk('9.0.0'), sources: [_apk('9.0.0').url], update: info);
    }
    await _showUpdateDownload(
      tester,
      context,
      file: _apk('9.0.0'),
      sources: [_apk('8.0.0').url],
      update: _info('9.0.0'),
    );
    final lowerBuild = _apk('9.0.0', build: 1);
    await _showUpdateDownload(
      tester,
      context,
      file: lowerBuild,
      sources: [lowerBuild.url],
      update: _info('9.0.0', build: 1),
    );
    expect(http.opens, 0);
    expect(h.toasts, hasLength(6));
    expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
  });

  group('Y02.3 verified update policy', () {
    testWidgets('legacy metadata stays readable with explicit browser fallback, not install or retry', (tester) async {
      final folder = _temp();
      final http = _PayloadHttp([1, 2, 3]);
      final h = await _pump(tester, overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(http, folder))]);
      final named = _apk('9.0.0');
      final legacy = ReleaseFile(name: named.name, size: named.size, downloads: named.downloads, url: named.url);
      await _showUpdateDownload(
        tester,
        tester.element(find.text('home')),
        file: legacy,
        sources: downloadSources(legacy.url, githubOrigin: false),
        update: _info('9.0.0'),
      );
      await tester.pumpAndSettle();
      expect(http.opens, 0);
      expect(find.text('此版本未提供完整校验信息，无法在应用内下载。可在浏览器中自行下载。'), findsOneWidget);
      expect(find.byKey(const ValueKey('update-download-install')), findsNothing);
      expect(find.byKey(const ValueKey('update-download-retry')), findsNothing);
      expect(find.byKey(const ValueKey('download-directory-dialog')), findsNothing);
      expect(h.opened, isEmpty, reason: 'browser is a separate user action');
      await tester.tap(find.byKey(const ValueKey('update-download-browser')));
      await tester.pumpAndSettle();
      expect(h.opened, [legacy.url]);
      await tester.tap(find.byKey(const ValueKey('update-download-close')));
      await tester.pumpAndSettle();
    });

    testWidgets('historical confirmation cannot bypass malformed release build metadata', (tester) async {
      final folder = _temp();
      final http = _PayloadHttp([1, 2, 3]);
      await _pump(tester, overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(http, folder))]);
      final file = _apk('9.0.0', bytes: [1, 2, 3]);
      final release = ReleaseInfo(version: '9.0.0', date: '2027-01-01', buildNumber: 1, files: [file]);
      await _showUpdateDownload(
        tester,
        tester.element(find.text('home')),
        file: file,
        sources: [file.url],
        historical: true,
        historicalRelease: release,
      );
      await tester.pumpAndSettle();
      expect(http.opens, 0);
      expect(find.text('安装包校验信息无效，无法在应用内下载。可在浏览器中自行下载。'), findsOneWidget);
      expect(find.byKey(const ValueKey('update-download-install')), findsNothing);
      expect(find.byKey(const ValueKey('update-download-retry')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('update-download-close')));
      await tester.pumpAndSettle();
    });

    testWidgets('Back then reopen waits for the old target write before offering verified Install', (tester) async {
      final folder = _temp();
      final http = _PayloadHttp([3, 2, 1]);
      final operations = _HeldFirstWrite();
      var folderCalls = 0;
      final h = await _pump(
        tester,
        overrides: [
          updateDownloadToolsProvider.overrideWithValue(
            UpdateDownloadTools(
              downloader: FileDownloader(http, fileOperations: operations),
              folder: () async {
                folderCalls++;
                return folder;
              },
              pickFastest: false,
            ),
          ),
        ],
      );
      final file = _apk('9.0.0', bytes: [1, 2, 3]);
      try {
        final first = await _showUpdateDownload(
          tester,
          tester.element(find.text('home')),
          file: file,
          sources: [file.url],
          update: _info('9.0.0'),
        );
        await _until(tester, () => operations.oldHandle != null);
        expect(operations.oldHandle, isNotNull);
        await tester.binding.handlePopRoute();
        await _until(tester, () => first.completed);
        expect(first.completed, isTrue);
        expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
        expect(operations.oldClosed, isFalse, reason: 'route closure does not finish the held write');
        http.bytes = [1, 2, 3];
        final reopened = await _showUpdateDownload(
          tester,
          tester.element(find.text('home')),
          file: file,
          sources: [file.url],
          update: _info('9.0.0'),
        );
        await _until(tester, () => folderCalls == 2);
        expect(folderCalls, 2);
        expect(find.byKey(const ValueKey('update-download-dialog')), findsOneWidget);
        // Let unrelated file work finish while the reopened download waits for
        // its old owner. No extra production lifecycle hooks are needed.
        await tester.runAsync(() async {
          await FileDownloader(_PayloadHttp([1, 2, 3]))
              .download([Uri.parse(file.url)], File('${folder.path}/unrelated'));
          await tester.pump();
        });
        expect(http.opens, 1);
        expect(find.byKey(const ValueKey('update-download-install')), findsNothing);
        operations.release.complete();
        await _until(tester, () => find.byKey(const ValueKey('update-download-install')).evaluate().isNotEmpty);
        expect(operations.oldClosed, isTrue);
        expect(http.opens, 2);
        expect(find.byKey(const ValueKey('update-download-install')), findsOneWidget);
        expect(File('${folder.path}/${file.name}').readAsBytesSync(), [1, 2, 3]);
        expect(h.opened, isEmpty, reason: 'neither old cancellation nor verified completion auto-installs');
        await tester.tap(find.byKey(const ValueKey('update-download-close')));
        await _until(tester, () => reopened.completed);
        expect(reopened.completed, isTrue);
        expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
      } finally {
        if (!operations.release.isCompleted) operations.release.complete();
        if (operations.oldHandle != null) await _until(tester, () => operations.oldClosed);
        for (final navigator in tester.stateList<NavigatorState>(find.byType(Navigator)).toList().reversed) {
          navigator.popUntil((route) => route.isFirst);
        }
        await tester.runAsync(tester.pumpAndSettle);
      }
    });

    testWidgets('same-length corruption never enables Install; retry verifies fresh bytes', (tester) async {
      final folder = _temp();
      final http = _PayloadHttp([3, 2, 1]);
      final h = await _pump(tester, overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(http, folder))]);
      final file = _apk('9.0.0', bytes: [1, 2, 3]);
      await _showUpdateDownload(
        tester,
        tester.element(find.text('home')),
        file: file,
        sources: [file.url],
        update: _info('9.0.0'),
      );
      await _until(tester, () => find.byKey(const ValueKey('update-download-retry')).evaluate().isNotEmpty);
      expect(find.text('安装包校验失败，未提供安装。请重试或在浏览器中下载。'), findsOneWidget);
      expect(find.byKey(const ValueKey('update-download-install')), findsNothing);
      expect(h.opened, isEmpty);
      expect(File('${folder.path}/${file.name}').existsSync(), isFalse);
      expect(http.opens, 2);
      http.bytes = [1, 2, 3];
      await tester.runAsync(() => tester.tap(find.byKey(const ValueKey('update-download-retry'))));
      await _until(tester, () => find.byKey(const ValueKey('update-download-install')).evaluate().isNotEmpty);
      expect(find.byKey(const ValueKey('update-download-install')), findsOneWidget);
      expect(File('${folder.path}/${file.name}').readAsBytesSync(), [1, 2, 3]);
      expect(http.opens, 3, reason: 'retry makes one fresh verified request');
      expect(h.opened, isEmpty, reason: 'successful verification does not auto-install');
      await tester.tap(find.byKey(const ValueKey('update-download-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
    });
  });

  group('download (U.3d c7–c10)', () {
    testWidgets('issue 132: a completed TV download focuses install without an extra key', (tester) async {
      final folder = _temp();
      final http = _GatedHttp(size: _downloadBytes.length);
      final h = await _pump(
        tester,
        width: 1280,
        height: 720,
        directional: true,
        overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(http, folder))],
      );
      await _showUpdateDownload(
        tester,
        tester.element(find.text('home')),
        file: _apk('9.0.0'),
        sources: [_apk('9.0.0').url],
        update: _info('9.0.0'),
      );
      await _until(tester, () => http.opens > 0);
      http.body.add(_downloadBytes);
      unawaited(http.body.close());
      final install = find.byKey(const ValueKey('update-download-install'));
      await _until(tester, () => install.evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      final element = tester.element(install);
      var focused = false;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((ancestor) {
        focused = identical(ancestor, element);
        return !focused;
      });
      expect(focused, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(h.opened.single, endsWith('.apk'), reason: 'the first OK acts on the visible install action');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    });

    testWidgets('downloading, done, open failed, folder failed: titles, lines and buttons', (tester) async {
      final folder = _temp();
      final http = _GatedHttp(size: 3 * 1024 * 1024);
      final h = await _pump(tester, overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(http, folder))]);
      final context = tester.element(find.text('home'));
      await _showUpdateDownload(
        tester,
        context,
        file: _apk('9.0.0'),
        sources: [_apk('9.0.0').url],
        update: _info('9.0.0'),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('正在下载 v9.0.0'), findsOneWidget);
      expect(find.text('准备中...'), findsOneWidget);
      expect(find.text('…'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('关闭'), findsNothing);
      // No toast repeating the title (D5).
      expect(h.toasts, isEmpty);

      await _until(tester, () => http.opens > 0);
      http.body.add(List.filled(1024 * 1024, 1));
      await _until(tester, () => find.text('33%').evaluate().isNotEmpty);
      expect(find.text('1.0 MB / 3.0 MB'), findsOneWidget);

      http.body.add(List.filled(2 * 1024 * 1024, 2));
      unawaited(http.body.close());
      await _until(tester, () => find.text('v9.0.0 已下载').evaluate().isNotEmpty);
      expect(find.text('下载完成'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      // Close at the left, then open folder and install.
      expect(_x(tester, '关闭'), lessThan(_x(tester, '打开文件夹')));
      expect(_x(tester, '打开文件夹'), lessThan(_x(tester, '立即安装')));
      expect(find.byIcon(AppIcons.downloadDone), findsOneWidget);

      // The installer does not open: the reason and "重新打开".
      await tester.tap(find.text('立即安装'));
      await tester.pumpAndSettle();
      expect(find.text('文件已下载，但打开失败。'), findsOneWidget);
      expect(find.text('重新打开'), findsOneWidget);
      expect(find.byIcon(AppIcons.downloadFailed), findsOneWidget);
      expect(h.opened.last, endsWith('.apk'));

      // Back closes a finished download (the file stays).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
      expect(File('${folder.path}/${_apk('9.0.0').name}').existsSync(), isTrue);
    });

    testWidgets('A18.2 c10: on a Mac a finished download has one button, "在访达中显示"', (tester) async {
      final folder = _temp();
      final http = _GatedHttp(size: 1024);
      final revealed = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('pure_live/finder'), (
        call,
      ) async {
        revealed.add((call.method, (call.arguments as Map)['path']));
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('pure_live/finder'),
          null,
        ),
      );
      final h = await _pump(tester, overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(http, folder))]);
      final context = tester.element(find.text('home'));
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _showUpdateDownload(
          tester,
          context,
          file: _apk('9.0.0', bytes: List<int>.filled(1024, 1)),
          sources: [_apk('9.0.0').url],
          update: _info('9.0.0'),
        );
        await tester.pump();
        await _until(tester, () => http.opens > 0);
        http.body.add(List.filled(1024, 1));
        unawaited(http.body.close());
        await _until(tester, () => find.text('v9.0.0 已下载').evaluate().isNotEmpty);
        expect(find.text('打开文件夹'), findsNothing);
        expect(find.text('立即安装'), findsNothing);
        expect(_x(tester, '关闭'), lessThan(_x(tester, '在访达中显示')));
        await tester.tap(find.text('在访达中显示'));
        await tester.pumpAndSettle();
        expect(revealed, [('reveal', '${folder.path}/${_apk('9.0.0').name}')]);
        expect(h.opened, isEmpty, reason: 'nothing is opened, the DMG is shown');
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('unknown HTTP size uses exact metadata; failure keeps retry, browser and close', (tester) async {
      final folder = _temp();
      final http = _GatedHttp();
      await _pump(tester, overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(http, folder))]);
      final context = tester.element(find.text('home'));
      await _showUpdateDownload(
        tester,
        context,
        file: _apk('9.0.0'),
        sources: [_apk('9.0.0').url],
        update: _info('9.0.0'),
      );
      await _until(tester, () => http.opens > 0);
      http.body.add(List.filled(1024 * 1024, 1));
      await _until(tester, () => find.text('1.0 MB / 3.0 MB').evaluate().isNotEmpty);
      expect(find.text('33%'), findsOneWidget);
      http.body.addError(const TransportFailure('update', TransportReason.connect, 'cut'));
      await _until(tester, () => find.text('下载没有完成').evaluate().isNotEmpty);
      expect(find.text('下载中断，已下载的部分会保留，重试时接着下载'), findsOneWidget);
      expect(_x(tester, '关闭'), lessThan(_x(tester, '在浏览器中下载')));
      expect(_x(tester, '在浏览器中下载'), lessThan(_x(tester, '重试')));
      final scheme = Theme.of(tester.element(find.text('下载没有完成'))).colorScheme;
      expect(
        tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('update-download-message'))).text.style?.color,
        scheme.error,
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
    });

    testWidgets('cancel while downloading keeps the part; Back is the same cancel', (tester) async {
      final folder = _temp();
      final http = _GatedHttp(size: 3 * 1024 * 1024);
      final h = await _pump(tester, overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(http, folder))]);
      final context = tester.element(find.text('home'));
      await _showUpdateDownload(
        tester,
        context,
        file: _apk('9.0.0'),
        sources: [_apk('9.0.0').url],
        update: _info('9.0.0'),
      );
      await _until(tester, () => http.opens > 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
      expect(h.toasts.single, '已取消下载，下次会接着已下载的部分继续');

      // Esc on a computer is the same cancel (a tap outside does nothing).
      final again = _GatedHttp(size: 3 * 1024 * 1024);
      final folder2 = _temp();
      await tester.pumpWidget(const SizedBox.shrink());
      final h2 = await _pump(
        tester,
        width: 1280,
        height: 800,
        overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(again, folder2))],
      );
      await _showUpdateDownload(
        tester,
        tester.element(find.text('home')),
        file: _apk('9.0.0'),
        sources: [_apk('9.0.0').url],
        update: _info('9.0.0'),
      );
      await _until(tester, () => again.opens > 0);
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(find.byKey(const ValueKey('update-download-dialog')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
      expect(h2.toasts.single, '已取消下载，下次会接着已下载的部分继续');
    });
  });

  group('download folder (U.3d c6)', () {
    testWidgets('asked when never answered and the default is missing; cancel, Esc and outside cancel the download', (
      tester,
    ) async {
      final folder = _temp();
      final missing = Directory('${folder.path}/missing');
      final http = _GatedHttp(size: 3 * 1024 * 1024);
      late SettingsStore settings;
      final h = await _pump(
        tester,
        overrides: [
          updateDownloadToolsProvider.overrideWith(
            (ref) => _tools(http, folder, settings: ref.watch(appServicesProvider).store.settings, fallback: missing),
          ),
        ],
      );
      settings = h.services.store.settings;
      final context = tester.element(find.text('home'));
      Future<_DownloadLaunch> start() async {
        final launch = await _showUpdateDownload(
          tester,
          context,
          file: _apk('9.0.0'),
          sources: [_apk('9.0.0').url],
          update: _info('9.0.0'),
        );
        await _until(tester, () => find.byKey(const ValueKey('download-directory-dialog')).evaluate().isNotEmpty);
        return launch;
      }

      await start();
      expect(find.text('选择下载目录'), findsOneWidget);
      expect(find.textContaining(missing.path), findsOneWidget);
      expect(_x(tester, '取消'), lessThan(_x(tester, '使用默认目录')));
      expect(_x(tester, '使用默认目录'), lessThan(_x(tester, '选择目录')));
      await tester.tap(find.text('取消'));
      await _until(tester, () => h.toasts.isNotEmpty);
      expect(h.toasts.last, '未选择下载目录，已取消下载');
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);

      await start();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _until(tester, () => h.toasts.length > 1);
      expect(h.toasts.last, '未选择下载目录，已取消下载');

      await start();
      await tester.tapAt(const Offset(10, 10));
      await _until(tester, () => h.toasts.length > 2);
      expect(h.toasts.last, '未选择下载目录，已取消下载');

      // The default folder: remembered, the download starts, no more asking.
      final launch = await start();
      await tester.tap(find.text('使用默认目录'));
      await _until(tester, () => find.byKey(const ValueKey('update-download-dialog')).evaluate().isNotEmpty);
      expect(settings.get(Settings.downloadDirectoryDecisionMade), isTrue);
      expect(settings.get(Settings.downloadDirectoryPath), '');
      // Dismiss before the test binding unmounts its Navigator. This observes
      // the public route lifetime, not completion of every cancelled file op.
      await tester.tap(find.byKey(const ValueKey('update-download-cancel')));
      await _until(tester, () => launch.completed);
      expect(launch.completed, isTrue);
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
    });
  });
}
