import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live/platform/twitch_webview_http.dart';
import 'package:pure_live/platform/xiaohongshu_guest.dart';

final class _Browser implements XiaohongshuGuestBrowser {
  final calls = <({Uri page, String script, String? proxyRule, CancelToken? cancel})>[];
  Object? answer = '{}';
  @override
  Future<Object?> run({required Uri page, required String script, String? proxyRule, CancelToken? cancel}) async {
    calls.add((page: page, script: script, proxyRule: proxyRule, cancel: cancel));
    if (answer case final Completer<Object?> pending) return await pending.future;
    if (answer case final Exception error) throw error;
    return answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('only read-only public directory paths enter the browser', () async {
    final browser = _Browser();
    final guest = WebViewXiaohongshuGuest(proxy: const FixedProxyPolicy(), browser: browser);
    await guest.categories();
    await guest.directory(category: '6', cursor: '9.75');
    expect(browser.calls.every((c) => c.page.toString() == 'https://www.xiaohongshu.com/livelist'), isTrue);
    expect(browser.calls[0].script, contains('/api/sns/red/live/web/feed/category'));
    expect(browser.calls[1].script, contains('cursor_score=9.75&source=13&category=6'));
    expect(browser.calls[1].script, isNot(contains('synthetic-credential')));
    expect(
      () => WebViewXiaohongshuGuest.requestScript('https://example.invalid/api/sns/red/live/web/feed/category'),
      throwsArgumentError,
    );
    expect(() => WebViewXiaohongshuGuest.requestScript('/api/sns/web/v1/comment/post'), throwsArgumentError);
    expect(() => guest.directory(category: '../bad', cursor: '0'), throwsArgumentError);
  });

  test('cancel before creation avoids a browser; cancelled result is suppressed', () async {
    final browser = _Browser();
    final guest = WebViewXiaohongshuGuest(proxy: const FixedProxyPolicy(), browser: browser);
    final cancel = CancelToken()..cancel();
    await expectLater(
      guest.categories(cancel: cancel),
      throwsA(isA<TransportFailure>().having((e) => e.reason, 'reason', TransportReason.cancelled)),
    );
    expect(browser.calls, isEmpty);
    final pending = Completer<Object?>();
    browser.answer = pending;
    final current = CancelToken();
    final response = guest.categories(cancel: current);
    current.cancel();
    pending.complete('{}');
    await expectLater(
      response,
      throwsA(isA<TransportFailure>().having((e) => e.reason, 'reason', TransportReason.cancelled)),
    );
    expect(browser.calls.single.cancel, same(current));
  });

  test('IPv6 proxy authority keeps its brackets for the temporary browser', () async {
    final browser = _Browser();
    final guest = WebViewXiaohongshuGuest(
      proxy: const FixedProxyPolicy(global: HttpProxyRoute('::1', 7897)),
      browser: browser,
    );
    await guest.categories();
    expect(browser.calls.single.proxyRule, '[::1]:7897');
  });

  test('identity is memory-only, reused briefly, renewed on refusal and expiry', () async {
    var now = DateTime.utc(2026, 11, 4);
    final browser = _Browser()
      ..answer = {
        'sid': 'synthetic-sid',
        'uid': 'synthetic-guest',
        'deviceId': 'synthetic-device',
        'fingerprint': 'synthetic-fingerprint',
        'userAgent': 'Synthetic browser',
      };
    final guest = WebViewXiaohongshuGuest(proxy: const FixedProxyPolicy(), browser: browser, now: () => now);
    final first = await guest.pushIdentity('570000000000000017');
    expect(first.sid, 'synthetic-sid');
    expect(await guest.pushIdentity('570000000000000018'), same(first));
    expect(browser.calls.length, 1);
    await guest.pushIdentity('570000000000000018', refresh: true);
    expect(browser.calls.length, 2);
    now = now.add(const Duration(minutes: 6));
    await guest.pushIdentity('570000000000000018');
    expect(browser.calls.length, 3);
    expect(first.toString(), isNot(contains('synthetic-sid')));
    expect(browser.calls.first.page.path, '/livestream/570000000000000017');
  });

  test('missing identity and oversized results fail without exposing raw credentials', () async {
    final browser = _Browser()..answer = {'sid': 'synthetic-private-sid'};
    final guest = WebViewXiaohongshuGuest(proxy: const FixedProxyPolicy(), browser: browser);
    await expectLater(
      guest.pushIdentity('570000000000000017'),
      throwsA(predicate<Object>((e) => !e.toString().contains('synthetic-private-sid'))),
    );
    browser.answer = Exception('synthetic-private-sid');
    await expectLater(
      guest.categories(),
      throwsA(
        isA<TransportFailure>().having((e) => e.toString(), 'diagnostic', isNot(contains('synthetic-private-sid'))),
      ),
    );
    browser.answer = 'x' * (2 * 1024 * 1024 + 1);
    await expectLater(guest.categories(), throwsA(isNotNull));
  });

  test('XHS and Twitch share an exclusive temporary page scope', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final order = <String>[];
    final first = InAppHeadlessBrowser.exclusive(
      body: () async {
        order.add('first-start');
        entered.complete();
        await release.future;
        order.add('first-end');
      },
    );
    await entered.future;
    final second = InAppHeadlessBrowser.exclusive(
      body: () async {
        order.add('second');
      },
    );
    await Future<void>.value();
    expect(order, ['first-start']);
    release.complete();
    await Future.wait([first, second]);
    expect(order, ['first-start', 'first-end', 'second']);
  });

  test('native visitor result is followed by cleanup, including a refused result', () async {
    const channel = MethodChannel('pure_live/xiaohongshu_guest');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    var ok = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'run') {
        return jsonEncode({
          'ok': ok,
          'value': {'sid': 'synthetic-native-sid'},
        });
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final browser = InAppXiaohongshuGuestBrowser();
    final result = await browser.androidRequest(Uri.parse('https://www.xiaohongshu.com/livelist'), 'return 1;', null);
    expect(result, {'sid': 'synthetic-native-sid'});
    expect(calls, ['run', 'cancel']);
    ok = false;
    await expectLater(
      browser.androidRequest(Uri.parse('https://www.xiaohongshu.com/livelist'), 'return 1;', null),
      throwsStateError,
    );
    expect(calls, ['run', 'cancel', 'run', 'cancel']);
  });

  test('cancelling a native visitor job closes its exact request and suppresses a late result', () async {
    const channel = MethodChannel('pure_live/xiaohongshu_guest');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final pending = Completer<String?>();
    final entered = Completer<void>();
    String? id;
    var cancelled = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      if (call.method == 'run') {
        id = args['id'] as String;
        entered.complete();
        return await pending.future;
      }
      expect(args['id'], id);
      cancelled = true;
      pending.complete('{"ok":true,"value":"late"}');
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final cancel = CancelToken();
    final future = InAppXiaohongshuGuestBrowser().androidRequest(
      Uri.parse('https://www.xiaohongshu.com/livelist'),
      'return 1;',
      cancel,
    );
    await entered.future;
    final expectation = expectLater(
      future,
      throwsA(isA<TransportFailure>().having((e) => e.reason, 'reason', TransportReason.cancelled)),
    );
    cancel.cancel();
    await expectation;
    expect(cancelled, isTrue);
  });
}
