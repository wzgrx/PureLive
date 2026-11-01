# A07.37 实现与验证记录

保留旧模式、开关和合并外观字段；separate默认关闭，clockStyle/speedStyle分别保存位置、字号、字体、ARGB，省略项继承旧样式，非法导入值按既有边界回退。同角落纵排，异角落在小画面按可用空间分配边界；16组角落组合在240×120、48字号及2倍系统字下不重叠。信息层保持IgnorePointer/ExcludeFocus，只订阅一个统计采样器。设置中切换编辑对象和位置、关闭独立及恢复默认有实际组件交互回归。

入口：设置→播放信息常驻显示→时间和网速分别设置。核心代码：`apps/pure_live/lib/shared/rooms/playback_hud_config.dart`、`playback_hud.dart`，设置：`features/settings/playback_hud_page.dart`。Settings.playbackHud仍为同一设置和备份键。

完整门禁、同源构建和最终原生结果将在发布验收中追加。原始证据保存在仓库外 `outputs/purelive-551-20261101/`。
