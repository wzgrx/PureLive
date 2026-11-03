# 审查

范围为D-092公开需求和回放恢复、本轮具体bugs及正式交付。UI继续A15.5原控件和小窗。原生库prerelease附件是锁定依赖，不能作为无用客户端版本移除。发布后只关闭已交付事项；尚未确认的硬件根因不假称已修复。

技术依据：Inno CloseApplications与Windows Restart Manager协议：https://jrsoftware.org/ishelp/topic_setup_closeapplications.htm 、https://learn.microsoft.com/en-us/windows/win32/rstmgr/guidelines-for-applications 。Huya当前BadgeInfo仅本客户端消费name/level，官网对象定义与动态资源：https://a.msstatic.com/huya/main3/common/headerfunction_83b33233.js 。mpv精确定位语义：https://mpv.io/manual/stable/#command-interface 。研究快照保留本机输出，完整第三方JS不入仓库。

## 5138：原生回归发现并处理跨HLS断点定位

5137候选源44d2c004的完整门禁和十包构建完成，但没有正式发布。Android API28软件解码回归复现#163：time-pos报告目标，缓存/解码仍留在原处。保留旧候选、失败画面与全部原始记录，不能把该候选当作已完成修复。

同一虎牙公开回放清单包含33处EXT-X-DISCONTINUITY。FFmpeg9.0.2直接定位3905秒在40秒限制内不产出画面，读取日志从正确目标分片继续扫描；该分片单独HTTP读取正常。保留同一清单，从3898.8秒附近分片起建立入口，内部仅定位6.2秒，约1.53秒完成解码。这支持HLS重置时间戳的定位路径是本次触发条件；不据此断言所有虎牙/CDN故障根因相同。

5138新增有界清单解析与分片入口，完整进度=入口偏移+原生进度。恢复、拖动和切清晰度统一重建入口，保持暂停/音量/倍速。入口使用既有HLS中继，分片保留请求头、TLS和站点代理；只对该回放输入放宽到最多50001条索引，默认直播中继上限不变。每房间至多两个替换中的路由，重开完成即释放旧路由，退出释放全部。未支持的加密/范围/初始化段清单明确报错，不擅自剥除标签。全局seek模式恢复原实现。

新增纯解析、长清单早期目标、完整时钟与暂停/倍速/音量、分片请求头、旧入口失效和延迟请求退场测试。定向分析和回放回归通过；5138完整门禁、最终原生回归和全平台重建继续执行，完成前不公开发行。
