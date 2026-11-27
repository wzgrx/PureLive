import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/web_dav/web_dav_auto_backup.dart';
import 'package:pure_live/features/web_dav/web_dav_auto_backup_scheduler.dart';

import '../../support.dart';

const _server = WebDavConfig(name: 'home', address: 'https://dav.test/dav/', username: 'u', password: 'p');

/// Enough of a WebDAV server for the scheduler: folders always exist, PUTs
/// are counted (and can be failed or held).
final class _SchedulerDav implements LiveHttp {
  new({this.putGate});

  final Completer<void>? putGate;
  final Completer<void> putStarted = Completer<void>();
  int putCount = 0;
  bool failPut = false;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    LiveResponse answer(int status, [String body = '']) =>
        LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);
    if (request.headers['authorization'] != 'Basic ${base64.encode(utf8.encode('u:p'))}') return answer(401);
    switch (request.method) {
      case 'PROPFIND':
        return answer(207, '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:"/>');
      case 'MKCOL':
        return answer(201);
      case 'PUT':
        if (!putStarted.isCompleted) putStarted.complete();
        if (putGate case final gate?) await gate.future;
        if (failPut) return answer(500);
        putCount++;
        return answer(201);
      case 'DELETE':
        return answer(204);
    }
    return answer(405);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

final class _FakeTimer implements Timer {
  bool _active = true;

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

Future<LiveStore> _store() async {
  final store = await LiveStore.memory(cipher: FakeCipher());
  await store.webdav.add(_server);
  await store.webdav.select(_server.name);
  return store;
}

Future<void> _enable(LiveStore store, {bool enabled = true}) => store.settings.setAll({
  Settings.webdavAutoBackupEnabled: enabled,
  Settings.webdavAutoBackupHours: 24,
  Settings.webdavAutoBackupFolder: 'purelive',
  Settings.webdavAutoBackupKeep: 7,
});

({WebDavAutoBackupScheduler scheduler, WebDavAutoBackupService service, _SchedulerDav dav, List<String> toasts})
_scheduler(LiveStore store, {_SchedulerDav? dav, DateTime Function()? now, bool observeLifecycle = false}) {
  final server = dav ?? _SchedulerDav();
  final service = WebDavAutoBackupService(
    store,
    server,
    BackupService(store),
    now: now ?? () => DateTime.utc(2026, 10, 24, 12),
  );
  final toasts = <String>[];
  final scheduler = WebDavAutoBackupScheduler(
    store.settings,
    service,
    toast: toasts.add,
    checkInterval: const Duration(seconds: 1),
    timer: (_, _) => _FakeTimer(),
    observeLifecycle: observeLifecycle,
  );
  addTearDown(scheduler.dispose);
  return (scheduler: scheduler, service: service, dav: server, toasts: toasts);
}

void main() {
  setUpAll(loadStrings);

  test('disabled: no timer and no request', () async {
    final store = await _store();
    addTearDown(store.close);
    final setup = _scheduler(store);
    setup.scheduler.start();
    await setup.scheduler.checkNow();
    expect(setup.scheduler.timerActive, isFalse);
    expect(setup.dav.putCount, 0);
    expect(setup.toasts, isEmpty);
    setup.scheduler.dispose();
  });

  test('enabled: starts the timer, catches up at once and says it uploaded', () async {
    final store = await _store();
    addTearDown(store.close);
    await _enable(store);
    final setup = _scheduler(store);
    setup.scheduler.start();
    await setup.scheduler.checkNow();
    expect(setup.scheduler.timerActive, isTrue);
    expect(setup.dav.putCount, 1);
    expect(setup.toasts.single, contains('已自动备份到 WebDAV'));
    expect(setup.toasts.single, contains('purelive_auto_2026-10-24T12_00_00.json.gz'));
    setup.scheduler.dispose();
    expect(setup.scheduler.timerActive, isFalse);
  });

  test('pause stops the timer; resume catches up when the interval passed', () async {
    final store = await _store();
    addTearDown(store.close);
    await _enable(store);
    final now = DateTime.utc(2026, 10, 24, 12);
    final setup = _scheduler(store, now: () => now);
    setup.scheduler.start();
    await setup.scheduler.checkNow();
    expect(setup.dav.putCount, 1);

    await store.meta.set(
      WebDavAutoBackupService.lastSuccessKey,
      now.subtract(const Duration(hours: 25)).toIso8601String(),
    );
    setup.scheduler.pause();
    expect(setup.scheduler.timerActive, isFalse);
    expect(setup.dav.putCount, 1);

    setup.scheduler.resume();
    await setup.scheduler.checkNow();
    expect(setup.scheduler.timerActive, isTrue);
    expect(setup.dav.putCount, 2);
    setup.scheduler.dispose();
  });

  test('a hidden desktop window pauses checks and catches up when visible', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized()
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() {
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final store = await _store();
    addTearDown(store.close);
    await _enable(store);
    final setup = _scheduler(store, observeLifecycle: true);
    setup.scheduler.start();
    await setup.scheduler.checkNow();
    expect(setup.dav.putCount, 1);
    await store.meta.set(WebDavAutoBackupService.lastSuccessKey, DateTime.utc(2026, 10, 23).toIso8601String());
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(setup.scheduler.timerActive, isFalse);
    await setup.scheduler.checkNow();
    expect(setup.dav.putCount, 1);
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await setup.scheduler.checkNow();
    expect(setup.dav.putCount, 2);
    setup.scheduler.dispose();
  });

  test('starting with a hidden window leaves checks paused', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized()
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    addTearDown(() {
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final store = await _store();
    addTearDown(store.close);
    await _enable(store);
    final setup = _scheduler(store, observeLifecycle: true);
    setup.scheduler.start();
    await setup.scheduler.checkNow();
    expect(setup.scheduler.timerActive, isFalse);
    expect(setup.dav.putCount, 0);
    setup.scheduler.dispose();
  });

  test('a failure is told once in this run, later failures only go to the log', () async {
    final store = await _store();
    addTearDown(store.close);
    await _enable(store);
    final dav = _SchedulerDav()..failPut = true;
    final now = DateTime.utc(2026, 10, 24, 12);
    final setup = _scheduler(store, dav: dav, now: () => now);
    setup.scheduler.start();
    await setup.scheduler.checkNow();
    expect(dav.putCount, 0);
    expect(setup.toasts, hasLength(1));
    expect(setup.toasts.single, contains('WebDAV 自动备份失败'));

    await store.meta.set(
      WebDavAutoBackupService.lastAttemptKey,
      now.subtract(const Duration(hours: 1)).toIso8601String(),
    );
    await store.meta.set(WebDavAutoBackupService.failuresKey, '1');
    await setup.scheduler.checkNow();
    expect(setup.toasts, hasLength(1), reason: 'the first failure was already told');
    setup.scheduler.dispose();
  });

  test('two checks at once share one upload', () async {
    final store = await _store();
    addTearDown(store.close);
    await _enable(store);
    final gate = Completer<void>();
    final dav = _SchedulerDav(putGate: gate);
    final setup = _scheduler(store, dav: dav);
    setup.scheduler.start();
    await dav.putStarted.future;
    final first = setup.scheduler.checkNow();
    final second = setup.scheduler.checkNow();
    expect(identical(first, second), isTrue);
    gate.complete();
    await Future.wait([first, second]);
    expect(dav.putCount, 1);
    setup.scheduler.dispose();
  });
}
