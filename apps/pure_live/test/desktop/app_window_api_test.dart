import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nativeapi/nativeapi.dart' as native;
import 'package:pure_live/app/desktop/app_window_api.dart';

final class _Window extends native.Window {
  new() : super.borrowed(0);
  int released = 0;
  int closes = 0;
  @override
  native.WindowId get id => 42;
  @override
  bool get isMaximized => false;
  @override
  bool close() {
    closes++;
    return true;
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
