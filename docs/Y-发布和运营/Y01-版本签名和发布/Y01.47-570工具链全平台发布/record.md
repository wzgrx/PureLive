# 发布记录

2026-11-25：由新的维护者升级并发布指令接续，不复用5.6.6旧自动发布入口。当前发布候选源代码包含852d90369之前已保存的工作；新增工具链迁移和原生兼容变更见Z01.4。仍在候选验证阶段，尚未公开客户端。


## 最终输入准备

全部现有目标已具备mpv0.42和录制FFmpeg9.1的哈希固定输入，Windows播放使用官方自带FFmpeg快照并单列。Apple公开归档五架构及实际最低系统核对完成；Android三正式签名预检包、压缩后的正常播放/录制，及Windows/Linux隔离运行通过。进入最终同一源码十包阶段，旧5.6.6自动发布hold和原设备/账号未验收记录保留。


## 2026-11-26正式交付
5.7.0+5146正式交付：冻结程序源码`73f6e420162c0f149fa68c295511d7a378337f34`，PR#250合并`c9126f2510a8fadf09ab09ac7bda61d72f41aad0`，十包与SHA256SUMS本地/草稿/匿名公开完整下载一致。旧更新源PRhttps://github.com/wzgrx/pure_live/pull/44，仅两JSON。基线5项、最终5项归档版本页失败；旧解析/比较/选包和全部历史保留通过，现代完整all14仍执行。原设备/账号反馈保留独立验收状态。

归档基线失败：
- features/version/version_page_test.dart: reads the repository update files as 3.x does
- features/version/version_page_test.dart: shows the failure and checks again on retry
- features/version/version_page_test.dart: the release history lists releases and opens one
- features/version/version_page_test.dart: U.12b the start-up check and the version page tell the about page about a newer version
- features/version/version_page_test.dart: U.12b history: "版本历史", "最新" and "当前", no file size; close at the top right (c2, c11, c12)

归档最终失败：
- features/version/version_page_test.dart: reads the repository update files as 3.x does
- features/version/version_page_test.dart: shows the failure and checks again on retry
- features/version/version_page_test.dart: the release history lists releases and opens one
- features/version/version_page_test.dart: U.12b the start-up check and the version page tell the about page about a newer version
- features/version/version_page_test.dart: U.12b history: "版本历史", "最新" and "当前", no file size; close at the top right (c2, c11, c12)

本次界限：按维护者既有自主维护委托，仅更新两JSON；本次例外不覆盖未来版本，不声称存在新的逐版人工确认。
Windows实际正式便携、Linux正式归档、Android压缩签名包均在生成数据环境运行正常首页和持续HLS视频；Apple同源构建、模拟器/原生探针及两次精确Mac包启动分别记录。实体ARM/TV/iPhone及特定账号未在本轮操作。


### 最终证据及覆盖界限

- [正式发布十包与校验文件](https://github.com/wzgrx/PureLive/releases/tag/v5.7.0)、[源码合并PR250](https://github.com/wzgrx/PureLive/pull/250)、[旧更新源PR44](https://github.com/wzgrx/pure_live/pull/44)。十包和SHA256SUMS.txt均完成匿名完整下载，合计1,041,131,877字节，与本地冻结产物逐字节摘要一致。发布标签固定到73f6e420162c0f149fa68c295511d7a378337f34。
- [同源Apple客户端构建与启动验证](https://github.com/wzgrx/PureLive/actions/runs/45652031236)整体成功，包含两次精确Mac包启动复验；[最终附件转存](https://github.com/wzgrx/PureLive/actions/runs/45666892511)成功。Apple录制与音频播放探针通过，iOS分享图仅覆盖系统确认弹窗，不等同真实房间交接；Apple视频渲染和实体设备未在本轮验收。
- Android实际正式签名混淆x64包在全空自有模拟器完成首页和连续HLS视频，另外的真实录制探针输出有效WAVE；三个发布ABI的签名、版本、ZIP/ELF16KB和原生字节来源分别核对。实体ARM手机及TV未验收。
- Windows实际正式便携包和Linux正式归档在独立生成数据环境完成首页与连续HLS视频。Windows安装器编译和同源负载检查通过，未运行安装器更改正式安装。Linux完整客户端glibc2.38/GLIBCXX3.4.32要求与5.6.5分发插件相同。
- 工作区直接依赖已到兼容的当前官方版本；cli_util、coverage、cross_file、material_color_utilities、package_config、vector_graphics_compiler六个间接依赖仍受SDK/上游约束，未强制跨不兼容版本。原账号、原设备、PiP和其他未复现反馈保留各自验收状态。
- 程序发布后本收尾只修改docs/和两份更新JSON；不重新构建或替换任何公开客户端。双更新源公开读回另在合并后检查，失败时继续修复通道，不能据本记录宣称完成。
