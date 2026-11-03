# 验证记录

冻结运行代码：`7f074ebe25a3698a45e78cefb4eb33a827ca43a0`。版本5.6.2-preview.2，Flutter基数5135；分ABI APK实际versionCode为arm64 7135、x64 9135，包名均为com.mystyle.purelive.v4dev，同既有测试签名。

## 自动与原生证据

- 相关回放、倍速、i18n组合69/69通过；全屏按钮边界补充回归后目录/布局18/18通过。
- 首次all/14仅应用翻译未使用键检查失败，三个旧键已清理；最终完整门禁必须以本机/tmp/purelive-v5-gate-final.log的gate: passed为准，推送及发布流程会检查实际结果。
- 本地两个架构profile构建成功。packages.json/SHA256SUMS记录逐包签名、ABI、大小和摘要；安装后读取base.apk确认x64哈希匹配候选。
- 任务独占API37模拟器emulator-5588，393×851左右dp，1080×2340像素。仅操作v4dev；没有操作用户手机。最终进程logcat范围内未发现fatal/unhandled，测试后停止应用和模拟器。
- 真实B站公开回放BV1pp4F6rEtu第2段，恢复旧进度并实际解码。竖屏页头、短标题、整场时长、四段列表、画面内控制与全屏按钮检查通过。
- 暂停在2:58后进入横屏；倍率面板右侧显示12档，选4×后仍暂停且进度不跳。更多显示音量滑条。系统Back先关面板、再退全屏还原竖屏、再回目录；分段内进度回读约2:56（原生时间取整/保存采样存在差异）。

## 下载与实际截图

预览发布目标：[回放第五版5.6.2-preview.2](https://github.com/wzgrx/PureLive/releases/tag/preview-replay-v5-20261103.2)。发布完成后页面附件提供本次APK截图portrait-player.png、landscape-settings.png和native-qa.json；发布前此链接不代表已交付。

## 边界与待真机

模拟器以-no-audio运行，未验实际听音。最终候选只重跑B站原生播放；斗鱼/虎牙的自动回归通过，不能因此宣称本次三平台真实设备验收。物理手机、电视硬件/遥控器、Apple、账号/VIP和所有CDN仍待验。

1. 直播间进入回放，竖屏控制不遮内容，分段和场次可选择。
2. 横屏播放3秒隐藏、暂停保持；各设置不挤压画面，Back逐层退出。
3. 切画质/分段保留暂停意图；退出再入续看；切场次无重叠声音和旧画面。
4. 电视方向键可达控件和侧栏，200%文字可滚动。

最终结果：`gate: passed (all, 14 members)`，完整门禁无例外。门禁后只追加验证文档与登记状态，apps/packages/tools及工具链与冻结运行源码完全一致；文档生成、owners和差异检查再次通过后推送。GitHub仅预览发布，原设备未验，状态待真机。
