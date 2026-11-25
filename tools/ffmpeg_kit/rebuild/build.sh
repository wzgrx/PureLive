#!/usr/bin/env bash
# Rebuilds the recorder's FFmpeg bundles (tools/ffmpeg_kit/bundles.txt) for
# Android, Linux and Windows from source on this machine; iOS and macOS are
# built by .github/workflows/ffmpeg-kit-apple.yml. Docker and the Android SDK
# (~/tools/purelive-env.sh) are needed.
#
#   tools/ffmpeg_kit/rebuild/build.sh <work dir> [android] [linux] [windows]
#
# - ffmpeg-kit-builders at the commit ffmpeg_kit_extended_flutter's native API
#   comes from, patched with builders.patch: FFmpeg fixed to a tag, git
#   retries that resolve the ref again, and the image's package mirrors.
# - Their image (manylinux_2_28: the Linux bundle needs glibc 2.28) with
#   their toolchain setup kept as a second image; both run on the host
#   network (the containers' own network drops GitHub connections).
# - Output: <work dir>/out with the three bundles and SHA256SUMS, after
#   check.sh passed on them.
set -euo pipefail

builders_commit=fac2076d06a473b8e1c1ed5a1fabe52ee974a5c0 # tag v0.11.2-android
ndk=30.0.16248370
image=purelive/ffmpeg-kit-builders:${builders_commit:0:7}
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $# -ge 1 ]] || { echo "usage: $0 <work dir> [android] [linux] [windows]" >&2; exit 2; }
work="$(mkdir -p "$1" && cd "$1" && pwd)"
shift
targets=("$@")
[[ ${#targets[@]} -gt 0 ]] || targets=(android linux windows)
builders="$work/builders"

if [[ ! -d "$builders/.git" ]]; then
  git clone -q https://github.com/akashskypatel/ffmpeg-kit-builders "$builders"
  git -C "$builders" -c advice.detachedHead=false checkout -q "$builders_commit"
  git -C "$builders" apply "$here/builders.patch"
  git -C "$builders" apply "$here/ffmpeg-9.1-compat.patch"
fi
[[ "$(git -C "$builders" rev-parse HEAD)" == "$builders_commit" ]] || { echo "builders is not at $builders_commit" >&2; exit 1; }

docker image inspect "$image" >/dev/null 2>&1 || docker build -f "$builders/docker/Dockerfile" -t "$image" "$builders"

# The builders' toolchain setup (Android SDK, Gradle via SDKMAN!, Rust
# targets, MinGW-w64, Wine) downloads for half an hour and writes into the
# NDK, so it runs once on a copy of the NDK and is kept as an image.
tools="$image-tools"
if ! docker image inspect "$tools" >/dev/null 2>&1; then
  sdk="${ANDROID_HOME:?ANDROID_HOME (source ~/tools/purelive-env.sh)}"
  [[ -d "$sdk/ndk/$ndk" ]] || yes | "$sdk/cmdline-tools/latest/bin/sdkmanager" --install "ndk;$ndk" >/dev/null
  setup="purelive-ffk-setup-$$"
  docker run --name "$setup" --network host --user root -e ANDROID_NDK_VERSION="$ndk" \
    -v "$sdk/ndk/$ndk:/ndk:ro" -v "$builders:/workspace:ro" --entrypoint bash "$image" -c "
      set -euo pipefail
      mkdir -p /usr/local/android-sdk/ndk && cp -a /ndk /usr/local/android-sdk/ndk/$ndk
      # Downloads drop now and then (TLS cut off); the setups skip what is done.
      for script in setup-android.sh setup-mingw-w64.sh; do
        for try in 1 2 3 4 5; do
          /workspace/scripts/toolchain/\$script && break
          [[ \$try -lt 5 ]] || exit 1
          sleep 30
        done
      done" || { docker rm "$setup" >/dev/null; exit 1; }
  docker commit "$setup" "$tools" >/dev/null
  docker rm "$setup" >/dev/null
fi

baseline="$work/ffmpeg-kit-api-0.11.2.aar"
if [[ " ${targets[*]} " == *" android "* ]]; then
  [[ -f "$baseline" ]] || curl --fail --location --retry 3 \
    https://github.com/wzgrx/PureLive/releases/download/native-ffmpeg-9.0.2-b2/bundle-base-shared-lgpl-release.aar -o "$baseline"
  echo "b4809b1b6d5cca73f13c7fe1640642a0dd6507a64e82264d83eeba8992b848b6  $baseline" | sha256sum --check
else
  # The unused read-only mount still needs an existing file.
  baseline="$here/pack_android.py"
fi

ndk_mount=()
if [[ " ${targets[*]} " == *" android "* ]]; then
  sdk="${ANDROID_HOME:?ANDROID_HOME (source the PureLive environment)}"
  [[ -d "$sdk/ndk/$ndk" ]] || { echo "Pinned NDK $ndk is missing" >&2; exit 1; }
  # A cached tools image may contain an earlier NDK. Always use this pinned
  # host copy, as in the verified 9.1 build, without rewriting either SDK.
  ndk_mount=(-v "$sdk/ndk/$ndk:/usr/local/android-sdk/ndk/$ndk:ro")
fi

docker run --rm --network host --user root -e NDK_VERSION="$ndk" "${ndk_mount[@]}" \
  -v "$builders:/workspace" -v "$here/in_container.sh:/usr/local/bin/in_container.sh:ro" \
+  -v "$here:/usr/local/share/purelive-ffmpeg:ro" -v "$baseline:/usr/local/share/ffmpeg-kit-api-baseline.aar:ro" \
  --entrypoint bash "$tools" -c "in_container.sh ${targets[*]}; status=\$?; chown -R $(id -u):$(id -g) /workspace; exit \$status"

out="$work/out"
mkdir -p "$out"
for target in "${targets[@]}"; do
  case "$target" in
    android) cp "$builders/tools/android/build/outputs/aar/bundle-base-shared-lgpl-release.aar" "$out/" ;;
    linux | windows) cp "$builders/prebuilt/$target-x86_64/releases/bundle-base-$target-x86_64-shared-lgpl.zip" "$out/" ;;
  esac
done
"$here/check.sh" "$out"
(cd "$out" && sha256sum ./*.aar ./*.zip 2>/dev/null | sed 's| \./| |' | tee SHA256SUMS)
