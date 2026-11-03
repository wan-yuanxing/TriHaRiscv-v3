"""Verify and map the application-only held-record CDC composition."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/video'))
from common import input_hashes, sha256, tool, write_json
from resource_probe import resource_report, tcl
from test_record_renderer import fixtures

COMPACT = ['rtl/video/display_mode_cdc_held.sv', 'rtl/video/display_record_pixels_compact.sv',
           'rtl/video/video_record_renderer_compact.sv', 'rtl/video/video_display_record_compact.sv',
           'rtl/video/video_display_mmio_compact.sv']


def display_source_negative(work, display_tb, display_sources, iv, vvp):
    """Prove the actual composition detects a broken upstream record lease."""
    directory = work / 'display_source_violation'
    fixtures(directory, 80, 64)
    injection = '''
 initial begin
  do @(posedge core_clk);while(!(dut.r_cmd_valid && dut.r_cmd_ready));
  @(negedge core_clk);
  dut.g_full_mmio.u_mmio.record_data[5119]=~dut.g_full_mmio.u_mmio.record_data[5119];
  repeat(10) @(negedge core_clk);
  $fatal(1,"COMPOSED_SOURCE_VIOLATION_NOT_DETECTED");
 end
'''
    assert display_tb.count('endmodule') == 1
    tb_path = directory / 'tb_negative.sv'
    tb_path.write_text(display_tb.replace('endmodule', injection + 'endmodule'), encoding='utf-8')
    binary = directory / 'sim.vvp'
    run([iv, '-g2012', '-Wall', '-I', ROOT / 'rtl/video/include', '-s', 'tb_video_display_record',
         '-o', binary] + [ROOT / n for n in display_sources] + [tb_path], directory / 'compile.log')
    run([vvp, binary, '+DIR=' + directory.as_posix()], directory / 'simulation.log',
        expected_error='HELD_RECORD_SOURCE_CHANGED')
    return 'PASS_EXPECTED_REJECTION'


def run(command, log, *, timeout=300, expected_error=None, cwd=ROOT):
    done = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True, timeout=timeout)
    log.write_bytes(done.stdout + done.stderr)
    output = (done.stdout + done.stderr).decode(errors='replace')
    if expected_error:
        if done.returncode == 0 or expected_error not in output:
            raise RuntimeError('negative case did not detect ' + expected_error)
    elif done.returncode:
        raise RuntimeError(str(log) + ': ' + output[-2500:])
    return output


def map_engine(work, result):
    manifest = json.loads((ROOT / 'fpga/pg2l100h/project/video_record_pipeline.json').read_text())
    excluded = {'video_shared_ddr', 'video_memory_scheduler', 'axi128_hmic256', 'video_record_pipeline'}
    names = [n for n in manifest['sources'] if Path(n).stem not in excluded] + COMPACT
    names += ['rtl/video/video_application_engine.sv', 'rtl/video/include/video_cfg.vh',
              'rtl/video/include/video_capture_v2.vh', 'rtl/video/include/video_display.vh']
    result['mapping_inputs'] = input_hashes(ROOT / n for n in names)
    mapped = work / 'map'; mapped.mkdir()
    for name in names:
        dst = mapped / 'src' / name; dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes((ROOT / name).read_bytes())
    # Generated target selects the compact production display explicitly.
    engine = (ROOT / 'rtl/video/video_application_engine.sv').read_text()
    engine = engine.replace('module video_application_engine #', 'module video_application_compact_probe #')
    target = mapped / 'video_application_compact_probe.sv'; target.write_text(engine, encoding='utf-8')
    header = engine[engine.index('module video_application_compact_probe'):].split(');', 1)[0]
    ports = re.findall(r'^\s*(input|output) wire\s*(?:\[(\d+):0\])?\s*(\w+)\s*[,\n]', header, re.M)
    ins, outs, connections = [], [], []
    for direction, high, name in ports:
        width = int(high) + 1 if high else 1
        if name in ('clk_i', 'rst_ni', 'pixel_clk', 'pixel_reset_n'):
            connections.append(f'.{name}({name})')
        else:
            group = ins if direction == 'input' else outs
            offset = sum(item[1] for item in group); group.append((name, width))
            bus = 'inputs_q' if direction == 'input' else 'outputs_w'
            connections.append(f'.{name}({bus}[{offset}+:{width}])')
    ni, no = sum(x[1] for x in ins), sum(x[1] for x in outs)
    if ni < 100 or no < 100:
        raise ValueError('incomplete application boundary')
    fixture = mapped / 'scan_fixture.sv'
    fixture.write_text(f'''module video_application_scan_top(input wire clk_i,rst_ni,pixel_clk,pixel_reset_n,scan_shift_i,scan_capture_i,scan_data_i,output wire scan_data_o);
reg [{ni-1}:0] inputs_q;wire [{no-1}:0] outputs_w;reg [{no-1}:0] outputs_q;
always @(posedge clk_i or negedge rst_ni)begin
 if(!rst_ni)begin inputs_q<=0;outputs_q<=0;end
 else begin if(scan_shift_i)inputs_q<={{inputs_q[{ni-2}:0],scan_data_i}};
 if(scan_capture_i)outputs_q<=outputs_w;else if(scan_shift_i)outputs_q<={{1'b0,outputs_q[{no-1}:1]}};end
end
assign scan_data_o=outputs_q[0];
video_application_compact_probe #(.ENABLE_AVATAR(0),.ENABLE_COMPACT(1)) u_service({','.join(connections)});
endmodule
''', encoding='utf-8')
    fdc = mapped / 'boundary.fdc'
    fdc.write_text('create_clock -name core_clk -period 8.000 [get_ports {clk_i}]\n'
                   'create_clock -name pixel_clock -period 25.000 [get_ports {pixel_clk}]\n', encoding='utf-8')
    commands = ['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
    commands += ['add_design ' + tcl(mapped / 'src' / n) for n in names if n.endswith('.sv')]
    commands += ['add_design ' + tcl(target), 'add_design ' + tcl(fixture), 'add_constraint ' + tcl(fdc),
                 'compile -system_verilog -top_module video_application_scan_top -include_path {' +
                 tcl(mapped / 'src/rtl/video/include') + '}',
                 'synthesize -ads -write_verilog TRUE', 'dev_map -detail']
    script = mapped / 'map.tcl'; script.write_text('\n'.join(commands) + '\n', encoding='utf-8')
    print('VIDEO_COMPACT_MAPPING', mapped, flush=True)
    log = run([tool('pds_shell'), '-file', script, '-work_dir', mapped,
               '-project_name', 'video_application_scan_top'], mapped / 'pds.log', timeout=1200, cwd=mapped)
    reports = [resource_report(mapped / folder / ('video_application_scan_top.' + ext), stage)
               for folder, ext, stage in [('synthesize', 'snr', 'SYN'), ('device_map', 'dmr', 'dev_map')]]
    result['mapping'] = dict(reports=reports, routed=False, timing_closed=False,
                             avatar_enabled=False, fixture_input_bits=ni, fixture_output_bits=no,
                             target_sha256=sha256(target), fixture_sha256=sha256(fixture), tcl_sha256=sha256(script))
    if 'Executing : dev_map -detail successfully.' not in log or re.search(r'(?m)^E:', log):
        raise RuntimeError('mapping did not complete cleanly')
    if result['mapping_inputs'] != input_hashes(ROOT / n for n in names):
        raise RuntimeError('mapping inputs changed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--map', action='store_true')
    args = parser.parse_args()
    work = ROOT / 'build/soc' / ('resource_probe_video_compact_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    work.mkdir(parents=True, exist_ok=False)
    result = dict(status='RUNNING', directory=str(work), cases={},
                  application_selection='RAM MMIO with held record CDC through renderer feedback')
    write_json(work / 'result.json', result)
    try:
        mp = ROOT / 'fpga/pg2l100h/project/video_record_pixels.json'
        manifest = json.loads(mp.read_text())
        display_manifest = json.loads((ROOT / 'fpga/pg2l100h/project/video_display_record.json').read_text())
        pixel_sources = manifest['sources'] + ['rtl/video/display_record_guard.sv']
        names = pixel_sources + COMPACT + ['tb/video/tb_video_record_compact.sv',
                 'tb/video/tb_display_record_guard.sv',
                 'tb/video/tb_display_record_pixels.sv', 'tb/video/check_record_pixels.py',
                 'tb/video/overlay_reference.py', 'scripts/soc/run_video_compact.py',
                 'tb/video/tb_video_display_mmio.sv', 'rtl/video/display_slot_owner.sv',
                 'scripts/video/test_record_renderer.py',
                 'rtl/video/include/video_cfg.vh', 'rtl/video/include/video_display.vh']
        names = list(dict.fromkeys(names + display_manifest['sources'] + display_manifest['tests']))
        result['inputs'] = input_hashes(ROOT / n for n in names)
        iv, vvp = tool('iverilog'), tool('vvp')
        result['tools'] = {str(t): sha256(t) for t in (iv, vvp)}
        guard_binary = work / 'guard.vvp'
        run([iv, '-g2012', '-Wall', '-I', ROOT / 'rtl/video/include', '-s', 'tb_display_record_guard',
             '-o', guard_binary, ROOT / 'rtl/video/display_record_guard.sv',
             ROOT / 'tb/video/tb_display_record_guard.sv'], work / 'guard_compile.log')
        guard_log = run([vvp, guard_binary], work / 'guard_simulation.log')
        if 'DISPLAY_RECORD_GUARD_PASS cases=246' not in guard_log:
            raise RuntimeError('missing record guard boundary/latency pass')
        result['cases']['guard'] = {'status': 'PASS', 'cases': 246}
        mmio_tb = (ROOT / 'tb/video/tb_video_display_mmio.sv').read_text()
        mmio_tb = mmio_tb.replace('video_display_mmio dut', 'video_display_mmio_compact dut')
        mmio_tb = mmio_tb.replace('waited<80', 'waited<1000')
        mmio_tb = mmio_tb.replace('submit(mode,41,0);repeat(25)cycle;', 'submit(mode,41,0);repeat(400)cycle;')
        mmio_path = work / 'tb_mmio.sv'; mmio_path.write_text(mmio_tb, encoding='utf-8')
        mmio_binary = work / 'mmio.vvp'
        run([iv, '-g2012', '-Wall', '-I', ROOT / 'rtl/video/include', '-s', 'tb_video_display_mmio', '-o', mmio_binary,
             ROOT / COMPACT[4], ROOT / 'rtl/video/display_record_guard.sv', ROOT / 'rtl/video/display_slot_owner.sv', mmio_path],
            work / 'mmio_compile.log')
        for case in range(9):
            log = run([vvp, mmio_binary, f'+CASE={case}'], work / f'mmio_{case}.log')
            if 'DISPLAY_MMIO_PASS' not in log:
                raise RuntimeError('missing MMIO pass')
            result['cases'][f'mmio_{case}'] = 'PASS'
        for label, case, half in [('held', 0, 12.5), ('ratio', 0, 17), ('reset', 2, 12.5),
                                  ('reset_release', 3, 12.5), ('source_violation', 1, 12.5)]:
            binary = work / (label + '.vvp')
            run([iv, '-g2012', '-Wall', '-s', 'tb_video_record_compact',
                 f'-Ptb_video_record_compact.CASE_ID={case}', f'-Ptb_video_record_compact.PIXEL_HALF={half}',
                 '-o', binary, ROOT / COMPACT[0], ROOT / 'tb/video/tb_video_record_compact.sv'], work / (label + '_compile.log'))
            log = run([vvp, binary], work / (label + '.log'), expected_error='HELD_RECORD_SOURCE_CHANGED' if case == 1 else None)
            if case != 1 and 'VIDEO_RECORD_COMPACT_CDC_PASS' not in log:
                raise RuntimeError('missing CDC pass')
            result['cases'][label] = 'PASS_EXPECTED_REJECTION' if case == 1 else 'PASS'
        tb = (ROOT / 'tb/video/tb_display_record_pixels.sv').read_text()
        tb = tb.replace('display_record_pixels dut', 'display_record_pixels_compact dut')
        poison = 'cmd_valid=0;cmd_data=~saved;cmd_frame=32\'hdeadbeef;cmd_generation=0;cmd_seq=0;cmd_slot=3;cmd_mode=3;'
        if tb.count(poison) != 1:
            raise ValueError('test source hold boundary changed')
        tb = tb.replace(poison, 'cmd_valid=0; // Application owner holds data through feedback.')
        tb_path = work / 'tb_pixels_held.sv'; tb_path.write_text(tb, encoding='utf-8')
        for label, case, half in [('pixels', 0, 12.5), ('pixels_ratio', 0, 17), ('pixels_tight', 0, 12.5), ('pending_reset', 4, 12.5),
                                  ('sample_fault', 3, 12.5), ('generation', 7, 12.5), ('new_source_asset', 8, 12.5)]:
            directory = work / label
            run([sys.executable, ROOT / manifest['reference'], 'generate', '--directory', directory,
                 '--width', '80', '--height', '64'], work / (label + '_fixture.log'))
            binary = directory / 'sim.vvp'
            run([iv, '-g2012', '-Wall', '-I', ROOT / 'rtl/video/include', '-s', 'tb_display_record_pixels',
                 '-Ptb_display_record_pixels.W=80', '-Ptb_display_record_pixels.H=64',
                 '-Ptb_display_record_pixels.REQUEST_LATENCY=10', f'-Ptb_display_record_pixels.TIGHT={int(label == "pixels_tight")}',
                 f'-Ptb_display_record_pixels.CASE_ID={case}', f'-Ptb_display_record_pixels.PIXEL_HALF={half}',
                 '-o', binary] + [ROOT / n for n in pixel_sources] + [ROOT / COMPACT[0], ROOT / COMPACT[1], tb_path],
                work / (label + '_compile.log'))
            log = run([vvp, binary, '+DIR=' + directory.as_posix()], work / (label + '.log'))
            if 'DISPLAY_RECORD_PIXELS_PASS' not in log:
                raise RuntimeError('missing pixel pass ' + label)
            run([sys.executable, ROOT / manifest['reference'], 'check', '--directory', directory], work / (label + '_oracle.log'))
            result['cases'][label] = json.loads((directory / 'checked.json').read_text())
        display_tb = (ROOT / 'tb/video/tb_video_display_record.sv').read_text()
        display_tb = display_tb.replace(' video_display_record #', ' video_display_record_compact #')
        display_tb = display_tb.replace('dut.u_mmio.phase!=1', '!dut.u_mmio.locked')
        display_tb = display_tb.replace('dut.u_mmio.', 'dut.g_full_mmio.u_mmio.')
        # Shadow writes may proceed during a lease, but a new submission must
        # not reload/shift the held record before actual output feedback.
        first = 'submit(0,1,10,0,1,0,1);consume_commit();'
        assert display_tb.count(first) == 1
        display_tb = display_tb.replace(first, '''submit(0,1,10,0,1,0,1);
  wait(dut.r_cmd_valid&&dut.r_cmd_ready);@(negedge core_clk);
  wr('h100,32'hdeadbeef,0);wr('h20,1,2);
  consume_commit();''')
        display_path = work / 'tb_display.sv'; display_path.write_text(display_tb, encoding='utf-8')
        display_sources = display_manifest['sources'] + [n for n in display_manifest['tests']
                           if not n.endswith('tb_video_display_record.sv')] + COMPACT
        for label, case, half in [('display', 0, 12.5), ('display_ratio', 0, 17), ('display_asset_wait', 1, 12.5)]:
            directory = work / label; fixtures(directory, 80, 64)
            binary = directory / 'sim.vvp'
            print('VIDEO_COMPACT_CASE', label, flush=True)
            run([iv, '-g2012', '-Wall', '-I', ROOT / 'rtl/video/include', '-s', 'tb_video_display_record',
                 f'-Ptb_video_display_record.CASE_ID={case}', f'-Ptb_video_display_record.PIXEL_HALF={half}', '-o', binary]
                + [ROOT / n for n in display_sources] + [display_path], work / (label + '_compile.log'))
            log = run([vvp, binary, '+DIR=' + directory.as_posix()], work / (label + '.log'), timeout=600)
            if 'VIDEO_DISPLAY_RECORD_PASS' not in log:
                raise RuntimeError('missing integrated display pass ' + label)
            result['cases'][label] = log
        result['cases']['display_source_violation'] = display_source_negative(
            work, display_tb, display_sources, iv, vvp)
        if args.map:
            map_engine(work, result)
        if result['inputs'] != input_hashes(ROOT / n for n in names):
            raise RuntimeError('functional inputs changed')
        result['status'] = 'PASS'
    except Exception as error:
        result.update(status='FAIL', error=str(error)); print(str(error), file=sys.stderr)
    write_json(work / 'result.json', result)
    print('VIDEO_COMPACT_' + result['status'], work, flush=True)
    return 0 if result['status'] == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
