import 'package:live_core/live_core.dart';
import 'package:live_store/src/settings/setting.dart';

/// Every setting the app stores, with 3.x's keys and defaults
/// (`lib/common/services/settings/*_controller.dart` at v3.2.11) plus the
/// settings added by approved upgrades (docs/specs/UPGRADES.md).
///
/// Accounts (cookies, WebDAV passwords) are not settings: they live in the
/// encrypted `SecretStore`. Follows, history, tags and block lists have their
/// own stores.
abstract final class Settings {
  // ---- app (app_settings_controller.dart:42-69) ----

  /// 3.x stored it but nothing outside the settings page read it.
  static const autoRefreshTime = IntSetting('autoRefreshTime', section: 'app', defaultValue: 3);

  /// Compact cards on the follow page.
  static const enableDenseFavorites = BoolSetting('enableDenseFavorites', section: 'app', defaultValue: true);

  /// Keep playing in the background.
  static const enableBackgroundPlay = BoolSetting('enableBackgroundPlay', section: 'app', defaultValue: false);

  /// Pause desktop playback only while the native window is minimized.
  /// Occlusion and focus changes do not pause; off by default.
  static const desktopPauseWhenMinimized = BoolSetting(
    'desktopPauseWhenMinimized',
    section: 'app',
    defaultValue: false,
  );

  /// Away from the app with background play on, only the sound plays (the
  /// video decoder stops); back, the picture returns (O01.3). New in v4,
  /// off: the video goes on decoding as before.
  static const backgroundAudioOnly = BoolSetting('backgroundAudioOnly', section: 'app', defaultValue: false);

  /// Away from the app the room's danmaku connection closes; back, it
  /// connects again (O01.3). New in v4, off: connected as before.
  static const backgroundPauseDanmaku = BoolSetting('backgroundPauseDanmaku', section: 'app', defaultValue: false);

  /// Closing the system picture-in-picture window pauses a room that would
  /// play on in the background (O01.3). New in v4, off: it plays on as
  /// before.
  static const pauseOnPipClose = BoolSetting('pauseOnPipClose', section: 'app', defaultValue: false);

  /// Sleep timer for audio streams.
  static const enableAsmrSleepMode = BoolSetting('enableAsmrSleepMode', section: 'app', defaultValue: false);

  /// Sleep timer length in minutes (1 minute .. 1 year).
  static const asmrSleepMinutes = IntSetting('asmrSleepMinutes', section: 'app', defaultValue: 60, min: 1, max: 525600);

  /// Follow the device orientation in the player.
  static const enableRotateScreen = BoolSetting('enableRotateScreen', section: 'app', defaultValue: false);

  /// Keep the screen on while playing.
  static const enableScreenKeepOn = BoolSetting('enableScreenKeepOn', section: 'app', defaultValue: true);

  /// Check for updates on start.
  static const enableAutoCheckUpdate = BoolSetting('enableAutoCheckUpdate', section: 'app', defaultValue: true);

  /// Download updates from GitHub instead of the mirror.
  static const useGitHubOriginForUpdates = BoolSetting(
    'useGitHubOriginForUpdates',
    section: 'app',
    defaultValue: false,
  );

  /// New (docs/A-界面设计/A06-首页和全局/A06.3-全局弹窗 c4): the version the user asked not to be
  /// reminded of ("不再提醒这个版本"); the start-up check stays quiet for it
  /// and speaks again for a newer one. Empty: none. A choice of this device,
  /// so backups do not carry it.
  static const skippedUpdateVersion = StringSetting(
    'skippedUpdateVersion',
    section: 'app',
    defaultValue: '',
    scope: SettingScope.internal,
  );

  /// Enter full screen when a room opens.
  static const enableFullScreenDefault = BoolSetting('enableFullScreenDefault', section: 'app', defaultValue: false);

  /// Switch an ended or unrecoverable live room to another online follow.
  static const autoSwitchLiveFollows = BoolSetting('autoSwitchLiveFollows', section: 'app', defaultValue: false);

  /// Opt-in simultaneous audio in multiview; each cell keeps its room volume.
  static const multiviewMixAudio = BoolSetting('multiviewMixAudio', section: 'app', defaultValue: false);

  /// Show the splash page.
  static const showSplashPage = BoolSetting('showSplashPage', section: 'app', defaultValue: true);

  /// Display refresh-rate policy. A 3.x install without it derives it from
  /// the retired `enableHighRefreshRate` switch (see the migration).
  static const refreshRateMode = StringSetting(
    'refreshRateMode',
    section: 'app',
    defaultValue: 'powerSaving',
    allowed: {'powerSaving', 'balanced', 'performance'},
  );

  /// While a stream plays, ask for a display refresh rate that is a whole
  /// multiple of its frame rate (U.2i; new in v4, so no 3.x key).
  static const matchVideoFrameRate = BoolSetting('matchVideoFrameRate', section: 'app', defaultValue: true);

  /// Prefer real online counts over popularity where a platform has both.
  static const preferRealOnlineCounts = BoolSetting('preferRealOnlineCounts', section: 'app', defaultValue: false);

  /// Platforms whose real online count is preferred.
  static const realOnlinePlatforms = StringListSetting(
    'realOnlinePlatforms',
    section: 'app',
    defaultValue: [
      SiteIds.douyin,
      SiteIds.kuaishou,
      SiteIds.cc,
      SiteIds.twitch,
      SiteIds.soop,
      SiteIds.acfun,
      SiteIds.picarto,
      SiteIds.twitcasting,
    ],
  );

  /// Bottom-menu entries, in order.
  static const savedMenuIds = StringListSetting(
    'savedMenuIds',
    section: 'app',
    defaultValue: ['favorites', 'popular', 'areas', 'record'],
  );

  /// Multi-view entry.
  static const enableMultiView = BoolSetting('enableMultiView', section: 'app', defaultValue: true);

  /// "Open in new window" entry (Windows).
  static const enableNewWindowPlay = BoolSetting('enableNewWindowPlay', section: 'app', defaultValue: true);

  /// New (docs/A-界面设计/A18-苹果平台界面/A18.2-macOS差异设计 c7, K2): the Mac's menu bar icon;
  /// off leaves the Dock icon, recording goes on.
  static const showMenuBarIcon = BoolSetting('showMenuBarIcon', section: 'app', defaultValue: true);

  /// New (unified rule "受限……"): discovery pages hide rooms that cannot
  /// be played; on shows them. Follows and search always show them.
  static const showUnplayableInDiscover = BoolSetting('showUnplayableInDiscover', section: 'app', defaultValue: false);

  /// New (F.0a): on start and one second after the app comes back, a share
  /// code on the clipboard is offered as "enter the room" (3.x always
  /// looked and had no switch).
  static const detectClipboardRooms = BoolSetting('detectClipboardRooms', section: 'app', defaultValue: true);

  /// New (UPGRADES 2-1): renew the Douyu cookie every 5 minutes after login.
  static const douyuForceRenew = BoolSetting('douyuForceRenew', section: 'app', defaultValue: false);

  /// New (UPGRADES 8-3): Twitch directory languages; empty = no filter.
  /// [twitchLegacyLanguages] is 3.x's fixed filter, offered as a preset.
  static const twitchLanguages = StringListSetting('twitchLanguages', section: 'app', defaultValue: []);

  /// 3.x's Twitch language filter (Chinese and Korean streams only).
  static const List<String> twitchLegacyLanguages = ['zh', 'ko'];

  // ---- favorite (favorite_room_controller.dart:16-24) ----

  /// Platforms shown on the home tabs, in order.
  static const hotAreasList = StringListSetting('hotAreasList', section: 'favorite', defaultValue: SiteIds.supported);

  /// The platform opened first.
  static const preferPlatform = StringSetting('preferPlatform', section: 'favorite', defaultValue: SiteIds.bilibili);

  // ---- history (history_controller.dart:8-15) ----

  /// History entries kept; 0 keeps everything; a negative count reads 50
  /// (3.x `normalizeHistoryLimit`, history_controller.dart:11-15; J01.3).
  static const historyLimit = IntSetting(
    'historyLimit',
    section: 'history',
    defaultValue: 50,
    min: 0,
    resetOutOfRange: true,
  );

  // ---- theme (theme_settings_controller.dart:17-24) ----

  /// `System`, `Dark` or `Light` (3.x's stored names).
  static const themeMode = StringSetting(
    'themeMode',
    section: 'theme',
    defaultValue: 'System',
    allowed: {'System', 'Dark', 'Light'},
  );

  /// Material You colours.
  static const enableDynamicTheme = BoolSetting('enableDynamicTheme', section: 'theme', defaultValue: false);

  /// Liquid glass (A01.5, A01.6): the home page's bottom bar floats as
  /// liquid glass over the page. On since 5.2 (user 2026-10-16: "增加类似
  /// Liquid Glass"); off: the plain bar as before.
  static const liquidGlass = BoolSetting('liquidGlass', section: 'theme', defaultValue: true);

  /// A tablet's home page keeps the phone's bottom bar instead of the side
  /// rail (V02.6, issue #4: "平板可以有玻璃底栏吗"); Android and iOS only.
  /// Off: the rail from 600 wide, as before.
  static const homeBottomBarOnWide = BoolSetting('homeBottomBarOnWide', section: 'theme', defaultValue: false);

  /// The home page's bottom bar is lower (V02.11, issue #9: "底栏高度太高"):
  /// the plain bar 64 instead of Material's 80, the glass capsule 56
  /// instead of 68. Off: as before.
  static const homeBottomBarCompact = BoolSetting('homeBottomBarCompact', section: 'theme', defaultValue: false);

  /// Android home navigation hides on upward content scrolling when enabled.
  static const homeNavigationAutoHide = BoolSetting('homeNavigationAutoHide', section: 'theme', defaultValue: false);

  /// The phone's navigation destinations keep their visible names by default.
  static const mobileNavigationLabels = BoolSetting('mobileNavigationLabels', section: 'theme', defaultValue: true);

  /// The desktop side rail keeps its visible names by default.
  static const desktopNavigationLabels = BoolSetting('desktopNavigationLabels', section: 'theme', defaultValue: true);

  /// How frosted the liquid glass is, 0 clear to 1 heavy frost (A01.8,
  /// iOS 27's "Liquid Glass" slider); 0.5, the middle, by default.
  static const liquidGlassFrost = DoubleSetting(
    'liquidGlassFrost',
    section: 'theme',
    defaultValue: 0.5,
    min: 0,
    max: 1,
  );

  /// Seed colour, `AARRGGBB` hex. The default is the brand blue (U.6b C-3);
  /// 3.x's default [legacyThemeColor] is moved to it once
  /// ([themeColorMigration], `LegacyRules.themeColor`).
  static const themeColorSwitch = StringSetting('themeColorSwitch', section: 'theme', defaultValue: brandThemeColor);

  /// The brand blue, the default theme colour.
  static const String brandThemeColor = 'FF2E6FE0';

