import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path
import prepare_dual_physical as m

class PhysicalGateTests(unittest.TestCase):
    def test_rejects_unfinished_or_changed_simulation(self):
        for row in [dict(status='RUNNING'),dict(status='PASS',source_unchanged=False)]:
            with self.assertRaises(ValueError):m.check_simulation(row)

    def test_rejects_missing_actual_dual_evidence(self):
        row=dict(status='PASS',source_unchanged=True,external_unchanged=True,runner_return_code=0,test='coremark',fault='none')
        with self.assertRaises(ValueError):m.check_simulation(row)

    def test_frozen_package_rejects_tcl_and_input_drift(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); (root/'src').mkdir()
            (root/'src/cpu.v').write_text('module cpu; endmodule')
            (root/'build.tcl').write_text('compile')
            row=dict(cpu_mode=1,period_ns=10,input_hashes={'cpu.v':m.sha(root/'src/cpu.v')},files={'build.tcl':m.sha(root/'build.tcl')})
            (root/'prepared.json').write_text(json.dumps(row))
            m.verify_file_hashes(root,row)
            (root/'build.tcl').write_text('changed')
            with self.assertRaises(ValueError):m.verify_file_hashes(root,row)
            (root/'build.tcl').write_text('compile')
            (root/'src/cpu.v').write_text('changed')
            with self.assertRaises(ValueError):m.verify_file_hashes(root,row)

    def test_frozen_package_rejects_escape_and_wrong_clock(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for row in [dict(cpu_mode=0,period_ns=10,input_hashes={},files={}),
                        dict(cpu_mode=1,period_ns=20,input_hashes={},files={}),
                        dict(cpu_mode=1,period_ns=10,input_hashes={'../escape':'0'},files={})]:
                (root/'prepared.json').write_text(json.dumps(row))
                with self.assertRaises(ValueError):m.verify_file_hashes(root,row)

    def test_package_must_bind_simulation(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            row=dict(status='PREPARED_NOT_EXECUTED',pds_started=False,cpu_mode=1,period_ns=10,input_hashes={},files={})
            (root/'prepared.json').write_text(json.dumps(row))
            with self.assertRaises(ValueError):m.verify_package(root)

    def test_package_binds_firmware_and_actual_dual_log(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); work=root/'package'; sim=root/'sim'
            core=dict(family='Logos2',device='PG2L100H',speedgrade='-6',package='FBG676',sources=['cpu.v'],headers=[])
            recipe=dict(sources=[],headers=[],constraints='clock.fdc')
            for p in [work/'src',sim/'src/fpga/pg2l100h/project',root/'fpga/pg2l100h/project']:
                p.mkdir(parents=True)
            (root/'fpga/pg2l100h/project/cpu_minimal_soc.json').write_text(json.dumps(recipe))
            (sim/'src/fpga/pg2l100h/project/cpu_core.json').write_text(json.dumps(core))
            (work/'src/cpu.v').write_text('module cpu; endmodule')
            (root/'clock.fdc').write_text('original constraints')
            (work/'src/clock.fdc').write_bytes((root/'clock.fdc').read_bytes())
            for name in ['rom.hex','sram.hex','firmware.elf']:
                (sim/name).write_text(name);(work/name).write_text(name)
            (sim/'simulation.log').write_text('SOC_DUAL_CONFIG actual=1 pairs=2')
            (work/'build.tcl').write_text(m.tcl(work,core,['cpu.v'],'clock.fdc'))
            evidence=dict(status='PASS',source_unchanged=True,external_unchanged=True,runner_return_code=0,test='coremark',fault='none',
                input_hashes={'cpu.v':m.sha(work/'src/cpu.v')},output_hashes={n:m.sha(sim/n) for n in ['rom.hex','sram.hex','firmware.elf','simulation.log']})
            (sim/'result.json').write_text(json.dumps(evidence))
            row=dict(status='PREPARED_NOT_EXECUTED',pds_started=False,cpu_mode=1,period_ns=10,simulation=str(sim),
                simulation_result_sha256=m.sha(sim/'result.json'),input_hashes={n:m.sha(work/'src'/n) for n in ['cpu.v','clock.fdc']},
                files={n:m.sha(work/n) for n in ['rom.hex','sram.hex','firmware.elf','build.tcl']})
            (work/'prepared.json').write_text(json.dumps(row))
            with patch.object(m,'ROOT',root):
                m.verify_package(work)
                (work/'sram.hex').write_text('different program')
                row['files']['sram.hex']=m.sha(work/'sram.hex')
                (work/'prepared.json').write_text(json.dumps(row))
                with self.assertRaisesRegex(ValueError,'firmware differs'):m.verify_package(work)
                (work/'sram.hex').write_bytes((sim/'sram.hex').read_bytes())
                row['files']['sram.hex']=m.sha(work/'sram.hex')
                (sim/'simulation.log').write_text('SOC_DUAL_CONFIG actual=0 pairs=0')
                evidence['output_hashes']['simulation.log']=m.sha(sim/'simulation.log')
                (sim/'result.json').write_text(json.dumps(evidence))
                row['simulation_result_sha256']=m.sha(sim/'result.json')
                (work/'prepared.json').write_text(json.dumps(row))
                with self.assertRaisesRegex(ValueError,'actual dual'):m.verify_package(work)

    def test_tcl_keeps_multicorner_hold_and_no_programming(self):
        core=dict(family='Logos2',device='PG2L100H',speedgrade='-6',package='FBG676')
        text=m.tcl(Path('D:/test'),core,['rtl/a.v'],'clock.fdc')
        self.assertIn('-fix_hold_violation',text)
        self.assertIn('-optimize_multi_corner_timing',text)
        self.assertIn('report_timing',text)
        self.assertNotIn('program_device',text)
        self.assertNotIn('generate_bitstream',text)

if __name__=='__main__':unittest.main()
