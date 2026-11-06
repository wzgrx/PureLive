# S01.3 CI 上设置页总览卡在录制页

`Test` workflow 建立后第一次跑就红在 `settings_page_test.dart` 的 overview 回退链：`settleSettingsFiles` 等 IPTV/录制/备份页处理完本地读取，10 次 × 真实 1 秒后放弃。断言一条没失败，纯粹等不到。原来的失败信息不说明卡在哪一步，所以先补信息，再按结果定位。

诊断信息（run 42184739481）给出：`recording service: there`、`status views: none`、`1 spinner(s)`、`settings-row-busy` 且该行文字是「已占用」——即 `record_settings_page.dart:367-371` 的 `record-used-space` 行，`busy: _measuring` 一直没落地，也就是 `_refreshStorage()` 里的 `recordDirectory()` 与 `sizeMB()` 没有走完。同一轮还在 `runAsync` 窗口里对这两个 await 各加 3 秒上限做探测，走不完就报 `not resolved`。

此后 `Targeted tests` 连绿三轮，`Full gate` 的 `apps/pure_live` 全量也绿。没有排除的一种可能是：探测本身把那两次 IO 推进了事件循环。等待逻辑没有放宽（仍是 10 次 × 1 秒，判据不变），若日后重现，`storage:` 字段会直接给出目录路径和条目数。

## 顺带补上的 CI 环境缺口

`Full gate` 真跑起来后唯一还红的成员是 `packages/live_player test`。原因不在代码：media_kit 的 build hook 把 `libmpv.so.2` 放进 `packages/live_player/build/native_assets/linux/`，而这个库链接的系统库 runner 镜像不全，第一次 `dlopen` 就失败（`libva-drm.so.2: cannot open shared object file`）。按新增的 `ldd` 报告逐个补齐：`libva-drm2`、`libva-x11-2`、`libva-wayland2`、`libva2`、`libvdpau1`、`libxv1` 以及其余 mpv 运行期依赖；包名逐个安装以容忍 Ubuntu 的 t64 改名。同时撤掉早先基于错判（以为要靠 `LD_LIBRARY_PATH` 提供 libmpv）加的 `$HOME` 下载步骤。

## 结果

run 42200886546：`gate: passed (all, 14 members)`，`Full gate: success`。其中也包含本任务之前同步的生成文档——`docs --check` 与 `owners --check` 都通过。

## 留下的问题

- 录制页那一行为什么原本等不完：探测的作用未分离，若重现按 `storage:` 报告继续查。
- `settleSettingsFiles` 里的探测代码要不要长期留在测试脚手架中：目前它只在失败时输出信息，不影响判定，保留成本低。
