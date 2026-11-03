"""Audit the two compute-domain reset chains and their async-input exception.

This checks synthesized topology and FDC scope, not routed synchronizer timing
or metastability. Local release fanout and stage-to-stage paths remain timed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
PATTERN = (r'^g_full[.]impl/face/(u_compute_cdc/cpu_release_q|'
           r'u_control_cdc/s_release)\[(0|1|1:0)\]/C$')
COMMAND = ('set_false_path -from [get_clocks {sys_clk}] -to '
           '[get_pins {g_full.impl/face/u_compute_cdc/cpu_release_q[1:0]/C '
           'g_full.impl/face/u_control_cdc/s_release[1:0]/C}]')


def audit(fdc, netlist):
    # PDS FDC import uses unsplit bus names. Use the queried literal names,
    # not Python regex syntax (PDS rejected the grouped alternation).
    commands = [line.strip() for line in fdc.splitlines()
                if line.strip().startswith('set_false_path')
                and ('cpu_release_q' in line or '/s_release' in line)]
    assert commands == [COMMAND], 'missing or widened compute reset input exception'
    chains = {}
    for module, chain, clock, output, instance in [
        ('triha_axi128_cdc', 'cpu_release_q', 'cpu_clk_i', 'cpu_rst_no', 'u_compute_cdc'),
        ('soc_axil_cdc', 's_release', 's_clk_i', 's_release[1]', 'u_control_cdc'),
    ]:
        match = re.search(r'\bmodule\s+' + module + r'\s*\(.*?\bendmodule', netlist, re.S)
        assert match, 'missing synthesized module ' + module
        body = match[0]
        pins = []
        for bit in range(2):
            name = chain + '[' + str(bit) + ']'
            cell = re.search(r'GTP_DFF_C\s*/\*\s*\\' + re.escape(name)
                             + r'\s*\*/\s*#\(.*?\);', body, re.S)
            assert cell, 'missing preserved async-clear DFF ' + name
            ports = dict(re.findall(r'\.(Q|C|CLK|D)\s*\(\s*([^()]+?)\s*\)', cell[0]))
            assert ports == dict(Q=chain+'[0]' if bit == 0 else output,
                                 C='N0', CLK=clock,
                                 D="1'b1" if bit == 0 else chain+'[0]'), 'broken reset chain ' + name
            pins.append('g_full.impl/face/' + instance + '/' + name + '/C')
        # Stage zero must feed only the second D input, not functional reset logic.
        connections = re.findall(r'\.(\w+)\s*\(\s*' + re.escape(chain+'[0]') + r'\s*\)', body)
        assert sorted(connections) == ['D', 'Q'], 'first release stage escapes synchronizer'
        assert all(re.fullmatch(PATTERN, pin) for pin in pins)
        # PDS imports FDC before bit splitting, when this is one [1:0] C pin.
        bus = 'g_full.impl/face/' + instance + '/' + chain
        assert re.fullmatch(PATTERN, bus + '[1:0]/C')
        assert not re.fullmatch(PATTERN, bus + '[2]/C')
        assert not re.fullmatch(PATTERN, bus + '[3:0]/C')
        chains[instance] = pins
    excluded = [pin for pins in chains.values() for pin in pins]
    for pin in excluded:
        for port in ['D', 'Q', 'CLK', 'CE']:
            assert not re.fullmatch(PATTERN, pin.rsplit('/', 1)[0]+'/'+port)
    for pin in ['g_full.impl/face/video_irq_sync[0]/C',
                'g_full.impl/face/compute_fault_sync[0]/C',
                'g_full.impl/face/u_compute_cdc/u_aw_fifo/wr_gray[0]/C',
                'g_full.impl/face/u_control_cdc/u_aw/wr_gray[0]/C']:
        assert not re.fullmatch(PATTERN, pin), 'local reset incorrectly excluded'
    return excluded


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--netlist', required=True, type=Path)
    parser.add_argument('--fdc', type=Path, default=ROOT/'fpga/pg2l100h/constraints/triha_face_board.fdc')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    fdc = args.fdc.read_text(encoding='utf-8')
    netlist = args.netlist.read_text(encoding='utf-8')
    result = dict(status='FAIL', scope=__doc__, inputs={str(p.resolve()): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in [args.fdc, args.netlist, Path(__file__)]})
    try:
        result['excluded_async_inputs'] = audit(fdc, netlist)
        negatives = {
            'missing_exception': (fdc.replace(COMMAND, ''), netlist),
            'data_pin_exception': (fdc.replace(COMMAND, COMMAND.replace('/C', '/D')), netlist),
            'widened_pin_exception': (fdc.replace(COMMAND, COMMAND.replace('/C', '/*')), netlist),
            'single_stage_compute': (fdc, netlist.replace('.D (cpu_release_q[0])', ".D (1'b1)")),
            'single_stage_control': (fdc, netlist.replace('.D (s_release[0])', ".D (1'b1)")),
        }
        result['negative_controls'] = {}
        for name, (bad_fdc, bad_netlist) in negatives.items():
            try:
                audit(bad_fdc, bad_netlist)
            except AssertionError as error:
                result['negative_controls'][name] = str(error)
            else:
                raise AssertionError('mutation survived: ' + name)
        result['status'] = 'PASS'
    except AssertionError as error:
        result['error'] = str(error)
    (args.output/'result.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(result['status'], result.get('error', ''), args.output)
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
