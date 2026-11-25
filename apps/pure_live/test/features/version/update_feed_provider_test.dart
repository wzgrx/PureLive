// Provider regressions use APIs available before Y02.2, including the actual
// settings stream; no duplicate implementation of source-policy selection.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/bootstrap.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/features/version/version_page.dart';

import '../../support.dart';

final class _Http implements LiveHttp {
  new(this.respond);

  final Future<Object?> Function(LiveRequest request) respond;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    final value = await respond(request);
    return LiveResponse(status: value == null ? 404 : 200, bytes: utf8.encode(jsonEncode(value)), url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

Map<String, Object?> _current() => {'version': appVersion, 'build_number': appBuild};

Future<AppServices> _services(LiveHttp http) async {
  final cipher = FakeCipher();
  final store = await LiveStore.memory(cipher: cipher);
  return AppBootstrap.wire(
    store: store,
    cipher: cipher,
    launch: const LaunchArgs(),
    dataRoot: Directory.systemTemp,
    http: http,
    background: false,
  );
}

Future<AppServices> _pump(WidgetTester tester, LiveHttp http) async {
  final services = (await tester.runAsync(() => _services(http)))!;
  final strings = (await tester.runAsync(loadStrings))!;
  addTearDown(() => tester.runAsync(services.close));
  addTearDown(() => foundUpdate.value = null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          home: const UpdateView(),
        ),
      ),
    ),
  );
  return services;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('origin policy changes affect the next check, but unchanged initial emission preserves the feed', () async {
    final http = _Http((_) async => _current());
    final services = await _services(http);
    addTearDown(services.close);
    final container = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(services)]);
    addTearDown(container.dispose);
    final subscription = container.listen(updateFeedProvider, (_, _) {});
    addTearDown(subscription.close);
    final first = container.read(updateFeedProvider);
    await pumpEventQueue();
    expect(container.read(updateFeedProvider), same(first));
    await first.latest();
    // raceFirst schedules each source on the event queue in the baseline.
    await pumpEventQueue();
    expect(http.requests.any((request) => request.url.host != 'raw.githubusercontent.com'), isTrue);
    await services.store.settings.set(Settings.useGitHubOriginForUpdates, true);
    await pumpEventQueue();
    final origin = container.read(updateFeedProvider);
    expect(origin, isNot(same(first)));
    http.requests.clear();
    await origin.latest();
    expect(http.requests, hasLength(1));
    expect(http.requests.single.url.host, 'raw.githubusercontent.com');
    await services.store.settings.set(Settings.useGitHubOriginForUpdates, true);
    await pumpEventQueue();
    expect(container.read(updateFeedProvider), same(origin));
  });

  test('an old source-policy response cannot be returned after the provider is replaced', () async {
    final delayed = Completer<Object?>();
    var waiting = true;
    final http = _Http((_) async => waiting ? await delayed.future : _current());
    final services = await _services(http);
    addTearDown(services.close);
    final container = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(services)]);
    addTearDown(container.dispose);
    final subscription = container.listen(updateFeedProvider, (_, _) {});
    addTearDown(subscription.close);
    final old = container.read(updateFeedProvider).latest();
    await pumpEventQueue();
    await services.store.settings.set(Settings.useGitHubOriginForUpdates, true);
    await pumpEventQueue();
    waiting = false;
    expect((await container.read(updateFeedProvider).latest())?.version, appVersion);
    delayed.complete({'version': '99.0.0', 'build_number': 9999});
    expect(await old, isNull);
  });

  testWidgets('an offline origin-only refresh labels the previous mirror snapshot last-known', (tester) async {
    var offline = false;
    final http = _Http((_) async => offline ? null : _current());
    final services = await _pump(tester, http);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('version-latest')), findsOneWidget);
    offline = true;
    await tester.runAsync(() => services.store.settings.set(Settings.useGitHubOriginForUpdates, true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('version-last-known')), findsOneWidget);
    http.requests.clear();
    await tester.tap(find.byKey(const ValueKey('version-refresh')));
    await tester.pumpAndSettle();
    expect(http.requests, hasLength(1));
    expect(http.requests.single.url.host, 'raw.githubusercontent.com');
    expect(find.byKey(const ValueKey('version-last-known')), findsOneWidget);
    expect(find.byKey(const ValueKey('version-latest')), findsNothing);
  });

  testWidgets('late mirror metadata cannot overwrite the page or badge after an origin-only check', (tester) async {
    final delayed = Completer<Object?>();
    var waiting = true;
    final http = _Http((_) async => waiting ? await delayed.future : _current());
    final services = await _pump(tester, http);
    await tester.pump();
    expect(http.requests, isNotEmpty);
    await tester.runAsync(() => services.store.settings.set(Settings.useGitHubOriginForUpdates, true));
    await tester.pump();
    waiting = false;
    await tester.tap(find.byKey(const ValueKey('version-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('version-latest')), findsOneWidget);
    delayed.complete({'version': '99.0.0', 'build_number': 9999});
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('version-latest')), findsOneWidget);
    expect(find.textContaining('99.0.0'), findsNothing);
    expect(foundUpdate.value, isNull);
  });
}
