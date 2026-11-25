# 执行记录

基线852d90369，上一轮门禁all/14通过，原工具链保留。审计218份官方元数据和只读解算记录位于外部工作输出。新版的运行验收仍须重新执行，不继承旧提交通过结论。

## 2026-11-25 第一阶段

- 独立安装Flutter3.50.1/Dart3.14、Temurin27.0.1.1+4、Clang23.1.6、CMake4.5.1、Inno7.1.1、platform-tools37.0.3和Android CLI1.1.16919734；VS18.12.1已具备C++工作负载。原SDK及安装保留。Gradle9.9.2、AGP9.5.2升级。
- 对新版SDK重新执行官方语义测试：未修复源码复现失败，应用官方同一补丁后7项通过。显式SDK测试缓存准备仅恢复已核验的lock下限变化，未知变更保留现场并拒绝。
- 迁移Flutter分离后的Material/Cupertino导入与类型；更新工作区直接依赖。window_manager0.7.1改为原生事件适配，测试覆盖关闭投票与订阅生命周期；文件夹选择改为URI并验证已有文件系统写入路径。
- 应用/live_player/live_ui静态分析通过，窗口、启动和目录回归4项通过。全量门禁、正式客户端和真实原生验收尚未完成，不能沿用旧版结果。
- media-kit同步到484639aca5ffc754a65876c22f01dbb070225732；保留生产帧提交、生命周期和平台补丁。新版原生包仍在构建，清单此时仍固定旧版，不提前修改版本声明。
- FFmpeg9.1 Android三ABI及Linux已编译；Android保留已核验0.11.2 Java API，剥离分发符号后通过16KB/架构检查；Linux最高glibc2.28检查通过。Windows继续编译。Apple首次在Rust准备阶段失败，保留日志；显式透传runner的Cargo/Rustup目录后待重跑，尚不能宣称通过。


## 完整门禁首轮及修复

首轮完整14成员检查保留于外部`full-gate-first.log`：应用5项测试失败、live_ui一项同类测试失败、弹幕基准一条静态分析失败，其他成员通过。

- 平板背景两项失败定位到旧MaterialUiThemeBridge：迁移后两侧已是同一ThemeData类型，旧字段复制丢失AppBar组件主题。改为保留完整继承主题；原主页测试全部通过。
- 已关注卡片和隐藏侧栏标签的测试仍使用SDK旧Tooltip类型查找（且组件已自行提供Semantics）。保留无障碍行为，按material_ui的实际Tooltip类型核对消息；没有增加重复朗读。
- 新SDK的RawTooltip在焦点树之前处理Esc，以先关闭可见提示。单独运行复现了同一变化；回归明确核对提示→面板→全屏的逐层关闭，保留播放会话与窗口状态断言。
- 恢复格式迁移误删的原基准`avoid_print`注释；基准输出仍仅用于测试。
- Apple云日志证实cargo-c宿主编译误用了iOS SDK头文件，改为切换跨平台环境前准备宿主工具；同时新增独立的mpv0.42/FFmpeg9.1 Apple动态框架构建，五个slice保持iOS15/macOS12最低要求，使用系统TLS信任与AV1软件解码。


## 原生内核与信任库验证

- Android0.42/FFmpeg9.1在自有API27模拟器先复现：本地H264/AAC正常，默认验证开启的公网HTTPS因未知CA失败。接入系统信任库后同一HTTPS正常解码；未知测试证书仍拒绝，显式测试CA才接受。三ABI重编译后完整API26强导入、16KB及helper字节保留再次通过。
- Windows采用官方0.42 LGPL包，核对发布摘要；实际本地和公网HTTPS解码通过，验证保持yes。官方包内FFmpeg报告其Git快照，不能冒充同版录制用FFmpeg9.1。
- Linux先捕获静态libplacebo的C++转换符号缺失和新增XPresent动态依赖，改为C++链接器、严格未解析符号检查并静态链接XPresent。保持glibc2.28、X11/VAAPI/VDPAU，播放器启用GPL，录制仍是LGPL基础包。受下载代理环境影响的一次公网探针未在时限内推进，清空该环境后本地/公网HTTPS解码通过；不据此宣称修复所有代理场景。
- Apple录制云构建已通过Xcode27.2/Python3.15.2/CocoaPods检查及宿主cargo-c准备，仍在编译。播放器单独提供构建工作流，补齐静态C++链接和旧OS数值转换保护；最终运行结果尚待取得。


## 客户端集成修正

旧窗口适配在Windows隐藏启动时只查active window，会遗漏本程序的隐藏HWND。改由runner的既有startup通道返回自身句柄，Dart显式绑定，异步初始化共享一次请求；并核对拒绝关闭后仍保留下一次确认。窗口和启动回归、分析通过。

精简内核可能没有长编码描述，新增缺失描述的回归先失败，补实际短名回退后通过。Android Downloads系统provider的downloads/raw目录ID按AOSP定义映射，拒绝跨用户、越界和仅provider可解析的ID；红绿回归通过。

本地已验证播放与录制组件已上传native预发布依赖，GitHub摘要核对通过；旧客户端更新通道仍未改动。各工作区使用新版本独立录制缓存，旧缓存保留。新Apple工作流未在默认分支注册，改由已注册FFmpegKit Apple工作流的player-only入口执行；源码验证后再触发。


## Apple平台分架构校验

24a6836e云运行的录制Build、Check and hash及录制artifact上传成功，后续播放器失败不作为录制包失败或客户端通过的证据。播放器iOS编译暴露avfoundation自动检测选中macOS专用音频代码；iOS明确禁用该后端，保留AudioUnit。改为五个独立slice任务并行构建，再严格核对同一源码、工具链、最低系统和每个二进制SHA后组合通用框架；不足五个或来源不一致拒绝组装。

5.7.0本地集成首轮全部测试通过，仅Downloads URI代码的一条多行if风格检查未通过；已补block。新增组装契约测试覆盖缺slice、跨源码和字节变化；重新通过静态检查后再跑完整门禁。
