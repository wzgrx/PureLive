# E02.16 / D01.38 验证记录

2026-11-04，本机生成数据的 Android API37 模拟器（WebView 145.0.7632.218），仅 com.mystyle.purelive.v4dev，未使用物理手机或账号登录。

- 游客分类7个；推荐第一页27个、第二页27个；广播ID保持字符串；进房在播、画质1档。
- 临时游客页退出后，原生RWP认证/注册/进房确认成功；35秒内实际收到2条文本聊天、6次在线更新、6次累计更新；没有异常断开；显式退出正常。
- 在默认WebView资料区放入的合成 example.invalid Cookie 在游客初始化后仍保持不变。Android使用独立固定资料区；每次操作前后以带完成回调的 WebStorageCompat 清除该资料区数据，不清默认Cookie、账号库或其他资料区。
- 原生联调首轮因测试模拟器缺少ACCESS_LOCAL_NETWORK权限、无法到测试代理而超时；仅为该隔离测试包补齐权限后，分类链路成功。随后修正了已加载资料区不能直接deleteProfile的生命周期问题，连续目录和弹幕初始化复验成功。失败过程保留在外部证据目录。
- 纯合成测试覆盖分页尾游标、分类/刷新隔离、64位ID、异常不是空列表、取消、文本/人数区分、批次容错、订阅确认、去重、退出及一次认证更新；不访问真实平台。完整全仓门禁的最终结果见本分支PR和外部gate-all.log，不以本记录替代门禁日志。

边界：本次未在物理Android/电视/Apple真机上验收；Windows/macOS/iOS复用既有WebView后端但新游客链路仍需平台实测；Linux无既有WebView后端，保留分享链接播放，游客目录/弹幕不宣称支持。旧Android WebView须具备MULTI_PROFILE、DOCUMENT_START_SCRIPT、WEB_MESSAGE_LISTENER、DELETE_BROWSING_DATA；缺失时明确失败，不能退回共享资料区。

未实现：关键词全站搜索、账号互动、主播跨场稳定追踪及小红书官方回放目录。原分享页受限检查和CDN流地址校验保留。发布版本、version.json、releases.json均未修改。

外部证据目录：outputs/purelive-xhs-20261104（native-acceptance.json、core-tests.log、danmaku-tests.log、browser-tests.log、app-tests.log，最终全仓日志gate-all.log）。原生验收使用独立入口，入口不进入源码提交或交付包。
