#!/usr/bin/env bash
set -euo pipefail
cd /workspace
export PATH=/opt/python/cp313-cp313/bin:/usr/local/bin:$PATH
export CFLAGS='-O2 -fPIC -march=x86-64 -mtune=generic'
export CXXFLAGS="$CFLAGS"
export PKG_CONFIG_PATH=/workspace/prefix/lib/pkgconfig:/workspace/prebuilt/linux-x86_64/libraries/lib/pkgconfig
prefix=/workspace/prefix
mkdir -p "$prefix" build
git config --global --add safe.directory /workspace/sources/mpv
git config --global --add safe.directory /workspace/sources/ffmpeg

cd /workspace/sources/libass-0.17.5
if [[ ! -f configure ]]; then ./autogen.sh; fi
mkdir -p /workspace/build/libass
cd /workspace/build/libass
[[ -f Makefile ]] || /workspace/sources/libass-0.17.5/configure --prefix="$prefix" --disable-shared --enable-static
make -j16
make install

cd /workspace
if [[ ! -f build/dav1d/build.ninja ]]; then
  meson setup build/dav1d sources/dav1d --prefix="$prefix" --buildtype=release --libdir=lib --default-library=static \
    -Denable_tools=false -Denable_tests=false
fi
meson compile -C build/dav1d -j16
meson install -C build/dav1d

if [[ ! -f build/libplacebo/build.ninja ]]; then
  meson setup build/libplacebo sources/libplacebo --prefix="$prefix" --buildtype=release --libdir=lib --default-library=static \
    -Dopengl=enabled -Dvulkan=disabled -Dd3d11=disabled -Dshaderc=disabled -Dglslang=disabled -Dtests=false -Ddemos=false
fi
meson compile -C build/libplacebo -j16
meson install -C build/libplacebo

mkdir -p /workspace/build/ffmpeg
cd /workspace/build/ffmpeg
if [[ ! -f config.h ]]; then
  /workspace/sources/ffmpeg/configure --prefix="$prefix" --enable-static --disable-shared --enable-pic \
    --extra-cflags="$CFLAGS -I$prefix/include" --extra-ldflags="-L$prefix/lib" --pkg-config-flags=--static \
    --disable-gpl --disable-nonfree --enable-version3 --disable-autodetect --disable-vulkan \
    --disable-doc --disable-programs --disable-avdevice --disable-encoders --disable-muxers \
    --enable-encoder=png,mjpeg --enable-libdav1d --enable-openssl --enable-zlib --enable-iconv \
    --enable-vaapi --enable-vdpau --enable-xlib
fi
make -j16
make install

cd /workspace
mkdir -p build/xpresent
cd build/xpresent
[[ -f Makefile ]] || /workspace/sources/libXpresent-1.0.2/configure --prefix="$prefix" --disable-shared --enable-static
make -j16
make install
cd /workspace
mpv_setup=()
if [[ -f build/mpv/meson-private/coredata.dat ]]; then mpv_setup=(--reconfigure --clearcache); fi
meson setup "${mpv_setup[@]}" build/mpv sources/mpv --prefix="$prefix" --buildtype=release --libdir=lib --default-library=shared \
    -Dgpl=true -Dprefer_static=true -Db_lundef=true -Dcpp_link_args=-static-libstdc++ -Dlibmpv=true -Dcplayer=false -Dbuild-date=false -Dtests=false \
    -Dgl=enabled -Dplain-gl=enabled -Dvulkan=disabled -Dwayland=disabled \
    -Dvaapi=enabled -Dvaapi-x11=enabled -Dvdpau=enabled -Dlua=disabled -Djavascript=disabled \
    -Dlibavdevice=disabled -Dlibbluray=disabled -Ddvdnav=disabled -Dcdda=disabled
meson compile -C build/mpv -j16
meson install -C build/mpv
mkdir -p out
cp -L prefix/lib64/libmpv.so.2 out/libmpv.so.2 2>/dev/null || cp -L prefix/lib/libmpv.so.2 out/libmpv.so.2
strip --strip-unneeded out/libmpv.so.2
readelf -d out/libmpv.so.2 | sed -n '/NEEDED/p'
objdump -T out/libmpv.so.2 | sed -nE 's/.*(GLIBC_[0-9.]+).*/\1/p' | sort -Vu > out/glibc-required.txt
test "$(tail -n 1 out/glibc-required.txt)" = GLIBC_2.28
zip -j out/libmpv_x86_64.zip out/libmpv.so.2
sha256sum out/libmpv_x86_64.zip
