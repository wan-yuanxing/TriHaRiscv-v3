"""Post-map pin and primitive-site merge must preserve immutable source inputs."""
import tempfile
import unittest
from pathlib import Path
import build_pds

class PhysicalConstraintsTest(unittest.TestCase):
    def test_merge_preserves_generated_board_pins_and_source_files(self):
        with tempfile.TemporaryDirectory() as d:
            work=Path(d);(work/'device_map').mkdir();(work/'src').mkdir()
            generated=work/'device_map/top.pcf';generated.write_text('def_port {clk} LOC=D18\ndef_inst_site {cpd} DDRPHY_CPD_369_466\n',encoding='utf-8')
            user=work/'src/gate.pcf';user.write_text('# fixed gate\ndef_inst_site {gate[0]/ff} CLMA_357_354 FF3\n',encoding='utf-8')
            before=[p.read_bytes() for p in (generated,user)]
            merged=build_pds.prepare_physical_constraints(work,'top',['gate.pcf'])
            self.assertIn('def_port {clk} LOC=D18',merged.read_text(encoding='utf-8'))
            self.assertIn('def_inst_site {gate[0]/ff} CLMA_357_354 FF3',merged.read_text(encoding='utf-8'))
            self.assertEqual(before,[p.read_bytes() for p in (generated,user)])
            self.assertNotIn(merged,(generated,user))

    def test_missing_generated_pin_map_fails_closed(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(FileNotFoundError):
                build_pds.prepare_physical_constraints(Path(d),'top',[])

    def test_duplicate_primitive_site_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            work=Path(d);(work/'device_map').mkdir();(work/'src').mkdir()
            (work/'device_map/top.pcf').write_text('def_inst_site {gate} CLMA_357_354 FF3\n',encoding='utf-8')
            (work/'src/gate.pcf').write_text('def_inst_site {gate} CLMA_357_660 FF3\n',encoding='utf-8')
            with self.assertRaisesRegex(ValueError,'Duplicate'):
                build_pds.prepare_physical_constraints(work,'top',['gate.pcf'])

if __name__=='__main__':unittest.main()
