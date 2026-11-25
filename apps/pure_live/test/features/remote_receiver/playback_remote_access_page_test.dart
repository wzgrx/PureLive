import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/system_access.dart';

import '../settings/settings_harness.dart';

void main() {
  testWidgets('receiver, discovery and pairing refusals show the local-network explanation', (tester) async {
    var requests = 0;
    SystemAccess.debugCall = (method) async {
      expect(method, 'requestLocalNetwork');
      requests++;
      return false;
    };
    addTearDown(() => SystemAccess.debugCall = null);
    final harness = await pumpSettings(tester, width: 1280, height: 1200);
    await searchSettingsFor(tester, 'remote');
    await tester.tap(settingsRow('playback_remote'));
    await settleSettings(tester);
    await tester.tap(find.byKey(const ValueKey('remote-control-enable')));
    await tester.pump(const Duration(seconds: 1));
    expect(harness.services.remoteControl.running, isFalse);
    expect(find.text(i18n('remote_control_permission_denied')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remote-control-discover')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(i18n('remote_control_permission_denied')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('remote-control-address')), '192.168.1.2:4000');
    await tester.enterText(find.byKey(const ValueKey('remote-control-code')), '123456');
    await tester.tap(find.byKey(const ValueKey('remote-control-pair')));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(i18n('remote_control_permission_denied')), findsOneWidget);
    expect(requests, 3);
  });
}
