// Generated-media integration probe for issue #49. Run only in v4dev with
// an owned emulator; no account, production store or external server is used.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

final _label = ValueNotifier<String>('正在准备本地播放恢复验证');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = Directory('${Directory.systemTemp.path}/purelive-issue49');
  await root.create(recursive: true);
  final fixture = File('${Directory.systemTemp.path}/issue49-fixture.mp4');
  final stages = <Map<String, Object?>>[];
  final errors = <String>[];
  final requests = <String>[];
  final result = <String, Object?>{
    'platform': Platform.operatingSystem,
    'generated_media_only': true,
    'passed': false,
    'stages': stages,
    'native_errors': errors,
    'requests': requests,
  };
  Future<void> save() async {
    final tmp = File('${root.path}/result.tmp');
    await tmp.writeAsString(jsonEncode(result), flush: true);
    await tmp.rename('${root.path}/result.json');
  }

  HttpServer? server;
  PlaybackSession? session;
  final engines = <MpvEngine>[];
  final subscriptions = <StreamSubscription<Object?>>[];
  Future<void> sample(String phase) async {
    result['phase'] = phase;
    final engine = session?.engine;
    final properties = <String, String>{};
    if (engine is MpvEngine && engine.player.platform is NativePlayer) {
      final native = engine.player.platform! as NativePlayer;
      for (final key in ['core-idle', 'idle-active', 'pause', 'vo', 'vid', 'aid', 'hwdec', 'wid', 'track-list/count']) {
        try {
          properties[key] = await native.getPropertyAsync(key);
        } on Object catch (error) {
          properties[key] = error.runtimeType.toString();
        }
      }
      stages.add({
        'phase': phase,
        'engine_index': engines.indexOf(engine),
        'status': session!.state.status.name,
        'position_ms': engine.player.state.position.inMilliseconds,
        'video_w': engine.player.state.videoParams.w,
        'video_h': engine.player.state.videoParams.h,
        'audio_rate': engine.player.state.audioParams.sampleRate,
        'texture_id': (await engine.controller.platform.future).id.value,
        'properties': properties,
      });
    }
    await save();
    debugPrint('ISSUE49_PHASE $phase');
  }

  Future<void> healthy(String phase) async {
    final clock = Stopwatch()..start();
    Duration? previous;
    var advances = 0;
    while (clock.elapsed < const Duration(seconds: 20)) {
      final engine = session!.engine;
      if (engine is MpvEngine) {
        final state = engine.player.state;
        if (previous != null && state.position > previous && (state.videoParams.w ?? 0) > 0) advances++;
        previous = state.position;
        if (advances >= 3) {
          _label.value = '正在核对恢复后的测试画面';
          await sample(phase);
          final frame = await engine.player.screenshot().timeout(const Duration(seconds: 5));
          if (frame != null) await File('${root.path}/$phase-native.jpg').writeAsBytes(frame);
          await Future<void>.delayed(const Duration(seconds: 5));
          return;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await sample('$phase-timeout');
    throw StateError('No sustained native video progress in $phase');
  }

  try {
    if (!Platform.isAndroid) throw StateError('This fixture is an Android integration probe');
    if (!fixture.existsSync()) throw StateError('Install generated issue49-fixture.mp4 in v4dev cache first');
    final length = await fixture.length();
    server = (await HttpServer.bind(InternetAddress.loopbackIPv4, 0))
      ..listen((request) async {
        final response = request.response;
        if (requests.length < 100) requests.add('${request.method} ${request.uri.path}');
        try {
          if (request.uri.path == '/missing') {
            response.statusCode = HttpStatus.notFound;
            return;
          }
          if (request.uri.path == '/hang') {
            await Future<void>.delayed(const Duration(seconds: 40));
            response.statusCode = HttpStatus.serviceUnavailable;
            return;
          }
          final range = request.headers.value(HttpHeaders.rangeHeader);
          final match = range == null ? null : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
          var start = 0;
          var end = length - 1;
          if (range != null) {
            if (match == null) {
              response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
              return;
            }
            start = int.parse(match.group(1)!);
            if (match.group(2)!.isNotEmpty) end = int.parse(match.group(2)!);
            if (end >= length) end = length - 1;
            if (start > end) {
              response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
              return;
            }
            response.statusCode = HttpStatus.partialContent;
            response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
          }
          response
            ..headers.contentType = ContentType('video', 'mp4')
            ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
            ..contentLength = end - start + 1;
          if (request.method != 'HEAD') await response.addStream(fixture.openRead(start, end + 1));
        } on Object {
          // A retired local media request is expected to disconnect.
        } finally {
          await response.close().catchError((Object _) {});
        }
      });
    session = PlaybackSession(
      engine: () async {
        final engine = await MpvEngine.create(
          config: const MpvEngineConfig(hardwareDecoding: false),
          onBufferingSnapshot: (line) => debugPrint('ISSUE49_NATIVE $line'),
        );
        engines.add(engine);
        subscriptions.add(
          engine.player.stream.log.listen((line) {
            if (line.level == 'error' && errors.length < 80) errors.add('${line.prefix}: ${line.text}');
            debugPrint('ISSUE49_MPV ${line.level} ${line.prefix}: ${line.text}');
          }),
        );
        return engine;
      },
      opener: MediaOpener(),
    );
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ValueListenableBuilder(valueListenable: _label, builder: (_, text, _) => Text(text)),
              Expanded(child: LiveVideoView(session: session, keepScreenOn: false)),
            ],
          ),
        ),
      ),
    );
    final base = 'http://127.0.0.1:${server.port}';
    PlaybackRequest request(String path) => PlaybackRequest(
      site: 'fixture',
      plan: PlaybackPlan.of(LivePlayUrlResolution.lines([LivePlayLine('$base/$path')])),
      volume: 0,
    );
    await save();
    await session.open(request('good.mp4')).timeout(const Duration(seconds: 25));
    await healthy('cold-good');
    for (final failed in ['missing', 'hang', 'missing']) {
      _label.value = '正在验证失败后返回正常视频：$failed';
      await session.open(request(failed)).timeout(const Duration(seconds: 25));
      await Future<void>.delayed(const Duration(seconds: 5));
      await sample('after-$failed');
      await session.open(request('good.mp4')).timeout(const Duration(seconds: 25));
      await healthy('return-from-$failed-${stages.length}');
    }
    _label.value = '正在验证缓冲恢复耗尽后返回正常视频';
    await session.open(request('hang')).timeout(const Duration(seconds: 25));
    await Future<void>.delayed(const Duration(seconds: 27));
    await sample('long-stall');
    await session.open(request('good.mp4')).timeout(const Duration(seconds: 25));
    await healthy('return-after-long-stall');
    _label.value = '正在验证连接期间手动切换线路';
    await session
        .open(
          PlaybackRequest(
            site: 'fixture',
            plan: PlaybackPlan.of(
              LivePlayUrlResolution.lines([LivePlayLine('$base/hang'), LivePlayLine('$base/good.mp4')]),
            ),
            volume: 0,
          ),
        )
        .timeout(const Duration(seconds: 25));
    await Future<void>.delayed(const Duration(seconds: 3));
    await session.selectLine(1).timeout(const Duration(seconds: 25));
    await healthy('manual-line-after-hang');
    _label.value = '正在核对恢复后暂停保持';
    await session.pause().timeout(const Duration(seconds: 5));
    final pausedEngine = session.engine! as MpvEngine;
    final pausedPosition = pausedEngine.player.state.position;
    final creationsBeforePause = engines.length;
    await Future<void>.delayed(const Duration(seconds: 13));
    await sample('manual-pause-held');
    if (!identical(session.engine, pausedEngine) ||
        engines.length != creationsBeforePause ||
        pausedEngine.player.state.playing ||
        (pausedEngine.player.state.position - pausedPosition).abs() > const Duration(milliseconds: 300)) {
      throw StateError('Manual pause was reversed after recovery');
    }
    await session.resume().timeout(const Duration(seconds: 5));
    await healthy('manual-resume');
    result['passed'] = true;
    result['engine_creations'] = engines.length;
    result['phase'] = 'completed';
    _label.value = '本地播放恢复验证结束';
  } on Object catch (error, stack) {
    result['error'] = error.toString();
    result['stack'] = stack.toString();
    _label.value = '本地播放恢复验证失败，结果已保留';
  } finally {
    await save();
    debugPrint('ISSUE49_RESULT ${jsonEncode(result)}');
    // Keep the final frame visible for scoped native screenshot inspection.
    // The harness stops only its own package after collecting the result.
  }
}
