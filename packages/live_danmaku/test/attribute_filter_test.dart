import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

LiveMessage _chat({
  LiveMessageColor color = LiveMessageColor.white,
  int? user,
  int? fan,
  String displayUser = '',
  String displayFan = '',
  bool local = false,
  bool bot = false,
  String id = '',
}) => LiveMessage(
  type: LiveMessageType.chat,
  userName: 'synthetic viewer',
  message: 'hello',
  color: color,
  userLevelValue: user,
  fansLevelValue: fan,
  userLevel: displayUser,
  fansLevel: displayFan,
  isLocal: local,
  suspectedAutomated: bot,
  messageId: id,
);

void main() {
  test('Douyu packets keep numeric zero even when display badges are empty', () {
    final message = DouyuDanmakuProtocol.decode(
      DouyuDanmakuProtocol.packet(
        'type@=chatmsg/rid@=1/uid@=synthetic/nn@=viewer/txt@=hello/level@=0/bl@=0/dms@=1/',
        type: DouyuDanmakuProtocol.serverPacketType,
      ),
      roomId: '1',
    ).single;
    expect(message.userLevel, isEmpty);
    expect(message.fansLevel, isEmpty);
    expect(message.userLevelValue, 0);
    expect(message.fansLevelValue, 0);
    expect(
      DanmakuMessageFilter(settings: const DanmakuFilterSettings(minUserLevel: 1)).judge(message),
      DanmakuVerdict.blocked,
    );
  });
  test('new attribute filters are off by default, including explicit zero and tagged bots', () {
    final filter = DanmakuMessageFilter();
    expect(filter.judge(_chat(user: 0, fan: 0, bot: true)), DanmakuVerdict.shown);
  });
  test('colored-only uses source chroma and rejects white, gray and black', () {
    for (final color in [
      LiveMessageColor.white,
      const LiveMessageColor(128, 128, 128),
      const LiveMessageColor(0, 0, 0),
    ]) {
      final filter = DanmakuMessageFilter(settings: const DanmakuFilterSettings(coloredOnly: true));
      expect(filter.judge(_chat(color: color)), DanmakuVerdict.blocked);
    }
    final filter = DanmakuMessageFilter(settings: const DanmakuFilterSettings(coloredOnly: true));
    expect(filter.judge(_chat(color: const LiveMessageColor(30, 135, 240))), DanmakuVerdict.shown);
    expect(filter.judge(_chat(local: true, id: 'local')), DanmakuVerdict.shown);
  });
  test('minimum levels distinguish an explicit zero from unknown metadata', () {
    final filter = DanmakuMessageFilter(settings: const DanmakuFilterSettings(minUserLevel: 10, minFansLevel: 3));
    expect(filter.judge(_chat(user: 0, id: 'zero-user')), DanmakuVerdict.blocked);
    expect(filter.judge(_chat(user: 10, fan: 0, id: 'zero-badge')), DanmakuVerdict.blocked);
    expect(filter.judge(_chat(user: 10, fan: 3, id: 'boundary')), DanmakuVerdict.shown);
    expect(filter.judge(_chat(id: 'unknown')), DanmakuVerdict.shown);
    expect(filter.judge(_chat(displayUser: '9', id: 'legacy')), DanmakuVerdict.blocked);
    expect(filter.judge(_chat(displayUser: 'VIP', displayFan: '?', id: 'labels')), DanmakuVerdict.shown);
    expect(filter.judge(_chat(user: -1, fan: -1, id: 'invalid')), DanmakuVerdict.shown);
  });
  test('hot updates apply without reconnecting and local chat remains exempt', () {
    final filter = DanmakuMessageFilter();
    expect(filter.judge(_chat(user: 1, id: 'before')), DanmakuVerdict.shown);
    filter.settings = const DanmakuFilterSettings(minUserLevel: 5, filterSuspectedAutomated: true);
    expect(filter.judge(_chat(user: 1, id: 'after')), DanmakuVerdict.blocked);
    expect(filter.judge(_chat(bot: true, id: 'bot')), DanmakuVerdict.blocked);
    expect(filter.judge(_chat(user: 1, bot: true, local: true, id: 'local')), DanmakuVerdict.shown);
    expect(filter.judge(_chat(bot: true, id: 'bot')), DanmakuVerdict.duplicate);
  });
  test('cleaning text preserves numeric zero and automation metadata', () {
    const input = LiveMessage(
      type: LiveMessageType.chat,
      userName: 'viewer',
      message: 'a\uFFFC',
      color: LiveMessageColor.white,
      userLevelValue: 0,
      fansLevelValue: 0,
      suspectedAutomated: true,
    );
    final clean = cleanDanmakuText(input);
    expect(clean.message, 'a');
    expect(clean.userLevelValue, 0);
    expect(clean.fansLevelValue, 0);
    expect(clean.suspectedAutomated, isTrue);
  });
}
