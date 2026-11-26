import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';

final class _NoSecrets implements SecretCipher {
  @override
  Future<Uint8List> seal(String ref, String plain) => throw StateError('Generated media only');
  @override
  Future<String> open(String ref, Uint8List sealed) => throw StateError('Generated media only');
}

/// Manual native A/B on generated loopback HLS. The upstream injects a
/// segment response delay; no platform account or external URL is accepted.
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  const address = String.fromEnvironment('PURELIVE_HLS_FIXTURE');
  const output = String.fromEnvironment('PURELIVE_PROOF_DIR');
  final uri = Uri.parse(address);
  if (uri.scheme != 'http' || uri.host != '127.0.0.1' || output.isEmpty) {
    throw StateError('Provide an owned generated loopback fixture and proof directory');
  }
  final parallel = !arguments.contains('--serial-only');
  final root = Directory('$output/${parallel ? 'parallel' : 'serial'}');
  await root.create(recursive: true);
  final store = await LiveStore.memory(cipher: _NoSecrets());
  await DesktopShell.start(
    store,
    primary: false,
    dataRoot: root,
    instanceId: 'hls-jitter-${parallel ? 'parallel' : 'serial'}',
  );
  final engine = await MpvEngine.create();
  final opener = MediaOpener(prefetchLiveHls: parallel);
  final session = PlaybackSession(engine: () async => engine, opener: opener);
  runApp(
    MaterialApp(
      home: Scaffold(body: LiveVideoView(session: session, keepScreenOn: false)),
    ),
  );
  final watch = Stopwatch()..start();
  final samples = <Map<String, Object?>>[];
  var firstPlaying = false;
  var bufferingEpisodes = 0;
  var bufferingMs = 0;
  Duration? bufferingAt;
  final buffering = engine.player.stream.buffering.listen((waiting) {
    if (!firstPlaying) return;
    if (waiting && bufferingAt == null) {
      bufferingAt = watch.elapsed;
      bufferingEpisodes++;
    } else if (!waiting && bufferingAt != null) {
      bufferingMs += (watch.elapsed - bufferingAt!).inMilliseconds;
      bufferingAt = null;
    }
  });
  String? failure;
  try {
    await session.open(
      PlaybackRequest(
        site: 'soop',
        volume: 0,
        plan: PlaybackPlan(sources: const [LineSource(LivePlayLine(address, format: StreamFormat.hls))]),
      ),
    );
    final ready = watch.elapsed + const Duration(seconds: 30);
    while (!engine.player.state.playing || engine.player.state.position <= Duration.zero) {
      if (watch.elapsed > ready) throw StateError('Generated HLS did not start');
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    firstPlaying = true;
    final deadline = watch.elapsed + const Duration(seconds: 75);
    while (watch.elapsed < deadline) {
      final stats = await engine.readStats();
      samples.add({
        'elapsed_ms': watch.elapsedMilliseconds,
        'position_ms': engine.player.state.position.inMilliseconds,
        'buffering': engine.player.state.buffering,
        'cache_seconds': stats.bufferSeconds,
        'dropped_frames': stats.droppedFrames,
        'frame_revision': engine.controller.frameRevision.value,
      });
      await File('${root.path}/state.json').writeAsString(jsonEncode(samples.last), flush: true);
      if (session.state.status == PlaybackStatus.error) throw StateError('Native playback failed');
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } on Object catch (error) {
    failure = error.runtimeType.toString();
  } finally {
    if (bufferingAt != null) bufferingMs += (watch.elapsed - bufferingAt!).inMilliseconds;
    await buffering.cancel();
    runApp(const SizedBox.shrink());
    await Future<void>.delayed(const Duration(seconds: 1));
    await session.dispose();
    await opener.close();
    await DesktopShell.current?.dispose();
    await store.close();
    final proof = {
      'passed': failure == null && firstPlaying,
      'failure_type': failure,
      'source_commit': const String.fromEnvironment('PURELIVE_SOURCE_COMMIT'),
      'parallel_prefetch': parallel,
      'buffering_episodes_after_start': bufferingEpisodes,
      'buffering_ms_after_start': bufferingMs,
      'elapsed_ms': watch.elapsedMilliseconds,
      'samples': samples,
      'generated_media_only': true,
      'physical_device': false,
    };
    await File('${root.path}/result.json').writeAsString(jsonEncode(proof), flush: true);
    exit(proof['passed'] == true ? 0 : 1);
  }
}
