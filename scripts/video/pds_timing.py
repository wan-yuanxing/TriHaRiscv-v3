"""Checked PDS synthesis diagnostics; these never certify routed timing."""
import math
import re

TARGETS = ('video_control_decode', 'video_display_record', 'video_record_pipeline')
NUMBER = r'[-+]?\d+(?:\.\d+)?'
KINDS = {'setup': 'Setup', 'hold': 'Hold', 'recovery': 'Recovery',
         'removal': 'Removal', 'pulse_width': 'Minimum Pulse Width'}
HEADERS = {
    'Clock Non-clock', 'Clock Period Waveform Type Loads Loads Sources',
    'TNS Failing TNS Total', 'THS Failing THS Total', 'WPWS Failing WPWS Total',
    'Launch Clock Capture Clock WNS(ns) TNS(ns) Endpoints Endpoints',
    'Launch Clock Capture Clock WHS(ns) THS(ns) Endpoints Endpoints',
    'Clock WPWS(ns) TPWS(ns) Endpoints Endpoints',
}


def finite(value):
    if not re.fullmatch(NUMBER, value) or not math.isfinite(float(value)):
        raise ValueError('Invalid or nonfinite timing number: ' + value)
    return float(value)


def data_lines(body):
    for line in body.splitlines():
        compact = ' '.join(line.split())
        if compact and compact not in HEADERS and not re.fullmatch(r'[-=*]+', compact):
            yield line


def synthesis_command(target, stage, mode):
    if mode is None:
        return 'synthesize -ads'
    if target not in TARGETS or stage != 'synth' or mode not in ('pads', 'component'):
        raise ValueError('Synthesis timing diagnostics require an approved component and synth stage')
    command = 'synthesize -ads -max_path 20 -nworst 1'
    return command + (' -disable_io_insertion' if mode == 'component' else '')


def section(text, heading):
    if len(re.findall(r'^\s*' + re.escape(heading) + r'\s*$', text, re.M)) != 1:
        raise ValueError('Missing or duplicate synthesis heading: ' + heading)
    matches = list(re.finditer(re.escape(heading) + r'\s*\n(.*?)^=+\s*$', text, re.M | re.S))
    if len(matches) != 1:
        raise ValueError('Missing or duplicate synthesis section: ' + heading)
    return matches[0][1]


