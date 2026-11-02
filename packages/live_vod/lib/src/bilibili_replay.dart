import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_vod/src/client.dart';
import 'package:live_vod/src/models.dart';
import 'package:live_vod/src/parse.dart';
import 'package:live_vod/src/streams.dart';
import 'package:live_vod/src/ugc_api.dart';
import 'package:meta/meta.dart';

/// An official creator-owned replay collection, never inferred from video titles.
@immutable
final class ReplayCollection {
  /// Identifies the collection in its own namespace.
  const new({required this.id, required this.name, this.season = false, this.updated = 0});

  /// Numeric series/season id.
  final int id;

  /// Label supplied by the creator.
  final String name;

  /// Seasons and series use different endpoints.
  final bool season;

  /// Last update, when the platform supplies it.
  final int updated;

  /// Stable key for selection; series and season ids may collide.
  String get key => '${season ? 'season' : 'series'}:$id';
}

/// Replaceable, read-only Bilibili replay contract.
abstract interface class BilibiliReplaySource {
  /// Only creator collections explicitly labelled as broadcast recordings.
  Future<VodPage<ReplayCollection>> collections(int mid, {int page = 1, CancelToken? cancel});

  /// Newest-first official recordings within the chosen collection.
  Future<VodPage<VodArchive>> list(int mid, ReplayCollection collection, {int page = 1, CancelToken? cancel});

  /// Full parts and actual author identity.
  Future<VodArchive> detail(String bvid);

  /// Renditions permitted by the current local account, guests included.
  Future<VodStreams> streams(String bvid, int cid, {int qn = 0});
}

/// Official series/season APIs with the existing local login and proxy transport.
final class BilibiliReplayApi implements BilibiliReplaySource {
  /// Uses the same client as ordinary on-demand playback.
  const new(this.client);

  /// Shared request plumbing.
  final BilibiliVodClient client;
  static final _label = RegExp(r'直播[\s·・_-]*(?:回放|回看|录像|录播)|live[\s_-]*(?:replay|archive|vod)', caseSensitive: false);
  static void _bounds(int mid, int page) {
    if (mid <= 0 || page < 1 || page > 10000) throw const FormatException('Invalid replay page');
  }

  @override
  Future<VodPage<ReplayCollection>> collections(int mid, {int page = 1, CancelToken? cancel}) async {
    _bounds(mid, page);
    final response = await client.get(
      Uri.https('api.bilibili.com', '/x/polymer/web-space/seasons_series_list'),
      query: {'mid': mid, 'page_num': page, 'page_size': 20},
      referer: 'https://space.bilibili.com/$mid/',
      cancel: cancel,
    );
    return parseCollections(response.text, mid: mid, page: page, status: response.status);
  }

  /// Validates the creator id and collection shape; unrelated uploads stay out.
  static VodPage<ReplayCollection> parseCollections(
    String body, {
    required int mid,
    required int page,
    int status = 200,
  }) {
    final data = VodParse.object(VodParse.data(body, status: status, what: 'replay collections'));
    final lists = VodParse.object(data?['items_lists']);
    if (lists == null || lists['series_list'] is! List || lists['seasons_list'] is! List) {
      throw const ApiChanged('bilibili', 'Replay collections missing');
    }
    final result = <ReplayCollection>[];
    final seen = <String>{};
    for (final season in [false, true]) {
      for (final item in VodParse.list(lists[season ? 'seasons_list' : 'series_list']).map(VodParse.object).nonNulls) {
        final meta = VodParse.object(item['meta']);
        final owner = jsonInt(meta?['mid']);
        final id = jsonInt(meta?[season ? 'season_id' : 'series_id']);
        final name = jsonString(meta?['name']) ?? '';
        if (owner != mid || id == null || id <= 0 || !_label.hasMatch(name)) continue;
        final collection = ReplayCollection(
          id: id,
          name: name,
          season: season,
          updated: jsonInt(meta?['last_update_ts']) ?? jsonInt(meta?['mtime']) ?? jsonInt(meta?['ptime']) ?? 0,
        );
        if (seen.add(collection.key)) result.add(collection);
      }
    }
    result.sort((a, b) => b.updated.compareTo(a.updated));
    final paging = VodParse.object(lists['page']);
    return VodPage(List.unmodifiable(result), hasMore: page * 20 < (jsonInt(paging?['total']) ?? 0));
  }

