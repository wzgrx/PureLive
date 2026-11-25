"""Reject incomplete, mixed-source or modified native slice artifacts."""
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('apple_native_pack', ROOT / 'tools/native/libmpv_apple/pack_slices.py')
PACK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACK)


class NativeSlices(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for target in PACK.TARGETS:
            folder = self.root / ('libmpv-slice-' + target)
            framework = folder / target / 'Mpv.framework'
            framework.mkdir(parents=True)
            binary = target.encode()
            (framework / 'Mpv').write_bytes(binary)
            (framework / 'Info.plist').write_bytes(plistlib.dumps({'MinimumOSVersion': '12.0' if target.startswith('macos') else '15.0'}))
            data = {key: 'one-verified-source' for key in PACK.COMMON}
            data['targets'] = [{'target': target, 'sha256': hashlib.sha256(binary).hexdigest()}]
            (folder / 'provenance.json').write_text(json.dumps(data))

    def test_complete_same_source_inputs_are_accepted(self):
        frameworks, common, receipts = PACK.load_slices(self.root)
        self.assertEqual(set(frameworks), set(PACK.TARGETS))
        self.assertEqual(len(receipts), 5)

    def test_mixed_commit_is_rejected_before_native_commands(self):
        path = self.root / 'libmpv-slice-ios-arm64/provenance.json'
        data = json.loads(path.read_text())
        data['source_ref'] = 'another-commit'
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'one source'):
            PACK.load_slices(self.root)

    def test_modified_binary_is_rejected(self):
        path = self.root / 'libmpv-slice-ios-arm64/ios-arm64/Mpv.framework/Mpv'
        path.write_bytes(b'not the recorded binary')
        with self.assertRaisesRegex(ValueError, 'checksum differs'):
            PACK.load_slices(self.root)

    def test_missing_slice_cannot_produce_partial_release(self):
        path = self.root / 'libmpv-slice-ios-arm64/provenance.json'
        path.unlink()
        with self.assertRaises(FileNotFoundError):
            PACK.load_slices(self.root)
