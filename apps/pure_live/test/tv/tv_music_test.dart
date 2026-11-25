// A17.7: the TV music mode — song rows and menu, adding to playlists, the
// mini bar, the play mode, recent plays, the import.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_vod/live_vod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/music_catalog.dart';
import 'package:pure_live/app/music_library.dart';
import 'package:pure_live/app/music_player.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/tv/music/music_panes.dart';
import 'package:pure_live/tv/music/music_widgets.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/video/video_source.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

import '../features/live_play/live_play_support.dart';
import '../support.dart';

VodArchive _archive(String bvid, String title) => VodArchive(
  bvid: bvid,
  aid: 9,
  cid: 90,
  title: title,
  owner: const VodOwner(mid: 3, name: '歌手'),
  duration: const Duration(minutes: 4),
);

MusicTrack _track(String bvid, String title) => MusicTrack(
  archive: _archive(bvid, title),
  part: const VodPart(cid: 90, duration: Duration(minutes: 4)),
);

final class _Catalog implements MusicCatalog {
  @override
  bool get isLoggedIn => true;

  @override
  List<LyricSource> get lyricSources => const [];

  @override
  Future<MusicStream> stream(MusicTrack track, {required bool audioOnly, bool lossless = false}) async => (
    track: track,
    lines: const [LivePlayLine('https://a.example/song.m4s')],
    audio: null,
    headers: const <String, String>{},
  );

  @override
  Future<void> reportPlay(MusicTrack track) async {}

  @override
  Future<VodArchive> detail(String bvid) async => _archive(bvid, '歌 $bvid');

  @override
  Future<List<ImportedTrack>> importTracks(PlaylistPlatform platform, String id) async => const [
    ImportedTrack(name: '晴天', artist: '周杰伦', duration: Duration(minutes: 4, seconds: 29)),
    ImportedTrack(name: '查无此歌', artist: '无人', duration: Duration(minutes: 3)),
  ];

  @override
  Future<VodPage<VodArchive>> search(String keyword, {int page = 1}) async => VodPage(
    keyword.contains('晴天')
        ? [
            const VodArchive(
              bvid: 'BVq',
              aid: 1,
              cid: 10,
              title: '周杰伦 晴天',
              owner: VodOwner(mid: 1, name: '周杰伦'),
              duration: Duration(minutes: 4, seconds: 29),
              typeId: 193,
            ),
          ]
        : const [],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(UnsupportedError('${invocation.memberName}'));
}

final class _SignedIn implements VideoSource {
  @override
  bool get signedIn => true;

