"""Independent review of CPU/DDR board digital and physical evidence."""
import argparse
import json
from pathlib import Path
import re

from run_cache import ROOT, sha, save
from review_cache_soc import verify_run, hierarchy


def matched_pins(text):
    result = {}
    matches = re.findall(r"(?m)^\s*I: The pattern '([^']+)' in command '[^\r\n]+' match (\d+) objects below:\r?\n((?:[ \t]*I: pin [^\r\n]+\r?\n)+)", text)
    for expression, count, block in matches:
        pins = re.findall(r'(?m)^\s*I: pin ([^\r\n]+)', block)
        if len(pins) != int(count) or len(set(pins)) != len(pins):
            raise ValueError('incomplete constraint pin match')
        if expression in result and result[expression] != pins:
            raise ValueError('inconsistent repeated constraint pin match')
        result[expression] = pins
    return result


def cdc_constraints(text, fdc):
    matches = matched_pins(text)
    patterns = re.findall(r'get_pins -regexp -hsc / \{([^}]+)\}', fdc)
    if len(patterns) != 60 or len(set(patterns)) != 20:
        raise ValueError('wrong number of Gray constraint selections')
    pointers = {}
    for pattern in sorted(set(patterns)):
        pins = matches.get(pattern, [])
        if len(pins) != 3 or any(re.fullmatch(pattern, pin) is None for pin in pins):
            raise ValueError('Gray bus selection did not match three exact data pins: '+pattern)
        pointers[pattern] = pins
    expected = {'u_system.u_cdc.ready_meta_q/D*':1, 'u_system.u_cdc.fault_meta_q/D*':1,
        'u_supervisor.status_meta_q*/D*':9, 'u_supervisor.beat_meta_q/D*':1,
        'software_meta_q*/D*':2, 'board_fault_meta_q/D*':1}
    first = {}
    for pattern, count in expected.items():
        pins = matches.get(pattern, [])
        if len(pins) != count or any(not re.search(r'/D(?:\[\d+\])?$', pin) for pin in pins):
            raise ValueError('wrong first-stage asynchronous data selection: '+pattern)
        first[pattern] = pins
    return dict(gray_pointer_selections=pointers, first_stage_data_selections=first)


def parse_timing(text):
    if ('Timing analysis mode : multi corner' not in text or
            not re.search(r'(?m)^\s*cpu_clk\s+10\.0000\s+\{0\.0000 5\.0000\}', text)):
        raise ValueError('missing actual multi-corner 100MHz report')
    rows = []
    for corner in ['Slow', 'Fast']:
        for kind in ['Setup', 'Hold', 'Recovery', 'Removal', 'Minimum Pulse Width']:
            sections = re.findall(r'(?ms)^'+re.escape(kind+' Summary('+corner+' Corner):')+r'\r?\n(.*?)(?=^={10,}\s*$)', text)
            if len(sections) != 1:
                raise ValueError('missing/duplicate timing summary: '+kind+'/'+corner)
            pattern = (r'(?m)^\s*(\S+)\s+' if kind == 'Minimum Pulse Width' else r'(?m)^\s*(\S+)\s+(\S+)\s+')
            matches = re.findall(pattern+r'(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$', sections[0])
            if not matches:
                raise ValueError('empty/malformed timing summary: '+kind+'/'+corner)
            pairs = set()
            cpu = False
            for match in matches:
                clocks = match[:-4]
                if clocks in pairs:
                    raise ValueError('duplicated clock pair')
                pairs.add(clocks)
                slack, tns, failing, count = match[-4:]
                if int(count) <= 0:
                    raise ValueError('no endpoints timed')
                cpu |= clocks == (('cpu_clk',) if kind == 'Minimum Pulse Width' else ('cpu_clk','cpu_clk'))
                rows.append(dict(corner=corner, check=kind, clocks=clocks, slack_ns=float(slack),
                    total_negative_slack_ns=float(tns), failing_endpoints=int(failing), endpoints=int(count)))
            if not cpu:
                raise ValueError('missing CPU timing row')
    performance = re.findall(r'(?m)^\s*cpu_clk\s+100\.0000 MHz\s+\d+\.\d+ MHz\s+10\.0000\s+\d+\.\d+\s+(-?\d+\.\d+)\s*$', text)
    if len(performance) != 1:
        raise ValueError('missing/duplicate CPU performance row')
    worst = min(r['slack_ns'] for r in rows if r['check']=='Setup' and r['clocks']==('cpu_clk','cpu_clk'))
    consistent = abs(float(performance[0])-worst) <= 0.001
    met = (all(r['slack_ns'] >= 0 and r['total_negative_slack_ns'] == 0 and r['failing_endpoints'] == 0 for r in rows)
        and 'Design Summary : All Constraints Met.' in text and consistent)
    return dict(summary_met=met, physical_admitted=False, rows=rows, worst_cpu_setup_ns=worst,
        performance_slack_ns=float(performance[0]), performance_consistent=consistent,
        scope='All final summary rows only; physical admission also requires bindings, actual stages and matched CDC checks')


