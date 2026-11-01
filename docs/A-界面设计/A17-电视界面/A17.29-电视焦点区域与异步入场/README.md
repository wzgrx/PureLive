# 2026-11-01 TV问题全面复核

复核范围：仓库96条issue中41条电视及共享交互相关条目，含37条已关闭、4条开放，以及143条评论。该数包含功能建议，不能当作41个未修复bug。两个最新问题#141/#142来自Sony KD-65X8566E、Android9、v7a、5.5.0覆盖安装。它们已能在不接入原电视、账号和直播网络的完整应用Widget遥控路径中复现，因此不能先归咎硬件或网络。

## 已证实的共同根因

1. **异步入场只有一次机会**：TvHomePage._select在切换后仅尝试一个post-frame。历史Stream、IPTV Future尚未返回时没有可聚焦目标，之后也不补交接；第二次进入已有数据因而正常。改为可聚焦控件实际挂载/启用后通知，由当前页面和当前用户意图决定是否交接，不轮询、不靠增加固定等待。离开菜单、切页、弹窗和迟到数据均有保护。
2. **内容状态与入口脱节**：关注页Down只尝试房间网格或离线行，空状态搜索按钮没有逻辑入口；失败又回退几何导航，结果受标签横坐标影响。统一从当前内容区域取得有效目标，并把Up接回原筛选栏。
3. **不同方向没有同一张逻辑图**：历史页工具栏Down会越过日期栏，而网格Up却明确回日期栏；日期栏横向末端继续按几何寻找会跳到上面。IPTV网格首列Left随行高落到管理按钮或主菜单。补齐操作行/平台/日期/网格的相邻关系、标签横向边界、IPTV三行左返和列表上下边界。分区页同排的全部平台按钮保留显式入口。
4. **焦点记忆与显式目标相互覆盖**：TvGrid.focusIndex指定换台后的房间，_primaryChanged却可能用旧_last把焦点拉回旧卡片。另一个反证显示屏外卡片的post-frame请求会抢走用户随后移到外部按钮的焦点。显式目标成功提交时才更新记忆，延迟请求校验请求代次、来源焦点和当前路由。
5. **测试缺的是完整路径**：已有用例证明单个组件、外观、若干焦点分支正常，没有覆盖所有“冷入场+异步数据+空态+跨区域+返回”的组合。门禁通过只能证明已有断言通过，不能证明所有遥控边可达。新增实际菜单与按键路径、720p/1080p与1/1.5倍字体矩阵、可见控件方向可达图和迟到回调保护；保留旧实现失败日志。

## 被反证否定的怀疑

首页没有显式ExcludeFocus一度被怀疑导致隐藏页串焦。旧代码的保护测试实际通过：当前Flutter IndexedStack已通过Visibility隔离隐藏页。它不是本次已证明的根因，没有为这一猜测添加重复隔离或改SDK。

## 不能混作导航缺陷的报告

- #131为电视自动识别/持久化场景。5.5.0已有识别失败回退和重试；原Sony偶发情形尚无同机复验，本轮不称已彻底解决。
- #135为斗鱼登录元数据取流，已发布房间级公开游客恢复；不是D-pad问题，原私有登录场景未取得，仍开放。
- #33/#49为首次媒体载入挂起及后续故障传播，缺原机原生首错/线程栈；按既定决定暂缓，不以本轮焦点修复重开或冒称解决。
- #126/#128关闭后的新回复是致谢，没有新增故障。较早#105/#115确认回复已在上一轮处理。

## 验收边界

现有显示不变，修正控制关系；不升级内核、不碰正式安装与用户数据。不以碰巧多等几帧或单个按钮可点击当作整页通过。受控Widget矩阵、专用Android9 AVD、原Sony电视三层证据分开；没有原机证据不标原机问题已验收。当前批次先统一验收，不为每个按钮各发一个版本；也不能承诺未来永无bug。

