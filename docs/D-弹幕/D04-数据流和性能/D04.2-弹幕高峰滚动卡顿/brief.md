# D04.2 弹幕高峰滚动卡顿：大帧解码移出界面线程（B站/斗鱼/抖音/虎牙）：任务书

## 背景

- 来源：用户反馈（2026-11-09）："研究下为什么当弹幕多了的时候，弹幕滚动明显会很卡"，确认为缺陷并要求修复，四个平台（B 站、斗鱼、抖音、虎牙）都接入。
- 现象：热门直播间弹幕密集时飞行弹幕滚动明显顿挫；B 站高能时刻和抖音热门房间最明显。
- 为什么现在做：直播间是最常用页面；D04.1 已消除"每条消息重建整页"，剩下的卡顿来自界面线程上的同步解码。相关决定 D-092（恢复维护者开发）。
- 已经做过的：[D04.1](../D04.1-弹幕性能和可读性/README.md)（每帧最多通知一次、列表反转、重复时间戳不补双步）；[D03.1](../../D03-飞行弹幕引擎/D03.1-飞行弹幕渲染/README.md)（渲染器：一次排版录制 + Picture 缓存）；[R01.2](../../../R-性能和流畅度/R01-基准和测量/README.md)（K90 profile 基准，jank 0）。

## 目标和验收

1. c1：四个平台的 `onData` 不再在界面线程同步解码大帧。卸载机制只有一份（`DanmakuSocketSession.decodeFrame` + `frame_decode.dart`），平台侧只是把现有解码调用包一层。
2. c1a：小帧（小于 8 KiB）且串行链空闲时仍同步解码；同一会话的帧按到达顺序分发，ack 与认证回复相对顺序不变；会话停止后排队帧的分发丢弃；isolate 失败回退同步解码，行为与改之前一致。
3. c1b：四个平台走会话路径解出来的消息，和直接调用各自 `Protocol.decode`/`read` 的结果逐条一致（内容、顺序、条数）。
4. c2：竖屏堆叠层 build 不再对未变的行做 `TextPainter.layout`；每条消息不再各触发一次 `setState`（合并到帧首），本机发送的消息仍然立即出现。
5. c3：带表情码的消息不再每条编译新 `RegExp`；同一（表情表，码集合）第二次解析命中缓存；表情显示不变。
6. 每秒 200 条时 K90 profile 界面线程 P90 ≤3 毫秒（计划书 9.4）；观感上匀速滚动。
7. 不加任何设置项，用户可见文字不变（本任务不新增翻译键）。

## 现状（读代码得出，写文件:行）

- 渲染：`apps/pure_live/lib/shared/danmaku/danmaku_overlay.dart`（`_tick` `:496`、`_enter` `:542`、`_place` `:561`、`_record` `:732`、`_Pictures` `:1112`、`_DanmakuPainter` `:1284`）。
- 传输：`packages/live_net/lib/src/socket.dart:288-294`（监听回调内联）；`packages/live_danmaku/lib/src/socket_connection.dart`（`onData` 声明 `:154`，`DanmakuSocketSession` `:223`，`isActive` `:240`，`send` `:247`，`message` `:265`，socket 回调 `:373-375`）；`connection_base.dart:24`（事件总线 `broadcast(sync: true)`）。
- 四个平台的 `onData`：`sites/bilibili.dart:206-220`（解码 `:441`，brotli `:500`，zlib `:513-519`）、`sites/douyin.dart:550-560`（解码 `:147-192`，gzip `:158`）、`sites/huya.dart:389-408`（`_now` `:367`，注入的时钟）、`sites/douyu.dart:512-523`（`_gifts` 字段在运行中会被 `merge` 换掉）。
- 竖屏堆叠层：`shared/danmaku/portrait_chat_overlay.dart`（`_take` `:97-107`、`didUpdateWidget` `:128-145`、build 的排版 `:206-218`）；按帧合并的现成做法 `features/live_play/danmaku/chat_feed.dart:115-123`（`scheduleChatFlushForNextFrame`）。
- 表情分段：`shared/danmaku/emotes.dart`（`chatSegments` 的 Expando 缓存 `:166-181`、`_parse` 每次新建 `RegExp` `:192-200`）。
- 控制器：`features/live_play/logic/room_controller.dart`（`_flying` `:240`、`_onMessage` 里 `chat.add` + `_flying.add` `:1573-1574`）。

## 3.x 基线

- 3.x 用 flame_barrage 渲染，解码同样在 Dart 侧，但 3.x 没有把解码移出界面线程；本任务改的是流畅度，弹幕的内容、顺序、出现时机和屏蔽规则必须与 3.x 观感一致（D03.1 c2、c7 的行为不变）。
- 要保留：飞行弹幕不等批量（D04.1 的"要保留"第 3 条）；同屏 48 条；ack 及时（B 站心跳、抖音 `needAck`）；B 站认证回复驱动 `ready`；虎牙 `_now()` 注入时钟在测试里可换。

## 先读

1. `AGENTS.md`、`docs/PROCESS.md`（第 5 节分阶段、第 8 节合并审查、第 14 节规则；注意"不许用 WSL"和"python 使用 `uv` 执行"）。
2. `docs/specs/ENGINEERING.md`（第 4 节分层和依赖方向：live_net 在下，live_danmaku 不依赖 Flutter）。
3. 本文件夹的 [README.md](README.md)（诊断表和方案）、D04.1 的 `README.md` 和 `record.md`、D03.1 的 `README.md`（c3 帧率、c6 图片缓存、c7 上限）。