def parse_synthesis_timing(text, mode, expected_clocks):
    if mode not in ('pads', 'component') or not expected_clocks:
        raise ValueError('Invalid synthesis timing scope')
    if 'Timing analysis mode : single corner' not in text:
        raise ValueError('Expected the qualified single-corner synthesis report')
    clock_text = section(text, 'Clock Summary:')
    clocks = {}
    pattern = (r'^\s*(\S+)\s+(' + NUMBER + r')\s+\{[^}\n]+\}\s+Declared\s+'
               r'(\d+)\s+(\d+)\s+\{([^}\n]+)\}\s*$')
    for line in data_lines(clock_text):
        match = re.fullmatch(pattern, line)
        if not match:
            raise ValueError('Unrecognized clock row: ' + line)
        name, period, loads, nonclock, source = match.groups()
        if name in clocks:
            raise ValueError('Duplicate synthesis clock: ' + name)
        clocks[name] = {'period_ns': finite(period), 'loads': int(loads),
                        'nonclock_loads': int(nonclock), 'source': source}
    if set(clocks) != set(expected_clocks) or any(
            clocks[name]['period_ns'] != period or clocks[name]['loads'] <= 0
            for name, period in expected_clocks.items()):
        raise ValueError('Synthesis clocks differ from the required component clocks')
    summaries = {}
    for key, label in KINDS.items():
        summaries[key] = {}
        for corner in ('slow', 'fast'):
            body = section(text, label + ' Summary(' + corner.title() + ' Corner):')
            rows = []
            for line in data_lines(body):
                fields = line.split()
                count = 5 if key == 'pulse_width' else 6
                if len(fields) != count or not all(re.fullmatch(r'\d+', value) for value in fields[-2:]):
                    raise ValueError('Malformed synthesis timing row: ' + line)
                names = fields[:-4]
                if any(name not in clocks for name in names) or any(
                        not re.fullmatch(NUMBER, value) for value in fields[-4:-2]):
                    raise ValueError('Unknown clock or invalid timing number: ' + line)
                wns, total_ns = map(finite, fields[-4:-2])
                failing, endpoints = map(int, fields[-2:])
                if endpoints <= 0 or failing > endpoints or (wns < 0) != (failing > 0) or (
                        (total_ns < 0) != (failing > 0)) or total_ns > 0:
                    raise ValueError('Inconsistent timing endpoint counts/slacks: ' + line)
                # Tables are printed to 0.001 ns, so allow accumulated rounding.
                if failing and (total_ns > wns + 0.001 or total_ns < failing * (wns - 0.001)):
                    raise ValueError('Total negative slack cannot contain the worst endpoint: ' + line)
                row = {'launch_clock': names[0], 'capture_clock': names[-1],
                       'wns_ns': wns, 'total_negative_slack_ns': total_ns,
                       'failing_endpoints': failing, 'endpoints': endpoints}
                if any((old['launch_clock'], old['capture_clock']) ==
                       (row['launch_clock'], row['capture_clock']) for old in rows):
                    raise ValueError('Duplicate timing clock pair')
                rows.append(row)
            if corner == 'slow' and any(not any(
                    row['launch_clock'] == name == row['capture_clock'] for row in rows)
                    for name in clocks):
                raise ValueError('Missing slow-corner clock coverage: ' + label)
            if corner == 'fast' and rows:
                raise ValueError('Unexpected fast-corner data in single-corner synthesis')
            summaries[key][corner] = rows
    all_met = all(row['wns_ns'] >= 0 for kinds in summaries.values() for row in kinds['slow'])
    design = re.findall(r'Design Summary\s*:\s*(All Constraints Met|Some Constraints Violated)\.', text)
    if len(design) != 1 or (design[0] == 'All Constraints Met') != all_met:
        raise ValueError('Design summary contradicts the timing tables')
    paths = []
    for block in re.split(r'(?=^Startpoint\s*:)', text, flags=re.M)[1:]:
        fields = {}
        for key, label in [('startpoint', 'Startpoint'), ('endpoint', 'Endpoint'),
                           ('group', 'Path Group'), ('type', 'Path Type'), ('class', 'Path Class')]:
            matches = re.findall(r'^' + label + r'\s*:\s*([^\n]+)', block, re.M)
            if len(matches) != 1:
                raise ValueError('Missing or duplicate synthesis path field: ' + label)
            fields[key] = matches[0].strip()
        slack_lines = [line for line in re.findall(r'^[ \t]*Slack\b[^\n]*', block, re.M)
                       if ' '.join(line.split()) != 'Slack Actual Width Require Width Type Location Pin']
        slack = re.fullmatch(r'\s*Slack \((MET|VIOLATED)\)\s+(' + NUMBER + r')\s*',
                             slack_lines[0]) if len(slack_lines) == 1 else None
        if not slack or (finite(slack[2]) < 0) != (slack[1] == 'VIOLATED'):
            raise ValueError('Missing or inconsistent synthesis path slack')
        if fields['group'] not in clocks or fields['type'] not in ('max (slow corner)', 'min (slow corner)'):
            raise ValueError('Unexpected synthesis path clock/corner')
        fields['slack_ns'] = finite(slack[2])
        if fields['class'] not in ('sequential timing path', 'async timing path'):
            raise ValueError('Unknown synthesis path class')
        maximum = fields['type'].startswith('max ')
        kind = ('recovery' if maximum else 'removal') if fields['class'] == 'async timing path' else (
            'setup' if maximum else 'hold')
        applicable = [row for row in summaries[kind]['slow'] if row['capture_clock'] == fields['group']]
        edge_clocks = re.findall(r'^\s*Clock (\S+) \((?:rising|falling) edge\)', block, re.M)
        if len(edge_clocks) == 2:
            applicable = [row for row in applicable if
                          (row['launch_clock'], row['capture_clock']) == tuple(edge_clocks)]
            fields['summary_match'] = 'clock_pair'
        elif not edge_clocks and re.search(
                r'^Timing Exception\s*:\s*MaxDelay Path\s+' + NUMBER + r'ns -datapath_only\s*$', block, re.M):
            # This report omits launch/capture clocks for datapath-only paths.
            # Only a conservative lower bound across this capture group is known.
            fields['summary_match'] = 'capture_group_lower_bound'
        else:
            raise ValueError('Missing or unsupported synthesis path clocks/exception')
        if not applicable or fields['slack_ns'] < min(row['wns_ns'] for row in applicable) - 0.001:
            raise ValueError('Synthesis path is worse than its applicable summary')
        values = {}
        for label in ('arrival', 'required'):
            numbers = re.findall(r'^\s*Data ' + label + r' time\s+(' + NUMBER + r')\b', block, re.M)
            if not numbers or len(numbers) > 2:
                raise ValueError('Missing or duplicate path ' + label + ' times')
            values[label] = finite(numbers[0])
            if any(abs(finite(number) - values[label]) > 0.002 for number in numbers):
                raise ValueError('Inconsistent repeated path time')
        computed = values['required'] - values['arrival']
        if abs((computed if maximum else -computed) - fields['slack_ns']) > 0.0021:
            raise ValueError('Path arrival/required arithmetic contradicts slack')
        fields['analysis'] = kind
        paths.append(fields)
    if not paths:
        raise ValueError('No synthesis timing paths reported')
    return {'stage': 'synthesis_estimate', 'io_model': mode,
            'path_scope': 'all_constrained_paths', 'corners_with_data': ['slow'],
            'clocks': clocks, 'summaries': summaries, 'paths': paths,
            'setup_estimate_met': all(row['wns_ns'] >= 0 for row in summaries['setup']['slow']),
            'all_synthesis_checks_met': all_met, 'timing_closed': False,
            'physical_route_verified': False, 'external_io_timing_verified': False}
