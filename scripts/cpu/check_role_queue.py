"""Actual decode role capture plus the existing151bit/four-state queue oracle."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from check_role_predecode import function, ROOT, SIM


def main():
    p = argparse.ArgumentParser()
    p.add_argument('parent', type=Path)
    p.add_argument('candidate', type=Path)
    p.add_argument('output', type=Path)
    args = p.parse_args()
    out = args.output.resolve()
    assert out.is_relative_to(ROOT/'build/cpu')
    out.mkdir(parents=True, exist_ok=False)
    files = [args.parent/'triha_issue.v', args.candidate/'triha_decode.v',
             ROOT/'rtl/cpu/vendor/src/core/biriscv_decoder.v',
             ROOT/'rtl/cpu/vendor/src/core/biriscv_defs.v',
             ROOT/'tb/cpu/tb_decode_alu_control.v', ROOT/'tb/cpu/tb_role_queue.v',
             Path(__file__).resolve(), ROOT/'scripts/cpu/check_role_predecode.py', args.parent/'triha_decode.v']
    sha = lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    row = dict(status='RUNNING', input_hashes={str(p.resolve()):sha(p) for p in files}, commands=[])
    try:
        old = function(files[0].read_text(encoding='utf-8'), 'register_roles')
        (out/'role_parent.v').write_text('module role_parent(input [31:0] opcode_i,input invalid_i,input [1:0] fault_i,input [2:0] raw_i,output [2:0] roles_o);\n'+old+'\nassign roles_o=register_roles(opcode_i,invalid_i,fault_i);\nendmodule\n', encoding='utf-8', newline='\n')
        # Reuse the existing stimulus but bind its reference to the actual v78
        # parent. Its embedded v26 shift-FIFO is not an invalid-history oracle
        # for the later ring FIFO.
        reference = files[8].read_text(encoding='utf-8')
        for name in ['triha_decode', 'triha_fetch_fifo', 'triha_exec_classify', 'triha_alu_predecode']:
            reference = reference.replace(name, name+'_roles_reference')
        harness = files[4].read_text(encoding='utf-8').split('\nendmodule', 1)[0]+'\nendmodule\n'
        harness = harness.replace('triha_decode_queued_reference', 'triha_decode_roles_reference')
        harness = '\n'.join(line for line in harness.split('\n') if 'triha_alu_predecode u_expected' not in line)
        harness = harness.replace('.fetch_in_accept_o(ref_out[150]),', '.fetch_in_accept_o(ref_out[150]),\n        .fetch_out0_alu_decode_o(expected_control0),.fetch_out1_alu_decode_o(expected_control1),')
        (out/'queue_harness.v').write_text(harness+'\n'+reference, encoding='utf-8', newline='\n')
        calls = [('vlib', 'vlib.exe', ['work'], None),
                 ('compile', 'vlog.exe', ['+incdir+'+str(files[3].parent.resolve()), 'role_parent.v', 'queue_harness.v', *map(lambda p:str(p.resolve()), [files[1],files[2],files[5]])], None)]
        for extra,mul in [(0,1),(0,0),(1,1),(1,0)]:
            calls.append((f'queue-{extra}-{mul}', 'vsim.exe', ['-c','-voptargs=+acc','tb_role_queue', f'-gEXTRA={extra}',f'-gMULDIV={mul}','-do','run -all; quit -f'], False))
        calls.append(('negative', 'vsim.exe', ['-c','-voptargs=+acc','tb_role_queue','-gBROKEN=1','-do','run -all; quit -f'], True))
        for label,tool,arguments,fail in calls:
            cmd=[str(SIM/tool),*arguments]
            r=subprocess.run(cmd,cwd=out,capture_output=True,timeout=120)
            log=r.stdout+r.stderr;(out/(label+'.log')).write_bytes(log)
            row['commands'].append(dict(command=cmd,return_code=r.returncode))
            assert r.returncode==0, label+' tool error'
            if fail is not None:
                assert (b'ROLE_QUEUE_FAIL' in log)==fail, label
                if not fail:assert b'ROLE_QUEUE_PASS' in log and b'ALU_META_ALIGNMENT_PASS' in log,label
        assert all(sha(Path(n))==h for n,h in row['input_hashes'].items())
        row['status']='PASS'
    except Exception as error:
        row.update(status='FAIL',error=str(error));raise
    finally:
        row['output_hashes']={p.name:sha(p) for p in out.iterdir() if p.is_file()}
        (out/'result.json').write_text(json.dumps(row,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('ROLE_QUEUE_CHECK_PASS',out)


if __name__=='__main__':main()
