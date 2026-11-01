# 旧安卓全屏系统栏恢复

本轮#148原生验收发现：Android9录像进入全屏后返回列表，状态栏仍隐藏。与原Sony媒体挂起、自动界面识别分开，不声称解释那些设备问题。

共用SystemUiVisibility覆盖首页、直播、多画面、共享回放播放器。恢复先沿用Flutter edgeToEdge；原生只判断系统是否早于API29；旧系统再通过Flutter公开manual overlays接口显示两栏，同时更新框架保存的模式，避免旋转/恢复应用时重套旧隐藏状态。主题样式仍由原SystemBarsScope管理。Android10及更新、iOS和桌面保持原策略。新的全屏请求会使等待中的旧系统回退失效。

3.x同样依赖播放器退出时恢复系统栏，本任务修复兼容行为，不新增用户开关。录像页说明与输入框浮动标签之间另增加8px间距。

来源：[Flutter SystemUiMode官方文档](https://api.flutter.dev/flutter/services/SystemUiMode.html)、[上游系统栏问题](https://github.com/flutter/flutter/issues/162214)、本地3.47.8 SDK同样明确API29之前忽略edgeToEdge。上游问题用于核对布局差异，不能替代本地Android9原生复现。
