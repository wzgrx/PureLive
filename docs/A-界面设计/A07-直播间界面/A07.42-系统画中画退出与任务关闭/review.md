# A07.42 合并审查

对照本任务brief、record与本轮最终源码：保留设置默认语义与原播放器所有权；所有新用户文字走15语言，未携带真实账号/Cookie/原始帧进入仓库。修复项具旧行为反证，协议/接口/组件/原生/原设备证据分别记载。原生退出确实发现并修复额外竞态，没有以重跑掩盖原故障。

当前专项/严格分析与组件图已检查；完整all/14、最终同源构建和公开回读等待发布阶段完成后追加。尚未合并，不提前声称合并或原机验收。#192、#198礼物剩余项与#177TV原机边界保留；未直接新增未经证实的画质、价格或图标。

2026-11-05追加原生反证：同源重验捕获FlutterJNI.scheduleFrame在纹理回调里调用已销毁引擎，完整堆栈本地保留。Flutter上游#174859有相同堆栈；不能据此说是设备或网络问题。当前代码RoomRuntime先background.dispose并发布audio_service idle，再等待异步视频释放；audio_service在无Activity时销毁缓存引擎，形成真实先后顺序竞态。改为先停止策略监听/锁，再等待session.waitForResourceRelease的实际退休（不把dispose的有界grace当作真实完成），最后清通知。任务回调3秒grace到期不再强制idle，真实退休仍由runtime持有；新房间所有者保护保持。

使用可控native dispose future延迟超过5秒的新回归，旧顺序在通知提前hide断言失败；修后保持通知到真实释放后才hide。既有小窗/后台/PiP/叠加窗口80项通过，延迟测试与严格分析另通过。独立API37原生AppTask.finishAndRemoveTask连续3轮通过回调、原生视频释放、音频服务1→0、无接收器泄漏/音频空指针并正常重开；不是原Honor/MagicOS验收，也不声称修复所有Flutter内核路径。
参考：https://github.com/flutter/flutter/issues/174859

仅调整当前房间的释放顺序还不足：9250复验中当前纹理已先释放，旧导航栈房间的另一条纹理仍在，媒体插件onDetachedFromEngine原来仅删除MethodChannel处理器、未释放管理器所有输出。最终补上插件detach时先断开回调，再幂等disposeAll所有剩余SurfaceProducer（包括旧房间/空闲输出），拒绝迟到create。FlutterEngine.destroy源码明确plugins.destroy先于JNI detach；利用已有生命周期修复，不补丁SDK、不改解码内核或强行杀应用。8个相关生产文件SHA与最终源一一核对。两次真实崩溃及只改顺序仍失败的反证保留。

5.6.4+5143已正式交付。构建源码`d4bdcf962cfe9753e0c23d731dd246e970b306c7`，源PR[#199](https://github.com/wzgrx/PureLive/pull/199)；最终完整all/14、十个同源包及SHA256SUMS本地/远端摘要/匿名完整下载一致，历史更新条目保留。最终双源结果以Y01.44记录为准；未将原机和礼物剩余项冒充全部完成。

分层证据与剩余边界见[Y01.44发布验证](https://github.com/wzgrx/PureLive/blob/master/docs/Y-发布和运营/Y01-版本签名和发布/Y01.44-5.6.4竖屏弹幕与礼物小窗发布/verify.md)。
