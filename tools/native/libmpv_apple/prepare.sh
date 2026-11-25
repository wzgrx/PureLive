#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../../toolchain.env"
brew list nasm >/dev/null 2>&1 || brew install nasm
brew list pkgconf >/dev/null 2>&1 || brew install pkgconf
read -r version url expected < <(python3 -c 'import json,sys; x=json.load(open(sys.argv[1]))["cmake"]; print(x["version"], x["url"], x["sha256"])' "$here/host_tools.json")
[[ "$version" == "$CMAKE_VERSION" ]]
cmake_dir="$RUNNER_TEMP/purelive-player-cmake"
mkdir -p "$cmake_dir"
curl --fail --location --retry 4 "$url" -o "$cmake_dir/source.tar.gz"
echo "$expected  $cmake_dir/source.tar.gz" | shasum -a 256 --check
tar -xf "$cmake_dir/source.tar.gz" --strip-components=1 -C "$cmake_dir"
cmake_bin="$cmake_dir/CMake.app/Contents/bin"
"$cmake_bin/cmake" --version
echo "$cmake_bin" >> "$GITHUB_PATH"
python3 -m venv "$RUNNER_TEMP/player-python"
"$RUNNER_TEMP/player-python/bin/python" -m pip install meson==1.12.1 jinja2 packaging
read -r version url expected < <(python3 -c 'import json,sys; x=json.load(open(sys.argv[1]))["ninja"]; print(x["version"], x["url"], x["sha256"])' "$here/host_tools.json")
[[ "$version" == "$NINJA_VERSION" ]]
curl --fail --location --retry 4 "$url" -o "$RUNNER_TEMP/player-ninja.zip"
echo "$expected  $RUNNER_TEMP/player-ninja.zip" | shasum -a 256 --check
unzip -o "$RUNNER_TEMP/player-ninja.zip" -d "$RUNNER_TEMP/player-python/bin"
[[ "$("$RUNNER_TEMP/player-python/bin/ninja" --version)" == "$NINJA_VERSION" ]]
echo "$RUNNER_TEMP/player-python/bin" >> "$GITHUB_PATH"
