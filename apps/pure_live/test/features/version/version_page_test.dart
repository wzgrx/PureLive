import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

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
import 'package:pure_live/features/about/about_page.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/features/version/update_download.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/features/version/update_prompt.dart';
import 'package:pure_live/features/version/version_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';

/// The repository's own update files (the ones 3.x reads too).
Map<String, Object?> _versionJson() =>
    jsonDecode(File('../../assets/version.json').readAsStringSync()) as Map<String, Object?>;

Object? _releasesJson() => jsonDecode(File('../../assets/releases.json').readAsStringSync());

/// A feed with fixed answers; [latest] null means no source answered.
final class _FakeFeed extends UpdateFeed {
  new({this.info, this.history}) : super(NoNetworkHttp(), githubOrigin: false, platform: 'android');

  UpdateInfo? info;
  List<ReleaseInfo>? history;
  int checks = 0;
  Completer<UpdateInfo?>? latestGate;

  @override
  Future<UpdateInfo?> latest({Duration timeout = const Duration(seconds: 10)}) async {
    checks++;
    final gate = latestGate;
    return gate == null ? info : await gate.future;
  }

  @override
  Future<List<ReleaseInfo>?> releases({Duration timeout = const Duration(seconds: 15), UpdateInfo? matching}) async =>
      history;
}

UpdateInfo _newer() => UpdateInfo.fromJson({
  ..._versionJson(),
  'version': '9.0.0',
  'build_number': appBuild + 1,
  'version_desc': '## 新功能\n- **更快**的播放',
  'platforms': const <String, Object?>{},
}, platform: 'android');

List<ReleaseInfo> _historyWith9() => [
  ReleaseInfo(
    version: '9.0.0',
    date: '2027-01-01',
    changelog: '# v9\n- 改进',
    files: [
      for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64'])
        ReleaseFile(
          name: 'PureLive-9.0.0-${pubspecBuild + 1}-android-$abi-release.apk',
          size: '100mb',
          sizeBytes: 3000,
          sha256: '0f378acebd51c8b1fca222ee057b87b8de674e9aaaad845d7ff4a1e177117b36',
          downloads: 1,
          url:
              'https://github.com/wzgrx/pure_live/releases/download/v9.0.0/PureLive-9.0.0-${pubspecBuild + 1}-android-$abi-release.apk',
        ),
    ],
  ),
  // The installed version as the newest one the repository lists: the
  // version bump comes before the update files (PROCESS §11.7), so between
  // them the repository's list does not have it yet.
  if (!parseReleases(_releasesJson()).any((release) => release.version == appVersion))
    const ReleaseInfo(version: appVersion, date: '2026-10-09', changelog: '# v$appVersion'),
  ...parseReleases(_releasesJson()),
];

