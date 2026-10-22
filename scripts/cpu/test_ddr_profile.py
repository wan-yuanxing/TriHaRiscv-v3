"""The diagnostic profile must describe exactly the measured CSR window."""
import unittest
from ddr_profile import parse_profile


def log():
    return '''CPU_DDR_PROFILE_WINDOW cycles=100 start=17 stop=117 reads=2
CPU_DDR_PROFILE_ISSUE issue=20 cancel=0 lsu=60 pipe=0 div=0 csr=0 frontend=10 unit=0 dependency=5 other=5 wb=19 stores=2
CPU_DDR_PROFILE_DC reads=3 writes=2 read_hits=2 read_misses=1 uncached_reads=0 store_hits=2 store_misses=0 uncached_writes=0 refills=1 lower_writes=2
CPU_DDR_PROFILE_DC_STATES idle=20 lookup=5 refill_req=1 refill=9 relookup=1 response=5 write_req=2 write_wait=55 store_update=2 uncached_req=0 uncached_wait=0 reset=0 invalidate=0 flush=0
CPU_DDR_PROFILE_BRIDGE idle=25 collect=5 wpre=2 waddr=3 wdata=5 vpre=2 vaddr=8 vdata=35 raddr=3 rdata=5 rpre=2 rresp=3 bresp=2 quarantine=0 native_aw=2 native_ar=3 native_wbeats=2 native_rbeats=3
'''


class ProfileTests(unittest.TestCase):
    def test_writeback_classifies_write_allocation_and_coalesced_stores(self):
        from ddr_profile import DC_STATES_WB
        text = log().replace('refills=1 lower_writes=2',
            'refills=1 lower_writes=0 writeback_words=0 uncached_lower_writes=0')
        states = ' '.join(k+'='+str(100 if k=='idle' else 0) for k in DC_STATES_WB)
        text = '\n'.join(('CPU_DDR_PROFILE_DC_STATES '+states if line.startswith('CPU_DDR_PROFILE_DC_STATES ') else line)
            for line in text.splitlines())+'\nCPU_DDR_PROFILE_POLICY write_back=1\n'
        row = parse_profile(text, 100)
        self.assertEqual(row['dcache']['lower_writes'], 0)
        self.assertEqual(row['write_policy'], 'write_back')
        for bad in (text.replace('lower_writes=0', 'lower_writes=1', 1),
                    text.replace('refills=1', 'refills=2')):
            with self.assertRaises(ValueError):
                parse_profile(bad, 100)

    def test_exact_window_and_distinct_overlapping_observations(self):
        row = parse_profile(log(), 100)
        self.assertEqual(row['cycles'], 100)
        self.assertEqual(row['issue']['lsu'], 60)
        self.assertEqual(row['dcache']['read_hit_rate'], 2/3)
        self.assertEqual(row['dcache_states']['write_wait'], 55)
        self.assertEqual(row['bridge_states']['vdata'], 35)
        self.assertFalse(row['physical_board_profile'])

    def test_wrong_window_or_category_sum(self):
        for text in (log().replace('stop=117', 'stop=118'),
                     log().replace('reads=2\n', 'reads=3\n', 1),
                     log().replace('lsu=60', 'lsu=59'),
                     log().replace('idle=20', 'idle=21'),
                     log().replace('vdata=35', 'vdata=34')):
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_profile(text, 100)
        with self.assertRaises(ValueError):
            parse_profile(log(), 99)

    def test_missing_duplicate_and_inconsistent_counts(self):
        for text in (log().replace(' stores=2', ''), log()+log().splitlines()[0]+'\n',
                     log().replace('read_hits=2', 'read_hits=3'),
                     log().replace('store_hits=2', 'store_hits=1'),
                     log().replace('lower_writes=2', 'lower_writes=3')):
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_profile(text, 100)


if __name__ == '__main__':
    unittest.main()
