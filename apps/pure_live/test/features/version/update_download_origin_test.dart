import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/downloads.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/features/version/update_download.dart';
import 'package:pure_live/features/version/update_feed.dart';

import '../../support.dart';

/// Uses only the pre-Y02.3 public API so the old six-mirror cap fails behaviorally.
final class _OriginOnlyHttp implements LiveHttp {
  final List<Uri> opened = [];

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    opened.add(request.url);
    final origin = request.url.host == 'github.com';
    return LiveStreamedResponse(
      status: origin ? 200 : 503,
      body: Stream.value(origin ? [1, 2, 3] : <int>[]),
      contentLength: origin ? 3 : 0,
      url: request.url,
    );
  }

  @override
  Future<LiveResponse> send(LiveRequest request) async => await (await open(request)).collect();

  @override
  void close() {}
}

void main() {
  testWidgets('Y02.3: failed mirrors still reach canonical origin within six sources', (tester) async {
    final folder = Directory.systemTemp.createTempSync('update_origin_');
    addTearDown(() => folder.deleteSync(recursive: true));
    final strings = (await tester.runAsync(loadStrings))!;
    final http = _OriginOnlyHttp();
    final name = 'PureLive-9.0.0-${appBuild + 1}-android-arm64-v8a-release.apk';
    final file = ReleaseFile.fromJson({
      'name': name,
      'size': '3 bytes',
      'downloads': 0,
      'url': 'https://github.com/wzgrx/PureLive/releases/download/v9.0.0/$name',
      'size_bytes': 3,
      'sha256': '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateDownloadToolsProvider.overrideWithValue(
            UpdateDownloadTools(downloader: FileDownloader(http), folder: () async => folder, pickFastest: false),
          ),
        ],
        child: LiveUiScope(
          config: LiveUiConfig(strings: strings.ui),
          child: MaterialApp(
            theme: const LiveTheme(primaryColor: Colors.blue).light,
            home: const Scaffold(body: Text('home')),
          ),
        ),
      ),
    );
    var completed = false;
    Future<void>? closed;
    addTearDown(() async {
      final publicClose = closed;
      if (completed || publicClose == null) return;
      for (var i = 0; i < 20 && !completed; i++) {
        tester.state<NavigatorState>(find.byType(Navigator)).popUntil((route) => route.isFirst);
        await tester.pumpAndSettle();
        if (!completed) await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      }
      expect(completed, isTrue, reason: 'the real dialog route must close before test teardown');
      await publicClose;
    });
    // Start the public operation and actual dialog creation frame in real I/O.
    // Await setup only; the separately tracked public future ends on dismissal.
    await tester.runAsync(() async {
      closed = showUpdateDownload(
        tester.element(find.text('home')),
        file: file,
        sources: downloadSources(file.url, githubOrigin: false),
        update: UpdateInfo(version: '9.0.0', buildNumber: appBuild + 1),
      ).whenComplete(() => completed = true);
      await Future<void>.delayed(const Duration(seconds: 1));
      await tester.pump();
    });
    final install = find.byKey(const ValueKey('update-download-install'));
    for (var i = 0; i < 20 && install.evaluate().isEmpty; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(seconds: 1));
        await tester.pump();
      });
      if (find.byKey(const ValueKey('update-download-retry')).evaluate().isNotEmpty) break;
    }
    expect(http.opened.map((url) => url.host), contains('github.com'));
    expect(http.opened.toSet(), hasLength(6));
    expect(http.opened.last, Uri.parse(file.url));
    expect(install, findsOneWidget);
    expect(File('${folder.path}/$name').readAsBytesSync(), [1, 2, 3]);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('update-download-close')));
      await tester.pumpAndSettle();
    });
    expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
    expect(completed, isTrue);
  });
}