  /// 3.x's default theme colour (`Colors.blue`); 3.x stored it on its first
  /// start, so an untouched 3.x install has it.
  static const String legacyThemeColor = 'FF2196F3';

  /// New (U.6b C-4): black backgrounds in the dark theme.
  static const pureBlackTheme = BoolSetting('pureBlackTheme', section: 'theme', defaultValue: false);

  /// Bookkeeping: 1 once a stored [legacyThemeColor] was moved to
  /// [brandThemeColor] (so a later pick of 3.x's blue stays).
  static const themeColorMigration = IntSetting(
    'themeColorMigration',
    section: 'meta',
    defaultValue: 0,
    scope: SettingScope.internal,
  );

  /// Language display name (`简体中文`, `English`, `日本語`…, the app's
  /// `AppLanguage.displayName`); 3.x's backups also used `languageName`.
  static const language = StringSetting(
    'language',
    section: 'theme',
    defaultValue: '简体中文',
    legacyKeys: ['languageName'],
  );

  /// Grid spacing.
  static const crossAxisSpacing = DoubleSetting('crossAxisSpacing', section: 'theme', defaultValue: 6, min: 0, max: 64);

  /// Grid spacing.
  static const mainAxisSpacing = DoubleSetting('mainAxisSpacing', section: 'theme', defaultValue: 6, min: 0, max: 64);

  /// Loading indicator style key.
  static const loadingStyle = StringSetting('loadingStyle', section: 'theme', defaultValue: 'default');

  /// Loading indicator colour; empty follows the theme.
  static const loadingStyleColorSwitch = StringSetting('loadingStyleColorSwitch', section: 'theme', defaultValue: '');

  // ---- font (font_settings_controller.dart:39-47) ----

  /// Text scale (0.5..2, font_settings_controller.dart:17-18).
  static const textScaleFactor = DoubleSetting('textScaleFactor', section: 'font', defaultValue: 1, min: 0.5, max: 2);

  /// Small text size (9..15, font_settings_controller.dart:19-33 gives
  /// every size's range).
  static const fontSizeBodySmall = DoubleSetting(
    'fontSizeBodySmall',
    section: 'font',
    defaultValue: 12,
    min: 9,
    max: 15,
  );

  /// Body text size (11..17).
  static const fontSizeBodyMedium = DoubleSetting(
    'fontSizeBodyMedium',
    section: 'font',
    defaultValue: 13,
    min: 11,
    max: 17,
  );

  /// Large body text size (12..18).
  static const fontSizeBodyLarge = DoubleSetting(
    'fontSizeBodyLarge',
    section: 'font',
    defaultValue: 14,
    min: 12,
    max: 18,
  );

  /// Heading size (13..20).
  static const fontSizeTitleMedium = DoubleSetting(
    'fontSizeTitleMedium',
    section: 'font',
    defaultValue: 15,
    min: 13,
    max: 20,
  );

  /// Large heading size (16..26).
  static const fontSizeTitleLarge = DoubleSetting(
    'fontSizeTitleLarge',
    section: 'font',
    defaultValue: 20,
    min: 16,
    max: 26,
  );

  /// App font id.
  static const fontFamilyName = StringSetting('fontFamilyName', section: 'font', defaultValue: 'Default');

  /// App font file (downloaded on this device).
  static const fontFamilyFileName = StringSetting('fontFamilyFileName', section: 'font', defaultValue: '');

  /// Danmaku font file (downloaded on this device).
  static const danmakuFontFamilyFileName = StringSetting(
    'danmakuFontFamilyFileName',
    section: 'font',
    defaultValue: '',
  );

  // ---- player (player_settings_controller.dart:33-71) ----

  /// Index into contain, cover, fill, fitHeight, fitWidth, scaleDown; any
  /// other reads 0 (3.x `normalizeVideoFitIndex`; J01.3).
  static const videoFitIndex = IntSetting(
    'videoFitIndex',
    section: 'player',
    defaultValue: 0,
    min: 0,
    max: 5,
    resetOutOfRange: true,
  );

  /// 3.x's player engine; v4 plays everything with mpv, kept for backups.
  static const videoPlayerKey = StringSetting('videoPlayerKey', section: 'player', defaultValue: 'mpv');

  /// Preferred quality name on Wi-Fi (`原画`, `蓝光8M`, `蓝光4M`, `超清`, `流畅`).
  static const preferResolution = StringSetting(
    'preferResolution',
    section: 'player',
    defaultValue: '原画',
    allowed: resolutions,
  );

  /// Preferred quality name on mobile data.
  static const preferResolutionCellular = StringSetting(
    'preferResolutionCellular',
    section: 'player',
    defaultValue: '原画',
    allowed: resolutions,
  );

  /// 3.x's quality names (player_consts.dart:25).
  static const Set<String> resolutions = {'原画', '蓝光8M', '蓝光4M', '超清', '流畅'};

  /// Hardware decoding.
  static const enableCodec = BoolSetting('enableCodec', section: 'player', defaultValue: true);

  /// New (UPGRADES unified rule, 22-3, 14-5, 33-2, 8-8): H.264 qualities
  /// first so HEVC is only played when chosen by hand.
  static const preferH264 = BoolSetting('preferH264', section: 'player', defaultValue: true);

  /// Opt-in Bilibili Raw candidates, followed by every official play line.
  static const bilibiliPreferRaw = BoolSetting('bilibiliPreferRaw', section: 'player', defaultValue: false);

  /// Compatibility output.
  static const playerCompatMode = BoolSetting('playerCompatMode', section: 'player', defaultValue: false);

  /// Custom mpv outputs.
  static const customPlayerOutput = BoolSetting('customPlayerOutput', section: 'player', defaultValue: false);

  /// mpv `vo`.
  static const videoOutputDriver = StringSetting('videoOutputDriver', section: 'player', defaultValue: 'gpu');

  /// mpv `ao`.
  static const audioOutputDriver = StringSetting('audioOutputDriver', section: 'player', defaultValue: 'auto');

  /// mpv `hwdec`.
  static const videoHardwareDecoder = StringSetting('videoHardwareDecoder', section: 'player', defaultValue: 'auto');

  /// Picture-in-picture on leaving.
  static const floatPlay = BoolSetting('floatPlay', section: 'player', defaultValue: false);

  /// New (docs/A-界面设计/A07-直播间界面/A07.22-小窗改大小和尺寸设置; V01.5, D-036): how big the
  /// in-app floating window is ("小窗大小"): `small`, `medium` or `large`,
  /// 0.8, 1 and 1.25 × the size A07.8 c6 gives it. `medium` (the default)
  /// is that size, so nothing changes for a user who never picks one; 3.x
  /// had no such setting.
  static const floatWindowSize = StringSetting(
    'floatWindowSize',
    section: 'player',
    defaultValue: 'medium',
    allowed: {'small', 'medium', 'large'},
  );

  /// New (A07.22, as [floatWindowSize]): the in-app floating window's size
  /// for a landscape picture as the user pulled it (the grip or two
  /// fingers), as a factor of [floatWindowSize]'s; 1 = not changed. A
  /// factor, not pixels, so it fits another screen as well. Picking a size
  /// puts it back to 1.
  static const floatWindowLandscapeScale = DoubleSetting(
    'floatWindowLandscapeScale',
    section: 'player',
    defaultValue: 1,
    min: 0.25,
    max: 4,
  );

  /// New (A07.25 c6, the user: "位置也要记住，跨重启保存"): where the in-app
  /// floating window was left, kept across restarts — `x,y` as fractions of
  /// the screen's width and height, or `left,y` / `right,y` tucked into a
  /// side; empty for the corner. Internal: a place on this device's screen,
  /// not for backups.
  static const floatWindowPosition = StringSetting(
    'floatWindowPosition',
    section: 'player',
    defaultValue: '',
    scope: SettingScope.internal,
  );

  /// New (A07.22): [floatWindowLandscapeScale] for a portrait picture's
  /// window (each kept on its own, as upstream pure_live a25facd94).
  static const floatWindowPortraitScale = DoubleSetting(
    'floatWindowPortraitScale',
    section: 'player',
    defaultValue: 1,
    min: 0.25,
    max: 4,
  );

  /// Windows PiP on top.
  static const windowsPipAlwaysOnTop = BoolSetting('windowsPipAlwaysOnTop', section: 'player', defaultValue: false);

  /// Leaving the app from a playing room goes into the mini window by itself
  /// (U.2j, choice J1): the app's floating window, or the system's
  /// picture-in-picture with [useSystemPip] (A07.25; before, always the
  /// picture-in-picture). New in v4, off by default; 3.x only had the button.
  static const autoPipOnLeave = BoolSetting('autoPipOnLeave', section: 'player', defaultValue: false);

  /// New (A07.25 c12, D-042, "改用系统画中画"): the mini window button,
  /// leaving the app with the mini window and [autoPipOnLeave] use the
  /// system's picture-in-picture instead of the in-app window and its
  /// floating window over other apps ("显示在其他应用的上层"). Off by default;
  /// a user who had [autoPipOnLeave] on keeps the picture-in-picture (set
  /// once at start, `keepPictureInPicture`).
  static const useSystemPip = BoolSetting('useSystemPip', section: 'player', defaultValue: false);

  /// New (A07.25 c9): the toast saying the floating window can stay over
  /// other apps ("显示在其他应用的上层") was shown; it shows once. Internal: a
  /// note of this device's.
  static const floatOverlayTipShown = BoolSetting(
    'floatOverlayTipShown',
    section: 'player',
    defaultValue: false,
    scope: SettingScope.internal,
  );

  /// NVIDIA RTX video super resolution.
  static const enableRtxVsr = BoolSetting('enableRtxVsr', section: 'player', defaultValue: false);

  /// Hard stop on exit.
  static const useHardStopOnExit = BoolSetting('useHardStopOnExit', section: 'player', defaultValue: false);

  /// Portrait stream adaptation.
  static const enablePortraitStreamAdaptation = BoolSetting(
    'enablePortraitStreamAdaptation',
    section: 'player',
    defaultValue: true,
  );

  /// Portrait adaptive height.
  static const portraitAdaptiveHeight = BoolSetting('portraitAdaptiveHeight', section: 'player', defaultValue: true);

  /// Portrait layout.
  static const portraitLayoutMode = StringSetting('portraitLayoutMode', section: 'player', defaultValue: 'balanced');

  /// Portrait full-screen policy.
  static const portraitFullscreenPolicy = StringSetting(
    'portraitFullscreenPolicy',
    section: 'player',
    defaultValue: 'followSource',
  );

  /// Portrait full-screen display mode.
  static const portraitFullscreenDisplayMode = StringSetting(
    'portraitFullscreenDisplayMode',
    section: 'player',
    defaultValue: 'ambient',
  );

  /// Portrait PiP follows the source.
  static const portraitPipFollowSource = BoolSetting('portraitPipFollowSource', section: 'player', defaultValue: true);

