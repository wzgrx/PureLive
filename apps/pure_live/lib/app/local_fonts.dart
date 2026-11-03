part of 'fonts.dart';

/// Upper bound for one user-selected font; cloud fonts retain their own rules.
const int maxLocalFontBytes = 64 * 1024 * 1024;

/// Maximum number of imported families retained by the local catalog.
const int maxLocalFonts = 64;

/// User-facing categories without exposing filesystem paths in an error.
enum FontImportFailure {
  /// Only TTF and OTF files are accepted.
  unsupported,

  /// The selected file exceeds the memory and disk bound.
  tooLarge,

  /// The font header or table bounds are invalid.
  invalid,

  /// A previous copy needs explicit removal before reimporting.
  damagedExisting,

  /// The local catalog has reached its bound.
  tooMany,

  /// Reading or storing the selected file failed.
  io,
}

/// A failed import leaves the original and the current font selection intact.
final class FontImportException implements Exception {
  /// Creates a bounded failure category.
  const new(this.failure);

  /// Why the import failed.
  final FontImportFailure failure;
}

/// A managed family and whether its identical bytes were already imported.
typedef FontImportResult = ({FontFamily family, bool duplicate});

bool _isLocalFontId(String id) => RegExp(r'^localfont_[0-9a-f]{64}$').hasMatch(id);

final Map<String, Future<void>> _localFontQueues = {};

Directory _localFontChild(Directory root, String name) {
  final parent = p.normalize(p.absolute(root.path));
  final target = p.normalize(p.join(parent, name));
  if (p.basename(name) != name || !p.isWithin(parent, target) || p.dirname(target) != parent) {
    throw const FontImportException(FontImportFailure.io);
  }
  if (FileSystemEntity.typeSync(target, followLinks: false) == FileSystemEntityType.link) {
    throw const FontImportException(FontImportFailure.io);
  }
  return Directory(target);
}

Future<T> _withLocalFontLock<T>(Directory root, Future<T> Function(Directory) action) async {
  await root.create(recursive: true);
  final managed = Directory(await root.resolveSymbolicLinks());
  final previous = _localFontQueues[managed.path] ?? Future<void>.value();
  final done = Completer<void>();
  _localFontQueues[managed.path] = done.future;
  RandomAccessFile? handle;
  try {
    await previous;
    handle = await File(p.join(managed.path, '.local-fonts.lock')).open(mode: FileMode.append);
    await handle.lock(FileLock.blockingExclusive);
    return await action(managed);
  } on FileSystemException {
    throw const FontImportException(FontImportFailure.io);
  } finally {
    try {
      await handle?.close();
    } finally {
      done.complete();
      if (identical(_localFontQueues[managed.path], done.future)) {
        unawaited(_localFontQueues.remove(managed.path));
      }
    }
  }
}

FontFamily? _readLocalFontFamily(Directory folder) {
  try {
    final id = p.basename(folder.path);
    if (!_isLocalFontId(id) ||
        FileSystemEntity.typeSync(folder.path, followLinks: false) != FileSystemEntityType.directory) {
      return null;
    }
    final meta = File(p.join(folder.path, 'family.json'));
    if (FileSystemEntity.typeSync(meta.path, followLinks: false) != FileSystemEntityType.file ||
        meta.lengthSync() > 4096) {
      return null;
    }
    final data = jsonDecode(meta.readAsStringSync());
    if (data is! Map ||
        data['version'] != 1 ||
        data['name'] is! String ||
        !const ['font.ttf', 'font.otf'].contains(data['file'])) {
      return null;
    }
    final name = data['name'] as String;
    if (name.isEmpty || name.runes.length > 80 || RegExp(r'[\x00-\x1f]').hasMatch(name)) return null;
    return FontFamily(id: id, name: name, files: ['$id/${data['file']}'], local: true);
  } on Object {
    return null;
  }
}

Future<List<FontFamily>> _readLocalFontFamilies(Directory root) async {
  if (!root.existsSync()) return const [];
  final families = <FontFamily>[];
  try {
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory || !_isLocalFontId(p.basename(entity.path))) continue;
      final family = _readLocalFontFamily(entity);
      if (family != null) families.add(family);
      if (families.length >= maxLocalFonts) break;
    }
  } on FileSystemException {
    /* Keep readable entries. */
  }
  families.sort((a, b) => a.name.compareTo(b.name));
  return families;
}

