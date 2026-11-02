import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/iptv_library.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/app/ui_mode.dart';
import 'package:pure_live/features/home/home_page.dart';
import 'package:pure_live/features/iptv/iptv_data.dart';
import 'package:pure_live/features/iptv/iptv_page.dart';
import 'package:pure_live/features/live_play/logic/predictive_back.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/remote_receiver/remote_receiver_page.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_service.dart';
import 'package:pure_live/features/settings/settings_catalog.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/rooms/share_code.dart';
import 'package:pure_live/tv/home/tv_home_page.dart';
import 'package:pure_live/tv/pages/tv_favorites_pane.dart';
import 'package:pure_live/tv/pages/tv_history_pane.dart';
import 'package:pure_live/tv/room/tv_live_play_page.dart';
import 'package:pure_live/tv/settings/tv_settings_catalog.dart';
import 'package:pure_live/tv/settings/tv_settings_section_page.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';
import 'package:pure_live/tv/widgets/tv_qr_panel.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';
import 'package:pure_live/tv/widgets/tv_room_row.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

import '../features/live_play/live_play_support.dart';
import '../qa_capture.dart';
import '../support.dart';

final class _LayoutOnlySync extends RemoteSyncService {
  new(super.store);
  @override
  Future<void> start() async {}
}

final class _LocalHttp extends HttpOverrides;

/// A platform with [count] recommended rooms that all play.
final class _TvSite extends LiveSite {
  new(this.count, {this.offline = const {}, this.singleQuality = false});

  final bool singleQuality;

  final int count;

  /// Rooms off air.
  final Set<int> offline;

  @override
  String get id => SiteIds.bilibili;

  @override
  String get name => '哔哩哔哩';

  LiveRoom room(int n) => LiveRoom(
    platform: SiteIds.bilibili,
    roomId: '$n',
    title: '直播 $n',
    nick: '主播$n',
    popularity: '${1000 - n}',
    audienceMetricType: AudienceMetricType.popularity,
    liveStatus: offline.contains(n) ? LiveStatus.offline : LiveStatus.live,
  );

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      page == 1 ? [for (var n = 0; n < count; n++) room(n)] : const [];

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async => room(int.parse(roomId));

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async => [
    if (page == 1)
      for (var n = 0; n < count; n++)
        if (room(n).title.contains(keyword)) room(n),
  ];

  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async => [
    if (page == 1)
      for (var n = 0; n < count; n++)
        if (room(n).title.contains(keyword))
          LiveAnchorItem(roomId: '$n', avatar: '', userName: '主播$n', liveStatus: n.isOdd),
  ];

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => [
    const LivePlayQuality(quality: '原画', id: 10000),
    if (!singleQuality) const LivePlayQuality(quality: '流畅', id: 80),
  ];

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    'https://a.example/${detail.roomId}/${quality.id}.flv',
  ];
}

/// A second followed platform without network calls.
final class _ExtraTvSite extends LiveSite {
  new(this.id, this.rooms);

  @override
  final String id;

  @override
  String get name => id;

  final List<LiveRoom> rooms;

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async => rooms.firstWhere((room) => room.roomId == roomId);
}

final class _DelayedIptv extends LiveSite {
  final ready = Completer<List<LiveRoom>>();
  @override
  String get id => SiteIds.iptv;
  @override
  String get name => '本地测试';
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) => ready.future;
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async => [];
}

Future<void> _openMenuWithRemote(WidgetTester tester, String pane) async {
  for (var i = 0; i < 15 && _focused != 'tv menu $pane'; i++) {
    await _press(tester, LogicalKeyboardKey.arrowDown);
  }
  expect(_focused, 'tv menu $pane');
  await _press(tester, LogicalKeyboardKey.select);
}

Future<void> _expectVisibleControlsReachable(WidgetTester tester, String pane) async {
  final root = find.byKey(ValueKey('tv-pane-$pane'));
  final bounds = tester.getRect(root);
  final expected = <FocusNode>{};
  for (final widget in tester.widgetList<Focus>(find.descendant(of: root, matching: find.byType(Focus)))) {
    final node = widget.focusNode;
    if (node != null &&
        node.canRequestFocus &&
        !node.skipTraversal &&
        node.context != null &&
        node.rect.overlaps(bounds) &&
        !node.rect.isEmpty) {
      expected.add(node);
    }
  }
  final initial = FocusManager.instance.primaryFocus!;
  final queue = <FocusNode>[initial];
  final reached = <FocusNode>{initial};
  for (var cursor = 0; cursor < queue.length && cursor < 100; cursor++) {
    final from = queue[cursor];
    if (from.context == null || !from.canRequestFocus) continue;
    for (final key in [
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ]) {
      from.requestFocus(); // Replay a previously reached vertex, not an unreachable control.
      await tester.pump(const Duration(seconds: 1));
      await _press(tester, key);
      final next = FocusManager.instance.primaryFocus;
      if (next != null && !next.debugLabel.toString().startsWith('tv menu') && reached.add(next)) {
        queue.add(next);
      }
    }
  }
  final unreachable = expected.where((node) => node.context != null && !reached.contains(node)).toList();
  expect(
    unreachable.map((node) => node.debugLabel),
    isEmpty,
    reason: '$pane: every initially visible enabled control must have a D-pad path from the real entry',
  );
}

bool _buttonFocused(WidgetTester tester, String text) => Focus.of(tester.element(find.text(text))).hasFocus;

final List<String> _toasts = [];
final GlobalKey _menuFrame = GlobalKey();

/// The app on a 1080p panel in [mode] (`uiMode`), on a device that is
/// [television] or not.
Future<AppServices> _pumpApp(
  WidgetTester tester, {
  String mode = 'tv',
  bool television = false,
  int rooms = 10,
  bool noticeAccepted = true,
  bool recordingEnabled = false,
  bool iptvEnabled = false,
  List<int> follows = const [],
  Set<int> offline = const {},
  List<LiveSite> extraSites = const [],
  List<LiveRoom> extraFollows = const [],
  bool taggedFollows = false,
  bool singleQuality = false,
  Stream<IptvOverview>? iptvOverview,
  Stream<List<LiveRoom>>? history,
  Size viewport = const Size(1920, 1080),
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = viewport
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final base = (await tester.runAsync(testServices))!;
  await tester.runAsync(() async {
    final settings = base.store.settings;
    await settings.set(Settings.showSplashPage, false);
    await settings.set(Settings.enableAutoCheckUpdate, false);
    await settings.set(Settings.hotAreasList, [
      SiteIds.bilibili,
      if (iptvEnabled) SiteIds.iptv,
      for (final site in extraSites) site.id,
    ]);
    await settings.set(Settings.uiMode, mode);
    await settings.set(Settings.language, '简体中文');
    await settings.set(Settings.textScaleFactor, textScale);
    if (noticeAccepted) await base.store.meta.set(TvHomePage.noticeKey, '1');
  });
  final site = _TvSite(rooms, offline: offline, singleQuality: singleQuality);
  await tester.runAsync(() async {
    final rooms = [for (final n in follows) site.room(n), ...extraFollows];
    for (final room in rooms) {
      await base.store.follows.add(room);
    }
    if (taggedFollows) {
      final tag = (await base.store.tags.add('回归分组'))!;
      for (final room in rooms) {
        await base.store.tags.setTagsOf(room, [tag.id]);
      }
    }
  });
  final iptvDirectory = iptvEnabled ? Directory.systemTemp.createTempSync('pure_live_tv_iptv_') : null;
  if (iptvDirectory != null) addTearDown(() => iptvDirectory.deleteSync(recursive: true));
  final services = AppServices(
    store: base.store,
    cipher: base.cipher,
    http: base.http,
    proxy: base.proxy,
    cookies: base.cookies,
    sites: SiteRegistry({SiteIds.bilibili: () => site, for (final extra in extraSites) extra.id: () => extra}),
    danmaku: base.danmaku,
    launch: base.launch,
    dataRoot: base.dataRoot,
    followsReady: base.followsReady,
    mediaOpener: base.mediaOpener,
    iptvImporter: iptvDirectory == null
        ? null
        : IptvImporter(
            library: StoreIptvLibrary(base.store),
            http: NoNetworkHttp(),
            playlistDirectory: iptvDirectory,
            selectedGuideSourceId: () => base.store.settings.get(Settings.selectedSourceId),
          ),
    recording: recordingEnabled
        ? buildAppRecording(store: base.store, sites: base.sites, proxy: base.proxy, dataRoot: base.dataRoot)
        : null,
  );
  final strings = (await tester.runAsync(loadStrings))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        remoteSyncServiceProvider.overrideWithValue(() => _LayoutOnlySync(services.store)),
        if (history != null) tvHistoryProvider.overrideWith((ref) => history),
        if (iptvOverview != null) iptvOverviewProvider.overrideWith((ref) => iptvOverview),
        televisionDeviceProvider.overrideWithValue(television),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
      ],
      child: RepaintBoundary(
        key: _menuFrame,
        child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
      ),
    ),
  );
  await _settle(tester);
  AppNavigator.toast = _toasts.add;
  return services;
}

/// Lets the store and the fakes answer (real time) and the frames run.
Future<void> _settle(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(services.close);
}

