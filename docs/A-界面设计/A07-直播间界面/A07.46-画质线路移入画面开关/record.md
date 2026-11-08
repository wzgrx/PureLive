# A07.46 记录

## 做了什么

| 项 | 结果 |
|---|---|
| 设置 | 新增 `Settings.livePlayPickersInVideo`（默认 false），位于「播放 → 视频 → 播放行为设置」，在宽屏底栏开关之后 |
| 默认行为 | 关闭时 `pickersInBar` 条件保持原样：手机/竖屏流在弹幕栏上方，宽屏底栏或上方，手机横屏/全屏在下栏 |
| 开启行为 | 手机竖屏、竖屏流、宽屏（底栏开/关）都由播放器下栏承载画质线路；`RoomInfoBar`、宽屏底栏、`RoomReplayInfo` 通过 `showPickers: false` 隐藏 |
| 回放 | 新增 `RoomPlayer.replayActionsInBar`，`immersive` 不再依赖 `pickersInBar`；手机横屏 true，宽屏折叠时为 true（设置关时保持 A07.44 的旧条件） |
| 文案 | 新增中英文标题/副标题；宽屏底栏副标题不再承诺画质线路 |

## 测试

- 新增 `live_play_layouts_test.dart` 三例：手机竖屏开启后信息条无 pickers、下栏有，并能运行时切回；宽屏底栏开时底栏只剩人数，pickers 在下栏；宽屏底栏关时仍在下栏。
- 现有用例均按默认关运行，覆盖默认行为不回归。

## 验证方式

按用户要求不在本机运行测试。推送分支后由 GitHub Actions `test.yml`（workflow `Test`）执行定向测试与 `tools/gate/gate.sh --all`；结果以 Action 日志为准。

## 停在哪 / 下一步

- 待 `Test` workflow 通过后合并审查并做真机检查（手机竖屏、竖屏流、手机横屏、宽屏底栏开/关、聊天栏折叠、宽屏回放）。
