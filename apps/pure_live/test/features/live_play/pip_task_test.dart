import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pure_live/pip');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    PictureInPicture.debugAndroid = null;
    PictureInPicture.active.value = false;
  });

  test('issue194: retiring a task resets cached PiP without a final native callback', () async {
    PictureInPicture.debugAndroid = true;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'isSupported' ? true : null;
    });
    await PictureInPicture.supported();
    PictureInPicture.active.value = true;
    await PictureInPicture.closeTask();
    expect(calls, contains('closeTask'));
    expect(PictureInPicture.active.value, isFalse);

    // The same engine still accepts the recreated Activity's current state.
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('changed', true)),
      (_) {},
    );
    expect(PictureInPicture.active.value, isTrue);
  });
}
