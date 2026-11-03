"""Exercise fail-closed timing and physical checks using native routed evidence.

The input route may fail timing: these are audit controls, not board acceptance.
Run again with --clock-review to cover the all-bit early/late clock proof.
"""
import argparse
import json
from pathlib import Path
import re

from common import sha256
from face_timing import audit_paths, gray_bounds, parse_tables, path_blocks, require_routed_report
from check_face_gray_clocks import audit
from qualify_face_bitstream import check_sites
from face_gray_netlist import load_evidence


def replace_once(pattern, replacement, text):
    changed, count = re.subn(pattern, replacement, text, count=1, flags=re.M)
    if count != 1 or changed == text:
        raise RuntimeError('Negative control did not alter its input: '+pattern)
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--review', type=Path, required=True)
    parser.add_argument('--clock-review', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = dict(status='FAIL', scope='Audit controls only; no timing or board acceptance', controls={})
    inputs = [Path(__file__), args.review/'result.json', args.base/'physical.pcf',
              args.base/'src/fpga/pg2l100h/constraints/triha_face_cdc.fdc']
    inputs += [Path(__file__).with_name(n) for n in
               ('face_timing.py', 'check_face_gray_clocks.py', 'qualify_face_bitstream.py', 'face_gray_netlist.py')]

    def rejected(name, operation):
        try:
            operation()
        except ValueError as error:
            result['controls'][name] = str(error)
        else:
            raise RuntimeError('Invalid evidence was accepted: '+name)

    try:
        profile=json.loads((args.base/'result.json').read_text(encoding='utf-8'))['face_profile']
        review = json.loads(inputs[1].read_text(encoding='utf-8'))
        report, sites = (Path(review[n]['path']) for n in ('report', 'sites'))
        inputs += [report, sites]
        for name, path in [('report', report), ('sites', sites)]:
            if sha256(path) != review[name]['sha256']:
                raise ValueError('Native evidence changed: '+name)
        text, physical = (path.read_text(encoding='utf-8') for path in (report, sites))
        fdc = inputs[3].read_text(encoding='utf-8')
        requested = inputs[2].read_text(encoding='utf-8')
        dbs = [n for n in review['inputs'] if n.endswith('_pnr.adf')]
        if len(dbs) != 1:
            raise ValueError('Expected one routed database')
        require_routed_report(text, Path(dbs[0]).as_posix())
        tables = parse_tables(text)
        result['baseline_timing_met'] = tables['all_tables_met']
        audit_paths(text, tables)
        netlist = load_evidence(review['gray_netlist'], review['route_evidence']['routed_db_sha256']) if 'gray_netlist' in review else None
        if netlist is not None:
            inputs += [Path(review['gray_netlist'][key]['path']) for key in ('netlist','model')]
        gray_check = lambda report: gray_bounds(report, fdc, physical, netlist)
        gray = gray_check(text)
        check_sites(requested, physical, profile)
        rejected('wrong_database', lambda: require_routed_report(text, 'wrong_pnr.adf'))
        rejected('missing_corner', lambda: parse_tables(replace_once(
            r'Hold Summary\(Fast Corner\):', 'Removed hold corner:', text)))
        rejected('wrong_compute_period', lambda: parse_tables(replace_once(
            r'^(\s*compute_clk\s+)20\.0000', r'\g<1>40.0000', text)))
        summary = 'Some Constraints Violated' if tables['all_tables_met'] else 'All Constraints Met'
        rejected('contradictory_summary', lambda: parse_tables(replace_once(
            r'(Design Summary\s*:\s*)(?:All Constraints Met|Some Constraints Violated)',
            lambda match: match[1]+summary, text)))
        block = next(b for b in path_blocks(text)
                     if re.match(r'Startpoint\s*:\s*[^\n]*/u_aw_fifo/wr_gray\[0\]', b)
                     and 'MaxDelay Path' in b and 'max (slow corner)' in b)
        rejected('missing_gray_bit', lambda: gray_check(text.replace(block, '', 1)))
        swapped = replace_once(r'(^Endpoint\s*:\s*[^\n]*wr_gray_rd_sync1)\[0\]', r'\g<1>[1]', block)
        rejected('swapped_gray_bit', lambda: gray_check(text.replace(block, swapped, 1)))
        relaxed = replace_once(r'MaxDelay Path 6\.000ns', 'MaxDelay Path 60.000ns', block)
        rejected('relaxed_gray_delay', lambda: gray_check(text.replace(block, relaxed, 1)))
        need = float(re.search(r'Data required time\s+([\d.]+)', block)[1])
        violated = re.sub(r'(Data arrival time\s+)[\d.]+', r'\g<1>7.000', block)
        violated = re.sub(r'Slack \(MET\)\s+[\d.]+', f'Slack (VIOLATED) {need-7:.3f}', violated)
        rejected('numeric_gray_violation', lambda: gray_check(text.replace(block, violated, 1)))
        wrong_pin = replace_once(r'(^def_port \{uart_rx\} [^\n]*?)LOC=\S+', r'\g<1>LOC=A1', physical)
        rejected('wrong_pin', lambda: check_sites(requested, wrong_pin, profile))
        wrong_gate = replace_once(r'(ddrphy_ioclk_gate\[0\]/opit_0_inv\} )CLMA_357_354', r'\g<1>CLMA_351_354', physical)
        rejected('wrong_ddr_gate', lambda: check_sites(requested, wrong_gate, profile))
        if profile=='avatar':
            missing_key=replace_once(r'^def_port \{mode_button_n\} [^\n]*\n', '', physical)
            rejected('missing_avatar_mode_key',lambda: check_sites(requested,missing_key,profile))
        if args.clock_review:
            receipt_path = args.clock_review/'result.json'
            receipt = json.loads(receipt_path.read_text(encoding='utf-8'))
            clock_path = Path(receipt['report']['path'])
            if sha256(clock_path) != receipt['report']['sha256']:
                raise ValueError('Clock report changed')
            inputs += [receipt_path, clock_path]
            clock_text = clock_path.read_text(encoding='utf-8')
            logical = {re.sub(r'/opit_\d+(?:_inv)?$', '', n): n
                       for n in re.findall(r'^def_inst_site \{([^}]+)\}', physical, re.M)}
            stages = {}
            for group in gray['groups']:
                for path in group['paths']:
                    meta = re.sub(r'/opit_\d+(?:_inv)?$', '', path['end'])
                    nxt = meta.replace('gray_rd_sync1[', 'gray_rd_sync2[').replace(
                        'gray_wr_sync1[', 'gray_wr_sync2[').replace('gray_meta[', 'gray_sync[')
                    stages[path['end']] = logical[nxt]
            audit(clock_text, gray['groups'], stages)
            clock_block = next(b for b in path_blocks(clock_text)
                               if re.search(r'^Endpoint\s*:\s*[^\n]*/u_aw_fifo/wr_gray\[0\]/opit_\d+(?:_inv)?/D\s*$', b, re.M)
                               and 'min (slow corner)' in b)
            rejected('missing_clock_observation', lambda: audit(clock_text.replace(clock_block, '', 1), gray['groups'], stages))
            rejected('duplicate_clock_observation', lambda: audit(clock_text+clock_block, gray['groups'], stages))
            spread = replace_once(r'(^[ \t]*Capture Clock Delay\s*:\s*)[\d.]+', r'\g<1>100.000', clock_block)
            rejected('excessive_clock_spread', lambda: audit(clock_text.replace(clock_block, spread, 1), gray['groups'], stages))
            mismatch = replace_once(r'(^\s*Clock )\S+( \((?:rising|falling) edge\))', r'\g<1>wrong_clock\2', clock_block)
            rejected('clock_group_mismatch', lambda: audit(clock_text.replace(clock_block, mismatch, 1), gray['groups'], stages))
        result['status'] = 'PASS'
    except Exception as error:
        result['error'] = str(error)
    result['inputs'] = {str(p.resolve()): sha256(p) for p in inputs if p.is_file()}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('x', encoding='utf-8') as stream:
        stream.write(json.dumps(result, indent=2)+'\n')
    print(result['status'], len(result['controls']), result.get('error', ''), flush=True)
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
