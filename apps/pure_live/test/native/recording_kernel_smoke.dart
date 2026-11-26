// Cloud-only native check: local PCM input, no platform URLs or user data.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/platform/recording_platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  final root = Directory('${Directory.systemTemp.path}/purelive-recording-kernel-smoke');
  await root.create(recursive: true);
  final result = <String, Object?>{'operating_system': Platform.operatingSystem, 'available': platformHasFfmpeg};
  try {
    if (!platformHasFfmpeg) throw StateError('The shipped native bundle is disabled');
    final input = File('${root.path}/silence.pcm');
    final output = File('${root.path}/silence.wav');
    await input.writeAsBytes(Uint8List(16000), flush: true);
    final execution = await FfmpegKitRunner()
        .start([
          '-hide_banner',
          '-nostdin',
          '-y',
          '-f',
          's16le',
          '-ar',
          '8000',
          '-ac',
          '1',
          '-i',
          input.path,
          '-t',
          '1',
          '-c:a',
          'pcm_s16le',
          output.path,
        ])
        .timeout(const Duration(seconds: 45));
    final code = await execution.exitCode.timeout(const Duration(seconds: 45));
    final bytes = await output.readAsBytes();
    final wave =
        bytes.length > 44 &&
        ascii.decode(bytes.sublist(0, 4)) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12)) == 'WAVE';
    final local = XFile.fileSystem(path: output.path);
    final localBytes = await local.readAsBytes();
    final streamed = await local.openRead().expand((chunk) => chunk).toList();
    final localPassed =
        await local.exists() &&
        await local.length() == bytes.length &&
        await local.name() == 'silence.wav' &&
        _sameBytes(localBytes, bytes) &&
        _sameBytes(streamed, bytes);
    var scopedPassed = true;
    String? scopedUri;
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      if (Platform.isAndroid) {
        final temp = await getTemporaryDirectory();
        final shared = File('${temp.path}/share_plus/purelive-generated-file-probe.wav');
        await shared.parent.create(recursive: true);
        await shared.writeAsBytes(bytes, flush: true);
        const package = String.fromEnvironment('PURELIVE_PROBE_PACKAGE', defaultValue: 'com.mystyle.purelive.v4dev');
        scopedUri = 'content://$package.flutter.share_provider/cache/purelive-generated-file-probe.wav';
      } else {
        scopedUri = output.uri.toString();
      }
      final scoped = XFile.scopedStorage(uri: scopedUri) as ScopedStorageXFile;
      try {
        final scopedBytes = await scoped.openRead().expand((chunk) => chunk).toList();
        final expectedName = Platform.isAndroid ? 'purelive-generated-file-probe.wav' : 'silence.wav';
        scopedPassed =
            _sameBytes(scopedBytes, bytes) &&
            await scoped.length() == bytes.length &&
            await scoped.name() == expectedName &&
            await scoped.canRead();
      } finally {
        await scoped.dispose();
      }
    }
    result.addAll({
      'exit_code': code,
      'bytes': bytes.length,
      'riff_wave': wave,
      'file_interop': {
        'local_file_passed': localPassed,
        'scoped_supported': scopedUri != null,
        'scoped_passed': scopedPassed,
        'scoped_uri_scheme': scopedUri == null ? null : Uri.parse(scopedUri).scheme,
      },
      'passed': code == 0 && wave && localPassed && scopedPassed,
    });
  } on Object catch (error, stack) {
    result.addAll({'passed': false, 'error': error.toString(), 'stack': stack.toString()});
  }
  await File('${root.path}/result.json').writeAsString(jsonEncode(result), flush: true);
}

bool _sameBytes(List<int> left, List<int> right) =>
    left.length == right.length && Iterable<int>.generate(left.length).every((i) => left[i] == right[i]);
