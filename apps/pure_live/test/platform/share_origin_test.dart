import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/platform/plugins.dart';
import 'package:pure_live/shared/rooms/share_code.dart';

void main() {
  test('A18.1 c7: an iPad share sheet always gets a place: the tapped button, else the middle of the window', () {
    const button = Rect.fromLTWH(900, 20, 48, 48);
    expect(sheetOrigin(button, platform: TargetPlatform.iOS), button);
    expect(
      sheetOrigin(null, platform: TargetPlatform.iOS, window: const Size(1180, 820)),
      Rect.fromCenter(center: const Offset(590, 410), width: 1, height: 1),
      reason: 'share_plus fails on an iPad without one (the log share has no button)',
    );
    expect(
      sheetOrigin(Rect.zero, platform: TargetPlatform.iOS, window: const Size(100, 100))?.center,
      const Offset(50, 50),
    );
    expect(sheetOrigin(null, platform: TargetPlatform.android), isNull, reason: 'Android is unchanged');
  });

  testWidgets("the place is the tapped widget's rectangle on screen", (tester) async {
    Rect? origin;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Builder(
              builder: (context) => IconButton(
                key: const ValueKey('share'),
                onPressed: () => origin = shareOrigin(context),
                icon: const Icon(Icons.share),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('share')));
    expect(origin, tester.getRect(find.byKey(const ValueKey('share'))));
  });
}