bool _validImportedFont(File file) {
  final size = file.lengthSync();
  if (size < 12 || size > maxLocalFontBytes) return false;
  final handle = file.openSync();
  try {
    final header = handle.readSync(12);
    final tag = String.fromCharCodes(header.take(4));
    if (!(header[0] == 0 && header[1] == 1 && header[2] == 0 && header[3] == 0) &&
        !const ['OTTO', 'true', 'typ1'].contains(tag)) {
      return false;
    }
    final count = ByteData.sublistView(header).getUint16(4);
    if (count == 0 || count > 4096 || 12 + count * 16 > size) return false;
    final tables = handle.readSync(count * 16);
    if (tables.length != count * 16) return false;
    final directory = ByteData.sublistView(tables);
    for (var i = 0; i < count; i++) {
      final offset = directory.getUint32(i * 16 + 8);
      final length = directory.getUint32(i * 16 + 12);
      if (offset > size || length > size - offset) return false;
    }
    return true;
  } finally {
    handle.closeSync();
  }
}

Future<void> _discardFontStage(Directory stage) async {
  if (!stage.existsSync() ||
      FileSystemEntity.typeSync(stage.path, followLinks: false) != FileSystemEntityType.directory) {
    return;
  }
  final entries = await stage.list(followLinks: false).toList();
  if (entries.any((e) => e is! File || !const ['font.ttf', 'font.otf', 'family.json'].contains(p.basename(e.path)))) {
    return;
  }
  for (final entry in entries) {
    await entry.delete();
  }
  await stage.delete();
}

Future<FontImportResult> _importLocalFont(Directory root, File source, String? pickedName) async {
  final original = p.basename(pickedName ?? source.path);
  final ext = p.extension(original).toLowerCase();
  if (!const ['.ttf', '.otf'].contains(ext)) throw const FontImportException(FontImportFailure.unsupported);
  if (await source.length() > maxLocalFontBytes) throw const FontImportException(FontImportFailure.tooLarge);
  final random = Random.secure();
  final stage = _localFontChild(
    root,
    '.localfont-import-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}.pending',
  );
  await stage.create();
  final file = File(p.join(stage.path, 'font$ext'));
  var committed = false;
  try {
    var bytes = 0;
    final sink = file.openWrite();
    try {
      await sink.addStream(
        source.openRead().timeout(const Duration(seconds: 30)).map((chunk) {
          bytes += chunk.length;
          if (bytes > maxLocalFontBytes) throw const FontImportException(FontImportFailure.tooLarge);
          return chunk;
        }),
      );
    } finally {
      await sink.close();
    }
    if (!_validImportedFont(file)) throw const FontImportException(FontImportFailure.invalid);
    final digest = (await crypto.sha256.bind(file.openRead()).first).toString();
    final id = 'localfont_$digest';
    final destination = _localFontChild(root, id);
    if (destination.existsSync()) {
      final existing = _readLocalFontFamily(destination);
      if (existing == null) throw const FontImportException(FontImportFailure.damagedExisting);
      final existingFile = File(p.join(destination.path, existing.fileNames.single));
      if (FileSystemEntity.typeSync(existingFile.path, followLinks: false) != FileSystemEntityType.file ||
          existingFile.lengthSync() > maxLocalFontBytes ||
          (await crypto.sha256.bind(existingFile.openRead()).first).toString() != digest) {
        throw const FontImportException(FontImportFailure.damagedExisting);
      }
      return (family: existing, duplicate: true);
    }
    if ((await _readLocalFontFamilies(root)).length >= maxLocalFonts) {
      throw const FontImportException(FontImportFailure.tooMany);
    }
    final clean = p.basenameWithoutExtension(original).replaceAll(RegExp(r'[\x00-\x1f]'), '').trim();
    final name = String.fromCharCodes((clean.isEmpty ? 'Font' : clean).runes.take(80));
    await File(p.join(stage.path, 'family.json'))
        .writeAsString(jsonEncode({'version': 1, 'name': name, 'file': 'font$ext'}));
    // Both paths are direct children of the resolved managed font directory.
    _localFontChild(root, p.basename(stage.path));
    _localFontChild(root, id);
    await stage.rename(destination.path);
    committed = true;
    return (family: FontFamily(id: id, name: name, files: ['$id/font$ext'], local: true), duplicate: false);
  } on FileSystemException {
    throw const FontImportException(FontImportFailure.io);
  } on TimeoutException {
    throw const FontImportException(FontImportFailure.io);
  } finally {
    if (!committed) {
      try {
        await _discardFontStage(stage);
      } on FileSystemException {
        /* Preserve a failed cleanup for inspection. */
      }
    }
  }
}
