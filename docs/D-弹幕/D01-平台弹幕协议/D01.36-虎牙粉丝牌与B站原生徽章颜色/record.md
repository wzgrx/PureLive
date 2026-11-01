# D01.36 实现与验证记录

虎牙当前官方视频页面加载的协议定义：MessageNotice的8/9/12/15为DecorationInfo向量，DecorationInfo 0为iAppId、2为vData，10400载荷BadgeInfo 3为名称、4为等级。读取首个有效粉丝牌，未知装饰、无名称/非正等级/损坏可选载荷不制造徽章、不丢正常聊天。公开上游录制载荷也按当前定义解码为“絕跡 11”。来源：https://github.com/OrdinaryRoad-Project/ordinaryroad-barrage-fly/blob/162a9d1581c642986ee575b80cc82006e7dece59/barrage-fly/src/main/resources/express/msg-examples-huya.txt。

B站读取rich user.medal颜色或legacy info[3]，实际S13录制的并行字段核对了7=border、8=start、9=end。rich缺颜色时只回退到名称和等级均一致的legacy徽章，不使用另一牌子的颜色。模型LiveFanBadgeColors无Flutter依赖，文本清洗与礼物合并保留；共享ChatChip画原生颜色/渐变/描边并选更清楚的文字色。浅/深/纯黑、窄栏2倍字回归通过。

完整门禁、同源构建和最终原生结果将在发布验收中追加。原始证据保存在仓库外 `outputs/purelive-551-20261101/`。
