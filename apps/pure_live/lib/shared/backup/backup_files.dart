import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/shared/backup/backup_data.dart';

/// The name of a new backup file: 3.x's prefixes (`purelive_`,
/// `purelive_favorites_`) and date, the JSON gzipped (`<date>.json.gz`,
/// J03.1 — a full backup is megabytes of JSON and a few hundred KB
/// compressed). A data-only backup says so in its name
/// (`purelive_data_<date>.json.gz`), the sensitive flag stays out of it: the
/// file itself carries it.
String backupFileName(BackupScope scope, DateTime now, {BackupContents contents = BackupContents.settings}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final date = '${now.year}-${two(now.month)}-${two(now.day)}T${two(now.hour)}_${two(now.minute)}_${two(now.second)}';
  final prefix = scope == BackupScope.follows
      ? 'purelive_favorites'
      : contents == BackupContents.data
      ? 'purelive_data'
      : 'purelive';
  return '${prefix}_$date.json.gz';
}

/// The name of a scheduled WebDAV backup (J04.2): 3.x's prefixes stay, and
/// `auto` keeps retention from deleting a manual backup.
String autoBackupFileName(BackupScope scope, DateTime now) {
  final manual = backupFileName(scope, now);
  final prefix = scope == BackupScope.follows ? 'purelive_favorites' : 'purelive';
  return manual.replaceFirst('${prefix}_', '${prefix}_auto_');
}

/// Matches the files [autoBackupFileName] writes; manual `purelive_<date>`
/// files and renamed files do not match. A `.txt` or `.json` tail is a
/// scheduled backup written before the files were gzipped: retention still
/// counts it.
final RegExp _autoBackupName = RegExp(
  r'^purelive(?:_favorites)?_auto_(\d{4}-\d{2}-\d{2}T\d{2}_\d{2}_\d{2})\.(?:json\.gz|txt|json)$',
  caseSensitive: false,
);

/// Whether [name] is a scheduled WebDAV backup.
bool isAutoBackupFile(String name) => autoBackupTimeKey(name) != null;

/// A sortable timestamp independent of the full/follows filename prefix.
String? autoBackupTimeKey(String name) => _autoBackupName.firstMatch(name)?.group(1);

/// A file named [name] in [folder] that does not exist yet: `_2`, `_3` … are
/// added before the extension (3.x overwrote a backup made in the same
/// second).
File freeBackupFile(Directory folder, String name) {
  // `.json.gz`: the suffix stays whole, `_2` goes before it.
  const suffix = '.json.gz';
  final hasSuffix = name.toLowerCase().endsWith(suffix);
  final base = hasSuffix ? name.substring(0, name.length - suffix.length) : p.basenameWithoutExtension(name);
  final extension = hasSuffix ? suffix : p.extension(name);
  var file = File(p.join(folder.path, name));
  for (var i = 2; file.existsSync(); i++) {
    file = File(p.join(folder.path, '${base}_$i$extension'));
  }
  return file;
}

/// A backup file found in the backup folder.
final class LocalBackupFile {
  /// Creates the entry.
  const new({required this.file, required this.modified, required this.size});

  /// The file.
  final File file;

  /// Last change.
  final DateTime modified;

  /// Size in bytes.
  final int size;

  /// The file name.
  String get name => p.basename(file.path);

  /// Whether the name says it is a follows-only backup.
  bool get followsOnly => name.toLowerCase().startsWith('purelive_favorites');

  /// Whether the name says it is a data-only backup (no settings).
  bool get dataOnly => name.toLowerCase().startsWith('purelive_data');

  /// Translation key of the kind shown under the name. The sensitive flag
  /// is not in the name: only the file's `sensitiveDataIncluded` has it.
  String get kindKey => followsOnly
      ? 'backup_kind_follows'
      : dataOnly
      ? 'backup_kind_data'
      : 'backup_kind_full';
}

/// The backups in [folder] (`purelive*.json.gz`, and the plain `.txt` /
/// `.json` files 3.x wrote), newest first.
/// Throws [FileSystemException] when the folder cannot be read.
Future<List<LocalBackupFile>> listBackupFiles(Directory folder) async {
  if (!folder.existsSync()) return const [];
  final found = <LocalBackupFile>[];
  await for (final entity in folder.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path).toLowerCase();
    final backup = name.endsWith('.json.gz') || name.endsWith('.txt') || name.endsWith('.json');
    if (!name.startsWith('purelive') || !backup) continue;
    try {
      final stat = entity.statSync();
      found.add(LocalBackupFile(file: entity, modified: stat.modified, size: stat.size));
    } on FileSystemException {
      continue;
    }
  }
  found.sort((a, b) => b.modified.compareTo(a.modified));
  return found;
}

/// The folder backups go to when the user picked none: on Android the
/// public `Download/PureLive` when the app may write there, else the app's
/// own external folder; elsewhere `Documents/PureLive`. 3.x had no default
/// and asked for a folder on every backup.
Future<Directory> defaultBackupFolder() async {
  final candidates = <Directory>[];
  if (Platform.isAndroid) {
    candidates.add(Directory('/storage/emulated/0/Download/PureLive'));
    if (await _tryDirectory(getExternalStorageDirectory) case final dir?) {
      candidates.add(Directory(p.join(dir.path, 'backup')));
    }
  } else {
    if (await _tryDirectory(getApplicationDocumentsDirectory) case final dir?) {
      candidates.add(Directory(p.join(dir.path, 'PureLive')));
    }
  }
  if (await _tryDirectory(getApplicationSupportDirectory) case final dir?) {
    candidates.add(Directory(p.join(dir.path, 'backup')));
  }
  for (final candidate in candidates) {
    if (await isWritableFolder(candidate)) return candidate;
  }
  return candidates.isNotEmpty ? candidates.last : Directory(p.join(Directory.systemTemp.path, 'PureLive'));
}

Future<Directory?> _tryDirectory(Future<Directory?> Function() find) async {
  try {
    return await find();
  } on Object {
    return null;
  }
}

/// Whether files can be written in [folder] (made when missing).
Future<bool> isWritableFolder(Directory folder) async {
  try {
    await folder.create(recursive: true);
    final probe = File(p.join(folder.path, '.purelive_probe'));
    await probe.writeAsString('');
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Human-readable size: B, KB, MB.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// `yyyy-MM-dd HH:mm` in local time.
String formatFileTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
