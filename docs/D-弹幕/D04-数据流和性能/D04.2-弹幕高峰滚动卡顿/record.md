# D04.2 弹幕高峰滚动卡顿：大帧解码移出界面线程：记录

- 日期：2026-11-09
- 执行者：Qoder（维护者指令：四个平台都接）
- 分支和提交：`ai/D04.2`
- 任务书：[brief.md](brief.md)；诊断和方案：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| c1 卸载机制一份、四平台各包一层 | 做了 | 机制在 `frame_decode.dart`，会话方法 `DanmakuSocketSession.decodeFrame`；B 站、斗鱼、抖音、虎牙的 `onData` 各只改一处 |
| c1a 小帧同步、串行、回退、停止后丢弃 | 做了 | 阈值 8 KiB；另加 `maxBacklogBytes`（16 MiB）上限：解码赶不上到达速度时该帧仍在本 isolate 读，避免等待队列无限增长（这是卸载本身带来的新风险，不改就不会有） |
| c1b 四平台一致性用例 | 做了 | 每平台一条"大帧 + 紧跟一个小帧"用例，断言消息内容、条数、顺序 |
| c2 竖屏层按行缓存 + 按帧合并 | 做了 | `_PortraitLine` 增加 `parts`/`text`/`measured`/`height`；`_take` 不再每条 `setState`，用 `scheduleChatFlushForNextFrame`；本机消息仍立即 |
| c3 表情正则缓存 | 做了 | `_namedPattern` 按（表情表，转义后的码集合）缓存 16 条 |
| c4 飞行流分批 | 不做 | 见 README"方案"最后一条 |

## 根因

见 [README.md](README.md) 的诊断表：渲染器（`shared/danmaku/danmaku_overlay.dart`）不是瓶颈，R01.2 真机 jank 0；卡顿来自界面线程同步解码（`packages/live_net/lib/src/socket.dart:288-294` 内联监听 + `connection_base.dart:24` 同步广播 + `sites/bilibili.dart:500` 纯 Dart brotli、`sites/douyin.dart:158` gzip + 批量 protobuf）、竖屏层每条消息 `setState` 加每帧重新排版（`portrait_chat_overlay.dart` 原 `:102,206-218`）、带表情码消息每条编译 `RegExp`（`emotes.dart` 原 `:192-200`）。

## 改了哪些文件

- 新增 `packages/live_danmaku/lib/src/frame_decode.dart`：`FrameDecode`（阈值门控、每会话串行链、`Isolate.run`、失败回退、积压上限、分发异常交给 zone）。
- `packages/live_danmaku/lib/src/socket_connection.dart`：会话持有一个 `FrameDecode`，新增 `decodeFrame`（带 `run.isActive` 守卫）。
- `sites/bilibili.dart:205-228`、`sites/douyin.dart:548-569`、`sites/huya.dart:388-415`、`sites/douyu.dart:511-536`：`onData` 把"同步解码 + 分发"包进 `decodeFrame`；可变状态（抖音 `broadcast.heard`/礼物门、虎牙 `_superChats`/`_uid`、B 站 `_authReply`）留在分发侧。
- `sites/douyu.dart` 另一处偏差：斗鱼"疑似机器人"设置原来每条疑似消息调一次回调，现在每帧取一次值（回调本身不可发送到别的 isolate），文档注释同步改了。
- `apps/pure_live/lib/shared/danmaku/portrait_chat_overlay.dart`、`emotes.dart`。
- 测试：新增 `packages/live_danmaku/test/frame_decode_test.dart`；`sites/bilibili_test.dart`、`sites/douyin_test.dart`、`huya_test.dart`、`douyu_test.dart` 各加一条大帧用例；`douyu_test.dart` 里"设置读取次数"那条用例的期望从 2 次改成 3 次（每帧一次，见上）；`apps/pure_live/test/shared/portrait_chat_overlay_test.dart`、`emotes_test.dart` 各加用例。

## 新设置、翻译键、门禁基线

- 无。用户可见文字没变，行为除上面写明的一处外没变。

## 测试

- 新增 13 个用例：机制 6（`frame_decode_test.dart`）、四平台一致性各 1（B 站、抖音、虎牙、斗鱼）、竖屏层 2、表情正则缓存 1。改了 1 个既有用例（斗鱼设置读取次数）。
- CI run 42650080380（提交 `51458199`）挂在 `dart format`：`apps/pure_live` 的 `emotes.dart`、`portrait_chat_overlay.dart` 需要重排，后面的 analyze/test/门禁都没跑。
- 本机后来有了 dart 3.13.7（winget 装在 `AppData\Local\Microsoft\WinGet\Packages\Google.DartSDK_…\dart-sdk\bin`，不在会话启动时的 PATH 里）。按仓库的 120 列跑 `dart format --line-length=120`：本任务 15 个 Dart 文件全部通过，其中 9 个被重排；同时发现并修掉抖音新用例里 `[...for …]` 的语法错误（应为 `[for …]`）。提交 `642da1da`，推送后 CI run 42749158530。
- 本机能跑的 Python 门禁全过：`check_deps`（14 个成员 0 错）、`check_fixtures`、`check_ui_structure`、`docs.py --check`、`owners.py --check`。
- `tools/gate/tests`：`test_docs` 8/8 通过；`test_device` 的 14 项在本机失败（adb 与 Windows 路径/引号，既有问题，CI 在 Linux 上跑）。
- Flutter 侧的 `dart analyze --fatal-infos`、`flutter test` 交给 CI（本机没有 Flutter SDK，`dart pub get` 因 `live_ui` 需要 Flutter 而失败）。