  @override
  Future<VodPage<VodArchive>> list(int mid, ReplayCollection collection, {int page = 1, CancelToken? cancel}) async {
    _bounds(mid, page);
    if (collection.id <= 0) throw const FormatException('Invalid replay collection');
    final response = await client.get(
      Uri.https(
        'api.bilibili.com',
        collection.season ? '/x/polymer/web-space/seasons_archives_list' : '/x/series/archives',
      ),
      query: collection.season
          ? {'mid': mid, 'season_id': collection.id, 'sort_reverse': false, 'page_num': page, 'page_size': 20}
          : {'mid': mid, 'series_id': collection.id, 'only_normal': true, 'sort': 'desc', 'pn': page, 'ps': 20},
      referer: 'https://space.bilibili.com/$mid/',
      cancel: cancel,
    );
    return parsePage(response.text, page: page, status: response.status);
  }

  /// Dates and durations come from the platform; malformed rows are omitted.
  static VodPage<VodArchive> parsePage(String body, {required int page, int status = 200}) {
    final data = VodParse.object(VodParse.data(body, status: status, what: 'replay recordings'));
    if (data?['archives'] is! List) throw const ApiChanged('bilibili', 'Replay recordings missing');
    final rows = VodParse.list(data?['archives']);
    if (rows.length > 100) throw const ApiChanged('bilibili', 'Replay page too large');
    final seen = <String>{};
    final videos = [
      for (final v in rows.map(VodParse.archive).nonNulls)
        if (RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(v.bvid) && v.title.isNotEmpty && seen.add(v.bvid)) v,
    ]..sort((a, b) => (b.publishedAt ?? DateTime(1970)).compareTo(a.publishedAt ?? DateTime(1970)));
    final paging = VodParse.object(data?['page']);
    return VodPage(List.unmodifiable(videos), hasMore: rows.isNotEmpty && page * 20 < (jsonInt(paging?['total']) ?? 0));
  }

  @override
  Future<VodArchive> detail(String bvid) => BilibiliUgcApi(client).detail(bvid);
  @override
  Future<VodStreams> streams(String bvid, int cid, {int qn = 0}) =>
      BilibiliUgcApi(client).streams(bvid: bvid, cid: cid, qn: qn);
}

/// Resolves public room ids separately from live playback/offline metadata.
final class ReplayIdentityApi {
  /// Cookies are only attached to their own platform's API host.
  const new(this.http, {this.cookies});

  /// Shared platform-routed HTTP transport.
  final LiveHttp http;

  /// The existing encrypted local account store.
  final CookieVault? cookies;

  /// A room number is never treated as a presenter uid.
  Future<String> resolve(String platform, String room, {CancelToken? cancel}) async {
    if (!{SiteIds.huya, SiteIds.douyu, SiteIds.bilibili}.contains(platform) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(room)) {
      throw const FormatException('Invalid replay room');
    }
    final url = switch (platform) {
      SiteIds.huya => Uri.https('mp.huya.com', '/cache.php', {
        'm': 'Live',
        'do': 'profileRoom',
        'roomid': room,
        'showSecret': '1',
      }),
      SiteIds.douyu => Uri.https('www.douyu.com', '/betard/$room'),
      _ => Uri.https('api.live.bilibili.com', '/room/v1/Room/room_init', {'id': room}),
    };
    final cookie = cookies?.cookieFor(platform)?.replaceAll(RegExp(r'[\r\n]'), '') ?? '';
    final response = await http.send(
      LiveRequest(
        site: platform,
        url: url,
        cancel: cancel,
        headers: {
          'user-agent': BilibiliApi.userAgent,
          'referer': switch (platform) {
            SiteIds.huya => 'https://www.huya.com/',
            SiteIds.douyu => 'https://www.douyu.com/',
            _ => 'https://live.bilibili.com/',
          },
          if (cookie.isNotEmpty) 'cookie': cookie,
        },
      ),
    );
    if (response.status == 403 || response.status == 412 || response.status == 429) {
      throw RiskControl(platform, detail: 'Replay identity refused');
    }
    if (!response.isSuccess) throw NetworkFailure(platform, 'Replay identity HTTP ${response.status}');
    final data = platform == SiteIds.bilibili
        ? VodParse.object(VodParse.data(response.text, status: response.status, what: 'replay room'))
        : null;
    // Huya and Douyu are not Bilibili envelopes. Read the original object.
    return identity(response.text, platform: platform, fallback: data);
  }

  /// Reads independently recorded public identity envelopes.
  static String identity(String body, {required String platform, Map<String, dynamic>? fallback}) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(platform, 'Replay identity response changed');
    }
    final root = VodParse.object(decoded);
    final data = VodParse.object(root?['data']) ?? fallback;
    final value = switch (platform) {
      SiteIds.huya => VodParse.object(data?['profileInfo'])?['uid'],
      SiteIds.douyu => VodParse.object(root?['room'])?['up_id'],
      _ => data?['uid'],
    };
    final id = value?.toString() ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id) || id == '0') {
      throw ApiChanged(platform, 'Replay presenter identity missing');
    }
    return id;
  }
}
