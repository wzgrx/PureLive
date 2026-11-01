import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/features/huya_replay/huya_archive_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/app_router.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/archive_navigation.dart';

import '../../support.dart';

void main() {
  test('registered route preserves presenter identity and local ownership callbacks', () {
    final room = LiveRoom(platform: SiteIds.huya, roomId: '998', userId: '123');
    Future<void> before() async {}
    void retire(Future<void> _) {}
    final args = HuyaArchiveArguments(room: room, beforePlay: before, onRetire: retire);
    final page =
        pageRoutes[RoutePath.kHuyaArchives]!(RouteArgs(RoutePath.kHuyaArchives, arguments: args)) as HuyaArchivePage;
    expect(page.room, same(room));
    expect(page.beforePlay, same(before));
    expect(page.onRetire, same(retire));
  });

  for (final failCleanup in [false, true]) {
    testWidgets('route completion waits for real native retirement; failure $failCleanup never grants restoration', (
      tester,
    ) async {
      await tester.runAsync(loadStrings);
      final pending = Completer<void>();
      var completed = false;
      bool? safeToResume;
      HuyaArchiveArguments? passed;
      final messages = <String>[];
      final oldToast = AppNavigator.toast;
      AppNavigator.toast = messages.add;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  safeToResume = await openHuyaArchives(context);
                  completed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
          GoRoute(
            path: RoutePath.kHuyaArchives,
            builder: (context, state) {
              passed = state.extra! as HuyaArchiveArguments;
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    passed!.onRetire!(pending.future);
                    context.pop();
                  },
                  child: const Text('back'),
                ),
              );
            },
          ),
        ],
      );
      AppNavigator.router = router;
      addTearDown(() {
        AppNavigator.router = null;
        AppNavigator.toast = oldToast;
        router.dispose();
      });
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(passed, isNotNull);
      await tester.tap(find.text('back'));
      await tester.pumpAndSettle();
      expect(completed, isFalse);
      if (failCleanup) {
        pending.completeError(StateError('synthetic native cleanup failure'));
      } else {
        pending.complete();
      }
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(safeToResume, !failCleanup);
      expect(messages.length, failCleanup ? 1 : 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
