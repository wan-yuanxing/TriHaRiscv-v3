"""Synthesis diagnostics must distinguish complete analysis from timing closure."""
from pathlib import Path
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts/video'))
try:
    import pds_timing
except ModuleNotFoundError:
    pds_timing = None


def report():
    text = '''Timing analysis mode : single corner
 Clock Summary:
 Clock Period Waveform Type Loads Loads Sources
 core_clk 8.0000 {0.0000 4.0000} Declared 120 0 {clk_i}
 pixel_clk 25.0000 {0.0000 12.5000} Declared 10 0 {pixel_clk}
====================================================================================================
Design Summary : Some Constraints Violated.
'''
    for corner in ('Slow', 'Fast'):
        for kind in ('Setup', 'Hold', 'Recovery', 'Removal', 'Minimum Pulse Width'):
            text += f'{kind} Summary({corner} Corner):\n---\n'
            if corner == 'Slow':
                if kind == 'Minimum Pulse Width':
                    text += ' core_clk 3.000 0.000 0 120\n pixel_clk 11.000 0.000 0 10\n'
                else:
                    values = '-2.000 -4.000 2' if kind == 'Hold' else '0.311 0.000 0'
                    text += f' core_clk core_clk {values} 120\n pixel_clk pixel_clk 1.000 0.000 0 10\n'
            text += '=' * 100 + '\n'
    return text + '''Startpoint  : u_raw/mul/CLK (GTP_APM_E2)
Endpoint    : u_link/state/CE (GTP_DFF_CE)
Path Group  : core_clk
Path Type   : max (slow corner)
Path Class  : sequential timing path
 Clock core_clk (rising edge) 0.000 0.000
 Data arrival time 10.713 Logic Levels: 7
 Clock core_clk (rising edge) 8.000 8.000
 Data required time 11.024
 Slack (MET) 0.311
'''


class SynthesisTimingTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(pds_timing, 'checked synthesis timing module is missing')

    def parse(self, text=None):
        return pds_timing.parse_synthesis_timing(
            report() if text is None else text, 'component',
            {'core_clk': 8.0, 'pixel_clk': 25.0})

    def test_default_command_preserved(self):
        self.assertEqual(pds_timing.synthesis_command('video_timing', 'synth', None),
                         'synthesize -ads')

    def test_component_and_pads_use_all_paths(self):
        for target in pds_timing.TARGETS:
            for mode in ('pads', 'component'):
                command = pds_timing.synthesis_command(target, 'synth', mode)
                self.assertIn('-max_path 20 -nworst 1', command)
                self.assertEqual('-disable_io_insertion' in command, mode == 'component')
                self.assertNotIn('-from', command)
                self.assertNotIn('-to ', command)

    def test_invalid_scope_rejected(self):
        for target, stage, mode in [('video_mode_board', 'synth', 'component'),
                                     ('video_control_decode', 'route', 'component'),
                                     ('video_record_pipeline', 'bitstream', 'pads'),
                                     ('video_record_pipeline', 'synth', 'injected;')]:
            with self.subTest(target=target, stage=stage, mode=mode), self.assertRaises(ValueError):
                pds_timing.synthesis_command(target, stage, mode)

    def test_setup_pass_does_not_hide_hold_failure(self):
        result = self.parse()
        self.assertTrue(result['setup_estimate_met'])
        self.assertFalse(result['all_synthesis_checks_met'])
        self.assertFalse(result['timing_closed'])
        self.assertEqual(result['corners_with_data'], ['slow'])
        self.assertEqual(result['summaries']['hold']['slow'][0]['wns_ns'], -2.0)
        self.assertEqual(result['path_scope'], 'all_constrained_paths')
        self.assertEqual(result['paths'][0]['endpoint'], 'u_link/state/CE (GTP_DFF_CE)')

    def test_missing_or_empty_summary_rejected(self):
        for kind in ('Setup', 'Hold', 'Recovery', 'Removal', 'Minimum Pulse Width'):
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                self.parse(report().replace(kind + ' Summary(Slow Corner):', 'missing:'))
        with self.assertRaises(ValueError):
            self.parse(report().replace(' core_clk core_clk 0.311 0.000 0 120', ''))

    def test_changed_or_missing_clock_rejected(self):
        for before, after in [('core_clk 8.0000', 'core_clk 10.0000'),
                              ('pixel_clk 25.0000', 'other_clk 25.0000')]:
            with self.subTest(before=before), self.assertRaises(ValueError):
                self.parse(report().replace(before, after))

    def test_unknown_summary_clock_rejected(self):
        with self.assertRaises(ValueError):
            self.parse(report().replace('core_clk core_clk', 'unknown core_clk'))

    def test_contradictory_design_summary_rejected(self):
        with self.assertRaises(ValueError):
            self.parse(report().replace('Some Constraints Violated', 'All Constraints Met'))

    def test_missing_path_or_slack_rejected(self):
        for text in [report().split('Startpoint')[0], report().replace('Slack (MET) 0.311', '')]:
            with self.assertRaises(ValueError):
                self.parse(text)

    def test_invalid_summary_counts_rejected(self):
        with self.assertRaises(ValueError):
            self.parse(report().replace('-2.000 -4.000 2 120', '-2.000 -4.000 121 120'))

    def test_malformed_cross_clock_row_cannot_disappear(self):
        for row in (' core_clk pixel_clk -1.0 -1.0 1 NaN',
                    ' core_clk pixel_clk NaN -1.0 1 10'):
            with self.subTest(row=row), self.assertRaises(ValueError):
                self.parse(report().replace('Setup Summary(Slow Corner):\n---\n',
                                            'Setup Summary(Slow Corner):\n---\n' + row + '\n'))

    def test_all_met_remains_a_synthesis_estimate(self):
        result = self.parse(report().replace('-2.000 -4.000 2', '1.000 0.000 0').replace(
            'Some Constraints Violated', 'All Constraints Met'))
        self.assertTrue(result['all_synthesis_checks_met'])
        self.assertFalse(result['timing_closed'])
        self.assertFalse(result['physical_route_verified'])

    def test_path_cannot_be_worse_than_its_summary(self):
        with self.assertRaises(ValueError):
            self.parse(report().replace('Slack (MET) 0.311', 'Slack (VIOLATED) -9.000'))

    def test_negative_total_must_include_worst_endpoint(self):
        with self.assertRaises(ValueError):
            self.parse(report().replace('-2.000 -4.000 2', '-2.000 -0.001 2'))

    def test_unknown_path_class_rejected(self):
        with self.assertRaises(ValueError):
            self.parse(report().replace('sequential timing path', 'unknown path'))

    def test_datapath_exception_uses_explicit_group_lower_bound(self):
        text = report().replace(' Clock core_clk (rising edge) 0.000 0.000\n', '').replace(
            ' Clock core_clk (rising edge) 8.000 8.000\n', '').replace(
            'Path Class  : sequential timing path',
            'Path Class  : sequential timing path\nTiming Exception : MaxDelay Path 6.000ns -datapath_only')
        self.assertEqual(self.parse(text)['paths'][0]['summary_match'], 'capture_group_lower_bound')
        with self.assertRaises(ValueError):
            self.parse(text.replace('Timing Exception : MaxDelay Path 6.000ns -datapath_only', ''))

    def test_path_arithmetic_must_match_slack(self):
        with self.assertRaises(ValueError):
            self.parse(report().replace('Data required time 11.024', 'Data required time 20.000'))

    def test_strict_headers_fields_and_finite_numbers(self):
        variants = [
            report().replace(' Clock Summary:\n', ' Clock Summary:\n rogue_clk 8.000 {0 4} Generated 1 0 {rogue}\n'),
            report().replace('Setup Summary(Fast Corner):\n---\n',
                             'Setup Summary(Fast Corner):\n---\n rogue_clk rogue_clk NaN NaN NaN NaN\n'),
            report().replace('Setup Summary(Slow Corner):',
                             'Setup Summary(Slow Corner):\nSetup Summary(Slow Corner):'),
            report().replace(' Slack (MET) 0.311', ' Slack (MET) 0.311\n Slack (VIOLATED) -9.000'),
            report().replace('Path Group  : core_clk', 'Path Group  : core_clk\nPath Group : pixel_clk'),
            report().replace('0.311 0.000 0 120', '9' * 400 + '.0 0.000 0 120'),
        ]
        for index, text in enumerate(variants):
            with self.subTest(index=index), self.assertRaises(ValueError):
                self.parse(text)

    def test_final_pulse_width_column_is_not_another_path_slack(self):
        text = report() + '''{core_clk} Minimum Pulse Width :
 Slack       Actual Width    Require Width   Type              Location                Pin
 3.800       4.000           0.200           High Pulse Width                          araddr[0]/CLK
'''
        self.assertEqual(len(self.parse(text)['paths']), 1)

    def test_cli_rejects_diagnostic_board_and_route_before_building(self):
        root = Path(__file__).resolve().parents[2]
        for target, stage in [('video_mode_board', 'synth'), ('video_record_pipeline', 'route')]:
            process = subprocess.run([sys.executable, str(root/'scripts/video/build_pds.py'),
                                      '--target', target, '--stage', stage,
                                      '--synth-timing', 'component'], cwd=root,
                                     capture_output=True, text=True, timeout=30)
            self.assertEqual(process.returncode, 2)
            self.assertIn('approved component and synth stage', process.stderr)
            self.assertNotIn('RUN ', process.stdout)


if __name__ == '__main__':
    unittest.main()
