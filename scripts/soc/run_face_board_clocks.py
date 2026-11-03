"""Real generated GPLL + board connectivity/reset regression and mutations."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'video'))
from common import ROOT, tool, sha256, write_json
from gen_compute_pll import generate


def run(output):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    write_json(output/'result.json', {'status': 'RUNNING'})
    inputs = {}
    def snapshot(path, name=None):
        path = Path(path)
        inputs[str(path)] = sha256(path)
        dest = output/(name or path.name)
        dest.write_bytes(path.read_bytes())
        return dest
    try:
        _, pll = generate(output/'pll')
        board = snapshot(ROOT/'fpga/pg2l100h/rtl/triha_face_board_top.sv')
        bench = snapshot(ROOT/'tb/soc/tb_face_board_clocks.sv')
        face = snapshot(ROOT/'rtl/soc/triha_face_system.v', 'face_source.v')
        snapshot(ROOT/'rtl/soc/include/avatar_preset.vh')
        face_stub = output/'face_interface.v'
        face_stub.write_text(face.read_text().split('    wire capture_irq;')[0]+'endmodule\n')
        sources = [bench, face_stub, pll]
        for name in ['rtl/video/video_capture_ingress.sv', 'rtl/video/video_async_fifo.sv',
                     'rtl/video/video_stream_register.sv','rtl/soc/triha_uart_rx.v',
                     'rtl/soc/triha_uart_tx.v', 'tb/video/models/ddr_board_ip_model.sv']:
            sources.append(snapshot(ROOT/name))
        model = tool('pds_shell').parent.parent/'arch/vendor/pango/verilog/simulation/GTP_GPLL.v'
        sources.append(snapshot(model))
        original = board.read_text()
        cases = {'positive': original,
                 'negative_compute_125': original.replace('.compute_clk_i(compute_clk)', '.compute_clk_i(ddr_clk)'),
                 'negative_uart_domain': original.replace('.clk_i(ddr_clk)', '.clk_i(compute_clk)'),
                 'negative_reset_split': original.replace('.rst_ni(application_reset_n)', '.rst_ni(controller_reset_n)')}
        results = {}
        for name,text in cases.items():
            dut = output/(name+'.sv');dut.write_text(text)
            exe = output/(name+'.vvp')
            command = [str(tool('iverilog')), '-g2012', '-i', '-I',str(output),'-s', 'tb_face_board_clocks',
                       '-o', str(exe), str(dut), *map(str,sources)]
            cp = subprocess.run(command,capture_output=True,text=True,timeout=60)
            (output/(name+'.compile.log')).write_text(cp.stdout+cp.stderr)
            if cp.returncode:
                raise ValueError('compile failed: '+cp.stdout+cp.stderr)
            cp = subprocess.run([str(tool('vvp')),str(exe)],capture_output=True,text=True,timeout=60)
            log = cp.stdout+cp.stderr
            (output/(name+'.simulation.log')).write_text(log)
            if name=='positive':
                ok = cp.returncode==0 and 'FACE_BOARD_CLOCK_PASS' in log and 'error:' not in log.lower()
            else:
                expected = {'negative_compute_125':'compute period must be 20 ns',
                            'negative_uart_domain':'video-side direct interface clock mismatch',
                            'negative_reset_split':'application reset not coordinated'}[name]
                ok = cp.returncode!=0 and expected in log
            if not ok:
                raise ValueError(name+': '+log)
            results[name] = {'returncode':cp.returncode,'verified':ok,'dut_sha256':sha256(dut)}
        for path,digest in inputs.items():
            if sha256(path)!=digest:raise ValueError('input changed: '+path)
        write_json(output/'result.json',dict(status='PASS', cases=results, inputs=inputs,
                   scope='Board clock ports, digital PLL periods, coordinated reset; unrelated HDMI/face datapaths blackboxed',
                   physical_timing_verified=False))
        print('FACE_BOARD_CLOCKS_PASS',output)
    except Exception as exc:
        write_json(output/'result.json',dict(status='FAIL',error=str(exc)))
        raise


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    run(parser.parse_args().output)