def digital(directories):
    bound = {}
    modes = {}
    for directory in directories:
        directory = Path(directory).resolve()
        initial = json.loads((directory/'result.json').read_text(encoding='utf-8'))
        negative = initial['fault'] == 'data'
        row = verify_run(directory, negative=negative)
        if not row['pinned_unchanged']:
            raise ValueError('pinned dependencies changed')
        for entry in row['binding']['files'].values():
            if sha(entry['path']) != entry['sha256']:
                raise ValueError('pinned file differs')
        text = (directory/'simulation.log').read_text(encoding='utf-8')
        expected_codes = {'no-init':'e0', 'init-loss':'e1', 'clock-stop':'e4', 'cpu-pll-loss':'e5'}
        if negative:
            if row['test'] != 'boot' or 'CPU_TRAP cause=00000007 value=80010000' not in text or 'CPU_DDR_BOARD_FAIL first software run' not in text:
                raise ValueError('negative did not exercise real store visibility failure')
            key = 'corrupt-data'
        elif row['test'] == 'boot':
            if ('CPU_DDR_BOARD_PASS boots=2 tested_private=8192 tested_shared=8192' not in text or
                    text.count('# CPU_DDR_PASS private=8192 shared=8192 fence_i=1') != 2):
                raise ValueError('two complete software boots not observed')
            key = 'boot'
        else:
            code = expected_codes[row['test']]
            if not re.search(r'CPU_DDR_BOARD_MONITOR_PASS .*code='+code, text):
                raise ValueError('wrong supervisor failure code')
            key = row['test']
        if key in modes:
            raise ValueError('duplicate digital coverage')
        modes[key] = str(directory)
        bound[str(directory/'result.json')] = sha(directory/'result.json')
    if set(modes) != {'boot','no-init','init-loss','clock-stop','cpu-pll-loss','corrupt-data'}:
        raise ValueError('incomplete board digital coverage')
    return dict(status='PASS', physical_admitted=False, bound_results=bound, modes=modes,
        scope='Real CPU/O2 software with digital DDR/PLL substitutes; no analog training or physical timing claim')


