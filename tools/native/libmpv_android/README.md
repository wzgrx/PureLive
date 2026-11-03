# Android libmpv 0.41.0 / FFmpeg 9.0.2 b2

Issue #176 的兼容性修复。旧 b1 在 Android API27 模拟器中加载失败：两个 Vulkan 1.1 核心符号被直接导入。b2 在创建 Vulkan 实例之后动态查询核心/KHR入口，缺失时退出可选 Vulkan 路径，保留 OpenGL/MediaCodec 与原 JNI 补丁。没有修改 API 最低要求或全局 TLS 策略。

## 构建来源

`provenance.json` 固定上游构建器、各依赖、补丁与二进制/JAR校验和。JAR保留 b1 的 media-kit helper，只替换同 ABI 的 libmpv.so。三个 ABI 的 ELF LOAD 对齐均至少16KB，Vulkan强导入均存在于NDK API26 stub。尚无原反馈者360N7Pro或ARM真机执行证据。

复建在新的独立目录进行，不能对已有工程执行重置/清理：

```bash
git clone https://github.com/Predidit/libmpv-android-video-build.git android-mpv-b2
cd android-mpv-b2
git checkout 0443048272a511d7a990a2a3d5ca6bbaf55a869a
git apply /path/to/PureLive/tools/native/libmpv_android/builder.patch
cd buildscripts
mkdir -p sdk
ln -s "$ANDROID_HOME" sdk/android-sdk-linux
# Host Python needs Jinja2; the recorded build used Python 3.12 with Jinja2.
cp /path/to/PureLive/tools/native/libmpv_android/ffmpeg.sh scripts/ffmpeg.sh
cp /path/to/PureLive/tools/native/libmpv_android/api26_vulkan_entrypoints.patch patches/mpv/
bash -e include/download-deps.sh
bash -e patch.sh
export cores=16
for arch in x86_64 arm64 armv7l; do bash -e build.sh --arch "$arch"; done
```

保留构建器原 mbedTLS `/dev/urandom` 配置，三个 ABI 顺序构建以免共享源码清理冲突。可选 Kazumi HLS 和不适用0.41的 TLS 补丁已从构建选择移除。以实际 `prefix/<abi>/lib/libmpv.so` 存在及校验为准，不能只看脚本退出码。不要运行上游 `bundle_default.sh` 的递归清理。

## 运行验证边界

在本任务新建、只读基础镜像的 API27 x64 模拟器中，5.6.1 release、修复前5.6.2 release/profile均出现原生加载失败；仅替换libmpv的独立签名诊断APK成功初始化并连续解码本地产生的 H.264/AAC 视频（11秒至17秒画面）。诊断APK不是正式附件。最终同源 profile/release 执行结果另记在 Y01.42 验证记录；ARM静态检查不等于ARM真机播放验证。

参考：[Android Vulkan 实现](https://source.android.com/docs/core/graphics/implement-vulkan)、[Khronos Android平台说明](https://docs.vulkan.org/guide/latest/platforms.html)。
