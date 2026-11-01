import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/player/bar_parts.dart';
import 'package:pure_live/shared/rooms/playback_hud.dart';
import 'package:pure_live/shared/rooms/playback_hud_config.dart';
import 'package:pure_live/shared/rooms/playback_telemetry.dart';

import '../../support.dart';

void main() {
  setUpAll(() async {
    if (Platform.environment['PURELIVE_HUD_PREVIEW_DIR'] == null) return;
    final font = File('/mnt/c/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      await (FontLoader('HudPreview')..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  for (final portrait in [true, false]) {
    for (final fullscreen in [true, false]) {
      testWidgets('phone portrait=$portrait fullscreen=$fullscreen follows the display policy', (tester) async {
        tester.view
          ..physicalSize = portrait ? const Size(393, 852) : const Size(852, 393)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final services = (await tester.runAsync(testServices))!;
        final strings = (await tester.runAsync(loadStrings))!;
        await tester.runAsync(() => services.store.settings.set(Settings.playbackHud, {'speed': true}));
        var reads = 0;
        final telemetry = PlaybackTelemetry(
          read: () async {
            reads++;
            return const PlaybackStats(downloadBytesPerSecond: 2097152);
          },
        );
        final image = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appServicesProvider.overrideWithValue(services)],
            child: LiveUiScope(
              config: LiveUiConfig(strings: strings.ui),
              child: MaterialApp(
                theme: ThemeData.dark().copyWith(textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'HudPreview')),
                home: Scaffold(
                  body: RepaintBoundary(
                    key: image,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Color(0xff18212b)),
                        Center(
                          child: Text(
                            portrait ? '手机竖屏：播放信息隐藏' : '横屏全屏：紧凑状态信息',
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ),
                        PlaybackHud(
                          telemetry: telemetry,
                          controls: false,
                          phone: true,
                          fullscreen: fullscreen,
                          compactHeader: !portrait,
                          compactLeading: PlayerBattery(read: () async => 80),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        final visible = !portrait && fullscreen;
        expect(find.byKey(const ValueKey('live-play-clock')), visible ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('playback-hud-speed')), visible ? findsOneWidget : findsNothing);
        if (visible) {
          final battery = tester.getRect(find.byKey(const ValueKey('live-play-battery')));
          final clock = tester.getRect(find.byKey(const ValueKey('live-play-clock')));
          expect(clock.left, greaterThan(battery.right));
          expect(clock.left - battery.right, lessThanOrEqualTo(16));
          expect((clock.center.dy - battery.center.dy).abs(), lessThanOrEqualTo(2));
          expect(clock.top, lessThan(40));
          expect(tester.widget<Text>(find.byKey(const ValueKey('live-play-clock'))).style!.fontSize, batteryFontSize);
          expect(tester.widget<Text>(find.byKey(const ValueKey('playback-hud-speed'))).data, isNot(contains('直播流网速')));
          expect(reads, 1);
        } else {
          await tester.pump(const Duration(seconds: 5));
          expect(reads, 0, reason: 'hidden phone information must not poll statistics');
        }
        expect(tester.takeException(), isNull);
        final output = Platform.environment['PURELIVE_HUD_PREVIEW_DIR'];
        if (output != null && fullscreen) {
          final boundary = image.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final file = File('$output/${portrait ? 'portrait-hidden' : 'landscape-compact'}.png');
          await tester.runAsync(() async {
            final pixels = await boundary.toImage(pixelRatio: 2);
            final bytes = (await pixels.toByteData(format: ui.ImageByteFormat.png))!;
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes.buffer.asUint8List());
            pixels.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        telemetry.dispose();
        await tester.runAsync(services.close);
      });
    }
  }

  test('new defaults are compact fullscreen; explicit legacy customization remains intact', () {
    final defaults = PlaybackHudConfig.fromJson(const {});
    expect(defaults.mode, 'fullscreen');
    expect(defaults.corner, 'topLeft');
    expect(defaults.size, batteryFontSize);
    expect(defaults.visible(controls: false), isTrue);
    expect(defaults.visible(controls: true, fullscreen: false), isFalse);
    final custom = PlaybackHudConfig.fromJson(const {
      'mode': 'always',
      'corner': 'bottomRight',
      'size': 32,
      'font': 'mono',
    });
    expect(custom.corner, 'bottomRight');
    expect(custom.size, 32);
    expect(custom.font, 'mono');
    expect(custom.mode, 'always');
  });
}
