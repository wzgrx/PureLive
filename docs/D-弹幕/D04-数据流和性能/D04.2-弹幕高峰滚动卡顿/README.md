# D04.2 弹幕高峰滚动卡顿：大帧解码移出界面线程（B站/斗鱼/抖音/虎牙）

> 任务说明（性能）。完成前写"方案"，完成后写"结果"。编号、状态、档位以 [登记表](../../../tasks.toml) 为准，见[子分类页](../README.md)和 [STATUS.md](../../../STATUS.md)。

- 类型：性能
- 来源：用户反馈（2026-11-09）"弹幕多了的时候，弹幕滚动明显会很卡"
- 相关：[D04.1 弹幕性能和可读性](../D04.1-弹幕性能和可读性/README.md)（每帧最多刷新一次、列表反转）；[D03.1 飞行弹幕渲染](../../D03-飞行弹幕引擎/D03.1-飞行弹幕渲染/README.md)（渲染器）；[R01 基准和测量](../../../R-性能和流畅度/R01-基准和测量/README.md)

## 目标

热门直播间（每秒几十到上百条）里飞行弹幕滚动匀速、不顿挫；用户不需要改任何设置，行为和外观不变。

## 诊断（读代码和已有测量得出）

渲染器不是瓶颈：`shared/danmaku/danmaku_overlay.dart` 已经是一次排版录制 + `ui.Picture` 缓存（96 条）、外层 `RepaintBoundary`（`features/live_play/player/player_view.dart:687`）、帧率整除上限、同屏默认 48 条、每帧最多入场 4 条、等待队列 120 条/5 秒。R01.2 真机 profile 实测 `danmaku_200` 界面线程 P90 4.59 毫秒、光栅 P90 2.06 毫秒、掉帧 0。

卡顿来自界面线程被每条消息的上游处理同步阻塞，弹幕越多、单帧越大，vsync 和 Ticker 回调越被推迟：

| 编号 | 根因 | 位置 |
|---|---|---|
| c1 | 协议解码全在界面线程同步跑：socket 监听回调内联调 `onData`，事件总线 `broadcast(sync: true)`，解码→过滤→所有消费者是一条同步链。B 站单帧最多 4096 包/16 MiB，用**纯 Dart brotli**（比 C 库慢一个数量级）+ 每包 `jsonDecode`；抖音单帧 gzip + 批量 protobuf，protobuf 读字段是线性扫描 | `packages/live_net/lib/src/socket.dart:288-294`、`packages/live_danmaku/lib/src/connection_base.dart:24`、`sites/bilibili.dart:206-220,500,513-519,524`、`sites/douyin.dart:158,166-185`、`codec/protobuf.dart:52-92` |
| c2 | 竖屏堆叠层每条消息 `setState`；build 里对每个可见行重新分段 + `TextPainter.layout`；`didUpdateWidget` 还全量重解析 | `shared/danmaku/portrait_chat_overlay.dart:102-106,141,206-218` |
| c3 | 自带表情码的消息每条新编译一个 `RegExp`（B 站弹幕大量带表情），缓存只共享同一条消息的解析 | `shared/danmaku/emotes.dart:192-200` |
| c4 | 次要：飞行流不分批（`room_controller.dart:1573-1574`，但入队本身便宜）、车道分配 O(车道×在屏)（`danmaku_overlay.dart:590-605`）、相似过滤开启时每条 O(96×L²)（默认关） | — |

## 方案

- c1：**卸载机制只写一份**，放在共享的 `DanmakuSocketSession`（`packages/live_danmaku/lib/src/socket_connection.dart`），新建 `packages/live_danmaku/lib/src/frame_decode.dart`：
  - 帧小于阈值（8 KiB）且串行链空闲 → 仍同步解码（小帧、认证回复、心跳的延迟和顺序不变）；
  - 大帧 → `Isolate.run` 跑平台传入的**纯解码**回调（live_danmaku 是纯 Dart 包，用 `Isolate.run` 而不是 `compute`）；链未结时后续帧排队，保证消息和 ack 顺序；
  - isolate 失败 → 回退同步解码；解码结果的分发（`session.send` 的 ack、`_authReply`、礼物门 `accept`）仍在界面线程执行；
  - 会话已停（`isActive` 为假）时分发丢弃，行为和各平台现有的 `if (!session.isActive) return` 一致。
  - 接入 B 站、斗鱼、抖音、虎牙四个平台的 `onData`：把现有"同步 decode + 分发"包进 `session.decodeFrame(data, decode, dispatch)`，各平台只改这一处。其余平台的 `onData` 不动，需要时再接。
- c2：竖屏堆叠层按行缓存分段和行高（行不可变，签名是可用宽度、字号、缩放、字体、字重），build 不再对未变的行做 `TextPainter.layout`；`_take` 的通知按帧合并（复用 `features/live_play/danmaku/chat_feed.dart:115` 的 `scheduleChatFlushForNextFrame`），本机消息立即刷新。
- c3：`_parse` 里带表情码的正则按（表情表，排序后的码）缓存最多 16 条，超了淘汰最旧的。
- c4：不做。飞行流分批只是搬移工作，且改控制器流类型会破坏"同一功能同一组件"；真机数字仍不达标再开后续任务。

## 性能任务：测量

| 指标 | 改之前 | 目标或结果 | 怎么测 |
|---|---|---|---|
| 单条大帧在界面线程的解码耗时（B 站 brotli 突发帧） | 数毫秒到数十毫秒（待实测） | 移出界面线程 | 新增基准测试：固定样本帧，测解码墙钟时间 |
| 每秒 200 条时界面线程 P90 | D04.1 在 WSL debug 下 P99 14.32、最差 74.19 毫秒；R01.2 K90 profile P90 4.59 | ≤3 毫秒（计划书 9.4） | `apps/pure_live/test/features/live_play/chat_benchmark_test.dart` + K90 profile（R01 的 FrameReport） |

> D04.1 的数字来自 WSL，不具可比性；本任务只在本机测，不许用 WSL。

## 验证

- 自动测试：`packages/live_danmaku/test/frame_decode_test.dart`（阈值、顺序、回退、停止后丢弃）；`sites/bilibili_test.dart`、`douyin_test.dart`、`douyu_test.dart`、`huya_test.dart` 各加一条走会话路径的大帧用例，断言与直接调用 `Protocol.decode` 结果一致；`portrait_chat_overlay_test.dart`（缓存命中和失效、按帧合并）。测试不访问真实平台，定时器至少 1 秒。
- 真机：见 [verify.md](verify.md)（K90 profile，B 站高能时刻和抖音热门房间）。

## 留下的问题

- 其余平台（快手、YY、SOOP 等）的接入：实测有卡顿再接，机制已就位。
- 相似过滤开启时每条 O(96×L²)：默认关闭，需要时单独任务。
