import 'dart:async';
import 'dart:developer';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pure_live/features/account/account_platforms.dart';
import 'package:pure_live/features/account/bilibili_web_login.dart' show cookieHeader;
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/in_app_web.dart';

/// A platform's own sign-in page in the app (K01.3): where it is, whose
/// cookies make up the login, and which of them say someone signed in.
@immutable
final class PlatformWebLogin {
  /// Creates the description.
  const new({
    required this.page,
    required this.domains,
    required this.signals,
    this.desktop = false,
    this.tapSignIn = false,
  });

  /// The sign-in page (or the site, whose own button opens the sign-in).
  final Uri page;

  /// The addresses whose cookies are read.
  final List<Uri> domains;

  /// Cookie names any of which means someone has signed in; empty: only
  /// "已登录，保存" takes the cookies.
  final Set<String> signals;

  /// The desktop site, laid out at its width and zoomable: the platform has
  /// no sign-in on its phone pages.
  final bool desktop;

  /// The sign-in opens from a "登录" at the top right of the page, which
  /// the user taps (the page says so).
  final bool tapSignIn;

  /// Whether [cookies] (names) show a sign-in.
  bool signedIn(Iterable<String> cookies) => cookies.any(signals.contains);
}

/// The platforms with an official sign-in in the app, by id (Bilibili has
/// its own pages: the QR code and `BilibiliWebLoginView`). Each page was
/// opened in the app's WebView on the K90 (2026-10-16): a phone sign-in
/// where the platform has one (Douyu's, YY's security centre, Twitch's,
/// SOOP's: password or SMS, which a phone can use itself), else the
/// desktop site, whose sign-in offers the platform app's QR code (for a
/// tablet or a second phone) and SMS or password. Huya's and Kuaishou's
/// phone pages only send to their apps; www.yy.com refuses the WebView.
final Map<String, PlatformWebLogin> platformWebLogins = {
  SiteIds.douyu: PlatformWebLogin(
    page: Uri.https('passport.douyu.com', '/h5/loginActivity'),
    domains: [Uri.https('passport.douyu.com'), Uri.https('www.douyu.com'), Uri.https('m.douyu.com')],
    signals: const {'acf_auth', 'dy_auth'},
  ),
  SiteIds.huya: PlatformWebLogin(
    page: Uri.https('www.huya.com', '/'),
    domains: [Uri.https('www.huya.com'), Uri.https('udblgn.huya.com')],
    signals: const {'udb_biztoken', 'yyuid'},
    desktop: true,
    tapSignIn: true,
  ),
  SiteIds.douyin: PlatformWebLogin(
    page: Uri.https('live.douyin.com', '/'),
    domains: [Uri.https('live.douyin.com'), Uri.https('www.douyin.com')],
    signals: const {'sessionid', 'sessionid_ss'},
    desktop: true,
    tapSignIn: true,
  ),
  SiteIds.kuaishou: PlatformWebLogin(
    page: Uri.https('passport.kuaishou.com', '/pc/account/login/', {
      'sid': 'kuaishou.live.web',
      'callback': 'https://live.kuaishou.com/',
    }),
    domains: [Uri.https('live.kuaishou.com'), Uri.https('passport.kuaishou.com'), Uri.https('id.kuaishou.com')],
    signals: const {'kuaishou.live.web_st', 'userId'},
    desktop: true,
  ),
  SiteIds.yy: PlatformWebLogin(
    page: Uri.https('aq.yy.com', '/'),
    domains: [Uri.https('aq.yy.com'), Uri.https('www.yy.com')],
    signals: const {'udb_biztoken', 'yyuid'},
  ),
  SiteIds.cc: PlatformWebLogin(
    page: Uri.https('cc.163.com', '/'),
    domains: [Uri.https('cc.163.com'), Uri.https('www.163.com')],
    signals: const {},
    desktop: true,
    tapSignIn: true,
  ),
  SiteIds.twitch: PlatformWebLogin(
    page: Uri.https('www.twitch.tv', '/login'),
    domains: [Uri.https('www.twitch.tv')],
    signals: const {'auth-token'},
  ),
  SiteIds.soop: PlatformWebLogin(
    page: Uri.https('login.sooplive.co.kr', '/afreeca/login.php'),
    domains: [Uri.https('login.sooplive.co.kr'), Uri.https('www.sooplive.co.kr')],
    signals: const {'AuthTicket'},
  ),
};

/// Lays a desktop site out 1280 wide and fits it to the screen, still
/// zoomable: the sites ask for the device's width even with a desktop
/// browser's name, so the "登录" in their header was off the screen. The
/// sign-in is the user's tap: the sites ignored a script's click (Douyin,
/// Huya, CC on the K90), a finger's opened it.
const String desktopFitScript = '''
(function () {
  var width = 1280;
  var scale = Math.max(0.2, Math.min(1, screen.width / width));
  var meta = document.querySelector('meta[name="viewport"]');
  if (!meta) {
    meta = document.createElement('meta');
    meta.name = 'viewport';
    (document.head || document.documentElement).appendChild(meta);
  }
  meta.setAttribute('content', 'width=' + width + ', initial-scale=' + scale + ', minimum-scale=0.1, maximum-scale=5, user-scalable=yes');
})();
''';

