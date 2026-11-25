# Android libmpv 0.42.0 / FFmpeg 9.1

稳定标签的确切提交、全部依赖和三个JAR的SHA-256固定于`provenance.json`。保留API26最低要求、原Java/JNI helper和动态查询Vulkan可选入口的兼容修复。三个ABI全部强导入已与NDK API26 stub逐项核对，ELF至少16KB对齐。

mpv0.42在FFmpeg9中默认验证TLS证书，mbedTLS未自动加载Android根证书会使HTTPS直播失败。`../ffmpeg_system_ca.patch`在没有显式CA文件时加载Conscrypt APEX系统信任库，旧Android加载`/system/etc/security/cacerts`；显式CA文件仍替换默认来源，验证保持开启。

复建须使用新的独立目录，保留已有源代码和缓存：

```bash
git clone https://github.com/Predidit/libmpv-android-video-build.git android-mpv-042
cd android-mpv-042
git checkout 0443048272a511d7a990a2a3d5ca6bbaf55a869a
git apply /path/to/PureLive/tools/native/libmpv_android/builder.patch
cd buildscripts
mkdir -p sdk
ln -s "$ANDROID_HOME" sdk/android-sdk-linux
cp /path/to/PureLive/tools/native/libmpv_android/ffmpeg.sh scripts/ffmpeg.sh
cp /path/to/PureLive/tools/native/libmpv_android/api26_vulkan_entrypoints.patch patches/mpv/
cp /path/to/PureLive/tools/native/ffmpeg_system_ca.patch patches/ffmpeg/system_ca.patch
bash -e include/download-deps.sh
bash -e patch.sh
git -C deps/mpv fetch --depth 1 origin tag v0.42.0
git -C deps/ffmpeg fetch --depth 1 origin tag n9.1
export cores=16
for arch in x86_64 arm64 armv7l; do bash -e build.sh --arch "$arch"; done
```

JAR保留旧版已校验helper，仅替换同ABI的`libmpv.so`。不要执行上游`bundle_default.sh`的递归清理。API27自有模拟器已验证本地H.264/AAC、公网HTTPS、未知证书拒绝及显式测试CA接受；ARM静态检查不等于原机播放验收。旧0.41构建和API27故障证据保留在Git历史及旧native发布页。
