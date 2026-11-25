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


class SemanticsIsolationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.sdk = Path(self.temp.name) / "sdk"
        self.source = self.sdk / "packages/flutter/test"
        (self.source / "semantics").mkdir(parents=True)
        (self.source / "widgets").mkdir()
        self.test = self.source / "semantics/semantics_update_test.dart"
        self.test.write_bytes(b"// exact fixture\nvoid main() { expect(value, 1); }\n")
        self.helper = self.source / "widgets/button_tester.dart"
        self.helper.write_bytes(b"// original helper\n")
        self.config = "\n".join([
            "import '_goldens_io.dart' if (dart.library.js_interop) '_goldens_web.dart' as flutter_goldens;",
            "debugCheckIntrinsicSizes = true;",
            "WidgetController.hitTestWarningShouldBeFatal = true;",
            "if (leakTracking) LeakTesting.enable();",
            "return flutter_goldens.testExecutable(testMain);",
        ])
        (self.source / "flutter_test_config.dart").write_text(self.config)
        self.destination = Path(self.temp.name) / "isolated/test"

    def test_assertions_helpers_and_sdk_sources_remain_byte_exact(self):
        selected = PREPARE.stage_semantics_test(self.sdk, self.destination)
        self.assertEqual(selected.read_bytes(), self.test.read_bytes())
        self.assertEqual((self.destination / "widgets/button_tester.dart").read_bytes(), self.helper.read_bytes())
        config = (self.destination / "flutter_test_config.dart").read_text()
        for check in ["debugCheckIntrinsicSizes = true", "hitTestWarningShouldBeFatal = true", "LeakTesting.enable()"]:
            self.assertIn(check, config)
        self.assertIn("Future<void>.sync(testMain)", config)
        self.assertEqual((self.source / "flutter_test_config.dart").read_text(), self.config)

    def test_image_assertions_cannot_be_silently_excluded(self):
        self.test.write_text("expect(image, matchesGoldenFile('image.png'));")
        with self.assertRaisesRegex(ValueError, "refuses image assertions"):
            PREPARE.stage_semantics_test(self.sdk, self.destination)

    def test_unrecognized_sdk_configuration_requires_review(self):
        (self.source / "flutter_test_config.dart").write_text("new configuration")
        with self.assertRaisesRegex(ValueError, "configuration changed"):
            PREPARE.stage_semantics_test(self.sdk, self.destination)
