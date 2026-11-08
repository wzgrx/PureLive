# S01.3 CI 上设置页总览卡在录制页：记录

- 日期：2026-11-06
- 执行者：Claude（本机没有 Flutter；临时下载了 toolchain.env 对应的 3.13.7 Dart，只用于 `dart format -l 120` 自检，不进仓库、不入 PATH）
- 分支和提交：master，标题以 `[S01.3]` 开头
- 任务书：无（小任务）；设计或说明：[README.md](README.md)

## 逐条对照

| 编号 | 做了没有 | 偏差和原因 |
|---|---|---|
| 诊断 | 做了 | `settleSettingsFiles(tester, {where})` 加段名、转圈数、`hasScheduledFrame`、途经 `ValueKey` 与该行文字；判定条件与等待次数一字未放宽 |
| 探测 | 做了 | 同一用例里在 `runAsync` 窗口对 `recordDirectory()` 与递归 `list` 各加 3 秒上限，走不完报 `not resolved` |
| CI 系统库 | 做了 | 按 `ldd` 报告补齐 mpv 的运行期依赖；包名逐个安装以容忍 t64 改名 |
| 撤掉的错判 | 做了 | `$HOME` 下载 libmpv 的步骤删除（hook 本来就放了）；`pumpSettings` 里那句 `loadSettings()` 回退（录制页 `_load` 自己会调） |

## 排查过程（按 CI 轮次，全部有 run 号可查）

| run | 结论 |
|---|---|
| 42175455033 | 你那条 `ci` 提交其实触发了 CI，红在 `dart analyze` 的 `comment_references`（A07.44 我自己写的文档注释） |
| 42177642502 / 42180083219 | analyze 修好后露出设置页总览超时，两次同处，非偶发 |
| 42182177555 | SDK 挪出 `$RUNNER_TEMP` 无效 → dataRoot 猜测排除 |
| 42183189317 | `recording service: there`、`status views: none` → 不是页面级加载卡片 |
| 42184150884 | `dart format` 拦在我新加的诊断代码（嵌套函数声明后要空行）；本机 3.13.7 + 120 列复检，确认只有这一处 |
| 42184739481 | `settings-row-busy`、「已占用」→ 锁定 `record-used-space` 行的 `_measuring` |
| 42193472812 | 只剩 `packages/live_player test` 红：libmpv 已就位，缺 `libva-drm.so.2` |
| 42196958763 | `ldd` 报告点名 `libXv.so.1`、`libva-wayland.so.2`、`libvdpau.so.1` |
| 42200886546 | `gate: passed (all, 14 members)` |

## 改了哪些文件

- `.github/workflows/test.yml`：按固定 revision 检出 SDK 并应用语义补丁、系统库清单、失败时的 `ldd` 报告
- `apps/pure_live/test/features/settings/settings_harness.dart`：`settleSettingsFiles` 的诊断信息
- `apps/pure_live/test/features/settings/settings_page_test.dart`：段名标签与 IO 探测
- `apps/pure_live/lib/features/live_play/live_play_page.dart`：文档注释引用修正（属 A07.44）
- `docs/tasks.toml`、`docs/inventory/OWNERS.{toml,md}`、`docs/STATUS.md`、`docs/TASKS.md`、S 组与 A07 页面、S01.3 任务文件夹

## 新设置、翻译键、门禁基线

- 本任务无新设置、无翻译键、无门禁基线改动（A07.44 的那一条见其 record.md）。

## 测试

- 未新增用例；改的是脚手架可见性与 CI 环境。最终由 CI 验证：`gate: passed (all, 14 members)`，含 `docs --check`、`owners --check`、14 个成员的 format/analyze/test 与 `gate tests`。

## 真机上要看的

- 无（测试基础设施）。A07.44 的真机项仍在其 record.md 里待验。

## 停在哪（没做完时写）

- 做完了。遗留两点写在 README 的「留下的问题」：探测是否顺带推进了事件循环未分离；`storage:` 探测代码是否长期保留。
