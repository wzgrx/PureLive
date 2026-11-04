# D07.9

2026-11-04：核对当前三个开放issue及原始复现步骤，开始实现；发布、原生及真实平台证据后补。

2026-11-04：补Douyin WebcastGiftMessage的公开protobuf字段解码；显式组号连击为单调总量快照，512组LRU去重复/结束包/倒序，不累加快照；未知价图不推测。快手现有mobile feed收到gift+文字时保留为gift类型，未提供price/icon时data为空，不编造币价。

公开字段来源：wwengg/douyin 268d5d8abc571783f0fb355ba4401aee55b42f87 proto/message.proto；wbt5/real-url b6daf0abcd445b6ede76221a7d2aac383bc87a2e danmu/danmaku/kuaishou.proto。dyhub关于登录礼物的描述仅为第三方观察，非本地证明。合约用合成数据，旧解码器失败记录保留；三份新旧协议专项138项通过，严格分析通过。原3.x冻结向量保留，两条旧的忽略gift预期只对chat/ack做旧子集比对，同时独立断言新增gift。

用户反馈无法登录，不读取Cookie、密码或代付礼物。生产抖音游客连接75秒ready，16文字消息，收到GiftSort但未收到GiftMessage；快手公开SSR无有效ws/token/catalog，六次旧feed无gift观察。这些仅是样本窗口，不能推断永久平台限制。实际登录态投递、快手完整价格/图标目录及WS路径尚未验证或交付；#192必须继续开放，发布说明只写已实现部分。

5.6.4+5143已正式交付。构建源码`d4bdcf962cfe9753e0c23d731dd246e970b306c7`，源PR[#199](https://github.com/wzgrx/PureLive/pull/199)；最终完整all/14、十个同源包及SHA256SUMS本地/远端摘要/匿名完整下载一致，历史更新条目保留。最终双源结果以Y01.44记录为准；未将原机和礼物剩余项冒充全部完成。

分层证据与剩余边界见[Y01.44发布验证](https://github.com/wzgrx/PureLive/blob/master/docs/Y-发布和运营/Y01-版本签名和发布/Y01.44-5.6.4竖屏弹幕与礼物小窗发布/verify.md)。
