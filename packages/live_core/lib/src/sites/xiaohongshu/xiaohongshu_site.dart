import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/xiaohongshu/xiaohongshu_api.dart';
import 'package:live_core/src/sites/xiaohongshu/xiaohongshu_directory.dart';
import 'package:live_core/src/sites/xiaohongshu/xiaohongshu_guest.dart';
import 'package:live_net/live_net.dart';

const _site = 'xiaohongshu';

/// How long a search may spend on a short link, and each of its requests
/// (3.x's search session).
const _shortLinkTimeout = Duration(seconds: 12);

/// The Xiaohongshu adapter (3.x's `XiaohongshuSite`, `XiaohongshuApi` and
/// `XiaohongshuLink`; parsing in [XiaohongshuApi]).
///
/// Public share-page playback keeps the existing restriction and stream URL
/// checks. Shells with a visitor bootstrap also expose native categories,
/// caller-owned cursor pages and non-secret room chat arguments (E02.16).
/// A follow still identifies this broadcast, not the streamer's next room.
/// Errors remain typed; bootstrap refusals are never disguised as offline.
final class XiaohongshuSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteCursorDirectoryPager,
        LiveDirectoryNotice,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter.
  new(this.http, {this.guest});

  /// Transport.
  final LiveHttp http;

  /// Anonymous web session, injected only where the browser backend exists.
  final XiaohongshuGuest? guest;

  @override
  String get id => _site;

  @override
  String get name => '小红书';

  /// 3.x's `xiaohongshu_directory_scope` (text: [XiaohongshuApi.directoryScope]).
  @override
  String get directoryNoticeKey => guest == null ? 'xiaohongshu_directory_scope' : 'xiaohongshu_guest_directory_scope';

  // Requests ------------------------------------------------------------------

  /// The share page of [roomId]: a room id that is not one is `NotFound`
  /// without a request; the page is read without following redirects (it
  /// must be the page asked for).
  Future<LiveResponse> _page(String roomId) async {
    if (!XiaohongshuApi.isRoomId(roomId)) throw NotFound(_site, 'room id "$roomId" is not a Xiaohongshu room');
    try {
      return await http.send(
        LiveRequest(
          site: _site,
          url: XiaohongshuApi.roomUrl(roomId),
          headers: XiaohongshuApi.headers,
          followRedirects: false,
        ),
      );
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<XiaohongshuPage> _read(String roomId) async {
    final id = roomId.trim();
    final response = await _page(id);
    return XiaohongshuApi.room(response.text, requestedId: id, status: response.status);
  }

  // Directory -----------------------------------------------------------------

  /// Dynamic platform categories. The old link-only adapter remains usable
  /// in isolates and shells without a browser backend.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page != 1 || guest == null) return const [];
    return XiaohongshuDirectory.categories(await guest!.categories());
  }

  String _category(LiveArea? area) {
    if (area == null) return '0';
    if (area.platform != _site || !RegExp(r'^\d{1,8}$').hasMatch(area.areaId)) {
      throw ArgumentError.value(area, 'category', 'Expected a Xiaohongshu category');
    }
    return area.areaId;
  }

  /// One request by caller-owned cursor, so refreshing or switching tabs
  /// cannot reuse another listing's cursor.
  @override
  Future<LiveDirectoryPage> getDirectoryPageAtCursor({
    required int page,
    String? cursor,
    LiveArea? category,
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if ((page == 1) != (cursor == null)) throw ArgumentError.value(cursor, 'cursor', 'Cursor does not match page');
    final session = guest;
    if (session == null) {
      if (category != null) throw ArgumentError.value(category, 'category', 'Directory is unavailable in this shell');
      return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    }
    final score = cursor ?? '0';
    if (score.isEmpty || score.length > 128) throw ArgumentError.value(cursor, 'cursor');
    final body = await session.directory(category: _category(category), cursor: score, cancel: cancel);
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
    return XiaohongshuDirectory.page(body, page: page, cursor: score);
  }

  /// Compatibility paging (1–20), replaying cursors locally with a bounded
  /// deadline. The application's directory uses the single-request method.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if (guest == null) {
      if (category != null) throw ArgumentError.value(category, 'category', 'Directory is unavailable in this shell');
      return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    }
    if (page > 20) throw RangeError.range(page, 1, 20, 'page');
    final owned = CancelToken();
    if (cancel != null) unawaited(cancel.whenCancelled.then((_) => owned.cancel()));
    Future<LiveDirectoryPage> replay() async {
      String? cursor;
      final shown = <String>{};
      for (var current = 1; ; current++) {
        final result = await getDirectoryPageAtCursor(page: current, cursor: cursor, category: category, cancel: owned);
        if (current == page) {
          return LiveDirectoryPage(
            rooms: result.rooms.where((room) => !shown.contains(room.roomId)),
            page: page,
            hasMore: result.hasMore,
            nextCursor: result.nextCursor,
          );
        }
        if (!result.hasMore) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
        shown.addAll(result.rooms.map((room) => room.roomId));
        cursor = result.nextCursor;
      }
    }

    try {
      return await replay().timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw const NetworkFailure(_site, 'Directory timed out');
    } finally {
      owned.cancel();
    }
  }

  /// Public recommendations, or the explicit link-only fallback.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      (await getDirectoryPage(page: page)).rooms;

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async =>
      guest == null ? const [] : (await getDirectoryPage(page: page, category: category)).rooms;

  // Search --------------------------------------------------------------------

  /// The one room [keyword] names (3.x's exact lookup): a room id, a share
  /// page, an app deep link, or a short link followed hop by hop within
  /// `xhslink.com` (at most 12 seconds). Other keywords, and pages after
  /// the first, give nothing without a request. The room is the follow
  /// refresh's (no stream data). A room that does not exist (HTTP 404, or
  /// the page's "未找到直播间", 16-1; 3.x showed an error for the latter)
  /// gives nothing; every other failure is thrown, as in 3.x.
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    if (page != 1) return const [];
    final text = keyword.trim();
    final roomId = XiaohongshuApi.roomIdFrom(text) ?? await _shortLinkRoom(text);
    if (roomId == null) return const [];
    final response = await _page(roomId);
    try {
      return [XiaohongshuApi.room(response.text, requestedId: roomId, status: response.status).room];
    } on NotFound {
      return const [];
    }
  }

  /// The room a short link [text] leads to, in a session of its own.
  Future<String?> _shortLinkRoom(String text) async {
    final start = XiaohongshuApi.shortLink(text);
    if (start == null) return null;
    final session = ShortLinkSession(http, timeout: _shortLinkTimeout, site: _site);
    try {
      return await _follow(start, session).timeout(_shortLinkTimeout, onTimeout: () => null);
    } finally {
      session.close();
    }
  }

  /// Follows [start] one redirect at a time without fetching any target:
  /// a room link ends it, another short link is the next hop, anything
  /// else (the home page, a note, a profile, another site) is no room.
  Future<String?> _follow(Uri start, ShortLinkSession session) async {
    Uri? current = start;
    while (current != null && !session.isClosed) {
      final response = await session.get(current, headers: XiaohongshuApi.headers);
      if (session.isClosed || response == null) return null;
      final target = XiaohongshuApi.shortLinkHop(
        current,
        status: response.status,
        locations: response.headers['location'],
      );
      if (target == null) return null;
      final roomId = XiaohongshuApi.roomIdFrom(target.toString());
      if (roomId != null) return roomId;
      current = XiaohongshuApi.shortLink(target.toString());
    }
    return null;
  }

  // Rooms ---------------------------------------------------------------------

  /// The room with the page's data (the stream is read from it).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    final page = await _read(roomId);
    return page.room.copyWith(
      data: page.data,
      danmakuData: guest == null ? null : XiaohongshuDanmakuArgs(roomId: page.room.roomId),
    );
  }

  /// Follow-card refresh: the same one request, without stream data (3.x).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) async => (await _read(roomId)).room;

  /// Room entry's answer, checked as 3.x did: a room that is not ended must
  /// be playable (see [XiaohongshuApi.playable]); an ended room is returned
  /// as it is.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) async {
    final page = await _read(roomId);
    if (!page.room.isExplicitlyOfflineNow) XiaohongshuApi.playable(page.data);
    return page.room.copyWith(data: page.data);
  }

  /// Whether the room is live; a state the page does not name is
  /// `ApiChanged` (3.x's "schema").
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = (await _read(roomId)).room;
    if (room.isLiveStatusPending) throw ApiChanged(_site, 'share page $roomId: state not known');
    return room.isLiveNow;
  }

  // Streams -------------------------------------------------------------------

  /// The qualities of the stream [detail] carries (a room without it, like
  /// a search card, is read first): one per `quality_type` (16-3). A room
  /// known to be offline has none (`StreamUnavailable`, without a request;
  /// 3.x listed nothing).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      XiaohongshuApi.qualities(XiaohongshuApi.playable(await _data(detail, fresh: false)));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] in the stream [detail] carries; a 3.x quality
  /// id (`h264:HD`) plays its quality now ([XiaohongshuApi.qualityIdFromLegacy]).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => XiaohongshuApi.resolution(XiaohongshuApi.playable(await _data(detail, fresh: false)), quality);

  /// Recovery reads the page again, as 3.x did; the quality must still be
  /// there (no silent switch).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => XiaohongshuApi.resolution(XiaohongshuApi.playable(await _data(detail, fresh: true)), quality);

  /// The data [detail] carries for its own room or, when it has none (or
  /// [fresh]), the page's now. A room known to be offline is
  /// `StreamUnavailable` without a request.
  Future<XiaohongshuRoomData> _data(LiveRoom detail, {required bool fresh}) async {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a Xiaohongshu room');
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, 'room ${detail.roomId} has ended');
    if (!fresh) {
      if (detail.data case final XiaohongshuRoomData data when data.roomId == detail.roomId) return data;
    }
    return (await _read(detail.roomId)).data;
  }

  // Links ---------------------------------------------------------------------

  /// A share page (see [XiaohongshuApi.webRoomId]).
  @override
  String? roomIdFromUrl(String url) => XiaohongshuApi.webRoomId(url);

  /// `xhslink.com` short links.
  @override
  bool needsResolving(String url) => XiaohongshuApi.shortLink(url) != null;

  /// Follows the short link within `xhslink.com` (3.x); only a room of this
  /// platform ends it, so a hop elsewhere is not handed to other platforms.
  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    final start = XiaohongshuApi.shortLink(url);
    if (start == null) return null;
    final roomId = await _follow(start, session);
    return roomId == null ? null : LinkRoom(roomId);
  }

  /// Rooms of `xhsdiscover://live_audience` deep links in a share text.
  @override
  Iterable<String> roomIdsInShareText(String text) => XiaohongshuApi.shareTextRoomIds(text);
}
