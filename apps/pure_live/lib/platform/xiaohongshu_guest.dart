import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';

import 'package:pure_live/platform/twitch_webview_http.dart';

/// The finite browser operation, isolated from platform plugins for testing.
abstract interface class XiaohongshuGuestBrowser {
  /// Loads the public [page], observes only read-only visitor traffic and
  /// runs [script]. Cancellation, failure and success all dispose the page.
  Future<Object?> run({required Uri page, required String script, String? proxyRule, CancelToken? cancel});
}

/// Anonymous directory and RWP bootstrap. Browsers exist only during a
/// request; playback and subsequent chat use the normal native transports.
final class WebViewXiaohongshuGuest implements XiaohongshuGuest {
  /// Creates the visitor client. It never reads CookieVault or account data.
  new({required this.proxy, XiaohongshuGuestBrowser? browser, DateTime Function()? now})
    : browser = browser ?? InAppXiaohongshuGuestBrowser(),
      _now = now ?? DateTime.now;

  /// Platforms with the existing WebView plugin backend.
  static bool get isAvailable => Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows;

  /// Same per-platform route used by HTTP and the independent socket.
  final ProxyPolicy proxy;

  /// Temporary page implementation.
  final XiaohongshuGuestBrowser browser;
  final DateTime Function() _now;
  XiaohongshuPushIdentity? _identity;
  DateTime? _identityAt;

  Future<Object?> _run(Uri page, String script, CancelToken? cancel) async {
    if (cancel?.isCancelled ?? false) throw const TransportFailure('xiaohongshu', TransportReason.cancelled);
    final route = proxy.routeFor('xiaohongshu', page);
    try {
      final value = await browser.run(
        page: page,
        script: script,
        proxyRule: route is HttpProxyRoute ? Uri(scheme: 'http', host: route.host, port: route.port).authority : null,
        cancel: cancel,
      );
      if (cancel?.isCancelled ?? false) throw const TransportFailure('xiaohongshu', TransportReason.cancelled);
      return value;
    } on TransportFailure {
      rethrow;
    } on TimeoutException {
      throw const TransportFailure('xiaohongshu', TransportReason.timeout, 'Visitor initialization timed out');
    } on Object {
      // Plugin and JS errors can include credentials. Keep diagnostics fixed.
      throw const TransportFailure('xiaohongshu', TransportReason.connect, 'Visitor initialization failed');
    }
  }

  Future<String> _request(String path, CancelToken? cancel) async {
    final value = await _run(Uri.parse('https://www.xiaohongshu.com/livelist'), requestScript(path), cancel);
    if (value is! String || value.length > 2 * 1024 * 1024) {
      throw const ApiChanged('xiaohongshu', 'Invalid visitor response');
    }
    return value;
  }

  @override
  Future<String> categories({CancelToken? cancel}) => _request('/api/sns/red/live/web/feed/category', cancel);

  @override
  Future<String> directory({required String category, required String cursor, CancelToken? cancel}) {
    if (!RegExp(r'^\d{1,8}$').hasMatch(category) || cursor.isEmpty || cursor.length > 128) {
      throw ArgumentError('Invalid directory request');
    }
    final query =
        'cursor_score=${Uri.encodeComponent(cursor)}&source=13&category=${Uri.encodeComponent(category)}&pre_source=&extra_info=%7B%22image_formats%22:[%22jpg%22,%22webp%22,%22avif%22]%7D&size=27';
    return _request('/api/sns/red/live/web/feed/v1/squarefeed?$query', cancel);
  }

