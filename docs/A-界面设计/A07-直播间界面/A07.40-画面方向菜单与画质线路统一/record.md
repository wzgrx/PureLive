# A07.40 记录

2026-11-04，按用户明确选择“和画质、线路一样”实施。方向菜单原有320固定宽度、标题、三段说明和双行记忆区域；不是小红书提交修改了此入口。移除固定宽度及可见标题/说明，三项使用相同showSmallMenu标准行；底部保留“记住本直播间”单行开关。无障碍仍使用完整方向菜单名称，没有删除设置键、方向算法或房间记忆功能。

同393×852视口、同本地中文字体的真实组件渲染前后对比：旧菜单320×321；新菜单按内容收紧（常规中文约224×236），不是设备截图。浅/深色、852×393横屏、2倍字号和280宽窄屏均有组件渲染与边界回归。

34项专项通过：新交互/布局5、原直播间方向入口1、共享菜单16、多语言12；静态分析fatal-infos通过。额外CJK组件出图5项通过。将player_dialogs.dart恢复至父提交旧代码后，同一回归明确以320超过280宽度上限失败；随后固定源码已恢复。

证据：外部outputs/purelive-orientation-menu-20261104的before/after、old-code-regression.log、red-proof.json与qa-tests.log；work/purelive-orientation-targeted.log、purelive-orientation-integration.log、purelive-orientation-menus.log。

当前仅本地实现与组件验证：未做物理手机验证，未跑本次全量all/14，未推送分支或替换已公开测试安装包。后续推送/打包前仍须完整门禁，不能把父提交的门禁当作本次结果。
