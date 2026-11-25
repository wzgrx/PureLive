# Linux libmpv 0.42 / FFmpeg 9.1

在独立AlmaLinux8/manylinux2_28构建目录中复建，保留glibc2.28上限。`provenance.json`记录稳定源码和补丁，`build.sh`运行在`/workspace`；依赖环境来自录制构建器fac2076的工具镜像，并安装字体、X11、EGL、VAAPI、VDPAU、PulseAudio、LCMS开发包和Meson1.12.1。

先由`tools/ffmpeg_kit/rebuild/`准备OpenSSL等静态依赖，复制`prebuilt/linux-x86_64/libraries`至新工作目录；按provenance中的版本准备`sources/`下的FFmpeg、mpv、libplacebo（含子模块）、libass、dav1d和XPresent源码。分别向FFmpeg应用`../ffmpeg_system_ca.patch`、向mpv应用`mpv_cxx_link.patch`，挂载新目录至容器`/workspace`后执行`bash build.sh`。

mpv的X11后端启用GPL以保留VAAPI/VDPAU；FFmpeg未启用GPL组件。Flutter管理主窗口并提供GL上下文，mpv不创建Wayland窗口；保留EGL DMA-BUF互操作。XPresent静态链接，避免为客户端新增系统动态依赖。静态libplacebo包含C++数值转换代码，因此显式使用C++链接器并禁止未解析符号；不能以“共享库生成成功”替代实际加载。

Linux默认从常见系统CA文件加载信任来源，保留显式CA文件及SSL_CERT_FILE/SSL_CERT_DIR选择。真实HTTPS解码需与下载工具代理环境区分；不关闭TLS验证。原设备GPU兼容性仍需各设备复测。
