import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/fonts.dart';

import 'support.dart';

Uint8List fontBytes([int marker = 1]) {
  final bytes = Uint8List(64);
  final data = ByteData.sublistView(bytes)
    ..setUint32(0, 0x00010000)
    ..setUint16(4, 1);
  bytes.setRange(12, 16, ascii.encode('name'));
  data
    ..setUint32(20, 28)
    ..setUint32(24, 36);
  bytes[63] = marker;
  return bytes;
}

void main() {
  late Directory temp;
  late FontLibrary library;
  final registered = <String>[];
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('purelive-local-font-');
    registered.clear();
    library = FontLibrary(
      root: Directory(p.join(temp.path, 'managed')),
      http: NoNetworkHttp(),
      manifest: () async => '[]',
      register: (name, fonts) async {
        await Future.wait(fonts);
        registered.add(name);
      },
    );
  });
  tearDown(() async {
    library.dispose();
    expect(p.isWithin(Directory.systemTemp.absolute.path, temp.absolute.path), isTrue);
    await temp.delete(recursive: true);
  });
  test(
    'imports a copied font, deduplicates content, and survives removing the selected source and restarting',
    () async {
      final source = File(p.join(temp.path, '我的字体.ttf'))..writeAsBytesSync(fontBytes());
      final first = await library.importLocal(source);
      expect(first.duplicate, isFalse);
      expect(first.family.local, isTrue);
      expect(first.family.name, '我的字体');
      expect(library.isDownloaded(first.family.id), isTrue);
      final second = await library.importLocal(source, fileName: 'different-name.otf');
      expect(second.duplicate, isTrue);
      expect(second.family.id, first.family.id);
      await source.delete();
      final restarted = FontLibrary(
        root: library.root,
        http: NoNetworkHttp(),
        manifest: () async => '[]',
        register: (_, fonts) async {
          await Future.wait(fonts);
        },
      );
      try {
        expect((await restarted.families()).single.name, '我的字体');
        expect(await restarted.load(first.family.id), isTrue);
        final metadata = File(p.join(library.folderOf(first.family.id).path, 'family.json')).readAsStringSync();
        expect(metadata, isNot(contains(source.path)));
      } finally {
        restarted.dispose();
      }
    },
  );
  test('simultaneous imports through two library instances keep one complete family', () async {
    final source = File(p.join(temp.path, 'shared.ttf'))..writeAsBytesSync(fontBytes());
    final other = FontLibrary(root: library.root, http: NoNetworkHttp(), manifest: () async => '[]');
    try {
      final results = await Future.wait([
        library.importLocal(source),
        other.importLocal(source),
        library.importLocal(source),
      ]);
      expect(results.where((r) => !r.duplicate), hasLength(1));
      expect(await library.families(), hasLength(1));
      expect(library.filesOf(results.first.family.id), hasLength(1));
    } finally {
      other.dispose();
    }
  });
  test('keeps app/danmaku choices independent and deletion resets both active uses', () async {
    final store = await LiveStore.memory(cipher: FakeCipher());
    try {
      final source = File(p.join(temp.path, 'local.ttf'))..writeAsBytesSync(fontBytes());
      final result = await library.importLocal(source);
      expect(store.settings.get(Settings.fontFamilyName), 'Default');
      await store.settings.set(Settings.fontFamilyName, result.family.id);
      await library.restore(store.settings);
      expect(registered, contains(result.family.id));
      expect(store.settings.get(Settings.danmakuFontFamilyName), 'Default');
      await store.settings.set(Settings.danmakuFontFamilyName, result.family.id);
      expect(await library.delete(result.family.id, store.settings), isTrue);
      expect(await library.families(), isEmpty);
      expect(store.settings.get(Settings.fontFamilyName), 'Default');
      expect(store.settings.get(Settings.danmakuFontFamilyName), 'Default');
      expect(library.registered, isNot(contains(result.family.id)));
    } finally {
      await store.close();
    }
  });
  test('rejects renamed non-fonts, truncated tables, unsupported extensions and oversized sparse files', () async {
    final invalid = File(p.join(temp.path, 'bad.ttf'))..writeAsStringSync('not a font, not executable');
    await expectLater(
      library.importLocal(invalid),
      throwsA(isA<FontImportException>().having((e) => e.failure, 'failure', FontImportFailure.invalid)),
    );
    invalid.writeAsBytesSync(fontBytes().sublist(0, 20));
    await expectLater(library.importLocal(invalid), throwsA(isA<FontImportException>()));
    final unsupported = File(p.join(temp.path, 'font.zip'))..writeAsBytesSync(fontBytes());
    await expectLater(
      library.importLocal(unsupported),
      throwsA(isA<FontImportException>().having((e) => e.failure, 'failure', FontImportFailure.unsupported)),
    );
    final large = File(p.join(temp.path, 'large.ttf'));
    large.openSync(mode: FileMode.write)
      ..truncateSync(maxLocalFontBytes + 1)
      ..closeSync();
    await expectLater(
      library.importLocal(large),
      throwsA(isA<FontImportException>().having((e) => e.failure, 'failure', FontImportFailure.tooLarge)),
    );
    expect(await library.families(), isEmpty);
    expect(library.root.listSync().whereType<Directory>(), isEmpty);
  });
  test('does not follow a corrupted catalog path outside the managed root', () async {
    final id = 'localfont_${'a' * 64}';
    final directory = Directory(p.join(library.root.path, id))..createSync(recursive: true);
    File(p.join(directory.path, 'family.json'))
        .writeAsStringSync(jsonEncode({'version': 1, 'name': 'unsafe', 'file': '../../original.ttf'}));
    final original = File(p.join(temp.path, 'original.ttf'))..writeAsBytesSync(fontBytes());
    expect(await library.families(), isEmpty);
    expect(library.filesOf(id), isEmpty);
    expect(original.readAsBytesSync(), fontBytes());
  });
}
