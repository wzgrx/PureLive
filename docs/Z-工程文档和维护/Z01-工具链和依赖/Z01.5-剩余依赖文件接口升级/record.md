# 记录

2026-11-26：从干净5.7.0主分支开始；前序隔离试验确认五包可兼容，cross_file0.4在分享代码中有十处实际编译错误。以此为修复前证据，按上游迁移方案移植稳定版消费者。


## 2026-11-26迁移实现

从06bd8290d的5.7.0开始。六依赖已全部解算至最新发布版，额外检查并纳入AGP9.5.3和flutter_svg2.5.1。Android官方元数据经直连验证，NDK30/SDK37.2/build-tools37/platform-tools37.0.3/cmdline23/CMake4.1.2保持当前官方稳定版；代理TLS失败原日志保留，不当作版本已验证。

九个稳定版文件/分享消费者复制上游发布源并保留许可；runtime选择性移植file_picker PR2300的cross_file0.4变更。Linux/Windows保留13.x的可选bytes元数据接口（旧XFile的path构造本就不读取这些bytes）；Web保留13.x缓存和流选项。没有将14.0未发布分支整体引入。share_plus使用异步文件名、FileSystem/ScopedStorage分流、受限文件流式复制和安全文件名；原有native渠道及取消结果保留。

先前隔离环境的十处实际编译错误作为修复前证据。新增八项文件与分享回归后，读取失败触发重复close并掩盖原错误，修复后八项全部通过。应用静态分析通过；原有项目测试未删除。上游示例和测试的原件保留在本机审计目录，发布runtime copy不包含未迁移的上游示例，其行为由项目回归覆盖；准确runtime/pubspec差异和哈希写入每个包的PURELIVE_PATCH.diff与消费者清单。

原生录制探针扩展实际cross_file本地读写与流比较；Android使用本应用FileProvider的生成content URI，Apple使用本容器生成文件的scoped URL，均释放作用域引用。仍需同源平台构建/原生执行通过后才接受客户端交付。


完整门禁首轮捕获版本同步遗漏：pubspec已5.7.1+5147，但无Flutter编译常量时的备用pubspecVersion/pubspecBuild仍5.7.0+5146，导致版本元数据与测试安装包身份不一致。同步两处应用常量，保留六项原始失败日志，不删除或放宽版本/身份测试；重新执行完整门禁。


## 原生Android复验与第二候选

首轮ec3d34316917f33137ed0982e8b44cb5c33d450d的十包候选保持未公开，已构建及私有字节证据保留。实际Android API27混淆包确认FileProvider URI内容/长度/名称正确但canRead=false；20次读取FD80→100。不能把解算/桌面通过当作Android通过。

新增cross_file_android1.0.0局部适配，保留许可证/版本并生成双端close桥接；正常DocumentsContract路径保留，非文档提供者通过真实受权限约束的开闭流判断可读/存在，避免不存在子文件仅因元数据行而误报。所有读取出口finally关闭。八项新生命周期回归加原八项共16项通过，应用分析通过。

在冻结前先运行实际混淆包修复预检：元数据、可读/存在、字节一致、范围/完整/提前取消、缺失URI拒绝均通过；20次读取及其他检查后FD79→79。该预检记录明确为提交前输入哈希证据；第二候选仍需完整门禁及同源十包重建和原生验证。未放宽原失败断言。


## 5.7.1正式交付

冻结客户端源码`30847927035f963513d36338f591f24bd67b02b5`，源码PRhttps://github.com/wzgrx/PureLive/pull/252合并`255616634b714f3790758b5032d60e00b6dc40e2`；正式版本https://github.com/wzgrx/PureLive/releases/tag/v5.7.1。十个客户端及SHA256SUMS完成本地/草稿/匿名公开完整字节核对，全部历史记录和完整性清单保留。源码之后本收尾仅更新docs/和两份更新JSON，不替换公开安装包。

全部六依赖与AGP9.5.3/flutter_svg2.5.1/isolate_channel0.6.3升级；十个本地消费者保留上游版本、许可和精确补丁。Android原生诊断在发布前捕获canRead误判及FD80→100；修复后真实混淆包可读/存在/名称/长度/数据、范围/取消/批量、缺失URI拒绝及FD稳定检查通过。原断言保留。Windows/Linux真实文件和录制API通过；Apple同源客户端CI45734676884完整成功、两次精确Mac包启动和iOS/Mac真实文件/录制探针通过。

Windows正式便携、Linux正式归档与Android签名混淆x64包在生成数据环境进入首页及持续HLS视频。Windows安装器未执行更改正式安装；Apple实体机、外部文档授权和视频渲染仍保留独立实测边界。旧设备/账号问题不会自动完成。

旧更新源https://github.com/wzgrx/pure_live/pull/45仅两JSON。完整基线复用的是已逐项核对源树/更新文件/原日志摘要的相同输入，未重复执行完整基线；本次候选完整门禁与旧解析/版本比较/选包/所有历史保留检查另行执行。完整日志的失败汇总均为6项，但截断的错误上下文只列出5个名称，因此又分别以新旧更新数据执行版本页专项复验，取得完整6个相同失败名称，无新增。基线6项、候选6项失败如下。按维护者既有自主维护及本次发布委托记录D-098，例外只限本次5.7.1旧库两文件，现代完整all14仍须通过，不声称新取得逐版人工确认。

基线失败：
- features/version/version_page_test.dart: reads the repository update files as 3.x does
- features/version/version_page_test.dart: shows the failure and checks again on retry
- features/version/version_page_test.dart: the release history lists releases and opens one
- features/version/version_page_test.dart: U.12b the start-up check and the version page tell the about page about a newer version
- features/version/version_page_test.dart: U.12b history: "版本历史", "最新" and "当前", no file size; close at the top right (c2, c11, c12)
- features/version/version_page_test.dart: the release history shows both panes on a wide window

候选失败：
- features/version/version_page_test.dart: reads the repository update files as 3.x does
- features/version/version_page_test.dart: shows the failure and checks again on retry
- features/version/version_page_test.dart: the release history lists releases and opens one
- features/version/version_page_test.dart: U.12b the start-up check and the version page tell the about page about a newer version
- features/version/version_page_test.dart: U.12b history: "版本历史", "最新" and "当前", no file size; close at the top right (c2, c11, c12)
- features/version/version_page_test.dart: the release history shows both panes on a wide window

2026-11-26 计数更正：D-097及5.7.0收尾记录的“5项”来自门禁截断错误片段的名称提取；原完整基线和候选日志的最终汇总实际均为6项。本次逐项核对原日志摘要，并以新旧更新数据专项复验确认6项相同版本页失败，无新增。原记录保留，实际计数以本条及D-098为准。
