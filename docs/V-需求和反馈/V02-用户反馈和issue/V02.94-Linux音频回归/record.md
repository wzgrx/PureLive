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
