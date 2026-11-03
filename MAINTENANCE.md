# 当前维护方针

生效：2026-11-03，依据维护者直接决定D-092。恢复接收功能需求、维护者开发和公开直播回放维护；此前功能冻结与回放停维公告已撤销，历史决定仅保留追溯。

## 功能需求与bug

- 用户可以通过GitHub功能需求表单请求新增功能、平台、设置或操作优化，不要求先提供实现或PR。
- 说明使用场景、涉及平台、期望操作和参考资料。先搜索已有及已关闭issue，一条issue聚焦一个主题。需求会评估可行性、维护成本和优先级，不以提交即承诺排期。
- 已有功能bug、崩溃、卡死、兼容性、资源泄漏和数据安全继续优先处理；性能问题尽量附复现或测量。
- 斗鱼、虎牙、哔哩哔哩公开直播回放继续维护，沿用现有直播间横竖屏、小窗与共享播放器体系增强。平台未公开或账号无权限的内容不伪装成已支持。
- 因旧停维决定关闭的回放问题重新评估，验证修复或交付后再按completed关闭；不能把恢复维护本身说成bug已修复。

## 贡献与验收

欢迎提交PR，也欢迎仅提交需求。不以使用某一AI模型作为需求受理门槛；贡献者说明实现、设计和实际验证材料即可，工具或模型声明可帮助审查，但不代替质量验收。

UI变化附设计或前后截图、受影响布局与焦点/大字/加载/错误等状态；代码说明默认值、升级兼容和维护成本，附合适回归。正式交付要求完整门禁、同源包验证、发布附件和更新源校验。没有原设备证据时如实保留验证边界。

旧的明确拒绝或原设备暂缓决定不因开放需求自动取消；有新证据或维护者明确新决定再评估。安全漏洞按SECURITY.md私下反馈，不公开Cookie、令牌、密码或个人资料。

English: Feature requests and maintainer-led development are open again. Users may request features without providing a PR. Public replay support is maintained using the existing room UI and playback ownership. Requests and contributions are reviewed for feasibility, quality, compatibility and validation; acceptance does not guarantee a schedule. Historical deferred or explicitly rejected reports remain governed by their specific decisions.
