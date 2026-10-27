"""Replay full BTB outputs and block write enables against the frozen parent against an isolated CPU candidate."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SIM = Path('D:/modeltech64_2020.4/win64')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('parent', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--old', action='store_true')
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    candidate = args.candidate.resolve()
    source = ROOT
    out = args.output.resolve()
    if not out.is_relative_to(ROOT / 'build/cpu'):
        raise ValueError('Output must be under build/cpu')
    out.mkdir(parents=True, exist_ok=False)
    row = {'status': 'RUNNING', 'commands': [], 'input_hashes': {}}
    receipt = out / 'result.json'

    def save():
        receipt.write_text(json.dumps(row, indent=2) + '\n', encoding='utf-8')

    def run(name, tool, arguments, expected=None, rejected=None):
        command = [str(SIM / tool)] + arguments
        result = subprocess.run(command, cwd=out, capture_output=True, timeout=120)
        log = result.stdout + result.stderr
        (out / (name + '.log')).write_bytes(log)
        row['commands'].append({'command': command, 'return_code': result.returncode,
                                'log': name + '.log'})
        if result.returncode or (expected and expected.encode() not in log) or (rejected and rejected.encode() in log):
            raise RuntimeError(name + ' failed; inspect log')

    try:
        cfg = json.loads((source / 'fpga/pg2l100h/project/cpu_core.json').read_text())
        primitives = json.loads((source / 'config/cpu_primitives.json').read_text())
        files = [(candidate / Path(n).name) if n.startswith('rtl/cpu/') and (candidate / Path(n).name).is_file() else source / n for n in cfg['sources']]
        for item in primitives['simulation_models']:
            path = Path(item['path'])
            if hashlib.sha256(path.read_bytes()).hexdigest() != item['sha256']:
                raise ValueError('Primitive drift')
            files.append(path)
        tests = [ROOT / ('tb/cpu/' + n + '.v') for n in
                 ['tb_btb_local_write', 'tb_indexed_btb']]
        parent_path=args.parent.resolve()/'triha_btb.v'
        parent_text=parent_path.read_text(encoding='utf-8').replace('triha_btb_bank','triha_btb_bank_parent').replace('module triha_btb (','module triha_btb_parent (')
        parent_file=out/'parent.v';parent_file.write_text(parent_text,encoding='utf-8')
        for path in files + tests + [parent_path,Path(__file__).resolve()]:
            row['input_hashes'][str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
        run('vlib', 'vlib.exe', ['work'])
        run('compile', 'vlog.exe', ['+incdir+' + (source / 'rtl/cpu/vendor/src/core').as_posix()] + [str(p) for p in files + tests + [parent_file]])
        if not args.old:
            for name, marker in [('tb_btb_local_write','BTB_LOCAL'),('tb_indexed_btb','INDEXED_BTB')]:
                run(name,'vsim.exe',['-c',name,'-do','run -all; quit -f'],marker+'_PASS',marker+'_FAIL')
        for label,flag,negative in [('structural','POISON_SHARED',args.old),('negative','FAULT_WE',True)]:
            command=[str(SIM/'vsim.exe'),'-c','tb_btb_local_write','+'+flag,'-do','run -all; quit -f']
            result=subprocess.run(command,cwd=out,capture_output=True,timeout=120)
            log=result.stdout+result.stderr;(out/(label+'.log')).write_bytes(log)
            row['commands'].append({'command':command,'return_code':result.returncode})
            expected=b'BTB_LOCAL_FAIL' if negative else b'BTB_LOCAL_PASS'
            rejected=b'BTB_LOCAL_PASS' if negative else b'BTB_LOCAL_FAIL'
            if expected not in log or rejected in log or (not negative and result.returncode):raise RuntimeError(label+' marker mismatch')
        for path, value in row['input_hashes'].items():
            if hashlib.sha256(Path(path).read_bytes()).hexdigest() != value:
                raise ValueError('Input changed during run')
        row['status'] = 'PASS'
    except Exception as exc:
        row.update(status='FAIL', error=str(exc))
        raise
    finally:
        row['output_hashes'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in out.glob('*.log')}
        save()
    print('BTB_LOCAL_CHECK_PASS', receipt)


if __name__ == '__main__':
    main()
