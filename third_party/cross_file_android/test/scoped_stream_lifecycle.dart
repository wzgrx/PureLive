import 'dart:math';
import 'dart:typed_data';

import 'package:cross_file_android/src/android_library.g.dart' as android;
import 'package:cross_file_android/src/android_scoped_storage_cross_file.dart';
import 'package:cross_file_platform_interface/cross_file_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

void runScopedStreamLifecycleTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const params = PlatformScopedStorageXFileCreationParams(
    uri: 'content://generated/file',
  );
  AndroidScopedStorageXFile file(_Input input) =>
      AndroidScopedStorageXFile(params, contentResolver: _Resolver(input));

  test('Android scoped full streams close once after EOF', () async {
    final input = _Input(List<int>.generate(9000, (i) => i % 251));
    final result = await file(
      input,
    ).openRead().expand((chunk) => chunk).toList();
    expect(result, input.bytes);
    expect(input.closed, 1);
    expect(input.requests.every((count) => count <= 4096), isTrue);
  });
  test(
    'Android scoped range closes at its exclusive boundary without reading ahead',
    () async {
      final input = _Input(List<int>.generate(20, (i) => i));
      expect(
        await file(input).openRead(2, 5).expand((chunk) => chunk).toList(),
        [2, 3, 4],
      );
      expect(input.requests, [3]);
      expect(input.closed, 1);
    },
  );
  test(
    'Android scoped canceled subscriptions close their native stream',
    () async {
      final input = _Input(List<int>.generate(9000, (i) => i % 251));
      await file(input).openRead().take(1).drain<void>();
      expect(input.closed, 1);
      expect(input.requests, [4096]);
    },
  );
  test('Android scoped native read errors still close the stream', () async {
    final input = _Input([1, 2, 3])..failRead = true;
    await expectLater(file(input).openRead().drain<void>(), throwsStateError);
    expect(input.closed, 1);
  });
  test('Android scoped bulk reads close on success and failure', () async {
    final success = _Input([1, 2, 3]);
    expect(await file(success).readAsBytes(), [1, 2, 3]);
    expect(success.closed, 1);
    final failure = _Input([1, 2, 3])..failRead = true;
    await expectLater(file(failure).readAsBytes(), throwsStateError);
    expect(failure.closed, 1);
  });
  test('Android scoped partial native skips preserve offsets', () async {
    final input = _Input(List<int>.generate(12, (i) => i))..skipLimit = 1;
    expect(await file(input).openRead(5, 8).expand((chunk) => chunk).toList(), [
      5,
      6,
      7,
    ]);
    expect(input.closed, 1);
  });
  test(
    'Android scoped non-seekable streams discard bytes before reading their range',
    () async {
      final input = _Input(List<int>.generate(12, (i) => i))..skipLimit = 0;
      expect(
        await file(input).openRead(5, 8).expand((chunk) => chunk).toList(),
        [5, 6, 7],
      );
      expect(input.closed, 1);
    },
  );
  test(
    'Android scoped seeks beyond EOF close without returning data',
    () async {
      final input = _Input([1, 2, 3])..skipLimit = 0;
      expect(await file(input).openRead(20).toList(), isEmpty);
      expect(input.closed, 1);
    },
  );
}

class _Resolver extends android.ContentResolver {
  _Resolver(this.input) : super.pigeon_detached();
  final _Input input;
  @override
  Future<android.InputStream?> openInputStream(String uri) async => input;
}

class _Input extends android.InputStream {
  _Input(this.bytes) : super.pigeon_detached();
  final List<int> bytes;
  final requests = <int>[];
  int position = 0;
  int closed = 0;
  int skipLimit = 100000;
  bool failRead = false;
  @override
  Future<Uint8List> readBytes(int maxLength) async {
    if (failRead) throw StateError('generated native read error');
    requests.add(maxLength);
    final end = min(bytes.length, position + maxLength);
    final result = Uint8List.fromList(bytes.sublist(position, end));
    position = end;
    return result;
  }

  @override
  Future<Uint8List> readAllBytes() async {
    if (failRead) throw StateError('generated native read error');
    return Uint8List.fromList(bytes);
  }

  @override
  Future<int> skip(int n) async {
    final skipped = min(min(n, skipLimit), bytes.length - position);
    position += skipped;
    return skipped;
  }

  @override
  Future<void> close() async => closed++;
}
