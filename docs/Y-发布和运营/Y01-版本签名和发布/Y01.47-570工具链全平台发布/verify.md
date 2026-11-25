# 发布验收

- 最终源码：待完整门禁通过后冻结，外部final-client-source.json记录commit/tree/门禁日志摘要；十包均从该提交构建。
- Android：三个单ABI APK，固定包名、版本、ABI版本码、原证书、通知/字体资源、ZIP和ELF16KB、mpv/FFmpeg来源字节；新建无用户数据虚拟设备运行正式包。
- Windows：便携与安装包同源，正常lib/main.dart和AOT摘要，隔离UserData、隐藏启动和正常视频；不对用户同AppID安装目录运行安装器。
- Linux：精确归档、依赖和真实隔离首页/视频；glibc2.38/GLIBCXX3.4.32与既有客户端一致。
- Apple：最终同一源码工作流，四包及两次精确Mac归档启动，正常Mac/模拟器截图、原生绑定与播放探针。原iPhone/iPad真机仍有边界。
- 交付：十个候选附件与SHA256SUMS、GitHub摘要、完整回读；公开后再次完整下载核对，再同步两仓库更新源并保持全部历史。
