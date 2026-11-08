# A07.44 宽屏视频底栏改为开关：记录

- 日期：2026-11-06
- 执行者：Claude（本机工作区，没有推送、没有跑门禁）
- 分支和提交：待建 `ai/A07.44`，提交信息以 `[A07.44]` 开头
- 任务书：无（小任务，见 PROCESS §4）；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 | 做了 | 设置行放在 `portrait` 之后、`audience` 之前；没有加 `when:`，因为 `SettingsEnv`（`settings_model.dart:184`）只有平台没有窗口尺寸，`_desktop` 会把 iPad 和安卓平板一起藏掉，而 #180 说的正是这些设备 |
| c2 | 做了 | 底栏用集合 `if (settings.wideFooter)` 包住原来的 `ListenableSelector`，而不是把条件并进选择器里：这样 `Expanded(child: video)` 的槽位和整棵子树不动，`isArchive` 的监听也保留 |
| c3 | 做了 | 只兜画质和线路；人数和时长仍在被折叠的聊天栏里（README 的已知代价）。兜底条件没有排除回放，因为要读的 `isArchive` 在 `_wide` 这一层不是监听值（会读到过期状态）；回放拿到控制条选择器时进度条转为沉浸式，与手机横屏一致 |
| c4 | 做了 | 无改动，靠新增测试断言把手仍贴着 `live-play-chat-box` 的左边界 |
| 回放对比 | 没做自动化 | 该测试文件没有回放房间的脚手架（`ArchiveRoomArguments` 在本目录的测试里没用过）；展开聊天栏时回放与开关无关，折叠时的差别只有控制条多出的画质/线路，列为真机项 |

## 根因

- 问题：#180 的底栏在 `live_play_page.dart:1840` 的 `picture` 里是无条件渲染的，人数行因此被从弹幕窗上方搬走且不可回退；用户要求可配置。

## 改了哪些文件

- `packages/live_store/lib/src/settings/settings.dart`：新增 `livePlayWideFooter`（紧跟 `livePlayChatCollapsed`）并登记进 `Settings.all`
- `packages/live_store/test/settings_defaults_test.dart`：`newInV4` 加一条
- `apps/pure_live/lib/features/live_play/live_play_page.dart`：`_LayoutSettings` 加 `wideFooter`（两处构造点 `:748`、`:1030` 都补，否则记录类型不匹配）；`_wide` 的底栏门、`figuresBelowVideo`、`pickersInBar`；更新 `_wide` 的过期文档注释（原文仍写「居中 16:9 框」）
- `apps/pure_live/lib/features/settings/settings_catalog.dart`：新增开关行
- `apps/pure_live/assets/translations/*.json`：15 个文件各加 2 键
- `docs/inventory/OWNERS.toml` + 重新生成 `OWNERS.md`（设置 304 个）
- `docs/tasks.toml`：A07.44 与反馈行 V02.89
- `apps/pure_live/test/features/live_play/live_play_layouts_test.dart`：新增 6 例

## 新设置、翻译键、门禁基线

- 新设置：`livePlayWideFooter`，分节 `player`，默认 `true`（＝5.6.3 已有的底栏，升级后界面不变）；归属 A07（OWNERS.toml 单独指定）。备份导出和本地配置预览按 `Settings.all` 自动带上，无需另登记。
- 翻译键：`enable_live_play_wide_footer`、`enable_live_play_wide_footer_subtitle`，15 个文件各 2 行（净增 30 行、删除 0 行）；中文说明 33 字（上限 40，`settings_page_test.dart:641`）。繁体两条按仓库既有词（影片、底欄、人數、時長、畫質、線路、關閉）手工补，没有重跑 `tools/i18n/zh_hant.py`：当前 opencc 版本会顺带改写 165 条无关字符串。
- 门禁基线：无改动；本轮未跑门禁（用户指示，验证放 GitHub Actions 侧）。`tools/docs/docs.py` 也没跑——它用 `os.path.relpath`（`docs.py:240`），在 Windows 上会把生成文档的链接写成反斜杠；`STATUS.md`、`TASKS.md` 等生成文件因此还没带 A07.44/V02.89 的行，需要在 Linux 侧生成一次。

## 测试

- 新增 6 例（`live_play_layouts_test.dart` 的 U.2d 组 5 例 + 竖屏组 1 例）：无底栏时 `live-play-wide-footer` 不存在、人数行回到 `live-play-chat-box` 且全树只有一份、把手仍贴分栏线、画面区补上底栏让出的高度；折叠聊天时控制条里有 `live-play-quality`（开着底栏时没有，作对照）；改设置后不重进房间即生效；竖屏流关掉底栏后画面高度回到 744。
- QA 取帧新增 `issue180-footer-off`，与既有 `issue180-wide-short`（开着）成对。
- 现有断言不用改：默认值为开，`:500`、`:514-518`、`:535-538`、`:1001-1003` 和 `room_on_phone_test.dart:184` 编码的就是有底栏形态。
- 全部通过的范围：未运行（本轮只写代码）。

## 真机上要看的

- Windows 与 iPad 横屏：开关开／关各看一次人数、时长、画质、线路的位置，以及画面下缘与把手吸附。
- 开关关掉 + 折叠聊天栏：确认画质和线路在播放器控制条里可用。
- 回放房间：展开聊天栏时两种设置应完全一致（`RoomReplayInfo` 在聊天栏内）；关掉底栏并折叠聊天栏时，确认画质和线路在控制条里可用、进度条的沉浸式样式可以接受。
- 竖屏流（氛围背景）：关掉底栏后画面占满整个画面区。
- 设置页：播放 → 播放行为设置里的新行，大字号和键盘焦点走一遍，搜索「底栏」能找到。

## 停在哪（没做完时写）

- 做完的阶段：实现和回归的代码与文档写入。
- 正在做的阶段做到：门禁、`flutter test`、`dart analyze`、`tools/docs/docs.py` 生成文件都还没跑。
- 已知问题：无（关掉底栏 + 折叠聊天时看不到人数是设计上的取舍，见 README）。
- 下一步：在能跑 Flutter 的环境执行门禁与上述测试，跑 `python3 tools/docs/docs.py` 同步生成文档，再建分支 `ai/A07.44` 提交。

5.6.5审查：默认开保留现有布局；关后选择器回聊天侧，折叠仍可操作。13项界面/回放定向组通过；已人工复核两张生产组件图（合成播放器，非原设备）。S01.3增加有界诊断，未放宽等待条件。

5.6.5+5144 正式交付：源码 `0aa4571a9b6690ce19ba2ee1a989f6860d7f0648`，源 PR [#218](https://github.com/wzgrx/PureLive/pull/218)。全量 all/14 通过；10 个同源安装包及 SHA256SUMS 的本地、草稿摘要和匿名公开下载字节核对一致。旧更新源 PR [#43](https://github.com/wzgrx/pure_live/pull/43)。双源回读以后续发布核对为准。
分层验证和保留问题见 Y01.45。
