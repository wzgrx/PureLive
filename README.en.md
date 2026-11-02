<p align="center">
  <img src="docs/Y-发布和运营/Y03-发布说明和README/readme/banner-en.jpg" alt="Pure Live" width="100%">
</p>

<h1 align="center">Pure Live</h1>

<p align="center"><a href="README.md">简体中文</a> · <b>English</b></p>

<p align="center">
  34 live-streaming platforms and IPTV in one app.<br>
  Danmaku (bullet chat), recording, multiview, floating window and background play. No sign-up, no ads, free and open source.
</p>

<p align="center">
  <a href="https://github.com/wzgrx/PureLive/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/wzgrx/PureLive?label=release&color=2e6fe0"></a>
  <a href="https://github.com/wzgrx/PureLive/releases"><img alt="Downloads" src="https://img.shields.io/github/downloads/wzgrx/PureLive/total?label=downloads&color=2e6fe0"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/wzgrx/PureLive?label=license&color=555"></a>
</p>

<p align="center">
  <a href="https://github.com/wzgrx/PureLive/releases/latest"><b>Download 5.6.1</b></a>
  &nbsp;·&nbsp; <a href="docs/Y-发布和运营/Y03-发布说明和README/releases/5.6.1.md">Release notes (Chinese)</a>
  &nbsp;·&nbsp; <a href="#features">Features</a>
  &nbsp;·&nbsp; <a href="#supported-platforms">Platforms</a>
  &nbsp;·&nbsp; <a href="#building-from-source">Build</a>
  &nbsp;·&nbsp; <a href="#roadmap">Roadmap</a>
</p>

---

Pure Live (纯粹直播) is a third-party live-stream aggregator. It brings Chinese platforms such as Bilibili, Douyu, Huya, Douyin and Kuaishou together with international ones such as Twitch, YouTube and SOOP, plus the IPTV channels you import yourself. Follows, danmaku, recording and multiview all live in one place, so you don't need a separate app for every platform.

**5.0 was the first release for every platform.** Since 4.0 the network layer, platform adapters, danmaku, playback, recording, storage and every screen have been rewritten (features are based on 3.x, playback is mpv only). 5.0 ships **Android phones and tablets, Android TV, Windows and Linux** from one codebase and one design. You can install over 3.x and 4.x and keep your follows, settings and history. 5.1 added video (Bilibili VOD), music, wallpapers and TV-style settings to the TV interface, and per-streamer live alerts. 5.2 was about smoothness: no more stutter the first time you open a platform or a room, damped overscroll on every list and pager, spring page transitions, and a liquid-glass bottom bar on the home screen. 5.3 adds official sign-in for Douyu, Huya, Douyin, Kuaishou, YY, NetEase CC, Twitch and SOOP: the platform's own sign-in page opens in the app and the login is saved automatically. 5.4 adds Traditional Chinese and twelve more interface languages (Japanese, Korean, Spanish, French, German, Portuguese, Russian, Italian, Vietnamese, Thai, Indonesian and Turkish) and a volume boost. 5.4.1 fixes the Linux build not starting and is the first 5.x release for macOS, iOS and iPadOS (built on GitHub's macOS runners, not signed by Apple). 5.4.2 rebuilds the mini window: the same window inside the app and over other apps, movable anywhere, tucked into a side, resized steplessly; the Mac gets its own title bar, menu bar and menu bar icon. 5.4.3 lets iPhones and iPads share rooms in from other apps, keeps playing in the background and on the lock screen with Now Playing, and lists the iPad's ⌘ shortcuts when you hold ⌘. 5.4.4 fixes live alerts that could be missed when the background check ran. 5.4.5 reworks the feel of the glass bottom bar: a pill at rest that turns into a glass lens when pressed or dragged, with spring motion throughout; tablets can keep the bottom bar too. 5.4.6 lets Popular → Network switch between the built-in list and your own imported IPTV playlists. 5.4.7 lets a TV remote reach the buttons of every dialog, brings the glass bottom bar down to the iPhone's home indicator with an optional compact bar, and marks followed rooms with a small heart in browse lists.

5.4.8 adds current-room Super Chat history and fixes TV focus, links without a scheme and automatic-recording toggles. 5.4.9 adds multiview mute, TV preferred-platform selection and a fullscreen Super Chat entry, with iPad volume/brightness gestures and screen-wake recovery fixes. Verification on the reported physical devices remains pending; see the release notes.

5.4.24 delivers all nine requests together: anonymous live updates and schedules, linked displays, paired LAN controls, landscape gestures, room gain, Douyu VOD, Android audio coexistence, TV titles and two-refresh recovery. It also fixes native player queue isolation and projection room/fullscreen lifecycles. Original-device intermittent reports remain open.

5.4.26 integrates reviewed draft designs: desktop minimize/restore state, rail scrolling, favorite-area logos, TV settings, and wallpaper resource handoff. The 47 original draft files are preserved; original-device reports were open then and are now deferred and closed under the user decision.