  /// Portrait danmaku mode.
  static const portraitDanmakuMode = StringSetting(
    'portraitDanmakuMode',
    section: 'player',
    defaultValue: 'followGlobal',
  );

  /// Remember per-room portrait overrides.
  static const rememberPortraitRoomOverride = BoolSetting(
    'rememberPortraitRoomOverride',
    section: 'player',
    defaultValue: true,
  );

  /// New (docs/A-界面设计/A07-直播间界面/A07.2-竖屏流和竖屏全屏 c14, U.2b2; 3.x has no such setting): in the
  /// portrait fullscreen an upward swipe in the middle of the picture opens
  /// the next room of the list the room was opened from, a downward one the
  /// previous. Off by default.
  static const portraitFullscreenSwipeSwitch = BoolSetting(
    'portraitFullscreenSwipeSwitch',
    section: 'player',
    defaultValue: false,
  );

  /// Portrait diagnostics overlay.
  static const showPortraitDiagnostics = BoolSetting('showPortraitDiagnostics', section: 'player', defaultValue: false);

  /// Per-room portrait layout, `{"platform:roomId": "<layout>"}`.
  static const portraitRoomOverrides = JsonSetting('portraitRoomOverrides', section: 'player', defaultValue: {});

  /// The wide room's chat column is folded away (docs/A-界面设计/A07-直播间界面/A07.5-宽屏左右分栏
  /// change 7; new in v4, remembered for the next room).
  static const livePlayChatCollapsed = BoolSetting('livePlayChatCollapsed', section: 'player', defaultValue: false);

  /// New (docs/A-界面设计/A07-直播间界面/A07.13-切换直播间面板/brief.md, docs/A-界面设计/A07-直播间界面/A07.13-切换直播间面板 c4; 3.x has no such
  /// setting): how the live room's "切换直播间" panel shows the rooms, kept
  /// from the panel's style button: `grid` (the default, 3.x's small cards,
  /// GitHub issue #37) or `list` (rows with a 16:9 cover).
  static const roomSwitcherLayout = StringSetting(
    'roomSwitcherLayout',
    section: 'player',
    defaultValue: 'grid',
    allowed: {'grid', 'list'},
  );

  // ---- danmaku (danmaku_settings_controller.dart:58-111) ----

  /// Hide danmaku.
  static const hideDanmaku = BoolSetting('hideDanmaku', section: 'danmaku', defaultValue: false);

  /// Hide emoji danmaku.
  static const noEmojiMode = BoolSetting('noEmojiMode', section: 'danmaku', defaultValue: false);

  /// Space kept free above the danmaku, in logical pixels (0..300 as 3.x's
  /// `_boundedDouble`, danmaku_settings_controller.dart:115; it was clamped
  /// to 0..1 here before, which turned a 3.x value of 40 into 1).
  static const danmakuTopArea = DoubleSetting('danmakuTopArea', section: 'danmaku', defaultValue: 0, min: 0, max: 300);

  /// Display area.
  static const danmakuArea = DoubleSetting('danmakuArea', section: 'danmaku', defaultValue: 1, min: 0, max: 1);

  /// Space kept free below the danmaku, in logical pixels (0..300, see
  /// [danmakuTopArea]; 3.x's default is 0.5).
  static const danmakuBottomArea = DoubleSetting(
    'danmakuBottomArea',
    section: 'danmaku',
    defaultValue: 0.5,
    min: 0,
    max: 300,
  );

  /// Scroll speed, pixels per second (20..400: 3.x clamped a stored or
  /// imported value, danmaku_settings_controller.dart:118, J01.2).
  static const danmakuSpeed = DoubleSetting('danmakuSpeed', section: 'danmaku', defaultValue: 120, min: 20, max: 400);

  /// Font size (10..60); the existing default stays 16.
  static const danmakuFontSize = DoubleSetting(
    'danmakuFontSize',
    section: 'danmaku',
    defaultValue: 16,
    min: 10,
    max: 60,
  );

  /// Font weight (100..900 in hundreds: 550 reads 600,
  /// danmaku_settings_controller.dart:41-44; J01.3).
  static const danmakuFontWeight = IntSetting(
    'danmakuFontWeight',
    section: 'danmaku',
    defaultValue: 500,
    min: 100,
    max: 900,
    step: 100,
  );

  /// Stroke width.
  static const danmakuFontBorder = DoubleSetting(
    'danmakuFontBorder',
    section: 'danmaku',
    defaultValue: 1.5,
    min: 0,
    max: 4,
  );

  /// Opacity.
  static const danmakuOpacity = DoubleSetting('danmakuOpacity', section: 'danmaku', defaultValue: 1, min: 0, max: 1);

  /// Show danmaku.
  static const enableDanmakuDisplay = BoolSetting('enableDanmakuDisplay', section: 'danmaku', defaultValue: true);

  /// Stroke.
  static const enableDanmakuStroke = BoolSetting('enableDanmakuStroke', section: 'danmaku', defaultValue: true);

  /// The chat list's look in the room (U.2a): `compact` lines ("用户名：" in
  /// a secondary colour, then the message) or 3.x's `card` per message.
  /// New in v4; 3.x always drew cards.
  static const danmakuListStyle = StringSetting(
    'danmakuListStyle',
    section: 'danmaku',
    defaultValue: 'compact',
    allowed: {'compact', 'card'},
  );

  /// Gifts appear as lines in the room's chat list (B-21; A08.6 c3, G1 A).
  /// New in v4 (3.x had no gift lines); the room kept it in `meta`
  /// (`live_play.showGifts`) before it was a setting, taken over once when
  /// the store opens.
  static const showChatGifts = BoolSetting('showChatGifts', section: 'danmaku', defaultValue: true);

  /// New (docs/A-界面设计/A08-弹幕界面/A08.15-聊天列表字号和行距; 3.x drew its cards at a fixed 14):
  /// the size of the room's chat list text ("列表文字大小"), 12..22; 0, the
  /// default, keeps the theme's body size as before (D-040). The marks of a
  /// line (chips, badges, the gift's picture, the avatar) follow it; the
  /// system text scale still applies on top. Out of range reads as 0.
  static const danmakuListFontSize = IntSetting(
    'danmakuListFontSize',
    section: 'danmaku',
    defaultValue: 0,
    min: 12,
    max: 22,
    resetOutOfRange: true,
  );

  /// New (A08.15): how far apart the chat list's lines sit ("行间距"):
  /// `compact` (half the gaps, the text 1.4 high), `standard` (the default,
  /// as before) or `loose` (1.5 times the gaps, the text 1.7 high).
  static const danmakuListLineSpacing = StringSetting(
    'danmakuListLineSpacing',
    section: 'danmaku',
    defaultValue: 'standard',
    allowed: {'compact', 'standard', 'loose'},
  );

  /// New (docs/A-界面设计/A08-弹幕界面/A08.12-礼物开关和飞行弹幕里的礼物; 3.x had no gift lines): the
  /// chat list keeps only the platform's gifts worth a mark ("只显示值钱的礼物":
  /// `LiveGiftTier.valuable` and up, about 10 yuan); free and cheap ones
  /// are left out, a combo shows once its total gets there. Off by default
  /// (D-040: nothing changes for old users); it acts only while
  /// [showChatGifts] is on. Local gifts always show.
  static const chatGiftsAboveTier = BoolSetting('chatGiftsAboveTier', section: 'danmaku', defaultValue: false);

  /// New (A08.12): a gift line writes the value of the platforms whose rate
  /// is fixed in yuan ("礼物价值换算成元": 1000 gold seeds, 10 Missevan
  /// diamonds, 10 Douyin coins are 1 yuan); other units stay the platform's.
  /// Off by default (D-040).
  static const giftValueInYuan = BoolSetting('giftValueInYuan', section: 'danmaku', defaultValue: false);

  /// New (A08.12): the platform's gifts worth a mark fly over the picture
  /// as danmaku of their own look ("飞行弹幕显示礼物"; the room, fullscreen,
  /// the mini windows, the multi-view and the TV): a precious one stands at
  /// the top for 4 s, a combo flies when it starts and once more with its
  /// total, at most 3 a second. Off by default (D-040); independent of
  /// [showChatGifts].
  static const danmakuShowGifts = BoolSetting('danmakuShowGifts', section: 'danmaku', defaultValue: false);

  /// Shows an entry over fullscreen video while a super chat is active.
  static const showFullscreenSuperChat = BoolSetting('showFullscreenSuperChat', section: 'danmaku', defaultValue: true);

  /// New (docs/D-弹幕/D07-礼物和付费消息/D07.2-醒目留言平台表和价格单位; 3.x had no
  /// memberships): a membership or subscription the platform reports
  /// (Bilibili's guards, YouTube's memberships, Twitch's, CHZZK's, Kick's
  /// and Picarto's subscriptions) is also a card among the super chats
  /// ("上舰和开会员进醒目留言"), for as long as a super chat of its price; the
  /// chat list keeps its one line either way. On by default: the exception
  /// D-040 names (V03.5 §6.6: only the super chats get more cards).
  static const superChatIncludesMembership = BoolSetting(
    'superChatIncludesMembership',
    section: 'danmaku',
    defaultValue: true,
  );

  /// New (docs/A-界面设计/A08-弹幕界面/A08.10-弹幕列表名字和内容分开; 3.x has no such setting): the
  /// room's chat list names who sent each line ("显示用户名"); off, it shows
  /// only what was said. On by default, as 3.x and before. The flying
  /// danmaku never show names; the long-press card always does.
  static const showChatNames = BoolSetting('showChatNames', section: 'danmaku', defaultValue: true);

  /// New (docs/A-界面设计/A07-直播间界面/A07.10-暂停状态/brief.md c3; 3.x has no such setting): what the
  /// platform's flying danmaku do while the video is paused ("暂停时的弹幕"):
  /// `pause` stands them with the video (the default, as 3.x's main
  /// picture), `continue` lets them fly on and new ones in. Danmaku composed
  /// on this device fly on either way.
  static const danmakuPausedBehavior = StringSetting(
    'danmakuPausedBehavior',
    section: 'danmaku',
    defaultValue: 'pause',
    allowed: {'pause', 'continue'},
  );

  /// Frame rate.
  static const danmakuFps = IntSetting('danmakuFps', section: 'danmaku', defaultValue: 60, min: 30, max: 240);

  /// Automatic frame rate.
  static const danmakuAutoFps = BoolSetting('danmakuAutoFps', section: 'danmaku', defaultValue: true);

  /// New (docs/D-弹幕/D05-弹幕设置生效/D05.2-同屏最大弹幕条数可以设置; V01.4, D-036): at most this many
  /// of the platform's danmaku fly over the picture at once ("同屏最大弹幕条数";
  /// 3.x always 48, the default). Danmaku composed on this device do not
  /// count. 10..120; a value out of range (pure_live_TV's backups store 0
  /// for "by device") reads as 48.
  static const danmakuMaxVisibleCount = IntSetting(
    'danmakuMaxVisibleCount',
    section: 'danmaku',
    defaultValue: 48,
    min: 10,
    max: 120,
    resetOutOfRange: true,
  );

