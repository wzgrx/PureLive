# A07.44 宽屏视频底栏改为开关（接 A07.41）

> A07.46 之后，画质和线路由新设置 `livePlayPickersInVideo` 控制宿主；本任务的底栏只管人数和时长。

5.6.3（A07.41，`bd781917`）按 issue #180 做了两件事：宽屏的分栏边界修复和横屏设备的视频下方底栏。第二件是硬编码的——只要不是回放就画底栏，弹幕窗上方的信息条只剩标题。用户随后要求这一项可配置：既可以保留底栏，也可以没有底栏，人数、时长、画质、线路回到之前在弹幕窗口上方的位置（3.x 和 5.6.2 的老位置）。

现状（`apps/pure_live/lib/features/live_play/live_play_page.dart`）：`_wide` 把 `picture` 组成 `Column[Expanded(video), 底栏]`，底栏是 `Material(key: 'live-play-wide-footer')` 包一个 `showTitle: false` 的 `RoomInfoBar`，聊天栏则用 `_chatColumn(..., figuresBelowVideo: true)` 关掉自己那份人数行。`RoomInfoBar` 的 `showTitle`/`showFigures`（`layout/room_info_bar.dart:36-37`）本来就是为分工设计的，所以界面组件不用改，只需要把这个选择接到设置上。

## 确认的改动

| 编号 | 类型 | 内容 |
|---|---|---|
| c1 | 增强 | 新设置 `livePlayWideFooter`（`Settings`，分节 `player`），默认开＝5.6.3 的视频下方底栏；设置页落在播放 → 播放行为设置，紧跟竖屏设置之后，图标复用 `AppIcons.homeBottomBar` |
| c2 | 修改 | 底栏只在开着时存在；关掉后 `picture` 只剩画面区，`_chatColumn` 的 `figuresBelowVideo` 改为跟随设置，人数行回到弹幕窗上方。`live-play-audience-row` 任一时刻全树只有一份 |
| c3 | 增强 | 关掉底栏且聊天栏折叠时，画质和线路挪进播放器控制条（沿用 `_phoneLandscape` 的 `pickersInBar`，`player_controls.dart:763`） |
| c4 | 保留 | #180 第一件（`SizedBox.expand` 让视口贴着分栏线、收放把手吸附聊天栏）不受开关影响，两种形态都成立 |

回放那边底栏始终不出现：`_infoBar`（`live_play_page.dart:1497`）对 archive 直接返回 `RoomReplayInfo`，底栏原本也由 `isArchive` 抑制，所以 `isArchive` 的监听保留、没有换成普通 `if`。展开聊天栏时两种设置下的回放界面相同；关掉底栏又折叠聊天栏时，回放和直播一样由控制条兜住画质和线路，此时回放进度条进入沉浸式（`player_view.dart:1089`），与手机横屏的做法一致。

## 已知代价

关掉底栏并把聊天栏折叠时，人数和时长在被折叠的聊天栏里，屏幕上看不到（c3 只兜住了可操作的画质和线路）。这正是 #180 当初要底栏的理由，也是默认保持开启的原因。

## 验证

自动测试见 `apps/pure_live/test/features/live_play/live_play_layouts_test.dart` 的 A07.44 用例（宽扁 1600×500、iPad 1180×820、折叠聊天、改设置即时生效、竖屏流）；真机项见 record.md。本轮按用户指示未跑门禁与测试，正确性待 GitHub Actions 侧验证。
