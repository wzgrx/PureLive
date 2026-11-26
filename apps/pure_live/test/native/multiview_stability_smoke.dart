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
import 'package:media_kit/media_kit.dart' as kit;
import 'package:pure_live/app/bootstrap.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';
import 'package:pure_live/features/multiview/logic/multiview_session.dart';
import 'package:pure_live/features/multiview/multiview_page.dart';
import 'package:pure_live/features/multiview/widgets/toolbar.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import 'recording_interruption_probe.dart';

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
    Settings.globalVolumeMute: true,
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
  await DesktopShell.start(store, primary: false, dataRoot: root, instanceId: 'codex572-native-stability');
  final site = _LocalSite(server.port);
  final localSites = SiteRegistry({SiteIds.bilibili: () => site});
  final sessions = <PlaybackSession>[];
  final engines = <PlaybackSession, MpvEngine>{};
  final watch = Stopwatch()..start();
  var created = 0;
  var retired = 0;
  var writing = false;
  final ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
    if (writing) return;
    writing = true;
    try {
      await File('${root.path}/native-state.json').writeAsString(
        jsonEncode({
          'pid': pid,
          'platform': Platform.operatingSystem,
          'generated_media_only': true,
          'mix_audio': store.settings.get(Settings.multiviewMixAudio),
          'elapsed_ms': watch.elapsedMilliseconds,
          'created': created,
          'retired': retired,
          'rss_bytes': ProcessInfo.currentRss,
          'peak_rss_bytes': ProcessInfo.maxRss,
          'sessions': [
            for (final session in sessions)
              {
                'url': session.state.line?.url,
                'status': session.state.status.name,
                'native_playing': engines[session]?.player.state.playing,
                'position_ms': engines[session]?.player.state.position.inMilliseconds,
                'native_volume': engines[session]?.player.state.volume,
                'native_frame_revision': engines[session]?.controller.frameRevision.value,
                'native_texture_id': engines[session]?.controller.id.value,
              },
          ],
        }),
      );
    } finally {
      writing = false;
    }
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
              await engine.player.setPlaylistMode(kit.PlaylistMode.single);
              return engine;
            },
            opener: services.mediaOpener,
          );
          sessions.add(session);
          created++;
          session.states.listen(
            (_) {},
            onDone: () {
              sessions.remove(session);
              engines.remove(session);
              retired++;
            },
          );
          return session;
        }),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: const MultiviewPage(route: RouteArgs(RoutePath.kMultiview)),
      ),
    ),
  );
  Object? failure;
  MultiviewController? multiview;
  var cycles = 0;
  var resizeOperations = 0;
  var editorVerified = false;
  Map<String, Object?>? recordingRecovery;
  try {
    recordingRecovery = await probeInterruptedRecording(Directory('${root.path}/recording-recovery'));
    if (recordingRecovery['passed'] != true) throw StateError('Native interrupted recording did not finalize');
    await _until(() => _widgets<LayoutSegments>().isNotEmpty);
    multiview = _widgets<LayoutSegments>().first.controller;
    await multiview.restoreLast();
    await _until(
      () =>
          sessions.length == 4 &&
          sessions.every(
            (s) => (engines[s]?.controller.frameRevision.value ?? 0) > 0 && s.state.status == PlaybackStatus.playing,
          ),
    );
    if (Platform.isWindows) {
      const channel = MethodChannel('pure_live/playback_keyboard');
      final before = await channel.invokeMapMethod<String, Object?>('getPlaybackKeyboardState');
      if (before?['enabled'] != true || before?['hasImeContext'] != false) {
        throw StateError('Playback IME remains attached');
      }
      final editor = _widgets<EditableText>().first;
      editor.focusNode.requestFocus();
      await Future<void>.delayed(const Duration(seconds: 1));
      final during = await channel.invokeMapMethod<String, Object?>('getPlaybackKeyboardState');
      if (during?['enabled'] != false) throw StateError('Text editing did not restore IME');
      editor.controller.text = '中文输入验证';
      editor.focusNode.unfocus();
      await Future<void>.delayed(const Duration(seconds: 1));
      final after = await channel.invokeMapMethod<String, Object?>('getPlaybackKeyboardState');
      if (after?['enabled'] != true || after?['hasImeContext'] != false) {
        throw StateError('Playback IME state did not resume');
      }
      editorVerified = true;
    }
    const seconds = int.fromEnvironment('PURELIVE_STRESS_SECONDS', defaultValue: 3900);
    final deadline = watch.elapsed + const Duration(seconds: seconds);
    while (watch.elapsed < deadline) {
      final active = List<PlaybackSession>.of(sessions);
      for (final session in active) {
        final engine = engines[session];
        if (engine == null) continue;
        await engine.controller.setSize(
          width: cycles.isEven ? 480 : 640,
          height: cycles.isEven ? 270 : 360,
          force: true,
        );
        resizeOperations++;
      }
      if (cycles % 10 == 0) {
        await multiview.setLayout(MultiviewLayout.dual);
        await multiview.setLayout(MultiviewLayout.quad);
        await multiview.assign(2, _room('c'));
        await multiview.assign(3, _room('d'));
        await _until(() => multiview!.cells.every((cell) => cell.playing));
      }
      await multiview.setMixAudio(enabled: cycles.isEven);
      await Future<void>.delayed(const Duration(seconds: 1));
      if (sessions.any((s) => s.state.status == PlaybackStatus.error)) {
        throw StateError('Native playback entered an error state');
      }
      cycles++;
    }
  } on Object catch (error) {
    failure = error.toString();
  } finally {
    ticker.cancel();
    runApp(const SizedBox.shrink());
    await Future<void>.delayed(const Duration(seconds: 1));
    await multiview?.retirement;
    final proof = {
      'passed': failure == null && cycles > 0 && sessions.isEmpty,
      'failure': failure,
      'source_commit': const String.fromEnvironment('PURELIVE_SOURCE_COMMIT'),
      'elapsed_ms': watch.elapsedMilliseconds,
      'cycles': cycles,
      'interrupted_recording': recordingRecovery,
      'resize_operations': resizeOperations,
      'sessions_created': created,
      'sessions_retired': retired,
      'remaining_sessions': sessions.length,
      'windows_editor_focus_and_native_ime_verified': editorVerified,
      'rss_bytes': ProcessInfo.currentRss,
      'peak_rss_bytes': ProcessInfo.maxRss,
      'generated_media_only': true,
      'physical_device_used': false,
    };
    await File('${root.path}/result.json').writeAsString(jsonEncode(proof));
    await server.close(force: true);
    await services.close();
    exit(proof['passed'] == true ? 0 : 1);
  }
}

List<T> _widgets<T extends Widget>() {
  final result = <T>[];
  void visit(Element element) {
    final widget = element.widget;
    if (widget is T) result.add(widget);
    element.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  return result;
}

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('Native readiness timed out');
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}