  /// Tap a danmaku for actions.
  static const enableDanmakuTapInteraction = BoolSetting(
    'enableDanmakuTapInteraction',
    section: 'danmaku',
    defaultValue: true,
  );

  /// Long-press a danmaku for actions.
  static const enableDanmakuLongPressInteraction = BoolSetting(
    'enableDanmakuLongPressInteraction',
    section: 'danmaku',
    defaultValue: true,
  );

  /// New (docs/D-弹幕/D03-飞行弹幕引擎/D03.4-按住飞行弹幕让它停住; V01.3, D-036): a finger pressing a
  /// flying danmaku on the room's picture pins that one where it is, the
  /// others fly on; it flies on when the finger lifts or moves away
  /// ("按住飞行弹幕让它停住"). On by default (D-039, the one exception to
  /// D-036's "nothing changes for old users"); off, the picture behaves as
  /// 3.x's. The tap and long-press actions are unchanged either way.
  static const holdDanmakuOnPress = BoolSetting('holdDanmakuOnPress', section: 'danmaku', defaultValue: true);

  /// Collapse repeats.
  static const collapseRepeatedDanmaku = BoolSetting(
    'collapseRepeatedDanmaku',
    section: 'danmaku',
    defaultValue: false,
  );

  /// Repeat window, seconds (1..30, danmaku_settings_controller.dart:260).
  static const repeatedDanmakuWindowSeconds = IntSetting(
    'repeatedDanmakuWindowSeconds',
    section: 'danmaku',
    defaultValue: 5,
    min: 1,
    max: 30,
  );

  /// Saved danmaku template.
  static const savedDanmakuTemplate = StringSetting('savedDanmakuTemplate', section: 'danmaku', defaultValue: '');

  /// Danmaku font id.
  static const danmakuFontFamilyName = StringSetting(
    'danmakuFontFamilyName',
    section: 'danmaku',
    defaultValue: 'Default',
  );

  /// Danmaku in PiP.
  static const enablePipDanmaku = BoolSetting('enablePipDanmaku', section: 'danmaku', defaultValue: true);

  /// PiP danmaku scaling.
  static const pipDanmakuAutoScale = BoolSetting('pipDanmakuAutoScale', section: 'danmaku', defaultValue: true);

  /// PiP: hide emoji (3.x's Hive key is misspelt; backups use the right name).
  static const pipDanmakuNoEmojiMode = BoolSetting(
    'pipDanmaNoEmojiMode',
    section: 'danmaku',
    defaultValue: false,
    backupKey: 'pipDanmakuNoEmojiMode',
  );

  /// PiP: original colours.
  static const pipDanmakuUseOriginalColor = BoolSetting(
    'pipDanmakuUseOriginalColor',
    section: 'danmaku',
    defaultValue: true,
  );

  /// PiP colour, ARGB.
  static const pipDanmakuColor = IntSetting('pipDanmakuColor', section: 'danmaku', defaultValue: 0xFFFFFFFF);

  // The PiP ranges are 3.x's on a backup import, which its PiP page's
  // sliders also kept to (danmaku_settings_controller.dart:272-291, J01.2).

  /// PiP font size (8..24).
  static const pipDanmakuFontSize = DoubleSetting(
    'pipDanmakuFontSize',
    section: 'danmaku',
    defaultValue: 12,
    min: 8,
    max: 24,
  );

  /// PiP font weight (100..900 in hundreds, as [danmakuFontWeight]).
  static const pipDanmakuFontWeight = IntSetting(
    'pipDanmakuFontWeight',
    section: 'danmaku',
    defaultValue: 500,
    min: 100,
    max: 900,
    step: 100,
  );

  /// PiP speed (20..400).
  static const pipDanmakuSpeed = DoubleSetting(
    'pipDanmakuSpeed',
    section: 'danmaku',
    defaultValue: 90,
    min: 20,
    max: 400,
  );

  /// PiP opacity (0.1..1).
  static const pipDanmakuOpacity = DoubleSetting(
    'pipDanmakuOpacity',
    section: 'danmaku',
    defaultValue: 0.9,
    min: 0.1,
    max: 1,
  );

  /// PiP area (0.1..1).
  static const pipDanmakuArea = DoubleSetting(
    'pipDanmakuArea',
    section: 'danmaku',
    defaultValue: 0.5,
    min: 0.1,
    max: 1,
  );

  /// PiP visible count (1..20).
  static const pipDanmakuMaxVisibleCount = IntSetting(
    'pipDanmakuMaxVisibleCount',
    section: 'danmaku',
    defaultValue: 6,
    min: 1,
    max: 20,
  );

  /// PiP emit interval, seconds (0.05..2).
  static const pipDanmakuEmitInterval = DoubleSetting(
    'pipDanmakuEmitInterval',
    section: 'danmaku',
    defaultValue: 0.35,
    min: 0.05,
    max: 2,
  );

  /// PiP frame rate (15..240).
  static const pipDanmakuFps = IntSetting('pipDanmakuFps', section: 'danmaku', defaultValue: 30, min: 15, max: 240);

  /// PiP automatic frame rate.
  static const pipDanmakuAutoFps = BoolSetting('pipDanmakuAutoFps', section: 'danmaku', defaultValue: true);

  /// Drop Douyu's suspected bot messages.
  static const filterDouyuSuspectedAutomatedMessages = BoolSetting(
    'filterDouyuSuspectedAutomatedMessages',
    section: 'danmaku',
    defaultValue: false,
  );

  /// Similarity filter.
  static const enableDanmakuSimilarityFilter = BoolSetting(
    'enableDanmakuSimilarityFilter',
    section: 'danmaku',
    defaultValue: false,
  );

  /// Similarity threshold, percent (50..100).
  static const danmakuSimilarityThreshold = IntSetting(
    'danmakuSimilarityThreshold',
    section: 'danmaku',
    defaultValue: 85,
    min: 50,
    max: 100,
  );

  /// Similarity cache duration (1..60, danmaku_settings_controller.dart:126).
  static const danmakuSimilarityCacheDuration = IntSetting(
    'danmakuSimilarityCacheDuration',
    section: 'danmaku',
    defaultValue: 3,
    min: 1,
    max: 60,
  );

  /// Similarity cache size (20..1000, danmaku_settings_controller.dart:127).
  static const danmakuSimilarityMaxCacheSize = IntSetting(
    'danmakuSimilarityMaxCacheSize',
    section: 'danmaku',
    defaultValue: 100,
    min: 20,
    max: 1000,
  );

  /// New (docs/D-弹幕/D02-过滤和屏蔽/D02.2-正则屏蔽和更多屏蔽; V03.6 E11, D-040): a platform
  /// message that is nothing but emoticons (pictures or Unicode emoji) is
  /// hidden ("屏蔽只有表情的弹幕"). Off by default, as 3.x, which had no such
  /// block.
  static const blockEmoteOnlyDanmaku = BoolSetting('blockEmoteOnlyDanmaku', section: 'danmaku', defaultValue: false);

  /// New (D02.2, as [blockEmoteOnlyDanmaku]): a platform message longer than
  /// [blockLongDanmakuLength] characters is hidden ("屏蔽超长弹幕"). Off by
  /// default, as 3.x.
  static const blockLongDanmaku = BoolSetting('blockLongDanmaku', section: 'danmaku', defaultValue: false);

  /// New (D02.2): the most characters [blockLongDanmaku] lets through, an
  /// emoticon counting as one (10..100).
  static const blockLongDanmakuLength = IntSetting(
    'blockLongDanmakuLength',
    section: 'danmaku',
    defaultValue: 30,
    min: 10,
    max: 100,
  );

  /// New (UPGRADES B-13): YouTube "Live chat" (every message) instead of
  /// the web page's default "Top chat".
  static const youtubeShowAllChat = BoolSetting('youtubeShowAllChat', section: 'danmaku', defaultValue: false);

  // ---- volume (volume_settings_controller.dart:8-11) ----

  /// Default volume on phones.
  static const defaultMobileVolume = DoubleSetting(
    'defaultMobileVolume',
    section: 'volume',
    defaultValue: 0.5,
    min: 0,
    max: 1,
  );

  /// Default volume on desktops.
  static const defaultDesktopVolume = DoubleSetting(
    'defaultDesktopVolume',
    section: 'volume',
    defaultValue: 1,
    min: 0,
    max: 1,
  );

  /// "音量增强" (issue wzgrx/pure_live#38): extra gain in dB on top of the
  /// volume, for streams quieter than the platforms' own apps (which raise
  /// their sound); one of [volumeBoostSteps], 0 is off.
  static const volumeBoostDb = IntSetting(
    'volumeBoostDb',
    section: 'volume',
    defaultValue: 0,
    min: 0,
    max: 12,
    resetOutOfRange: true,
  );

  /// The choices of [volumeBoostDb].
  static const volumeBoostSteps = [0, 3, 6, 9, 12];

  /// Mute everything.
  static const globalVolumeMute = BoolSetting('globalVolumeMute', section: 'volume', defaultValue: false);

  /// Per-room volume, `{"room_vol_<platform>_<roomId>": 0..1}`.
  static const roomVolumes = JsonSetting('roomVolumes', section: 'volume', defaultValue: {});

  /// Optional per-room signed dB overrides; absent entries inherit the global gain.
  static const roomVolumeGains = JsonSetting('roomVolumeGains', section: 'volume', defaultValue: {});

  /// Application capture banner visibility; OS privacy indicators are unaffected.
  static const screenCaptureHint = StringSetting('screenCaptureHint', section: 'app', defaultValue: 'full');

  /// Optional local image or colour behind phone and desktop pages.
  static const customBackground = JsonSetting('customBackground', section: 'app', defaultValue: {});

  /// Local clock and media input-rate presentation; absent keys retain defaults.
  static const playbackHud = JsonSetting('playbackHud', section: 'player', defaultValue: {});

  /// Opt-in coexistence with external media; system interruptions still apply.
  static const allowAudioMixing = BoolSetting('allowAudioMixing', section: 'volume', defaultValue: false);

  // ---- room card (room_card_settings_controller.dart:251-265) ----

  /// Phone card preset (`compact`, `normal`, `rich`, `custom`).
  static const roomCardMobilePreset = StringSetting(
    'room_card_mobile_preset',
    section: 'roomCard',
    defaultValue: 'normal',
    allowed: {'compact', 'normal', 'rich', 'custom'},
    backupKey: 'mobilePreset',
  );

  /// Desktop card preset.
  static const roomCardDesktopPreset = StringSetting(
    'room_card_desktop_preset',
    section: 'roomCard',
    defaultValue: 'normal',
    allowed: {'compact', 'normal', 'rich', 'custom'},
    backupKey: 'desktopPreset',
  );

