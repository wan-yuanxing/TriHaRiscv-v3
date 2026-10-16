"""Verify reference staging rejects changed bytes and unsafe member paths."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReferenceTests(unittest.TestCase):
    def fixture(self, root, *, altered_hash=False, destination="rtl/sample.v"):
        data = b"module sample; endmodule\n"
        archive = root / "reference.tar"
        with tarfile.open(archive, "w") as stream:
            info = tarfile.TarInfo("example/rtl/sample.v")
            info.size = len(data)
            stream.addfile(info, io.BytesIO(data))
        manifest = root / "manifest.json"
        manifest.write_text(json.dumps({"schema_version": 1, "references": {
            "sample": {"archive": "reference.tar",
                       "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                       "files": [{"member": "example/rtl/sample.v", "path": destination,
                                  "sha256": "0" * 64 if altered_hash else
                                  hashlib.sha256(data).hexdigest()}]}}}))
        return manifest, data

    def invoke(self, root, manifest):
        return subprocess.run([sys.executable, str(ROOT / "scripts/video/prepare_reference.py"),
                               "--manifest", str(manifest), "--board-root", str(root),
                               "--output", str(root / "output"), "--reference", "sample"],
                              capture_output=True, text=True, timeout=30)

    def test_stages_exact_verified_bytes(self):
        with tempfile.TemporaryDirectory(prefix="reference path ") as directory:
            root = Path(directory)
            manifest, expected = self.fixture(root)
            result = self.invoke(root, manifest)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((root / "output/sample/rtl/sample.v").read_bytes(), expected)

    def test_changed_source_does_not_publish_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, _ = self.fixture(root, altered_hash=True)
            result = self.invoke(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("hash mismatch", result.stderr)
            self.assertFalse((root / "output/sample").exists())

    def test_rejects_destination_escape(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, _ = self.fixture(root, destination="../../escaped.v")
            result = self.invoke(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unsafe relative path", result.stderr)
            self.assertFalse((root / "escaped.v").exists())

    def test_rejects_reserved_provenance_before_publishing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, _ = self.fixture(root, destination="provenance.json")
            result = self.invoke(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("reserved metadata", result.stderr)
            self.assertFalse((root / "output/sample").exists())

    def test_rejects_windows_trailing_dot_and_space_aliases(self):
        for destination in ("provenance.json.", "provenance.json "):
            with self.subTest(destination=destination), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                manifest, _ = self.fixture(root, destination=destination)
                result = self.invoke(root, manifest)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("unsafe relative path", result.stderr)
                self.assertFalse((root / "output/sample").exists())

    def test_rejects_escaping_metadata_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, _ = self.fixture(root)
            destination = root / "output/sample"
            destination.mkdir(parents=True)
            outside = root / "outside.json"
            outside.write_bytes(b"preserve me")
            try:
                (destination / "provenance.json").symlink_to(outside)
            except OSError as error:
                self.skipTest(f"OS symlink creation unavailable (winerror={getattr(error, 'winerror', None)})")
            result = self.invoke(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unsafe metadata", result.stderr)
            self.assertEqual(outside.read_bytes(), b"preserve me")
            self.assertFalse((destination / "rtl").exists())

    def test_rejects_metadata_hardlink_without_altering_original(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest, _ = self.fixture(root)
            destination = root / "output/sample"
            destination.mkdir(parents=True)
            outside = root / "outside.json"
            outside.write_bytes(b"preserve me")
            os.link(outside, destination / "provenance.json")
            result = self.invoke(root, manifest)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unsafe metadata", result.stderr)
            self.assertEqual(outside.read_bytes(), b"preserve me")
            self.assertFalse((destination / "rtl").exists())


if __name__ == "__main__":
    unittest.main()
