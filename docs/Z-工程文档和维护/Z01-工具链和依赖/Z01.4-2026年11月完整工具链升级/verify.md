# 本轮验证边界

| 层次 | 结果与范围 |
|---|---|
| 源码 | Flutter3.50/Dart3.14及直接依赖迁移；完整主题、窗口归属、URI和静态JNI修正；官方SDK补丁精确revision/字节校验 |
| 测试 | 最近8bdd395b完整all/14通过；最终Apple清单集成后仍须再次完整门禁。SDK七项原断言在隔离环境执行，无图像断言被跳过 |
| 原生 | Android3ABI/API26导入和16KB；Linux/Windows真实本地及HTTPS；Apple五slice同源及公开下载/hash/最低系统通过 |
| 正常运行 | 自有API27 profile与实际minified signed release正常HLS；Windows无插桩两次SW_HIDE冷启动及正常窗口HLS；隔离Linux首页和HLS |
| 录制 | Android/Windows真实Flutter绑定PCM→WAVE；Android另有minified release同项；Linux使用应用捕获/分段/合并实参产生有效H264/AAC MP4 |
| Apple客户端 | 等待最终冻结提交的Mac与iOS模拟器正常入口、录制/播放探针、精确包启动验证 |
| 原场景 | ARM手机、电视遥控/硬件解码、原iPhone/iPad及受影响登录账号未在本轮操作，不沿用其他环境结果作为原问题验收 |

详细安装包/源SHA和截图保存在维护者本地本轮输出；正式发布仍需十包远端与完整公开下载核对。
