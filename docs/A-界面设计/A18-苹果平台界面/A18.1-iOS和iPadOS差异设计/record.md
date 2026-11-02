# A18.1 记录

## 2026-10-17

用户：“发布5.4.1，没有苹果设备，继续做macOS和iPad”。没有 iPhone、iPad 和 Mac（D-041），验证只有 Dart 测试（`debugDefaultTargetPlatformOverride = TargetPlatform.iOS`）和 GitHub 构建机上 iPhone 模拟器的启动截图。

### 第 1 阶段：前提

- X04.1：工程能在构建机上构建，5.4.1 发布了未签名 IPA 和 TrollStore IPA；iPhone 模拟器里启动到首页（液态玻璃底栏）。没有真机，“拿不准的地方”里要真机看的（画中画、灵动岛的确切让位、分享扩展）留到有设备时。

### 第 2 阶段：纯 Dart 的部分

| 条 | 做了什么 |
|---|---|
| c2 安全区 | 横屏全屏的上下栏（`SafeArea`）、锁定键（右边让 `padding.right`）、录制角标（左边让 `padding.left`）早就按系统给的让位排（B09 c2 为安卓刘海做的），iPhone 横屏的左右 59、下 21 同样让开；全屏时 `SystemUiMode.immersiveSticky` 在 iOS 上隐藏状态栏、主屏指示条自动变淡（Flutter 引擎）。没改代码 |
| c3 左边缘滑动 | iOS 上直播间不让系统返回时（全屏、开着面板），从左边缘往右滑走直播间自己的返回：全屏时退出全屏、面板先关（`EdgeSwipeBack`，起点在左边 24 以内、滑过 64 或快速一甩）；普通时系统的滑动返回照旧 |
| c7 iPad 分享 | iPad 的系统分享必须有弹出位置，没有会报错：分享口令时把点的按钮（直播间菜单按钮、详情里的“分享”、卡片）传给分享面板；不知道按钮时（日志分享）从窗口中间弹（`sheetOrigin`）；Android 不变 |
| c9 剪贴板 | iOS 回到前台只查剪贴板的变化次数（原生 `pure_live/clipboard` 的 `changeCount`，有文字才算，不读内容，系统不弹“允许粘贴”）；有新文字时底部提示“剪贴板里有新内容，要识别分享口令吗？[识别]”，点了才读。提示用应用统一的带按钮提示（4 秒，A02.4），不是设计写的 6 秒 |
| c11 宽度分档 | 首页、直播间早就只按窗口宽度换排法（600、840），分屏拖动只改宽度；播放会话在直播间页面里，换排法不重建页面。没改代码 |
| c12 指针 | Flutter 在 iPad 上把触控板、鼠标当指针，悬停效果和电脑同一套代码；双指点按是系统的次要点按，长按菜单照旧。没改代码，要真机看 |
| c13 更新 | iOS 上新版本对话框的主按钮是“去下载页”，打开发布页（IPA 用 AltStore、SideStore、TrollStore 装）；版本页“下载文件”说明 iPhone、iPad 的安装包在发布页，按钮“去下载页” |

### 第 3 阶段：⌘ 快捷键（c10）的 Dart 层

