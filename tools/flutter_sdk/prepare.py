#!/usr/bin/env python3
"""Validate or explicitly prepare the isolated, pinned Flutter SDK for this app."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent


def digest(path, *, text=False):
    data = path.read_bytes()
    return hashlib.sha256(data.replace(b"\r\n", b"\n") if text else data).hexdigest()


def git(sdk, *args):
    return subprocess.check_output(["git", "-C", str(sdk), *args], text=True).strip()


def prepare(sdk, *, apply=False):
    policy = json.loads((HERE / "patch.json").read_text(encoding="utf-8"))
    env = dict(
        line.split("=", 1)
        for line in (ROOT / "toolchain.env").read_text(encoding="utf-8").splitlines()
        if line and not line.startswith("#") and "=" in line
    )
    if env["FLUTTER_REVISION"] != policy["base_revision"]:
        raise ValueError("toolchain.env and Flutter patch revision disagree")
    patch = HERE / policy["patch"]
    if digest(patch) != env["FLUTTER_PATCH_SHA256"] or digest(patch) != policy["patch_sha256"]:
        raise ValueError("Flutter patch checksum differs; no SDK files were changed")
    if git(sdk, "rev-parse", "HEAD") != policy["base_revision"]:
        raise ValueError("Unsupported SDK revision; use a separate SDK at the pinned revision")
    changed = set(git(sdk, "diff", "HEAD", "--name-only").splitlines())
    allowed = set(policy["files"])
    if not changed.issubset(allowed):
        raise ValueError("SDK has unrelated tracked changes; preserve it and use a clean copy")
    states = {
        name: digest(sdk / name, text=True)
        for name in policy["files"]
    }
    if all(states[name] == values["after_lf_sha256"] for name, values in policy["files"].items()):
        print("Flutter SDK: pinned upstream semantics patch verified")
        return
    if not all(states[name] == values["before_lf_sha256"] for name, values in policy["files"].items()):
        raise ValueError("SDK files differ or patch is partly applied; no SDK files were changed")
    if not apply:
        raise ValueError("SDK patch missing: run python3 tools/flutter_sdk/prepare.py --apply --sdk <isolated-sdk>")
    subprocess.run(["git", "-C", str(sdk), "apply", "--check", str(patch)], check=True)
    subprocess.run(["git", "-C", str(sdk), "apply", str(patch)], check=True)
    for name, values in policy["files"].items():
        if digest(sdk / name, text=True) != values["after_lf_sha256"]:
            raise ValueError("Patched SDK output differs; preserve this copy for diagnosis")
    print("Flutter SDK: applied and verified official merged semantics patch")



def bootstrap_tests(sdk):
    """Resolve SDK test caches, preserving the pinned upstream source lock."""
    policy = json.loads((HERE / "patch.json").read_text(encoding="utf-8"))
    expected = policy["test_bootstrap_lock"]
    lock = sdk / "pubspec.lock"
    before = lock.read_bytes()
    if digest(lock, text=True) != expected["before_lf_sha256"]:
        raise ValueError("SDK test bootstrap requires the unchanged upstream lock")
    flutter = sdk / "bin" / ("flutter.bat" if os.name == "nt" else "flutter")
    try:
        subprocess.run([str(flutter), "pub", "get"], cwd=sdk, check=True)
    finally:
        resolved = digest(lock, text=True)
        if resolved not in (expected["before_lf_sha256"], expected["resolved_lf_sha256"]):
            raise ValueError("SDK dependency resolution changed unexpectedly; preserve this SDK for diagnosis")
        # Pub only raises the SDK floor of this pinned lock on Dart 3.14.
        # Restore these known bytes; never reset unrelated user changes.
        lock.write_bytes(before)
    prepare(sdk)
    print("Flutter SDK: test dependencies prepared; upstream lock preserved")



def stage_semantics_test(sdk, destination):
    """Retain exact upstream semantic assertions without Skia Gold bootstrap.

    The SDK-wide config fetches image expectations before even registering
    this non-golden file. Stage its exact source/helper and preserve all
    intrinsic-size, hit-test and leak-tracking setup; change only the unused
    network image-comparator initialization. Refuse image tests entirely.
    """
    test_root = sdk / "packages/flutter/test"
    inputs = ["semantics/semantics_update_test.dart", "widgets/button_tester.dart"]
    for name in inputs:
        data = (test_root / name).read_bytes()
        if b"golden" in data.lower() or b"matchesReferenceImage" in data:
            raise ValueError("SDK semantics isolation refuses image assertions")
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    config = (test_root / "flutter_test_config.dart").read_text(encoding="utf-8")
    golden_import = "import '_goldens_io.dart' if (dart.library.js_interop) '_goldens_web.dart' as flutter_goldens;"
    golden_call = "return flutter_goldens.testExecutable(testMain);"
    if config.count(golden_import) != 1 or config.count(golden_call) != 1:
        raise ValueError("SDK test configuration changed; preserve it for review")
    config = config.replace(golden_import, "", 1).replace(golden_call, "return Future<void>.sync(testMain);", 1)
    config = config.replace("// Enable golden file testing using Skia Gold.",
                            "// Exact non-golden semantics fixture: no Skia Gold connection is needed.", 1)
    (destination / "flutter_test_config.dart").write_text(config, encoding="utf-8")
    print("Flutter SDK: exact non-golden semantics inputs " + json.dumps({name: digest(test_root / name) for name in inputs}))
    return destination / inputs[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="Explicitly modify an isolated SDK copy")
    mode.add_argument("--check", action="store_true", help="Check only (the default); never modify SDK sources")
    mode.add_argument("--test", action="store_true", help="Check then run the upstream semantics regression file")
    parser.add_argument("--bootstrap-tests", action="store_true", help="Explicitly prepare SDK test dependency caches and preserve its known lock")
    args = parser.parse_args()
    sdk = args.sdk
    if sdk is None:
        configured = os.environ.get("FLUTTER_ROOT")
        executable = shutil.which("flutter")
        if configured:
            sdk = Path(configured)
        elif executable:
            sdk = Path(executable).resolve().parent.parent
        else:
            parser.error("Set FLUTTER_ROOT or pass --sdk")
    sdk = sdk.resolve(strict=True)
    prepare(sdk, apply=args.apply)
    if args.bootstrap_tests:
        bootstrap_tests(sdk)
    if args.test:
        flutter = sdk / "bin" / ("flutter.bat" if os.name == "nt" else "flutter")
        with tempfile.TemporaryDirectory(prefix="purelive-sdk-semantics-") as temporary:
            test = stage_semantics_test(sdk, Path(temporary) / "test")
            subprocess.run(
                [str(flutter), "test", "--no-pub", str(test), "--reporter", "expanded"],
                cwd=sdk / "packages/flutter",
                check=True,
            )


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"Flutter SDK: {error}", file=sys.stderr)
        sys.exit(1)
