import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/tv/room/tv_room_overlays.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';

import '../qa_capture.dart';
import '../support.dart';

void main() {
  setUpAll(loadStrings);
  testWidgets('issue112 only the focused room title scrolls and names are bold', (tester) async {
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = const LiveTheme().dark;
    final rooms = [
      for (var i = 0; i < 3; i++)
        LiveRoom(platform: SiteIds.bilibili, roomId: '$i', nick: '主播$i', title: '超长标题$i ${'户外直播 Outdoor live ' * 8}'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: TvTheme(
          palette: TvPalette.of(theme.colorScheme),
          child: Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: TvRoomList(rooms: rooms, current: 0, onPick: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    final first = find.byKey(const ValueKey('tv-room-list-0'));
    Finder transform(Finder row) => find.descendant(of: row, matching: find.byType(Transform));
    expect(tester.widget<Text>(find.text('主播0')).style!.fontWeight, FontWeight.w700);
    expect(tester.widget<TvMarquee>(find.descendant(of: first, matching: find.byType(TvMarquee))).running, isTrue);
    expect(tester.widget<Transform>(transform(first).last).transform.getTranslation().x, lessThan(0));
    await captureQaFrame(tester, 'issue112-focused-title');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<TvMarquee>(find.descendant(of: first, matching: find.byType(TvMarquee))).running, isFalse);
    final second = find.byKey(const ValueKey('tv-room-list-1'));
    expect(tester.widget<TvMarquee>(find.descendant(of: second, matching: find.byType(TvMarquee))).running, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
