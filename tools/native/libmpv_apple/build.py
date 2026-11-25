#!/usr/bin/env python3
"""Build API-compatible, dynamic Apple libmpv frameworks in an isolated tree."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import tarfile
import zipfile


HERE = Path(__file__).resolve().parent
MPV = 'b0841e8c4d156b8403dc1876c4cbd9011eb583f3'  # v0.42.0
PLACEBO = '275f7dea27924cdd34ab2e6c20e448b6bc4fab65'  # v7.387.0
TARGETS = [
    ('ios-arm64', 'iphoneos', 'ios', 'arm64', 'arm64-apple-ios15.0'),
    ('ios-sim-arm64', 'iphonesimulator', 'isimulator', 'arm64', 'arm64-apple-ios15.0-simulator'),
    ('ios-sim-x64', 'iphonesimulator', 'isimulator', 'x86_64', 'x86_64-apple-ios15.0-simulator'),
    ('macos-arm64', 'macosx', 'macos', 'arm64', 'arm64-apple-macos12.0'),
    ('macos-x64', 'macosx', 'macos', 'x86_64', 'x86_64-apple-macos12.0'),
]


def run(args, *, cwd=None, env=None):
    print('+', shlex.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, check=True)


def output(*args):
    return subprocess.check_output(list(map(str, args)), text=True).strip()


def fetch(url, dest, expected=None):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        run(['curl', '--fail', '--location', '--retry', '4', '--output', dest, url])
    if expected and hashlib.sha256(dest.read_bytes()).hexdigest() != expected:
        raise ValueError(f'Download hash differs: {dest.name}')
    return dest


def git_source(root, name, repo, ref):
    source = root / 'sources' / name
    if not source.exists():
        source.mkdir(parents=True)
        run(['git', 'init', '-q', source])
        run(['git', '-C', source, 'remote', 'add', 'origin', repo])
        run(['git', '-C', source, 'fetch', '--depth', '1', 'origin', ref])
        run(['git', '-C', source, 'checkout', '--detach', 'FETCH_HEAD'])
    actual = output('git', '-C', source, 'rev-parse', 'HEAD')
    if len(ref) == 40 and actual != ref:
        raise ValueError(f'Unexpected {name} source commit: {actual}')
    tag = {"mpv": "v0.42.0", "ffmpeg": "n9.1", "libplacebo": "v7.387.0", "dav1d": "1.5.5"}.get(name)
    if tag:
        run(['git', '-C', source, 'fetch', '--depth', '1', 'origin', f'refs/tags/{tag}:refs/tags/{tag}'])
        if output('git', '-C', source, 'rev-parse', tag + '^{commit}') != actual:
            raise ValueError(f'Unexpected release tag for {name}')
    return source



def apply_mpv_embedding_patch(source):
    patch = HERE / 'mpv-embedded-apple.patch'
    check = subprocess.run(['git', '-C', str(source), 'apply', '--check', str(patch)], capture_output=True)
    if check.returncode == 0:
        run(['git', '-C', source, 'apply', patch])
    else:
        reverse = subprocess.run(['git', '-C', str(source), 'apply', '--reverse', '--check', str(patch)], capture_output=True)
        if reverse.returncode != 0:
            raise ValueError('Pinned Apple embedding patch does not apply cleanly')


def crossfile(path, arch, flags, pkgdirs):
    text = "[binaries]\nc = 'clang'\ncpp = 'clang++'\nobjc = 'clang'\nobjcpp = 'clang++'\nar = 'ar'\nstrip = 'strip'\npkg-config = 'pkg-config'\n"
    text += f"[host_machine]\nsystem = 'darwin'\ncpu_family = '{'aarch64' if arch == 'arm64' else 'x86_64'}'\ncpu = '{arch}'\nendian = 'little'\n"
    text += f'[properties]\nneeds_exe_wrapper = true\npkg_config_libdir = {pkgdirs!r}\n[built-in options]\n'
    for key in ['c_args', 'cpp_args', 'objc_args', 'objcpp_args', 'c_link_args', 'cpp_link_args', 'objc_link_args', 'objcpp_link_args']:
        scoped = flags + (['-DHAS_STD_TO_CHARS_FP=0', '-DHAS_STD_FROM_CHARS_FP=0'] if key in ['cpp_args', 'objcpp_args'] else [])
        text += f'{key} = {scoped!r}\n'
    path.write_text(text)


def framework(root, name, binary, platform):
    folder = root / name / 'Mpv.framework'
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copy2(binary, folder / 'Mpv')
    run(['install_name_tool', '-id', '@rpath/Mpv.framework/Mpv', folder / 'Mpv'])
    run(['strip', '-x', folder / 'Mpv'])
    data = {
        'CFBundleExecutable': 'Mpv', 'CFBundleIdentifier': 'com.purelive.libmpv',
        'CFBundleName': 'Mpv', 'CFBundlePackageType': 'FMWK',
        'CFBundleShortVersionString': '0.42.0', 'CFBundleVersion': '1',
        'CFBundleSupportedPlatforms': [platform],
        'MinimumOSVersion': '12.0' if platform == 'MacOSX' else '15.0',
    }
    (folder / 'Info.plist').write_bytes(plistlib.dumps(data))
    linked = output('otool', '-L', folder / 'Mpv')
    for line in linked.splitlines()[1:]:
        dep = line.strip().split(' (')[0]
        if not dep.startswith(('/usr/lib/', '/System/Library/', '@rpath/Mpv.framework/Mpv')):
            raise ValueError(f'Unbundled Apple dependency: {dep}')
    return folder


def select_targets(target):
    if target is None: return list(TARGETS)
    selected = [item for item in TARGETS if item[0] == target]
    if len(selected) != 1: raise ValueError('Unknown Apple target')
    return selected


def build(work, dist, target=None):
    dependencies = json.loads((HERE / 'dependencies.json').read_text())
    for asset in dependencies['assets']:
        archive = fetch(asset['url'], work / 'downloads' / asset['name'], asset['sha256'])
        dest = work / 'dependencies' / asset['name'].removesuffix('-all.zip')
        if not dest.exists():
            dest.mkdir(parents=True)
            with zipfile.ZipFile(archive) as source:
                source.extractall(dest)
    mpv = git_source(work, 'mpv', 'https://github.com/mpv-player/mpv.git', MPV)
    apply_mpv_embedding_patch(mpv)
    placebo = git_source(work, 'libplacebo', 'https://github.com/haasn/libplacebo.git', PLACEBO)
    run(['git', '-C', placebo, 'submodule', 'update', '--init', '--recursive'])
    # Static C++ dependencies need a C++ linker even though libmpv's own
    # sources are C/Objective-C. Reject unresolved imports at link time.
    meson_file = mpv / 'meson.build'
    text = meson_file.read_text()
    if "link_language: 'cpp'" not in text:
        text = text.replace("        'c',", "        'c', 'cpp',", 1)
        meson_target = "libmpv = library('mpv', sources, dependencies: dependencies, gnu_symbol_visibility: 'hidden',"
        if meson_target not in text:raise ValueError('Unexpected libmpv target')
        text = text.replace(meson_target, meson_target + "\n                 link_language: 'cpp',", 1)
        meson_file.write_text(text)
    # Keep numeric conversion compatible with iOS15/macOS12; newer SDK
    # declarations alone do not make newer libc++ entry points available.
    convert = placebo / 'src/convert.cc'
    text = convert.read_text()
    guard = 'constexpr bool has_std_from_chars = has_std_from_chars_impl<T>::value;'
    if 'HAS_STD_FROM_CHARS_FP' not in text:
        if guard not in text:raise ValueError('Unexpected libplacebo conversion source')
        text = text.replace(guard, guard + "\n#if defined(HAS_STD_FROM_CHARS_FP) && HAS_STD_FROM_CHARS_FP == 0\ntemplate <> constexpr bool has_std_from_chars<float> = false;\ntemplate <> constexpr bool has_std_from_chars<double> = false;\n#endif", 1)
        convert.write_text(text)

    ffmpeg = git_source(work, 'ffmpeg', 'https://github.com/FFmpeg/FFmpeg.git', '74e4393595cf2b5857f0da925c4e0dd74ea306e5')
    dav1d = git_source(work, 'dav1d', 'https://github.com/videolan/dav1d.git', '1.5.5')
    uchardet_archive = fetch(
        'https://www.freedesktop.org/software/uchardet/releases/uchardet-0.0.8.tar.xz',
        work / 'downloads/uchardet-0.0.8.tar.xz',
        'e97a60cfc00a1c147a674b097bb1422abd9fa78a2d9ce3f3fdcc2e78a34ac5f0',
    )
    uchardet = work / 'sources/uchardet-0.0.8'
    if not uchardet.exists():
        with tarfile.open(uchardet_archive) as archive:
            archive.extractall(work / 'sources', filter='data')
    receipts = []
    frameworks = {}
    jobs = str(min(12, os.cpu_count() or 4))
    for name, sdk, label, arch, triple in select_targets(target):
        prefix = work / name / 'prefix'
        prefix.mkdir(parents=True, exist_ok=True)
        include = prefix / 'include'; libraries = prefix / 'lib'; pcs = libraries / 'pkgconfig'
        pcs.mkdir(parents=True, exist_ok=True)
        for asset in dependencies['assets']:
            dep = work / 'dependencies' / asset['name'].removesuffix('-all.zip')
            shutil.copytree(dep / 'include', include, dirs_exist_ok=True)
            for library in (dep / 'lib' / label / 'thin' / arch / 'lib').glob('*.a'):
                shutil.copy2(library, libraries / library.name)
            for pc in (dep / 'pkgconfig-example' / label / arch).glob('*.pc'):
                value = re.sub(r'^prefix=.*$', f'prefix={prefix}', pc.read_text(), flags=re.M)
                # Upstream's libunibreak pc has a stray non-pkg-config label.
                value = value.removeprefix('libunibreak:\n')
                (pcs / pc.name).write_text(value)
        (pcs / 'zlib.pc').write_text('Name: zlib\nDescription: Apple SDK zlib\nVersion: 1.2.13\nLibs: -lz\n')
        sysroot = output('xcrun', '--sdk', sdk, '--show-sdk-path')
        flags = ['-target', triple, '-isysroot', sysroot, '-fPIC']
        machine = work / name / 'cross.ini'
        crossfile(machine, arch, flags, [str(pcs)])
        env = os.environ.copy()
        env.pop('SDKROOT', None)
        env['PKG_CONFIG_PATH'] = env['PKG_CONFIG_LIBDIR'] = str(pcs)
        env['CFLAGS'] = env['CXXFLAGS'] = shlex.join(flags)
        env['LDFLAGS'] = shlex.join(flags)
        for library, source, options in [
            ('dav1d', dav1d, ['-Denable_tools=false', '-Denable_tests=false']),
            ('libplacebo', placebo, ['-Dopengl=enabled', '-Dvulkan=disabled', '-Dd3d11=disabled', '-Dshaderc=disabled', '-Dglslang=disabled', '-Dlcms=disabled', '-Dtests=false', '-Ddemos=false']),
        ]:
            builddir = work / name / library
            if not (builddir / 'build.ninja').exists():
                run(['meson', 'setup', builddir, source, '--prefix', prefix, '--cross-file', machine,
                     '--buildtype', 'release', '--default-library', 'static', *options], env=env)
            run(['meson', 'compile', '-C', builddir, '-j', jobs], env=env)
            run(['meson', 'install', '-C', builddir], env=env)
        ubuild = work / name / 'uchardet'
        run(['cmake', '-S', uchardet, '-B', ubuild, '-G', 'Ninja',
             '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
             '-DBUILD_SHARED_LIBS=OFF', '-DBUILD_BINARY=OFF', '-DCMAKE_POSITION_INDEPENDENT_CODE=ON',
             '-DCMAKE_SYSTEM_NAME=' + ('Darwin' if sdk == 'macosx' else 'iOS'),
             '-DCMAKE_OSX_ARCHITECTURES=' + arch, '-DCMAKE_OSX_SYSROOT=' + sysroot,
             '-DCMAKE_OSX_DEPLOYMENT_TARGET=' + ('12.0' if sdk == 'macosx' else '15.0'),
             '-DCMAKE_INSTALL_PREFIX=' + str(prefix)], env=env)
        run(['cmake', '--build', ubuild, '--parallel', jobs], env=env)
        run(['cmake', '--install', ubuild], env=env)
        fbuild = work / name / 'ffmpeg'
        fbuild.mkdir(exist_ok=True)
        if not (fbuild / 'config.h').exists():
            run([ffmpeg / 'configure', '--prefix=' + str(prefix), '--target-os=darwin',
                 '--arch=' + ('aarch64' if arch == 'arm64' else 'x86_64'), '--enable-cross-compile',
                 '--cc=clang', '--cxx=clang++', '--sysroot=' + sysroot,
                 '--extra-cflags=' + shlex.join(flags + ['-I' + str(include)]),
                 '--extra-ldflags=' + shlex.join(flags + ['-L' + str(libraries)]),
                 '--pkg-config=pkg-config', '--pkg-config-flags=--static',
                 '--enable-static', '--disable-shared', '--enable-pic', '--enable-version3',
                 '--disable-gpl', '--disable-nonfree', '--disable-autodetect', '--disable-doc',
                 '--disable-programs', '--disable-avdevice', '--disable-encoders', '--disable-muxers',
                 '--enable-encoder=png,mjpeg', '--enable-libdav1d', '--enable-zlib', '--enable-iconv',
                 '--enable-videotoolbox', '--enable-audiotoolbox', '--enable-securetransport'], cwd=fbuild, env=env)
        run(['make', '-j' + jobs], cwd=fbuild, env=env)
        run(['make', 'install'], cwd=fbuild, env=env)
        mbuild = work / name / 'mpv'
        options = ['-Dlibmpv=true', '-Dcplayer=false', '-Dgpl=false', '-Dbuild-date=false',
                   '-Dtests=false', '-Db_lundef=true', '-Dprefer_static=true', '-Dgl=enabled', '-Dplain-gl=enabled', '-Diconv=enabled',
                   '-Duchardet=enabled', '-Dlibavdevice=disabled', '-Dvulkan=disabled',
                   '-Dlua=disabled', '-Djavascript=disabled', '-Dlcms2=disabled', '-Dswift-build=disabled',
                   '-Dmacos-cocoa-cb=disabled', '-Dmacos-media-player=disabled', '-Dmacos-touchbar=disabled']
        options += (['-Dcocoa=enabled', '-Dcoreaudio=enabled', '-Dgl-cocoa=enabled', '-Dvideotoolbox-gl=enabled']
                    if sdk == 'macosx' else ['-Dcocoa=disabled', '-Dcoreaudio=disabled', '-Davfoundation=disabled', '-Daudiounit=enabled', '-Dios-gl=enabled', '-Dvideotoolbox-gl=disabled'])
        if not (mbuild / 'build.ninja').exists():
            run(['meson', 'setup', mbuild, mpv, '--prefix', prefix, '--cross-file', machine,
                 '--buildtype', 'release', '--default-library', 'shared', *options], env=env)
        run(['meson', 'compile', '-C', mbuild, '-j', jobs], env=env)
        binary = mbuild / 'libmpv.2.dylib'
        if not binary.is_file():raise ValueError(f'Missing native output: {binary}')
        frameworks[name] = framework(work / 'frameworks', name, binary,
                                     'MacOSX' if sdk == 'macosx' else 'iPhoneSimulator' if label == 'isimulator' else 'iPhoneOS')
        receipts.append({'target': name, 'sha256': hashlib.sha256((frameworks[name] / 'Mpv').read_bytes()).hexdigest(),
                         'unstripped_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                         'load_commands': output('otool', '-l', frameworks[name] / 'Mpv')})
    if target is not None:
        dist.mkdir(parents=True, exist_ok=True)
        shutil.copytree(frameworks[target], dist / target / 'Mpv.framework', dirs_exist_ok=True)
        write_provenance(dist, ffmpeg, dav1d, dependencies, receipts)
        return
    for label, names in [('ios-simulator', ['ios-sim-arm64', 'ios-sim-x64']), ('macos-universal', ['macos-arm64', 'macos-x64'])]:
        folder = work / 'frameworks' / label / 'Mpv.framework'
        folder.mkdir(parents=True, exist_ok=True)
        shutil.copy2(frameworks[names[0]] / 'Info.plist', folder / 'Info.plist')
        run(['lipo', '-create', *[frameworks[x] / 'Mpv' for x in names], '-output', folder / 'Mpv'])
        frameworks[label] = folder
    dist.mkdir(parents=True, exist_ok=True)
    for platform, names in [('ios', ['ios-arm64', 'ios-simulator']), ('macos', ['macos-universal'])]:
        out = work / 'xcframeworks' / platform / 'Mpv.xcframework'
        out.parent.mkdir(parents=True, exist_ok=True)
        run(['xcodebuild', '-create-xcframework', *[arg for name in names for arg in ['-framework', frameworks[name]]], '-output', out])
        archive = dist / f'libmpv-{platform}-0.42.0-ffmpeg-9.1.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:tar.add(out, arcname='Mpv.xcframework')
    write_provenance(dist, ffmpeg, dav1d, dependencies, receipts)


def write_provenance(dist, ffmpeg, dav1d, dependencies, receipts):
    data = {'mpv': MPV, 'libplacebo': PLACEBO,
            'patches': {'mpv-embedded-apple.patch': hashlib.sha256((HERE / 'mpv-embedded-apple.patch').read_bytes()).hexdigest()},
            'ffmpeg': output('git', '-C', ffmpeg, 'rev-parse', 'HEAD'),
            'dav1d': output('git', '-C', dav1d, 'rev-parse', 'HEAD'),
            'source_ref': os.environ.get('GITHUB_SHA', ''),
            'dependencies': dependencies, 'targets': receipts,
            'tools': {'python': output('python3', '--version'),
                      'cmake': output('cmake', '--version').splitlines()[0],
                      'ninja': output('ninja', '--version'),
                      'meson': output('meson', '--version'),
                      'xcode': output('xcodebuild', '-version'),
                      'clang': output('clang', '--version').splitlines()[0]}}
    (dist / 'provenance.json').write_text(json.dumps(data, indent=2) + '\n')



if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--target', choices=[item[0] for item in TARGETS])
    args = parser.parse_args()
    build(args.work.resolve(), args.output.resolve(), args.target)
