"""Generated system status and DDR attributes must agree across RTL and C."""
from pathlib import Path
import json
import tempfile
import unittest
from gen_cache_soc import generated

ROOT = Path(__file__).resolve().parents[2]


class CacheSocMapTests(unittest.TestCase):
    def changed(self, **changes):
        temporary = tempfile.TemporaryDirectory(prefix='cache-soc-config-', dir=ROOT/'build/cpu')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root/'config').mkdir()
        for name in ['cpu_cache_soc.json', 'cpu_cache.json', 'soc_map.json']:
            (root/'config'/name).write_bytes((ROOT/'config'/name).read_bytes())
        path = root/'config/cpu_cache_soc.json'
        value = json.loads(path.read_text(encoding='utf-8'))
        value.update(changes)
        path.write_text(json.dumps(value), encoding='utf-8')
        return root

    def test_exact_system_status_and_ddr_addresses(self):
        files = generated(ROOT)
        self.assertIn("32'h2002000c", files['rtl/soc/include/cpu_cache_map.vh'])
        self.assertIn('0x2002000cu', files['sw/runtime/cpu_cache_map.h'])
        self.assertIn("32'h80000000", files['rtl/soc/include/cpu_cache_map.vh'])
        self.assertIn("32'h88000000", files['rtl/soc/include/cpu_cache_map.vh'])

    def test_read_only_status_bits_have_distinct_meanings(self):
        files = generated(ROOT)
        self.assertIn('#define TRIHA_CPU_DDR_READY 0x00000001u', files['sw/runtime/cpu_cache_map.h'])
        self.assertIn('#define TRIHA_CPU_DDR_FAULT 0x00000002u', files['sw/runtime/cpu_cache_map.h'])

    def test_wrong_status_offset_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'status'):
            generated(self.changed(ddr_status_offset=8))

    def test_uncoordinated_fault_recovery_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'coordinated'):
            generated(self.changed(fault_recovery='cache_only_reset'))

    def test_unsynchronized_ddr_domain_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'clock'):
            generated(self.changed(ddr_interface_clock_domain='ddr_clk'))

    def test_renaming_both_domains_cannot_hide_missing_cpu_clock(self):
        with self.assertRaisesRegex(ValueError, 'clock'):
            generated(self.changed(clock_domain='ddr_clk', ddr_interface_clock_domain='ddr_clk'))


if __name__ == '__main__':
    unittest.main()
