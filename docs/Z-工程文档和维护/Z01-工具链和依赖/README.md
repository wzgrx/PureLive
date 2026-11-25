# Z01 工具链和依赖

`toolchain.env` 是工具版本来源，pub workspace 的 14 个成员共用根锁文件。当前升级和验收见 [Z01.3](Z01.3-全端工具链与依赖重新核验升级/README.md)，历史迁移及保留原因见 [Z01.2](Z01.2-例行依赖升级检查/record.md)。

## 2026-10-26 重新核验

Flutter 3.47.8 / Dart 3.13.7；Gradle 9.8.2、AGP 9.4.1、Kotlin 2.4.21；Temurin 27.0.1.0.2+1。Android compile SDK 37.2、build-tools 37.0.0、NDK 30.0.16248370、platform-tools 37.0.1、cmdline-tools 23.0、SDK CMake 4.1.2 保持官方当前稳定版本。mpv 0.41.0、FFmpeg 9.0.2 和自维护播放器上游提交未改变。

Linux 使用官方正式 Clang 23.1.4；桌面登记独立 CMake 4.4.4、Ninja 1.13.2、Visual Studio 18.11.2、Inno Setup 7.1.0；Flutter Windows 实际使用最新 Visual Studio 自带的 CMake 4.3.1-msvc1，而非 PATH 上的独立 CMake。项目脚本使用独立 Python 3.15.2。Apple 工作流选择 `xcode-27` 镜像中固定的正式 Xcode 27.1、CocoaPods 1.17.0，拒绝自动选中较新的 RC。Apple 原生构建仍待本次源码完整门禁后执行。

官方检查器共 75 项，落后 0、查询失败 0；查询失败现在退出非零，Android 稳定包按 channelRef 与 preview 判定。直接依赖升级 10 项，锁文件调整 48 项；5 个传递依赖受 SDK/依赖自身约束保留，没有用无依据的覆盖强行提高版本。

## 关键兼容约束

- Flutter 的已合并语义树修复仍按 [tools/flutter_sdk](../../../tools/flutter_sdk/README.md) 的版本和文件哈希核验，在独立 SDK 应用；共享旧 SDK 保留。
- screen_retriever 0.3 改为 nativeapi，显示器句柄不能跨启动保存。应用使用即时快照和持久显示器键，旧小窗坐标按当前工作区验证后保留。最新 window_manager 0.5.2 的唯一显示器工具函数随本地 MIT 分支迁移，原生窗口实现保持上游版本；来源和完整补丁范围在 third_party/window_manager/PURELIVE_PATCH.md。
- 录制 FFmpeg 的 Dart/原生 ABI 配套和原有包哈希不变；不能因包名版本相同假定 ABI 相同。
- Inno Setup 通过预处理器实际版本校验，缺失或不匹配直接失败；用 `PURELIVE_ISCC` 或打包脚本 `-Iscc` 指定独立安装。旧用户数据不进入包。

## 验证和维护

`dart run tools/check_latest/bin/check_latest.dart` 查询官方稳定源；私有 GitHub 令牌仅通过进程环境提供。`--report-only` 只供报告，不作为成功门禁。修改前失败的 Android 预发布选择回归已保留，更新后 8 项检查器测试和 53 项桌面/小窗测试通过；14 个成员静态分析通过。完整 all/14、Android/Windows/Linux/Apple 最终构建与原生操作验证分别记录，不能互相替代。

<!-- docs:生成开始（下面由 tools/docs/docs.py 根据 docs/tasks.toml 生成，不要手改） -->

## 登记的任务和进度

属于 [Z 工程文档和维护](../README.md)。

- 代码：`toolchain.env`、`tools/check_latest/`
- 进度：`███████████████████░` 96%


| 编号 | 任务 | 类型 | 状态 | 日期 | 提交 | 资料 |
|---|---|---|---|---|---|---|
| Z01.1 | 工程底座：工具链、门禁、代码规范 | 工程 | 完成 | 2026-09-28 | 4aaeb0fda | [设计或说明](Z01.1-工程底座/README.md)、[记录](Z01.1-工程底座/record.md) |
| Z01.2 | 例行依赖升级检查（每月用 check_latest 查一次，升级后跑门禁） | 工程 | 开发中 | — | — | [设计或说明](Z01.2-例行依赖升级检查/README.md)、[任务书](Z01.2-例行依赖升级检查/brief.md)、[记录](Z01.2-例行依赖升级检查/record.md) |
| Z01.3 | 全端工具链与依赖重新核验升级 | 工程 | 完成 | 2026-10-27 | bf25cffced2050d27bb3db85aa0d62c47fbfd7ee | [设计或说明](Z01.3-全端工具链与依赖重新核验升级/README.md)、[任务书](Z01.3-全端工具链与依赖重新核验升级/brief.md)、[记录](Z01.3-全端工具链与依赖重新核验升级/record.md)、[真机验证](Z01.3-全端工具链与依赖重新核验升级/verify.md)、[合并审查](Z01.3-全端工具链与依赖重新核验升级/review.md) |
| Z01.4 | 2026年11月完整工具链升级 | 工程 | 完成 | 2026-11-26 | c9126f2510a8fadf09ab09ac7bda61d72f41aad0 | [设计或说明](Z01.4-2026年11月完整工具链升级/README.md)、[任务书](Z01.4-2026年11月完整工具链升级/brief.md)、[记录](Z01.4-2026年11月完整工具链升级/record.md)、[真机验证](Z01.4-2026年11月完整工具链升级/verify.md)、[合并审查](Z01.4-2026年11月完整工具链升级/review.md) |

## 还没完成的

- **Z01.2 例行依赖升级检查（每月用 check_latest 查一次，升级后跑门禁）**（开发中，第三档，规模 小）
  - 接着做：2026-10-20 升级了 Gradle 9.8.2、go_router、hive_ce、material_ui、tray_manager 0.8、open_filex 5、ffmpeg_kit 1.0、media_kit 上游；screen_retriever 0.3 等 window_manager 跟上；下次 2026-11 上旬

<!-- docs:生成结束 -->
