# PureLive media_kit_video patch

- Upstream: `https://github.com/Predidit/media-kit.git`
- Base commit: `803c4a27912091db6f839d48d1b984a0d9f588c7` (2026-09-26, "fix(native): handle unavailable mpv properties safely"; `media_kit` follows the same commit)
- Synced to `6b188ae978808a63e5b58b7ce61f7725238c04c5` (2026-10-14): upstream's only change, "update libmpv video binaries to v1.3.0", applies to `media_kit/hook/native_bundles.json` alone; the arm64, arm and x86_64 bundles here are PureLive's own builds (mpv 0.41.0, FFmpeg 9.0.2), so only the x86 bundle moved to v1.3.0.
- Package version: `media_kit_video 1.2.5`
- License: MIT; the upstream `LICENSE` is retained in this directory.

This revision uses `media_kit`'s Native Assets hook rather than the removed
`media_kit_libs_*` packages. The local patch was replayed with a three-way
merge against the new upstream video implementation. Android JNI references
now call the helper class shipped by `media_kit` directly. The unused upstream
`deletedGlobalObjectRefs` field was dropped; reference deletion remains
serialized by the existing Surface owner and delayed teardown.

## Why this copy exists

On Android, `AndroidVideoController` owns the `vo`, `wid` and Surface lifecycle.
PureLive's room-scoped audio mode also needs to select `vid=no` without replacing
the player or reopening the live stream. Sending that property independently
could race a rotation, PiP or Surface resize update and leave the UI waiting for
a video track or Surface that had already vanished.

This patch adds `VideoController.setVideoOutputEnabled` and makes the Android
controller the single owner of both the requested video-output state and the
Surface lifecycle. Track properties are issued from the controller's lock via
media_kit's asynchronous mpv request. The synchronous string-property FFI call
is deliberately avoided for headphone switching because a busy live demuxer
can block Flutter's isolate before the audio presentation or timeout paints.
Video mode always selects `vid=auto`, including while WID is temporarily zero;
only an explicit audio-only request selects `vid=no`. This avoids a startup
deadlock where disabling video before a Surface callback also prevented the
callback that would restore it. Surface replacement follows Flutter's
`SurfaceProducer` contract: every availability/resize queries `getSurface()`, a
changed Java Surface receives a new JNI global reference, and the old WID is
detached exactly once before delayed reference deletion. Geometry-only updates
do not reset `vo`, and Surface changes do not seek a live stream merely to
refresh rendering. The Android Surface-size MethodChannel request remains
outside the controller lock. Desktop platforms retain media_kit's existing
`setVideoTrack` behavior.

On Windows, PureLive also exposes a throttled `frameRevision` liveness signal.
The native D3D11 mailbox emits it only after a fence-confirmed frame has been
promoted for Flutter consumption; software rendering emits it after a completed
render. This lets `PlayerManager` distinguish “libmpv still says playing” from
“the presentation surface has stopped advancing”, recreate the renderer once,
then fall through to the existing CDN-line recovery. The signal carries no
pixels, is limited to two events per second, and does not alter normal frame
delivery or aspect-ratio policy.

`VideoController.setSize` also accepts an opt-in `force` flag on every platform
(only the Windows native implementation changes behavior). PureLive uses it on
the first layout after a Windows `Texture` remount so the current native output
receives a viewport even when its controller cache still contains equal width
and height. Normal resize calls keep the upstream equality fast path. Together
with the frame-progress fence, this prevents a 0×0 replacement output from
being treated as presentation-ready after an overlay route or transport retry.

## Maintenance

When updating the pinned media-kit revision:

1. Replace this directory with the new upstream package.
2. Reapply the controller API, Android state-owner patch, and Windows
   fence-confirmed frame-progress callback.
3. Compare every file against the new upstream commit; only the files described
   above, `pubspec.yaml`, this note and the policy helper should differ.
4. Run `flutter analyze`, the full test suite, Windows release build and Android
   ARM64 release build.
5. On Android, repeat video/audio toggles plus rotation, PiP and room re-entry.
6. On Windows, verify a deliberately stalled renderer is recreated once, a
   stalled CDN advances to the next line, a 0×0 candidate never replaces the
   active texture, remounting reasserts viewport size, and explicit pause never
   triggers the watchdog.

## iOS: no OpenGL ES frame in the background (2026-10-18)

`ios/.../plugin/TextureHW.swift` skips `render` while the app is in the
background (`AppVisibility`, following `didEnterBackground` /
`willEnterForeground`). iOS ends an app that issues OpenGL ES commands in the
background; with PureLive's background play (A18.1 c5) mpv keeps playing the
sound and the next frame is drawn once the app is back. The simulator's
software path (`TextureSW`) has no GL and is unchanged.

## Android initialization ordering (2026-10-30)

Initial mpv options and Surface attachment now share the controller lock.
A Surface published before the Create reply is retained and replayed after
initialization, so the startup vo=null cannot overwrite a valid gpu binding.
Creation still does not wait for a Surface. The application keys Video by its
controller because VideoState binds player width/height streams in initState;
replacing a native player must replace those listeners too. Factory race tests
and Android 9 generated-media native/screen comparisons cover both paths.

## Independent native player queues (2026-10-30)

The companion `media_kit` NativePlayer lock is instance-owned. Upstream's
static lock serialized every player's create/open/control/dispose operation,
so a held stop reply in a retired player also blocked its replacement from
initializing. The session's bounded retirement alone could not bypass that
shared queue. Each player's existing serialization and native event-buffer
ownership remain intact. The real-handle regression
`packages/live_player/test/native_instance_isolation_test.dart` holds an old
stop reply during disposal and requires a replacement to initialize, change
volume and pause before releasing the old reply. The original shared lock
times out; the instance lock passes. This is an identified common defect,
not original Sony/Huawei/Honor hardware acceptance.


## Early native lifecycle evidence (2026-10-31)

The companion media_kit NativePlayer exposes an optional exception-isolated
lifecycle listener. It emits fixed phase names and numeric end-file errors,
never media paths or native log text. MpvEngine assigns its diagnostic identity
before initialization, owns cleanup when its factory fails, and retains the
original setup exception. The real-handle setup-failure regression verifies
release before propagation. Session creation/stop retirement is bounded and
late completions cannot adopt a new room (G02.13).

## 2026-11-25 upstream render-API migration

Rebased onto Predidit/media-kit 484639aca5ffc754a65876c22f01dbb070225732.
Windows uses the upstream D3D11 render API; preserve PureLive's fence-confirmed
ProducerCommit result as the presented-frame signal. Failed native renders must
not increment frameRevision. Existing Surface, disposal, audio mode and viewport
patches remain. The native bundle must export the matching render API.
Linux prefers upstream's GLES3 context and keeps its GLES2 fallback.
