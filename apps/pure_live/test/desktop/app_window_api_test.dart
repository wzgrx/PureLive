import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nativeapi/nativeapi.dart' as native;
import 'package:pure_live/app/desktop/app_window_api.dart';

final class _Window extends native.Window {
  new() : super.borrowed(0);
  int released = 0;
  int closes = 0;
  bool acceptClose = true;
  bool visible = false;
  bool consumeFirstShow = false;
  int activeShows = 0;
  int inactiveShows = 0;
  @override
  bool get isMinimized => false;
  @override
  bool get isVisible => visible;
  void _show() {
    if (consumeFirstShow) {
      consumeFirstShow = false;
    } else {
      visible = true;
    }
  }

  @override
  void show() {
    activeShows++;
    _show();
  }

  @override
  void showInactive() {
    inactiveShows++;
    _show();
  }

  @override
  native.WindowId get id => 42;
  @override
  bool get isMaximized => false;
  @override
  bool close() {
    closes++;
    return acceptClose;
  }

  @override
  void dispose() {
    released++;
  }
}

final class _Request extends native.EventRequest {
  new() : super.borrowed(0);
  int cancellations = 0;
  @override
  bool cancel() {
    cancellations++;
    return true;
  }
}

final class _Shell with AppWindowListener {
  int confirmations = 0;
  int minimizes = 0;
  @override
  void onWindowClose() {
    confirmations++;
  }

  @override
  void onWindowMinimize() {
    minimizes++;
  }
}

void main() {
  for (final inactive in [false, true]) {
    test('explicit show survives a hidden first native show: inactive=$inactive', () async {
      final window = _Window()..consumeFirstShow = true;
      final host = AppWindowApi(resolve: () => window, listen: (_) => 1, unlisten: (_) {});
      await host.ensureInitialized();
      await host.show(inactive: inactive);
      expect(window.visible, isTrue);
      expect(window.activeShows, inactive ? 0 : 2);
      expect(window.inactiveShows, inactive ? 2 : 0);
    });
  }
  test('an already effective show does not run a second native show', () async {
    final window = _Window();
    final host = AppWindowApi(resolve: () => window, listen: (_) => 1, unlisten: (_) {});
    await host.ensureInitialized();
    await host.show();
    expect(window.visible, isTrue);
    expect(window.activeShows, 1);
  });

  test('a refused native close does not bypass the next confirmation', () async {
    final window = _Window()..acceptClose = false;
    final shell = _Shell();
    FutureOr<void> Function(native.WindowEvent)? deliver;
    final host = AppWindowApi(
      resolve: () => window,
      listen: (callback) {
        deliver = callback;
        return 1;
      },
      unlisten: (_) {},
    )..addListener(shell);
    await host.ensureInitialized();
    await host.setPreventClose(true);
    await host.destroy();
    final request = _Request();
    await deliver!(native.WindowCloseRequestedEvent(windowId: 42, request: request));
    expect(request.cancellations, 1);
    expect(shell.confirmations, 1);
  });

  test('the hidden host may resolve asynchronously before event ownership begins', () async {
    final ready = Completer<native.Window?>();
    var resolves = 0;
    final window = _Window();
    var listens = 0;
    final host = AppWindowApi(
      resolve: () {
        resolves++;
        return ready.future;
      },
      listen: (_) {
        listens++;
        return 1;
      },
      unlisten: (_) {},
    );
    final initialized = host.ensureInitialized();
    final concurrent = host.ensureInitialized();
    expect(resolves, 1);
    expect(listens, 0);
    ready.complete(window);
    await Future.wait([initialized, concurrent]);
    expect(listens, 1);
    await host.ensureInitialized();
    expect(listens, 1);
  });

  test('one native subscription owns close confirmation, forced exit and final handle release', () async {
    final window = _Window();
    final shell = _Shell();
    FutureOr<void> Function(native.WindowEvent)? deliver;
    final removed = <int>[];
    var listens = 0;
    final host = AppWindowApi(
      resolve: () => window,
      listen: (callback) {
        listens++;
        deliver = callback;
        return 7;
      },
      unlisten: removed.add,
    )..addListener(shell);
    await host.ensureInitialized();
    await host.ensureInitialized();
    expect(listens, 1);
    await host.setPreventClose(true);
    final close = _Request();
    await deliver!(native.WindowCloseRequestedEvent(windowId: 42, request: close));
    expect(close.cancellations, 1);
    expect(shell.confirmations, 1);
    await host.destroy();
    expect(window.closes, 1);
    final confirmed = _Request();
    await deliver!(native.WindowCloseRequestedEvent(windowId: 42, request: confirmed));
    expect(confirmed.cancellations, 0);
    expect(shell.confirmations, 1);
    await deliver!(const native.WindowMinimizedEvent(windowId: 43));
    expect(shell.minimizes, 0, reason: 'other native windows never change this shell');
    host.removeListener(shell);
    await deliver!(const native.WindowMinimizedEvent(windowId: 42));
    expect(shell.minimizes, 0);
    await deliver!(const native.WindowClosedEvent(windowId: 42));
    expect(removed, [7]);
    expect(window.released, 1);
  });
}
