# 固定 Flutter 语义树修复

Flutter 3.50.1 的固定 revision 和补丁 SHA-256 记录在 `toolchain.env`。`flutter-193372.patch` 原样来自 Flutter 官方合并提交 [b304cf18b6864d141cf08e26a07898901cddb4b5](https://github.com/flutter/flutter/commit/b304cf18b6864d141cf08e26a07898901cddb4b5)，许可证见 `LICENSE.flutter`，范围仅语义更新及其官方测试。背景和应用对照见 X01.4；不包含未合并的 190344 或 190903，不关闭无障碍功能。

先在独立 SDK 副本中显式准备，再运行门禁和构建；保留原共享 SDK：

```sh
python3 tools/flutter_sdk/prepare.py --apply --bootstrap-tests --sdk /path/to/isolated/flutter
export FLUTTER_ROOT=/path/to/isolated/flutter
export PATH="$FLUTTER_ROOT/bin:$PATH"
python3 tools/flutter_sdk/prepare.py --test
bash tools/gate/gate.sh --all
```

Windows 可用 Python 运行同一脚本并传入独立 SDK 的路径，然后把该 SDK 的 `bin` 放在 PATH 最前。Apple 云构建在固定版本安装后显式准备同一补丁。`--check` 是默认行为；门禁检查并执行官方七项回归，不修改 SDK 源码。脚本核对基线 revision、完整补丁字节、两个目标文件修改前后经 LF 归一化的 SHA-256；遇到额外 tracked 改动、部分应用或未知内容立即拒绝。

升级稳定版时须重新检查官方是否已包含修复，一并更新版本、revision 和这套策略，再执行全仓库门禁、构建与原生交互验证；不要把本补丁强行应用到别的 SDK 版本。

2026-11-25：3.50.1官方源码可干净应用同一上游补丁；先只加入官方回归，在未修源码上复现失败，再应用源码修复并跑完整同一文件。策略固定新版revision和修改前后哈希，原3.47.8 SDK保留。

`--bootstrap-tests`显式生成SDK测试依赖缓存：只允许固定revision的原始lock或已校验的Dart 3.14 SDK下限变化，并恢复原lock字节；出现其他依赖变化保留现场并拒绝继续。门禁使用`--no-pub`运行测试，不隐式重解析SDK依赖。


## 离线语义回归

--test 在临时目录执行逐字节复制的上游语义测试与其按钮辅助代码。保留 SDK 的布局、命中和可选泄漏检查，仅移除该非图像测试不使用的 Skia Gold 网络初始化；检测到图像断言或未知 SDK 配置立即拒绝。SDK 源码和测试断言不变，不使用跳过测试的 CI 环境标记。SDK 原配置在注册语义测试前请求 Gold，TLS 故障会表现为测试加载握手失败；隔离后无需访问 Gold。
