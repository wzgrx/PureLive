# 当前维护方针

**本轮明确例外（D-089，2026-11-02）：维护者已直接授权C03.4的斗鱼、虎牙、哔哩哔哩公开回放、入口与倍速设计实现，以及D01.37的匿名昵称和常驻提示修复。该范围按本轮指令执行；不据此恢复其他功能队列。**

生效：2026-11-02。依据维护者明确决定（D-088）；本页优先于旧路线图、功能任务书和继续扩展功能的安排。

## 维护范围

- 暂停受理新功能需求和主动功能开发。后续维护集中于已有功能的 bug、崩溃、卡死、兼容性、资源泄漏、数据安全和稳定性；性能问题须有可复现的退化或测量依据。
- 不再按旧功能清单自动补齐功能、增加开关、平台或客户端。旧任务的历史实现与验证记录保留；未交付的新功能暂停，恢复须维护者明确决定。
- **直播回放功能停止维护和更新**：斗鱼、虎牙等平台的历史直播回放解析、列表、播放适配和扩展不再由维护者开发；相关需求和回放专项 bug 统一说明后以 `not_planned` 关闭，不宣称问题已修复。
- 本次保留现有回放代码、入口、用户数据及历史发行版本。停维不表示删除功能，也不承诺现有入口持续可用。该范围不等同于电视普通点播、音乐或本机录制管理；共享播放器若影响正常直播或核心稳定性，仍按核心 bug 评估。

## Issue 处理

- 保留直播、弹幕、登录、IPTV及核心应用的 bug 和稳定性反馈入口。按正文和复现情况判断，不仅看 `enhancement` 标签或标题。
- 未附完成实现的新功能请求，回复本方针并以 `not_planned` 关闭，不建立维护者待开发承诺。
- 已关闭的回放讨论补充停维通知。以前确实实现并发布的历史需求保留原完成记录；尚未实现的需求和未修复的回放 bug 不标记为完成。
- 关闭后追加新功能需求仍按同一方针处理；不锁定讨论，不删除原始报文、复现步骤和历史回复。

## 新功能只能由需求方提交完成的 PR

1. 需求方自行完成 UI 设计与代码实现，再提交可审查的 PR；维护者暂停代为设计、实现和补完功能。
2. **UI 设计和代码实现均须使用 Opus 5.5 的 high 档，或更高规格模型。** 这是维护者指定的贡献准入要求。PR须写明实际使用的模型、版本、推理档位和用途，未达到要求或未声明的功能 PR 暂不受理。
3. 有界面的功能须附设计说明及实现前后截图，覆盖竖屏、横屏、桌面/电视等受影响布局，以及空、加载、错误、大字和焦点等相关状态。无界面变化须说明。
4. 代码须范围清楚、可以独立合并，说明依赖、设置默认值、升级兼容和维护成本；附适当回归测试、完整门禁结果及实际平台验证材料。不能只提交方案、截图或半成品。
5. 模型声明由贡献者提供，维护者结合设计、代码和验证材料审核；声明本身不等于质量验收或合并承诺。提交 PR 后等待维护者后续审核，不保证排期或合并。回放类 PR 也适用，停维决定不会因有人提需求而自动撤销。

Bug 修复、稳定性修复和文档贡献继续按 [贡献规范](CONTRIBUTING.md) 审查；上述模型门槛针对新功能 PR，不把 bug 标签当作绕过功能冻结的方式。

English: Feature requests and maintainer-led feature development are paused. Maintenance focuses on bugs and stability. Historical live-stream replay support is unmaintained, including replay-specific fixes and platform updates. Keep existing code and data. New features require a complete contributor-owned PR: both UI design and implementation must use Opus 5.5 at high reasoning effort or a higher-specification model, with a model declaration, UI evidence, tests and reviewable code. Maintainer review and merge are discretionary.
