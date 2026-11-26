import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'package:cross_file_io/cross_file_io.dart';
import 'package:cross_file_platform_interface/cross_file_platform_interface.dart';
import 'package:file_picker_darwin/file_picker_darwin.dart';
import 'package:file_picker_linux/file_picker_linux.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:share_plus_platform_interface/method_channel/method_channel_share.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart' hide XFile;
import 'package:windows_file_picker/windows_file_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late _Files files;
  late CrossFilePlatform? previousFiles;
  late PathProviderPlatform previousPaths;
  Map<Object?, Object?>? payload;
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('purelive-file-migration-');
    previousFiles = CrossFilePlatform.instance;
    previousPaths = PathProviderPlatform.instance;
    files = _Files();
    CrossFilePlatform.instance = files;
    PathProviderPlatform.instance = _Paths(folder.path);
    payload = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannelShare.channel,
      (call) async {
        payload = call.arguments as Map<Object?, Object?>;
        return 'generated.share.target';
      },
    );
  });
  tearDown(() async {
    CrossFilePlatform.instance = previousFiles;
    PathProviderPlatform.instance = previousPaths;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannelShare.channel,
      null,
    );
    await folder.delete(recursive: true);
  });

  test('picked local files retain paths, zero sizes, and byte streams', () async {
    final source = File('${folder.path}/generated 文档.txt');
    await source.writeAsString('generated fixture');
    final picked = [
      AndroidPlatformFile.fromMap({'path': source.path, 'name': 'generated 文档.txt'}),
      DarwinPlatformFile.fromMap({'path': source.path, 'name': 'generated 文档.txt'}),
      LinuxPlatformFile.fromPath(source.path),
      WindowsPlatformFile.fromPath(source.path),
    ];
    for (final file in picked) {
      expect(file.xFile, isA<FileSystemXFile>());
      expect((file.xFile as FileSystemXFile).path, source.path);
      expect(await file.readAsBytes(), utf8.encode('generated fixture'));
      expect(await file.readAsByteStream().expand((chunk) => chunk).toList(), utf8.encode('generated fixture'));
    }
    final empty = File('${folder.path}/empty.txt');
    await empty.writeAsBytes([]);
    expect(await LinuxPlatformFile.fromPath(empty.path).length(), 0);
    expect(LinuxPlatformFile.fromPath(empty.path, bytes: Uint8List(0)).lengthSync(), 0);
    expect(
      (WindowsPlatformFile.fromPath(r'C:\generated\file.txt').xFile as FileSystemXFile).path,
      r'C:\generated\file.txt',
    );
  });

  test('Android content URIs remain scoped resources and stream readable data', () async {
    const uri = 'content://generated.documents/document/report';
    final picked = AndroidPlatformFile.fromMap({'path': uri, 'name': 'report.txt', 'size': 4});
    expect(picked.xFile, isA<ScopedStorageXFile>());
    expect(picked.xFile.uri, uri);
    expect(picked.lengthSync(), 4);
    expect(await picked.readAsByteStream().expand((chunk) => chunk).toList(), [1, 2, 3, 4]);
  });

  test('Apple photo references still reject reads without a copied file', () async {
    final picked = DarwinPlatformFile.fromMap({'uri': 'ph:generated', 'name': 'generated.jpg'});
    expect(await picked.length(), isNull);
    await expectLater(picked.readAsBytes(), throwsUnsupportedError);
  });

  test('sharing a local log keeps its path and MIME type', () async {
    final source = File('${folder.path}/log.txt');
    await source.writeAsString('generated log');
    final result = await MethodChannelShare().share(ShareParams(files: [XFile.fileSystem(path: source.path)]));
    expect(result.status, ShareResultStatus.success);
    expect(payload?['paths'], [source.path]);
    expect(payload?['mimeTypes'], ['text/plain']);
  });

  test('sharing a scoped document uses streamed bytes and a safe file name', () async {
    files.name = '../../generated.txt';
    final result = await MethodChannelShare().share(
      ShareParams(files: [XFile.scopedStorage(uri: 'content://generated/document')]),
    );
    expect(result.status, ShareResultStatus.success);
    final path = (payload!['paths']! as List).single as String;
    expect(File(path).uri.pathSegments.last, 'generated.txt');
    expect(path.startsWith(folder.path), isTrue);
    expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
    expect(payload!['mimeTypes'], ['text/plain']);
    expect(files.opened, isTrue);
  });

  test('scoped names can be absent or overridden', () async {
    files.name = null;
    await MethodChannelShare().share(ShareParams(files: [XFile.scopedStorage(uri: 'content://generated/document')]));
    expect((payload!['paths']! as List).single, endsWith('.bin'));
    await MethodChannelShare().share(
      ShareParams(
        files: [XFile.scopedStorage(uri: 'content://generated/document')],
        fileNameOverrides: [r'..\export.txt'],
      ),
    );
    expect((payload!['paths']! as List).single, endsWith('export.txt'));
  });

  test('failed scoped streams leave no partial share and do not invoke native UI', () async {
    files.fail = true;
    await expectLater(
      MethodChannelShare().share(ShareParams(files: [XFile.scopedStorage(uri: 'content://generated/failure')])),
      throwsStateError,
    );
    expect(payload, isNull);
    expect(await folder.list().toList(), isEmpty);
  });

  test('native share dismissal keeps its established result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannelShare.channel,
      (call) async => '',
    );
    final result = await MethodChannelShare().share(ShareParams(text: 'generated text'));
    expect(result.status, ShareResultStatus.dismissed);
  });
}

final class _Paths extends PathProviderPlatform {
  new(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

final class _Files extends CrossFileIO {
  String? name = 'generated.txt';
  bool opened = false;
  bool fail = false;
  @override
  PlatformScopedStorageXFile createPlatformScopedStorageXFile(PlatformScopedStorageXFileCreationParams params) =>
      _Scoped(params, this);
}

final class _Scoped extends PlatformScopedStorageXFile {
  new(super.params, this.files) : super.implementation();
  final _Files files;
  @override
  Future<bool> canRead() async => true;
  @override
  Future<bool> exists() async => true;
  @override
  Future<DateTime?> lastModified() async => null;
  @override
  Future<int?> length() async => 4;
  @override
  Future<String?> name() async => files.name;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    files.opened = true;
    yield Uint8List.fromList([1, 2]);
    if (files.fail) throw StateError('generated stream failure');
    yield Uint8List.fromList([3, 4]);
  }

  @override
  Future<Uint8List> readAsBytes() => throw StateError('Scoped shares must stream, not buffer whole files');
  @override
  Future<String> readAsString({Encoding encoding = utf8}) async => '';
  @override
  Future<void> dispose() async {}
}
