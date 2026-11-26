import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/platform/recording_platform.dart';

import 'recording_input.dart';

/// Uses generated media and the real recorder/native muxer. Fault injection
/// removes only this owned fixture's final journal row after cancellation,
/// matching the reported valid-raw/unflushed-row state, not a user recording.
Future<Map<String, Object?>> probeInterruptedRecording(Directory root) async {
  await root.create(recursive: true);
  final native = FfmpegKitRunner();
  final clip = File(p.join(root.path, 'generated.mp4'));
  await clip.writeAsBytes(base64Decode(recordingInputBase64), flush: true);
  final bytes = await clip.readAsBytes();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final response = request.response;
    try {
      if (request.uri.path != '/generated.mp4') {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final range = request.headers.value(HttpHeaders.rangeHeader);
      final match = range == null ? null : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
      final start = match == null ? 0 : int.parse(match.group(1)!);
      final end = match == null || match.group(2)!.isEmpty
          ? bytes.length - 1
          : int.parse(match.group(2)!).clamp(0, bytes.length - 1);
      if (start > end || start >= bytes.length || range != null && match == null) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        return;
      }
      if (range != null) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${bytes.length}');
      }
      response
        ..headers.contentType = ContentType('video', 'mp4')
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = end - start + 1;
      if (request.method != 'HEAD') response.add(bytes.sublist(start, end + 1));
    } on SocketException {
      // A manual cancellation closes only this generated input.
    } finally {
      await response.close().catchError((Object _) {});
    }
  });
  final injected = _UnflushedRunner(native, root);
  final source = _FileSite('http://127.0.0.1:${server.port}/generated.mp4');
  final recorder = Recorder(
    sites: (_) => source,
    ffmpeg: injected,
    storage: RecordStorage(defaultDirectory: () async => p.join(root.path, 'records'), configuredPath: () => ''),
    settings: () => RecordSettings(autoReconnect: false),
  );
  try {
    final task = (await recorder.addTask(source.room))!;
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    var bytes = 0;
    while (bytes == 0) {
      final path = task.outputDir;
      if (path != null && Directory(path).existsSync()) {
        for (final file in Directory(path).listSync(followLinks: false).whereType<File>()) {
          if (file.path.endsWith(SegmentClock.segmentSuffix)) bytes += file.lengthSync();
        }
      }
      if (bytes == 0) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError(
            'Native capture produced no segment: ${task.status.name} ${task.lastErrorStage} ${task.lastError}',
          );
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    await recorder.stopTask(task).timeout(const Duration(seconds: 60));
    final output = task.lastOutputPath == null ? null : File(task.lastOutputPath!);
    final committed = output != null && output.existsSync() && output.lengthSync() > 0;
    int? decodeCode;
    if (committed) {
      final decode = await native.start([
        '-hide_banner',
        '-nostdin',
        '-v',
        'error',
        '-i',
        output.path,
        '-f',
        'null',
        '-',
      ]);
      decodeCode = await decode.exitCode.timeout(const Duration(seconds: 45));
    }
    return {
      'passed':
          injected.injected &&
          committed &&
          decodeCode == 0 &&
          task.status == RecordStatus.stopped &&
          task.pendingAttempts.isEmpty,
      'injected_unflushed_last_row': injected.injected,
      'real_native_capture_bytes': bytes,
      'committed_mp4': committed,
      'decode_exit_code': decodeCode,
      'pending_attempts': task.pendingAttempts.length,
      'pending_open_tail_flags': task.pendingAttempts.map((a) => a.openTail).toList(),
      'last_error_stage': task.lastErrorStage,
      'last_error': task.lastError,
      'fixture_codec': 'h264',
      'task_status': task.status.name,
      'generated_media_only': true,
    };
  } finally {
    await recorder.dispose();
    await server.close(force: true);
  }
}

final class _FileSite extends LiveSite {
  new(this.url);
  final String url;
  LiveRoom get room => LiveRoom(platform: id, roomId: '1', nick: 'Native fixture', liveStatus: LiveStatus.live);
  @override
  String get id => 'fixture';
  @override
  String get name => 'Native fixture';
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async => room;
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => const [
    LivePlayQuality(quality: 'Native', id: 'original'),
  ];
  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [url];
}

final class _UnflushedRunner implements FfmpegRunner {
  new(this.inner, this.root);
  final FfmpegRunner inner;
  final Directory root;
  bool injected = false;
  @override
  Future<FfmpegExecution> start(List<String> arguments) async {
    final list = arguments.indexOf('-segment_list');
    if (list < 0) return await inner.start(arguments);
    final journal = File(arguments[list + 1]);
    if (!p.isWithin(root.absolute.path, journal.absolute.path)) throw StateError('Fixture journal escaped owned root');
    final realtime = List<String>.of(arguments)..insert(arguments.indexOf('-i'), '-re');
    return _UnflushedExecution(await inner.start(realtime), () async {
      if (journal.existsSync()) {
        await journal.writeAsString('', flush: true);
        injected = true;
      }
    });
  }
}

final class _UnflushedExecution implements FfmpegExecution {
  new(this.inner, Future<void> Function() inject) {
    _exit = inner.exitCode.then((code) async {
      if (_cancelled) await inject();
      return code;
    });
  }
  final FfmpegExecution inner;
  late final Future<int> _exit;
  bool _cancelled = false;
  @override
  Stream<String> get logs => inner.logs;
  @override
  Stream<FfmpegStatistics> get statistics => inner.statistics;
  @override
  Future<int> get exitCode => _exit;
  @override
  void cancel() {
    _cancelled = true;
    inner.cancel();
  }
}
