# Apple稳定版播放内核

`build.py`在新的独立目录构建mpv0.42.0、FFmpeg9.1、libplacebo7.387和dav1d1.5.5。字体静态依赖的URL与SHA-256固定于`dependencies.json`，来源为mpvkit的公开构建。动态Mpv框架包含五个slice，最低要求保持iOS15、macOS12；FFmpeg使用系统SecureTransport信任、VideoToolbox和AV1软件解码。

`prepare.sh`准备已校验的CMake4.5.1、Ninja固定版本及Python3.15下的Meson1.12.1。`Libmpv Apple`工作流可以单独重建播放器；`FFmpegKit Apple`仍可重建录制包。静态C++依赖显式用C++链接器，保留旧OS可用的数值转换路径，不以较新SDK的声明代替旧OS兼容性。

输出为iOS、macOS两个动态XCFramework压缩包及来源记录。最终客户端还须执行Apple工作流的启动截图、原生播放探针及附件核验。框架构建不等于iPhone/iPad真机验收。