Future<(AppServices, List<String>)> _pump(
  WidgetTester tester,
  Widget page,
  _FakeFeed feed, {
  double width = 420,
  double height = 900,
  List<Override> overrides = const [],
  LiveFontSizes fontSizes = const LiveFontSizes(),
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final toasts = <String>[];
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previousToast);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => page),
      GoRoute(
        path: RoutePath.kVersionPage,
        builder: (_, _) => const Scaffold(body: Text('version page')),
      ),
      GoRoute(
        path: RoutePath.kVersionHistory,
        builder: (_, _) => const Scaffold(body: Text('history page')),
      ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() => AppNavigator.router = null);
  addTearDown(() => foundUpdate.value = null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        updateFeedProvider.overrideWithValue(feed),
        ...overrides,
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp.router(
          theme: LiveTheme(primaryColor: Colors.blue, fontSizes: fontSizes).light,
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (services, toasts);
}

void main() {
  test("the installed version is pubspec.yaml's", () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^version: (\S+)$', multiLine: true).firstMatch(pubspec)!.group(1), '$pubspecVersion+$pubspecBuild');
    expect(appVersion, pubspecVersion);
    expect(appBuild, pubspecBuild);
  });

  // The update files offer the latest release: this tree's once its
  // packages are up, the one before while it is being released (PROCESS
  // §11: they change last).
  test('reads the repository update files as 3.x does', () {
    final android = UpdateInfo.fromJson(_versionJson(), platform: 'android');
    final offered = android.version;
    expect(isNewerVersion(offered, pubspecVersion), isFalse, reason: 'never ahead of this tree');
    if (offered == pubspecVersion) expect(android.buildNumber, pubspecBuild);
    expect(android.androidAbis, {'arm64-v8a', 'armeabi-v7a', 'x86_64'});
    expect(android.isNewer, isFalse);
    // A platform block overrides the top level; the release is on Linux,
    // macOS and iOS too (5.4.1 brought the Apple platforms back from 3.2.10).
    for (final platform in ['linux', 'macos', 'ios']) {
      expect(UpdateInfo.fromJson(_versionJson(), platform: platform).version, offered, reason: platform);
    }
    expect(() => UpdateInfo.fromJson({'version': '1.0.0'}, platform: 'android'), throwsFormatException);

    final releases = parseReleases(_releasesJson());
    expect(releases.first.version, offered);
    for (var i = 1; i < releases.length; i++) {
      expect(releases[i - 1].date.compareTo(releases[i].date), greaterThanOrEqualTo(0));
    }
    final packages = platformPackages('android', android, releases.first.files);
    expect([for (final (title, _) in packages) title], ['arch_arm64', 'arch_arm32', 'arch_x86_64']);
    expect(packages.first.$2.name, contains('arm64-v8a'));
    // The release is on Windows too, with the installer and the portable ZIP.
    final windowsInfo = UpdateInfo.fromJson(_versionJson(), platform: 'windows');
    expect(windowsInfo.version, offered);
    final windows = platformPackages(
      'windows',
      windowsInfo,
      releases.firstWhere((release) => release.version == windowsInfo.version).files,
    );
    expect([for (final (title, _) in windows) title], containsAll(['exe_installer', 'portable_package']));
    // The macOS card offers the disk image of the same release.
    final macos = platformPackages('macos', windowsInfo, releases.first.files);
    expect(
      [for (final (title, file) in macos) '$title ${file.name.endsWith('-macos-universal.dmg')}'],
      ['macos_package true'],
    );
    // X02.1: Linux gets 3.x's tarball name.
    final linux = platformPackages('linux', windowsInfo, const [
      ReleaseFile(
        name: 'PureLive-5.0.0-5100-linux-x64.tar.gz',
        size: '',
        downloads: 0,
        url: 'https://example.com/a.tar.gz',
      ),
      ReleaseFile(
        name: 'PureLive-5.0.0-5100-windows-x64-portable.zip',
        size: '',
        downloads: 0,
        url: 'https://example.com/a.zip',
      ),
    ]);
    expect(
      [for (final (title, file) in linux) '$title ${file.name}'],
      ['linux_package PureLive-5.0.0-5100-linux-x64.tar.gz'],
    );

    expect(isNewerVersion('3.2.12', '3.2.11'), isTrue);
    expect(isNewerVersion('v3.10.0', '3.9.9+1'), isTrue);
    expect(isNewerVersion('3.2.11', '3.2.11'), isFalse);
    expect(isNewerVersion('x', '3.2.11'), isFalse);
    // The same version with a newer build (Y02.1: 4.0.0 was re-released as build 5001).
    const rebuilt = UpdateInfo(version: '4.0.0', buildNumber: 5001);
    expect(rebuilt.newerThan('4.0.0', 5000), isTrue);
    expect(rebuilt.newerThan('v4.0.0', 5001), isFalse);
    expect(rebuilt.newerThan('4.0.1', 1), isFalse);
    expect(const UpdateInfo(version: '3.9.9', buildNumber: 9999).newerThan('4.0.0', 5001), isFalse);
    expect(compareVersions('3.2.10', '3.2.9'), greaterThan(0));
    expect(downloadSources('https://github.com/a/b.apk', githubOrigin: true), ['https://github.com/a/b.apk']);
    final mirrors = downloadSources('https://github.com/a/b.apk', githubOrigin: false);
    expect(mirrors.first, 'https://cdn.gh-proxy.org/https://github.com/a/b.apk');
    expect(mirrors.last, 'https://github.com/a/b.apk');
    expect(downloadSources('https://user:pw@github.com/a.apk', githubOrigin: false), isEmpty);
  });

  testWidgets('shows a newer version, its packages and notes, and copies a source', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final feed = _FakeFeed(info: _newer(), history: _historyWith9());
    final (_, toasts) = await _pump(tester, const VersionPage(route: RouteArgs(RoutePath.kVersionPage)), feed);
    expect(find.byKey(const ValueKey('version-newer')), findsOneWidget);
    expect(find.text('发现新版本: v9.0.0'), findsOneWidget);
    expect(find.text('当前 v$appVersion'), findsOneWidget);
    expect(find.textContaining('ARM64'), findsOneWidget);
    expect(find.textContaining('更快'), findsOneWidget);
    final updateScroll = tester.widget<ListView>(
      find.descendant(of: find.byKey(const ValueKey('version-update-scroll')), matching: find.byType(ListView)),
    );
    expect(updateScroll.controller, isNull);
    expect(find.byType(KeyboardScrollArea), findsNothing);

    // The mirrors are folded under "选择下载源" (U.12b c7).
    final first = find.byKey(
      const ValueKey('version-source-PureLive-9.0.0-${pubspecBuild + 1}-android-arm64-v8a-release.apk-0'),
    );
    expect(first, findsNothing);
    final sources = find.byKey(
      const ValueKey('version-sources-PureLive-9.0.0-${pubspecBuild + 1}-android-arm64-v8a-release.apk'),
    );
    await tester.ensureVisible(sources);
    await tester.tap(sources);
    await tester.pumpAndSettle();
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('version-source-copy')));
    await tester.pumpAndSettle();
    expect(copied.single, startsWith('https://cdn.gh-proxy.org/https://github.com/wzgrx/pure_live/releases/download/'));
    expect(toasts.last, '已复制到剪贴板');
  });

  testWidgets('downloads a package in the app and opens the installer', (tester) async {
    final temp = Directory.systemTemp.createTempSync('update_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final http = _BytesHttp(List.generate(3000, (i) => i % 13));
    final opened = <String>[];
    final previousOpen = AppNavigator.openFile;
    AppNavigator.openFile = (path) async {
      opened.add(path);
      return true;
    };
    addTearDown(() => AppNavigator.openFile = previousOpen);
    final feed = _FakeFeed(info: _newer(), history: _historyWith9());
    await _pump(
      tester,
      const VersionPage(route: RouteArgs(RoutePath.kVersionPage)),
      feed,
      overrides: [
        updateDownloadToolsProvider.overrideWithValue(
          UpdateDownloadTools(downloader: FileDownloader(http), folder: () async => temp, pickFastest: false),
        ),
      ],
    );
    final download = find.byKey(
      const ValueKey('version-download-PureLive-9.0.0-${pubspecBuild + 1}-android-arm64-v8a-release.apk'),
    );
    await tester.ensureVisible(download);
    await tester.tap(download);
    // The download writes real files: let the IO run between frames.
    final install = find.byKey(const ValueKey('update-download-install'));
    for (var i = 0; i < 50 && install.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await tester.pump();
    }
    expect(install, findsOneWidget);
    final file = File('${temp.path}/PureLive-9.0.0-${pubspecBuild + 1}-android-arm64-v8a-release.apk');
    expect(file.lengthSync(), 3000);
    expect(http.urls.single, startsWith('https://cdn.gh-proxy.org/'));
    await tester.tap(find.byKey(const ValueKey('update-download-install')));
    await tester.pumpAndSettle();
    expect(opened, [file.path]);
    expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
  });

  testWidgets('shows the failure and checks again on retry', (tester) async {
    final feed = _FakeFeed();
    await _pump(tester, const VersionPage(route: RouteArgs(RoutePath.kVersionPage)), feed);
    expect(find.text('更新信息获取失败'), findsOneWidget);
    feed.info = const UpdateInfo(version: appVersion, buildNumber: pubspecBuild);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(feed.checks, 2);
    expect(find.byKey(const ValueKey('version-latest')), findsOneWidget);
    expect(find.text('本次检查未发现新版本'), findsOneWidget);
  });

  testWidgets('Y02.2: older metadata is not latest and offers no in-app downgrade', (tester) async {
    final feed = _FakeFeed(
      info: const UpdateInfo(version: '1.0.0', buildNumber: 99999),
      history: _historyWith9(),
    );
    await _pump(tester, const VersionPage(route: RouteArgs(RoutePath.kVersionPage)), feed);
    expect(find.byKey(const ValueKey('version-update-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('version-latest')), findsNothing);
    expect(find.byKey(const ValueKey('version-packages')), findsNothing);
    expect(foundUpdate.value, isNull);
  });

  testWidgets('Y02.2: the current build is not offered as an upgrade, including offline refresh', (tester) async {
    final feed = _FakeFeed(
      info: UpdateInfo(version: appVersion, buildNumber: appBuild),
      history: _historyWith9(),
    );
    await _pump(tester, const VersionPage(route: RouteArgs(RoutePath.kVersionPage)), feed);
    expect(find.text('本次检查未发现新版本'), findsOneWidget);
    expect(find.byKey(const ValueKey('version-packages')), findsNothing);
    feed.info = null;
    await tester.tap(find.byKey(const ValueKey('version-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('version-last-known')), findsOneWidget);
    expect(find.text('暂时无法确认更新，显示上次检查结果'), findsOneWidget);
    expect(find.text('本次检查未发现新版本'), findsNothing);
    expect(find.byKey(const ValueKey('version-packages')), findsNothing);
  });

  testWidgets('Y02.2: refresh disables old actions and a disposed check cannot publish its badge', (tester) async {
    final feed = _FakeFeed(info: _newer(), history: _historyWith9());
    await _pump(tester, const VersionPage(route: RouteArgs(RoutePath.kVersionPage)), feed);
    final pending = Completer<UpdateInfo?>();
    feed.latestGate = pending;
    await tester.tap(find.byKey(const ValueKey('version-refresh')));
    await tester.pump();
    final scroll = find.byKey(const ValueKey('version-update-scroll'));
    final blocker = find.ancestor(of: scroll, matching: find.byType(IgnorePointer)).first;
    expect(tester.widget<IgnorePointer>(blocker).ignoring, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    foundUpdate.value = null;
    pending.complete(const UpdateInfo(version: '10.0.0', buildNumber: 6000));
    await tester.pumpAndSettle();
    expect(foundUpdate.value, isNull);
  });

  testWidgets('Y02.2: a refresh never displays new metadata with old packages', (tester) async {
    final feed = _FakeFeed(info: _newer(), history: _historyWith9());
    await _pump(tester, const VersionPage(route: RouteArgs(RoutePath.kVersionPage)), feed);
    expect(find.byKey(const ValueKey('version-packages')), findsOneWidget);
    feed.info = const UpdateInfo(
      version: '10.0.0',
      buildNumber: 6000,
      releaseUrl: 'https://github.com/o/r/releases/tag/v10.0.0',
    );
    await tester.tap(find.byKey(const ValueKey('version-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本: v10.0.0'), findsOneWidget);
    expect(find.byKey(const ValueKey('version-packages')), findsNothing);
    expect(find.byKey(const ValueKey('version-open-release')), findsOneWidget);
    expect(foundUpdate.value?.version, '10.0.0');
  });

  testWidgets('the start-up check asks only for a newer version with the setting on', (tester) async {
    final feed = _FakeFeed(info: _newer());
    final (services, _) = await _pump(tester, const Scaffold(body: SizedBox()), feed);
    final context = tester.element(find.byType(SizedBox).first);
    final settings = services.store.settings;

    await tester.runAsync(() => settings.set(Settings.enableAutoCheckUpdate, false));
    await checkForUpdateOnStartup(context, settings: settings, feed: feed);
    expect(feed.checks, 0);

    await tester.runAsync(() => settings.set(Settings.enableAutoCheckUpdate, true));
    final shown = checkForUpdateOnStartup(context, settings: settings, feed: feed);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-version-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('new-version-update')));
    await tester.pumpAndSettle();
    await shown;
    expect(find.text('version page'), findsOneWidget);
  });

  testWidgets('about shows the version and leads to update and history', (tester) async {
    await _pump(tester, const AboutPage(route: RouteArgs(RoutePath.kAbout)), _FakeFeed());
    expect(find.text('v$appVersion'), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
    await tester.tap(find.text('在线更新'));
    await tester.pumpAndSettle();
    expect(find.text('version page'), findsOneWidget);
  });

  testWidgets('the release history lists releases and opens one', (tester) async {
    final feed = _FakeFeed(history: parseReleases(_releasesJson()));
    await _pump(tester, const AboutPage(route: RouteArgs(RoutePath.kVersionHistory)), feed);
    expect(find.byKey(const ValueKey('release-history-mobile-list')), findsOneWidget);
    // The list grows with every release: scroll until the oldest is built.
    final oldest = find.byKey(const ValueKey('release-history-mobile-3.2.11'));
    await tester.scrollUntilVisible(
      oldest,
      300,
      scrollable: find
          .descendant(of: find.byKey(const ValueKey('release-history-mobile-list')), matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(oldest);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('release-history-detail-scroll')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('release-history-detail-dialog')),
        matching: find.text('发布于 2026-09-27'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('release-history-close-details')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('release-history-detail-scroll')), findsNothing);
  });

  group('U.12b', () {
    testWidgets('about: no title, "关于" then "项目", 3.x icons, "版本历史", the statement (c2–c5)', (tester) async {
      await _pump(tester, const AboutPage(route: RouteArgs(RoutePath.kAbout)), _FakeFeed(), width: 393, height: 1000);
      // 3.x: only "back" in the app bar.
      expect(find.descendant(of: find.byType(AppBar), matching: find.byType(Text)), findsNothing);
      final order = ['在线更新', '版本历史', '开源许可证', '项目主页', '项目声明'];
      final tops = [for (final text in order) tester.getTopLeft(find.text(text)).dy];
      expect(tops, [...tops]..sort());
      expect(tester.getTopLeft(find.text('关于')).dy, lessThan(tops.first));
      expect(tester.getTopLeft(find.text('项目')).dy, lessThan(tops[3]));
      expect(find.text('历史记录'), findsNothing);
      expect(find.text(withoutOrphan('检查新版本并下载安装包')), findsOneWidget);
      Finder icon(String key, IconData data) =>
          find.descendant(of: find.byKey(ValueKey(key)), matching: find.byIcon(data));
      expect(icon('about-online-update', AppIcons.onlineUpdate), findsOneWidget);
      expect(icon('about-version-history', AppIcons.versionHistory), findsOneWidget);
      expect(icon('about-licenses', AppIcons.licenses), findsOneWidget);
      expect(icon('about-project-page', AppIcons.projectPage), findsOneWidget);
      expect(icon('about-project-page', AppIcons.openExternal), findsOneWidget);
      expect(icon('about-statement', AppIcons.infoLine), findsOneWidget);
      // c4: no Firebase, no red icon.
      expect(find.textContaining('Firebase'), findsNothing);
      final info = tester.widget<Icon>(icon('about-statement', AppIcons.infoLine));
      expect(info.color, isNot(Theme.of(tester.element(find.byType(AboutView))).colorScheme.error));
      // c3: no badge while nothing newer was found.
      expect(find.byKey(const ValueKey('about-new-version')), findsNothing);
      foundUpdate.value = _newer();
      await tester.pump();
      expect(find.text('新版本 v9.0.0'), findsOneWidget);
      // c5: no bounce: the logo is there at full size from the first frame.
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      expect(tester.getSize(find.byKey(const ValueKey('about-logo'))), const Size(80, 80));

      await tester.tap(find.text('版本历史'));
      await tester.pumpAndSettle();
      expect(find.text('history page'), findsOneWidget);
    });

    testWidgets('about on a landscape phone and a wide window: at most 720, centred', (tester) async {
      for (final (width, height) in const [(852.0, 393.0), (1280.0, 800.0)]) {
        await _pump(
          tester,
          const AboutPage(route: RouteArgs(RoutePath.kAbout)),
          _FakeFeed(),
          width: width,
          height: height,
        );
        final row = tester.getRect(find.byKey(const ValueKey('about-online-update')));
        expect(row.width, 720);
        expect(row.center.dx, width / 2);
      }
    });

    testWidgets('the start-up check and the version page tell the about page about a newer version', (tester) async {
      final feed = _FakeFeed(info: _newer(), history: _historyWith9());
      await _pump(tester, const VersionPage(route: RouteArgs(RoutePath.kVersionPage)), feed);
      expect(foundUpdate.value?.version, '9.0.0');
      feed.info = UpdateInfo.fromJson(_versionJson(), platform: 'android');
      await tester.tap(find.byKey(const ValueKey('version-refresh')));
      await tester.pumpAndSettle();
      expect(foundUpdate.value?.version, '9.0.0');
      expect(find.byKey(const ValueKey('version-last-known')), findsOneWidget);
    });

    testWidgets('packages: name · size, "本机", "下载并安装" on the right, sources folded (c7, c8)', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(
        tester,
        const VersionPage(route: RouteArgs(RoutePath.kVersionPage)),
        _FakeFeed(info: _newer(), history: _historyWith9()),
        width: 393,
        height: 1400,
        overrides: [nativePackageTitleProvider.overrideWithValue('arch_arm32')],
      );
      expect(find.text('下载文件 · Android'), findsOneWidget);
      const arm64 = 'PureLive-9.0.0-${pubspecBuild + 1}-android-arm64-v8a-release.apk';
      const arm32 = 'PureLive-9.0.0-${pubspecBuild + 1}-android-armeabi-v7a-release.apk';
      // Three packages in 3.x's order, each with its own button.
      final names = ['ARM64 (64位)', 'ARM32 (通用)', 'x86_64 (Arch)'];
      final tops = [for (final name in names) tester.getTopLeft(find.text(name)).dy];
      expect(tops, [...tops]..sort());
      expect(find.text('下载并安装'), findsNWidgets(3));
      final title = tester.getRect(find.text('ARM64 (64位)'));
      final install = tester.getRect(find.byKey(const ValueKey('version-download-$arm64')));
      expect(install.left, greaterThan(title.right));
      expect(install.height, greaterThanOrEqualTo(48));
      // "本机" only on this device's package.
      expect(find.byKey(const ValueKey('version-native-$arm32')), findsOneWidget);
      expect(find.byKey(const ValueKey('version-native-$arm64')), findsNothing);
      expect(find.text('本机'), findsOneWidget);
      // 18 mirrors and the address itself, folded.
      expect(find.text('选择下载源（18 个）'), findsNWidgets(3));
      expect(find.byKey(const ValueKey('version-source-$arm64-0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('version-sources-$arm64')));
      await tester.pumpAndSettle();
      expect(find.text('下载源 1'), findsOneWidget);
      expect(find.text('GitHub 官方源'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('version-source-$arm64-2')));
      await tester.pumpAndSettle();
      // The mirror's dialog: which package and mirror, the file, then the
      // three ways in order, "取消" at the bottom.
      expect(find.text('ARM64 (64位) · 下载源 3'), findsOneWidget);
      expect(find.text(arm64), findsOneWidget);
      final ways = [
        for (final key in ['version-source-download', 'version-source-browser', 'version-source-copy'])
          tester.getTopLeft(find.byKey(ValueKey(key))).dy,
      ];
      expect(ways, [...ways]..sort());
      expect(find.text('在应用内下载'), findsOneWidget);
      expect(find.text('在浏览器中下载'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('version-source-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('version-source-dialog')), findsNothing);
      expect(copied, isEmpty);
    });

    testWidgets('the version page is at most 720 wide on a wide window and a landscape phone', (tester) async {
      for (final (width, height) in const [(852.0, 393.0), (1280.0, 800.0)]) {
        await _pump(
          tester,
          const VersionPage(route: RouteArgs(RoutePath.kVersionPage)),
          _FakeFeed(info: _newer(), history: _historyWith9()),
          width: width,
          height: height,
        );
        final card = tester.getRect(find.byKey(const ValueKey('version-newer')));
        expect(card.width, 720);
        expect(card.center.dx, width / 2);
        expect(find.text('版本更新'), findsOneWidget);
      }
    });

    testWidgets('history: "版本历史", "最新" and "当前", no file size; close at the top right (c2, c11, c12)', (tester) async {
      await _pump(
        tester,
        const VersionPage(route: RouteArgs(RoutePath.kVersionHistory)),
        _FakeFeed(history: _historyWith9()),
        width: 393,
        height: 852,
      );
      expect(find.text('版本历史'), findsOneWidget);
      expect(find.byKey(const ValueKey('release-latest-9.0.0')), findsOneWidget);
      expect(find.byKey(const ValueKey('release-current-$appVersion')), findsOneWidget);
      expect(find.text('最新'), findsOneWidget);
      expect(find.text('当前'), findsOneWidget);
      expect(find.textContaining('文件大小'), findsNothing);
      expect(find.text('发布于 2027-01-01'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('release-history-mobile-9.0.0')));
      await tester.pumpAndSettle();
      // Close is above the scrolling content, at the end of the header row.
      final scroll = tester.getRect(find.byKey(const ValueKey('release-history-detail-scroll')));
      final close = tester.getRect(find.byKey(const ValueKey('release-history-close-details')));
      final page = tester.getRect(find.byKey(const ValueKey('release-history-open-release')));
      expect(close.bottom, lessThanOrEqualTo(scroll.top + 8));
      expect(close.right, greaterThan(scroll.right - 24));
      expect(page.right, lessThanOrEqualTo(close.left));
      expect(find.text('关闭'), findsNothing);
      // Esc closes it too.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('release-history-detail-dialog')), findsNothing);
    });

    for (final width in [420.0, 1280.0]) {
      testWidgets('ordinary history retains implicit scroll controller at $width', (tester) async {
        await _pump(
          tester,
          const VersionPage(route: RouteArgs(RoutePath.kVersionHistory)),
          _FakeFeed(history: _historyWith9()),
          width: width,
        );
        if (width == 420) {
          await tester.tap(find.byKey(const ValueKey('release-history-mobile-9.0.0')));
          await tester.pumpAndSettle();
        }
        final detail = width == 420
            ? find.byKey(const ValueKey('release-history-detail-dialog'))
            : find.byKey(const ValueKey('release-history-detail-9.0.0'));
        final scroll = tester.widget<SingleChildScrollView>(
          find.descendant(of: detail, matching: find.byType(SingleChildScrollView)),
        );
        expect(scroll.controller, isNull, reason: 'ordinary input must retain primary controller inheritance');
        expect(find.byType(KeyboardScrollArea), findsNothing);
      });
    }

    testWidgets('history splits by the width of the page at 840 (c10, N3 A)', (tester) async {
      await _pump(
        tester,
        const VersionPage(route: RouteArgs(RoutePath.kVersionHistory)),
        _FakeFeed(history: _historyWith9()),
        width: 839,
        height: 600,
      );
      expect(find.byKey(const ValueKey('release-history-mobile-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('release-history-desktop-layout')), findsNothing);
      await _pump(
        tester,
        const VersionPage(route: RouteArgs(RoutePath.kVersionHistory)),
        _FakeFeed(history: _historyWith9()),
        width: 852,
        height: 393,
      );
      expect(find.byKey(const ValueKey('release-history-desktop-layout')), findsOneWidget);
    });

    testWidgets('a file: copy, and download after saying what and what next (c13)', (tester) async {
      await _pump(
        tester,
        const VersionPage(route: RouteArgs(RoutePath.kVersionHistory)),
        _FakeFeed(history: _historyWith9()),
        width: 1280,
        height: 800,
      );
      final file = find.byKey(const ValueKey('release-history-file-0'));
      final copy = tester.getRect(find.descendant(of: file, matching: find.byKey(const ValueKey('release-file-copy'))));
      final download = find.descendant(of: file, matching: find.byKey(const ValueKey('release-file-download')));
      expect(tester.getRect(download).left, greaterThan(copy.right));
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(find.text('下载安装包'), findsOneWidget);
      expect(
        find.text('是否下载“PureLive-9.0.0-${pubspecBuild + 1}-android-arm64-v8a-release.apk”（100mb）？下载完成后会打开安装。'),
        findsOneWidget,
      );
      final cancel = tester.getRect(find.byKey(const ValueKey('release-download-cancel')));
      final start = tester.getRect(find.byKey(const ValueKey('release-download-start')));
      expect(cancel.right, lessThan(start.left));
      expect(
        find.descendant(of: find.byKey(const ValueKey('release-download-start')), matching: find.text('下载')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('release-download-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('release-download-confirm')), findsNothing);
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
    });
  });

  test("this device's package follows the app's architecture", () {
    expect(nativePackageTitle(Abi.androidArm64), 'arch_arm64');
    expect(nativePackageTitle(Abi.androidArm), 'arch_arm32');
    expect(nativePackageTitle(Abi.androidX64), 'arch_x86_64');
    expect(nativePackageTitle(Abi.windowsX64), 'exe_installer');
    expect(nativePackageTitle(Abi.macosArm64), 'macos_package');
    expect(nativePackageTitle(Abi.linuxX64), 'linux_package'); // X02.1
    expect(nativePackageTitle(Abi.linuxArm64), isNull);
  });

  testWidgets('A01.2: the history and about follow the font settings, the same size by default', (tester) async {
    double size(Finder finder) => tester.renderObject<RenderParagraph>(finder).text.style!.fontSize!;
    final version = find.descendant(
      of: find.byKey(const ValueKey('release-history-mobile-9.0.0')),
      matching: find.text('v9.0.0'),
    );
    const page = VersionPage(route: RouteArgs(RoutePath.kVersionHistory));
    await _pump(tester, page, _FakeFeed(history: _historyWith9()), width: 393, height: 852);
    expect(size(find.text('版本历史')), 20);
    expect(size(version), 17);
    await _pump(tester, const AboutPage(route: RouteArgs(RoutePath.kAbout)), _FakeFeed());
    expect(size(find.text('纯粹直播')), 20);

    // Every size at its largest (Settings.fontSize*).
    const largest = LiveFontSizes(bodySmall: 15, bodyMedium: 17, bodyLarge: 18, titleMedium: 20, titleLarge: 26);
    await _pump(tester, page, _FakeFeed(history: _historyWith9()), width: 393, height: 852, fontSizes: largest);
    expect(size(find.text('版本历史')), 26);
    expect(size(version), closeTo(20 * 17 / 15, 1e-9));
    expect(tester.takeException(), isNull);
    await _pump(tester, const AboutPage(route: RouteArgs(RoutePath.kAbout)), _FakeFeed(), fontSizes: largest);
    expect(size(find.text('纯粹直播')), 26);
  });

  testWidgets('the release history shows both panes on a wide window', (tester) async {
    final feed = _FakeFeed(history: parseReleases(_releasesJson()));
    await _pump(tester, const AboutPage(route: RouteArgs(RoutePath.kVersionHistory)), feed, width: 1200);
    expect(find.byKey(const ValueKey('release-history-desktop-layout')), findsOneWidget);
    // The newest release is open first.
    expect(find.byKey(ValueKey('release-history-detail-${feed.history!.first.version}')), findsOneWidget);
    // The list grows with every release: scroll until the oldest is built.
    final oldest = find.byKey(const ValueKey('release-history-desktop-3.2.11'));
    await tester.scrollUntilVisible(
      oldest,
      300,
      scrollable: find
          .descendant(of: find.byKey(const ValueKey('release-history-desktop-list')), matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(oldest);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('release-history-detail-3.2.11')), findsOneWidget);
  });
}

/// Answers every URL with [bytes].
final class _BytesHttp implements LiveHttp {
  new(this.bytes);

  final List<int> bytes;
  final List<String> urls = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async => await (await open(request)).collect();

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    urls.add(request.url.toString());
    return LiveStreamedResponse(
      status: 200,
      body: Stream.fromIterable([bytes.sublist(0, 1000), bytes.sublist(1000)]),
      url: request.url,
      contentLength: bytes.length,
    );
  }

  @override
  void close() {}
}
