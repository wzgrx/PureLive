# 审查

范围为D-092公开需求和回放恢复、本轮具体bugs及正式交付。UI继续A15.5原控件和小窗。原生库prerelease附件是锁定依赖，不能作为无用客户端版本移除。发布后只关闭已交付事项；尚未确认的硬件根因不假称已修复。

技术依据：Inno CloseApplications与Windows Restart Manager协议：https://jrsoftware.org/ishelp/topic_setup_closeapplications.htm 、https://learn.microsoft.com/en-us/windows/win32/rstmgr/guidelines-for-applications 。Huya当前BadgeInfo仅本客户端消费name/level，官网对象定义与动态资源：https://a.msstatic.com/huya/main3/common/headerfunction_83b33233.js 。mpv精确定位语义：https://mpv.io/manual/stable/#command-interface 。研究快照保留本机输出，完整第三方JS不入仓库。
