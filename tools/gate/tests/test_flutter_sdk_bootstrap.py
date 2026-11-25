"""SDK dependency bootstrap must preserve known sources and unknown changes."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("flutter_prepare", ROOT / "tools/flutter_sdk/prepare.py")
PREPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARE)


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.sdk = Path(self.temp.name)
        self.before = b"upstream lock\n"
        self.after = b"same dependencies, raised SDK floor\n"
        self.lock = self.sdk / "pubspec.lock"
        self.lock.write_bytes(self.before)
        policy = {"test_bootstrap_lock": {
            "before_lf_sha256": hashlib.sha256(self.before).hexdigest(),
            "resolved_lf_sha256": hashlib.sha256(self.after).hexdigest(),
        }}
        (self.sdk / "patch.json").write_text(json.dumps(policy))
        self.addCleanup(patch.stopall)
        patch.object(PREPARE, "HERE", self.sdk).start()
        self.validate = patch.object(PREPARE, "prepare").start()

    def test_expected_resolution_preserves_upstream_lock(self):
        with patch.object(PREPARE.subprocess, "run", side_effect=lambda *a, **kw: self.lock.write_bytes(self.after)):
            PREPARE.bootstrap_tests(self.sdk)
        self.assertEqual(self.lock.read_bytes(), self.before)
        self.validate.assert_called_once_with(self.sdk)

    def test_unknown_resolution_is_preserved_for_diagnosis(self):
        unknown = b"unexpected dependency change\n"
        with patch.object(PREPARE.subprocess, "run", side_effect=lambda *a, **kw: self.lock.write_bytes(unknown)):
            with self.assertRaisesRegex(ValueError, "changed unexpectedly"):
                PREPARE.bootstrap_tests(self.sdk)
        self.assertEqual(self.lock.read_bytes(), unknown)
        self.validate.assert_not_called()

    def test_failed_pub_restores_only_a_known_lock(self):
        def fail(*args, **kwargs):
            self.lock.write_bytes(self.after)
            raise subprocess.CalledProcessError(1, "pub get")
        with patch.object(PREPARE.subprocess, "run", side_effect=fail):
            with self.assertRaises(subprocess.CalledProcessError):
                PREPARE.bootstrap_tests(self.sdk)
        self.assertEqual(self.lock.read_bytes(), self.before)

    def test_preexisting_user_edit_is_not_touched(self):
        self.lock.write_bytes(b"user edit")
        with patch.object(PREPARE.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "unchanged upstream lock"):
                PREPARE.bootstrap_tests(self.sdk)
        run.assert_not_called()
        self.assertEqual(self.lock.read_bytes(), b"user edit")
