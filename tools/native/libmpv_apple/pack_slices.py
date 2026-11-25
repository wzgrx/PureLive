#!/usr/bin/env python3
"""Validate same-source Apple slices, then assemble universal XCFrameworks."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile

TARGETS = ['ios-arm64', 'ios-sim-arm64', 'ios-sim-x64', 'macos-arm64', 'macos-x64']
COMMON = ['mpv', 'ffmpeg', 'libplacebo', 'dav1d', 'source_ref', 'dependencies', 'tools', 'patches']


def load_slices(root):
    frameworks, receipts = {}, []
    common = None
    for target in TARGETS:
        folder = root / ('libmpv-slice-' + target)
        data = json.loads((folder / 'provenance.json').read_text())
        candidate = {key: data[key] for key in COMMON}
        if common is None: common = candidate
        if candidate != common: raise ValueError('Apple slices do not share one source and toolchain')
        if len(data['targets']) != 1 or data['targets'][0]['target'] != target:
            raise ValueError('Unexpected Apple slice target')
        receipt = data['targets'][0]
        framework = folder / target / 'Mpv.framework'
        binary = framework / 'Mpv'
        if binary.is_symlink() or not binary.resolve().is_relative_to(root.resolve()):
            raise ValueError('Apple binary escapes the artifact root')
        if hashlib.sha256(binary.read_bytes()).hexdigest() != receipt['sha256']:
            raise ValueError('Apple slice binary checksum differs')
        info = plistlib.loads((framework / 'Info.plist').read_bytes())
        expected = '12.0' if target.startswith('macos') else '15.0'
        if info['MinimumOSVersion'] != expected: raise ValueError('Apple minimum OS changed')
        frameworks[target] = framework
        receipts.append(receipt)
    return frameworks, common, receipts


def run(*args):
    subprocess.run(list(map(str, args)), check=True)


def pack(root, output, work):
    frameworks, common, receipts = load_slices(root)
    work.mkdir(parents=True, exist_ok=True)
    output.mkdir(parents=True, exist_ok=True)
    for label, names in [('ios-simulator', ['ios-sim-arm64', 'ios-sim-x64']),
                         ('macos-universal', ['macos-arm64', 'macos-x64'])]:
        dest = work / label / 'Mpv.framework'
        dest.mkdir(parents=True)
        shutil.copy2(frameworks[names[0]] / 'Info.plist', dest / 'Info.plist')
        run('lipo', '-create', *[frameworks[name] / 'Mpv' for name in names], '-output', dest / 'Mpv')
        frameworks[label] = dest
    for platform, names in [('ios', ['ios-arm64', 'ios-simulator']), ('macos', ['macos-universal'])]:
        dest = work / platform / 'Mpv.xcframework'
        dest.parent.mkdir(parents=True, exist_ok=True)
        run('xcodebuild', '-create-xcframework', *[arg for name in names for arg in ['-framework', frameworks[name]]], '-output', dest)
        archive = output / f'libmpv-{platform}-0.42.0-ffmpeg-9.1.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar: tar.add(dest, arcname='Mpv.xcframework')
    (output / 'provenance.json').write_text(json.dumps({**common, 'targets': receipts}, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--slices', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    pack(args.slices.resolve(), args.output.resolve(), args.work.resolve())
