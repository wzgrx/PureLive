import 'package:flutter/foundation.dart';
import 'package:pure_live/shared/rooms/archive/archive_recording.dart';

/// A15.6: literal keyword and inclusive local-calendar dates for one catalog.
@immutable
final class ReplayCatalogQuery {
  /// No filter by default; unknown dates remain visible in the full catalog.
  new({this.keyword = '', DateTime? from, DateTime? through})
    : from = from == null ? null : DateTime(from.year, from.month, from.day),
      through = through == null ? null : DateTime(through.year, through.month, through.day),
      _terms = keyword
          .trim()
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((term) => term.isNotEmpty)
          .toList(growable: false);

  final List<String> _terms;

  /// Whitespace-separated terms all match the title or creator name.
  final String keyword;

  /// First local day, inclusive.
  final DateTime? from;

  /// Last local day, inclusive.
  final DateTime? through;

  /// Whether more pages may be needed to find matches.
  bool get active => keyword.trim().isNotEmpty || from != null || through != null;

  /// The available metadata satisfies this query; no regex or remote claims.
  bool matches(ArchiveRecording entry) {
    final haystack = '${entry.title} ${entry.author}'.toLowerCase();
    if (!_terms.every(haystack.contains)) return false;
    if (from == null && through == null) return true;
    final raw = entry.date;
    if (raw == null) return false;
    final local = raw.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (from != null && day.isBefore(from!)) return false;
    if (through != null && day.isAfter(through!)) return false;
    return true;
  }

  /// A preset preserves keywords and uses calendar-day boundaries, not UTC.
  ReplayCatalogQuery preset(String id, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (id == 'all') return ReplayCatalogQuery(keyword: keyword);
    if (id == 'yesterday') {
      final day = DateTime(today.year, today.month, today.day - 1);
      return ReplayCatalogQuery(keyword: keyword, from: day, through: day);
    }
    final days = switch (id) {
      'today' => 1,
      'three' => 3,
      'week' => 7,
      'month' => 30,
      'quarter' => 90,
      'year' => 365,
      _ => 1,
    };
    return ReplayCatalogQuery(
      keyword: keyword,
      from: DateTime(today.year, today.month, today.day - days + 1),
      through: today,
    );
  }
}
