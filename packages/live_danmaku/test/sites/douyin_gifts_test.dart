import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_danmaku/src/gift_progress.dart';
import 'package:test/test.dart';

List<int> giftFrame({
  int quantity = 3,
  int end = 0,
  int group = 77,
  int room = 1234,
  bool metadata = true,
  int event = 9001,
}) {
  final common =
      (ProtoWriter()
            ..integer(2, event)
            ..integer(3, room)
            ..integer(4, 1600000000))
          .toBytes();
  final user =
      (ProtoWriter()
            ..integer(1, 41)
            ..string(3, '测试赠送人'))
          .toBytes();
  final receiver =
      (ProtoWriter()
            ..integer(1, 51)
            ..string(3, '测试主播'))
          .toBytes();
  final image = (ProtoWriter()..string(1, 'https://gift.example.test/rose.png')).toBytes();
  final gift =
      (ProtoWriter()
            ..bytes(1, image)
            ..integer(5, 685)
            ..integer(10, 1)
            ..integer(11, 1)
            ..integer(12, 6)
            ..string(16, '玫瑰'))
          .toBytes();
  final payload = ProtoWriter()
    ..bytes(1, common)
    ..integer(2, 685)
    ..integer(4, 1)
    ..integer(5, quantity)
    ..integer(6, quantity)
    ..bytes(7, user)
    ..bytes(8, receiver)
    ..integer(9, end)
    ..integer(11, group);
  if (metadata) payload.bytes(15, gift);
  final envelope =
      (ProtoWriter()
            ..string(1, 'WebcastGiftMessage')
            ..bytes(2, payload.toBytes())
            ..integer(3, event))
          .toBytes();
  final response =
      (ProtoWriter()
            ..bytes(1, envelope)
            ..string(5, 'synthetic-ack')
            ..integer(9, 1))
          .toBytes();
  return (ProtoWriter()
        ..integer(2, 91)
        ..bytes(8, response))
      .toBytes();
}

void main() {
  test('group progress and ending snapshots never repeat or reduce displayed totals', () {
    final gate = GiftSnapshotGate();
    final accepted = <LiveMessage>[];
    for (final quantity in [1, 2, 5, 5, 3, 6, 6]) {
      final message = DouyinDanmakuProtocol.decode(
        giftFrame(quantity: quantity, event: 9000 + quantity),
        roomId: '1234',
      ).messages.single;
      if (gate.accept(message)) accepted.add(message);
    }
    expect(accepted.map((message) => message.gift!.comboTotal ?? message.gift!.count), [1, 2, 5, 6]);
    var shown = 0;
    for (final message in accepted) {
      shown = shown == 0 ? giftComboStart(message.gift!) : giftComboTotal(shown, message.gift!);
    }
    expect(shown, 6);
    expect(giftValueOfCount(accepted.last.gift!, shown), 36);
    expect(gate.length, 1);
  });
  test('unknown metadata keeps the gift id/quantity, without invented price or icon', () {
    final message = DouyinDanmakuProtocol.decode(giftFrame(metadata: false), roomId: '1234').messages.single;
    expect(message.gift!.id, '685');
    expect(message.gift!.unitPrice, isNull);
    expect(message.gift!.totalValue, isNull);
    expect(message.gift!.iconUrl, isNull);
    expect(message.gift!.free, isFalse);
    expect(message.message, isNotEmpty);
  });
  test('another broadcast is rejected but acknowledgements are preserved', () {
    final frame = DouyinDanmakuProtocol.decode(giftFrame(room: 999), roomId: '1234');
    expect(frame.messages, isEmpty);
    expect(frame.ack, isNotNull);
  });
  test('a malformed gift count loses only that envelope and a new group remains independent', () {
    final bad = DouyinDanmakuProtocol.decode(giftFrame(quantity: -1), roomId: '1234');
    expect(bad.messages, isEmpty);
    expect(bad.errors, hasLength(1));
    expect(bad.ack, isNotNull);
    final gate = GiftSnapshotGate(capacity: 2);
    for (var group = 1; group <= 3; group++) {
      expect(
        gate.accept(DouyinDanmakuProtocol.decode(giftFrame(group: group), roomId: '1234').messages.single),
        isTrue,
      );
    }
    expect(gate.length, 2);
    gate.clear();
    expect(gate.length, 0);
  });

  test('WebcastGiftMessage reaches the existing typed gift UI data contract', () {
    final frame = DouyinDanmakuProtocol.decode(giftFrame(), roomId: '1234');
    expect(frame.ack, isNotNull);
    expect(frame.messages, hasLength(1));
    final message = frame.messages.single;
    expect(message.type, LiveMessageType.gift);
    expect(message.userName, '测试赠送人');
    expect(message.gift!.name, '玫瑰');
    expect(message.gift!.id, '685');
    expect(message.gift!.unit, LiveGiftUnit.douyinCoin);
    expect(message.gift!.unitPrice, 6);
    expect(message.gift!.count, 3);
    expect(message.gift!.totalValue, 18);
    expect(message.gift!.comboTotal, 3);
    expect(message.gift!.iconUrl.toString(), 'https://gift.example.test/rose.png');
    expect(message.gift!.receiverName, '测试主播');
    expect(message.message, isNotEmpty);
  });
}
