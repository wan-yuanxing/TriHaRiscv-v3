"""Board contracts: exact clock arithmetic, safe pins, and stale generated data."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BoardContracts(unittest.TestCase):
    def setUp(self):
        path = ROOT / "scripts/soc/gen_board.py"
        self.assertTrue(path.is_file(), "board configuration generator has not been implemented")
        spec = importlib.util.spec_from_file_location("cpu_board_generator", path)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.config = json.loads((ROOT / "config/cpu_board.json").read_text(encoding="utf-8"))

    def test_exact_100mhz_recipe(self):
        self.assertEqual(self.module.validate(self.config)[2], 100_000_000)

    def test_generated_high_pfd_pll_is_checked_from_actual_parameters(self):
        import board_pll
        self.assertTrue(hasattr(board_pll, "review_wrapper"), "generated divider review is missing")
        self.config["pll"].update(input_divider=1, multiplier=1, feedback_divider=8, output_divider=10)
        wrapper = 'CLKIN_FREQ=125.0; STATIC_RATIOI=1; STATIC_RATIOM=1; STATIC_RATIOF=8; STATIC_RATIO0=10; BANDWIDTH="HIGH";'
        result = board_pll.review_wrapper(self.config, wrapper)
        self.assertEqual((result["pfd_hz"], result["vco_hz"], result["cpu_hz"]), (125_000_000, 1_000_000_000, 100_000_000))
        with self.assertRaisesRegex(ValueError, "STATIC_RATIO0"):
            board_pll.review_wrapper(self.config, wrapper.replace("STATIC_RATIO0=10", "STATIC_RATIO0=9"))

    def test_approximate_frequency_is_rejected(self):
        self.config["pll"]["output_divider"] = 9
        with self.assertRaisesRegex(ValueError, "100MHz"):
            self.module.validate(self.config)

    def test_generated_pll_bandwidth_must_match_requested_setting(self):
        import board_pll
        self.config['pll']['bandwidth'] = 'HIGH'
        wrapper = ('CLKIN_FREQ=125.0; STATIC_RATIOI=1; STATIC_RATIOM=1; '
                   'STATIC_RATIOF=8; STATIC_RATIO0=10; BANDWIDTH="OPTIMIZED";')
        with self.assertRaisesRegex(ValueError, 'BANDWIDTH'):
            board_pll.review_wrapper(self.config, wrapper)
        checked = board_pll.review_wrapper(self.config, wrapper.replace('OPTIMIZED', 'HIGH'))
        self.assertEqual(checked['actual_parameters']['BANDWIDTH'], 'HIGH')

    def test_unknown_pll_bandwidth_is_rejected(self):
        self.config['pll']['bandwidth'] = 'INVALID'
        with self.assertRaisesRegex(ValueError, 'bandwidth'):
            self.module.validate(self.config)

    def test_out_of_range_pfd_is_rejected(self):
        self.config["pll"].update(input_divider=25, multiplier=20)
        with self.assertRaisesRegex(ValueError, "PFD"):
            self.module.validate(self.config)

    def test_reused_board_pin_is_rejected(self):
        self.config["pins"]["uart_tx_o"]["location"] = "C22"
        with self.assertRaisesRegex(ValueError, "duplicate"):
            self.module.validate(self.config)

    def test_unknown_port_is_rejected(self):
        self.config["pins"]["unconnected_o"] = self.config["pins"]["uart_tx_o"].copy()
        with self.assertRaisesRegex(ValueError, "ports"):
            self.module.validate(self.config)

    def test_generated_constraints_detect_drift(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
            output = Path(directory) / "board.fdc"
            self.module.generate(self.config, output, check=False)
            text = output.read_text(encoding="utf-8")
            self.assertIn("-multiply_by 4 -divide_by 5", text)
            self.assertNotIn("set_false_path", text)
            self.assertNotIn("set_multicycle_path", text)
            self.module.generate(self.config, output, check=True)
            output.write_text(text.replace("2.000", "3.000"), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "drift"):
                self.module.generate(self.config, output, check=True)

    def test_real_windows_nm_address(self):
        import run_board
        self.assertTrue(hasattr(run_board, "initialized_address"), "Windows nm symbol parsing is missing")
        self.assertEqual(run_board.initialized_address("00010640 00000004 t initialized\r\n"), 0x10640)

    def test_ambiguous_nm_symbol_is_rejected(self):
        import run_board
        self.assertTrue(hasattr(run_board, "initialized_address"), "Windows nm symbol parsing is missing")
        with self.assertRaisesRegex(ValueError, "initialized"):
            run_board.initialized_address("00010640 00000004 t initialized\r\n00010644 00000004 t initialized\r\n")


if __name__ == "__main__":
    unittest.main()