## 范围

- 可以改：`packages/live_danmaku/lib/src/frame_decode.dart`（新建）、`socket_connection.dart`、`sites/bilibili.dart`、`sites/douyin.dart`、`sites/huya.dart`、`sites/douyu.dart` 和它们的测试；`apps/pure_live/lib/shared/danmaku/portrait_chat_overlay.dart`、`emotes.dart` 和对应测试。
- 不能改：`danmaku_overlay.dart` 的渲染时序和缓存策略；`room_controller.dart` 的流类型；其他平台的 `onData`；聊天列表和弹幕的样子；版本号、`assets/version.json`、`assets/releases.json`；签名配置；3.x 的设置键名和含义；不新增设置项。

## 方案和阶段

| 阶段 | 做什么（对应 c 编号） | 改哪些文件 | 怎么算做完 |
|---|---|---|---|
| 1 | c1、c1a：`FrameDecode`（阈值 + 串行链 + `Isolate.run` + 回退 + 停止丢弃）、`DanmakuSocketSession.decodeFrame`、接入 B 站 | `frame_decode.dart`、`socket_connection.dart`、`sites/bilibili.dart`；`frame_decode_test.dart`、`sites/bilibili_test.dart` | 新测试全过；B 站大帧用例与直接解码结果一致 |
| 2 | c1、c1a：接入斗鱼、抖音、虎牙 | `sites/douyu.dart`、`sites/douyin.dart`、`sites/huya.dart` 及各自测试 | 三个平台各有一条走会话路径的大帧一致性用例 |
| 3 | c2、c3：竖屏层按行缓存 + 按帧合并；表情正则微缓存 | `portrait_chat_overlay.dart`、`emotes.dart` 及测试 | build 不重排未变的行；一条消息一次通知；同集合第二次命中缓存 |
| 4 | 真机 profile 和观感 | `verify.md` | 每步有结果；P90 达标后登记表改"待真机/完成" |

## 测试

- 新增：`packages/live_danmaku/test/frame_decode_test.dart` — 小帧同步（无调度延迟）、大帧走 isolate、排队顺序（大帧后紧跟小帧不乱序）、`Isolate.run` 失败回退、会话停止后分发丢弃、解码抛错时后续帧继续。
- 各平台：`packages/live_danmaku/test/sites/bilibili_test.dart` 等加"走 `DanmakuSocketSession` 的突发帧"用例，用测试里现造的样本帧（不新建真实抓包、不访问真实平台），断言与 `Protocol.decode` 结果逐条一致、ack 顺序不变。
- `apps/pure_live/test/shared/portrait_chat_overlay_test.dart`（已有，扩）— 两条消息一帧内只 build 一次；行高缓存命中（改宽度后失效）；本机消息立即。表情正则缓存在 `apps/pure_live/test/shared/emotes_test.dart` 加一条命中用例。
- 基准：`apps/pure_live/test/features/live_play/chat_benchmark_test.dart` 改前改后各跑一次记录数字。
- 定时器至少 1 秒；不访问真实平台。本机 python 一律 `uv run`。

## 真机验证（维护者在 K90 上做）

| 步骤 | 期望 |
|---|---|
| 1. profile 构建进 B 站高能时刻房间 | 滚动匀速，无整段停顿；FrameReport P90 ≤3 毫秒 |
| 2. 进抖音热门房间 | 同上；礼物 ack 不延迟到下一批 |
| 3. 竖屏堆叠模式刷屏 | 堆叠层每帧最多一次重建，向上翻看已显示行不跳位 |
| 4. 带表情的 B 站弹幕刷屏 | 表情显示与改前一致 |

## 风险和注意

- `Isolate.run` 每次有创建成本：只用于大帧，小帧仍同步；持续大帧下若测出 spawn 开销明显，改成常驻 isolate 要在 record.md 写理由。
- 闭包捕获的可发送性：`BilibiliGiftCatalog`、`DouyuGiftCatalog`、`LiveMessage` 都是不可变纯数据（`live_core`），可以发送；抖音的 `broadcast.gifts.accept`（可变门）和虎牙的 `_superChats` 必须留在分发侧。
- 顺序：B 站 `opAuthReply` 驱动 `ready`，若认证帧排在突发帧后会延迟进入——串行链保证不乱序，认证回复仍按到达顺序处理。
- 抖音 `session.send(ack)` 挪到分发后，突发帧的 ack 晚一个 isolate 往返；抖音服务端容忍度未知，真机步骤 2 要确认不掉线。
- 可能冲突的文件：`portrait_chat_overlay.dart`（A08 组）、`emotes.dart`（A07.11 改过）。

## 环境和提交

- 本机（Windows，Git Bash）：`flutter`、`dart` 按 `toolchain.env`；**不许用 WSL**；python 脚本一律 `uv run`（如 `uv run tools/docs/docs.py`）。
- 分支 `ai/D04.2`；提交信息以 `[D04.2]` 开头（英文）；不推 master。
- 提交前：改过的包 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、测试；推送前 `bash tools/gate/gate.sh --all` 通过（日志有 `gate: passed`）。

## 停下时（额度或时间不够）

照 `docs/PROCESS.md` 第 5.2 节：提交到分支、在 `record.md` 写"停在哪"、更新登记表的 `done`、`next`、`branch`，`uv run tools/docs/docs.py`。

## 报告（中文，简洁）

每条做到没有；根因（文件:行）；测试数量与结果；改了哪些文件；基准改前改后数字；要在真机上看的；需要维护者决定的。
