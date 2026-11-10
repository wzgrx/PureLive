import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/portrait_chat_overlay.dart';

LiveMessage _message(int n) => LiveMessage(
  type: LiveMessageType.chat,
  userName: '观众$n',
  userId: '$n',
  message: '第$n条聊天内容',
  messageId: '$n',
  color: LiveMessageColor.white,
);

void main() {
  late StreamController<LiveMessage> messages;
  late StreamController<LiveRetraction> retractions;
  late GlobalKey<PortraitChatOverlayState> key;

  setUp(() {
    messages = StreamController.broadcast(sync: true);
    retractions = StreamController.broadcast(sync: true);
    key = GlobalKey();
  });
  tearDown(() async {
    await messages.close();
    await retractions.close();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool visible = true,
    bool running = true,
    bool held = false,
    double textScale = 1,
    Stream<LiveMessage>? source,
    DanmakuLook look = const DanmakuLook(),
  }) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: const LiveTheme().dark,
        home: MediaQuery(
          data: MediaQueryData(size: const Size(393, 852), textScaler: TextScaler.linear(textScale)),
          child: PortraitChatOverlay(
            key: key,
            messages: source ?? messages.stream,
            retractions: retractions.stream,
            look: look,
            visible: visible,
            running: running,
            held: held,
            clearance: const EdgeInsets.only(bottom: 100),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('new rows enter below older ones, stay left aligned and stay bounded during a burst', (tester) async {
    await pump(tester);
    messages.add(_message(1));
    await tester.pump();
    messages.add(_message(2));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getCenter(find.text('第2条聊天内容')).dy, greaterThan(tester.getCenter(find.text('第1条聊天内容')).dy));
    expect(tester.getRect(find.text('第2条聊天内容')).left, closeTo(tester.getRect(find.text('第1条聊天内容')).left, 1));
    for (var n = 3; n < 500; n++) {
      messages.add(_message(n));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(key.currentState!.visibleCount, 6);
    expect(find.text('第1条聊天内容'), findsNothing);
    expect(find.text('第499条聊天内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('paused media preserves visible rows, drops remote arrivals, then expires after resume', (tester) async {
    await pump(tester);
    messages.add(_message(1));
    await tester.pump();
    await pump(tester, running: false);
    messages.add(_message(2));
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('第1条聊天内容'), findsOneWidget);
    expect(find.text('第2条聊天内容'), findsNothing);
    await pump(tester);
    await tester.pump(const Duration(seconds: 9));
    expect(key.currentState!.visibleCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('moderation, hidden state and a replaced source never leak rows from the old room', (tester) async {
    await pump(tester);
    messages
      ..add(_message(1))
      ..add(_message(2));
    await tester.pump();
    retractions.add(const LiveRetraction.message('1'));
    await tester.pump();
    expect(find.text('第1条聊天内容'), findsNothing);
    expect(find.text('第2条聊天内容'), findsOneWidget);
    await pump(tester, visible: false);
    messages.add(_message(3));
    await tester.pump();
    await pump(tester);
    expect(key.currentState!.visibleCount, 0);
    final other = StreamController<LiveMessage>.broadcast(sync: true);
    await pump(tester, source: other.stream);
    messages.add(_message(4));
    other.add(_message(5));
    await tester.pump();
    expect(find.text('第4条聊天内容'), findsNothing);
    expect(find.text('第5条聊天内容'), findsOneWidget);
    retractions.add(const LiveRetraction.all());
    await tester.pump();
    expect(key.currentState!.visibleCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await other.close();
  });

  testWidgets('hit testing and a held message keep the existing player gesture contract', (tester) async {
    await pump(tester);
    final one = _message(1);
    messages.add(one);
    await tester.pump();
    final point = tester.getCenter(find.text('第1条聊天内容'));
    expect(key.currentState!.messageAt(point), same(one));
    expect(key.currentState!.pinAt(point), same(one));
    messages.add(_message(2));
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('第1条聊天内容'), findsOneWidget);
    expect(find.text('第2条聊天内容'), findsNothing);
    key.currentState!.unpin();
    messages.add(_message(3));
    await tester.pump();
    expect(find.text('第3条聊天内容'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('large text wraps within the bottom clearance and a narrow viewport', (tester) async {
    await pump(tester, textScale: 2, look: const DanmakuLook(fontSize: 28));
    for (var n = 0; n < 8; n++) {
      messages.add(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: '很长很长的观众昵称',
          message: '这是一段较长的消息内容，用来检查放大字体后不会超出屏幕$n',
          color: LiveMessageColor.white,
        ),
      );
    }
    await tester.pump(const Duration(seconds: 1));
    for (final paragraph in find.byType(Text).evaluate()) {
      final box = paragraph.renderObject;
      if (box is RenderBox && box.hasSize) {
        final rect = box.localToGlobal(Offset.zero) & box.size;
        expect(rect.right, lessThanOrEqualTo(393));
        expect(rect.bottom, lessThanOrEqualTo(852 - 100));
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('D04.2 c2: rows of one frame build once, and an older row keeps its measured height', (tester) async {
    await pump(tester);
    messages
      ..add(_message(1))
      ..add(_message(2))
      ..add(_message(3));
    await tester.pump();
    final before = tester.getRect(find.text('第1条聊天内容'));
    messages
      ..add(_message(4))
      ..add(_message(5));
    await tester.pump();
    expect(find.text('第5条聊天内容'), findsOneWidget, reason: 'in the frame it arrived in');
    expect(
      tester.getRect(find.text('第1条聊天内容')),
      before,
      reason: 'its height came from the cache, not from laying it out again',
    );
    expect(key.currentState!.visibleCount, 5);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('D04.2 c2: a message written here is on the screen at once; the rows change before the build does', (
    tester,
  ) async {
    await pump(tester);
    messages.add(
      const LiveMessage(
        type: LiveMessageType.chat,
        userName: '我',
        message: '刚发的一条',
        color: LiveMessageColor.white,
        isLocal: true,
      ),
    );
    await tester.pump();
    expect(find.text('刚发的一条'), findsOneWidget);
    messages.add(_message(7));
    expect(key.currentState!.visibleCount, 2, reason: 'the rows change at once; only the build waits for the frame');
    await tester.pump();
    expect(find.text('第7条聊天内容'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
