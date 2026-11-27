// XML samples are written as adjacent strings without spaces between tags.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/web_dav/web_dav_auto_backup.dart';
import 'package:pure_live/features/web_dav/web_dav_client.dart';
import 'package:pure_live/shared/backup/backup_data.dart';
import 'package:pure_live/shared/backup/backup_files.dart';

import '../../support.dart';

const _server = WebDavConfig(name: 'home', address: 'https://dav.test/dav/', username: 'u', password: 'p');

/// A WebDAV server in memory below `/dav/`, Basic auth `u:p`.
final class _AutoDav implements LiveHttp {
  final Map<String, List<int>> files = {};
  final Set<String> dirs = {''};
  final List<String> requests = [];
  int failPutStatus = 0;
  bool includeOtherDepths = false;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    LiveResponse answer(int status, [String body = '']) =>
        LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);
    if (request.headers['authorization'] != 'Basic ${base64.encode(utf8.encode('u:p'))}') return answer(401);
    final key = [
      for (final segment in request.url.pathSegments)
        if (segment.isNotEmpty) segment,
    ].skip(1).join('/');
    requests.add('${request.method} $key');
    switch (request.method) {
      case 'PROPFIND':
        if (!dirs.contains(key)) return answer(404);
        String href(String path, {required bool dir}) =>
            '/dav/${[for (final part in path.split('/'))
              if (part.isNotEmpty) Uri.encodeComponent(part)].join('/')}'
            '${dir && path.isNotEmpty ? '/' : ''}';
        bool child(String path) =>
            path != key &&
            (key.isEmpty
                ? !path.contains('/')
                : path.startsWith('$key/') && !path.substring(key.length + 1).contains('/'));
        final responses = StringBuffer()
          ..write(
            '<D:response><D:href>${href(key, dir: true)}</D:href>'
            '<D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>',
          );
        if (request.headers['depth'] != '0') {
          for (final dir in dirs.where(child)) {
            responses.write(
              '<D:response><D:href>${href(dir, dir: true)}</D:href><D:propstat><D:prop>'
              '<D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>',
            );
          }
          for (final MapEntry(key: path, value: bytes) in files.entries.where(
            (entry) => includeOtherDepths || child(entry.key),
          )) {
            responses.write(
              '<D:response><D:href>${href(path, dir: false)}</D:href><D:propstat><D:prop>'
              '<D:resourcetype/><D:getcontentlength>${bytes.length}</D:getcontentlength>'
              '<D:getlastmodified>Wed, 01 Oct 2026 12:00:00 GMT</D:getlastmodified>'
              '</D:prop></D:propstat></D:response>',
            );
          }
        }
        return answer(207, '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">$responses</D:multistatus>');
      case 'MKCOL':
        if (dirs.contains(key)) return answer(405);
        if (!dirs.contains(_parent(key))) return answer(409);
        dirs.add(key);
        return answer(201);
      case 'PUT':
        if (failPutStatus != 0) return answer(failPutStatus);
        if (!dirs.contains(_parent(key))) return answer(409);
        files[key] = request.body ?? const [];
        return answer(201);
      case 'GET':
        final bytes = files[key];
        return bytes == null ? answer(404) : LiveResponse(status: 200, bytes: bytes, url: request.url);
      case 'DELETE':
        return files.remove(key) == null && !dirs.remove(key) ? answer(404) : answer(204);
    }
    return answer(405);
  }

  static String _parent(String key) {
    final slash = key.lastIndexOf('/');
    return slash < 0 ? '' : key.substring(0, slash);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

Future<LiveStore> _store({bool server = true}) async {
  final store = await LiveStore.memory(cipher: FakeCipher());
  if (server) {
    await store.webdav.add(_server);
    await store.webdav.select(_server.name);
  }
  return store;
}

Future<void> _enable(
  LiveStore store, {
  int hours = 24,
  String folder = 'purelive',
  String scope = 'all',
  int keep = 7,
  bool accounts = false,
}) => store.settings.setAll({
  Settings.webdavAutoBackupEnabled: true,
  Settings.webdavAutoBackupHours: hours,
  Settings.webdavAutoBackupScope: scope,
  Settings.webdavAutoBackupFolder: folder,
  Settings.webdavAutoBackupKeep: keep,
  Settings.webdavAutoBackupIncludeAccounts: accounts,
});

void main() {
  test('automatic names keep the purelive prefix and are told apart from manual files', () {
    final now = DateTime(2026, 10, 24, 12, 34, 56);
    expect(autoBackupFileName(BackupScope.all, now), 'purelive_auto_2026-10-24T12_34_56.json.gz');
    expect(autoBackupFileName(BackupScope.follows, now), 'purelive_favorites_auto_2026-10-24T12_34_56.json.gz');
    expect(isAutoBackupFile('purelive_auto_2026-10-24T12_34_56.json.gz'), isTrue);
    expect(isAutoBackupFile('purelive_favorites_auto_2026-10-24T12_34_56.json.gz'), isTrue);
    expect(isAutoBackupFile('purelive_2026-10-24T12_34_56.json.gz'), isFalse);
    expect(isAutoBackupFile('purelive_favorites_2026-10-24T12_34_56.json.gz'), isFalse);
    expect(isAutoBackupFile('notes.txt'), isFalse);
  });

  test('a remote folder is a safe relative path', () {
    expect(parseWebDavFolder(' purelive '), ['purelive']);
    expect(parseWebDavFolder('/backup/purelive/'), ['backup', 'purelive']);
    expect(parseWebDavFolder('备份/直播'), ['备份', '直播']);
    expect(parseWebDavFolder(''), isNull);
    expect(parseWebDavFolder('/'), isNull);
    expect(parseWebDavFolder('..'), isNull);
    expect(parseWebDavFolder('a/../b'), isNull);
    expect(parseWebDavFolder(r'a\b'), isNull);
  });

  test('disabled, no server and an invalid folder do nothing', () async {
    final dav = _AutoDav();
    final store = await _store();
    addTearDown(store.close);
    final service = WebDavAutoBackupService(
      store,
      dav,
      BackupService(store),
      now: () => DateTime.utc(2026, 10, 24, 12),
    );
    expect((await service.runIfDue()).skipped, isTrue);
    await _enable(store, folder: '..');
    expect((await service.runIfDue()).skipped, isTrue);
    expect(dav.requests, isEmpty);

    final noServer = await _store(server: false);
    addTearDown(noServer.close);
    await _enable(noServer);
    final other = WebDavAutoBackupService(
      noServer,
      dav,
      BackupService(noServer),
      now: () => DateTime.utc(2026, 10, 24, 12),
    );
    expect((await other.runIfDue()).skipped, isTrue);
    expect(dav.requests, isEmpty);
  });

  test('due: creates the levels, uploads a full backup, writes the meta state', () async {
    final dav = _AutoDav();
    final store = await _store();
    addTearDown(store.close);
    await _enable(store, folder: 'backup/purelive');
    final service = WebDavAutoBackupService(
      store,
      dav,
      BackupService(store),
      now: () => DateTime.utc(2026, 10, 24, 12),
    );
    final result = await service.runIfDue();
    expect(result.fileName, 'purelive_auto_2026-10-24T12_00_00.json.gz');
    expect(dav.dirs, containsAll(['backup', 'backup/purelive']));
    final file = dav.files['backup/purelive/purelive_auto_2026-10-24T12_00_00.json.gz'];
    expect(file, isNotNull);
    final json = BackupService.decode(file!);
    expect(json['backupVersion'], 4);
    expect(json['sensitiveDataIncluded'], isFalse);
    expect(json['cookie'], isNull);
    final meta = await service.readMeta();
    expect(meta.lastSuccess, DateTime.utc(2026, 10, 24, 12));
    expect(meta.lastAttempt, DateTime.utc(2026, 10, 24, 12));
    expect(meta.failures, 0);
    expect(meta.target, contains('"folder":"backup/purelive"'));
    expect(await service.isDue(now: DateTime.utc(2026, 10, 24, 12, 1)), isFalse);
    expect(await service.isDue(now: DateTime.utc(2026, 10, 25, 12)), isTrue);
  });

  test('failure: no success, one failure, the backoff delays the next try', () async {
    final dav = _AutoDav()..failPutStatus = 500;
    final store = await _store();
    addTearDown(store.close);
    await _enable(store);
    var now = DateTime.utc(2026, 10, 24, 12);
    final service = WebDavAutoBackupService(store, dav, BackupService(store), now: () => now);
    final result = await service.runIfDue();
    expect(result.error, isNotNull);
    var meta = await service.readMeta();
    expect(meta.lastSuccess, isNull);
    expect(meta.lastAttempt, DateTime.utc(2026, 10, 24, 12));
    expect(meta.failures, 1);
    now = DateTime.utc(2026, 10, 24, 12, 14);
    expect(await service.isDue(), isFalse);
    now = DateTime.utc(2026, 10, 24, 12, 15);
    expect(await service.isDue(), isTrue);
    await service.runIfDue();
    meta = await service.readMeta();
    expect(meta.failures, 2);
  });

  test('a changed target is due at once', () async {
    final dav = _AutoDav();
    final store = await _store();
    addTearDown(store.close);
    await _enable(store);
    final service = WebDavAutoBackupService(
      store,
      dav,
      BackupService(store),
      now: () => DateTime.utc(2026, 10, 24, 12),
    );
    await service.runIfDue();
    await store.settings.set(Settings.webdavAutoBackupFolder, 'other');
    expect(await service.isDue(now: DateTime.utc(2026, 10, 24, 12, 1)), isTrue);
  });

  test('retention keeps the newest automatic files and never touches a manual one', () async {
    final dav = _AutoDav();
    dav.dirs.add('purelive');
    for (final day in [1, 2, 3]) {
      dav.files['purelive/purelive_auto_2026-10-0${day}T10_00_00.json.gz'] = utf8.encode('{}');
    }
    dav.files['purelive/purelive_2026-10-04T10_00_00.json.gz'] = utf8.encode('{}');
    final store = await _store();
    addTearDown(store.close);
    await _enable(store, keep: 3);
    final service = WebDavAutoBackupService(
      store,
      dav,
      BackupService(store),
      now: () => DateTime.utc(2026, 10, 24, 12),
    );
    await service.runIfDue();
    final names = dav.files.keys.map((path) => path.substring('purelive/'.length)).toSet();
    expect(names, contains('purelive_auto_2026-10-24T12_00_00.json.gz'));
    expect(names, isNot(contains('purelive_auto_2026-10-01T10_00_00.json.gz')));
    expect(names, contains('purelive_auto_2026-10-02T10_00_00.json.gz'));
    expect(names, contains('purelive_auto_2026-10-03T10_00_00.json.gz'));
    expect(names, contains('purelive_2026-10-04T10_00_00.json.gz'));
  });

  test('mixed scopes retain by timestamp, including the new full backup', () async {
    final dav = _AutoDav();
    dav.dirs.add('purelive');
    dav.files['purelive/purelive_favorites_auto_2026-10-01T10_00_00.json.gz'] = utf8.encode('{}');
    dav.files['purelive/purelive_auto_2026-10-23T10_00_00.json.gz'] = utf8.encode('{}');
    final store = await _store();
    addTearDown(store.close);
    await _enable(store, keep: 2);
    final service = WebDavAutoBackupService(
      store,
      dav,
      BackupService(store),
      now: () => DateTime.utc(2026, 10, 24, 12),
    );
    final result = await service.runIfDue();
    expect(result.fileName, 'purelive_auto_2026-10-24T12_00_00.json.gz');
    expect(
      dav.files.keys,
      unorderedEquals([
        'purelive/purelive_auto_2026-10-23T10_00_00.json.gz',
        'purelive/purelive_auto_2026-10-24T12_00_00.json.gz',
      ]),
    );
  });

  test('retention ignores sibling and nested files in a malformed depth-one listing', () async {
    final dav = _AutoDav()..includeOtherDepths = true;
    dav.dirs.add('purelive');
    final protected = [
      'sibling/purelive_auto_2026-10-01T10_00_00.json.gz',
      'purelive/nested/purelive_auto_2026-10-02T10_00_00.json.gz',
      'purelive/purelive_2026-10-03T10_00_00.json.gz',
    ];
    for (final path in protected) {
      dav.files[path] = utf8.encode('{}');
    }
    dav.files['purelive/purelive_auto_2026-10-04T10_00_00.json.gz'] = utf8.encode('{}');
    final store = await _store();
    addTearDown(store.close);
    await _enable(store, keep: 1);
    final service = WebDavAutoBackupService(
      store,
      dav,
      BackupService(store),
      now: () => DateTime.utc(2026, 10, 24, 12),
    );
    await service.runIfDue();
    expect(dav.files.keys, containsAll(protected));
    expect(dav.requests.where((request) => request.startsWith('DELETE ')), [
      'DELETE purelive/purelive_auto_2026-10-04T10_00_00.json.gz',
    ]);
  });

  test('follows only and accounts are what the settings say', () async {
    final dav = _AutoDav();
    final store = await _store();
    addTearDown(store.close);
    await _enable(store, scope: 'follows', accounts: true);
    final service = WebDavAutoBackupService(
      store,
      dav,
      BackupService(store),
      now: () => DateTime.utc(2026, 10, 24, 12),
    );
    await service.runIfDue();
    var json = BackupService.decode(dav.files['purelive/purelive_favorites_auto_2026-10-24T12_00_00.json.gz']!);
    expect(json['backupScope'], 'favorites');
    expect(json['cookie'], isNull);

    await _enable(store, accounts: true);
    await store.meta.set('webdav.auto.lastSuccess', null);
    await service.runIfDue();
    final allFile = dav.files['purelive/purelive_auto_2026-10-24T12_00_00.json.gz']!;
    json = BackupService.decode(allFile);
    expect(json['sensitiveDataIncluded'], isTrue);
    expect(json['cookie'], isNotNull);
    expect(json['webdav'], isNotNull);
  });

  test('ensureFolder makes each level and accepts an existing one', () async {
    final dav = _AutoDav();
    final client = WebDavClient(dav, _server);
    await client.ensureFolder(['backup', 'purelive']);
    expect(dav.dirs, containsAll(['backup', 'backup/purelive']));
    await client.ensureFolder(['backup', 'purelive']);
    expect(dav.requests.where((request) => request == 'MKCOL backup').length, 2);
  });
}