  @override
  Stream<void> get loginChanges => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(UnsupportedError('${invocation.memberName}'));
}

void main() {
  late FakeEngine engine;
  setUp(() => engine = FakeEngine());

  Future<(AppServices, ProviderContainer)> pump(WidgetTester tester, Widget child) async {
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final services = (await tester.runAsync(testServices))!;
    await tester.runAsync(loadStrings);
    final scheme = ColorScheme.fromSeed(seedColor: LiveTheme.brandBlue, brightness: Brightness.dark);
    final catalog = _Catalog();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          videoSourceProvider.overrideWithValue(_SignedIn()),
          musicCatalogProvider.overrideWithValue(catalog),
          musicPlayerProvider.overrideWith((ref) {
            final player = MusicPlayer(
              catalog: catalog,
              library: ref.watch(musicLibraryProvider),
              settings: services.store.settings,
              session: () => fakeSession(engine),
            );
            ref.onDispose(player.dispose);
            return player;
          }),
        ],
        child: MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
                child: TvTheme(
                  palette: TvPalette.of(scheme),
                  child: Scaffold(body: child),
                ),
              );
            },
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.runAsync(() => container.read(musicLibraryProvider).ready());
    return (services, container);
  }

  Future<void> close(WidgetTester tester, AppServices services) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 6));
    await tester.runAsync(services.close);
  }

  testWidgets('the song menu: the first item has the focus; the removal says where from', (tester) async {
    final (services, container) = await pump(
      tester,
      Consumer(
        builder: (context, ref, _) => Column(
          children: [
            TextButton(
              onPressed: () => showSongMenu(
                context,
                ref: ref,
                track: _track('BV1', '歌一'),
                place: MusicRowPlace.queue,
                queueIndex: 0,
              ),
              child: const Text('队列'),
            ),
            TextButton(
              onPressed: () => showSongMenu(
                context,
                ref: ref,
                track: _track('BV1', '歌一'),
                place: MusicRowPlace.playlist,
                playlistId: 'x',
              ),
              child: const Text('歌单'),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('队列'));
    await settle(tester);
    expect(find.text('从队列移除'), findsOneWidget);
    expect(find.text('下一首播放'), findsNothing, reason: 'it is in the queue already');
    final first = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvOptionRow>();
    expect(first?.label, '喜欢', reason: 'g6: the focus on the first item, not on the removal');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await tester.tap(find.text('歌单'));
    await settle(tester);
    expect(find.text('移出歌单'), findsOneWidget);
    expect(find.text('下一首播放'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    await close(tester, services);
  });

  testWidgets('adding to a playlist says "已在"; "新建歌单并加入" makes one with the song', (tester) async {
    TvTextInput.prompt = (
      context, {
      required title,
      hint = '',
      text = '',
      subtitle,
      numeric = false,
      suffix,
      maxLength,
    }) async => '新的歌单';
    addTearDown(() => TvTextInput.prompt = TvTextInput.defaultPrompt);
    late MusicLibrary library;
    final track = _track('BV1', '歌一');
    final (services, container) = await pump(
      tester,
      Consumer(
        builder: (context, ref, _) {
          library = ref.watch(musicLibraryProvider);
          return TextButton(
            onPressed: () => showAddToPlaylist(context, library: library, tracks: [track]),
            child: const Text('加入'),
          );
        },
      ),
    );
    await tester.runAsync(() => library.createPlaylist('老歌单', tracks: [track]));
    await tester.tap(find.text('加入'));
    await settle(tester);
    expect(find.text('已在'), findsOneWidget);
    await tester.tap(find.text('新建歌单并加入'));
    await settle(tester);
    await settle(tester);
    final made = library.playlists.firstWhere((playlist) => playlist.name == '新的歌单');
    expect(made.tracks.map((song) => song.id), [track.id]);
    await close(tester, services);
  });

  testWidgets('the mini bar shows while the queue has songs; "列表循环 ⌄" offers the modes', (tester) async {
    final (services, container) = await pump(
      tester,
      const TvMusicFrame(child: Column(children: [TvMusicModeButton()])),
    );
    expect(find.byKey(const ValueKey('tv-music-mini-bar')), findsNothing);
    final player = container.read(musicPlayerProvider);
    unawaited(player.play([_track('BV1', '歌一'), _track('BV2', '歌二')]));
    await settle(tester);
    await settle(tester);
    expect(find.byKey(const ValueKey('tv-music-mini-bar')), findsOneWidget);
    expect(find.text('歌一'), findsOneWidget);

    expect(find.text('列表循环 ⌄'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tv-music-mode')));
    await settle(tester);
    await tester.tap(find.text('随机播放'));
    await settle(tester);
    expect(player.mode, PlayMode.shuffle);
    expect(find.text('随机播放 ⌄'), findsOneWidget);
    await tester.runAsync(player.stop);
    await close(tester, services);
  });

  testWidgets('我的: "关注的UP主" and "B站关注" apart; clearing recent plays asks first', (tester) async {
    final (services, container) = await pump(tester, const TvMusicMinePane());
    expect(find.text('关注的UP主'), findsOneWidget);
    expect(find.text('B站关注'), findsOneWidget);
    final library = container.read(musicLibraryProvider);
    await tester.runAsync(() => library.recordPlay(_track('BV1', '歌一')));
    await tester.tap(find.text('最近'));
    await settle(tester);
    expect(find.text('歌一'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tv-music-clear-recent')));
    await settle(tester);
    expect(find.text('清空全部最近播放记录？'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TvButton>()?.label,
      '取消',
      reason: 'g8: the focus on cancel',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await settle(tester);
    expect(library.recents, hasLength(1));
    await close(tester, services);
  });

  testWidgets('the import: platform and link, matching with progress, a playlist of the matched songs', (tester) async {
    TvTextInput.prompt = (
      context, {
      required title,
      hint = '',
      text = '',
      subtitle,
      numeric = false,
      suffix,
      maxLength,
    }) async => 'https://music.163.com/#/playlist?id=123';
    addTearDown(() => TvTextInput.prompt = TvTextInput.defaultPrompt);
    final catalog = _Catalog();
    final (services, container) = await pump(
      tester,
      TvMusicImportPage(
        importer: PlaylistImporter(
          search: (keyword) async => (await catalog.search(keyword)).items,
          sleep: (_) async {},
        ),
      ),
    );
    expect(find.text('第 1 步：选择平台和歌单'), findsOneWidget);
    expect(find.byType(TvFocusable), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('tv-music-import-start')));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    expect(find.textContaining('导入完成：匹配到 1 首，1 首没找到'), findsOneWidget);
    final library = container.read(musicLibraryProvider);
    final made = library.playlists.single;
    expect(made.name, '从网易云导入');
    expect(made.tracks.single.archive.bvid, 'BVq');
    await close(tester, services);
  });
}

/// Lets the store answer (real time) and the frames run.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