5.6.1 adds compact landscape-fullscreen playback status and an opt-in line-details setting, disabled by default. It integrates custom backgrounds, Huya archives and medals, TV navigation, Kuaishou links and browser screen-connection fixes. Ten same-source installers are verified; unresolved original-device and account reports remain tracked.

5.5.0 adds a configurable playback HUD, app navigation and focused text input over LAN, consent-based screen viewing/mirroring, and browser PNG/video export. It fixes the followed-area entry, TV focus, six desktop settings layouts and startup window policy; improves cooperative Windows uninstall and room-scoped public Douyu recovery; and adds an opt-in Bilibili Raw candidate mode. #131 and #135 await original-scenario confirmation; the three deferred device reports remain deferred.

5.4.25 isolates timed-out player creation and unfinished stops, fixes the Windows startup restoration race, and adds fixed-phase native diagnostics without media addresses. Original Huawei/Sony/Honor and GTX760 reports remain open for device confirmation.

5.4.21 adds phone QR input to TV link playback, prevents horizontal swipes from changing brightness or volume, and keeps home jump buttons clear of the glass navigation bar. Douyu VIP counts remain separate from real viewer counts and rankings and are cleared when the broadcast ends.

5.4.20 adds opt-in simultaneous multiview audio with independent volumes and probes available Weibo stream qualities. It removes the persistent EPG selection outline and enlarges TV room-list and anchor text. Additional diagnostics support investigation of cross-platform playback stalls on older Android devices; affected-device reports remain open.

5.4.19 adds opt-in automatic switching among followed live rooms and recording controls in multiview. It fixes IPTV initialization, TV statistics/focus/backup menus, category browsing and iOS back navigation. Danmaku size now reaches 60; Douyu VIP-count notifications have a separate switch. Windows middle-click toggles system fullscreen. Update packages include exact sizes and SHA-256 checks.

5.4.18 fixes Super Chat event deduplication and unread badges, storage errors incorrectly triggering recording retries, settings navigation and TV focus. It adds platform icons, navigation display options and Windows middle-click fullscreen, and updates the stable toolchains. Reports still needing affected-device verification remain open.

5.4.17 keeps desktop playback running when obscured, adds an opt-in pause-on-minimize setting, and supports right-click in-window fullscreen and mouse Back navigation. Danmaku, controls, and dialogs keep their priority; Back on the home page does not exit.

5.4.16 routes TV log export through the existing phone QR view, keeps five standalone settings pages in the wide content pane, and adds automatic desktop grid capacity and six card sizes. Manual pagination and the phone default layout are preserved.

5.4.15 adds optional foreground WebDAV backup and fixes clipped TV menu focus borders, directional focus on inactive proxy fields, first-load IPTV guide refresh and RTP MPEG-TS playback. Existing focus zoom, navigation and fullscreen behaviour are preserved. Fixed-stage iPhone gesture diagnostics help the reports that still need affected-device checks.

5.4.14 puts room search, follows and history directly below the volume controls in immersive and fullscreen multi-view. Switching targets the selected cell and preserves the other streams and display mode. Short windows with large text can scroll. Two live streams were verified on Windows; reports awaiting affected-device checks remain open.

5.4.13 repairs remote navigation in the TV update dialog and aligns settings focus frames. It also preserves gestures pending native reads and temporarily mitigates observed Mac rendering failures. Wallpaper retries now display loading immediately. Wallhaven connectivity on the reported TV, Huawei Smart Screen playback and affected Douyu accounts remain under investigation.

5.4.12 restores the TV favorites Back levels: cards return to the last filter before the sidebar, preserving platform, state and tag selections, including offline rows and empty lists. Huawei Smart Screen playback and affected Douyu signed-in accounts remain under investigation.

5.4.11 adds a vertical four-view layout with playback-session, audio-selection and layout persistence, plus safe terminal playback diagnostics. Huawei Smart Screen playback and affected Douyu signed-in accounts remain under investigation.

5.4.10 fixes the landscape sidebar, TV settings focus frames and custom Douyin room links, enables KICK on Windows, and adds Douyu chat levels, fan medals and notices with identity-cache and diagnostic corrections. Playback failures on affected signed-in Douyu accounts remain under investigation.

> The app's interface comes in 15 languages: Simplified and Traditional Chinese, English, Japanese, Korean, Spanish, French, German, Portuguese, Russian, Italian, Vietnamese, Thai, Indonesian and Turkish (switch in Settings → Appearance; until you pick one it follows the system). The foreign languages were machine-assisted and not yet reviewed by native speakers; corrections are welcome. Release notes and in-depth docs are written in Chinese.