  @override
  Future<XiaohongshuPushIdentity> pushIdentity(String roomId, {bool refresh = false, CancelToken? cancel}) async {
    if (!XiaohongshuApi.isRoomId(roomId)) throw ArgumentError.value(roomId, 'roomId');
    if (cancel?.isCancelled ?? false) throw const TransportFailure('xiaohongshu', TransportReason.cancelled);
    if (refresh) {
      _identity = null;
      _identityAt = null;
    }
    final kept = _identity;
    if (kept != null && _identityAt != null) {
      final age = _now().difference(_identityAt!);
      if (!age.isNegative && age < const Duration(minutes: 5)) return kept;
    }
    final value = await _run(XiaohongshuApi.roomUrl(roomId), identityScript, cancel);
    if (value is! Map) throw const ApiChanged('xiaohongshu', 'Missing visitor identity');
    String field(String key) {
      final item = value[key];
      if (item is! String || item.isEmpty || item.length > 4096) {
        throw const ApiChanged('xiaohongshu', 'Incomplete visitor identity');
      }
      return item;
    }

    final identity = XiaohongshuPushIdentity(
      sid: field('sid'),
      uid: field('uid'),
      deviceId: field('deviceId'),
      fingerprint: field('fingerprint'),
      userAgent: field('userAgent'),
    );
    _identityAt = _now();
    return _identity = identity;
  }

  /// Uses the currently served website signer; no copied or hard-coded
  /// signature algorithm. Only the two public directory endpoints qualify.
  @visibleForTesting
  static String requestScript(String path) {
    final uri = Uri.parse(path);
    if (uri.hasScheme ||
        uri.hasAuthority ||
        !const ['/api/sns/red/live/web/feed/category', '/api/sns/red/live/web/feed/v1/squarefeed'].contains(uri.path)) {
      throw ArgumentError.value(path, 'path');
    }
    return '''
const path = ${jsonEncode(path)};
for (let n=0; n<250; n++) {
  const s = window.__pureLiveXhs;
  if (s && s.headers && typeof window._webmsxyw === 'function') {
    const headers = Object.assign({}, s.headers, window._webmsxyw(path));
    const r = await fetch('https://live-room.xiaohongshu.com'+path, {headers, credentials:'include'});
    if (r.status !== 200) throw new Error('Visitor directory refused');
    const body = await r.text();
    if (body.length > 2097152) throw new Error('Visitor response too large');
    return body;
  }
  await new Promise(resolve=>setTimeout(resolve,100));
}
throw new Error('Visitor directory unavailable');
''';
  }

  /// Only an acknowledged visitor handshake is returned. The page never
  /// sends a test comment, reaction, follow or account request on our behalf.
  @visibleForTesting
  static const String identityScript = '''
for (let n=0; n<250; n++) {
  const s=window.__pureLiveXhs;
  if(s && s.identity) return s.identity;
  if(s && s.refused) throw new Error('Visitor handshake refused');
  await new Promise(resolve=>setTimeout(resolve,100));
}
throw new Error('Visitor chat unavailable');
''';

  /// Observes the site's own feed headers and RWP auth ack, keeping them in
  /// the ephemeral incognito page. No general HTTP or account bridge exists.
  @visibleForTesting
  static const String captureScript = '''
(()=>{
  if(window.__pureLiveXhs)return;
  const state=window.__pureLiveXhs={};
  const wanted=k=>['x-s-common','xy-common-params','accept'].includes(k.toLowerCase());
  const feed=url=>{try{const u=new URL(url,location.href);return u.hostname==='live-room.xiaohongshu.com'&&u.pathname==='/api/sns/red/live/web/feed/v1/squarefeed';}catch{return false;}};
  const save=(url,headers)=>{
    if(!feed(url))return;
    const h={};new Headers(headers).forEach((v,k)=>{if(wanted(k))h[k]=v;});
    if(h['x-s-common'])state.headers=h;
  };
  const X=XMLHttpRequest.prototype,open=X.open,set=X.setRequestHeader,send=X.send;
  X.open=function(method,url,...rest){this.__plUrl=String(url);this.__plHeaders={};return open.call(this,method,url,...rest);};
  X.setRequestHeader=function(k,v){if(wanted(String(k)))this.__plHeaders[k]=String(v);return set.call(this,k,v);};
  X.send=function(...args){save(this.__plUrl,this.__plHeaders);return send.apply(this,args);};
  const fetch=window.fetch;
  window.fetch=function(input,options){save(typeof input==='string'?input:input.url,options?.headers||input?.headers);return fetch.apply(this,arguments);};
  const Socket=window.WebSocket;
  window.WebSocket=class extends Socket {
    constructor(...args){
      super(...args);
      if(String(args[0])!=='wss://apppush-rws.xiaohongshu.com/rwp')return;
      this.__plRwp=true;
      this.addEventListener('message',event=>{
        try{const f=JSON.parse(event.data);if(f.m!==this.__plAuthId)return;
          if(f.b?.a?.c===0)state.identity=this.__plIdentity;else state.refused=true;
        }catch{}
      });
    }
    send(data){
      if(this.__plRwp)try{const f=JSON.parse(data),b=f.b?.d?.b;
        if(f.t===2&&f.b?.d?.s===0&&b?.appId==='xhs-pc'&&b.authInfo?.authType==='generic'){
          this.__plAuthId=f.m;
          this.__plIdentity={sid:b.authInfo.sid,uid:b.authInfo.uid,deviceId:b.deviceInfo?.deviceId,fingerprint:b.deviceInfo?.fingerprint,userAgent:navigator.userAgent};
        }
      }catch{}
      return super.send(data);
    }
  };
})();
''';
}

