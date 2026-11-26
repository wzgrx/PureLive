import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;

import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/web_dav/web_dav_client.dart';
import 'package:pure_live/shared/backup/backup_data.dart';
import 'package:pure_live/shared/backup/backup_files.dart';

/// One scheduled WebDAV backup check (J04.2, V01.9).
final class WebDavAutoBackupResult {
  const new _({this.fileName, this.error, this.skipped = false});

  /// Uploaded [fileName].
  const new uploaded(String fileName) : this._(fileName: fileName);

  /// Nothing to do (disabled, not due, no server, invalid folder).
  const new skipped() : this._(skipped: true);

  /// An upload or export failed; [error] is logged.
  const new failed(Object error) : this._(error: error);

  /// The uploaded file, when there was one.
  final String? fileName;

  /// The failure, when the check failed.
  final Object? error;

  /// Whether the check had nothing to do.
  final bool skipped;
}

/// The state a scheduled backup keeps in `meta`.
final class WebDavAutoBackupMeta {
  /// Creates the state.
  const new({this.lastSuccess, this.lastAttempt, this.failures = 0, this.target});

  /// Last successful upload.
  final DateTime? lastSuccess;

  /// Last attempt, successful or not.
  final DateTime? lastAttempt;

  /// Failed attempts since the last success.
  final int failures;

  /// The server, folder and contents of [lastSuccess].
  final String? target;
}

