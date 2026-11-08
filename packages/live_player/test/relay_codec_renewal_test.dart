import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/src/session.dart';

void main() {
  test('a reordered renewal can never splice a different codec into the open input', () {
    const current = LivePlayLine('https://example.test/old', lineId: 'cdn:hevc', codec: 'hevc');
    const collision = LivePlayLine('https://example.test/avc', lineId: 'cdn:hevc', codec: 'avc');
    const other = LivePlayLine('https://example.test/new', lineId: 'other:hevc', codec: 'hevc');
    const exact = LivePlayLine('https://example.test/renewed', lineId: 'cdn:hevc', codec: 'hevc');
    expect(selectRelayRenewal(current, [collision, other, exact], previousIndex: 0), same(exact));
    expect(selectRelayRenewal(current, [collision, other], previousIndex: 0), same(other));
    expect(() => selectRelayRenewal(current, [collision], previousIndex: 0), throwsStateError);
  });
}
