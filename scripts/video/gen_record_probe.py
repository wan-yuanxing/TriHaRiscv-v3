"""Generate a dual-clock registered scan boundary for component routing only."""
import argparse
import fnmatch
import json
from pathlib import Path
import re
import sys

from common import ROOT

BASE = 'fpga/pg2l100h/project/video_record_pipeline.json'
WRAPPER = 'fpga/pg2l100h/rtl/video_record_probe.sv'
FDC = 'fpga/pg2l100h/constraints/video_record_probe.fdc'
MANIFEST = 'fpga/pg2l100h/project/video_record_probe.json'
DIRECT = {'clk_i', 'rst_ni', 'pixel_clk', 'pixel_reset_n'}


def interface(source):
    header = source.split(');', 1)[0]
    ports = []
    for line in header.splitlines():
        line = line.split('//',1)[0]
        if not re.search(r'\b(input|output|inout)\b', line):
            continue
        match = re.fullmatch(r'\s*(input|output)\s+wire\s*(?:\[(\d+):0\]\s*)?(\w+)\s*,?\s*', line)
        if not match:
            raise ValueError('Unsupported component port declaration: ' + line)
        direction, high, name = match.groups()
        ports.append({'name': name, 'width': int(high) + 1 if high else 1, 'direction': direction})
    if not ports or len({p['name'] for p in ports}) != len(ports):
        raise ValueError('Missing or duplicate component ports')
    if {p['name'] for p in ports if p['name'] in DIRECT and p['direction'] == 'input' and p['width'] == 1} != DIRECT:
        raise ValueError('Clock/reset interface changed')
    return ports


def analyze(source, fdc):
    ports = interface(source)
    clocks = {
        'create_clock -name core_clk -period 8.000 [get_ports {clk_i}]',
        'create_clock -name pixel_clk -period 25.000 [get_ports {pixel_clk}]'}
    seen_clocks = set()
    io = {}
    internal = []
    for raw in fdc.splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('create_clock'):
            if line not in clocks or line in seen_clocks:
                raise ValueError('Unexpected or duplicate probe clock constraint')
            seen_clocks.add(line)
            internal.append(line)
        elif line.startswith(('set_input_delay', 'set_output_delay')):
            match = re.fullmatch(r'set_(input|output)_delay 0\.000 -clock \[get_clocks \{(core|pixel)_clk\}\] -(max|min) \[get_ports \{([^}]+)\}\]', line)
            if not match:
                raise ValueError('Unsupported component I/O budget')
            direction, domain, edge, patterns = match.groups()
            key = direction, domain, edge
            if key in io:
                raise ValueError('Duplicate component I/O constraint')
            names = set()
            for pattern in patterns.split():
                matched = {p['name'] for p in ports if p['direction'] == direction and fnmatch.fnmatchcase(p['name'], pattern)}
                if not matched:
                    raise ValueError('Unmatched component I/O pattern: ' + pattern)
                names |= matched
            io[key] = names
        elif re.fullmatch(r'set_false_path -from \[get_clocks \{(?:core|pixel)_clk\}\] -to \[get_cells \{[^}]+\}\]', line) or re.fullmatch(
                r'set_max_delay 6\.(?:0|000) -datapath_only -from \[get_cells \{[^}]+\}\] -to \[get_cells \{[^}]+\}\]', line):
            for group in re.findall(r'get_cells \{([^}]+)\}', line):
                if any(not re.fullmatch(r'u_[A-Za-z0-9_.*]+', token) for token in group.split()):
                    raise ValueError('Unsupported CDC endpoint')
            internal.append(re.sub(r'get_cells \{([^}]+)\}', lambda m: 'get_cells {' +
                                   ' '.join('u_pipeline.' + n for n in m[1].split()) + '}', line))
        else:
            raise ValueError('Unsupported component timing constraint: ' + line)
    semantic_internal = [re.sub(r'get_cells \{([^}]+)\}',
                         lambda m: 'get_cells {'+' '.join(sorted(set(m[1].split())))+'}',
                         re.sub(r'(?<=set_max_delay )6\.(?:000|0)(?= )', '6.0', line))
                         for line in internal]
    if (seen_clocks != clocks or len(internal) != 18 or len(set(semantic_internal)) != 18
            or sum(l.startswith('set_false_path') for l in internal) != 4):
        raise ValueError('Component clock/CDC constraint coverage changed')
    boundary = {}
    covered = set(DIRECT)
    for domain, clock, reset in [('core','clk_i','rst_ni'), ('pixel','pixel_clk','pixel_reset_n')]:
        boundary[domain] = {'clock': clock, 'reset': reset}
        for direction in ('input', 'output'):
            maximum = io.get((direction, domain, 'max'))
            minimum = io.get((direction, domain, 'min'))
            if maximum is None or maximum != minimum:
                raise ValueError('Missing or inconsistent max/min domain constraint')
            if direction == 'input' and maximum & DIRECT != {reset}:
                raise ValueError('Reset belongs to the wrong clock domain')
            entries = []
            offset = 0
            for port in ports:
                if port['name'] not in maximum - DIRECT:
                    continue
                if port['name'] in covered:
                    raise ValueError('Component port has multiple timing domains')
                entries.append({'name':port['name'], 'width':port['width'], 'offset':offset})
                covered.add(port['name'])
                offset += port['width']
            if not entries:
                raise ValueError('Empty scan boundary')
            boundary[domain][direction+'s'] = entries
            boundary[domain][direction+'_bits'] = offset
    if covered != {p['name'] for p in ports} or len(io) != 8:
        raise ValueError('Uncovered component ports or timing domains')
    return ports, boundary, internal


