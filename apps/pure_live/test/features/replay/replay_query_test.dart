import 'package:flutter_test/flutter_test.dart';
import 'package:live_vod/live_vod.dart';
import 'package:pure_live/features/replay/replay_query.dart';
import 'package:pure_live/shared/rooms/archive/archive_recording.dart';

ArchiveRecording entry(String title, {DateTime? date, String author = 'Alice'}) => ArchiveRecording(
  HuyaArchiveVideo(id: '123', title: title, authorId: '456', authorName: author),
  title: title,
  cover: '',
  date: date,
  duration: Duration.zero,
);

void main() {
  test('keywords are literal case-insensitive AND terms over title and author', () {
    final query = ReplayCatalogQuery(keyword: '  复盘  ALICE ');
    expect(query.matches(entry('周末复盘')), isTrue);
    expect(query.matches(entry('周末聊天')), isFalse);
    expect(ReplayCatalogQuery(keyword: '.*').matches(entry('正常标题')), isFalse);
    expect(ReplayCatalogQuery(keyword: '.*').matches(entry('标题包含.*')), isTrue);
    expect(ReplayCatalogQuery().matches(entry('无日期')), isTrue);
  });
  test('calendar ranges include both whole boundary days and exclude unknown dates', () {
    final query = ReplayCatalogQuery(from: DateTime(2026, 11, 1, 12), through: DateTime(2026, 11, 3, 12));
    expect(query.matches(entry('a', date: DateTime(2026, 11))), isTrue);
    expect(query.matches(entry('b', date: DateTime(2026, 11, 3, 23, 59))), isTrue);
    expect(query.matches(entry('c', date: DateTime(2026, 11, 4))), isFalse);
    expect(query.matches(entry('d', date: DateTime(2026, 10, 31, 23, 59))), isFalse);
    expect(query.matches(entry('unknown')), isFalse);
  });
  test('presets cross year boundaries, retain keywords and clear their dates', () {
    final query = ReplayCatalogQuery(keyword: '复盘').preset('week', DateTime(2026, 1, 3, 16));
    expect(query.from, DateTime(2025, 12, 28));
    expect(query.through, DateTime(2026, 1, 3));
    expect(query.keyword, '复盘');
    final yesterday = query.preset('yesterday', DateTime(2026));
    expect(yesterday.from, DateTime(2025, 12, 31));
    expect(yesterday.through, yesterday.from);
    final all = yesterday.preset('all', DateTime(2026));
    expect(all.from, isNull);
    expect(all.through, isNull);
    expect(all.keyword, '复盘');
  });
}