/// A full-size but short-lived, isolated visitor page. It shares Twitch's
/// exclusive Android proxy scope; it is never kept per multiview cell.
final class InAppXiaohongshuGuestBrowser implements XiaohongshuGuestBrowser {
  /// Creates the browser.
  new();

  static const MethodChannel _channel = MethodChannel('pure_live/xiaohongshu_guest');
  static int _sequence = 0;

  /// Android uses a dedicated WebView profile. The plugin's incognito flag
  /// deletes default-profile cookies, so it must never be used on Android.
  @visibleForTesting
  Future<Object?> androidRequest(Uri page, String script, CancelToken? cancel) async {
    final id = 'xhs-${_sequence++}';
    final run = _channel.invokeMethod<String>('run', {
      'id': id,
      'url': page.toString(),
      'capture': WebViewXiaohongshuGuest.captureScript,
      'script': script,
    });
    try {
      final body = await Future.any([
        run,
        if (cancel != null)
          cancel.whenCancelled.then<String?>(
            (_) => throw const TransportFailure('xiaohongshu', TransportReason.cancelled),
          ),
      ]).timeout(const Duration(seconds: 30));
      if (body == null || body.length > 2 * 1024 * 1024 + 65536) throw StateError('Invalid visitor result');
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['ok'] != true) throw StateError('Visitor request failed');
      return decoded['value'];
    } finally {
      await _channel.invokeMethod<void>('cancel', {'id': id});
    }
  }

  @override
  Future<Object?> run({required Uri page, required String script, String? proxyRule, CancelToken? cancel}) =>
      InAppHeadlessBrowser.exclusive(
        proxyRule: proxyRule,
        body: () async {
          if (cancel?.isCancelled ?? false) throw const TransportFailure('xiaohongshu', TransportReason.cancelled);
          if (proxyRule != null &&
              (!Platform.isAndroid || !await WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE))) {
            throw const TransportFailure(
              'xiaohongshu',
              TransportReason.protocol,
              'Visitor browser cannot use the configured proxy',
            );
          }
          if (Platform.isAndroid) return await androidRequest(page, script, cancel);
          final loaded = Completer<InAppWebViewController>();
          final view = HeadlessInAppWebView(
            initialSize: const Size(1280, 900),
            initialUrlRequest: URLRequest(url: WebUri.uri(page)),
            initialSettings: InAppWebViewSettings(
              incognito: true,
              transparentBackground: true,
              userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
            ),
            initialUserScripts: UnmodifiableListView([
              UserScript(
                source: WebViewXiaohongshuGuest.captureScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            onLoadStop: (controller, url) {
              if (!loaded.isCompleted) loaded.complete(controller);
            },
          );
          Future<Object?> execute() async {
            await view.run();
            final controller = await loaded.future;
            final result = await controller.callAsyncJavaScript(functionBody: script);
            if (result == null || result.error != null) throw StateError('Visitor script failed');
            return result.value;
          }

          try {
            return await Future.any([
              execute(),
              if (cancel != null)
                cancel.whenCancelled.then<Object?>(
                  (_) => throw const TransportFailure('xiaohongshu', TransportReason.cancelled),
                ),
            ]).timeout(const Duration(seconds: 30));
          } finally {
            if (view.isRunning()) await view.dispose();
          }
        },
      );
}