def boundary_map(source, fdc):
    return analyze(source, fdc)[1]


def render(root=ROOT):
    root = Path(root)
    base = json.loads((root/BASE).read_text(encoding='utf-8'))
    source = (root/'rtl/video/video_record_pipeline.sv').read_text(encoding='utf-8')
    old_fdc = (root/'fpga/pg2l100h/constraints/video_record_pipeline.fdc').read_text(encoding='utf-8')
    ports, boundary, timing = analyze(source, old_fdc)
    lines = ['`timescale 1ns/1ps', '`default_nettype none',
             '// Generated by gen_record_probe.py. Component STA only; no board/SoC claim.',
             'module video_record_probe (', '    input wire clk_i,', '    input wire rst_ni,',
             '    input wire pixel_clk,', '    input wire pixel_reset_n,']
    for domain in ('core','pixel'):
        lines += [f'    input wire {domain}_scan_i,', f'    input wire {domain}_shift_i,',
                  f'    input wire {domain}_capture_i,', f'    output wire {domain}_scan_o' + (',' if domain == 'core' else '')]
    lines += [');']
    connections = {name: name for name in DIRECT}
    for domain, data in boundary.items():
        ni, no = data['input_bits'], data['output_bits']
        lines += [f'    reg [{ni-1}:0] {domain}_input_q;', f'    reg [{no-1}:0] {domain}_output_q;',
                  f'    wire [{no-1}:0] {domain}_sampled;',
                  f'    assign {domain}_scan_o = {domain}_output_q[0];',
                  f"    always @(posedge {data['clock']} or negedge {data['reset']}) begin",
                  f"        if (!{data['reset']}) begin", f"            {domain}_input_q <= 0;",
                  f"            {domain}_output_q <= 0;", '        end else begin',
                  f'            if ({domain}_shift_i) {domain}_input_q <= {{{domain}_scan_i, {domain}_input_q[{ni-1}:1]}};',
                  f'            if ({domain}_capture_i) {domain}_output_q <= {domain}_sampled;',
                  f"            else if ({domain}_shift_i) {domain}_output_q <= {{1'b0, {domain}_output_q[{no-1}:1]}};",
                  '        end', '    end']
        for direction in ('input','output'):
            for port in data[direction+'s']:
                vector = domain + ('_input_q' if direction == 'input' else '_sampled')
                connections[port['name']] = f"{vector}[{port['offset']} +: {port['width']}]"
    lines += ['    video_record_pipeline u_pipeline (']
    lines += ['        .'+p['name']+'('+connections[p['name']]+')'+(',' if i<len(ports)-1 else '')
              for i,p in enumerate(ports)]
    lines += ['    );', 'endmodule', '`default_nettype wire', '']
    fdc = ['# Generated component scan boundary. No physical board or global CDC claim.'] + timing
    for domain, data in boundary.items():
        fdc += [f'set_clock_uncertainty -setup 0.100 [get_clocks {{{domain}_clk}}]',
                f'set_clock_uncertainty -hold 0.050 [get_clocks {{{domain}_clk}}]']
        for edge, delay in [('max','2.000'),('min','0.500')]:
            fdc.append(f"set_input_delay {delay} -clock [get_clocks {{{domain}_clk}}] -{edge} [get_ports {{{data['reset']} {domain}_scan_i {domain}_shift_i {domain}_capture_i}}]")
            fdc.append(f'set_output_delay {delay} -clock [get_clocks {{{domain}_clk}}] -{edge} [get_ports {{{domain}_scan_o}}]')
    manifest = {'schema_version':1, 'target':'video_record_probe', 'top':'video_record_probe',
                'test_top':'tb_record_probe_idle', 'sources':[WRAPPER]+base['sources'],
                'tests':['tb/video/tb_record_probe_idle.sv'], 'constraints':[FDC],
                'boundary':boundary, 'generator':'scripts/video/gen_record_probe.py',
                'source_manifest':BASE,
                'scope':'Full default record pipeline with separate core/pixel registered scan boundaries; component routing only. No legal-traffic, CPU/NPU, DDR visibility, board or full-system timing claim.'}
    return {WRAPPER:'\n'.join(lines), FDC:'\n'.join(fdc)+'\n',
            MANIFEST:json.dumps(manifest,ensure_ascii=False,indent=2)+'\n'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    try:
        for name, expected in render().items():
            path = ROOT/name
            if args.check:
                if not path.is_file() or path.read_text(encoding='utf-8') != expected:
                    raise ValueError('Generated probe is stale: ' + name)
            else:
                path.parent.mkdir(parents=True,exist_ok=True)
                path.write_text(expected,encoding='utf-8',newline='\n')
    except (ValueError,KeyError,OSError) as error:
        print(str(error),file=sys.stderr)
        return 1
    print('VIDEO_RECORD_PROBE_' + ('CHECK' if args.check else 'GENERATE') + '_PASS')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
