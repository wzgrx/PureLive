import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_vod/live_vod.dart';

/// One controller-owned entry using the existing bounded loopback HLS relay.
/// Every segment retains the site's headers, TLS and proxy policy.
final class HuyaManifestEntry {
  /// Replaces only the root manifest; downstream requests keep their transport.
  new({this.proxy = const FixedProxyPolicy(), this.upstreamFor});

  /// App-owned routing rules, including user-configured Huya proxies.
  final ProxyPolicy proxy;

  /// Deterministic segment transport for tests.
  final HlsUpstream Function(String site)? upstreamFor;
  Future<LoopbackRelay>? _relay;
  final List<RelayInput> _inputs = [];
  Uri? _source;
  List<int> _body = const [];
  bool _closed = false;

  /// At most two routes are retained while a native input is being replaced.
  Future<String> publish(HuyaArchiveAnchor anchor, String source) async {
    if (_closed) throw StateError('Archive entry closed');
    final body = utf8.encode(anchor.playlist);
    if (body.length > 16777216) throw const FormatException('Archive entry bounds');
    _source = Uri.parse(source);
    _body = body;
    final relay = await (_relay ??= LoopbackRelay.start(
      proxy: proxy,
      hlsUpstream: (site) =>
          _EntryUpstream(_source!, _body, upstreamFor?.call(site) ?? IoHlsUpstream(site: site, proxy: proxy)),
    ));
    if (_closed) throw StateError('Archive entry closed');
    while (_inputs.length >= 2) {
      await _inputs.removeAt(0).close();
    }
    final input = relay.openHls(
      LivePlayLine(source, format: StreamFormat.hls, headers: HuyaArchiveApi.mediaHeaders),
      site: SiteIds.huya,
      maxEntries: 50001,
      maxPlaylistBytes: 16 << 20,
    );
    _inputs.add(input);
    return input.uri.toString();
  }

  /// The replacement open settled, so its predecessor can release all requests.
  Future<void> retirePrevious({bool keepCurrent = true}) async {
    while (_inputs.length > (keepCurrent ? 1 : 0)) {
      await _inputs.removeAt(0).close();
    }
  }

  /// Releases even when the live-room runtime owns the shared decoder.
  Future<void> close() async {
    _closed = true;
    _body = const [];
    _source = null;
    for (final input in _inputs) {
      await input.close();
    }
    _inputs.clear();
    final relay = _relay;
    if (relay != null) await (await relay).close();
  }
}

final class _EntryUpstream implements HlsUpstream {
  new(this.source, this.body, this.delegate);
  final Uri source;
  final List<int> body;
  final HlsUpstream delegate;
  @override
  Future<HlsUpstreamResponse> get(Uri url, Map<String, String> headers) async => url == source
      ? HlsUpstreamResponse(status: 200, url: source, body: Stream.value(body), contentLength: body.length)
      : await delegate.get(url, headers);
  @override
  void close() => delegate.close();
}