## CI 往返（按失败逐项修）

- run 42650080380：`dart format`（两个 app 文件）。→ 用本机 dart 按 120 列重排，修掉 `[...for …]` 语法错误，提交 `642da1da`。
- run 42749158530：Targeted tests 首次通过（format、live_store、app analyze），但停在后来推送前的状态。
- run 42750217814：`Targeted tests` 过；Full gate 报 4 项失败，逐项修：
  - `packages/live_danmaku analyze`：`port.send` 不存在（应 `port.sendPort.send`）、3 个 lint info（`FontWeight.index` 已废弃、级联、`const`）。→ 提交 `77131292`、`6ff1199c`。
  - `packages/live_danmaku test`：抖音突发帧只有 5421 字节，低于 8 KiB 阈值，用例的 `greaterThan(8 * 1024)` 与"走卸载"前提都不成立。→ 批量从 60 条加到 120 条（提交 `5bb95e66`）。
  - `apps/pure_live test`：表情缓存用例的尾段写错，`'a0[0]b'` 去掉表情后是 `'b'`，期望却写了 `'b0'`。→ 提交 `40947fcd`。
  - `docs`：工作区里有一个**空的**同名任务文件夹 `D04.2-弹幕高峰滚动卡顿`（未提交），本地生成时 `find_dir` 选中它（没有文件 → 资料列为 —），CI 上没有它 → 生成结果不同，判"不是最新的"。→ 删掉空文件夹，任务文件夹按标题改名（原来的 `…解码卡顿` 改成 `D04.2-弹幕高峰滚动卡顿`），重新生成，提交 `0829cf62`。
- run 42753511666（提交 `0829cf62`）：**通过**，`gate: passed (all, 14 members)`，含 Targeted tests 和 Full gate（14 个成员的 format、analyze、测试，以及门禁自己的测试）。
- 本机验证手段：把 `live_net`、`live_core`、`live_danmaku` 三个纯 Dart 包复制到临时工作区（外加 `fixtures`），`dart pub get` 后可以真正跑 `dart analyze --fatal-infos` 和 `dart test`；`live_danmaku` 全量 1729+ 用例除 10 个 `exact_websocket_test` 外全过，而那 10 个用 master 的原样代码在同样环境下也失败（`Bad state: the client closed the connection`，Windows 环境问题，Linux CI 上通过）。
- 机制本身另用独立脚本验证：突发帧与后续小帧严格按到达顺序分发、队列排空后小帧恢复同步、不可发送的解码器回退到本 isolate、分发抛错只进 zone 且不影响后续帧。

## 顺手修的两个工程问题（Windows）

- `tools/docs/docs.py` 用 `os.path.relpath` 直接拼 Markdown 链接，在 Windows 上生成反斜杠路径，一次运行就把 130 个生成文档的链接改坏（`A01.1-界面代码搬目录\README.md`）。加 `rel()` 助手统一换成 `/`；问题消息里的 `p.relative_to(ROOT)` 同样改用 `rel()`。重跑后 `--check` 通过，生成差异只剩该变的 5 个文件。
- `tools/gate/tests/test_docs.py` 的子进程用 `text=True` 按本机 GBK 解码 docs.py 的 UTF-8 输出，reader 线程抛 `UnicodeDecodeError`、`stderr` 变成 None，7 个用例报错。补 `encoding='utf-8'` 后 8/8 通过。
- AGENTS.md 现在要求 Windows + `uv`，这两处不修就没法在本机登记任务和跑门禁自己的测试。

## 真机上要看的

- [verify.md](verify.md) 四步：B 站高能时刻的匀速和 P90、抖音突发帧 ack 是否掉线、竖屏刷屏、带表情刷屏。

## 停在哪（没做完时写）

- 做完的阶段：阶段 1、2、3 的代码和测试写完，推送在 `ai/D04.2`，CI 全绿（run 42753511666）。
- 正在做的阶段做到：阶段 4（真机 profile）没开始。
- 已知问题：`Isolate.run` 每条大帧起一个 isolate，若真机显示持续大帧下 spawn 开销明显，改常驻 isolate（理由写在这里）。本机 10 个 `exact_websocket` 用例失败是 Windows 环境问题（master 同样失败）。
- 下一步：按 [verify.md](verify.md) 上 K90（B 站高能时刻、抖音热门房间、竖屏刷屏、表情刷屏），再做第 8 节合并审查。