  /// Phone card appearance; empty uses the preset.
  static const roomCardMobileConfig = JsonSetting(
    'room_card_mobile_config',
    section: 'roomCard',
    defaultValue: {},
    backupKey: 'mobileConfig',
  );

  /// Desktop card appearance; empty uses the preset.
  static const roomCardDesktopConfig = JsonSetting(
    'room_card_desktop_config',
    section: 'roomCard',
    defaultValue: {},
    backupKey: 'desktopConfig',
  );

  /// How large the room cards of a desktop grid are (V02.47): `smaller`,
  /// `small`, `standard` (the widths of UI.md §5.3), `large`, `xlarge` or
  /// `xxlarge`.
  static const roomCardSize = StringSetting(
    'room_card_size',
    section: 'roomCard',
    defaultValue: 'standard',
    allowed: {'smaller', 'small', 'standard', 'large', 'xlarge', 'xxlarge'},
    backupKey: 'cardSize',
  );

  // ---- page (page_settings_controller.dart:14-19) ----

  /// Page-size selector.
  static const pageShowSizeSelector = BoolSetting(
    'page_show_size_selector',
    section: 'page',
    defaultValue: true,
    backupKey: 'showPageSizeSelector',
  );

  /// "Go to page" button.
  static const pageShowGotoButton = BoolSetting(
    'page_show_goto_button',
    section: 'page',
    defaultValue: true,
    backupKey: 'showGotoButton',
  );

  /// Scroll-to-top button.
  static const pageShowScrollTop = BoolSetting(
    'page_show_scroll_top',
    section: 'page',
    defaultValue: true,
    backupKey: 'showScrollToTopBtn',
  );

  /// Rooms per page; 0 = by screen width (20 above 960 logical px, else 12,
  /// page_settings_controller.dart:23-32), decided by the UI.
  static const pageDefaultSize = IntSetting(
    'page_default_size',
    section: 'page',
    defaultValue: 0,
    min: 0,
    max: 100,
    backupKey: 'defaultPageSize',
  );

  /// Page-size choices, comma separated (a list of numbers in backups).
  static const pageSizeOptions = StringSetting(
    'page_size_options_raw',
    section: 'page',
    defaultValue: '',
    backupKey: 'pageSizeOptions',
  );

  // ---- refresh (refresh_config_controller.dart:21-30) ----

  /// Refresh follows on a timer.
  static const autoRefreshFavorite = BoolSetting('autoRefreshFavorite', section: 'refresh', defaultValue: false);

  /// Refresh follows when the app returns.
  static const refreshFavoriteOnResume = BoolSetting('refreshFavoriteOnResume', section: 'refresh', defaultValue: true);

  /// Minutes between follow refreshes (5..360).
  static const autoRefreshInterval = IntSetting(
    'autoRefreshInterval',
    section: 'refresh',
    defaultValue: 30,
    min: 5,
    max: 360,
  );

  /// Parallel refresh requests (1..20).
  static const maxConcurrentRefresh = IntSetting(
    'maxConcurrentRefresh',
    section: 'refresh',
    defaultValue: 4,
    min: 1,
    max: 20,
  );

  /// "开播提醒": a system notification when a followed streamer goes live,
  /// while the app runs (O01.1, V01.1; new in v4, off as D-036 asks).
  static const liveAlertEnabled = BoolSetting('liveAlertEnabled', section: 'refresh', defaultValue: false);

  /// The tags whose follows [liveAlertEnabled] covers; empty covers every
  /// follow (O01.1).
  static const liveAlertTagIds = StringListSetting('liveAlertTagIds', section: 'refresh', defaultValue: []);

  /// The follows given their own "开播提醒" switch (A09.13; identity keys,
  /// `platform:roomId`): covered besides [liveAlertTagIds]'s. New in v4,
  /// empty: as before.
  static const liveAlertRoomKeys = StringListSetting('liveAlertRoomKeys', section: 'refresh', defaultValue: []);

  /// [liveAlertEnabled] also checks after Android froze or cleared the
  /// app (O01.2, WorkManager every 15 minutes or later). New in v4, on:
  /// only does anything while [liveAlertEnabled] is on.
  static const liveAlertBackground = BoolSetting('liveAlertBackground', section: 'refresh', defaultValue: true);

  /// Refresh covers on a timer.
  static const autoRefreshThumbnails = BoolSetting('autoRefreshThumbnails', section: 'refresh', defaultValue: false);

  /// Minutes between cover refreshes (5..360).
  static const thumbnailRefreshInterval = IntSetting(
    'thumbnailRefreshInterval',
    section: 'refresh',
    defaultValue: 30,
    min: 5,
    max: 360,
  );

  // ---- iptv (iptv_settings_controller.dart:22-27) ----

  /// Selected source name.
  static const selectedSourceName = StringSetting('selectedSourceName', section: 'iptv', defaultValue: '');

  /// Selected source id.
  static const selectedSourceId = StringSetting('selectedSourceId', section: 'iptv', defaultValue: '');

  /// Automatic sync.
  static const isAutoSyncEnabled = BoolSetting('isAutoSyncEnabled', section: 'iptv', defaultValue: false);

  /// Sync interval in hours (2..72).
  static const autoSyncHoursInterval = IntSetting(
    'autoSyncHoursInterval',
    section: 'iptv',
    defaultValue: 24,
    min: 2,
    max: 72,
  );

  /// IPTV User-Agent.
  static const customIptvUserAgent = StringSetting('customIptvUserAgent', section: 'iptv', defaultValue: '');

  /// Playlist folder (3.x's default is the literal key).
  static const m3uDirectory = StringSetting('m3uDirectory', section: 'iptv', defaultValue: 'm3uDirectory');

  /// The playlist the popular page's IPTV tab shows (V02.9, issue #6): a
  /// playlist id; empty for the built-in hot list (3.x showed only that).
  static const iptvPopularPlaylist = StringSetting('iptvPopularPlaylist', section: 'iptv', defaultValue: '');

  /// The built-in hot list was deleted (V02.9): it is not imported again
  /// until restored on the IPTV page (3.x imported it again on every visit).
  static const iptvHotRemoved = BoolSetting('iptvHotRemoved', section: 'iptv', defaultValue: false);

  // ---- proxy (proxy_settings_controller.dart:11-18) ----

  /// Player proxy.
  static const enableProxy = BoolSetting('enableProxy', section: 'proxy', defaultValue: false);

  /// Player proxy host.
  static const proxyHost = StringSetting('proxyHost', section: 'proxy', defaultValue: '');

  /// Player proxy port; outside 1..65535 reads 7897 (3.x
  /// `normalizeStoredProxyPort`, proxy_routing.dart:9; J01.3).
  static const proxyPort = IntSetting(
    'proxyPort',
    section: 'proxy',
    defaultValue: 7897,
    min: 1,
    max: 65535,
    resetOutOfRange: true,
  );

  /// App (request) proxy.
  static const enableAppProxy = BoolSetting('enableAppProxy', section: 'proxy', defaultValue: false);

  /// App proxy host.
  static const appProxyHost = StringSetting('appProxyHost', section: 'proxy', defaultValue: '');

  /// App proxy port; outside 1..65535 reads 7897 (as [proxyPort]).
  static const appProxyPort = IntSetting(
    'appProxyPort',
    section: 'proxy',
    defaultValue: 7897,
    min: 1,
    max: 65535,
    resetOutOfRange: true,
  );

  // ---- window, exit, startup (window_size_controller.dart, exit_settings_controller.dart, startup_controller.dart) ----

  /// Restore the main window's last normal bounds and maximized state.
  static const rememberWindowGeometry = BoolSetting(
    'rememberWindowGeometry',
    section: 'windowSize',
    defaultValue: true,
  );

  /// Window width.
  static const windowWidth = DoubleSetting(
    'window_width',
    section: 'windowSize',
    defaultValue: 1280,
    min: 400,
    max: 16384,
  );

  /// Window height.
  static const windowHeight = DoubleSetting(
    'window_height',
    section: 'windowSize',
    defaultValue: 720,
    min: 300,
    max: 16384,
  );

  /// Remember the PiP window position.
  static const rememberPipPosition = BoolSetting('rememberPipPosition', section: 'windowSize', defaultValue: true);

  /// PiP display.
  static const windowsPipDisplayId = StringSetting(
    'windows_pip_display_id',
    section: 'windowSize',
    defaultValue: '',
    backupKey: 'displayId',
  );

  /// PiP geometry (0..16384, window_size_controller.dart:308, J01.2; 0 =
  /// nothing remembered).
  static const windowsPipWidth = DoubleSetting(
    'windows_pip_width',
    section: 'windowSize',
    defaultValue: 0,
    min: 0,
    max: 16384,
    backupKey: 'windowsPipWidth',
  );

  /// PiP geometry (as [windowsPipWidth]).
  static const windowsPipHeight = DoubleSetting(
    'windows_pip_height',
    section: 'windowSize',
    defaultValue: 0,
    min: 0,
    max: 16384,
    backupKey: 'windowsPipHeight',
  );

  /// PiP geometry.
  static const windowsPipX = DoubleSetting(
    'windows_pip_x',
    section: 'windowSize',
    defaultValue: 0,
    backupKey: 'windowsPipX',
  );

  /// PiP geometry.
  static const windowsPipY = DoubleSetting(
    'windows_pip_y',
    section: 'windowSize',
    defaultValue: 0,
    backupKey: 'windowsPipY',
  );

  /// Do not ask on exit.
  static const dontAskExit = BoolSetting('dontAskExit', section: 'exit', defaultValue: false);

  /// `exit` or `minimize`.
  static const exitChoose = StringSetting(
    'exitChoose',
    section: 'exit',
    defaultValue: 'exit',
    allowed: {'exit', 'minimize'},
  );

  /// Shutdown timer, minutes.
  static const autoShutDownTime = IntSetting(
    'autoShutDownTime',
    section: 'exit',
    defaultValue: 120,
    min: 1,
    max: 525600,
  );

  /// Shutdown timer.
  static const enableAutoShutDownTime = BoolSetting('enableAutoShutDownTime', section: 'exit', defaultValue: false);

  /// Start with Windows (3.x's default is on).
  static const enableStartUp = BoolSetting('enableStartUp', section: 'startup', defaultValue: true);

  // ---- recorder (lib/recorder/consts/recorder_keys.dart, recorder_config.dart) ----
  //
  // 3.x kept these in the same Hive box but never put them in backups (M8.1:
  // v4 backups carry them in a `recorder` section, which 3.x ignores). The
  // recorder (live_record `RecordSettings`) applies its own finer rules on
  // top (rw timeout and queue size are choices).

  /// Segment length, seconds.
  static const recordSegmentTime = IntSetting(
    'segmentTime',
    section: 'recorder',
    defaultValue: 300,
    min: 60,
    max: 3600,
  );