/// Whether [platform] can sign in on its own page here: it has one and the
/// device has an in-app browser.
bool hasPlatformWebLogin(String platform) => InAppWeb.available && platformWebLogins.containsKey(platform);

/// Opens a platform's sign-in page; the cookies of the login, or null when
/// the user left without one. Tests replace it (there is no WebView).
Future<String?> Function(BuildContext context, AccountPlatform platform) openPlatformWebLogin = _openWebLogin;

Future<String?> _openWebLogin(BuildContext context, AccountPlatform platform) => Navigator.of(context).push<String>(
  MaterialPageRoute(
    builder: (_) => PlatformWebLoginView(platform: platform, login: platformWebLogins[platform.id]!),
  ),
);

/// Reads the cookies of [domains] from the in-app browser.
Future<List<({String name, String value})>> readWebCookies(List<Uri> domains) async {
  final found = <({String name, String value})>[];
  for (final url in domains) {
    try {
      for (final cookie in await CookieManager.instance().getCookies(url: WebUri.uri(url))) {
        found.add((name: cookie.name, value: '${cookie.value}'));
      }
    } on Object {
      // Read what the other addresses have.
    }
  }
  return found;
}

/// The site [host] belongs to, whose cookies its pages share:
/// `passport.douyu.com` → `douyu.com`, `login.sooplive.co.kr` →
/// `sooplive.co.kr`.
String siteDomain(String host) {
  final labels = host.toLowerCase().split('.');
  final keep = labels.length > 2 && labels[labels.length - 2].length <= 3 && labels.last.length == 2 ? 3 : 2;
  return labels.length <= keep ? labels.join('.') : labels.sublist(labels.length - keep).join('.');
}

/// Removes the cookies of [domains] from the in-app browser, so an account
/// signed out of the app is not picked up again; failures are logged.
Future<void> clearWebCookies(List<Uri> domains) async {
  for (final url in domains) {
    try {
      final cookies = CookieManager.instance();
      await cookies.deleteCookies(url: WebUri.uri(url), domain: '.${siteDomain(url.host)}');
      await cookies.deleteCookies(url: WebUri.uri(url));
    } on Object catch (error) {
      log('Clearing the web cookies of ${url.host} failed: $error', name: 'AccountPage');
    }
  }
}

/// A platform's official sign-in in the app (K01.3, like Bilibili's web
/// login): the platform's page, where the user signs in with its app's QR
/// code, SMS or password; the moment a sign-in cookie appears (checked on
/// every page and every 1.5 s, as sites sign in inside a dialog) the
/// cookies go back to the cookie page, which checks and stores them as a
/// pasted cookie. "已登录，保存" takes them by hand.
class PlatformWebLoginView extends StatefulWidget {
  /// Creates the page.
  const new({required this.platform, required this.login, super.key});

  /// The platform.
  final AccountPlatform platform;

  /// Its sign-in page.
  final PlatformWebLogin login;

  @override
  State<PlatformWebLoginView> createState() => _PlatformWebLoginViewState();
}

class _PlatformWebLoginViewState extends State<PlatformWebLoginView> {
  InAppWebViewController? _web;
  late final Future<void> _cleared = clearWebCookies(widget.login.domains);
  Timer? _poll;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => unawaited(_look(manual: false)));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// The desktop sites: fitted to the screen.
  Future<void> _fit() async {
    if (!widget.login.desktop) return;
    try {
      await _web?.evaluateJavascript(source: desktopFitScript);
    } on Object catch (error) {
      log('Fitting the sign-in page failed: $error', name: 'AccountPage');
    }
  }

  Future<void> _look({required bool manual}) async {
    if (_done) return;
    final cookies = await readWebCookies(widget.login.domains);
    if (_done || !mounted) return;
    final names = cookies.map((cookie) => cookie.name);
    if (!manual && !widget.login.signedIn(names)) return;
    if (cookies.isEmpty) {
      AppNavigator.toast(i18n('account_web_login_none', args: {'name': widget.platform.name}));
      return;
    }
    _done = true;
    _poll?.cancel();
    // `pop`, not `maybePop`: the page's PopScope turns that into a step back.
    Navigator.of(context).pop(cookieHeader(cookies));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(i18n('account_web_login_title', args: {'name': widget.platform.name})),
      actions: [
        TextButton(
          key: const ValueKey('account-web-login-done'),
          onPressed: () => unawaited(_look(manual: true)),
          child: Text(i18n('account_web_login_done')),
        ),
      ],
    ),
    body: Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                const Icon(AppIcons.info, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    i18n(
                      widget.login.tapSignIn ? 'account_web_login_tip_desktop' : 'account_web_login_tip',
                      args: {'name': widget.platform.name},
                    ),
                    style: context.textStyles.t13,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<void>(
            future: _cleared,
            builder: (context, snapshot) => snapshot.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : InAppWebPage(
                    initial: widget.login.page,
                    desktopSite: widget.login.desktop,
                    onCreated: (controller) => _web = controller,
                    onPage: (_) {
                      unawaited(_look(manual: false));
                      unawaited(_fit());
                    },
                  ),
          ),
        ),
      ],
    ),
  );
}
