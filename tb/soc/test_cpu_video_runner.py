"""Fail-closed source-freeze contracts for the explicit CPU diagnostic."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("cpu_video_runner", ROOT / "scripts/soc/run_cpu_video.py")
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class FreezeTests(unittest.TestCase):
    def test_unsafe_export_paths(self):
        for value in ("../rtl/cpu/x.v", "/rtl/cpu/x.v", "C:/x.v", "rtl\\cpu\\x.v", "rtl/cpu/../../x", "rtl//cpu/x.v"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                runner.safe_relative(value)

    def test_missing_pinned_object(self):
        fixture = runner.load_fixture()
        fixture["cpu_revision"] = "0" * 40
        with tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory, self.assertRaisesRegex(RuntimeError, "pinned CPU object"):
            runner.export_cpu(fixture, Path(directory))

    def test_export_and_corruption(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory:
            target = Path(directory)
            records = runner.export_cpu(runner.load_fixture(), target)
            runner.verify_snapshots(target, records)
            source = target / records[0]["path"]
            source.write_bytes(source.read_bytes() + b"\ncorrupt\n")
            with self.assertRaisesRegex(RuntimeError, "snapshot changed"):
                runner.verify_snapshots(target, records)

    def test_stale_generated_header(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory:
            target = Path(directory)
            for relative in ("config/video_regs.json", "config/video_cfg.json", "config/video_edid.hex", "sw/include/video_regs.h", "sw/include/video_cfg.h", "rtl/video/include/video_regs.vh", "rtl/video/include/video_cfg.vh", "rtl/video/include/video_edid.vh"):
                output = target / relative
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes((ROOT / relative).read_bytes())
            runner.check_generated_headers(target)
            (target / "sw/include/video_regs.h").write_text("stale\n", encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "stale generated"):
                runner.check_generated_headers(target)

    def test_revision_is_exact(self):
        fixture = runner.load_fixture()
        self.assertEqual(fixture["cpu_revision"], "8a2a07cf02ae758131a0235887ea244b16c5a1f4")
        self.assertIn("rtl/cpu/vendor/LICENSE", fixture["cpu_blobs"])
        self.assertIn("rtl/cpu/ADAPTATIONS.json", fixture["cpu_blobs"])

    def test_geometry_drift_rejected(self):
        fixture = runner.load_fixture()
        with tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory:
            path = Path(directory) / 'fixture.json'
            for key, value in (('width', 40), ('height', True), ('pad_top', 0)):
                changed = {**fixture, 'test_geometry': {**fixture['test_geometry'], key: value}}
                path.write_text(json.dumps(changed), encoding='utf-8')
                with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'geometry'):
                    runner.load_fixture(path)

    def test_copy_must_match_original_hash(self):
        with tempfile.TemporaryDirectory(dir=ROOT / 'build') as directory:
            source = Path(directory) / 'source.v'
            source.write_bytes(b'original A')
            relative = source.relative_to(ROOT).as_posix()
            expected = {relative: runner.sha256(source)}
            source.write_bytes(b'changed B')
            with self.assertRaisesRegex(RuntimeError, 'copy differs from frozen input'):
                runner.copy_inputs([relative], Path(directory) / 'snapshot', expected)


if __name__ == "__main__":
    unittest.main()