/// Reads the current WebDAV server, exports the chosen backup and uploads it
/// to the auto-backup folder (J04.2). Only called while the app runs; the
/// scheduler decides when.
final class WebDavAutoBackupService {
  /// Creates the service over the store, HTTP client and backup service.
  new(this._store, this._http, this._backup, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final LiveStore _store;
  final LiveHttp _http;
  final BackupService _backup;
  final DateTime Function() _now;

  /// Meta key of the last successful upload.
  static const String lastSuccessKey = 'webdav.auto.lastSuccess';

  /// Meta key of the last attempt.
  static const String lastAttemptKey = 'webdav.auto.lastAttempt';

  /// Meta key of failed attempts since the last success.
  static const String failuresKey = 'webdav.auto.failures';

  /// Meta key of the target [lastSuccessKey] belongs to.
  static const String lastTargetKey = 'webdav.auto.lastTarget';

  /// Whether a backup is due now.
  Future<bool> isDue({DateTime? now}) async {
    final settings = _store.settings;
    if (!settings.get(Settings.webdavAutoBackupEnabled)) return false;
    final config = await _store.webdav.current();
    final folder = parseWebDavFolder(settings.get(Settings.webdavAutoBackupFolder));
    if (config == null || !WebDavConfig.isValidAddress(config.address) || folder == null) return false;
    final meta = await readMeta();
    final target = _targetOf(config, folder, _scope(), settings.get(Settings.webdavAutoBackupIncludeAccounts));
    return _due(now ?? _now(), settings.get(Settings.webdavAutoBackupHours), target, meta);
  }

  /// Uploads when due; otherwise returns [WebDavAutoBackupResult.skipped].
  Future<WebDavAutoBackupResult> runIfDue() async {
    final settings = _store.settings;
    if (!settings.get(Settings.webdavAutoBackupEnabled)) return const WebDavAutoBackupResult.skipped();
    final config = await _store.webdav.current();
    if (config == null || !WebDavConfig.isValidAddress(config.address)) return const WebDavAutoBackupResult.skipped();
    final folder = parseWebDavFolder(settings.get(Settings.webdavAutoBackupFolder));
    if (folder == null) {
      log('WebDAV auto backup folder is invalid', name: 'WebDav');
      return const WebDavAutoBackupResult.skipped();
    }
    final scope = _scope();
    final includeAccounts = settings.get(Settings.webdavAutoBackupIncludeAccounts);
    final target = _targetOf(config, folder, scope, includeAccounts);
    final meta = await readMeta();
    final now = _now();
    if (!_due(now, settings.get(Settings.webdavAutoBackupHours), target, meta)) {
      return const WebDavAutoBackupResult.skipped();
    }
    final utc = now.toUtc();
    try {
      final client = WebDavClient(_http, config);
      await client.ensureFolder(folder);
      final data = await exportBackup(
        _backup,
        _store,
        scope,
        contents: includeAccounts ? BackupContents.sensitive : BackupContents.settings,
      );
      final name = autoBackupFileName(scope, now);
      await client.write([...folder, name], utf8.encode(jsonEncode(data)));
      await _store.meta.set(lastSuccessKey, utc.toIso8601String());
      await _store.meta.set(lastAttemptKey, utc.toIso8601String());
      await _store.meta.set(failuresKey, '0');
      await _store.meta.set(lastTargetKey, target);
      await _prune(client, folder, settings.get(Settings.webdavAutoBackupKeep));
      return WebDavAutoBackupResult.uploaded(name);
    } on Object catch (error, stack) {
      log('WebDAV auto backup failed', name: 'WebDav', error: error, stackTrace: stack);
      final failures = (meta.failures) + 1;
      await _store.meta.set(lastAttemptKey, utc.toIso8601String());
      await _store.meta.set(failuresKey, '$failures');
      return WebDavAutoBackupResult.failed(error);
    }
  }

  /// The meta state.
  Future<WebDavAutoBackupMeta> readMeta() async {
    final meta = _store.meta;
    DateTime? time(String? value) => value == null ? null : DateTime.tryParse(value)?.toUtc();
    return WebDavAutoBackupMeta(
      lastSuccess: time(await meta.get(lastSuccessKey)),
      lastAttempt: time(await meta.get(lastAttemptKey)),
      failures: int.tryParse(await meta.get(failuresKey) ?? '') ?? 0,
      target: await meta.get(lastTargetKey),
    );
  }

  BackupScope _scope() =>
      _store.settings.get(Settings.webdavAutoBackupScope) == 'follows' ? BackupScope.follows : BackupScope.all;

  static String _targetOf(WebDavConfig config, List<String> folder, BackupScope scope, bool includeAccounts) =>
      jsonEncode({
        'server': config.name,
        'address': config.address,
        'folder': folder.join('/'),
        'scope': scope == BackupScope.follows ? 'follows' : 'all',
        'accounts': scope == BackupScope.all && includeAccounts,
      });

  static bool _due(DateTime now, int hours, String target, WebDavAutoBackupMeta meta) {
    final interval = Duration(hours: hours);
    DateTime? retry;
    if (meta.failures > 0 && meta.lastAttempt != null) {
      retry = meta.lastAttempt!.add(_backoff(meta.failures, interval));
    }
    if (meta.target != target) {
      if (retry != null && now.isBefore(retry)) return false;
      return true;
    }
    if (meta.lastSuccess == null) {
      if (retry != null) return !now.isBefore(retry);
      return true;
    }
    var due = meta.lastSuccess!.add(interval);
    if (retry != null && retry.isAfter(due)) due = retry;
    return !now.isBefore(due);
  }

  /// 15 min, 30 min, 1 h, 2 h, 4 h, 6 h; never longer than [interval].
  static Duration _backoff(int failures, Duration interval) {
    const delays = [
      Duration(minutes: 15),
      Duration(minutes: 30),
      Duration(hours: 1),
      Duration(hours: 2),
      Duration(hours: 4),
      Duration(hours: 6),
    ];
    final delay = delays[math.min(failures - 1, delays.length - 1)];
    return delay < interval ? delay : interval;
  }

  Future<void> _prune(WebDavClient client, List<String> folder, int keep) async {
    try {
      final entries = await client.list(folder);
      final files =
          [
            for (final entry in entries)
              if (!entry.isDir &&
                  entry.path.length == folder.length + 1 &&
                  List.generate(folder.length, (index) => entry.path[index] == folder[index]).every((same) => same) &&
                  isAutoBackupFile(entry.name))
                entry,
          ]..sort((a, b) {
            final time = autoBackupTimeKey(b.name)!.compareTo(autoBackupTimeKey(a.name)!);
            return time == 0 ? b.name.compareTo(a.name) : time;
          });
      for (final entry in files.skip(keep)) {
        try {
          await client.remove(entry.path);
        } on Object catch (error, stack) {
          log('Deleting an old WebDAV backup failed', name: 'WebDav', error: error, stackTrace: stack);
        }
      }
    } on Object catch (error, stack) {
      log('Listing WebDAV auto backups failed', name: 'WebDav', error: error, stackTrace: stack);
    }
  }
}

/// Splits a configured remote folder into path segments; null when it is
/// not a safe relative path (empty, `.`, `..`, backslash, control chars).
List<String>? parseWebDavFolder(String value) {
  final text = value.trim();
  if (text.isEmpty || RegExp(r'[\x00-\x1f\x7f\\]').hasMatch(text)) return null;
  final segments = [
    for (final segment in text.split('/'))
      if (segment.isNotEmpty) segment,
  ];
  if (segments.isEmpty || segments.any((segment) => segment == '.' || segment == '..')) return null;
  return segments;
}
