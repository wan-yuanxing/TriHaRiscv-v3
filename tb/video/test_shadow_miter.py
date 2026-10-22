"""The equivalence monitor must cover reset and reject unrepresented ports."""
from pathlib import Path
import re,subprocess,sys,unittest
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/video'))
from common import fresh_run,tool
import test_shadow_decode as runner


class ShadowMiterTests(unittest.TestCase):
    def test_current_interface_is_fully_represented(self):
        source=(ROOT/runner.LEAF).read_text(encoding='utf-8')
        ports=runner.ports(source)
        self.assertEqual(len(ports),53)
        self.assertEqual(sum(d=='output' for d,_,_ in ports),23)
        self.assertIn(('output','[5119:0]','cmd_data_o'),ports)

    def test_inout_cannot_silently_disappear(self):
        source=(ROOT/runner.LEAF).read_text(encoding='utf-8')
        source=source.replace('    input wire clk_i,rst_ni,','    inout wire omitted_bus,\n    input wire clk_i,rst_ni,')
        with self.assertRaises(ValueError):runner.ports(source)

    def test_reset_only_output_difference_is_rejected(self):
        work=fresh_run('shadow_miter_unit')
        source=(ROOT/runner.LEAF).read_text(encoding='utf-8')
        reference=subprocess.check_output(['git','show',runner.REFERENCE+':'+runner.LEAF],cwd=ROOT).decode('utf-8')
        self.assertEqual(source.count('assign fault_code_o=error_code;'),1)
        candidate=source.replace('assign fault_code_o=error_code;',
            "assign fault_code_o=rst_ni ? error_code : 8'hff;")
        for name,text in [('reference',reference),('candidate',candidate)]:
            text=re.sub(r'\bmodule video_display_mmio\b','module video_display_mmio_'+name,text)
            (work/(name+'.sv')).write_text(text,encoding='utf-8',newline='\n')
        (work/'miter.sv').write_text(runner.miter(source),encoding='utf-8',newline='\n')
        (work/'tb.sv').write_text('''`timescale 1ns/1ps
module tb_reset_miter;
reg clk_i=0,rst_ni=1;
always #4 clk_i=~clk_i;
video_display_mmio dut(.clk_i(clk_i),.rst_ni(rst_ni));
initial begin #1;rst_ni=0;#24;rst_ni=1;#40;
$display("RESET_MITER_FIXTURE_PASS");$finish;end
endmodule
''',encoding='utf-8',newline='\n')
        binary=work/'sim.vvp'
        command=[tool('iverilog'),'-g2012','-I',ROOT/'rtl/video/include','-s','tb_reset_miter','-o',binary,
                 ROOT/'rtl/video/display_slot_owner.sv',ROOT/'rtl/video/display_record_guard.sv',
                 *[work/(n+'.sv') for n in ('reference','candidate','miter','tb')]]
        compiled=subprocess.run(command,capture_output=True,timeout=60)
        (work/'compile.log').write_bytes(compiled.stdout+compiled.stderr)
        self.assertEqual(compiled.returncode,0,(compiled.stdout+compiled.stderr).decode(errors='replace')[-1500:])
        result=subprocess.run([tool('vvp'),binary],capture_output=True,timeout=30)
        log=result.stdout+result.stderr;(work/'run.log').write_bytes(log)
        self.assertNotEqual(result.returncode,0,'Reset-only RTL difference escaped the cycle comparator')
        self.assertIn(b'SHADOW_MITER_MISMATCH fault_code_o',log)


if __name__=='__main__':unittest.main()