依据：[Flutter焦点系统](https://docs.flutter.dev/ui/interactivity/focus)、[Android TV导航](https://developer.android.com/training/tv/get-started/navigation)。同时核对本地固定Flutter SDK的focus_traversal.dart与IndexedStack实现；没有以升级SDK替代修正应用逻辑。

## 逐条台账

|Issue|状态|本轮归类|
|---|---|---|
|[#6](https://github.com/wzgrx/PureLive/issues/6)|closed|功能/数据/共享交互|
|[#8](https://github.com/wzgrx/PureLive/issues/8)|closed|功能/数据/共享交互|
|[#14](https://github.com/wzgrx/PureLive/issues/14)|closed|布局/样式|
|[#17](https://github.com/wzgrx/PureLive/issues/17)|closed|功能/数据/共享交互|
|[#22](https://github.com/wzgrx/PureLive/issues/22)|closed|焦点/导航/选择|
|[#30](https://github.com/wzgrx/PureLive/issues/30)|closed|焦点/导航/选择|
|[#33](https://github.com/wzgrx/PureLive/issues/33)|closed|媒体或平台数据|
|[#35](https://github.com/wzgrx/PureLive/issues/35)|closed|焦点/导航/选择|
|[#37](https://github.com/wzgrx/PureLive/issues/37)|closed|焦点/导航/选择|
|[#38](https://github.com/wzgrx/PureLive/issues/38)|closed|功能/数据/共享交互|
|[#39](https://github.com/wzgrx/PureLive/issues/39)|closed|焦点/导航/选择|
|[#46](https://github.com/wzgrx/PureLive/issues/46)|closed|焦点/导航/选择|
|[#48](https://github.com/wzgrx/PureLive/issues/48)|closed|媒体或平台数据|
|[#49](https://github.com/wzgrx/PureLive/issues/49)|closed|媒体或平台数据|
|[#52](https://github.com/wzgrx/PureLive/issues/52)|closed|焦点/导航/选择|
|[#54](https://github.com/wzgrx/PureLive/issues/54)|closed|焦点/导航/选择|
|[#59](https://github.com/wzgrx/PureLive/issues/59)|closed|布局/样式|
|[#61](https://github.com/wzgrx/PureLive/issues/61)|closed|布局/样式|
|[#62](https://github.com/wzgrx/PureLive/issues/62)|closed|焦点/导航/选择|
|[#69](https://github.com/wzgrx/PureLive/issues/69)|closed|布局/样式|
|[#70](https://github.com/wzgrx/PureLive/issues/70)|closed|布局/样式|
|[#71](https://github.com/wzgrx/PureLive/issues/71)|closed|焦点/导航/选择|
|[#72](https://github.com/wzgrx/PureLive/issues/72)|closed|功能/数据/共享交互|
|[#74](https://github.com/wzgrx/PureLive/issues/74)|closed|焦点/导航/选择|
|[#84](https://github.com/wzgrx/PureLive/issues/84)|closed|布局/样式|
|[#90](https://github.com/wzgrx/PureLive/issues/90)|closed|布局/样式|
|[#91](https://github.com/wzgrx/PureLive/issues/91)|closed|布局/样式|
|[#98](https://github.com/wzgrx/PureLive/issues/98)|closed|功能/数据/共享交互|
|[#103](https://github.com/wzgrx/PureLive/issues/103)|closed|布局/样式|
|[#104](https://github.com/wzgrx/PureLive/issues/104)|closed|布局/样式|
|[#105](https://github.com/wzgrx/PureLive/issues/105)|closed|功能/数据/共享交互|
|[#112](https://github.com/wzgrx/PureLive/issues/112)|closed|布局/样式|
|[#115](https://github.com/wzgrx/PureLive/issues/115)|closed|媒体或平台数据|
|[#126](https://github.com/wzgrx/PureLive/issues/126)|closed|功能/数据/共享交互|
|[#128](https://github.com/wzgrx/PureLive/issues/128)|closed|功能/数据/共享交互|
|[#131](https://github.com/wzgrx/PureLive/issues/131)|open|设备识别|
|[#132](https://github.com/wzgrx/PureLive/issues/132)|closed|焦点/导航/选择|
|[#135](https://github.com/wzgrx/PureLive/issues/135)|open|媒体或平台数据|
|[#138](https://github.com/wzgrx/PureLive/issues/138)|closed|焦点/导航/选择|
|[#141](https://github.com/wzgrx/PureLive/issues/141)|open|焦点/导航/选择|
|[#142](https://github.com/wzgrx/PureLive/issues/142)|open|焦点/导航/选择|