/// Presses [key] (down and up) and lets the app follow.
Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await _settle(tester, rounds: 2);
}

String? get _focused => FocusManager.instance.primaryFocus?.debugLabel;

void main() {
  for (final id in ['live', 'replay', 'offline']) {
    for (final viewport in [const Size(1280, 720), const Size(1920, 1080)]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('issue141 app remote: empty favorite $id enters search and returns $viewport scale=$scale', (
          tester,
        ) async {
          final services = await _pumpApp(tester, viewport: viewport, textScale: scale);
          addTearDown(() => _close(tester, services));
          await _press(tester, LogicalKeyboardKey.arrowRight);
          for (var i = 0; i < ['live', 'replay', 'offline'].indexOf(id); i++) {
            await _press(tester, LogicalKeyboardKey.arrowRight);
          }
          expect(_focused, 'tab $id');
          await _press(tester, LogicalKeyboardKey.arrowDown);
          expect(_buttonFocused(tester, '搜索直播'), isTrue);
          await _press(tester, LogicalKeyboardKey.arrowUp);
          expect(_focused, 'tab $id');
        });
      }
    }
  }

  testWidgets('issue142 cold history entry follows asynchronous data instead of one frame', (tester) async {
    final ready = Completer<List<LiveRoom>>();
    final services = await _pumpApp(tester, history: Stream.fromFuture(ready.future));
    addTearDown(() => _close(tester, services));
    await _openMenuWithRemote(tester, 'history');
    ready.complete([_TvSite(1).room(0).copyWith(lastWatchedAt: DateTime.now().millisecondsSinceEpoch)]);
    await _settle(tester);
    expect(_buttonFocused(tester, '刷新'), isTrue, reason: 'first entry completes when content is mounted');
  });

  testWidgets('issue142 history visits actions then filters then cards with reversible vertical edges', (tester) async {
    final room = _TvSite(1).room(0).copyWith(lastWatchedAt: DateTime.now().millisecondsSinceEpoch);
    final services = await _pumpApp(tester, history: Stream.value([room]));
    addTearDown(() => _close(tester, services));
    await _openMenuWithRemote(tester, 'history');
    await _settle(tester);
    // Warm entry avoids depending on the separately covered asynchronous handoff.
    if (_focused == 'tv menu history') await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'tab all-days', reason: 'actions Down cannot skip the date filters');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, 'tab today');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, 'tab today', reason: 'row end must not jump diagonally into the actions');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_buttonFocused(tester, '刷新'), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 0');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tab today');
  });

  testWidgets('issue142 cold IPTV handoff and every channel row return to the playlist column', (tester) async {
    final site = _DelayedIptv();
    final services = await _pumpApp(tester, extraSites: [site]);
    addTearDown(() => _close(tester, services));
    await _openMenuWithRemote(tester, 'iptv');
    site.ready.complete([
      for (var i = 0; i < 12; i++) LiveRoom(platform: SiteIds.iptv, roomId: 'test-$i', title: '频道$i'),
    ]);
    await _settle(tester);
    expect(_focused, 'playlist hot');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    for (var row = 0; row < 3; row++) {
      if (row > 0) await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focused, 'cell ${row * 4}');
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(_focused, 'playlist hot', reason: 'row $row must share the playlist boundary');
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_focused, 'cell ${row * 4}', reason: 'the playlist restores the last channel');
    }
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'iptv manage');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'iptv manage', reason: 'bottom edge cannot enter the home rail');
  });

  testWidgets('pending content never steals focus after the user moved to another menu item', (tester) async {
    final ready = Completer<List<LiveRoom>>();
    final services = await _pumpApp(tester, history: Stream.fromFuture(ready.future));
    addTearDown(() => _close(tester, services));
    await _openMenuWithRemote(tester, 'history');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    final selected = _focused;
    ready.complete([_TvSite(1).room(0)]);
    await _settle(tester);
    expect(_focused, selected);
  });

  testWidgets('pending content cannot take focus from a covering dialog', (tester) async {
    final ready = Completer<List<LiveRoom>>();
    final services = await _pumpApp(tester, history: Stream.fromFuture(ready.future));
    addTearDown(() => _close(tester, services));
    await _openMenuWithRemote(tester, 'history');
    final context = tester.element(find.byType(TvHomePage));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('覆盖页面')),
      ),
    );
    await _settle(tester);
    final before = FocusManager.instance.primaryFocus;
    ready.complete([_TvSite(1).room(0)]);
    await _settle(tester);
    expect(FocusManager.instance.primaryFocus, same(before));
    expect(find.text('覆盖页面'), findsOneWidget);
    Navigator.of(context).pop();
    await _settle(tester);
  });

  testWidgets('late completion from a previous destination cannot interrupt the current destination', (tester) async {
    final ready = Completer<List<LiveRoom>>();
    final services = await _pumpApp(tester, history: Stream.fromFuture(ready.future));
    addTearDown(() => _close(tester, services));
    await _openMenuWithRemote(tester, 'history');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.select);
    final before = FocusManager.instance.primaryFocus;
    ready.complete([_TvSite(1).room(0)]);
    await _settle(tester);
    expect(FocusManager.instance.primaryFocus, same(before));
  });

  testWidgets('TV graph: empty favorites, populated history and IPTV expose all visible controls to D-pad', (
    tester,
  ) async {
    final site = _DelayedIptv();
    final rooms = [
      for (var i = 0; i < 8; i++) _TvSite(8).room(i).copyWith(lastWatchedAt: DateTime.now().millisecondsSinceEpoch),
    ];
    final services = await _pumpApp(tester, extraSites: [site], history: Stream.value(rooms));
    addTearDown(() => _close(tester, services));
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _expectVisibleControlsReachable(tester, 'favorites');
    // Return through the rail and enter each next destination using the actual menu.
    final scope = TvHomeScope.maybeOf(tester.element(find.byType(TvFavoritesPane)))!;
    scope.host.focusMenu();
    await _settle(tester);
    await _openMenuWithRemote(tester, 'history');
    await _settle(tester);
    await _expectVisibleControlsReachable(tester, 'history');
    scope.host.focusMenu();
    await _settle(tester);
    await _openMenuWithRemote(tester, 'iptv');
    site.ready.complete([
      for (var i = 0; i < 8; i++) LiveRoom(platform: SiteIds.iptv, roomId: 'graph-$i', title: '频道$i'),
    ]);
    await _settle(tester);
    await _expectVisibleControlsReachable(tester, 'iptv');
  });

  for (final pane in ['history', 'iptv']) {
    testWidgets('return to lower rail destination keeps its focus ring inside the expanded viewport: $pane', (
      tester,
    ) async {
      final site = _DelayedIptv();
      site.ready.complete([LiveRoom(platform: SiteIds.iptv, roomId: 'visibility', title: '测试频道')]);
      final services = await _pumpApp(
        tester,
        viewport: const Size(1280, 720),
        history: Stream.value([_TvSite(1).room(0)]),
        extraSites: [site],
      );
      addTearDown(() => _close(tester, services));
      await _openMenuWithRemote(tester, pane);
      await _settle(tester);
      await _press(tester, LogicalKeyboardKey.escape);
      expect(_focused, 'tv menu $pane');
      await tester.pump(const Duration(seconds: 1));
      final item = find.byKey(ValueKey('tv-menu-$pane'));
      final viewport = tester.getRect(find.ancestor(of: item, matching: find.byType(ClipRect)).first);
      final ring = find
          .descendant(
            of: item,
            matching: find.byWidgetPredicate(
              (widget) => widget is DecoratedBox && widget.position == DecorationPosition.foreground,
            ),
          )
          .first;
      final rect = tester.getRect(ring);
      expect(rect.top, greaterThanOrEqualTo(viewport.top));
      expect(
        rect.bottom,
        lessThanOrEqualTo(viewport.bottom),
        reason: 'logical focus must stay visibly inside the expanded menu after the clock changes its height',
      );
    });
  }

  testWidgets('hidden kept-alive destinations cannot receive directional focus', (tester) async {
    final ready = Completer<List<LiveRoom>>();
    final services = await _pumpApp(tester, history: Stream.fromFuture(ready.future));
    addTearDown(() => _close(tester, services));
    final node = tester.widget<TvFocusable>(find.byKey(const ValueKey('tv-tab-live'))).focusNode!;
    await _openMenuWithRemote(tester, 'history');
    expect(node.canRequestFocus, isFalse, reason: 'IndexedStack retains widgets, not their input eligibility');
    ready.complete([]);
    await _settle(tester);
  });

  testWidgets('issue112 one quality remains focusable and Right advances from its initial focus', (tester) async {
    final services = await _pumpApp(tester, singleQuality: true);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    final page = tester.state<TvLivePlayPageState>(find.byType(TvLivePlayPage));
    expect(page.controller!.qualities, hasLength(1));
    final session = page.controller!.session;
    await _press(tester, LogicalKeyboardKey.select);
    final quality = tester.widget<TvButton>(find.byKey(const ValueKey('tv-room-quality')));
    expect(quality.onTap, isNotNull, reason: 'one option is still a navigable control');
    expect(_focused, 'tv room first control');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, isNot('tv room first control'));
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused, 'tv room first control');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('原画'), findsWidgets);
    await _press(tester, LogicalKeyboardKey.select);
    expect(page.controller!.session, same(session));
    await _close(tester, services);
  });

  testWidgets('issue #68: TV automatically leaves an offline room for an online follow', (tester) async {
    final services = await _pumpApp(tester, follows: [1, 2], offline: {1});
    await tester.runAsync(() => services.store.settings.set(Settings.autoSwitchLiveFollows, true));
    unawaited(AppNavigator.toNamed<void>(RoutePath.kLivePlay, arguments: _TvSite(3).room(1)));
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    final page = tester.state<TvLivePlayPageState>(find.byType(TvLivePlayPage));
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(seconds: 21));
      await _settle(tester);
    }
    expect(page.controller!.room.roomId, '2');
    expect(page.controller!.stage, RoomStage.playing);
    expect(find.byKey(const ValueKey('tv-room-banner')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester, services);
  });

  for (final size in [const Size(1920, 1080), const Size(869, 400)]) {
    testWidgets('K90 IPTV first load keeps a visible actionable focus at $size', (tester) async {
      final highlightStrategy = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      addTearDown(() => FocusManager.instance.highlightStrategy = highlightStrategy);

      final overview = StreamController<IptvOverview>.broadcast();
      final services = await _pumpApp(tester, iptvEnabled: true, iptvOverview: overview.stream);
      addTearDown(() async {
        await _close(tester, services);
        await overview.close();
      });
      tester.view.physicalSize = size;
      await tester.runAsync(() => services.store.meta.set(defaultGuideMetaKey, '1'));
      unawaited(AppNavigator.toNamed<void>(RoutePath.kIptv));
      await _settle(tester, rounds: 8);
      await tester.pump(const Duration(seconds: 1));
      overview.add(
        const IptvOverview(
          playlists: [
            (
              playlist: IptvPlaylist(
                id: 'fixture',
                name: 'Synthetic playlist',
                format: IptvPlaylistFormat.m3u,
                source: 'https://example.invalid/one.m3u',
              ),
              channels: 1,
            ),
            (
              playlist: IptvPlaylist(
                id: IptvPlaylist.hotId,
                name: 'hot',
                format: IptvPlaylistFormat.m3u,
                source: 'https://example.invalid/hot.m3u',
              ),
              channels: 149,
            ),
          ],
          guides: [
            (
              source: EpgSource(id: 'guide', name: 'Synthetic guide', source: 'https://example.invalid/guide.xml'),
              channels: 150,
            ),
          ],
        ),
      );
      await _settle(tester, rounds: 8);
      final first = FocusManager.instance.primaryFocus!;
      var onImport = false;
      first.context?.visitAncestorElements((element) {
        onImport |= element.widget.key == const ValueKey('iptv-import-playlist');
        return !onImport;
      });
      expect(
        onImport,
        isTrue,
        reason: 'loaded IPTV must focus its import row, not an old row or invisible scope: $first',
      );
      final viewport = tester.getRect(find.byKey(const ValueKey('iptv-scroll')));
      final stats = tester.getRect(find.byKey(const ValueKey('iptv-stats')));
      expect(
        stats.bottom,
        lessThanOrEqualTo(viewport.top),
        reason: 'issue #69: TV overview stays outside focus-driven scrolling',
      );

      expect(first.rect.top, greaterThanOrEqualTo(viewport.top));
      expect(first.rect.bottom, lessThanOrEqualTo(viewport.bottom));
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final second = FocusManager.instance.primaryFocus!;
      expect(second, isNot(same(first)), reason: 'Down must advance from the import row');
      expect(second.rect.top, greaterThanOrEqualTo(viewport.top));
      expect(second.rect.bottom, lessThanOrEqualTo(viewport.bottom));
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final more = find.byKey(const ValueKey('iptv-more-fixture'));
      final material = tester.widget<Material>(find.descendant(of: more, matching: find.byType(Material)).first);
      expect(
        (material.shape! as OutlinedBorder).side,
        const BorderSide(color: TvColors.focusRing, width: 2),
        reason: 'the actual nested TV route must retain the standard button focus theme',
      );
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus, same(second));
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus, same(first));
      expect(first.rect.top, greaterThanOrEqualTo(viewport.top));
      expect(first.rect.bottom, lessThanOrEqualTo(viewport.bottom));
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: find.byKey(const ValueKey('iptv-scroll')), matching: find.byType(Scrollable)).first,
          )
          .position;
      final settled = position.pixels;
      await tester.pump(const Duration(seconds: 1));
      expect(position.pixels, settled, reason: 'a visible focused row must not keep scrolling after layout settles');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TV local nickname opens the input presenter and survives leaving the page', (tester) async {
    final services = await _pumpApp(tester);
    addTearDown(() => _close(tester, services));
    final original = TvTextInput.prompt;
    addTearDown(() => TvTextInput.prompt = original);
    String? answer = '  电视昵称  ';
    final initialValues = <String>[];
    TvTextInput.prompt =
        (context, {required title, hint = '', text = '', subtitle, numeric = false, suffix, maxLength}) async {
          expect(title, '本地昵称');
          expect(maxLength, 20);
          initialValues.add(text);
          return answer;
        };
    unawaited(AppNavigator.toNamed<void>(RoutePath.kLocalInteraction));
    await _settle(tester, rounds: 8);
    final edit = find.byKey(const ValueKey('local-name-edit'));
    expect(edit, findsOneWidget);
    expect(find.byKey(const ValueKey('local-name-input')), findsNothing, reason: 'the TV page has no inline editor');
    await tester.tap(edit);
    await _settle(tester);
    expect(find.text('电视昵称'), findsOneWidget);
    answer = null;
    await tester.tap(edit);
    await _settle(tester);
    expect(initialValues.last, '电视昵称');
    expect(find.text('电视昵称'), findsOneWidget, reason: 'cancelling does not change the saved nickname');
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(
      services.store.settings.get(Settings.localInteractionUserName),
      '电视昵称',
      reason: 'disposing the old inline controller must not overwrite the confirmed value',
    );
  });

  testWidgets('A06.9: TV sync address confirms trimmed input and cancel preserves it', (tester) async {
    final services = await _pumpApp(tester);
    addTearDown(() => _close(tester, services));
    final original = TvTextInput.prompt;
    addTearDown(() => TvTextInput.prompt = original);
    String? answer = '  http://example.invalid:1234  ';
    final initialValues = <String>[];
    TvTextInput.prompt =
        (context, {required title, hint = '', text = '', subtitle, numeric = false, suffix, maxLength}) async {
          expect(maxLength, 512);
          initialValues.add(text);
          return answer;
        };
    unawaited(AppNavigator.toNamed<void>(RoutePath.kRemoteSync));
    await _settle(tester, rounds: 8);
    final edit = find.byKey(const ValueKey('remote-sync-target'));
    expect(edit, findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await _settle(tester);
    expect(find.text('http://example.invalid:1234'), findsOneWidget);
    answer = null;
    await tester.tap(edit);
    await _settle(tester);
    expect(initialValues, ['', 'http://example.invalid:1234']);
    expect(find.text('http://example.invalid:1234'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('issue 61: initial focus waits for content that loads after many frames', (tester) async {
    await tester.runAsync(loadStrings);
    final ready = ValueNotifier(false);
    final target = FocusNode();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      ready.dispose();
      target.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TvSettingsScaffold(
          title: '设置',
          child: ValueListenableBuilder<bool>(
            valueListenable: ready,
            builder: (context, loaded, child) => loaded
                ? TextButton(focusNode: target, onPressed: () {}, child: const Text('设置内容'))
                : const CircularProgressIndicator(),
          ),
        ),
      ),
    );
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(seconds: 1));
    }
    ready.value = true;
    await tester.pump();
    await tester.pump();
    expect(target.hasFocus, isTrue, reason: 'async settings content must receive its opening focus when it arrives');
  });

  testWidgets('issue 62: cold launch paints the selected menu focus ring without a key', (tester) async {
    await prepareQaFonts(tester);
    final services = await _pumpApp(tester);
    addTearDown(() => _close(tester, services));
    expect(_focused, 'tv menu favorites');
    final target = find.byKey(const ValueKey('tv-menu-favorites'));
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: target,
                        matching: find.byWidgetPredicate(
                          (w) => w is DecoratedBox && w.position == DecorationPosition.foreground,
                        ),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(
      decoration.border,
      isNotNull,
      reason: 'a retained focused node must paint after menu expansion rebuilds its target',
    );
  });

  testWidgets('issue 59: TV configuration opens one full page rather than the phone overview', (tester) async {
    final services = await _pumpApp(tester);
    addTearDown(() => _close(tester, services));
    openTvSettingsSection(tester.element(find.byType(TvHomePage)), SettingsSection.configPreview);
    await _settle(tester, rounds: 8);
    expect(find.byKey(const ValueKey('settings-page-configPreview')), findsOneWidget);
    expect(
      find.byType(SettingsPage),
      findsNothing,
      reason: 'the TV preview must not open the phone two-pane settings shell',
    );
    final viewport = tester
        .state<ScrollableState>(
          find
              .descendant(of: find.byKey(const ValueKey('settings-config-scroll')), matching: find.byType(Scrollable))
              .first,
        )
        .position;
    expect(_focused, 'settings keyboard scroll');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(viewport.pixels, 0, reason: 'Up at the beginning must not wrap to the bottom');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(viewport.pixels, greaterThan(0), reason: 'the remote must scroll a long read-only configuration');
  });

  for (final path in [
    RoutePath.kMine,
    RoutePath.kWebDavPage,
    RoutePath.kRemoteSync,
    RoutePath.kIptv,
    RoutePath.kRecordSettings,
    RoutePath.kLocalInteraction,
    RoutePath.kBackup,
    RoutePath.kLogs,
    RoutePath.kAbout,
  ]) {
    testWidgets('issue 61: TV root $path keeps its header, first focus and transparent background', (tester) async {
      final services = await _pumpApp(
        tester,
        recordingEnabled: path == RoutePath.kRecordSettings,
        iptvEnabled: path == RoutePath.kIptv,
      );
      addTearDown(() => _close(tester, services));
      unawaited(AppNavigator.toNamed<void>(path));
      await _settle(tester, rounds: 8);
      final root = find.byKey(ValueKey('tv-settings-root-$path'));
      expect(root, findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byKey(const ValueKey('tv-page-title')), findsOneWidget);
      for (final element in find.descendant(of: root, matching: find.byType(Scaffold)).evaluate()) {
        final scaffold = element.widget as Scaffold;
        expect(scaffold.backgroundColor ?? Theme.of(element).scaffoldBackgroundColor, Colors.transparent);
      }
      final first = FocusManager.instance.primaryFocus!;
      expect(first, isNot(isA<FocusScopeNode>()));
      expect(
        first.context!.findAncestorWidgetOfExactType<TvPageHeader>(),
        isNull,
        reason: 'initial focus belongs to the content',
      );
      if (path == RoutePath.kLocalInteraction) {
        final row = find.byKey(const ValueKey('local-settings-enabled'));
        final frame = find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (widget) => widget is DecoratedBox && widget.position == DecorationPosition.foreground,
          ),
        );
        expect(frame, findsOneWidget, reason: 'the enabled row needs the same visible TV frame as other settings');
        final decoration = tester.widget<DecoratedBox>(frame).decoration as BoxDecoration;
        expect(decoration.border, Border.all(color: LiveTvColors.focusFrame, width: 3));
        expect(
          first.context!.findAncestorWidgetOfExactType<Switch>(),
          isNull,
          reason: 'the row, not its visual switch, owns directional focus',
        );
      }
      await _press(tester, LogicalKeyboardKey.arrowUp);
      final afterUp = FocusManager.instance.primaryFocus!;
      if (afterUp != first) {
        expect(
          afterUp.context!.findAncestorWidgetOfExactType<TvPageHeader>(),
          isNotNull,
          reason: 'Up must not wrap from the first row to the bottom',
        );
      }
      final visited = <FocusNode>{};
      for (var step = 0; step < 12; step++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
        final focused = FocusManager.instance.primaryFocus!;
        visited.add(focused);
        if (path == RoutePath.kLocalInteraction) {
          var informational = false;
          focused.context!.visitAncestorElements((element) {
            informational |= element.widget.key == const ValueKey('local-settings-status');
            return !informational;
          });
          expect(informational, isFalse, reason: 'the non-actionable status row is skipped');
        }
        final page = tester.getRect(root);
        expect(focused.rect.top, greaterThanOrEqualTo(page.top - 1));
        expect(focused.rect.bottom, lessThanOrEqualTo(page.bottom + 1), reason: 'directional focus remains in view');
      }
      if (path == RoutePath.kLocalInteraction) {
        expect(
          visited.length,
          greaterThanOrEqualTo(3),
          reason: 'Down must advance through controls, not stay in an editor',
        );
      }
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byType(TvHomePage), findsOneWidget);
    });
  }

  for (final zoom in [true, false]) {
    testWidgets('issue 46: first menu item paints its complete top focus ring (zoom=$zoom)', (tester) async {
      await prepareQaFonts(tester);
      final services = await _pumpApp(tester);
      addTearDown(() => _close(tester, services));
      await tester.runAsync(() => services.store.settings.set(Settings.tvFocusZoom, zoom));
      await _settle(tester);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _settle(tester);
      expect(_focused, 'tv menu favorites');
      final target = find.byKey(const ValueKey('tv-menu-favorites'));
      final ring = find
          .descendant(
            of: target,
            matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.position == DecorationPosition.foreground),
          )
          .first;
      final rect = tester.getRect(ring);
      final scale = TvScale.of(tester.element(target));
      final origin = tester.getTopLeft(find.byKey(_menuFrame));
      final y = ((rect.top - scale.px(1.5) - origin.dy) * 2).round();
      final x = ((rect.center.dx - origin.dx) * 2).round();
      final render = _menuFrame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final color = (await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
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
      await captureQaFrame(tester, 'tv-first-menu-ring-$zoom');
      expect(
        color,
        TvTheme.of(tester.element(target)).focusRing,
        reason: 'The top horizontal ring must be painted above the first menu row, even at the scroll boundary',
      );
    });
  }

  for (final zoom in [true, false]) {
    testWidgets('issue 46: last menu item paints its complete bottom focus ring (zoom=$zoom)', (tester) async {
      await prepareQaFonts(tester);
      final services = await _pumpApp(tester);
      addTearDown(() => _close(tester, services));
      await tester.runAsync(() => services.store.settings.set(Settings.tvFocusZoom, zoom));
      await _settle(tester);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _settle(tester);
      expect(_focused, 'tv menu favorites');
      for (var step = 0; step < 12 && _focused != 'tv menu iptv'; step++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(_focused, 'tv menu iptv');
      final target = find.byKey(const ValueKey('tv-menu-iptv'));
      final ring = find
          .descendant(
            of: target,
            matching: find.byWidgetPredicate((w) => w is DecoratedBox && w.position == DecorationPosition.foreground),
          )
          .first;
      final rect = tester.getRect(ring);
      final scale = TvScale.of(tester.element(target));
      final origin = tester.getTopLeft(find.byKey(_menuFrame));
      final y = ((rect.bottom + scale.px(1.5) - origin.dy) * 2).round();
      final x = ((rect.center.dx - origin.dx) * 2).round();
      final render = _menuFrame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final color = (await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
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
      await captureQaFrame(tester, 'tv-last-menu-ring-$zoom');
      expect(
        color,
        TvTheme.of(tester.element(target)).focusRing,
        reason: 'The bottom horizontal ring must be painted below the last menu row, even at the scroll boundary',
      );
    });
  }

  testWidgets('issue #35: favorites Back visits the filter, menu and exit on both channels', (tester) async {
    await prepareQaFonts(tester);
    final services = await _pumpApp(tester, follows: [1, 2], offline: {2});
    addTearDown(RoomBackChannel.instance.reset);
    Future<void> back({required bool native}) async {
      if (native) {
        unawaited(
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'pure_live/predictive_back',
            const StandardMethodCodec().encodeMethodCall(const MethodCall('backInvoked')),
            (_) {},
          ),
        );
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pump(const Duration(seconds: 1));
    }

    try {
      for (var attempt = 0; attempt < 5 && find.byType(TvRoomCard).evaluate().isEmpty; attempt++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.byType(TvRoomCard), findsOneWidget);
      for (final native in [false, true]) {
        expect(_focused, 'tv menu favorites');
        tester.widget<TvFocusable>(find.byKey(const ValueKey('tv-tab-live'))).focusNode!.requestFocus();
        await tester.pump(const Duration(seconds: 1));
        expect(_focused, 'tab live');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(seconds: 1));
        expect(_focused, 'cell 0');
        if (native) await captureQaFrame(tester, 'tv-favorites-back-cards');

        await back(native: native);
        expect(_focused, 'tab live', reason: 'first Back restores the filter instead of skipping to the menu');
        expect(find.byType(TvRoomCard), findsOneWidget, reason: 'the live selection is retained');
        if (native) await captureQaFrame(tester, 'tv-favorites-back-filter');
        await back(native: native);
        expect(_focused, 'tv menu favorites', reason: 'second Back reaches the side menu');
        if (native) await captureQaFrame(tester, 'tv-favorites-back-menu');
        await back(native: native);
        expect(find.text('退出纯粹直播？'), findsOneWidget, reason: 'the pane must not steal Back from the menu');
        await back(native: native);
        expect(find.text('退出纯粹直播？'), findsNothing);
        expect(_focused, 'tv menu favorites');
      }
    } finally {
      await _close(tester, services);
    }
  });

  Future<void> waitForFavorite(WidgetTester tester, Finder finder) async {
    for (var attempt = 0; attempt < 6 && finder.evaluate().isEmpty; attempt++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      await tester.pump(const Duration(seconds: 1));
    }
    expect(finder, findsWidgets);
  }

  Future<void> pageBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> focusTab(WidgetTester tester, String id) async {
    tester.widget<TvFocusable>(find.byKey(ValueKey('tv-tab-$id'))).focusNode!.requestFocus();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('issue #35: unselected platform focus returns without changing the selected filter', (tester) async {
    final other = LiveRoom(
      platform: SiteIds.douyu,
      roomId: '35',
      title: '另一路',
      nick: '测试主播',
      liveStatus: LiveStatus.live,
    );
    final services = await _pumpApp(
      tester,
      follows: [1, 2],
      offline: {2},
      extraSites: [
        _ExtraTvSite(SiteIds.douyu, [other]),
      ],
      extraFollows: [other],
    );
    try {
      await waitForFavorite(tester, find.byType(TvRoomCard));
      await focusTab(tester, SiteIds.douyu);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      expect(_focused, startsWith('cell'));
      expect(find.byType(TvRoomCard), findsNWidgets(2));
      final platforms = find.byWidgetPredicate(
        (widget) => widget is TvTabBar && widget.tabs.any((tab) => tab.id == SiteIds.douyu),
      );
      TvTabBar bar() => tester.widget<TvTabBar>(platforms);
      expect(bar().tabs[bar().selected].id, 'all');
      await pageBack(tester);
      expect(_focused, 'tab douyu');
      expect(bar().tabs[bar().selected].id, 'all', reason: 'focusing the Douyu filter must not select it');
      await pageBack(tester);
      expect(_focused, 'tv menu favorites');
    } finally {
      await _close(tester, services);
    }
  });

  testWidgets('issue #35: offline rows return to their state and other destinations keep their Back', (tester) async {
    final services = await _pumpApp(tester, follows: [1, 2], offline: {2});
    try {
      await waitForFavorite(tester, find.byType(TvRoomCard));
      await focusTab(tester, 'offline');
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      await waitForFavorite(tester, find.byType(TvRoomRow));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvRoomRow>(), isNotNull);
      await pageBack(tester);
      expect(_focused, 'tab offline');
      expect(find.byType(TvRoomRow), findsOneWidget);
      await pageBack(tester);
      expect(_focused, 'tv menu favorites');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      await waitForFavorite(tester, find.byType(TvRoomCard));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      await pageBack(tester);
      expect(_focused, 'tv menu popular', reason: 'the favorites handler must stay local to favorites');
    } finally {
      await _close(tester, services);
    }
  });

  testWidgets('issue #35: empty states return to the state filter when the platform row is absent', (tester) async {
    for (final follows in <List<int>>[
      [],
      [2],
    ]) {
      final services = await _pumpApp(tester, follows: follows, offline: {2});
      try {
        await waitForFavorite(tester, find.byType(TvStatusView));
        expect(find.byKey(const ValueKey('tv-follow-divider')), findsNothing);
        final status = find.byType(TvStatusView);
        final action = find.descendant(of: status, matching: find.byType(TvButton));
        expect(action, findsOneWidget);
        final text = find.descendant(of: action, matching: find.byType(Text)).first;
        Focus.of(tester.element(text)).requestFocus();
        await tester.pump(const Duration(seconds: 1));
        expect(_focused, isNot('tv menu favorites'));
        await pageBack(tester);
        expect(_focused, 'tab live');
        await pageBack(tester);
        expect(_focused, 'tv menu favorites');
        await pageBack(tester);
        expect(find.text('退出纯粹直播？'), findsOneWidget);
        await pageBack(tester);
        expect(find.text('退出纯粹直播？'), findsNothing);
      } finally {
        await _close(tester, services);
      }
    }
  });

  testWidgets('issue #35: tag and card Back restore the platform header while keeping the tag', (tester) async {
    final other = LiveRoom(
      platform: SiteIds.douyu,
      roomId: '35',
      title: '另一路',
      nick: '测试主播',
      liveStatus: LiveStatus.live,
    );
    final services = await _pumpApp(
      tester,
      follows: [1],
      extraSites: [
        _ExtraTvSite(SiteIds.douyu, [other]),
      ],
      extraFollows: [other],
      taggedFollows: true,
    );
    try {
      await waitForFavorite(tester, find.byType(TvRoomCard));
      final tags = (await tester.runAsync(services.store.tags.all))!;
      final tag = tags.single;
      await focusTab(tester, SiteIds.douyu);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      await focusTab(tester, tag.id);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      expect(_focused, startsWith('cell'));
      final tagBars = find.byWidgetPredicate(
        (widget) => widget is TvTabBar && widget.tabs.any((value) => value.id == tag.id),
      );
      TvTabBar tagBar() => tester.widget<TvTabBar>(tagBars);
      await pageBack(tester);
      expect(_focused, 'tab douyu');
      expect(tagBar().tabs[tagBar().selected].id, tag.id);
      await focusTab(tester, tag.id);
      await pageBack(tester);
      expect(_focused, 'tab douyu', reason: 'Back from the tag row also goes to the parent filter');
      expect(tagBar().tabs[tagBar().selected].id, tag.id);
      await pageBack(tester);
      expect(_focused, 'tv menu favorites');
    } finally {
      await _close(tester, services);
    }
    expect(RoomBackChannel.instance.held, isFalse);
  });

  testWidgets('issue #23: the TV remote opens active super chats and scroll keys never change channel', (tester) async {
    final services = await _pumpApp(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    final room = tester.state<TvLivePlayPageState>(find.byType(TvLivePlayPage));
    final session = room.controller!.session;
    final now = DateTime.now();
    (room.controller!.danmaku as FakeDanmaku).emit(
      DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.superChat,
          userName: '观众',
          message: '电视也能查看',
          color: LiveMessageColor.white,
          data: LiveSuperChatMessage(
            userName: '观众',
            face: '',
            message: '电视也能查看',
            price: 30,
            startTime: now,
            endTime: now.add(const Duration(minutes: 5)),
            backgroundColor: '#EDF5FF',
            backgroundBottomColor: '#2A60B2',
          ),
        ),
      ),
    );
    await _settle(tester);
    await _press(tester, LogicalKeyboardKey.select);
    final entry = find.byKey(const ValueKey('tv-room-super-chat'));
    expect(entry, findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    final focused = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>();
    expect(focused?.key, const ValueKey('tv-room-super-chat'));
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byKey(const ValueKey('panel-super-chats')), findsOneWidget);
    expect(find.text('电视也能查看'), findsOneWidget);
    await captureQaFrame(tester, 'tv-super-chat-panel');
    for (final size in [const Size(3840, 2160), const Size(1280, 720)]) {
      tester.view.physicalSize = size;
      await tester.pump(const Duration(seconds: 1));
      final heading = tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('room-panel-title')));
      expect(
        heading.getMinIntrinsicHeight(heading.size.width),
        lessThanOrEqualTo(heading.size.height + 0.1),
        reason: 'the title must fit inside the panel header at $size',
      );
      await captureQaFrame(tester, size.width == 3840 ? 'tv-super-chat-4k' : 'tv-super-chat-720p');
    }
    final index = room.index;
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(room.index, index);
    expect(room.controller!.session, same(session));
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tv super chat history');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('隐藏历史'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(room.index, index);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('显示历史'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byKey(const ValueKey('panel-super-chats')), findsNothing);
    expect(find.byType(TvLivePlayPage), findsOneWidget);
    await _close(tester, services);
  });

  setUp(_toasts.clear);

  test('interface mode: auto follows the device, phone and tv are fixed; rules of the grid', () {
    expect(UiMode.parse('tv'), UiMode.tv);
    expect(UiMode.parse('watch'), UiMode.auto);
    expect(UiMode.auto.showsTv(television: true), isTrue);
    expect(UiMode.auto.showsTv(television: false), isFalse);
    expect(UiMode.phone.showsTv(television: true), isFalse);
    expect(UiMode.tv.showsTv(television: false), isTrue);
    // pure_live_TV: four columns, one fewer up to 130 %, two fewer above.
    expect([1.0, 1.15, 1.3, 1.45, 1.6].map(tvRoomColumns), [4, 3, 3, 2, 2]);
    // A card is its 16:9 cover over two lines (U.15a): at 184 wide on a
    // 1080p television (unit 0.5) the cover is 103.5 high.
    const scale = TvScale(unit: 0.5, textScale: 1);
    expect(TvRoomCard.heightFor(184, scale), closeTo(184 * 9 / 16 + 16 + 42 + 1, 0.01));
    // The settings page has the row.
    expect(settingsCatalog.where((entry) => entry.id == 'ui_mode'), hasLength(1));
  });

  testWidgets('auto shows the TV interface on a television; switching the setting rebuilds at once', (tester) async {
    final services = await _pumpApp(tester, mode: 'auto', television: true);
    expect(find.byType(TvHomePage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);
    expect(MediaQuery.of(tester.element(find.byType(TvHomePage))).navigationMode, NavigationMode.directional);

    await tester.runAsync(() => services.store.settings.set(Settings.uiMode, 'phone'));
    await _settle(tester);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(TvHomePage), findsNothing);

    await tester.runAsync(() => services.store.settings.set(Settings.uiMode, 'tv'));
    await _settle(tester);
    expect(find.byType(TvHomePage), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('home: the menu, OK into a destination, the grid by index, Left back to the menu', (tester) async {
    final services = await _pumpApp(tester);
    expect(_focused, 'tv menu favorites');
    expect(find.text('无关注直播'), findsOneWidget);
    expect(find.text('搜索直播'), findsOneWidget, reason: 'A17.3 c4');

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'tv menu popular');
    await _press(tester, LogicalKeyboardKey.select);
    // OK opened the destination and moved into it (the platform tab).
    expect(_focused, 'tab bilibili');
    expect(find.text('直播 0'), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 0');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, 'cell 1');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 5');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    // The last row ends at room 9.
    expect(_focused, 'cell 9');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'cell 1');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tab bilibili');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 1', reason: 'back into the grid on the card left last');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused, 'tv menu popular');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, 'cell 0', reason: 'Right enters the destination on its last item');
    // A17.2 c2: in the page the menu is a rail of icons, no scrim.
    final rail = tester.getSize(find.byKey(const ValueKey('tv-home-menu'))).width;
    expect(find.byKey(const ValueKey('tv-home-menu-scrim')), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('tv-home-menu')), matching: find.text('热门')), findsNothing);

    // Back steps out: the destination, then the menu (opened over the
    // dimmed page, with the names), then the exit question (A17.2 c8).
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_focused, 'tv menu popular');
    expect(tester.getSize(find.byKey(const ValueKey('tv-home-menu'))).width, greaterThan(rail * 2));
    expect(find.byKey(const ValueKey('tv-home-menu-scrim')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('tv-home-menu')), matching: find.text('热门')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.text('退出纯粹直播？'), findsOneWidget);
    expect(_focused, isNot(startsWith('tv menu')), reason: 'the main button "退出" has the focus');
    // Back is cancel: the home stays, the focus is back on the menu.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('退出纯粹直播？'), findsNothing);
    expect(find.byType(TvHomePage), findsOneWidget);
    expect(_focused, 'tv menu popular');

    // "导航栏始终展开": the menu keeps its names beside the page.
    await tester.runAsync(() => services.store.settings.set(Settings.tvMenuAlwaysExpanded, true));
    await _settle(tester);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, startsWith('cell'));
    expect(find.descendant(of: find.byKey(const ValueKey('tv-home-menu')), matching: find.text('热门')), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-home-menu-scrim')), findsNothing);
    await _close(tester, services);
  });

  group('issue 98: phone input on TV link playback', () {
    Future<void> enter(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      await _press(tester, LogicalKeyboardKey.select);
      await _settle(tester);
      expect(find.byKey(const ValueKey('tv-link-phone')), findsOneWidget);
    }

    Future<Uri> open(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('tv-link-phone')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('tv-phone-dialog')), findsOneWidget);
      expect(find.byType(TvQrPanel), findsOneWidget);
      final address = Uri.parse(tester.widget<TvQrPanel>(find.byType(TvQrPanel)).data);
      // Only the application's newly created one-off server is contacted.
      return address.replace(host: '127.0.0.1');
    }

    Future<String> request(WidgetTester tester, Uri address, {String? link}) async {
      String? body;
      Object? failure;
      var done = false;
      await tester.runAsync(() async {
        unawaited(
          HttpOverrides.runWithHttpOverrides(() async {
                final client = HttpClient();
                try {
                  final req = await client.openUrl(link == null ? 'GET' : 'POST', address);
                  if (link != null) {
                    req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
                    req.write('link=${Uri.encodeQueryComponent(link)}');
                  }
                  final response = await req.close();
                  expect(response.statusCode, HttpStatus.ok);
                  return await utf8.decoder.bind(response).join();
                } finally {
                  client.close(force: true);
                }
              }, _LocalHttp())
              .timeout(const Duration(seconds: 5))
              .then(
                (value) {
                  body = value;
                  done = true;
                },
                onError: (Object error) {
                  failure = error;
                  done = true;
                },
              ),
        );
      });
      // The app's server futures belong to the widget-test zone. Pump them
      // while the loopback client runs instead of blocking inside runAsync.
      for (var i = 0; i < 300 && !done; i++) {
        await _settle(tester, rounds: 1);
      }
      expect(done, isTrue, reason: 'local form completes within the bounded wait');
      expect(failure, isNull);
      return body!;
    }

    testWidgets('a pasted multiline share code opens the TV room through the real local form', (tester) async {
      final services = await _pumpApp(tester);
      await enter(tester);
      final address = await open(tester);
      final html = await request(tester, address);
      expect(html, contains('name="link"'));
      expect(html, contains('<textarea'));
      expect(html, contains('链接放映'));
      final code = encodeRoomShareCode(LiveRoom(platform: SiteIds.bilibili, roomId: '1', title: '本地测试'));
      expect(await request(tester, address, link: '分享直播间\n$code\n'), contains('已发送到电视'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('tv-phone-dialog')), findsNothing);
      expect(find.byType(TvLivePlayPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester, services);
    });

    testWidgets('invalid input remains editable; cancel and blank submissions preserve it', (tester) async {
      final services = await _pumpApp(tester);
      await enter(tester);
      final first = await open(tester);
      await request(tester, first, link: '  not-a-room  ');
      await _settle(tester);
      expect(tester.widget<TvInputField>(find.byKey(const ValueKey('tv-link-field'))).text, 'not-a-room');
      expect(tester.widget<Text>(find.byKey(const ValueKey('tv-link-status'))).data, isNot(contains('按 OK')));
      expect(find.byType(TvLivePlayPage), findsNothing);
      final second = await open(tester);
      expect(await request(tester, second), contains('>not-a-room</textarea>'));
      await tester.tap(find.byKey(const ValueKey('tv-phone-close')));
      await _settle(tester);
      expect(tester.widget<TvInputField>(find.byKey(const ValueKey('tv-link-field'))).text, 'not-a-room');
      final third = await open(tester);
      await request(tester, third, link: '  \n ');
      await _settle(tester);
      expect(tester.widget<TvInputField>(find.byKey(const ValueKey('tv-link-field'))).text, 'not-a-room');
      expect(find.byType(TvLivePlayPage), findsNothing);
      expect(tester.takeException(), isNull);
      await _close(tester, services);
    });

    testWidgets('the remote reaches phone input and Back cancels without changing the draft', (tester) async {
      final services = await _pumpApp(tester);
      await enter(tester);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.select);
      await _settle(tester);
      expect(find.byKey(const ValueKey('tv-phone-dialog')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
      expect(find.byKey(const ValueKey('tv-phone-dialog')), findsNothing);
      expect(tester.widget<TvInputField>(find.byKey(const ValueKey('tv-link-field'))).text, isEmpty);
      expect(tester.widget<TvButton>(find.byKey(const ValueKey('tv-link-play'))).onTap, isNull);
      // The original button keeps its focus after the modal closes.
      await _press(tester, LogicalKeyboardKey.select);
      await _settle(tester);
      expect(find.byKey(const ValueKey('tv-phone-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tv-phone-close')));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _close(tester, services);
    });
  });

  testWidgets('A17.5 c12: 链接放映 sits between 关注分区 and 搜索; its field types with the remote', (tester) async {
    final services = await _pumpApp(tester);
    for (var i = 0; i < 4; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused, 'tv menu link');
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-link-field')), findsOneWidget);
    expect(find.text('支持直播间链接、短链接和分享口令；按 OK 用遥控器输入，或用手机扫码粘贴'), findsOneWidget);
    // Nothing typed: "播放" waits.
    expect(tester.widget<TvButton>(find.byKey(const ValueKey('tv-link-play'))).onTap, isNull);
    await _close(tester, services);
  });

  testWidgets("A17.2 c8: Android's Back (the native channel) asks before leaving; over a page it pops the page", (
    tester,
  ) async {
    final services = await _pumpApp(tester);
    addTearDown(RoomBackChannel.instance.reset);
    // Not awaited: the handler waits while the exit question is open.
    Future<void> nativeBack() async {
      unawaited(
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'pure_live/predictive_back',
          const StandardMethodCodec().encodeMethodCall(const MethodCall('backInvoked')),
          (_) {},
        ),
      );
      await _settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(RoomBackChannel.instance.held, isTrue, reason: 'the home takes Back from Android');
    await nativeBack();
    expect(find.text('退出纯粹直播？'), findsOneWidget);
    // Over the dialog, Back closes it.
    await nativeBack();
    expect(find.text('退出纯粹直播？'), findsNothing);
    expect(find.byType(TvHomePage), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('A17.2 c10: the first start shows the notice once; agreeing opens the home', (tester) async {
    final services = await _pumpApp(tester, noticeAccepted: false);
    expect(find.byKey(const ValueKey('tv-notice')), findsOneWidget);
    expect(find.text('已阅读并同意'), findsOneWidget);
    // Down scrolls the words; the focus stays on the buttons.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(find.byKey(const ValueKey('tv-notice')), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('tv-notice')), findsNothing);
    expect(_focused, 'tv menu favorites');
    expect(await tester.runAsync(() => services.store.meta.get(TvHomePage.noticeKey)), '1');
    await _close(tester, services);
  });

  testWidgets('issue #14 room: touch and remote show controls; switching and Back keep working', (tester) async {
    final services = await _pumpApp(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focused, 'cell 1');

    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    final room = tester.state<TvLivePlayPageState>(find.byType(TvLivePlayPage));
    expect(room.index, 1);
    expect(room.playlist, hasLength(10));
    expect(room.controller!.room.roomId, '1');
    // D05.2: the picture's danmaku follow "同屏最大弹幕条数" (48 by default).
    expect(tester.widget<DanmakuOverlay>(find.byType(DanmakuOverlay)).maxVisible, 48);
    await tester.runAsync(() => services.store.settings.set(Settings.danmakuMaxVisibleCount, 30));
    await _settle(tester);
    expect(tester.widget<DanmakuOverlay>(find.byType(DanmakuOverlay)).maxVisible, 30);

    // Two presses inside the window: one switch of two rooms.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(room.index, 3);
    expect(room.controller!.room.roomId, '3');
    expect(find.byKey(const ValueKey('tv-room-banner')), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester, rounds: 10);
    expect(room.index, 2);
    expect(room.controller!.stage, RoomStage.playing);
    // History records the rooms shown.
    final history = (await tester.runAsync(services.store.history.all))!;
    expect(history.map((room) => room.roomId), containsAll(['1', '2', '3']));

    // OK: the controls, focus on the first button; Back hides them.
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-room-controls')), findsOneWidget);
    expect(find.text('画质 原画'), findsOneWidget);
    expect(_focused, 'tv room first control');
    // Left and Right walk the buttons; Up/Down still switch rooms.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<TvLivePlayPage>()));
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-controls')), findsNothing);

    // Issue #14: touching the picture can open and close the controls.
    await tester.tapAt(const Offset(960, 400));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-controls')), findsOneWidget);
    await tester.tapAt(const Offset(960, 400));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-controls')), findsNothing);

    // A17.4 c3, c7: Right opens the play settings on the right: the
    // phone's danmaku settings, the block list and recording; Back closes.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-settings')), findsOneWidget);
    expect(find.text('播放设置'), findsOneWidget);
    expect(tester.getTopRight(find.byKey(const ValueKey('tv-room-settings'))).dx, 1920);
    expect(tester.getTopLeft(find.byKey(const ValueKey('tv-room-settings'))).dx, greaterThan(960));
    expect(find.byKey(const ValueKey('tv-room-settings-danmaku')), findsOneWidget);
    expect(_focused, isNot('tv room keys'), reason: 'the focus is in the panel');
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-settings')), findsNothing);

    // Left: the room list on the left with the room shown; OK on another
    // switches.
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byKey(const ValueKey('tv-room-panel')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('tv-room-panel'))).dx, 0);
    expect(_focused, 'tv room list current');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(room.index, 3);
    expect(find.byKey(const ValueKey('tv-room-panel')), findsNothing);

    // Back leaves; the grid's focus lands on the room shown last.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(find.byType(TvLivePlayPage), findsNothing);
    expect(_focused, 'cell 3');
    await _close(tester, services);
  });

  testWidgets('a held OK opens the card dialog instead of the room; the menu key too', (tester) async {
    final services = await _pumpApp(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'cell 0');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-dialog')), findsOneWidget);
    expect(find.byType(TvLivePlayPage), findsNothing);
    // The dialog took the focus (no arrow needed): "设置标签" (U.15a c9).
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Dialog>(), isNotNull);
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>()?.key,
      const ValueKey('tv-room-dialog-tags'),
    );

    await _press(tester, LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-dialog')), findsNothing);
    expect(_focused, 'cell 0');

    // The remote's menu key is the same as a held OK (U.15a c10).
    await _press(tester, LogicalKeyboardKey.contextMenu);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-room-dialog')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_focused, 'cell 0');
    await _close(tester, services);
  });

  testWidgets('search: OK on the field types through the input, results in a grid, Back to the history', (
    tester,
  ) async {
    final asked = <String>[];
    TvTextInput.prompt =
        (context, {required title, hint = '', text = '', subtitle, numeric = false, suffix, maxLength}) async {
          asked.add(title);
          return ' 直播 7 ';
        };
    addTearDown(() => TvTextInput.prompt = TvTextInput.defaultPrompt);
    final services = await _pumpApp(tester);
    for (var i = 0; i < 5; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused, 'tv menu search');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.text('按 OK 打开输入框，用遥控器或语音输入要找的内容'), findsOneWidget);
    expect(_focused, 'tv search field');

    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester, rounds: 6);
    expect(asked, ['搜索直播间、主播或房间号']);
    expect(find.text('直播 7'), findsWidgets);
    expect(find.text('主播7'), findsOneWidget);

    // Back: from the results to the field, the word kept in the history.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-search-word-直播 7')), findsOneWidget);
    expect(find.byType(TvHomePage), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('A17.3 c11, c12: one search page — filters, streamers as rows, up to the platforms, clear asks first', (
    tester,
  ) async {
    TvTextInput.prompt = (
      context, {
      required title,
      hint = '',
      text = '',
      subtitle,
      numeric = false,
      suffix,
      maxLength,
    }) async => '直播 7';
    addTearDown(() => TvTextInput.prompt = TvTextInput.defaultPrompt);
    final services = await _pumpApp(tester);
    for (var i = 0; i < 5; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    await _press(tester, LogicalKeyboardKey.select);
    expect(_focused, 'tv search field');
    // The filters are on the page before a search.
    for (final key in [
      'tv-search-mode-rooms',
      'tv-search-mode-anchors',
      'tv-search-offline',
      'tv-search-sort',
      'tv-search-phone',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(find.byKey(const ValueKey('tv-search-scope')), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester, rounds: 6);
    expect(find.byType(TvRoomCard), findsWidgets);
    // OK searched: the focus is on the first result.
    expect(_focused, 'cell 0');

    // "主播": the same words again; rows, not blown-up avatars; no order.
    await tester.tap(find.byKey(const ValueKey('tv-search-mode-anchors')));
    await _settle(tester, rounds: 6);
    expect(find.byType(TvRoomRow), findsOneWidget);
    expect(find.byType(TvRoomCard), findsNothing);
    expect(find.text('主播7'), findsOneWidget);
    expect(find.textContaining('正在直播'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-search-sort')), findsNothing);
    // Up from the results goes back to the platforms.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvRoomRow>(), isNotNull);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tab all');

    // Back to the recent words; "清空" asks with the focus on cancel.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('tv-search-clear')));
    await _settle(tester);
    expect(find.text('清空最近搜索'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>()?.key,
      const ValueKey('tv-confirm-no'),
    );
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-search-word-直播 7')), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('follows off air: ← from the first column of rows goes to the rail', (tester) async {
    final services = await _pumpApp(tester, follows: [1, 2, 3], offline: {2, 3});
    expect(_focused, 'tv menu favorites');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    // Up to the states, across to "未开播", OK, down into the rows.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvRoomRow>(), isNotNull);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused, 'tv menu favorites');
    await _close(tester, services);
  });

  testWidgets('issue128 HUD settings inherit TV styling and immediately focus their first control', (tester) async {
    final services = await _pumpApp(tester);
    try {
      for (var i = 0; i < TvPane.menu.length; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      await _press(tester, LogicalKeyboardKey.select);
      for (var i = 0; i < 9; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      await _press(tester, LogicalKeyboardKey.select);
      await _press(tester, LogicalKeyboardKey.select);
      await _settle(tester, rounds: 6);
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(focused?.findAncestorWidgetOfExactType<SettingsRow>()?.title, '显示方式');
      expect(SettingsRowStyle.tvOf(focused!), isTrue);
      expect(find.byKey(const ValueKey('tv-settings-playback-hud')), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.select);
      expect(find.byType(TvOptionRow), findsNWidgets(4));
      expect(
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvOptionRow>()?.key,
        const ValueKey('tv-choice-1'),
      );
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _press(tester, LogicalKeyboardKey.select);
      expect(services.store.settings.get(Settings.playbackHud)['mode'], 'off');

      for (
        var i = 0;
        i < 12 &&
            FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<SettingsSliderRow>()?.key !=
                const ValueKey('playback-hud-size');
        i++
      ) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<SettingsSliderRow>()?.key,
        const ValueKey('playback-hud-size'),
      );
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _settle(tester);
      expect(services.store.settings.get(Settings.playbackHud)['size'], 12);
    } finally {
      await _close(tester, services);
    }
  });

  testWidgets('issue131 TV scrolling reveals the complete focused slider row', (tester) async {
    final services = await _pumpApp(tester);
    try {
      tester.view.physicalSize = const Size(1280, 720);
      await _settle(tester);
      for (var i = 0; i < TvPane.menu.length; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      await _press(tester, LogicalKeyboardKey.select);
      for (var i = 0; i < 9; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      await _press(tester, LogicalKeyboardKey.select);
      for (
        var i = 0;
        i < 20 &&
            FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<SettingsSliderRow>()?.title !=
                '手机端默认音量';
        i++
      ) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      await tester.pump(const Duration(seconds: 1));
      expect(
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<SettingsSliderRow>()?.title,
        '手机端默认音量',
      );
      final row = find.byWidgetPredicate((widget) => widget is SettingsSliderRow && widget.title == '手机端默认音量');
      final viewport = find
          .descendant(of: find.byKey(const ValueKey('tv-settings-page-video')), matching: find.byType(Scrollable))
          .first;
      expect(tester.getRect(row).bottom, lessThanOrEqualTo(tester.getRect(viewport).bottom));
    } finally {
      await _close(tester, services);
    }
  });

  testWidgets('issue138 Up on the first settings row stays in the page; Left still returns to Settings', (
    tester,
  ) async {
    final services = await _pumpApp(tester);
    try {
      for (var i = 0; i < TvPane.menu.length; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      await _press(tester, LogicalKeyboardKey.select);
      final first = FocusManager.instance.primaryFocus;
      expect(first?.context?.findAncestorWidgetOfExactType<TvFocusable>()?.key, const ValueKey('tv-setting-ui_mode'));
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(FocusManager.instance.primaryFocus, same(first));
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(_focused, 'tv menu settings');
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(FocusManager.instance.primaryFocus, same(first));
    } finally {
      await _close(tester, services);
    }
  });

  testWidgets('issue138 returning to the first settings row restores the complete header', (tester) async {
    final services = await _pumpApp(tester);
    try {
      for (var i = 0; i < TvPane.menu.length; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      await _press(tester, LogicalKeyboardKey.select);
      final first = FocusManager.instance.primaryFocus;
      for (var i = 0; i < 9; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: find.byKey(const ValueKey('tv-settings-catalog')), matching: find.byType(Scrollable)).first,
      );
      expect(scroll.position.pixels, greaterThan(0));
      for (var i = 0; i < 9; i++) {
        await _press(tester, LogicalKeyboardKey.arrowUp);
      }
      expect(FocusManager.instance.primaryFocus, same(first));
      await tester.pump(const Duration(seconds: 1));
      expect(
        scroll.position.pixels,
        0,
        reason: 'the non-focusable page/group titles must reappear above the first row',
      );
    } finally {
      await _close(tester, services);
    }
  });

  testWidgets('rail: up and down follow the rail, not the page rows under the opened rail', (tester) async {
    final services = await _pumpApp(tester);
    for (var i = 0; i < TvPane.menu.length; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused, 'tv menu settings');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-setting-ui_mode')), findsOneWidget);
    // Down into the page, then back to the rail's 设置 and up along it.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focused, 'tv menu settings');
    final menu = TvPane.menuOf().where((pane) => pane != TvPane.settings).toList();
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tv menu ${menu.last.name}');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tv menu ${menu[menu.length - 2].name}');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused, 'tv menu settings');
    // The top of the rail is the mode button.
    for (var i = 0; i < menu.length + 2; i++) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(_focused, 'tv menu mode');
    await _close(tester, services);
  });

  testWidgets('TV settings: OK opens the choices on the current value; picking phone switches', (tester) async {
    final services = await _pumpApp(tester);
    for (var i = 0; i < TvPane.menu.length; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(_focused, 'tv menu settings');
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-setting-ui_mode')), findsOneWidget);
    // The first row has the focus; OK opens the choices with the focus on
    // the current one (tv), Up moves to phone, OK picks it (U.15a row 13).
    await _press(tester, LogicalKeyboardKey.select);
    expect(find.byKey(const ValueKey('tv-option-current')), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvOptionRow>()?.key,
      const ValueKey('tv-choice-2'),
    );
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(services.store.settings.get(Settings.uiMode), 'phone');
    expect(find.byType(HomePage), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('A17.9: the TV settings are the phone\'s overview after the TV rows, "关于" last', (tester) async {
    final services = await _pumpApp(tester);
    for (var i = 0; i < TvPane.menu.length; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    await _press(tester, LogicalKeyboardKey.select);
    String? row() =>
        (FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvFocusable>()?.key
                as ValueKey<String>?)
            ?.value
            .substring('tv-setting-'.length);
    final rows = [row()];
    var navigationWords = false;
    while (true) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
      if (row() == rows.last) break;
      rows.add(row());
      // "导航栏" manages the TV's side rail, and says so.
      if (row() == 'section-navigation') navigationWords = find.text('左边导航栏显示哪些入口、顺序和图标').evaluate().isNotEmpty;
    }
    expect(navigationWords, isTrue);
    expect(rows, [
      'ui_mode',
      'focus_zoom',
      'wallpaper',
      'menu_expanded',
      for (final area in SettingsArea.values)
        for (final section in SettingsSection.values)
          if (section.area == area && section != SettingsSection.pipDanmaku) 'section-${section.name}',
      'about',
    ]);
    await _close(tester, services);
  });

  testWidgets("A17.9: a settings page is the phone's rows in the TV look; ← off, → on; Back to its row", (
    tester,
  ) async {
    final services = await _pumpApp(tester);
    addTearDown(RoomBackChannel.instance.reset);
    final settings = services.store.settings;
    // Android's Back, as the device sends it (the TV home holds it).
    Future<void> nativeBack() async {
      unawaited(
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'pure_live/predictive_back',
          const StandardMethodCodec().encodeMethodCall(const MethodCall('backInvoked')),
          (_) {},
        ),
      );
      await _settle(tester, rounds: 6);
      await tester.pump(const Duration(milliseconds: 400));
    }

    for (var i = 0; i < TvPane.menu.length; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    await _press(tester, LogicalKeyboardKey.select);
    // ui_mode, focus_zoom, wallpaper, menu_expanded, appearance, navigation, platforms, refresh.
    for (var i = 0; i < 7; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvFocusable>()?.key,
      const ValueKey('tv-setting-section-refresh'),
    );
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester, rounds: 6);
    expect(find.byKey(const ValueKey('tv-settings-page-refresh')), findsOneWidget);
    expect(find.text('刷新设置'), findsWidgets);
    // The first row ("开启关注自动刷新") has the focus, in the TV look.
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused?.findAncestorWidgetOfExactType<SettingsSwitchRow>()?.title, '开启关注自动刷新');
    expect(SettingsRowStyle.tvOf(focused!), isTrue);
    expect(settings.get(Settings.autoRefreshFavorite), isFalse);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(settings.get(Settings.autoRefreshFavorite), isTrue);
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(settings.get(Settings.autoRefreshFavorite), isTrue, reason: 'already on: stays');
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(settings.get(Settings.autoRefreshFavorite), isFalse);
    expect(find.byKey(const ValueKey('tv-settings-page-refresh')), findsOneWidget, reason: 'the focus stayed');

    // The interval (on again) opens the TV's choices on the current value.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byType(TvOptionRow), findsWidgets);
    expect(find.byKey(const ValueKey('tv-option-current')), findsOneWidget);
    await nativeBack();
    expect(find.byType(TvOptionRow), findsNothing);
    expect(find.byKey(const ValueKey('tv-settings-page-refresh')), findsOneWidget);

    await nativeBack();
    expect(find.byKey(const ValueKey('tv-settings-page-refresh')), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvFocusable>()?.key,
      const ValueKey('tv-setting-section-refresh'),
      reason: 'back on the row that opened it',
    );
    await _close(tester, services);
  });

  testWidgets('A17.9 c14: a web address on the TV shows its code for a phone instead of a browser', (tester) async {
    final services = await _pumpApp(tester);
    final opened = AppNavigator.openExternal(Uri.parse('https://mpv.io/manual/stable/'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-link-dialog')), findsOneWidget);
    expect(find.text('https://mpv.io/manual/stable/'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byKey(const ValueKey('tv-link-dialog')), findsNothing);
    expect(await opened, isTrue);
    await _close(tester, services);
  });

  testWidgets('A17.6 X1: the mode button switches to videos: 搜索、我的、首页、分区、影视, behind the login', (tester) async {
    final services = await _pumpApp(tester);
    expect(_focused, 'tv menu favorites');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused, 'tv menu mode');
    expect(find.text('直播'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    expect(find.byType(TvOptionRow), findsNWidgets(3), reason: '直播, 视频, 音乐');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester, rounds: 6);
    expect(services.store.settings.get(Settings.tvMode), 'video');
    final menu = [
      for (final element
          in find
              .byWidgetPredicate(
                (widget) =>
                    widget.key is ValueKey<String> && (widget.key! as ValueKey<String>).value.startsWith('tv-menu-'),
              )
              .evaluate())
        (element.widget.key! as ValueKey<String>).value,
    ];
    expect(menu, [
      'tv-menu-mode',
      'tv-menu-videoSearch',
      'tv-menu-videoMine',
      'tv-menu-videoHome',
      'tv-menu-videoAreas',
      'tv-menu-videoCinema',
      'tv-menu-settings',
    ]);
    expect(_focused, 'tv menu videoSearch');
    expect(find.byKey(const ValueKey('tv-video-login-gate')), findsOneWidget, reason: 'signed out');

    // A17.7: music lands on "我的".
    for (var i = 0; i < 6; i++) {
      if (_focused == 'tv menu mode') break;
      await _press(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(_focused, 'tv menu mode');
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.select);
    await _settle(tester, rounds: 6);
    expect(services.store.settings.get(Settings.tvMode), 'music');
    expect(_focused, 'tv menu musicMine');
    expect(find.byKey(const ValueKey('tv-menu-musicNow')), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('a focusable: OK taps at once without a long press; with one, a hold never also taps', (tester) async {
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            TvFocusable(autofocus: true, onTap: () => taps++, builder: (_, _) => const Text('plain')),
            TvFocusable(onTap: () => taps++, onLongPress: () => holds++, builder: (_, _) => const Text('card')),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect((taps, holds), (2, 0));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect((taps, holds), (2, 1));
    // Android's long press is the first repeat (about 400 ms, before the
    // timer): it holds, the release does not tap, and more repeats do nothing.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(seconds: 1));
    expect((taps, holds), (2, 2));
  });
}
