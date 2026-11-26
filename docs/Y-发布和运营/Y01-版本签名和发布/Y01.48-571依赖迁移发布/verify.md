# 验证

待记录分层验证：源码/API回归、完整门禁、各平台构建、隔离运行及公开字节校验。原设备和账号问题不因升级自动完成。


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
