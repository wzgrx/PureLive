# A07.37 实现与验证记录

保留旧模式、开关和合并外观字段；separate默认关闭，clockStyle/speedStyle分别保存位置、字号、字体、ARGB，省略项继承旧样式，非法导入值按既有边界回退。同角落纵排，异角落在小画面按可用空间分配边界；16组角落组合在240×120、48字号及2倍系统字下不重叠。信息层保持IgnorePointer/ExcludeFocus，只订阅一个统计采样器。设置中切换编辑对象和位置、关闭独立及恢复默认有实际组件交互回归。

入口：设置→播放信息常驻显示→时间和网速分别设置。核心代码：`apps/pure_live/lib/shared/rooms/playback_hud_config.dart`、`playback_hud.dart`，设置：`features/settings/playback_hud_page.dart`。Settings.playbackHud仍为同一设置和备份键。

完整门禁、同源构建和最终原生结果将在发布验收中追加。原始证据保存在仓库外 `outputs/purelive-551-20261101/`。

## 全量兼容补齐

8cfc9d1完整all/14期间源码fingerprint前后一致，应用和存储测试共发现7项失败，其他门禁保留原结果，未启动构建。缺失search/loading改用已有本地化动作；新增图片适配和采集提示的运行时键族逐值登记，31条新文案补全至全部15语言，不改既有译文。新设置默认值、虎牙路由逐项进入兼容清单。电视HUD回归改为先确认字号控件再按Right，仍验证原合并配置从18改为19，不因新增设置行而误改其他控件。

新外观入口在TV模式委派电视原背景设置，避免手机背景配置在TV界面没有效果。55项翻译/主界面、4项默认值、TV HUD及TV入口专项均通过；失败原始日志在source-attempt2-compatibility保留。现代完整门禁再次按新提交从头执行，无失败豁免。
