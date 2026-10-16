"""Check the generated PLL uses actual divider values, not just UI labels."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/video"))


class PllTests(unittest.TestCase):
    def module(self):
        path = ROOT / "scripts/video/gen_pll.py"
        self.assertTrue(path.is_file(), "PLL generation implementation missing")
        spec = importlib.util.spec_from_file_location("gen_pll", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_actual_dividers_produce_exact_both_frequencies(self):
        module = self.module()
        config = json.loads((ROOT / "fpga/pg2l100h/ip/video_pll.json").read_text())
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "video_pll.idf"
            module.create_idf(config, out)
            tree = ET.parse(out)
            params = {p.findtext("name"): p.findtext("value")
                      for p in tree.findall("./param_list/param")}
            vco = (27_000_000 * int(params["STATIC_RATIOM"]) *
                   float(params["STATIC_RATIO7"]) / int(params["STATIC_RATIOI"]))
            self.assertEqual(vco, 1_080_000_000)
            self.assertEqual(vco / float(params["STATIC_RATIO0"]), 40_000_000)
            self.assertEqual(vco / float(params["STATIC_RATIO1"]), 10_000_000)
            self.assertEqual(params["CLKOUT1_EN"], "true")
            self.assertEqual(tree.findtext("header/instance"), "video_pll")

    def test_rejects_request_without_matching_actual_dividers(self):
        module = self.module()
        config = json.loads((ROOT / "fpga/pg2l100h/ip/video_pll.json").read_text())
        config["pixel_divider"] = 7
        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "video_pll.idf"
            with self.assertRaisesRegex(ValueError, "actual PLL frequencies"):
                module.create_idf(config, out)
            self.assertFalse(out.exists())

    def test_generator_errors_cannot_reuse_old_wrapper_or_success_provenance(self):
        module=self.module()
        with tempfile.TemporaryDirectory() as directory:
            output=Path(directory)
            (output/'video_pll.v').write_text('\n'.join(
                f'localparam {name} = {value};' for name,value in
                {'STATIC_RATIOI':1,'STATIC_RATIOM':5,'STATIC_RATIOF':8,
                 'STATIC_RATIO0':27,'STATIC_RATIO1':108}.items()))
            (output/'provenance.json').write_text('{"status":"pass"}')
            with patch.object(module,'run_logged',return_value='Done: 10 error(s), 0 warning(s)'):
                with self.assertRaisesRegex(RuntimeError,'zero errors'):
                    module.generate(output)
            self.assertFalse((output/'video_pll.v').exists())
            result=json.loads((output/'provenance.json').read_text())
            self.assertEqual(result['status'],'fail')


if __name__ == "__main__":
    unittest.main()
