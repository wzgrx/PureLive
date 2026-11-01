# D01.36 虎牙粉丝牌与B站原生徽章颜色

来源：#146 #147。

虎牙官方MessageNotice的8/9/12/15装饰向量，10400载荷BadgeInfo字段3名称、4等级；B站rich medal原生颜色和legacy info[3]颜色。默认值兼容、可选字段损坏保留聊天、文本清洗和礼物合并保留颜色。

用户授权所有决定自行处理，按本方案推进，无需重复确认。系统权限仍由系统处理。

## 各布局

手机使用设置列表和标准返回，桌面复用设置面板，电视保留遥控焦点和返回边界。用户可见新文字进入zh/en有序翻译。默认外观保持不变，配置不持有账号、Cookie或媒体签名。

## 验收

实际协议或官方响应证据、对应回归、必要的修改前失败、受控原生布局与运行验证。原设备未覆盖与受控证据分开记录。

## 实现要点

虎牙当前官方视频页面加载的协议定义：MessageNotice的8/9/12/15为DecorationInfo向量，DecorationInfo 0为iAppId、2为vData，10400载荷BadgeInfo 3为名称、4为等级。读取首个有效粉丝牌，未知装饰、无名称/非正等级/损坏可选载荷不制造徽章、不丢正常聊天。公开上游录制载荷也按当前定义解码为“絕跡 11”。来源：https://github.com/OrdinaryRoad-Project/ordinaryroad-barrage-fly/blob/162a9d1581c642986ee575b80cc82006e7dece59/barrage-fly/src/main/resources/express/msg-examples-huya.txt。

B站读取rich user.medal颜色或legacy info[3]，实际S13录制的并行字段核对了7=border、8=start、9=end。rich缺颜色时只回退到名称和等级均一致的legacy徽章，不使用另一牌子的颜色。模型LiveFanBadgeColors无Flutter依赖，文本清洗与礼物合并保留；共享ChatChip画原生颜色/渐变/描边并选更清楚的文字色。浅/深/纯黑、窄栏2倍字回归通过。
