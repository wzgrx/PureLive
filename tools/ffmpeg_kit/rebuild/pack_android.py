#!/usr/bin/env python3
"""Replace only the native payload of the verified FFmpegKit 0.11.2 API AAR."""
import argparse
import hashlib
import subprocess
import tempfile
from pathlib import Path
import zipfile


BASELINE_SHA256 = "b4809b1b6d5cca73f13c7fe1640642a0dd6507a64e82264d83eeba8992b848b6"
ABIS = {"arm64-v8a", "armeabi-v7a", "x86_64"}


def pack(baseline, jni, output, strip_tool):
    if hashlib.sha256(baseline.read_bytes()).hexdigest() != BASELINE_SHA256:
        raise ValueError("The preserved Java API AAR does not match the pinned source")
    replacement = {f"jni/{abi}/libffmpegkit.so": (jni / abi / "libffmpegkit.so").read_bytes() for abi in ABIS}
    if any(not data.startswith(b"\x7fELF") for data in replacement.values()):
        raise ValueError("Native payload is not ELF; no archive was written")
    # Keep unstripped build products for debugging. Only strip copies that
    # enter the distributable AAR, using the same Android NDK toolchain.
    with tempfile.TemporaryDirectory(prefix="ffmpeg-kit-strip-") as folder:
        for name, data in replacement.items():
            binary = Path(folder) / name.split("/")[1]
            binary.write_bytes(data)
            subprocess.run([str(strip_tool), "--strip-unneeded", str(binary)], check=True)
            replacement[name] = binary.read_bytes()
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(baseline) as source:
        if not replacement.keys() <= set(source.namelist()):
            raise ValueError("The Java API AAR has an unexpected ABI layout")
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as result:
            for item in source.infolist():
                result.writestr(item, replacement.get(item.filename, source.read(item.filename)))
    with zipfile.ZipFile(baseline) as source, zipfile.ZipFile(output) as result:
        if source.namelist() != result.namelist():
            raise ValueError("The preserved Java API archive layout changed")
        for name in source.namelist():
            if name not in replacement and source.read(name) != result.read(name):
                raise ValueError(f"The preserved Java API entry changed: {name}")
    print(f"FFmpegKit: Java API 0.11.2 preserved; three native ABIs packaged in {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("jni", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--strip-tool", type=Path, default=Path("llvm-strip"))
    args = parser.parse_args()
    pack(args.baseline, args.jni, args.output, args.strip_tool)
