# A07.46 画质线路移入画面开关（接 A07.44）

用户要求：原画（画质）和线路不再只在全屏时进入直播画面；增加一个设置，控制是否永久把它们放进直播画面。设置位于「播放 → 视频 → 播放行为设置」，默认关闭。

关闭（默认）时行为与升级前完全一致，因此老用户的界面不变。开启后：

| 布局 | 设置关（默认） | 设置开 |
|---|---|---|
| 手机竖屏 `_phone` | 弹幕栏上方信息条 | 播放器下栏；信息条只剩人数/时长 |
| 竖屏流面板 `_portraitPanel` | 弹幕栏上方信息条 | 播放器下栏 |
| 宽屏，底栏开 | 视频下方底栏 | 播放器下栏；底栏只剩人数/时长 |
| 宽屏，底栏关 | 弹幕栏上方信息条 | 播放器下栏 |
| 宽屏，聊天栏折叠 | 下栏（原有兜底） | 下栏 |
| 手机横屏 `_phoneLandscape` | 下栏（本来如此） | 下栏 |
| 全屏（三种排法） | 下栏（本来如此） | 下栏 |
| 回放 | `RoomReplayInfo`；手机横屏下栏 | 下栏；信息条只剩回放操作 |
| IPTV / PiP / TV / 多画面 | 不变 | 不变 |

## 实现

- 新设置 `Settings.livePlayPickersInVideo`（`packages/live_store/lib/src/settings/settings.dart`，默认 false），设置页条目 `live_play_pickers_in_video` 在 `playback_behavior_settings` 组、宽屏底栏开关之后。
- `live_play_page.dart` 的 `_LayoutSettings` 读取设置；三个 inline 布局的 `pickersInBar` 跟随设置，手机横屏保持 true。
- `RoomInfoBar` / `RoomReplayInfo` 新增 `showPickers`（默认 true），设置开启时关掉信息条和回放条里的画质线路。
- 回放传输条的 `immersive` 改由显式 `replayActionsInBar` 决定：手机横屏、宽屏聊天栏折叠时在传输条显示回放操作；宽屏展开时仍只在回放信息条，避免重复。

## 已知代价

手机竖屏/竖屏流打开设置后，下栏多了两颗 chip，窄屏（约 400 及以下）需要横向滚动控制条；原画/线路在右组最前，方向按钮可能被挤出可视区。沿用 `_InlineRow` 既有的横向滚动策略，不改两行控制条（会牵动遮罩、回放进度条和提示位置）。

## 验证

自动测试见 `apps/pure_live/test/features/live_play/live_play_layouts_test.dart` 的 A07.46 用例（手机竖屏、宽屏底栏开/关、运行时切换）。按用户要求不在本机跑测试，由 GitHub Actions `.github/workflows/test.yml`（workflow `Test`）跑定向测试和完整门禁；真机项待维护者验证。
