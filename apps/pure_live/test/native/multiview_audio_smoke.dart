import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/bootstrap.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/multiview/logic/multiview_session.dart';
import 'package:pure_live/features/multiview/multiview_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

// Native acceptance fixture: four generated tones, production multiview UI,
// real mpv, in-memory settings and no external requests or account access.

final class _NoSecrets implements SecretCipher {
  @override
  Future<Uint8List> seal(String ref, String plain) => throw StateError('No accounts in native fixture');
  @override
  Future<String> open(String ref, Uint8List sealed) => throw StateError('No accounts in native fixture');
}

final class _NoExternalHttp implements LiveHttp {
  @override
  Future<LiveResponse> send(LiveRequest request) => throw StateError('External network disabled');
  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw StateError('External network disabled');
  @override
  void close() {}
}

LiveRoom _room(String id) =>
    LiveRoom(platform: SiteIds.bilibili, roomId: id, nick: '本地音轨$id', title: '独立音量验证$id', liveStatus: LiveStatus.live);

final class _LocalSite extends LiveSite {
  new(this.port);
  final int port;
  @override
  String get id => SiteIds.bilibili;
  @override
  String get name => '本地验证';
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async => _room(roomId);
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => const [
    LivePlayQuality(quality: '本地音轨', id: 'local'),
  ];
  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    'http://127.0.0.1:$port/${detail.roomId}.mp4',
  ];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  currentStrings = await AppStrings.load(AppLanguage.zh, rootBundle);
  const mediaRoot = String.fromEnvironment('PURELIVE_AUDIO_FIXTURES');
  const output = String.fromEnvironment('PURELIVE_PROOF_DIR');
  if (mediaRoot.isEmpty || output.isEmpty) throw StateError('Provide generated media and proof directories');
  final root = Directory(output);
  await root.create(recursive: true);
  final videos = <String, List<int>>{
    for (final id in ['a', 'b', 'c', 'd']) '/$id.mp4': await File('$mediaRoot/$id.mp4').readAsBytes(),
  };
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final response = request.response;
    final video = videos[request.uri.path];
    if (video == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    try {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final match = range == null ? null : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
      final start = match == null ? 0 : int.parse(match.group(1)!);
      final end = match == null || match.group(2)!.isEmpty
          ? video.length - 1
          : int.parse(match.group(2)!).clamp(0, video.length - 1);
      if (start > end || start >= video.length || (range != null && match == null)) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        return;
      }
      if (range != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${video.length}');
      }
      response
        ..headers.contentType = ContentType('video', 'mp4')
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = end - start + 1;
      if (request.method != 'HEAD') response.add(video.sublist(start, end + 1));
    } on SocketException {
      // A page replacement closes the old native player's loopback request.
    } finally {
      await response.close().catchError((Object _) {});
    }
  });
  final cipher = _NoSecrets();
  final store = await LiveStore.memory(cipher: cipher);
  await store.settings.setAll({
    Settings.showSplashPage: false,
    Settings.enableAutoCheckUpdate: false,
    Settings.globalVolumeMute: false,
    Settings.defaultDesktopVolume: 0.5,
    Settings.useHardStopOnExit: true,
    Settings.floatPlay: false,
    Settings.windowWidth: 1200.0,
    Settings.windowHeight: 800.0,
  });
  for (final id in ['a', 'b', 'c', 'd']) {
    await store.follows.add(_room(id));
  }
  await writeMultiviewSession(store.meta, {
    'layout': 'quad',
    'smallCellsLowQuality': false,
    'danmaku': false,
    'rooms': [
      for (final id in ['a', 'b', 'c', 'd']) _room(id).toJson(),
    ],
  });
  final services = AppBootstrap.wire(
    store: store,
    cipher: cipher,
    launch: const LaunchArgs(),
    dataRoot: root,
    http: _NoExternalHttp(),
    background: false,
  );
  await DesktopShell.start(store, primary: false, dataRoot: root, instanceId: 'issue87-native');
  final site = _LocalSite(server.port);
  final localSites = SiteRegistry({SiteIds.bilibili: () => site});
  final sessions = <PlaybackSession>[];
  final engines = <PlaybackSession, MpvEngine>{};
  Timer.periodic(const Duration(seconds: 1), (_) async {
    await File('${root.path}/native-state.json').writeAsString(
      jsonEncode({
        'pid': pid,
        'platform': Platform.operatingSystem,
        'generated_media_only': true,
        'mix_audio': store.settings.get(Settings.multiviewMixAudio),
        'sessions': [
          for (final session in sessions)
            {
              'url': session.state.line?.url,
              'status': session.state.status.name,
              'native_playing': engines[session]?.player.state.playing,
              'position_ms': engines[session]?.player.state.position.inMilliseconds,
              'native_volume': engines[session]?.player.state.volume,
            },
        ],
      }),
    );
  });
  runApp(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(localSites),
        danmakuProvider.overrideWithValue(DanmakuRegistry({})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) {
          late final PlaybackSession session;
          session = PlaybackSession(
            engine: () async {
              final engine = await MpvEngine.create(config: config);
              engines[session] = engine;
              return engine;
            },
            opener: services.mediaOpener,
          );
          sessions.add(session);
          return session;
        }),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: const MultiviewPage(route: RouteArgs(RoutePath.kMultiview)),
      ),
    ),
  );
}
