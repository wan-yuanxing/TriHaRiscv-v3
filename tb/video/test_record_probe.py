"""Routable boundary must cover the actual interface and preserve CDC checks."""
from pathlib import Path
import json
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/video'))
try:
    import gen_record_probe as probe
except ModuleNotFoundError:
    probe = None


class RecordProbeTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(probe, 'record probe generator is missing')
        self.source = (ROOT/'rtl/video/video_record_pipeline.sv').read_text(encoding='utf-8')
        self.fdc = (ROOT/'fpga/pg2l100h/constraints/video_record_pipeline.fdc').read_text(encoding='utf-8')

    def test_every_port_has_one_boundary_or_direct_connection(self):
        boundary = probe.boundary_map(self.source, self.fdc)
        ports = re.findall(r'\b(?:input|output) wire\s*(?:\[\d+:0\]\s*)?(\w+)',
                           self.source.split(');',1)[0])
        actual = ['clk_i','rst_ni','pixel_clk','pixel_reset_n']
        for domain, sizes in [('core',(708,1148)),('pixel',(26,341))]:
            for kind, size in zip(('inputs','outputs'), sizes):
                entries = boundary[domain][kind]
                self.assertEqual(sum(p['width'] for p in entries), size)
                self.assertEqual([p['offset'] for p in entries],
                                 [sum(q['width'] for q in entries[:i]) for i in range(len(entries))])
                actual += [p['name'] for p in entries]
        self.assertEqual(len(actual), len(set(actual)))
        self.assertEqual(set(actual),set(ports))

    def test_wrong_clocks_and_unknown_commands_rejected(self):
        for text in [self.fdc.replace('-period 8.000','-period 10.000'),
                     self.fdc+'\nset_clock_groups -asynchronous -group core_clk -group pixel_clk\n']:
            with self.assertRaises(ValueError): probe.boundary_map(self.source,text)

    def test_missing_and_inconsistent_domain_rejected(self):
        for text in [self.fdc.replace('src_valid ', ''),
                     self.fdc.replace('pixel_reset_n pixel_x*', 'pixel_reset_n src_valid pixel_x*')]:
            with self.assertRaises(ValueError): probe.boundary_map(self.source,text)
        with self.assertRaises(ValueError):
            probe.boundary_map(self.source,self.fdc.replace('src_valid ', '', 1))

    def test_same_domain_wildcards_form_a_set(self):
        # generation* already covers generation_id*: SDC collections deduplicate.
        self.assertEqual(probe.boundary_map(self.source,self.fdc),
                         probe.boundary_map(self.source,self.fdc.replace(
                             'asset_retire_generation_id* ', '')))

    def test_duplicate_cdc_cannot_replace_another_check(self):
        lines=self.fdc.splitlines()
        indices=[i for i,line in enumerate(lines) if line.startswith('set_max_delay')]
        lines[indices[1]]=lines[indices[0]]
        with self.assertRaises(ValueError): probe.boundary_map(self.source,'\n'.join(lines))

    def test_equivalent_cdc_number_formats_cannot_hide_duplicate(self):
        lines=self.fdc.splitlines()
        indices=[i for i,line in enumerate(lines) if line.startswith('set_max_delay')]
        lines[indices[1]]=lines[indices[0]].replace('6.0 ', '6.000 ')
        self.assertNotEqual(lines[indices[0]],lines[indices[1]])
        with self.assertRaises(ValueError): probe.boundary_map(self.source,'\n'.join(lines))

    def test_equivalent_cdc_collection_forms_cannot_hide_duplicate(self):
        original=self.fdc.splitlines()
        indices=[i for i,line in enumerate(original) if line.startswith('set_max_delay')]
        first=original[indices[0]]
        for form in ('spaces','order','repeated_token'):
            def collection(match):
                names=match[1].split()
                if form=='order': names.reverse()
                if form=='repeated_token': names.append(names[0])
                return 'get_cells {'+('  ' if form=='spaces' else ' ').join(names)+'}'
            lines=list(original)
            lines[indices[1]]=re.sub(r'get_cells \{([^}]+)\}',collection,first)
            self.assertNotEqual(first,lines[indices[1]])
            with self.subTest(form=form),self.assertRaises(ValueError):
                probe.boundary_map(self.source,'\n'.join(lines))

    def test_attributed_unconstrained_port_cannot_disappear(self):
        source=self.source.replace(' input wire  online,',
            ' (* keep = "true" *) input wire omitted_by_probe,\n input wire  online,')
        self.assertNotEqual(source,self.source)
        with self.assertRaises(ValueError): probe.boundary_map(source,self.fdc)

    def test_derived_fdc_preserves_every_internal_exception(self):
        generated = probe.render(ROOT)
        text = generated['fpga/pg2l100h/constraints/video_record_probe.fdc']
        original = [l for l in self.fdc.splitlines() if l.startswith(('set_false_path','set_max_delay'))]
        derived = [l for l in text.splitlines() if l.startswith(('set_false_path','set_max_delay'))]
        self.assertEqual(len(original),16)
        self.assertEqual([l.replace('u_pipeline.','') for l in derived],original)
        self.assertNotIn('set_clock_groups', text)
        self.assertEqual(text.count('set_clock_uncertainty'),4)
        self.assertEqual(text.count('set_input_delay'),4)
        self.assertEqual(text.count('set_output_delay'),4)

    def test_manifest_is_explicit_and_keeps_default_full_dut(self):
        files = probe.render(ROOT)
        manifest = json.loads(files['fpga/pg2l100h/project/video_record_probe.json'])
        base = json.loads((ROOT/'fpga/pg2l100h/project/video_record_pipeline.json').read_text(encoding='utf-8'))
        self.assertEqual(manifest['sources'][1:],base['sources'])
        self.assertEqual(manifest['sources'][0],'fpga/pg2l100h/rtl/video_record_probe.sv')
        self.assertEqual(manifest['top'],'video_record_probe')
        wrapper = files[manifest['sources'][0]]
        self.assertIn('video_record_pipeline u_pipeline', wrapper)
        self.assertNotIn('FRAME_HEIGHT',wrapper)
        header=wrapper.split(');',1)[0]
        self.assertEqual(len(re.findall(r'\b(?:input|output) wire',header)),12)

    def test_only_probe_can_route_and_no_component_can_make_a_bitstream(self):
        import build_pds
        self.assertTrue(hasattr(build_pds,'component_stage_allowed'), 'component route gate is missing')
        self.assertTrue(build_pds.component_stage_allowed('video_record_probe','synth'))
        self.assertTrue(build_pds.component_stage_allowed('video_record_probe','route'))
        self.assertFalse(build_pds.component_stage_allowed('video_record_probe','bitstream'))
        self.assertFalse(build_pds.component_stage_allowed('video_record_pipeline','route'))

    def test_scanned_wiring_and_real_dut_idle(self):
        script=ROOT/'scripts/video/run_record_probe.py'
        self.assertTrue(script.is_file(), 'record probe simulation runner is missing')
        result=subprocess.run([sys.executable,str(script)],cwd=ROOT,capture_output=True,text=True,timeout=120)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('VIDEO_RECORD_PROBE_SIM_PASS',result.stdout)


if __name__ == '__main__': unittest.main()
