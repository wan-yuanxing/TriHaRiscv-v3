"""Full dual-corner routed reports are required for the scan component."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'scripts/video'))
try:
    import record_probe_timing as timing
except ModuleNotFoundError:
    timing=None


def report(failed=False):
    text='''| Design : video_record_probe
| Timing Models: Production
| Tcl Command : report_timing
Timing analysis mode : multi corner
Clock Summary:
 Clock Period Waveform Type Loads Loads Sources
 core_clk 8.0000 {0 4} Declared 120 0 {clk_i}
 pixel_clk 25.0000 {0 12.5} Declared 20 0 {pixel_clk}
========================
Clock Groups:
 Clock Group Group Type Clocks
========================
'''
    text+='Design Summary : '+('Some Constraints Violated.' if failed else 'All Constraints Met.')+'\n'
    for corner in ('Slow','Fast'):
        for kind in ('Setup','Hold','Recovery','Removal','Minimum Pulse Width'):
            text+=f'{kind} Summary({corner} Corner):\n---\n'
            for clock in ('core_clk','pixel_clk'):
                bad=failed and kind=='Hold' and corner=='Fast' and clock=='core_clk'
                numbers='-0.100 -0.100 1 20' if bad else '0.500 0.000 0 20'
                text+=' '+clock+(' ' if kind=='Minimum Pulse Width' else ' '+clock+' ')+numbers+'\n'
            text+='========================\n'
    return text+'''Startpoint : u_pipeline/state/CLK
Endpoint : u_pipeline/next/D
Path Group : core_clk
Path Type : max (slow corner)
Path Class : sequential timing path
 Clock core_clk (rising edge) 0 0
 Data arrival time 7.500
 Clock core_clk (rising edge) 8 8
 Data required time 8.000
 Slack (MET) 0.500
'''


class RecordProbeTimingTests(unittest.TestCase):
    def setUp(self): self.assertIsNotNone(timing,'routed record-probe parser is missing')

    def test_full_positive_report_is_only_component_closure(self):
        result=timing.parse_record_probe_timing(report())
        self.assertTrue(result['component_route_timing_met'])
        self.assertFalse(result['timing_closed'])
        self.assertEqual(result['corners_with_data'],['slow','fast'])

    def test_fast_hold_failure_is_preserved(self):
        self.assertFalse(timing.parse_record_probe_timing(report(True))['component_route_timing_met'])

    def test_missing_corner_or_clock_rejected(self):
        for text in [report().replace('Hold Summary(Fast Corner):','missing:'),
                     report().replace('core_clk 8.0000','core_clk 10.0000')]:
            with self.assertRaises(ValueError): timing.parse_record_probe_timing(text)

    def test_clock_pair_coverage_must_match_between_corners(self):
        for kind in ('Setup','Hold','Recovery','Removal'):
            text=report().replace(kind+' Summary(Slow Corner):\n---\n',
                kind+' Summary(Slow Corner):\n---\n core_clk pixel_clk 0.500 0.000 0 20\n')
            with self.assertRaises(ValueError): timing.parse_record_probe_timing(text)

    def test_filtered_or_asynchronous_report_rejected(self):
        for text in [report().replace('report_timing\n','report_timing -from {x}\n'),
                     report().replace(' Clock Group Group Type Clocks\n',' Clock Group Group Type Clocks\n core asynchronous core_clk\n')]:
            with self.assertRaises(ValueError): timing.parse_record_probe_timing(text)

    def test_command_and_clock_sources_are_exact(self):
        for text in [report().replace('report_timing\n','report_timing_bad\n'),
                     report().replace('{clk_i}','{wrong_clock_pin}')]:
            with self.assertRaises(ValueError): timing.parse_record_probe_timing(text)

    def test_placement_db_cannot_certify_completed_routing(self):
        with self.assertRaises(ValueError):
            timing.parse_record_probe_timing(report().replace('report_timing\n',
                'report_timing -input_db_file {component_plc.adf}\n'))

    def test_duplicate_malformed_or_nonfinite_rejected(self):
        for text in [report().replace('Setup Summary(Slow Corner):','Setup Summary(Slow Corner):\nSetup Summary(Slow Corner):'),
                     report().replace('0.500 0.000 0 20','NaN 0.000 0 20',1),
                     report().replace('0.500 0.000 0 20','9'*400+'.0 0.000 0 20',1)]:
            with self.assertRaises(ValueError): timing.parse_record_probe_timing(text)

    def test_path_may_not_contradict_summary(self):
        with self.assertRaises(ValueError):
            timing.parse_record_probe_timing(report().replace('Slack (MET) 0.500','Slack (VIOLATED) -9.000'))


if __name__=='__main__':unittest.main()
