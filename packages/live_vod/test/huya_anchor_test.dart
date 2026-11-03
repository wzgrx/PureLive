import 'package:live_vod/live_vod.dart';
import 'package:test/test.dart';

String playlist({bool reset = true, int count = 8}) =>
    '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:5
#EXT-X-MEDIA-SEQUENCE:100
#EXT-X-PLAYLIST-TYPE:VOD
${[for (var i = 0; i < count; i++) '${reset && i == 3 ? '#EXT-X-DISCONTINUITY\n' : ''}#EXTINF:5.0,\npart$i.ts?token=ephemeral'].join('\n')}
#EXT-X-ENDLIST
'''
        .trimLeft();

void main() {
  final source = Uri.parse('https://cdn.huya.com/record/index.m3u8?definition=original');
  HuyaArchiveAnchor? parse(String text, int seconds) => HuyaArchiveAnchor.parse(
    text,
    source: source,
    at: Duration(seconds: seconds),
  );
  test('resolves a global seek to a short native seek after an HLS timestamp reset (#163)', () {
    final anchor = parse(playlist(), 26)!;
    expect(anchor.offset, const Duration(seconds: 20));
    expect(anchor.start, const Duration(seconds: 6));
    expect(anchor.duration, const Duration(seconds: 40));
    expect(anchor.playlist, contains('#EXT-X-MEDIA-SEQUENCE:104'));
    expect(anchor.playlist, contains('#EXT-X-DISCONTINUITY-SEQUENCE:1'));
    expect(anchor.playlist, contains('https://cdn.huya.com/record/part4.ts?token=ephemeral'));
    expect(anchor.playlist, isNot(contains('/part3.ts')));
  });
  test('never retains pre-roll from another epoch and preserves later resets', () {
    final atReset = parse(playlist(), 15)!;
    expect(atReset.offset, const Duration(seconds: 15));
    expect(atReset.start, Duration.zero);
    expect(atReset.playlist, isNot(contains('#EXT-X-DISCONTINUITY\n')));
    final before = parse(playlist(), 6)!;
    expect(before.offset, Duration.zero);
    expect(before.playlist, contains('#EXT-X-DISCONTINUITY\n'));
    expect(parse(playlist(), 40)!.start, lessThan(const Duration(seconds: 10)));
  });
  test('continuous recordings and position zero retain the native input', () {
    expect(parse(playlist(reset: false), 26), isNull);
    expect(parse(playlist(), 0), isNull);
  });
  test('long recordings retain their early target, not only the final 2048 segments', () {
    final anchor = parse(playlist(count: 10000), 26)!;
    expect(anchor.duration, const Duration(seconds: 50000));
    expect(anchor.playlist, contains('/part4.ts'));
    expect(anchor.playlist, contains('/part9999.ts'));
  });
  test('rejects incomplete, encrypted, ranged, foreign-origin or malformed manifests', () {
    for (final text in [
      playlist().replaceAll('#EXT-X-ENDLIST', ''),
      playlist().replaceFirst('#EXTINF:', '#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:'),
      playlist().replaceFirst('#EXTINF:', '#EXT-X-BYTERANGE:4@0\n#EXTINF:'),
      playlist().replaceFirst('part0.ts?token=ephemeral', 'file:///etc/passwd'),
      playlist().replaceFirst('part0.ts?token=ephemeral', 'https://other.example/part.ts'),
      playlist().replaceFirst('5.0,', 'NaN,'),
    ]) {
      expect(() => parse(text, 26), throwsFormatException);
    }
  });
}