  /// Concurrent recordings.
  static const recordMaxTaskCount = IntSetting('maxTaskCount', section: 'recorder', defaultValue: 3, min: 1, max: 10);

  /// Retry an interrupted recording.
  static const recordAutoReconnect = BoolSetting('autoReconnect', section: 'recorder', defaultValue: true);

  /// Size limit of the recording folder, MiB.
  static const recordMaxCacheMB = IntSetting('maxCacheMB', section: 'recorder', defaultValue: 1024, min: 1);

  /// Delete the oldest recordings above [recordMaxCacheMB].
  static const recordEnableCacheLimit = BoolSetting('enableCacheLimit', section: 'recorder', defaultValue: false);

  /// Parent folder of the recordings ('' = the app's default). A path of
  /// this device, so backups do not carry it (like [backupDirectory]).
  static const recordSavePath = StringSetting(
    'recordSavePath',
    section: 'recorder',
    defaultValue: '',
    scope: SettingScope.internal,
  );

  /// The recording quality preference, best first (3.x
  /// `PlayerConsts.resolutions`; the stored values are 3.x's).
  static const recordQualityChoices = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅'];

  /// Default recording quality, one of [recordQualityChoices].
  static const recordDefaultQuality = StringSetting(
    'default_quality',
    section: 'recorder',
    defaultValue: '原画',
    allowed: {'原画', '蓝光8M', '蓝光4M', '超清', '流畅'},
  );

  /// Retries before waiting for the room again.
  static const recordMaxRetryCount = IntSetting(
    'max_retry_count',
    section: 'recorder',
    defaultValue: 5,
    min: 1,
    max: 20,
  );

  /// Retry delay, seconds.
  static const recordRetryDelay = IntSetting('retry_delay', section: 'recorder', defaultValue: 30, min: 5, max: 120);

  /// Check waiting rooms until they go live.
  static const recordEnablePolling = BoolSetting('enable_polling', section: 'recorder', defaultValue: false);

  /// Live check interval, seconds.
  static const recordLiveCheckInterval = IntSetting(
    'live_check_interval',
    section: 'recorder',
    defaultValue: 30,
    min: 10,
    max: 300,
  );

  /// Double the delays after each failure.
  static const recordEnableBackoff = BoolSetting('enable_backoff', section: 'recorder', defaultValue: false);

  /// Upper bound of backed-off delays, seconds.
  static const recordMaxCheckInterval = IntSetting(
    'max_check_interval',
    section: 'recorder',
    defaultValue: 300,
    min: 300,
    max: 3600,
  );

  /// Resume waiting and interrupted recordings when the app starts.
  static const recordAutoStartOnBoot = BoolSetting('auto_start_on_boot', section: 'recorder', defaultValue: false);

  /// Record only the first video and audio stream.
  static const recordPreferBestStream = BoolSetting(
    'recorder_prefer_best_stream',
    section: 'recorder',
    defaultValue: true,
  );

  /// FFmpeg read/write timeout, seconds (15, 30 or 60).
  static const recordRwTimeout = IntSetting(
    'recorder_rw_timeout',
    section: 'recorder',
    defaultValue: 15,
    min: 15,
    max: 60,
  );

  /// FFmpeg input thread queue size (512 to 8192).
  static const recordThreadQueueSize = IntSetting(
    'recorder_thread_queue_size',
    section: 'recorder',
    defaultValue: 2048,
    min: 512,
    max: 8192,
  );

  /// Name the platform and streamer folders in pinyin.
  static const recordPinyinFolders = BoolSetting(
    'recorder_folder_naming_strategy',
    section: 'recorder',
    defaultValue: false,
  );

  /// Save the chat beside each recording.
  static const recordDanmaku = BoolSetting('recorder_record_danmaku', section: 'recorder', defaultValue: false);

  /// New (docs/H-录制/H01-录制核心/H01.8-弹幕XML带礼物; 3.x saved only the
  /// chat): the saved chat file also has the room's gifts and super chats
  /// ("录制弹幕时包含礼物": `<gift>` and `<sc>` as BililiveRecorder writes
  /// them, a combo once). Off by default (D-040: the file stays as it was);
  /// it acts only while [recordDanmaku] (or the task's own choice) saves the
  /// chat.
  static const recordDanmakuGifts = BoolSetting('recordDanmakuGifts', section: 'recorder', defaultValue: false);

  /// The recorder's settings, in 3.x's key order, then v4's.
  static const List<Setting<Object>> recorder = [
    recordSegmentTime,
    recordMaxTaskCount,
    recordAutoReconnect,
    recordMaxCacheMB,
    recordEnableCacheLimit,
    recordSavePath,
    recordDefaultQuality,
    recordMaxRetryCount,
    recordRetryDelay,
    recordEnablePolling,
    recordLiveCheckInterval,
    recordEnableBackoff,
    recordMaxCheckInterval,
    recordAutoStartOnBoot,
    recordPreferBestStream,
    recordRwTimeout,
    recordThreadQueueSize,
    recordPinyinFolders,
    recordDanmaku,
    recordDanmakuGifts,
  ];

  // ---- local interaction (modules/live_play/widgets/local_interaction/
  // local_interaction_controller.dart:86-114) ----
  //
  // 3.x kept these in the same Hive box and never put them in backups; the
  // 3.x import parks them in `legacy_values` until they are registered here
  // (U.2k), and v4 backups carry them in a `localInteraction` section, which
  // 3.x ignores. Ranges are the ones 3.x's style editor and
  // `buildDanmakuStyle` allowed.

