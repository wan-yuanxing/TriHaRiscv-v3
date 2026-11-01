"""Map the admitted complete B03 frame service; no routing or board access."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
TOP = 'b03_frame_service_map_top'
WRAPPER = 'fpga/pg2l100h/rtl/' + TOP + '.v'


def scan_fixture(source):
    """Make all boundary bits driveable/observable with seven package pins.

    PDS dev_map rejects a -disable_io_insertion netlist.  This fixture is
    separate from u_service and is reported separately at each stage.
    """
    ports = re.findall(r'^\s*(input|output) wire\s*(?:\[(\d+):0\])?\s*(\w+)\s*[,\n]',
                       source.split(');', 1)[0], re.M)
    if len(ports) != 84:
        raise ValueError('unexpected frame service boundary')
    inputs, outputs, connections = [], [], []
    for direction, high, name in ports:
        width = int(high) + 1 if high else 1
        if name in ('clk_i', 'rst_ni'):
            connections.append('.' + name + '(' + name + ')')
        else:
            group = inputs if direction == 'input' else outputs
            offset = sum(item[1] for item in group)
            group.append((name, width))
            bus = 'inputs_q' if direction == 'input' else 'outputs_w'
            connections.append('.' + name + '(' + bus + '[' + str(offset) + '+:' + str(width) + '])')
    ni, no = sum(p[1] for p in inputs), sum(p[1] for p in outputs)
    return '''`timescale 1ns/1ps
module b03_frame_service_scan_top(input wire clk_i,rst_ni,scan_shift_i,scan_capture_i,scan_data_i,
                                 output wire scan_data_o);
 reg [{ni1}:0] inputs_q;
 wire [{no1}:0] outputs_w;
 reg [{no1}:0] outputs_q;
 always @(posedge clk_i or negedge rst_ni) begin
  if(!rst_ni) begin inputs_q<=0;outputs_q<=0;end
  else begin
   if(scan_shift_i) inputs_q<={{inputs_q[{ni2}:0],scan_data_i}};
   if(scan_capture_i) outputs_q<=outputs_w;
   else if(scan_shift_i) outputs_q<={{1'b0,outputs_q[{no1}:1]}};
  end
 end
 assign scan_data_o=outputs_q[0];
 b03_frame_service_map_top u_service({connections});
endmodule
'''.format(ni1=ni-1,ni2=ni-2,no1=no-1,connections=',\n  '.join(connections)), ni, no


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def tcl(path):
    value = Path(path).resolve().as_posix()
    if any(c in value for c in '{}\r\n'):
        raise ValueError('unsupported Tcl path')
    return '{' + value + '}'


def resource_report(path, stage):
    text = path.read_text(encoding='utf-8', errors='replace')
    if stage == 'dev_map':
        totals = {m[1].lower(): float(m[2]) for m in re.finditer(
            r'\| (APM|FF|LUT|DRM)\s+\| ([\d.]+)', text)}
    else:
        patterns = {'lut': r'Total LUTs: ([\d.]+)', 'ff': r'Total Registers: ([\d.]+)',
                    'apm': r'Total APMs = ([\d.]+)', 'drm': r'Total DRM = ([\d.]+)'}
        totals = {k: float(re.search(v, text)[1]) for k, v in patterns.items()}
    if set(totals) != {'lut', 'ff', 'apm', 'drm'}:
        raise ValueError('incomplete resource summary')
    rows, stack = [], []
    for number, line in enumerate(text.splitlines(), 1):
        cells = line.split('|')
        if len(cells) < 7 or '+' not in cells[1]:
            continue
        try:
            counts = [float(value.strip()) for value in cells[2:7]]
        except ValueError:
            continue
        depth = cells[1].index('+')
        name = cells[1].split('+', 1)[1].strip()
        while stack and stack[-1][0] >= depth:
            stack.pop()
        hierarchy = '/'.join([value[1] for value in stack] + [name])
        stack.append((depth, name))
        rows.append(dict(path=hierarchy, line=number, lut=counts[0], ff=counts[1],
                         lutram_included_in_lut=counts[2], apm=counts[3], drm=counts[4]))
    return dict(stage=stage, path=str(path), sha256=sha(path), total=totals, hierarchy=rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pds-shell', type=Path,
                        default=Path('D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe'))
    args = parser.parse_args()
    work = ROOT / 'build/soc' / ('resource_probe_b03_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    work.mkdir(parents=True, exist_ok=False)
    result = dict(status='RUNNING', directory=str(work), top=TOP, clock_mhz=100,
                  scope='Complete B03 frame/Graph/Layer/POST plus block DMA and phase mux; no UART, AXI adapter, CPU, Video, native bridge, PLL or HMIC',
                  source_only_admission=True, routed=False, timing_closed=False, board_accessed=False)
    save(work / 'result.json', result)
    print('RESOURCE_PROBE', work, flush=True)
    try:
        subprocess.run([sys.executable, str(ROOT / 'scripts/npu/import_b03.py'), '--check'],
                       cwd=ROOT, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        filelist = (ROOT / 'config/npu_b03_sources.f').read_text(encoding='utf-8').splitlines()
        if len(filelist) != 40 or len(set(filelist)) != 40:
            raise ValueError('expected the reviewed explicit 40-source closure')
        names = filelist + [WRAPPER]
        result['input_sha256'] = {}
        for name in names:
            source, target = ROOT / name, work / 'src' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
            result['input_sha256'][name] = sha(source)
        result['admission_manifest_sha256'] = sha(ROOT / 'rtl/npu/upstream/b03/UPSTREAM.json')
        result['runner_sha256'] = sha(Path(__file__))
        result['pds_shell_sha256'] = sha(args.pds_shell)
        fixture, input_bits, output_bits = scan_fixture((ROOT / WRAPPER).read_text())
        fixture_path = work / 'scan_fixture.v'
        fixture_path.write_text(fixture, encoding='utf-8')
        map_top = 'b03_frame_service_scan_top'
        result.update(map_top=map_top, fixture_input_bits=input_bits, fixture_output_bits=output_bits,
                      fixture_sha256=sha(fixture_path), service_hierarchy='u_service')
        fdc = work / 'boundary.fdc'
        fdc.write_text('create_clock -name compute_clk -period 10.000 [get_ports {clk_i}]\n', encoding='utf-8')
        commands = ['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
        commands += ['add_design ' + tcl(work / 'src' / name) for name in names]
        commands += ['add_design ' + tcl(fixture_path), 'add_constraint ' + tcl(fdc), 'compile -top_module ' + map_top,
                     'synthesize -ads -write_verilog TRUE', 'dev_map -detail']
        script = work / 'map.tcl'
        script.write_text('\n'.join(commands) + '\n', encoding='utf-8')
        command = [str(args.pds_shell), '-file', str(script), '-work_dir', str(work), '-project_name', TOP]
        result['command'] = command
        result['tcl_sha256'] = sha(script)
        save(work / 'result.json', result)
        with (work / 'pds.stdout.log').open('wb') as stdout, (work / 'pds.stderr.log').open('wb') as stderr:
            completed = subprocess.run(command, cwd=work, stdout=stdout, stderr=stderr,
                                       creationflags=subprocess.CREATE_NO_WINDOW)
        result['returncode'] = completed.returncode
        log = (work / 'pds.stdout.log').read_text(encoding='utf-8', errors='replace')
        result['reports'] = []
        for directory, extension, stage in [('synthesize', 'snr', 'SYN'), ('device_map', 'dmr', 'dev_map')]:
            report_path = work / directory / (map_top + '.' + extension)
            if report_path.exists():
                result['reports'].append(resource_report(report_path, stage))
        for stage in ('compile', 'synthesize', 'dev_map'):
            if not re.search(r'(?m)^Executing : ' + stage + r'(?: [^\r\n]*)? successfully\.', log):
                raise ValueError('missing successful stage: ' + stage)
        if completed.returncode or re.search(r'(?m)^\s*(?:E:|ERROR[: ]|FATAL[: ])', log):
            raise ValueError('PDS reported an error')
        rows = result['reports'][0]['hierarchy']
        for required in ('u_frame', 'u_frame/graph', 'u_frame/layer', 'u_frame/post', 'u_blocks', 'u_phase'):
            if not any(row['path'] == 'u_service/' + required and row['lut'] > 0 for row in rows):
                raise ValueError('required live hierarchy missing: ' + required)
        result['source_unchanged'] = all(sha(ROOT / name) == expected and sha(work / 'src' / name) == expected
                                       for name, expected in result['input_sha256'].items())
        if not result['source_unchanged']:
            raise ValueError('source snapshot changed during mapping')
        result['status'] = 'PASS_MAPPING_ONLY'
    except Exception as error:
        result.update(status='FAIL', error=str(error))
    save(work / 'result.json', result)
    print(json.dumps({key: result.get(key) for key in ('status', 'error', 'directory', 'reports')}, indent=2), flush=True)
    return 0 if result['status'] == 'PASS_MAPPING_ONLY' else 1


if __name__ == '__main__':
    raise SystemExit(main())
