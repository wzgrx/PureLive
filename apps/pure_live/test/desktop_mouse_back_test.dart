import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/app/desktop/mouse_back.dart';
import 'package:pure_live/routes/app_navigator.dart';

void main() {
  Future<void> back(WidgetTester tester) async {
    await tester.tapAt(const Offset(30, 150), buttons: kBackMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  testWidgets('mouse Back closes a modal before its page and never exits home', (tester) async {
    var rootBacks = 0;
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => PopScope<Object?>(
            canPop: false,
            onPopInvokedWithResult: (_, _) => rootBacks++,
            child: const Scaffold(body: Text('home')),
          ),
        ),
        GoRoute(
          path: '/child',
          builder: (context, state) => const Scaffold(body: Text('child')),
        ),
      ],
    );
    AppNavigator.router = router;
    addTearDown(() {
      AppNavigator.router = null;
      router.dispose();
    });
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => DesktopMouseBack(enabled: true, onBack: AppNavigator.mouseBack, child: child!),
      ),
    );
    unawaited(router.push<void>('/child'));
    await tester.pumpAndSettle();

    showDialog<void>(
      context: tester.element(find.text('child')),
      builder: (_) => const AlertDialog(content: Text('modal')),
    );
    await tester.pumpAndSettle();
    await back(tester);
    expect(find.text('modal'), findsNothing);
    expect(find.text('child'), findsOneWidget);
    await back(tester);
    expect(find.text('home'), findsOneWidget);
    await back(tester);
    expect(rootBacks, 0);
  });

  testWidgets('mouse Back honors the room fullscreen PopScope before leaving', (tester) async {
    final fullscreen = ValueNotifier(true);
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/child',
          builder: (_, _) => ValueListenableBuilder<bool>(
            valueListenable: fullscreen,
            builder: (_, active, _) => PopScope<Object?>(
              canPop: !active,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) fullscreen.value = false;
              },
              child: const Scaffold(body: Text('room')),
            ),
          ),
        ),
      ],
    );
    AppNavigator.router = router;
    addTearDown(() {
      AppNavigator.router = null;
      router.dispose();
      fullscreen.dispose();
    });
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => DesktopMouseBack(enabled: true, onBack: AppNavigator.mouseBack, child: child!),
      ),
    );
    unawaited(router.push<void>('/child'));
    await tester.pumpAndSettle();
    await back(tester);
    expect(fullscreen.value, isFalse);
    expect(find.text('room'), findsOneWidget);
    await back(tester);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a pending Back coalesces; Forward and mobile pointers are ignored', (tester) async {
    var calls = 0;
    final pending = Completer<bool>();
    Future<bool> pop() {
      calls++;
      return pending.future;
    }

    Widget app({required bool enabled}) => MaterialApp(
      home: DesktopMouseBack(
        enabled: enabled,
        onBack: pop,
        child: const ColoredBox(color: Colors.black),
      ),
    );
    await tester.pumpWidget(app(enabled: true));
    await back(tester);
    await back(tester);
    expect(calls, 1);
    await tester.tapAt(const Offset(30, 150), buttons: kForwardMouseButton, kind: PointerDeviceKind.mouse);
    expect(calls, 1);
    pending.complete(true);
    await tester.pump();
    await tester.pumpWidget(app(enabled: false));
    await back(tester);
    expect(calls, 1);
  });
}
