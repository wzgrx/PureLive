import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/xiaohongshu/xiaohongshu_api.dart';

/// Public web directory parsing, independent of the visitor bootstrap.
abstract final class XiaohongshuDirectory {
  static Map<Object?, Object?> _map(Object? value) => value is Map ? value : const {};

  static Map<Object?, Object?> _data(String body) {
    if (body.length > 2 * 1024 * 1024) throw const ApiChanged('xiaohongshu', 'directory response too large');
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const ApiChanged('xiaohongshu', 'directory response is not JSON');
    }
    final root = _map(decoded);
    if (root['success'] != true || jsonInt(root['code']) != 0 || root['data'] is! Map) {
      throw ApiChanged('xiaohongshu', 'visitor directory refused (${jsonInt(root['code']) ?? 'unknown'})');
    }
    return _map(root['data']);
  }

  /// Platform-supplied names and ids, including its "all" category.
  static List<LiveCategory> categories(String body) {
    final values = _data(body)['categories'];
    if (values is! List || values.length > 100) throw const ApiChanged('xiaohongshu', 'missing categories');
    final areas = <LiveArea>[];
    final seen = <String>{};
    for (final value in values) {
      final item = _map(value);
      final id = jsonString(item['id']) ?? '';
      final name = jsonString(item['desc']) ?? '';
      if (!RegExp(r'^\d{1,8}$').hasMatch(id) || name.isEmpty || name.length > 100 || !seen.add(id)) continue;
      areas.add(LiveArea(platform: 'xiaohongshu', areaType: 'live', areaId: id, areaName: name));
    }
    return areas.isEmpty ? const [] : [LiveCategory(id: 'live', name: '小红书', children: areas)];
  }

  /// A feed carries a score on each row. The endpoint is inclusive at the
  /// tail: a repeated final score terminates paging, even if it repeats a
  /// room. Never fabricate a page number or infer exhaustion from row count.
  static LiveDirectoryPage page(String body, {required int page, required String cursor}) {
    final values = _data(body)['feeds'];
    if (values is! List || values.length > 200) throw const ApiChanged('xiaohongshu', 'missing feeds');
    final rooms = <LiveRoom>[];
    final seen = <String>{};
    String? next;
    for (final value in values) {
      final row = _map(value);
      final score = jsonString(row['cursor_score']);
      if (score != null && score.isNotEmpty && score.length <= 128) next = score;
      if (row['type'] != 'live' || row['model_type'] != 'live_v2') continue;
      final live = _map(row['live']);
      final info = _map(live['t_room_info']);
      final host = _map(live['t_live_host_info']);
      // JS numbers lose precision for these ids. The API's explicit string
      // wins even if the numeric room_id disagrees; no id is read from a URL.
      final id = jsonString(info['room_id_str']) ?? jsonString(info['room_id']) ?? '';
      if (!XiaohongshuApi.isRoomId(id) || !seen.add(id)) continue;
      final online = jsonCount(info['member_count']);
      final total = jsonCount(info['uv']);
      rooms.add(
        LiveRoom(
          platform: 'xiaohongshu',
          roomId: id,
          userId: jsonString(host['user_id']) ?? '',
          title: jsonString(info['name']) ?? '',
          nick: jsonString(host['nickname']) ?? '',
          avatar: normalizeImageUrl(host['avatar']),
          cover: normalizeImageUrl(info['cover']),
          link: XiaohongshuApi.roomUrl(id).toString(),
          watching: total?.toString() ?? online?.toString() ?? '',
          audienceMetricType: total != null ? AudienceMetricType.totalViewers : AudienceMetricType.onlineViewers,
          onlineViewers: online?.toString() ?? '',
          totalViewers: total?.toString() ?? '',
          liveStatus: LiveStatus.live,
        ),
      );
    }
    final hasMore = values.isNotEmpty && next != null && next != cursor;
    return LiveDirectoryPage(rooms: rooms, page: page, hasMore: hasMore, nextCursor: hasMore ? next : null);
  }
}
