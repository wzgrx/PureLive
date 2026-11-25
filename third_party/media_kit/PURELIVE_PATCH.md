# PureLive native integration

The upstream repository/revision is pinned in `toolchain.env`. Existing code-assets and module ownership notes are retained in `doc/native_assets.md`; the original MIT license and source copyright notices are preserved.


2026-11-25 Android integration: initialize JNI through `mpv_lavc_set_java_vm`
when supplied, otherwise prefer `av_jni_set_java_vm` exported by the same
static libmpv module before considering a separate dynamic avcodec library.
The normal API27 profile reproduced initialization failure before this
fallback; its generated HLS room rendered after the change. Public TLS and
unknown/explicit CA checks remain enabled and independently recorded.