  /// The local interaction (local danmaku, gifts) is on.
  static const localInteractionEnabled = BoolSetting(
    'localInteraction.enabled',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The local nickname (at most 20 characters).
  static const localInteractionUserName = StringSetting(
    'localInteraction.userName',
    section: 'localInteraction',
    defaultValue: 'Pure Live',
  );

  /// The local title's id.
  static const localInteractionTitle = StringSetting(
    'localInteraction.title',
    section: 'localInteraction',
    defaultValue: 'listener',
    allowed: {'listener', 'night_owl', 'supporter', 'guardian'},
  );

  /// Local danmaku fly over the picture (they always join the chat list).
  static const localInteractionShowAsDanmaku = BoolSetting(
    'localInteraction.showAsDanmaku',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The platform's badge before the local name.
  static const localInteractionShowPlatformBadge = BoolSetting(
    'localInteraction.showPlatformBadge',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The local level in the badge.
  static const localInteractionShowLevelBadge = BoolSetting(
    'localInteraction.showLevelBadge',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The banner over the picture when a local gift is sent.
  static const localInteractionEnableGiftEffects = BoolSetting(
    'localInteraction.enableGiftEffects',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The platform pack previewed in the settings.
  static const localInteractionPreviewPlatform = StringSetting(
    'localInteraction.previewPlatform',
    section: 'localInteraction',
    defaultValue: SiteIds.bilibili,
  );

  /// Local coins.
  static const localInteractionCoins = IntSetting(
    'localInteraction.coins',
    section: 'localInteraction',
    defaultValue: 1000,
    min: 0,
  );

  /// Local experience (a level per 500).
  static const localInteractionExperience = IntSetting(
    'localInteraction.experience',
    section: 'localInteraction',
    defaultValue: 0,
    min: 0,
  );

  /// Gifts and coins added, newest first (at most 30).
  static const localInteractionHistory = StringListSetting(
    'localInteraction.history',
    section: 'localInteraction',
    defaultValue: [],
  );

  /// The local danmaku template's id, or `custom`.
  static const localDanmakuPreset = StringSetting(
    'localInteraction.danmakuPreset',
    section: 'localInteraction',
    defaultValue: 'clean',
  );

  /// The local danmaku colour, ARGB.
  static const localDanmakuColor = IntSetting(
    'localInteraction.danmakuColor',
    section: 'localInteraction',
    defaultValue: 0xFFFFFFFF,
  );

  /// The local danmaku font size.
  static const localDanmakuFontSize = DoubleSetting(
    'localInteraction.danmakuFontSize',
    section: 'localInteraction',
    defaultValue: 19,
    min: 14,
    max: 32,
  );

  /// The local danmaku speed, pixels per second.
  static const localDanmakuSpeed = DoubleSetting(
    'localInteraction.danmakuSpeed',
    section: 'localInteraction',
    defaultValue: 130,
    min: 60,
    max: 260,
  );

  /// The local danmaku font weight.
  static const localDanmakuFontWeight = IntSetting(
    'localInteraction.danmakuFontWeight',
    section: 'localInteraction',
    defaultValue: 600,
    min: 400,
    max: 900,
  );

  /// The local danmaku outline.
  static const localDanmakuShowStroke = BoolSetting(
    'localInteraction.danmakuShowStroke',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The outline width.
  static const localDanmakuStrokeWidth = DoubleSetting(
    'localInteraction.danmakuStrokeWidth',
    section: 'localInteraction',
    defaultValue: 1.5,
    min: 0,
    max: 4,
  );

  /// Where local danmaku fly: `scroll`, `top` or `bottom`.
  static const localDanmakuPlacement = StringSetting(
    'localInteraction.danmakuPlacement',
    section: 'localInteraction',
    defaultValue: 'scroll',
    allowed: {'scroll', 'top', 'bottom'},
  );

  /// The local danmaku font: `system`, `rounded`, `serif` or `mono`.
  static const localDanmakuFontFamily = StringSetting(
    'localInteraction.danmakuFontFamily',
    section: 'localInteraction',
    defaultValue: 'system',
    allowed: {'system', 'rounded', 'serif', 'mono'},
  );

  /// Italic local danmaku.
  static const localDanmakuItalic = BoolSetting(
    'localInteraction.danmakuItalic',
    section: 'localInteraction',
    defaultValue: false,
  );

  /// The local danmaku opacity.
  static const localDanmakuOpacity = DoubleSetting(
    'localInteraction.danmakuOpacity',
    section: 'localInteraction',
    defaultValue: 1,
    min: 0.35,
    max: 1,
  );

  /// The local danmaku letter spacing.
  static const localDanmakuLetterSpacing = DoubleSetting(
    'localInteraction.danmakuLetterSpacing',
    section: 'localInteraction',
    defaultValue: 0,
    min: -0.5,
    max: 3,
  );

  /// The outline colour, ARGB.
  static const localDanmakuStrokeColor = IntSetting(
    'localInteraction.danmakuStrokeColor',
    section: 'localInteraction',
    defaultValue: 0xFF000000,
  );

  /// The shadow (glow) of local danmaku.
  static const localDanmakuShowShadow = BoolSetting(
    'localInteraction.danmakuShowShadow',
    section: 'localInteraction',
    defaultValue: false,
  );

  /// The shadow colour, ARGB.
  static const localDanmakuShadowColor = IntSetting(
    'localInteraction.danmakuShadowColor',
    section: 'localInteraction',
    defaultValue: 0xFF000000,
  );

  /// The shadow blur.
  static const localDanmakuShadowBlur = DoubleSetting(
    'localInteraction.danmakuShadowBlur',
    section: 'localInteraction',
    defaultValue: 2,
    min: 0,
    max: 6,
  );

  /// The shadow offset.
  static const localDanmakuShadowOffset = DoubleSetting(
    'localInteraction.danmakuShadowOffset',
    section: 'localInteraction',
    defaultValue: 1,
    min: 0,
    max: 4,
  );

  /// How long a fixed (top or bottom) local danmaku stays, milliseconds.
  static const localDanmakuFixedDurationMs = IntSetting(
    'localInteraction.danmakuFixedDurationMs',
    section: 'localInteraction',
    defaultValue: 4000,
    min: 2000,
    max: 10000,
  );

  /// Entering a room puts the local danmaku sent there in the last 24 hours
  /// (at most 20) back at the top of the chat list, marked "之前发的"
  /// (D08.1 c6). New in v4: on by default, the exception D-040 names; off
  /// is the room as before.
  static const localInteractionReplayOnEnter = BoolSetting(
    'localInteraction.replayOnEnter',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// The user's phrases (D08.2), in their order: chips over the local
  /// danmaku composer, a tap sends one. At most [localPhraseLimit], trimmed,
  /// no empty ones or repeats; each at most a local danmaku's length (40
  /// characters, the app's `LocalCatalog.danmakuLimit`, kept by the app,
  /// which counts characters as the composer does). New in v4: empty, so
  /// nothing shows until one is saved (D-040).
  static const localInteractionPhrases = StringListSetting(
    'localInteraction.phrases',
    section: 'localInteraction',
    defaultValue: [],
    tidy: true,
    maxItems: localPhraseLimit,
  );

  /// The most phrases kept (D08.2).
  static const int localPhraseLimit = 20;

  /// Local growth (D08.3): watching a room, the first room of the day and
  /// local danmaku earn experience and coins, a little a day (the app's
  /// `LocalCatalog` holds the rules). New in v4: on by default, the
  /// exception D-040 names; off is 3.x's rules (only gifts earn experience,
  /// coins only from the buttons).
  static const localInteractionGrowthEnabled = BoolSetting(
    'localInteraction.growthEnabled',
    section: 'localInteraction',
    defaultValue: true,
  );

  /// What local growth gave today (D08.3), JSON kept by the app
  /// (`LocalGrowthDay`): the local date, the time watched, the experience
  /// from watching and from local danmaku, whether today's check-in was
  /// given. Empty until the first growth; another day's counts read as none.
  /// Synced with the other settings, so a restore or device sync carries
  /// today's limits with the coins and experience.
  static const localInteractionGrowthDay = StringSetting(
    'localInteraction.growthDay',
    section: 'localInteraction',
    defaultValue: '',
  );

  /// Which local gifts show their effect over the picture (D08.5 c2,
  /// "显示本地礼物特效" as three choices): `all` (every gift: a small one
  /// flies over the top, a medium one has the banner, a big one the banner
  /// and a vehicle), `bigOnly` (only the big ones; the others only join the
  /// chat list) or `off`. New in v4: `all`, what the switch on was. 3.x's
  /// [localInteractionEnableGiftEffects] keeps its key and meaning (D-018)
  /// and decides first: the app reads it off as `off`, and stores it with
  /// this one (`off` is off, the others on), so a 3.x install over v4 reads
  /// the same choice.
  static const localInteractionGiftEffectLevel = StringSetting(
    'localInteraction.giftEffectLevel',
    section: 'localInteraction',
    defaultValue: 'all',
    allowed: {'all', 'bigOnly', 'off'},
  );

  /// The local interaction's settings, in 3.x's order.
  static const List<Setting<Object>> localInteraction = [
    localInteractionEnabled,
    localInteractionUserName,
    localInteractionTitle,
    localInteractionShowAsDanmaku,
    localInteractionShowPlatformBadge,
    localInteractionShowLevelBadge,
    localInteractionEnableGiftEffects,
    localInteractionPreviewPlatform,
    localInteractionCoins,
    localInteractionExperience,
    localInteractionHistory,
    localDanmakuPreset,
    localDanmakuColor,
    localDanmakuFontSize,
    localDanmakuSpeed,
    localDanmakuFontWeight,
    localDanmakuShowStroke,
    localDanmakuStrokeWidth,
    localDanmakuPlacement,
    localDanmakuFontFamily,
    localDanmakuItalic,
    localDanmakuOpacity,
    localDanmakuLetterSpacing,
    localDanmakuStrokeColor,
    localDanmakuShowShadow,
    localDanmakuShadowColor,
    localDanmakuShadowBlur,
    localDanmakuShadowOffset,
    localDanmakuFixedDurationMs,
  ];

  // ---- backup (backup_controller.dart:37) ----

  /// Last backup folder (this device).
  static const backupDirectory = StringSetting(
    'backupDirectory',
    section: 'backup',
    defaultValue: '',
    scope: SettingScope.internal,
  );

  /// Uploads a backup to the current WebDAV server while the app runs
  /// (J04.2, V01.9).
  static const webdavAutoBackupEnabled = BoolSetting('webdavAutoBackupEnabled', section: 'backup', defaultValue: false);

  /// Hours between automatic WebDAV backups (J04.2).
  static const webdavAutoBackupHours = IntSetting(
    'webdavAutoBackupHours',
    section: 'backup',
    defaultValue: 24,
    min: 1,
    max: 168,
  );

  /// What an automatic WebDAV backup holds: `all` or `follows` (J04.2).
  static const webdavAutoBackupScope = StringSetting(
    'webdavAutoBackupScope',
    section: 'backup',
    defaultValue: 'all',
    allowed: {'all', 'follows'},
  );

  /// Folder below the WebDAV server's base URL (J04.2).
  static const webdavAutoBackupFolder = StringSetting(
    'webdavAutoBackupFolder',
    section: 'backup',
    defaultValue: 'purelive',
  );

  /// Automatic WebDAV backups kept in [webdavAutoBackupFolder] (J04.2).
  static const webdavAutoBackupKeep = IntSetting(
    'webdavAutoBackupKeep',
    section: 'backup',
    defaultValue: 7,
    min: 1,
    max: 100,
  );

  /// Automatic WebDAV backups include cookies and WebDAV passwords
  /// (J04.2); off by default, as manual backups.
  static const webdavAutoBackupIncludeAccounts = BoolSetting(
    'webdavAutoBackupIncludeAccounts',
    section: 'backup',
    defaultValue: false,
  );

  /// Where update packages are downloaded (3.x `CacheController`'s
  /// `downloadDirectoryPath`); empty is the platform default. A path of this
  /// device, so backups do not carry it.
  static const downloadDirectoryPath = StringSetting(
    'downloadDirectoryPath',
    section: 'cache',
    defaultValue: '',
    scope: SettingScope.internal,
  );

  /// Whether the user answered the download folder prompt (3.x
  /// `CacheController.downloadDirectoryDecisionPrefKey`): with it, an empty
  /// [downloadDirectoryPath] means the default folder without asking.
  static const downloadDirectoryDecisionMade = BoolSetting(
    'downloadDirectoryDecisionMade',
    section: 'cache',
    defaultValue: false,
    scope: SettingScope.internal,
  );

  // ---- log (new; 3.x's switch lasted one session) ----

  /// Write the app log to a file.
  static const enableLocalLog = BoolSetting('enableLocalLog', section: 'log', defaultValue: false);

  /// The lowest level the log keeps: `debug`, `info`, `warning` or `error`.
  static const logLevel = StringSetting(
    'logLevel',
    section: 'log',
    defaultValue: 'info',
    allowed: {'debug', 'info', 'warning', 'error'},
  );

  // ---- accounts, outside the cookie secrets ----

  /// Bilibili user id of the stored cookie (not secret).
  static const bilibiliUid = IntSetting(
    'bilibiliUid',
    section: 'cookie',
    defaultValue: 0,
    scope: SettingScope.internal,
  );

  /// When the Douyu cookie was saved (epoch seconds, 0 = unknown).
  static const douyuCookieSavedAt = IntSetting(
    'douyuCookieSavedAt',
    section: 'cookie',
    defaultValue: 0,
    scope: SettingScope.internal,
  );

  // ---- interface mode (M14.1) ----

  /// New (M14.1): which interface the app shows — `auto` (the TV interface on
  /// an Android TV, the phone/desktop one elsewhere), `phone` or `tv`. Kept
  /// on this device only: a phone's backup must not switch a TV to the phone
  /// interface, so it is never exported (and a settings reset keeps it).
  static const uiMode = StringSetting(
    'uiMode',
    section: 'app',
    defaultValue: 'auto',
    allowed: {'auto', 'phone', 'tv'},
    scope: SettingScope.internal,
  );

  /// New (docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件 c2): the TV interface grows the focused card,
  /// button or tab by 5 %; a slow box can switch it off and keep only the
  /// focus ring.
  static const tvFocusZoom = BoolSetting('tvFocusZoom', section: 'app', defaultValue: true);

  /// The TV side menu always shows its names (A17.2 c2); off, it is a rail
  /// of icons that opens over the page when the focus moves in.
  static const tvMenuAlwaysExpanded = BoolSetting('tvMenuAlwaysExpanded', section: 'app', defaultValue: false);

  /// The TV home's mode (A17.2 X1): `live` or `video` (A17.6).
  static const tvMode = StringSetting('tvMode', section: 'app', defaultValue: 'live');

  /// The order of the TV side menu's entries (A17.9 c11; pane names): these
  /// first, the rest in the default order. Empty: the default order.
  static const tvMenuOrder = StringListSetting('tvMenuOrder', section: 'app', defaultValue: []);

  /// The TV side menu's entries hidden (A17.9 c11; pane names); at least
  /// one stays shown.
  static const tvMenuHidden = StringListSetting('tvMenuHidden', section: 'app', defaultValue: []);

  /// The TV side menu's own icons (A17.9-31; `pane:icon` pairs); the others
  /// keep their default icon.
  static const tvMenuIcons = StringListSetting('tvMenuIcons', section: 'app', defaultValue: []);

  /// The TV interface's background (A17.8 h1): `none` (the theme's plain
  /// colour), `color`, `gradient`, `image` or `video`.
  static const tvWallpaperKind = StringSetting('tvWallpaperKind', section: 'app', defaultValue: 'none');

  /// What [tvWallpaperKind] shows: a colour (`AARRGGBB`), a gradient's name,
  /// or the file of the picture (blurred already) or video.
  static const tvWallpaperValue = StringSetting('tvWallpaperValue', section: 'app', defaultValue: '');

  /// Where the picture or video came from (its address), so the grids can
  /// mark "✓ 当前", and the file the blur starts from.
  static const tvWallpaperSource = StringSetting('tvWallpaperSource', section: 'app', defaultValue: '');

  /// How the background fills the screen (A17.8 h1; `BoxFit` names; pure_live_TV `cover`).
  static const tvWallpaperFit = StringSetting('tvWallpaperFit', section: 'app', defaultValue: 'cover');

  /// The dark veil over the background, 0 to 1 (pure_live_TV 0.35).
  static const tvWallpaperMask = DoubleSetting('tvWallpaperMask', section: 'app', defaultValue: 0.35, min: 0, max: 1);

  /// The blur of a picture background (sigma; 0 is none), applied once when
  /// it is set (A17.8 h7).
  static const tvWallpaperBlur = DoubleSetting('tvWallpaperBlur', section: 'app', defaultValue: 0, min: 0, max: 48);

  // ---- music mode (A17.7) ----

  /// New (A17.7, pure_live_TV `musicDefaultPlayMode`): how the music queue
  /// moves on — `sequence`, `repeatOne` or `shuffle` (live_vod `PlayMode`
  /// names; the TV client stored `sequence`/`loopOne`/`random`).
  static const musicPlayMode = StringSetting(
    'musicPlayMode',
    section: 'music',
    defaultValue: 'sequence',
    allowed: {'sequence', 'repeatOne', 'shuffle'},
  );

  /// New (A17.7, pure_live_TV `musicDefaultAudioOnly`): music plays the
  /// audio only (cover and lyrics on screen); off shows the video picture.
  static const musicAudioOnly = BoolSetting('musicAudioOnly', section: 'music', defaultValue: true);

  /// New (A17.7, pure_live_TV `musicResumeOnOpen`): opening music mode
  /// restores the last queue at the last position.
  static const musicResumeOnOpen = BoolSetting('musicResumeOnOpen', section: 'music', defaultValue: false);

  /// New (A17.7, pure_live_TV `musicPlayerProgressBar`): a thin progress
  /// line along the bottom of the player while its controls are hidden.
  static const musicProgressLine = BoolSetting('musicProgressLine', section: 'music', defaultValue: true);

  /// New (A17.7): prefer the Hi-Res (FLAC) audio when the account gets it.
  static const musicLossless = BoolSetting('musicLossless', section: 'music', defaultValue: false);

  /// New (A17.7): the audio cache's size limit in MiB (0 turns caching off;
  /// a TV box has little storage).
  static const musicCacheLimitMb = IntSetting(
    'musicCacheLimitMb',
    section: 'music',
    defaultValue: 1024,
    min: 0,
    max: 20480,
  );

  /// New (A17.7): the third-party service addresses of music mode (playlist
  /// mirrors, lyric services; live_vod `ThirdPartyEndpoints.toJson`); empty
  /// keeps every default.
  static const musicThirdPartyEndpoints = JsonSetting('musicThirdPartyEndpoints', section: 'music', defaultValue: {});

  // ---- internal ----

  /// The LAN-sync device id 3.x generated (remote_sync_service.dart:134).
  static const remoteSyncDeviceId = StringSetting(
    'remote_sync_device_id',
    section: 'meta',
    defaultValue: '',
    scope: SettingScope.internal,
  );

  /// Every setting, in registry order.
  static const List<Setting<Object>> all = [
    autoRefreshTime,
    enableDenseFavorites,
    enableBackgroundPlay,
    desktopPauseWhenMinimized,
    backgroundAudioOnly,
    backgroundPauseDanmaku,
    pauseOnPipClose,
    enableAsmrSleepMode,
    asmrSleepMinutes,
    enableRotateScreen,
    enableScreenKeepOn,
    enableAutoCheckUpdate,
    useGitHubOriginForUpdates,
    skippedUpdateVersion,
    enableFullScreenDefault,
    autoSwitchLiveFollows,
    multiviewMixAudio,
    showSplashPage,
    refreshRateMode,
    matchVideoFrameRate,
    preferRealOnlineCounts,
    realOnlinePlatforms,
    savedMenuIds,
    enableMultiView,
    enableNewWindowPlay,
    showMenuBarIcon,
    showUnplayableInDiscover,
    detectClipboardRooms,
    douyuForceRenew,
    twitchLanguages,
    hotAreasList,
    preferPlatform,
    historyLimit,
    themeMode,
    enableDynamicTheme,
    liquidGlass,
    homeBottomBarOnWide,
    homeBottomBarCompact,
    homeNavigationAutoHide,
    mobileNavigationLabels,
    desktopNavigationLabels,
    liquidGlassFrost,
    themeColorSwitch,
    pureBlackTheme,
    themeColorMigration,
    language,
    crossAxisSpacing,
    mainAxisSpacing,
    loadingStyle,
    loadingStyleColorSwitch,
    textScaleFactor,
    fontSizeBodySmall,
    fontSizeBodyMedium,
    fontSizeBodyLarge,
    fontSizeTitleMedium,
    fontSizeTitleLarge,
    fontFamilyName,
    fontFamilyFileName,
    danmakuFontFamilyFileName,
    videoFitIndex,
    videoPlayerKey,
    preferResolution,
    preferResolutionCellular,
    enableCodec,
    preferH264,
    bilibiliPreferRaw,
    playerCompatMode,
    customPlayerOutput,
    videoOutputDriver,
    audioOutputDriver,
    videoHardwareDecoder,
    floatPlay,
    floatWindowSize,
    floatWindowLandscapeScale,
    floatWindowPortraitScale,
    floatWindowPosition,
    windowsPipAlwaysOnTop,
    autoPipOnLeave,
    useSystemPip,
    floatOverlayTipShown,
    enableRtxVsr,
    useHardStopOnExit,
    enablePortraitStreamAdaptation,
    portraitAdaptiveHeight,
    portraitLayoutMode,
    portraitFullscreenPolicy,
    portraitFullscreenDisplayMode,
    portraitPipFollowSource,
    portraitDanmakuMode,
    rememberPortraitRoomOverride,
    portraitFullscreenSwipeSwitch,
    showPortraitDiagnostics,
    portraitRoomOverrides,
    livePlayChatCollapsed,
    roomSwitcherLayout,
    hideDanmaku,
    noEmojiMode,
    danmakuTopArea,
    danmakuArea,
    danmakuBottomArea,
    danmakuSpeed,
    danmakuFontSize,
    danmakuFontWeight,
    danmakuFontBorder,
    danmakuOpacity,
    enableDanmakuDisplay,
    enableDanmakuStroke,
    danmakuListStyle,
    danmakuListFontSize,
    danmakuListLineSpacing,
    showChatGifts,
    chatGiftsAboveTier,
    giftValueInYuan,
    danmakuShowGifts,
    superChatIncludesMembership,
    showFullscreenSuperChat,
    showChatNames,
    danmakuPausedBehavior,
    danmakuFps,
    danmakuAutoFps,
    danmakuMaxVisibleCount,
    enableDanmakuTapInteraction,
    enableDanmakuLongPressInteraction,
    holdDanmakuOnPress,
    collapseRepeatedDanmaku,
    repeatedDanmakuWindowSeconds,
    savedDanmakuTemplate,
    danmakuFontFamilyName,
    enablePipDanmaku,
    pipDanmakuAutoScale,
    pipDanmakuNoEmojiMode,
    pipDanmakuUseOriginalColor,
    pipDanmakuColor,
    pipDanmakuFontSize,
    pipDanmakuFontWeight,
    pipDanmakuSpeed,
    pipDanmakuOpacity,
    pipDanmakuArea,
    pipDanmakuMaxVisibleCount,
    pipDanmakuEmitInterval,
    pipDanmakuFps,
    pipDanmakuAutoFps,
    filterDouyuSuspectedAutomatedMessages,
    enableDanmakuSimilarityFilter,
    danmakuSimilarityThreshold,
    danmakuSimilarityCacheDuration,
    danmakuSimilarityMaxCacheSize,
    blockEmoteOnlyDanmaku,
    blockLongDanmaku,
    blockLongDanmakuLength,
    youtubeShowAllChat,
    defaultMobileVolume,
    defaultDesktopVolume,
    volumeBoostDb,
    globalVolumeMute,
    roomVolumes,
    roomVolumeGains,
    playbackHud,
    customBackground,
    screenCaptureHint,
    allowAudioMixing,
    roomCardMobilePreset,
    roomCardDesktopPreset,
    roomCardMobileConfig,
    roomCardDesktopConfig,
    roomCardSize,
    pageShowSizeSelector,
    pageShowGotoButton,
    pageShowScrollTop,
    pageDefaultSize,
    pageSizeOptions,
    autoRefreshFavorite,
    refreshFavoriteOnResume,
    autoRefreshInterval,
    maxConcurrentRefresh,
    liveAlertEnabled,
    liveAlertTagIds,
    liveAlertRoomKeys,
    liveAlertBackground,
    autoRefreshThumbnails,
    thumbnailRefreshInterval,
    selectedSourceName,
    selectedSourceId,
    isAutoSyncEnabled,
    autoSyncHoursInterval,
    customIptvUserAgent,
    m3uDirectory,
    iptvPopularPlaylist,
    iptvHotRemoved,
    enableProxy,
    proxyHost,
    proxyPort,
    enableAppProxy,
    appProxyHost,
    appProxyPort,
    rememberWindowGeometry,
    windowWidth,
    windowHeight,
    rememberPipPosition,
    windowsPipDisplayId,
    windowsPipWidth,
    windowsPipHeight,
    windowsPipX,
    windowsPipY,
    dontAskExit,
    exitChoose,
    autoShutDownTime,
    enableAutoShutDownTime,
    enableStartUp,
    ...recorder,
    ...localInteraction,
    localInteractionReplayOnEnter,
    localInteractionPhrases,
    localInteractionGrowthEnabled,
    localInteractionGrowthDay,
    localInteractionGiftEffectLevel,
    backupDirectory,
    webdavAutoBackupEnabled,
    webdavAutoBackupHours,
    webdavAutoBackupScope,
    webdavAutoBackupFolder,
    webdavAutoBackupKeep,
    webdavAutoBackupIncludeAccounts,
    downloadDirectoryPath,
    downloadDirectoryDecisionMade,
    enableLocalLog,
    logLevel,
    bilibiliUid,
    douyuCookieSavedAt,
    remoteSyncDeviceId,
    uiMode,
    tvFocusZoom,
    tvMenuAlwaysExpanded,
    tvMode,
    tvMenuOrder,
    tvMenuHidden,
    tvMenuIcons,
    tvWallpaperKind,
    tvWallpaperValue,
    tvWallpaperSource,
    tvWallpaperFit,
    tvWallpaperMask,
    tvWallpaperBlur,
    musicPlayMode,
    musicAudioOnly,
    musicResumeOnOpen,
    musicProgressLine,
    musicLossless,
    musicCacheLimitMb,
    musicThirdPartyEndpoints,
  ];

  static final Map<String, Setting<Object>> _byKey = {for (final setting in all) setting.key: setting};

  /// The setting stored under [key], if any.
  static Setting<Object>? byKey(String key) => _byKey[key];
}
