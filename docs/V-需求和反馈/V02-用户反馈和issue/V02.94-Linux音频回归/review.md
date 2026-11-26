# 审查

待核对根因、改前/改后结果、默认策略与显式null/设备选择、分层与完整门禁。

## 根因与原生波形对照

从正式5.6.5/5.7.2包抽取原生库，在同样Ubuntu24.04.5 LTS、同一独立Pulse空设备/监视器和生成440Hz立体声音频下验证。旧版动态依赖系统libasound.so.2；新版静态ALSA1.2.15.1把配置及模块位置编成构建机/workspace/prebuilt/linux-x86_64/libraries/share/alsa和lib/alsa-lib。应用仍强制ao=alsa。新版实际报错：Cannot open shared library libasound_module_pcm_pulse.so，随后加载构建机路径失败，无法初始化输出。用户调静音/音量不改变驱动，回退恢复与该链路一致。

对照结果：旧5.6.5 ALSA有非零440Hz PCM；新5.7.2 ALSA全零；同一新版库原生自动探测或显式pulse均有非零440Hz PCM。另确认界面auto不是有效后端名，直接传入时报Audio output auto not found并全零。已让Linux默认保留原生探测，将专家auto/空值规范为各平台默认；显式pulse/alsa/null等选择保留，Android的AudioTrack/AAudio/OpenSL ES回退保持。

实际生产MpvEngine和VideoController构建的Linux原生入口也验证：旧ALSA输出为空且PCM全零，新默认选择pulse，PCM非零且实测频率约440Hz。输入音量100，未连接用户声卡、WSLg Pulse服务或实体设备。该入口编译含未提交修复，记录基线提交与候选源码/AOT摘要，不冒充基线原包。首次旧库实验缺libarchive等运行依赖，补齐后取得旧版对照，初次失败保留。Docker直连及容器内127代理下载失败，改用DockerDesktop主机代理后完成；不视为产品音频错误。

本次证明默认策略恢复了Ubuntu桌面音频服务通道；用户明确指定ALSA仍依赖当前内核的静态ALSA可移植性，未将其改成其他驱动，也未宣称原用户物理声卡已实测。后续内核构建应使用目标系统ALSA动态库，避免再次固定构建机目录。
