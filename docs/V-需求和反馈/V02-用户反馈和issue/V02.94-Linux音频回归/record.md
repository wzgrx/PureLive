# 记录

2026-11-26读取反馈及当前master，初步发现强制ALSA与新原生静态库插件路径的交互，待原生确认。

## 根因与原生波形对照

从正式5.6.5/5.7.2包抽取原生库，在同样Ubuntu24.04.5 LTS、同一独立Pulse空设备/监视器和生成440Hz立体声音频下验证。旧版动态依赖系统libasound.so.2；新版静态ALSA1.2.15.1把配置及模块位置编成构建机/workspace/prebuilt/linux-x86_64/libraries/share/alsa和lib/alsa-lib。应用仍强制ao=alsa。新版实际报错：Cannot open shared library libasound_module_pcm_pulse.so，随后加载构建机路径失败，无法初始化输出。用户调静音/音量不改变驱动，回退恢复与该链路一致。

对照结果：旧5.6.5 ALSA有非零440Hz PCM；新5.7.2 ALSA全零；同一新版库原生自动探测或显式pulse均有非零440Hz PCM。另确认界面auto不是有效后端名，直接传入时报Audio output auto not found并全零。已让Linux默认保留原生探测，将专家auto/空值规范为各平台默认；显式pulse/alsa/null等选择保留，Android的AudioTrack/AAudio/OpenSL ES回退保持。

实际生产MpvEngine和VideoController构建的Linux原生入口也验证：旧ALSA输出为空且PCM全零，新默认选择pulse，PCM非零且实测频率约440Hz。输入音量100，未连接用户声卡、WSLg Pulse服务或实体设备。该入口编译含未提交修复，记录基线提交与候选源码/AOT摘要，不冒充基线原包。首次旧库实验缺libarchive等运行依赖，补齐后取得旧版对照，初次失败保留。Docker直连及容器内127代理下载失败，改用DockerDesktop主机代理后完成；不视为产品音频错误。

本次证明默认策略恢复了Ubuntu桌面音频服务通道；用户明确指定ALSA仍依赖当前内核的静态ALSA可移植性，未将其改成其他驱动，也未宣称原用户物理声卡已实测。后续内核构建应使用目标系统ALSA动态库，避免再次固定构建机目录。

## 修复验证

ALSA旧库通道、当前内核原生自动/Pulse及生产MpvEngine新默认的捕获波形均匹配440Hz，误差小于1Hz；当前强制ALSA和字面auto均全零。播放器完整135项、应用播放设置22项通过，静态分析通过。设置专项第一次文件名写反，运行器未找到测试；随后使用实际settings_playback_test.dart执行22项，原失败日志保留，不计为产品回归。

本次不改已发布5.7.2安装包，不升版本或修改更新JSON；待完整门禁通过后提交修复PR。原反馈者实际音频设备及系统原机尚需复验，issue保持开放至修复包发布/验证。新默认按内核能力探测系统服务，保留明确输出和禁音选择。


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