- 和 A18.2 共用 `app/commands.dart` 的命令表：iPad 接键盘时 ⌘, ⌘F ⌘L ⌘Y ⌘1～⌘4 ⌘[ 和直播间的 ⌘R 已生效（`AppCommandShortcuts`）；v3 的单键照旧。按住 ⌘ 时系统列出快捷键要原生 `UIKeyCommand`，还没做。

### 测试

- `test/platform/share_origin_test.dart`：iPad 分享总有位置；位置就是点的按钮。
- `test/intake_test.dart`：iOS 先问再读，不点“识别”就不读，同一段文字不再问，没有文字不提示。
- `test/features/live_play/edge_swipe_back_test.dart`：左边缘滑动返回；太短或从画面中间开始的是画面自己的手势；关掉时不拦。
- `test/features/version/update_dialogs_test.dart`：iOS 的主按钮“去下载页”打开发布页。
- `test/app_commands_test.dart`：iPad 上 ⌘R 刷新直播间。

### 还没做（当天）

- 第 3 阶段原生：按住 ⌘ 列出快捷键（`UIKeyCommand`）。
- 第 4 阶段原生：系统画中画和自动画中画（c4）、锁屏“正在播放”（c5）、分享扩展（c8）、台前调度窗口按钮让位（c11）。

## 2026-10-18

用户：“继续完善macOS和iPad”。仍然没有设备，验证是 Dart 测试和构建机（编译、包里有没有、模拟器截图）。

### 第 3 阶段：按住 ⌘ 的列表（c10 原生）

- Dart 把命令表（标题、分组、键、文字跟应用语言）发给原生 `pure_live/key_commands`；`AppDelegate.buildMenu(with:)` 把它做成 `UIKeyCommand`，放在主菜单“窗口”前面一组（iPadOS 26 的菜单栏、按住 ⌘ 的列表都从这里来）。按键由系统收到后回调 Dart 的 `run`，`⌘R` 只有在直播间里才可用（`canPerformAction`）。
- 原生接上以后 Dart 自己的 `CallbackShortcuts` 不再挂，免得同一个键执行两次；原生没接上（旧系统、模拟器以外的意外）时照旧用 Dart 的。

### 第 4 阶段：原生

| 条 | 做了什么 |
|---|---|
| c5 后台和锁屏 | iOS 也用播放会话（`audio_session` 的音乐会话，后台、锁屏有声音）和“正在播放”（`audio_service`，锁屏和控制中心显示房间、主播、暂停）；以前只在 Android 上开。`media_kit_video` 的 iOS 画面用 OpenGL ES，系统会结束在后台调用 GL 的应用，所以退到后台时停止画面、只放声音，回前台接着画（补丁见 `third_party/media_kit_video/PURELIVE_PATCH.md`） |
| c8 分享扩展 | 新的 `ShareExtension`（系统分享面板里的“纯粹直播”）：收网址和文字，拼成 `purelive-share://share?text=…` 打开应用，应用收到后和 Android 的分享一样识别房间。文件（图片里的口令）要 App Group，没做 |
| c4 画中画 | 没做：`media_kit` 的 iOS 画面是 GL 纹理，系统画中画要 `AVSampleBufferDisplayLayer` 一路的帧，工作量大，没有真机也看不了效果 |
| c11 台前调度 | 没做：窗口左上角按钮的让位要 iPadOS 26 真机或模拟器的窗口模式才能看 |

### 测试

- `test/app_commands_test.dart`：iPad 把命令表交给系统，系统按键时执行；原生接上后同一个键不执行两次。
- `test/intake_test.dart`：iOS 分享扩展的文字作为分享到达；Android 才有的调用不发。
- 构建机：`apple.yml` 检查包里有 `PlugIns/ShareExtension.appex` 和 URL 方案，TrollStore 包连扩展一起签；模拟器打开 `purelive-share://share?text=…` 后截图 `ios-share.png`。

### 构建机核对（运行 39088442351，6e67dad6f）

- 第一次构建（39086959261）编译失败：`AppDelegate` 里存命令表的属性叫 `keyCommands`，和 `UIResponder` 自带的属性重名；改名 `pureLiveKeys` 后通过。
- 包里有 `PlugIns/ShareExtension.appex`（`com.mystyle.purelive.liu.ShareExtension`，`com.apple.share-services`，5.4.2），应用的 URL 方案是 `purelive-share`；TrollStore 包连扩展一起签，`codesign --verify --deep --strict` 通过。
- 模拟器里 `simctl openurl purelive-share://share?text=…`：系统弹出“在‘纯粹直播’中打开？”（从外面打开别的应用的链接系统都会问），说明方案已注册、指向这个应用；构建机点不了这个按钮，之后进应用的部分靠 `test/intake_test.dart`。从分享扩展打开时会不会也问、⌘ 列表、锁屏“正在播放”、后台不画画面，都要真机看。

## 2026-11-02 功能冻结（D-088）

按维护者最新指令暂停后续功能开发；已有完成阶段、代码和证据保留。直播回放专项停止维护更新，其他已有功能仅处理bug和稳定性。旧任务书不能自行恢复新增功能；新功能须贡献者自带满足模型、UI、代码及验证要求的完整PR，再由维护者审核。
