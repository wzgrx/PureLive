import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/tv/room/tv_room_overlays.dart';
import 'package:pure_live/tv/tv_theme.dart';

import '../qa_capture.dart';
import '../support.dart';

void main() {
  setUpAll(loadStrings);
  for (final size in [const Size(1920, 1080), const Size(1280, 720), const Size(740, 360)]) {
    for (final factor in [1.0, 1.5, 2.0]) {
      testWidgets('issue91: room list remains readable and navigable at $size / $factor', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final theme = const LiveTheme().dark;
        var picked = -1;
        final rooms = [
          for (var i = 0; i < 8; i++)
            LiveRoom(
              platform: SiteIds.bilibili,
              roomId: '$i',
              nick: '主播$i的长名称',
              title: '直播$i：远距离阅读与长标题省略展示验证',
              liveStatus: LiveStatus.live,
            ),
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: MediaQuery(
              data: MediaQueryData(size: size, textScaler: TextScaler.linear(factor)),
              child: TvTheme(
                palette: TvPalette.of(theme.colorScheme),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.centerLeft,
                    child: TvRoomList(rooms: rooms, current: 0, onPick: (index) => picked = index),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        final row = find.byKey(const ValueKey('tv-room-list-0'));
        final title = find.descendant(of: row, matching: find.text(rooms.first.title)).first;
        final name = find.descendant(of: row, matching: find.text(rooms.first.nick));
        final bounds = tester.getRect(row);
        expect(tester.getRect(title).bottom, lessThanOrEqualTo(tester.getRect(name).top));
        expect(tester.getRect(name).bottom, lessThanOrEqualTo(bounds.bottom));
        expect(bounds.right, lessThanOrEqualTo(size.width));
        // The secondary line must meet the common 14px TV canvas minimum.
        final unit = TvScale.of(tester.element(row)).unit;
        expect(tester.widget<Text>(name).style!.fontSize, greaterThanOrEqualTo(28 * unit));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump(const Duration(seconds: 1));
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(picked, 1);
        expect(tester.takeException(), isNull);
        if (factor == 1.5) await captureQaFrame(tester, 'issue91-${size.width.toInt()}-150');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
