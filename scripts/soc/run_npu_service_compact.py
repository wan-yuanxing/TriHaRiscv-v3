"""Compare original and compact B03 service buffers in simulation and PDS map."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/video'))
from common import tool, write_json
sys.path.insert(0, str(ROOT / 'scripts/npu'))
from frozen_inputs import FrozenInputs
from resource_probe import resource_report, tcl

ORIGINAL = ['rtl/soc/npu_service_axi128.v', 'rtl/npu/upstream/b03/rtl/platform/b03_block_dma.v']
COMPACT = ['rtl/soc/npu_service_axi128_compact.v', 'rtl/npu/b03_block_dma_compact.v']
VENDOR = Path('D:/pango/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation/GTP_RAM32X2DP.v')


def execute(command, log, cwd, timeout=120):
    completed = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True,
                               timeout=timeout, creationflags=subprocess.CREATE_NO_WINDOW)
    log.write_bytes(completed.stdout + completed.stderr)
    text = log.read_text(encoding='utf-8', errors='replace')
    if completed.returncode or re.search(r'(?im)^\s*(?:ERROR[: ]|FATAL[: ]|E:)', text):
        raise RuntimeError(str(log) + ': ' + text[-2000:])
    return text


def scan_fixture(module, source):
    header = source[source.index('input wire'):].split(');', 1)[0]
    ports, direction, width = [], None, None
    for part in header.split(','):
        part = part.strip()
        match = re.fullmatch(r'(input|output)\s+(?:wire|reg)\s*(?:\[(\d+):0\])?\s*(\w+)', part)
        if match:
            direction, high, name = match.groups()
            width = int(high) + 1 if high else 1
        else:
            if not re.fullmatch(r'\w+', part) or direction is None:
                raise ValueError('unparsed port: ' + part)
            name = part
        ports.append((direction, name, width))
    inputs, outputs, connections = 0, 0, []
    for direction, name, width in ports:
        if name in ('clk_i', 'clk'):
            signal = 'clk_i'
        elif name in ('rst_ni', 'rst_n'):
            signal = 'rst_ni'
        elif direction == 'input':
            signal = 'inputs_q[' + str(inputs) + '+:' + str(width) + ']'
            inputs += width
        else:
            signal = 'outputs_w[' + str(outputs) + '+:' + str(width) + ']'
            outputs += width
        connections.append('.' + name + '(' + signal + ')')
    if inputs < 100 or outputs < 100:
        raise ValueError('incomplete scan boundary')
    fixture = f'''module npu_compact_scan_top(input wire clk_i,rst_ni,scan_shift_i,scan_capture_i,scan_data_i,output wire scan_data_o);
reg [{inputs-1}:0] inputs_q;wire [{outputs-1}:0] outputs_w;reg [{outputs-1}:0] outputs_q;
always @(posedge clk_i or negedge rst_ni)begin
 if(!rst_ni)begin inputs_q<=0;outputs_q<=0;end
 else begin
  if(scan_shift_i)inputs_q<={{inputs_q[{inputs-2}:0],scan_data_i}};
  if(scan_capture_i)outputs_q<=outputs_w;else if(scan_shift_i)outputs_q<={{1'b0,outputs_q[{outputs-1}:1]}};
 end
end
assign scan_data_o=outputs_q[0];
{module} u_service({','.join(connections)});
endmodule
'''
    return fixture, inputs, outputs


def map_module(output, label, source, frozen):
    mapped = output / ('map_' + label)
    mapped.mkdir()
    module = source.stem
    fixture_text, inputs, outputs = scan_fixture(module, source.read_text())
    fixture = mapped / 'scan_fixture.v'
    fixture.write_text(fixture_text, encoding='utf-8')
    fdc = mapped / 'boundary.fdc'
    fdc.write_text('create_clock -name compute_clk -period 10.000 [get_ports {clk_i}]\n', encoding='utf-8')
    script = mapped / 'map.tcl'
    script.write_text('\n'.join([
        'set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676',
        'add_design ' + tcl(source), 'add_design ' + tcl(fixture), 'add_constraint ' + tcl(fdc),
        'compile -top_module npu_compact_scan_top',
        'synthesize -ads -write_verilog TRUE', 'dev_map -detail',
    ]) + '\n', encoding='utf-8')
    print('MAPPING ' + label, flush=True)
    frozen.verify()
    log = execute([tool('pds_shell'), '-file', script, '-work_dir', mapped,
                   '-project_name', 'npu_compact_scan_top'], mapped / 'pds.log', mapped, 1200)
    for stage in ('compile', 'synthesize', 'dev_map'):
        if not re.search(r'(?m)^Executing : ' + stage + r'(?: [^\r\n]*)? successfully\.', log):
            raise ValueError('missing successful PDS stage ' + label + ': ' + stage)
    reports = [resource_report(mapped / folder / ('npu_compact_scan_top.' + ext), stage)
               for folder, ext, stage in [('synthesize', 'snr', 'SYN'), ('device_map', 'dmr', 'dev_map')]]
    for report in reports:
        rows = [row for row in report['hierarchy'] if row['path'] == 'u_service']
        if len(rows) != 1 or rows[0]['lut'] <= 0:
            raise ValueError('missing live DUT in ' + label + ' ' + report['stage'])
        report['dut'] = rows[0]
    frozen.verify()
    return {'reports': reports, 'fixture_input_bits': inputs, 'fixture_output_bits': outputs,
            'fixture_sha256': hashlib.sha256(fixture.read_bytes()).hexdigest(),
            'tcl_sha256': hashlib.sha256(script.read_bytes()).hexdigest()}


def run(output, do_map, registered_block=False, block_source=None):
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {'status': 'RUNNING', 'tests': {}, 'mapping': {}, 'board_verified': False,
              'routed': False, 'timing_closed': False}
    write_json(output / 'result.json', report)
    started = time.monotonic()
    try:
        names = ORIGINAL + COMPACT + ['tb/soc/tb_npu_service_axi128.sv', 'tb/soc/tb_npu_service_compact.sv',
                'scripts/soc/run_npu_service_compact.py', 'scripts/soc/resource_probe.py',
                'scripts/npu/frozen_inputs.py', 'scripts/video/common.py']
        frozen = FrozenInputs(ROOT, output / 'inputs_snapshot', names)
        block_candidate=None
        if block_source:
            block_candidate=output/'candidate/b03_block_dma_compact.v'
            frozen.external(Path(block_source).resolve(),block_candidate)
        vendor = output / 'vendor/GTP_RAM32X2DP.v'
        frozen.external(VENDOR, vendor)
        compiler, simulator = tool('iverilog'), tool('vvp')
        frozen.track(compiler)
        frozen.track(simulator)
        if do_map:
            frozen.track(tool('pds_shell'))
        for index, kind in enumerate(('adapter', 'block')):
            for compact in (False, True):
                label = kind + ('_compact' if compact else '_baseline')
                source = frozen.directory / (COMPACT if compact else ORIGINAL)[index]
                if compact and kind=='block' and block_candidate:source=block_candidate
                if kind == 'adapter':
                    top = 'tb_npu_service_axi128'
                    test = (frozen.directory / 'tb/soc/tb_npu_service_axi128.sv').read_text()
                    test = test.replace('npu_service_axi128 dut', source.stem + ' dut')
                    test = test.replace('splits=%0d",checks,aw_count,b_count,ar_count,before_aw,before_w,split_count)',
                                        'splits=%0d cycles=%0d",checks,aw_count,b_count,ar_count,before_aw,before_w,split_count,ticks)')
                    test=test.replace('endmodule','always @(posedge clk_i) if(rst_ni&&p_cmd_ready&&(p_read_valid||p_done_valid))\n'
                        ' $fatal(1,"adapter command overlaps registered response");\nendmodule')
                    tb = output / (label + '.sv')
                    tb.write_text(test, encoding='utf-8')
                    defines = []
                else:
                    top = 'tb_npu_service_compact'
                    tb = frozen.directory / 'tb/soc/tb_npu_service_compact.sv'
                    if compact and registered_block:
                        test=tb.read_text(encoding='utf-8').replace('.TIMEOUT_CYCLES(300)',
                            '.TIMEOUT_CYCLES(300),.ALLOW_COMMAND_CYCLE_RESPONSE(0)')
                        tb=output/'registered_block.sv';tb.write_text(test,encoding='utf-8')
                    defines = ['-DDMA_MODULE=' + source.stem]
                binary = output / (label + '.vvp')
                frozen.track(tb)
                frozen.verify()
                log = execute([compiler, '-g2012', '-s', top, *defines, '-o', binary, source, vendor, tb],
                              output / (label + '.compile.log'), output)
                if re.search(r'warning', log, re.I):
                    raise ValueError('simulation compile warning: ' + log)
                log = execute([simulator, binary], output / (label + '.simulation.log'), output)
                passes = [line for line in log.splitlines() if line.startswith('PASS ')]
                if len(passes) != 1 or ('checks=33 ' if kind == 'adapter' else 'checks=86 ') not in passes[0]:
                    raise ValueError('missing complete scoreboard PASS: ' + label)
                report['tests'][label] = {'pass_line': passes[0], 'test_sha256': hashlib.sha256(tb.read_bytes()).hexdigest()}
                if compact and passes[0] != report['tests'][kind + '_baseline']['pass_line']:
                    raise ValueError('compact changed transaction or cycle counts: ' + kind)
                print(label + ': ' + passes[0], flush=True)
                if do_map:
                    report['mapping'][label] = map_module(output, label, source, frozen)
                    write_json(output / 'result.json', report)
        frozen.verify()
        report.update(status='PASS_SIMULATION_AND_MAPPING' if do_map else 'PASS_SIMULATION_ONLY',
                      host_seconds=time.monotonic()-started, sources_sha256=frozen.inputs,
                      tools_sha256=frozen.tracked, vendor_sha256=frozen.external_inputs,
                      cycle_delta=0, scope='Cycle-count-identical adapter/block scoreboards and optional same-stage standalone mapping; no full-frame, routed timing or board claim.')
        write_json(output / 'result.json', report)
        print(json.dumps(report, indent=2), flush=True)
        return report
    except Exception as exc:
        report.update(status='FAIL', error=str(exc))
        write_json(output / 'result.json', report)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--map', action='store_true')
    parser.add_argument('--registered-block',action='store_true')
    parser.add_argument('--block-source',type=Path)
    args = parser.parse_args()
    try:
        run(args.output, args.map, args.registered_block, args.block_source)
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
