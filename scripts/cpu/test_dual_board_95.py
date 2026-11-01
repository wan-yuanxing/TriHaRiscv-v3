from pathlib import Path
import importlib.util,json,sys,tempfile,unittest
from decimal import Decimal,ROUND_DOWN
P=Path(__file__).resolve().parents[2]/'build/cpu/dual-board-v83-95mhz-20261101/project'
sys.path.insert(0,str(P/'scripts/soc'))
import gen_board,coremark_board

def report(hz=95000000):
    ticks=1250000000
    fixed=lambda n:format(n.quantize(Decimal('0.000001'),rounding=ROUND_DOWN),'f')
    score=Decimal(5000)*hz/ticks
    return f'''CPU_COREMARK_START iterations=5000 clock_hz={hz}
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
Correct operation validated.
CPU_COREMARK_STATUS errors=0 short=0
CPU_COREMARK_TIME seconds={fixed(Decimal(ticks)/hz)} cycles_hi=0 cycles_lo={ticks} clock_hz={hz}
CoreMark       : {fixed(score)}
CoreMark/MHz   : 4.000000
CPU core LUTs  : 9677
CoreMark/LUTs  : {fixed(score/9677)}
CPU_COREMARK_BOARD_PASS iterations=5000
'''

class ClockBoundary(unittest.TestCase):
    def test_generator_uses_measured_locking_bandwidth(self):
        root=Path(__file__).resolve().parents[2]
        spec=importlib.util.spec_from_file_location('board95_generator_regression',root/'scripts/cpu/prepare_dual_board_95.py')
        helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
        with tempfile.TemporaryDirectory(prefix='board95-pll-test-',dir=root/'build/cpu') as directory:
            temporary=Path(directory).resolve()
            self.assertTrue(temporary.is_relative_to((root/'build/cpu').resolve()))
            helper.DEST=temporary/'candidate';helper.P=helper.DEST/'project'
            helper.clone();helper.adapt()
            cfg=json.loads((helper.P/'config/cpu_board.json').read_text())
            self.assertEqual(cfg['pll']['bandwidth'],'OPTIMIZED')
            self.assertEqual(cfg['cpu_hz'],95000000)
    def test_pll_ratio_is_exact95(self):
        cfg=json.loads((P/'config/cpu_board.json').read_text())
        self.assertEqual(gen_board.validate(cfg)[2],95000000)
    def test_accepts_cycle_correct95_measurement(self):
        d=coremark_board.review_output(report(),expected_luts=9677)
        self.assertEqual(d['clock_hz'],95000000)
        self.assertEqual(d['coremark'],380)
        self.assertEqual(d['coremark_per_mhz'],4)
    def test_rejects_spoofed100_measurement(self):
        with self.assertRaises(ValueError):coremark_board.review_output(report(100000000))
    def test_rejects_wrong_score(self):
        with self.assertRaises(ValueError):coremark_board.review_output(report().replace('4.000000','4.100000'))
    def test_rejects_wrong_pll(self):
        cfg=json.loads((P/'config/cpu_board.json').read_text());cfg['pll']['feedback_divider']+=1
        with self.assertRaises(ValueError):gen_board.validate(cfg)

if __name__=='__main__':unittest.main()
