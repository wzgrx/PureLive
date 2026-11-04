import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';

import '../../support.dart';

void main() {
  setUpAll(loadStrings);
  testWidgets('never-show persists through route rebuild, settings restores it, close only hides one load', (
    tester,
  ) async {
    final services = (await tester.runAsync(testServices))!;
    addTearDown(services.close);
    MobileDataNotice.dismissed.value = false;
    MobileDataNotice.onMobileData.value = true;
    addTearDown(() {
      MobileDataNotice.dismissed.value = false;
      MobileDataNotice.onMobileData.value = false;
    });
    Future<void> pump() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: const MaterialApp(home: Scaffold(body: MobileDataBanner())),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump();
    expect(services.store.settings.get(Settings.showCellularWarning), isTrue);
    expect(find.byKey(const ValueKey('mobile-data-notice')), findsOneWidget);
    tester.widget<StatusBanner>(find.byKey(const ValueKey('mobile-data-notice'))).onClose!();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-data-notice')), findsNothing);
    await MobileDataNotice.precheck(() async => NetworkKind.mobile);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-data-notice')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile-data-never')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle();
    expect(services.store.settings.get(Settings.showCellularWarning), isFalse);
    expect(find.byKey(const ValueKey('mobile-data-notice')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await MobileDataNotice.precheck(() async => NetworkKind.mobile);
    await pump();
    expect(find.byKey(const ValueKey('mobile-data-notice')), findsNothing);
    await tester.runAsync(() => services.store.settings.set(Settings.showCellularWarning, true));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-data-notice')), findsOneWidget);
    await expectLater(MobileDataNotice.precheck(() async => NetworkKind.none), throwsA(isA<Offline>()));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