def physical(directory):
    directory = Path(directory).resolve()
    row = json.loads((directory/'result.json').read_text(encoding='utf-8'))
    if (row['flow_status'] != 'PASS' or row['status'] != 'REVIEW_REQUIRED' or
            row['runner_return_code'] != 2 or not all(row[k] for k in
            ['source_unchanged','external_unchanged','evidence_unchanged','hardware_unchanged'])):
        raise ValueError('need completed unchanged native implementation')
    for name, digest in row['input_hashes'].items():
        if sha(ROOT/name) != digest or sha(directory/'src'/name) != digest:
            raise ValueError('physical source binding drift: '+name)
    for key in ['external_hashes','evidence_hashes']:
        for name, digest in row[key].items():
            if sha(name) != digest:
                raise ValueError('physical tool/evidence drift: '+name)
    for key in ['output_hashes','frozen_hardware_hashes']:
        for name, digest in row[key].items():
            if sha(directory/name) != digest:
                raise ValueError('physical output/input drift: '+name)
    if sha(directory/'prepared.json') != row['prepared_sha256']:
        raise ValueError('prepared hardware binding drift')
    if any(c['return_code'] != 0 or c['timed_out'] for c in row['commands']):
        raise ValueError('native command failure')
    log = (directory/'pds.log').read_text(encoding='utf-8')
    for stage in ['compile','synthesize','dev_map','pnr','report_timing']:
        if not re.search(r'(?m)^Executing : '+stage+r'(?: [^\r\n]*)? successfully\.\s*$', log):
            raise ValueError('missing actual stage: '+stage)
    fdc = (directory/'src/fpga/pg2l100h/constraints/cpu_ddr_board.fdc').read_text(encoding='utf-8')
    ccr = (directory/'constraint_check/constraint_check.ccr').read_text(encoding='utf-8')
    if 'Found 0 error(s)' not in ccr or re.search(r'(?m)^\s*E:', ccr):
        raise ValueError('physical constraint errors')
    constraints = cdc_constraints(ccr, fdc)
    pins = dict(re.findall(r'define_attribute \{p:([^}]+)\} \{PAP_IO_LOC\} \{([^}]+)\}', fdc))
    critical = []
    for line in ccr.splitlines():
        if re.match(r'\s*C:', line):
            notice = re.fullmatch(r'\s*C: ConstraintEditor-2002: \[.*\] \| Port (\S+) has been placed at location (\S+), whose type is share pin\.', line)
            if not notice or pins.get(notice[1]) != notice[2]:
                raise ValueError('unreviewed critical constraint notice: '+line)
            critical.append(line.strip())
    text = (directory/'report_timing/triha_cpu_ddr_board_top.rtr').read_text(encoding='utf-8')
    timing = parse_timing(text)
    blocks = re.split(r'(?m)^Startpoint  : ', text)[1:]
    exceptions = []
    for block in blocks:
        if 'Timing Exception  :  MaxDelay Path 8.000ns -datapath_only' in block[:600]:
            arrival = re.search(r'Data arrival time\s+(-?[\d.]+)', block)
            slack = re.search(r'Slack \((MET|VIOLATED)\)\s+(-?[\d.]+)', block)
            exceptions.append(dict(startpoint=block.splitlines()[0], endpoint=block.splitlines()[1].split(': ',1)[1],
                corner=re.search(r'Path Type   : max \((slow|fast) corner\)',block)[1],
                arrival_ns=float(arrival[1]), slack_ns=float(slack[2]), met=slack[1]=='MET'))
    # The tool emitted datapath-only MaxDelay checks, but no distinct skew
    # check section in this first report. Never infer missing checks passed.
    timing['gray_reported_maxdelay_paths'] = exceptions
    covered = set()
    for path in exceptions:
        source = re.search(r'/u_(aw|w|b|ar|r)_fifo/(wr_gray|rd_gray)\[([012])\]/',path['startpoint'])
        if source is None:
            raise ValueError('unexpected MaxDelay source')
        channel, pointer, bit = source.groups()
        target = 'wr_gray_rd_sync1' if pointer == 'wr_gray' else 'rd_gray_wr_sync1'
        if f'/u_{channel}_fifo/{target}[{bit}]/' not in path['endpoint']:
            raise ValueError('MaxDelay path reaches wrong pointer synchronizer')
        covered.add((path['corner'], channel, pointer, bit))
    expected_paths = {(corner, channel, pointer, str(bit)) for corner in ['slow','fast']
        for channel in ['aw','w','b','ar','r'] for pointer in ['wr_gray','rd_gray'] for bit in range(3)}
    timing['gray_maxdelay_coverage_complete'] = covered == expected_paths
    timing['gray_maxdelay_met'] = covered == expected_paths and all(p['met'] and p['slack_ns'] >= 0 for p in exceptions)
    timing['gray_skew_status'] = 'UNKNOWN: no explicit skew check section observed'
    snr = (directory/'synthesize/triha_cpu_ddr_board_top.snr').read_text(encoding='utf-8')
    if not re.search(r'(?m)^Total Latches: 0\s*$', snr):
        raise ValueError('unexpected inferred latch')
    resources = {n:hierarchy(snr,n) for n in ['triha_cpu_ddr_board_top','I_ips_ddr_top','u_supervisor','u_core','u_cache','u_cdc','u_bridge','u_memory']}
    compile_log = (directory/'compile/run.log').read_text(encoding='utf-8')
    elaborated = {}
    expected = {'u_system/u_soc':{'CACHE_ENABLE':1}, 'u_system/u_soc/u_core':{'DUAL_ISSUE':0},
        'u_system/u_soc/u_core/u_cpu':{'SUPPORT_DUAL_ISSUE':0, 'NUM_BTB_ENTRIES':512,
            'NUM_BHT_ENTRIES':512,'NUM_RAS_ENTRIES':4,'GSHARE_ENABLE':0,'EARLY_MUL_BYPASS':1},
        'u_system/u_soc/u_router/u_cache':{'ICACHE_ENABLE':1,'DCACHE_ENABLE':1}}
    for channel, width in [('aw',49),('w',145),('b',6),('ar',49),('r',135)]:
        expected['u_system/u_cdc/u_'+channel+'_fifo'] = {'DATA_WIDTH':width,'ADDR_WIDTH':2}
    for scope, values in expected.items():
        sections = re.findall(r'(?ms)^I: Module instance \{triha_cpu_ddr_board_top/'+re.escape(scope)+r'\} parameter value:\r?\n(.*?)(?=^I:|\Z)',compile_log)
        if len(sections) != 1:
            raise ValueError('missing actual elaboration scope: '+scope)
        for name, value in values.items():
            field = re.findall(r'(?m)^\s*'+name+r" = (?:1|32)'b([01]+)\s*$",sections[0])
            if len(field) != 1 or int(field[0],2) != value:
                raise ValueError('actual elaboration mismatch: '+scope+'/'+name)
        elaborated[scope] = values
    worst = []
    for block in blocks:
        if 'max (slow corner)' in block[:350] and 'sequential timing path' in block[:500] and re.search(r'(?m)^Path Group  : cpu_clk$', block):
            worst.append(dict(startpoint=block.splitlines()[0], endpoint=block.splitlines()[1].split(': ',1)[1],
                slack_ns=float(re.search(r'Slack \((?:MET|VIOLATED)\)\s+(-?[\d.]+)', block)[1])))
    return dict(status='PASS', timing_status='FAIL' if not timing['summary_met'] else 'REVIEW_REQUIRED',
        timing_closed=False, physical_admitted=False, board_validated=False,
        bound_result=str(directory/'result.json'), bound_result_sha256=sha(directory/'result.json'),
        timing_report=str(directory/'report_timing/triha_cpu_ddr_board_top.rtr'),
        timing_report_sha256=sha(directory/'report_timing/triha_cpu_ddr_board_top.rtr'),
        resources=resources, timing=timing, constraints=constraints, elaborated=elaborated,
        reviewed_reference_pin_notices=critical, worst_cpu_setup_paths=sorted(worst,key=lambda r:r['slack_ns'])[:3],
        scope='Independent terminal binding and actual post-route review; review PASS does not mean timing PASS; DDR external AC/training and shared fabric not admitted')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--digital', type=Path, action='append', default=[])
    parser.add_argument('--timing-report', type=Path)
    parser.add_argument('--physical', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.physical:
        result = physical(args.physical)
    elif args.timing_report:
        result = parse_timing(args.timing_report.read_text(encoding='utf-8'))
    else:
        result = digital(args.digital)
    save(args.output, result)
    print('CPU_DDR_BOARD_REVIEW_PASS', args.output)


if __name__ == '__main__':
    main()
