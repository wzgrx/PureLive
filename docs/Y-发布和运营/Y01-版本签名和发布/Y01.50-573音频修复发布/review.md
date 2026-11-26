# 审查

审查默认与专家输出、禁音、原设置保留、单一冻结源和发布边界。原用户物理音频设备保持独立复验。


## 5.7.3正式交付

维护者明确授权核对#266门禁、合并分支PR并发布更新。修复PR267已合并；版本发布源码`a4af35b2e6bf117d098ad20b855fba3be4929dd5`经完整14成员门禁冻结，发布源码PRhttps://github.com/wzgrx/PureLive/pull/268合并`a18749e3483280771ba58d59dbe4f286fb260f79`，正式版本https://github.com/wzgrx/PureLive/releases/tag/v5.7.3。十客户端及摘要文件完成草稿完整回读、匿名公开完整下载与生产/远端摘要匹配，全部228条历史记录保留。

根因是应用强制ALSA与升级后内核静态ALSA的构建机配置/插件路径组合；同Ubuntu24.04.5、同生成440Hz音频和独立Pulse音频服务对照：旧5.6.5正常、新5.7.2固定ALSA全零、自动探测/Pulse正常。新默认不指定ao，让内核按能力探测；专家auto/空值归一化，明确的驱动和null禁音保留。播放器135项、播放设置22项与完整门禁通过。

本次进一步验证正式Linux归档，标准lib/main.dart入口：生成HLS与视频画面正常，私有空音频设备监视器捕获非零PCM，实测440.328Hz、RMS1479.070。成品包SHA与发布清单匹配，未借用主机音频服务或物理声卡。Windows/Android/Linux正常成品首页与移动画面、各系统原生文件和录制探针、Apple同源CI45838931351及两次独立Mac成品启动通过。原报告者的具体物理声卡仍保留复验，不将相同用户态与虚拟音频服务称为原机验收。

旧更新源PRhttps://github.com/wzgrx/pure_live/pull/47只同步version.json与releases.json。基线严格核对与5.7.2候选的源树、更新JSON及原完整日志摘要等价后复用；本次候选完整门禁、旧解析/版本比较/选包/全部历史保留独立执行。新旧均为相同6项历史版本页失败，无新增。按用户当前发布及既有自主维护委托记录D-100，仅适用于5.7.3旧库两JSON；现代完整14成员门禁通过，不声称新取得逐版人工确认。

历史失败：
- features/version/version_page_test.dart: reads the repository update files as 3.x does
- features/version/version_page_test.dart: shows the failure and checks again on retry
- features/version/version_page_test.dart: the release history lists releases and opens one
- features/version/version_page_test.dart: U.12b the start-up check and the version page tell the about page about a newer version
- features/version/version_page_test.dart: U.12b history: "版本历史", "最新" and "当前", no file size; close at the top right (c2, c11, c12)
- features/version/version_page_test.dart: the release history shows both panes on a wide window

已在#266回复正式版本与实际成品音频结果，留言7196659863；按原复验约定保持开放，等待反馈者原机声音确认。Apple正常iOS模拟器和Mac重新打开截图已读取，确认进入首页；未将CI虚拟设备称为Apple实体机验证。
