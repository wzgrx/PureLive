import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/platform/xiaohongshu_guest.dart';

/// Isolated emulator acceptance. The only default-profile value is synthetic;
/// no account, cookie export, interaction or platform message is requested.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('游客初始化验证')),
    ),
  );
  final root = Directory('${(await getTemporaryDirectory()).path}/purelive-xhs-572');
  await root.create(recursive: true);
  final cookie = CookieManager.instance();
  final marker = WebUri('https://privacy.example.test/');
  const name = 'purelive_generated_marker';
  await cookie.setCookie(url: marker, name: name, value: 'synthetic');
  final proof = <String, Object?>{
    'source_commit': const String.fromEnvironment('PURELIVE_SOURCE_COMMIT'),
    'generated_default_cookie_only': true,
  };
  try {
    const proxyRule = String.fromEnvironment('PURELIVE_VISITOR_PROXY');
    final proxyUri = Uri.tryParse(proxyRule);
    final route = proxyRule.isEmpty ? const DirectRoute() : HttpProxyRoute(proxyUri!.host, proxyUri.port);
    final browser = InAppXiaohongshuGuestBrowser();
    final flags = await browser.run(
      page: Uri.parse('https://www.xiaohongshu.com/livelist'),
      script: '''
for (let i=0;i<50 && document.readyState!=='complete';i++) await new Promise(resolve=>setTimeout(resolve,100));
const state = document.visibilityState;
const raf = await Promise.race([
  new Promise(resolve=>requestAnimationFrame(()=>resolve(true))),
  new Promise(resolve=>setTimeout(()=>resolve(false),2000))
]);
return {visibility:state, animationFrame:raf, ready:document.readyState};''',
      proxyRule: proxyRule.isEmpty ? null : proxyUri!.authority,
    );
    proof['document_flags'] = flags;
    if (flags is! Map || flags['visibility'] != 'visible') {
      throw StateError('Visitor page is backgrounded');
    }
    final guest = WebViewXiaohongshuGuest(
      proxy: FixedProxyPolicy(global: route),
      browser: browser,
    );
    final categories = XiaohongshuDirectory.categories(await guest.categories());
    proof['categories'] = categories.length;
    final preserved = (await cookie.getCookie(url: marker, name: name))?.value == 'synthetic';
    proof['default_profile_marker_preserved'] = preserved;
    proof['passed'] = categories.isNotEmpty && preserved;
  } on Object catch (error) {
    proof['passed'] = false;
    proof['error_type'] = error.runtimeType.toString();
    if (error case ApiChanged(code: final code?)) proof['capability_code'] = code.name;
    if (error case TransportFailure(:final reason)) proof['transport_reason'] = reason.name;
  }
  proof['default_profile_marker_preserved'] = (await cookie.getCookie(url: marker, name: name))?.value == 'synthetic';
  await File('${root.path}/result.json').writeAsString(jsonEncode(proof), flush: true);
}