> Since 5.0.0 the project lives in this standalone repository, [wzgrx/PureLive](https://github.com/wzgrx/PureLive). The old [wzgrx/pure_live](https://github.com/wzgrx/pure_live) (a fork of [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live)) is kept; devices running 3.x or 4.x still get update prompts and download new versions from here.

## Highlights

<table>
  <tr>
    <td width="33%" valign="top">
      <b>34 platforms plus IPTV</b><br>
      18 Chinese and 16 international platforms, plus IPTV channels and EPGs you import, with one follow list, one search and one room design.
    </td>
    <td width="33%" valign="top">
      <b>A redesigned room</b><br>
      Separate layouts for portrait, landscape fullscreen, vertical streams and tablets; loading, offline, restricted and dropped streams all say why and what to do next.
    </td>
    <td width="33%" valign="top">
      <b>Danmaku on 28 platforms</b><br>
      Up from 8 in 3.x. Flying danmaku is timed, so it moves at the same speed on 60 to 144 Hz screens, and shows emote images.
    </td>
  </tr>
  <tr>
    <td valign="top">
      <b>Recording</b><br>
      One tap, or automatically when a streamer goes live. Segmented recording merged into MP4, optionally with danmaku; follow progress or stop from the recording centre or the notification.
    </td>
    <td valign="top">
      <b>Multiview</b><br>
      Four layouts to watch several streams at once; tap a tile to switch audio, and set quality, line and volume per tile.
    </td>
    <td valign="top">
      <b>Floating window, PiP, background play</b><br>
      One mini window inside the app and over other apps: move it anywhere, tuck it into a side, resize it steplessly; or use system picture-in-picture; background play with a media notification, audio-only mode and a sleep timer.
    </td>
  </tr>
  <tr>
    <td valign="top">
      <b>Smooth</b><br>
      mpv for playback; damped overscroll, spring page transitions and a liquid-glass bottom bar; data in SQLite, written row by row.
    </td>
    <td valign="top">
      <b>Your data stays yours</b><br>
      No account, no ads, no analytics. When you do sign in, it's on the platform's own page inside the app; cookies and passwords are encrypted with the system keystore. Backup, WebDAV and LAN sync are up to you.
    </td>
    <td valign="top">
      <b>Seamless upgrade from 3.x</b><br>
      Just install over it: the first launch imports follows, settings, history, groups, blocked words, cookies, recording tasks and IPTV lists.
    </td>
  </tr>
</table>

## Screenshots

> All screenshots are of 5.3.0 on a Xiaomi phone (Android), with the interface in Chinese. Avatars, covers, titles and danmaku are from rooms that were live at the time.

### Home, categories and search

<table>
  <tr>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/home-follow.jpg" width="240" alt="Follows"><br><sub>Follows: live, replay and offline groups, filtered by platform; the bottom bar is liquid glass</sub></td>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/popular.jpg" width="240" alt="Popular"><br><sub>Popular: recommendations per platform, swipe to switch</sub></td>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/popular-dark.jpg" width="240" alt="Dark mode"><br><sub>Dark mode: the same interface in dark colours</sub></td>
  </tr>
  <tr>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/areas.jpg" width="240" alt="Categories"><br><sub>Categories: browse by platform and group, follow a category</sub></td>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/search.jpg" width="240" alt="Search"><br><sub>Search: every platform and IPTV at once, results labelled by platform</sub></td>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/settings.jpg" width="240" alt="Settings"><br><sub>Settings: five groups, searchable by name</sub></td>
  </tr>
</table>

### Live room

<table>
  <tr>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/room-portrait.jpg" width="240" alt="Portrait room"><br><sub>Portrait: video, info row, quality and line, danmaku list</sub></td>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/room-dark.jpg" width="240" alt="Dark room"><br><sub>Dark mode: danmaku list and local danmaku input</sub></td>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/danmaku-settings.jpg" width="240" alt="Danmaku settings"><br><sub>Danmaku settings: presets, display area and style, applied instantly</sub></td>
  </tr>
  <tr>
    <td align="center" colspan="3"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/room-landscape.jpg" width="760" alt="Landscape fullscreen"><br><sub>Landscape fullscreen: flying danmaku, clock and battery, lock, local danmaku, quality and line</sub></td>
  </tr>
</table>

### Multiview, recording and official sign-in

<table>
  <tr>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/multiview.jpg" width="240" alt="Multiview"><br><sub>Multiview: 2×2 layout, tap a tile to switch audio or change channel</sub></td>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/record-panel.jpg" width="240" alt="Recording panel"><br><sub>Recording panel in the room: time, size, bitrate</sub></td>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/recorder.jpg" width="240" alt="Recording centre"><br><sub>Recording centre: filter by state, stop any time</sub></td>
  </tr>
  <tr>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/accounts.jpg" width="240" alt="Platform accounts"><br><sub>Platform accounts: Chinese and international platforms</sub></td>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/official-login.jpg" width="240" alt="Douyu account"><br><sub>The “sign in with Douyu” button on the account page</sub></td>
    <td align="center" width="33%"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/official-login-page.jpg" width="240" alt="Douyu sign-in page"><br><sub>The platform's own sign-in page, saved automatically once signed in</sub></td>
  </tr>
</table>

### TV interface

<table>
  <tr>
    <td align="center" colspan="3"><img src="docs/Y-发布和运营/Y03-发布说明和README/readme/tv-home.jpg" width="760" alt="TV interface"><br><sub>TV interface: remote-control navigation, side rail, follows filtered by platform</sub></td>
  </tr>
</table>

## Features

### Watching

- **Three entry points**: Follows, Popular (recommendations per platform) and Categories; choose which platforms show, their order and the default one.
- **Quality and line**: separate default quality for Wi-Fi and mobile data. Switching quality or line keeps the old picture playing until the new one is ready. If the platform delivers lower quality than you picked, the app tells you.
- **Auto recovery**: reconnects after a dropped stream, refreshing the URL, switching lines or falling back to software decoding as needed; suggests another line if nothing shows after 8 seconds.
- **Clear states**: offline, banned, replay, sign-in required, paid, region-locked and interrupted each come with an explanation and a button. Offline rooms are checked every 60 seconds and start playing when the stream goes live.
- **Gestures**: tap for controls, double-tap for fullscreen; swipe the left half for brightness, the right half for volume; lock in fullscreen, with clock and battery in the top bar.
- **Vertical streams**: taller video, a three-step panel in portrait fullscreen, swipe up to bring the danmaku back; orientation is remembered per room.
- **More**: audio-only, auto sleep (audio-only on entry and a timer), sleep timer, per-room volume, a volume boost (a few dB for streams quieter than the platform app), aspect ratio, keep screen on (optional), DLNA casting, copy stream URL, share room, open in the platform's app or browser; keyboard shortcuts (Space, arrows, R, F, Esc).

### Danmaku

- **28 platforms** with danmaku. The list follows new messages and shows how many arrived while you scrolled up; names and messages are separate, names can be hidden, font size and line spacing are adjustable. Super chats get their own tab on 11 platforms, priced in the platform's unit and removed when they expire.
- **Gifts**: one style for every platform with image, count and value; combos merge into one line; show only valuable gifts, convert value to CNY, or let gifts fly across the video.
- **Flying danmaku**: display area, margins, opacity, speed, size, weight, outline, font and frame rate are all adjustable, plus a text-only mode; three presets and your own.
- **Emotes**: on platforms that have them, emote images appear in the list and in flying danmaku.
- **Filtering**: blocked keywords (regex supported), blocked users, emote-only and overlong messages, merged duplicates, similar-message filtering, and suspected bot filtering on Douyu.
- **Tap a message**: long-press one in the list, or tap / long-press a flying one (enable in danmaku settings) to copy it, block the user or block a keyword; danmaku pauses while the panel is open.
- **Matches your screen**: speed is time-based, the same on 60, 90, 120 and 144 Hz screens; danmaku pauses with the video.

### Local interaction

Send danmaku only you can see, send local gifts and watch their effects, with coins, levels and titles; watching and daily check-ins level you up, quick phrases send with one tap, the log can be reviewed, and your messages come back when you re-enter a room. Profile, coins and log stay on the device and are never sent to any platform.

### Recording

- **Start**: “record now” in the room, or “record when live”: starts when the streamer goes live and stops when they go offline. Choose the quality and optionally save danmaku as a matching `.xml` file (PotPlayer and others can load it).
- **Reliable**: FFmpeg segmented recording merged into one MP4 with progress; reconnects with back-off without losing what was recorded; tasks resume after an app restart.
- **Recording centre**: All, Recording, Waiting, Saved and Failed filters with counts; play, open the folder or record again; failures show the full reason.
- **Notification**: an ongoing notification with streamer and time, “stop recording” and a link to the recording centre; if the system stops it, you're told and the recording is still saved.
- **Storage**: pick the folder and an optional size limit; the oldest recordings are deleted when it's exceeded.

### Follows and live status

- Follows are grouped into live, replay and offline, filterable by platform and by your own tags.
- Live status is checked at launch, then periodically and when returning to the foreground; tap “Follows” again to refresh. Concurrency is capped and slow rooms time out, so the list never hangs.
- With live alerts on, you get a notification when a followed streamer goes live; tap it to enter the room. Alerts can be limited to selected streamers. On Android the system lets the app check about every 15 minutes even after it's been killed (allow autostart on Xiaomi/Redmi).
- To record automatically, turn on “record when live” in the room's recording panel.

### Search and categories

- Search every platform at once or just one; include offline rooms, sort four ways, search rooms or streamers.
- Paste a room link into search to open it; a copied share code prompts you when you return to the app (can be turned off). Sharing a room link to Pure Live from another app opens it directly.
- The search scope is adjustable (e.g. Chinese platforms only). When some platforms fail you can retry or use web search: the platform's page opens in the in-app browser and recognised rooms can be opened.
- Categories by platform and group; followed categories have their own list.

### Multiview

1×1, 1×2, 2×2 and 1+3 layouts, up to 4 tiles on phones. Tap a tile to switch audio or mute all; each tile has its own volume, quality and line, small tiles save data automatically; pick channels from follows, history or search; every tile has danmaku; immersive and fullscreen modes.

### IPTV

- Import M3U and TXT playlists from a URL or a file, and XML, GZ or JSON EPGs; sync on an interval or manually.
- Custom User-Agent and per-channel headers.
- Programme guide in the room; tap a catch-up programme to replay it and return to live any time.
- Share an M3U file from another app, or “open with” Pure Live, to import it.

### TV interface

- The same APK as the phone; on a TV it starts in a remote-control interface. The mode button at the top of the rail switches between Live, Video and Music.
- **Live**: follows, popular (with an all-platforms panel), categories and followed categories, search (rooms or streamers, offline rooms, sorting, type on your phone), history, link playback, IPTV; channel switching, room list and playback settings in the room.
- **Video** (Bilibili VOD, sign-in required): home, categories, movies and series, mine, search, details, anime, uploader pages; the player has danmaku, subtitles, episodes and comments.
- **Music**: playlists (importable from NetEase Cloud Music, Kugou and QQ Music), recommendations, search; the player has scrolling lyrics and a queue, keeps playing when you leave and can be controlled from the notification.
- **Wallpapers**: solid colours, gradients, Bing and Wallhaven images, random, video; adjustable dim and blur.
- **Settings**: a TV-style settings directory; rail entries can be reordered, hidden and given icons; scan a QR code to enter cookies or addresses or view logs on your phone.

### Floating window and picture-in-picture

- **Mini window**: the room's mini window button (or leaving a room with "mini window when leaving the room" on) shrinks the video into a floating window; "back to the room" carries on without reloading. Drag it up to the status bar or down to the gesture bar, it slides to the nearer side; fling it into a side to tuck it away while it keeps playing; resize it steplessly with the bottom-right grip or two fingers; its place and size are kept across restarts. Separate danmaku settings.
- **Over other apps**: with "Display over other apps" allowed, leaving the app keeps the same window on top of other apps, working as it does in the app.
- **System PiP**: with "use system picture-in-picture instead" on, the mini window button and leaving the app use the system's picture-in-picture with play/pause buttons. If the system has disabled PiP for the app, it explains why and opens the right settings page.

### Background play

With background play on, audio continues after you leave the app, with a notification showing title, streamer, cover and pause/stop buttons. The first time, the app explains and then asks for notification permission and to ignore battery optimisation. With it off, playback pauses about 1.5 s after you leave and resumes when you return.

### Backup, WebDAV and device sync

- **Local backup**: full backup (settings, follows, history, groups, blocked words, search history; not account cookies or the WebDAV password) or follows only; preview the changes before restoring. Backups exported by 3.x can be restored too.
- **WebDAV**: back up to your own WebDAV server (e.g. Nutstore), Basic and Digest auth; browse, upload, restore and delete.
- **Device sync**: pair two devices on the same LAN with a QR code and send or receive configuration, choosing what to sync; 3.x devices are discovered too. Syncing account cookies must be turned on manually and is only recommended between trusted devices.

### Accounts

- Bilibili: QR code, web (SMS) sign-in or cookie; remember several accounts and switch with one tap.
- Douyu (auto-renewed), Huya, Douyin, Kuaishou, YY, NetEase CC, Twitch and SOOP: open the platform's own sign-in page in the app (QR code, SMS or password); the login is saved automatically. Cookies can still be entered by hand.
- Signing in can unlock higher quality and rooms that require it (per the platform's rules). It's optional; everything else works without it.

### Appearance

Theme mode (system, light, dark), pure black, theme colour and dynamic colour; a liquid-glass bottom bar on the home screen (edge refraction, the selected item is a glass drop you can hold and drag; can be turned off); damped overscroll on every list and pager and spring page transitions; five font sizes and downloadable fonts; 85 loading animations; which details room cards show and their spacing; which bottom-bar pages show and their order; 15 interface languages (Simplified and Traditional Chinese, English, Japanese, Korean and more; it follows the system until you pick one). Settings are split into Interface, Sources, Playback, General & network and Data, and searchable by name.

### Privacy

- **No data collection**: no account needed; the project collects no data, has no ads, analytics, crash reporting or cloud services (the Google-based cloud account of 3.x is gone). Logs stay on the device and only leave it when you export them in Settings → Log Management.
- **Account data**: follows, history and settings stay on the device. Account cookies and the WebDAV password are encrypted: Android Keystore on Android, per-user DPAPI on Windows. Neither local nor WebDAV backups include them; device sync doesn't either unless you turn on “sync account cookies”. Cookies, tokens, passwords and signatures are stripped from logs.
- **Where the app connects**:
  - The platforms you watch: pages, danmaku, images and streams.
  - Addresses you enter yourself: IPTV playlists and EPGs, WebDAV servers, proxies. Device sync and casting stay on the LAN.
  - GitHub and third-party mirrors: update checks, installer downloads, fonts and Huya's player config are requested from GitHub and a dozen public mirrors (e.g. gh-proxy, kkgithub, jsDelivr) at once, using whichever answers first. Those mirrors are run by third parties and can see your IP and the file requested. With “use the official GitHub update source” on, update checks and installer downloads only contact GitHub (fonts and the Huya config still use mirrors); the automatic update check at launch can be turned off.
  - The project has no server of its own.
- **Proxy**: the app proxy (platform requests, danmaku, images) and the playback proxy (streams) are set separately.
- **Platform samples in the repository**: recorded API samples are only used by automated tests and are scrubbed before commit (client addresses become the documentation range `203.0.113.x`; visitor IDs, device IDs, tokens and cookies become synthetic values of the same shape; no real accounts). The gate's fixture privacy check scans every sample, including Base64, integer forms and danmaku frames, and rejects any address outside the documentation and private ranges.

## Design and performance

Since 4.0 every screen follows the same principles:

- **Keep the 3.x habits**: entry points, gestures, shortcuts and settings remain and 3.x data still applies; every change to look or behaviour was compared and confirmed item by item.
- **One way to do one thing**: one icon, one component and one wording per action; phones and tablets share components, screen size only decides placement.
- **Every state covered**: loading, empty, error, restricted, offline, permission denied, in progress and done all explain the reason and the next step the same way.
- **Follow the window**: layouts use the page's own available width and adapt to rotation, split screen and foldables; grid columns are computed from width.

Performance:

- **mpv only** (our own media_kit fork, libmpv 0.41.0, FFmpeg 9.0.2); switching quality or line doesn't rebuild the player.
- **Refresh rate**: the 3.x power-saving, balanced and performance modes remain; during playback the display rate is matched to the video frame rate, only when the switch is seamless.
- **Danmaku**: layouts are cached as images, the frame rate is an integer fraction of the refresh rate, and the on-screen count is capped; outlines only, no blur shadows.
- **Interface**: state changes rebuild only what uses them, lists are lazy, images are decoded at display size with a capped cache and downloaded on a separate isolate; no blur over video.
- **Motion** (since 5.2): damped overscroll on lists and pagers, spring page transitions with gesture-following back navigation; the home bottom bar is liquid glass, with shader-based edge refraction and a draggable glass drop for the selected item, falling back to frosted glass where shaders aren't supported.
- **Storage**: SQLite (drift), row-level writes in transactions, on a background isolate.

## Supported platforms

**34 live-streaming platforms** plus **IPTV**. The “Search” column says what search can find:

- **Incl. offline**: live and offline rooms; **Live only**: only rooms that are live;
- **Streamers**: can also search by streamer; **By room ID**, **By channel**: no keyword search, only a room ID or channel name; **Filter recommendations**: keyword filter over the platform's recommendations.

### Chinese platforms (18)

| Platform | Play | Danmaku | Search | Categories | Sign-in |
|---|:---:|:---:|---|:---:|---|
| Bilibili 哔哩哔哩 | ✓ | ✓ | Incl. offline, streamers | ✓ | QR code, web, cookie |
| Douyu 斗鱼 | ✓ | ✓ | Incl. offline, streamers | ✓ | Official, cookie (auto-renewed) |
| Huya 虎牙 | ✓ | ✓ | Live only, streamers | ✓ | Official, cookie |
| Douyin 抖音 | ✓ | ✓ | Live only | ✓ | Official, cookie |
| Kuaishou 快手 | ✓ | ✓ | Incl. offline, streamers | ✓ | Official, cookie |
| YY | ✓ | ✓ | Live only, streamers | ✓ | Official, cookie |
| NetEase CC 网易CC | ✓ | — | Incl. offline, streamers | ✓ | Official, cookie |
| AcFun Live | ✓ | ✓ | Incl. offline, streamers | ✓ | — |
| Missevan 猫耳 FM | ✓ | ✓ | Incl. offline | ✓ | — |
| Inke 映客 | ✓ | — | Filter recommendations | ✓ | — |
| KilaKila 克拉克拉 | ✓ | ✓ | Incl. offline | ✓ | — |
| Xiaohongshu 小红书 | ✓ | — | By room ID | — | — |
| Weibo Live 微博直播 | ✓ | — | By room ID | ✓ | — |
| JD Live 京东直播 | ✓ | ✓ | Incl. offline | ✓ | — |
| Kugou Live 酷狗直播 | ✓ | ✓ | Incl. offline | ✓ | — |
| Baidu Live 百度直播 | ✓ | ✓ | By room ID | ✓ | — |
| 6.cn 六间房直播 | ✓ | ✓ | Incl. offline | ✓ | — |
| LOOK Live LOOK 直播 | ✓ | ✓ | By room ID | ✓ | — |

### International platforms (16)

Accessing international platforms from mainland China usually needs a proxy, which can be set in Settings → Custom network proxy.

| Platform | Play | Danmaku | Search | Categories | Sign-in |
|---|:---:|:---:|---|:---:|---|
| Twitch | ✓ | ✓ | Incl. offline | ✓ | Official, cookie |
| SOOP | ✓ | ✓ | Live only | ✓ | Official, cookie |
| YouTube Live | ✓ | ✓ | Live only | — | — |
| TikTok LIVE | ✓ | — | By channel | — | — |
| Kick | ✓ | ✓ | Incl. offline | ✓ | — |
| niconico | ✓ | ✓ | Live only | ✓ | — |
| SHOWROOM | ✓ | ✓ | Live only | ✓ | — |
| TwitCasting | ✓ | ✓ | Live only | ✓ | — |
| CHZZK | ✓ | ✓ | Incl. offline | ✓ | — |
| PandaTV | ✓ | ✓ | Incl. offline | ✓ | — |
| Picarto | ✓ | ✓ | Incl. offline | ✓ | — |
| Bigo Live | ✓ | ✓ | Filter recommendations | ✓ | — |
| LiveMe | ✓ | — | Incl. offline | — | — |
| FC2 Live | ✓ | ✓ | Incl. offline | ✓ | — |
| Steam Broadcasts | ✓ | ✓ | Incl. offline | ✓ | — |
| 17LIVE | ✓ | ✓ | Live only | ✓ | — |

### IPTV

| Source | Play | Danmaku | Search | Categories | Sign-in |
|---|:---:|:---:|---|:---:|---|
| IPTV | ✓ | — | Local channels | Playlist groups | — |

Platforms without danmaku either have no public chat API or require sign-in or signatures; Xiaohongshu and Weibo Live can only follow a single broadcast, not a streamer. Platform APIs change often; if something stops working, please report it in [Issues](https://github.com/wzgrx/PureLive/issues).

## Download and install

Download the package for your platform from [Releases](https://github.com/wzgrx/PureLive/releases/latest).

| Platform | Requirements | Package |
|---|---|---|
| **Android phones and tablets** | Android 8.0+ | `…-android-arm64-v8a-release.apk` (almost every device; pick this if unsure); `armeabi-v7a` for old 32-bit devices, `x86_64` for emulators |
| **Android TV and TV boxes** | Android 8.0+ | The same APK as the phone: it starts in the TV interface on a TV (switch in Settings → Appearance → Interface mode) |
| **Windows** | Windows 10, 11 (64-bit) | `…-windows-x64-setup.exe` (installer) or `…-windows-x64-portable.zip` (portable, data in `UserData` next to the program) |
| **Linux** | x86_64, GTK 3 desktop | `…-linux-x64.tar.gz`: extract and run `pure_live`; the README.txt inside explains adding it to the app menu |
| **macOS** | macOS 12+, Intel and Apple silicon | `…-macos-universal.dmg`: open it and drag PureLive into Applications. It is not signed by Apple: if macOS cannot verify the developer the first time, click “Open Anyway” in System Settings → Privacy & Security |
| **iPhone, iPad** | iOS, iPadOS 15+ | `…-ios-unsigned.ipa` with AltStore or SideStore (signed with your own Apple ID; a free account renews every 7 days); `…-ios-trollstore.ipa` on devices with TrollStore (TrollStore also installs it on iOS 14 and earlier, but it will not open there: Flutter, the framework, needs iOS 15) |

- If Android says “install unknown apps”, allow your browser or file manager in the settings it opens.
- The Linux build has no in-app web sign-in (official sign-in, Bilibili web sign-in): enter a cookie, or sign in on a phone or Windows and bring the account over with device sync.

### Upgrading from 3.x or 4.x

- **Install over the old version, don't uninstall first**: uninstalling deletes your data. The Windows installer installs into the existing folder.
- From 3.x, the first launch imports settings, follows (including followed categories), history, groups, blocked words, account cookies, WebDAV settings, recording tasks and IPTV lists. The import only reads 3.x files; it never changes or deletes them.
- To be safe, make a full backup in 3.x's “Backup & restore” first; the new version can restore 3.x backups directly.

## Building from source

You need Flutter on Linux or Windows. Toolchain versions are pinned in [`toolchain.env`](toolchain.env) (Flutter 3.47.8, Dart 3.13.7, Gradle 9.8.2, AGP 9.4.1, Kotlin 2.4.21, JDK 27, Android SDK 37.2, build-tools 37.0.0, platform-tools 37.0.1, cmdline-tools 23.0, NDK 30.0.16248370, CMake 4.1.2); upgrade them there only (the Android build reads compileSdk, build-tools, NDK and CMake from it).

```bash
git clone https://github.com/wzgrx/PureLive.git
cd PureLive

# 1. Environment: install the toolchain from toolchain.env and source an env script before each build
#    (example paths, use your own)
export FLUTTER_ROOT="$HOME/tools/flutter-sdk/3.47.8"
export JAVA_HOME="$HOME/tools/jdk-27"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$FLUTTER_ROOT/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

# 2. FFmpeg native packages for recording: downloaded once into ~/.cache/pure_live/ffmpeg_kit, offline afterwards
bash tools/ffmpeg_kit/fetch.sh android

# 3. Dependencies: the repository is a pub workspace sharing the root pubspec.lock
flutter pub get

# 4. One APK per CPU architecture
cd apps/pure_live
flutter build apk --release --split-per-abi
```

- Output goes to `apps/pure_live/build/app/outputs/flutter-apk/`, one APK per architecture. The libmpv native packages are downloaded by the build.
- **Windows**: with Flutter, Visual Studio (Desktop development with C++) and NuGet on Windows, run `pwsh tools/release/package_windows.ps1` for the portable ZIP and the Inno Setup 6 installer.
- **Linux**: install `clang cmake ninja-build pkg-config libgtk-3-dev` and run `bash tools/release/package_linux.sh` for `linux-x64.tar.gz`.
- Signing keys are not in the repository: without `apps/pure_live/android/key.properties`, release builds are signed with the debug key.
- Debug and profile builds use the package name suffix `.v4dev` and the name “纯粹直播 v4dev”, so they install alongside the release.
- Run the gate before committing: `bash tools/gate/gate.sh --all` checks formatting, package dependency direction, `dart analyze` and all tests, and must print `gate: passed`. While working on one package, `bash tools/gate/gate.sh` is enough.

## Project structure

The core is pure Dart packages that can be tested on their own; Flutter only appears in the player binding, UI components and the app. Dependencies only point downwards, enforced by the gate.

```text
apps/pure_live          Flutter app: pages, routing, Android/Windows/Linux native code and the TV interface
packages/live_ui        Theme, icons and shared widgets
packages/live_player    Player binding on media_kit (mpv)
packages/live_media     Stream pipeline, local relay, playback recovery
packages/live_record    Recording: FFmpeg segments, merging, resume after disconnects, danmaku XML
packages/live_danmaku   Danmaku connections, decoding and filtering per platform
packages/live_iptv      IPTV: playlist and EPG parsing and sync
packages/live_cast      DLNA casting
packages/live_store     Storage (drift + SQLite), settings, backup, 3.x data migration
packages/live_core      Models, platform interfaces and the 34 platform adapters
packages/live_net       HTTP, WebSocket, proxy and Brotli decoding
packages/live_vod       Bilibili VOD and music core (for the TV video and music modes)
third_party/            Our media_kit fork and a Linux stand-in for flutter_inappwebview
tools/                  Gate, toolchain checks, FFmpeg native packages, mockup tools
docs/                   Plans, module records, UI design and feature inventory (in Chinese)
```

Plans and progress: [docs/PLAN.md](docs/PLAN.md); UI design: [docs/specs/UI.md](docs/specs/UI.md); feature inventory: [docs/inventory/FEATURES.md](docs/inventory/FEATURES.md) (all in Chinese).

## Roadmap

| Client | 5.6.1 (now) | Later |
|---|---|---|
| **Android phones and tablets** | Stable: liquid-glass bottom bar, damped and spring motion, official sign-in for eight platforms, 15 interface languages | Keep up with platform changes |
| **Android TV** | Stable: Live, Video (Bilibili VOD) and Music modes, wallpapers, TV-style settings, type on your phone via QR code | Verify and tune on more TVs |
| **Windows** | Stable: custom title bar, tray, close behaviour, launch at startup, desktop floating window, rooms in new windows, official sign-in, KICK playback and chat | Sustained playback and installer upgrade verification |
| **Linux** | Stable: the same desktop shell as Windows | In-app web sign-in |
| **macOS** | Beta: the Mac's title bar, menu bar and shortcuts, closing the window without quitting, menu bar icon; built on GitHub's macOS runners, not yet used on a real Mac | Recording |
| **iOS, iPadOS** | Beta: the Android interface, ⌘ shortcuts and their list on an iPad keyboard, sharing in from other apps, background and lock-screen playback; unsigned IPA and TrollStore IPA, only opened in the simulator | Stage Manager, system picture-in-picture, recording |

## Feedback and contributing

- Report problems and ideas through one of the [issue forms](https://github.com/wzgrx/PureLive/issues/new/choose): bug report, platform broken, feature request, or translation (English is fine). Version, device and steps to reproduce are required; for playback, crash and platform problems attach the log exported from Settings → Log Management (set the level to Debug first).
- What happens after you submit (labels, response times, what is out of scope, how feature requests are decided) is in [CONTRIBUTING.md](CONTRIBUTING.md) (Chinese).
- Security issues (e.g. anything that could leak accounts or cookies): please don't open a public issue; see [SECURITY.md](SECURITY.md) and report privately via a GitHub [Security Advisory](https://github.com/wzgrx/PureLive/security/advisories/new), visible only to maintainers until fixed.
- Pull requests are welcome; see section 6 of [CONTRIBUTING.md](CONTRIBUTING.md). Please make the gate pass first; code style is very_good_analysis, 120-character lines, and doc comments on public APIs.

## License

Released under the [GNU Affero General Public License v3.0 (AGPL-3.0)](LICENSE). You may use, study, modify and distribute it; if you distribute a modified version, or offer one to others as a network service, you must publish the complete source under the same license and keep the original copyright and license notices. The software comes with no warranty.

Third-party components are used under their own licenses, listed on the app's About page.

This project derives from [liuchuancong/pure_live](https://github.com/liuchuancong/pure_live) (also AGPL-3.0); thanks to the original author and all contributors. Since 5.0.0 development continues in this standalone repository, with history starting at that version; earlier history is kept in [wzgrx/pure_live](https://github.com/wzgrx/pure_live).

## Disclaimer

- Pure Live is only a player. It provides no live content and stores or relays none on any server. Video, danmaku, covers and other content belong to the platforms and streamers.
- Recordings stay on your own device; please use them for personal viewing only and respect the rights of streamers and platforms.
- This project is for learning and technical exchange. Follow the laws where you live and each platform's terms of service, and don't use it to infringe on others' rights.
- Platform names and trademarks belong to their owners; this project is not affiliated with any of them.
