#!/usr/bin/env bash
# Checks the recorder's FFmpeg bundles in a directory before they are
# published (build.sh runs it on its output; run it on the Apple workflow's
# zips too):
#
#   tools/ffmpeg_kit/rebuild/check.sh <dir> [FFmpeg tag, default n9.1]
#
# - Every binary carries the FFmpeg tag (the armeabi-v7a library of
#   ffmpeg-kit-builders' own 0.11.2 release was built from another commit).
# - Android: the three ABIs, stripped, 64-bit ones with 16 KiB LOAD alignment.
# - Linux: x86-64, glibc symbols no newer than 2.28, only system libraries.
# - Windows: x86-64, only Windows system DLLs and the UCRT.
# Needs binutils (readelf, objdump, strings) and unzip.
set -euo pipefail

dir="$(cd "${1:?usage: $0 <dir> [FFmpeg tag]}" && pwd)"
tag="${2:-n9.1}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failed=0
bad=0
fail() { echo "FAIL $*"; failed=1; bad=1; }
# "ok" for a part only when nothing in it failed.
ok() { ((bad)) || echo "ok   $*"; bad=0; }

# Not `strings | grep -q`: under pipefail grep's early exit fails the pipe.
carries_tag() {
  strings "$1" >"$tmp/strings.txt"
  grep -qF "$tag" "$tmp/strings.txt"
}

check_aar() {
  local aar="$1" abi so
  unzip -q -o "$aar" -d "$tmp/aar"
  for abi in arm64-v8a armeabi-v7a x86_64; do
    so="$tmp/aar/jni/$abi/libffmpegkit.so"
    [[ -f "$so" ]] || { fail "$aar: no $abi"; continue; }
    readelf -h "$so" >"$tmp/header.txt"
    case "$abi" in
      arm64-v8a) grep -q 'AArch64' "$tmp/header.txt" || fail "$abi: not AArch64" ;;
      armeabi-v7a) grep -q 'Machine:.*ARM$' "$tmp/header.txt" || fail "$abi: not ARM" ;;
      x86_64) grep -q 'X86-64' "$tmp/header.txt" || fail "$abi: not x86-64" ;;
    esac
    carries_tag "$so" || fail "$abi: no $tag"
    readelf -SW "$so" >"$tmp/sections.txt"
    grep -q ' \.symtab ' "$tmp/sections.txt" && fail "$abi: not stripped"
    if [[ "$abi" != armeabi-v7a ]]; then
      readelf -lW "$so" | awk '$1 == "LOAD" { print $NF }' >"$tmp/align.txt"
      while read -r align; do
        ((align >= 0x4000)) || fail "$abi: LOAD alignment $align"
      done <"$tmp/align.txt"
    fi
    ok "$(basename "$aar") $abi"
  done
}

check_linux() {
  local zip="$1" so newest
  unzip -q -o "$zip" -d "$tmp/linux"
  so="$(find "$tmp/linux" -path '*/lib/libffmpegkit.so')"
  [[ -n "$so" ]] || { fail "$zip: no lib/libffmpegkit.so"; return; }
  readelf -h "$so" | grep -q 'X86-64' || fail "linux: not x86-64"
  carries_tag "$so" || fail "linux: no $tag"
  objdump -T "$so" | grep -oE 'GLIBC_[0-9.]+' | sort -Vu >"$tmp/glibc.txt"
  newest="$(tail -n 1 "$tmp/glibc.txt")"
  [[ "$(printf '%s\n' "$newest" GLIBC_2.28 | sort -V | tail -n 1)" == GLIBC_2.28 ]] || fail "linux: needs $newest"
  readelf -d "$so" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' >"$tmp/needed.txt"
  while read -r lib; do
    case "$lib" in
      libasound.so.2 | libpthread.so.0 | libdl.so.2 | librt.so.1 | libm.so.6 | libstdc++.so.6 | libgcc_s.so.1 | libc.so.6 | ld-linux-x86-64.so.2) ;;
      *) fail "linux: needs $lib" ;;
    esac
  done <"$tmp/needed.txt"
  ok "$(basename "$zip") (newest $newest)"
}

check_windows() {
  local zip="$1" dll
  unzip -q -o "$zip" -d "$tmp/windows"
  dll="$(find "$tmp/windows" -path '*/bin/libffmpegkit.dll')"
  [[ -n "$dll" ]] || { fail "$zip: no bin/libffmpegkit.dll"; return; }
  objdump -f "$dll" | grep -q 'x86-64' || fail "windows: not x86-64"
  carries_tag "$dll" || fail "windows: no $tag"
  objdump -p "$dll" | sed -n 's/^\s*DLL Name: //p' >"$tmp/imports.txt"
  while read -r lib; do
    case "${lib,,}" in
      api-ms-win-crt-*.dll | advapi32.dll | avicap32.dll | crypt32.dll | gdi32.dll | imm32.dll | kernel32.dll | \
        oleaut32.dll | psapi.dll | setupapi.dll | shell32.dll | shlwapi.dll | secur32.dll | user32.dll | \
        version.dll | winmm.dll | ws2_32.dll | dbghelp.dll | ncrypt.dll | ole32.dll | bcrypt.dll) ;;
      *) fail "windows: imports $lib" ;;
    esac
  done <"$tmp/imports.txt"
  ok "$(basename "$zip")"
}

check_apple() {
  local zip="$1" binary found=0
  rm -rf "$tmp/apple" && unzip -q -o "$zip" -d "$tmp/apple"
  while IFS= read -r binary; do
    found=1
    carries_tag "$binary" || fail "$(basename "$zip"): ${binary#"$tmp/apple/"} has no $tag"
  done < <(find "$tmp/apple" -path '*/ffmpegkit.framework/ffmpegkit' -not -path '*dSYM*')
  ((found)) || fail "$zip: no ffmpegkit.framework"
  ok "$(basename "$zip")"
}

shopt -s nullglob
for file in "$dir"/*.aar "$dir"/*.zip; do
  case "$(basename "$file")" in
    *.aar) check_aar "$file" ;;
    *linux*) check_linux "$file" ;;
    *windows*) check_windows "$file" ;;
    *.xcframework.zip) check_apple "$file" ;;
    *) fail "unknown bundle $file" ;;
  esac
done
((failed == 0)) || { echo "check: failed"; exit 1; }
echo "check: passed"
