import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:live_player/live_player.dart';
import 'package:media_kit/media_kit.dart' as kit;

/// Manual native acceptance. Only an explicitly named private Pulse server
/// and generated local media qualify; never route this test to host speakers.
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  const media = String.fromEnvironment('PURELIVE_AUDIO_FIXTURE');
  const output = String.fromEnvironment('PURELIVE_AUDIO_PROOF');
  final server = Platform.environment['PULSE_SERVER'] ?? '';
  if (!Platform.isLinux || !server.contains('purelive266') || media.isEmpty || output.isEmpty) {
    throw StateError('Provide isolated Linux audio server, generated media and output directory');
  }
  final forced = arguments.contains('--force-old-alsa');
  final root = Directory('$output/${forced ? 'old-alsa' : 'native-default'}');
  await root.create(recursive: true);
  runApp(const Directionality(textDirection: TextDirection.ltr, child: SizedBox.shrink()));
  MpvEngine? engine;
  final proof = <String, Object?>{
    'source_commit': const String.fromEnvironment('PURELIVE_SOURCE_COMMIT'),
    'forced_old_alsa': forced,
    'private_audio_server': true,
    'generated_media_only': true,
  };
  try {
    engine = await MpvEngine.create(
      config: forced
          ? const MpvEngineConfig(
              platform: MpvPlatform.linux,
              customOutput: true,
              videoOutputDriver: 'libmpv',
              audioOutputDriver: 'alsa',
            )
          : const MpvEngineConfig(platform: MpvPlatform.linux),
    );
    await engine.setVolume(1);
    final native = engine.player.platform! as kit.NativePlayer;
    await engine.open(EngineMedia(uri: File(media).uri));
    final outputs = <String>{};
    var position = Duration.zero;
    for (var step = 0; step < 8; step++) {
      try {
        final value = await native.getPropertyAsync('current-ao');
        if (value.isNotEmpty) outputs.add(value);
      } on Object {
        /* An unavailable output is evidence, not a fallback. */
      }
      if (engine.player.state.position > position) position = engine.player.state.position;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    proof.addAll({
      'outputs': outputs.toList(),
      'position_ms': position.inMilliseconds,
      'volume': engine.player.state.volume,
      'passed': !forced && outputs.contains('pulse') && position > Duration.zero,
    });
  } on Object catch (error) {
    proof.addAll({'passed': false, 'error_type': error.runtimeType.toString()});
  } finally {
    await engine?.dispose();
    await File('${root.path}/result.json').writeAsString(jsonEncode(proof), flush: true);
    exit(0);
  }
}
