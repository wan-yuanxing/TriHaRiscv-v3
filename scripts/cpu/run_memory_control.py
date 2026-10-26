"""Isolated memory candidate/parent comparison using native ModelSim."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import time
from run_cache import ROOT, SIM, sha, save


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--rom-structure', action='store_true')
    parser.add_argument('--selector-structure', action='store_true')
    parser.add_argument('--fault-read', action='store_true')
    args = parser.parse_args()
    work = ROOT / 'build/cpu' / ('memory-control-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    work.mkdir(parents=True)
    row = dict(status='RUNNING', scope='RTL memory component only', input_hashes={}, input_origins={},
               external_hashes={}, output_hashes={}, commands=[], source_unchanged=False)
    save(work / 'result.json', row)
    print('MEMORY_CONTROL_RUN', work, flush=True)
    started = time.monotonic()

    def native(tool, arguments, label):
        exe = SIM / (tool + '.exe')
        row['external_hashes'][str(exe)] = sha(exe)
        command = [str(exe), *map(str, arguments)]
        process = subprocess.Popen(command, cwd=work, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        timed_out = False
        try:
            output, _ = process.communicate(timeout=120)
        except subprocess.TimeoutExpired:
            timed_out = True
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
            output, _ = process.communicate()
        (work / (label + '.log')).write_bytes(output)
        row['commands'].append(dict(command=command, return_code=process.returncode, timed_out=timed_out))
        if timed_out or process.returncode:
            raise ValueError(label + ' failed')
        return output.decode('utf-8', errors='replace')

    try:
        origins = {n: ROOT / n for n in ['rtl/soc/triha_sram.v', 'rtl/soc/triha_boot_rom.v',
            'rtl/soc/triha_uart_tx.v', 'rtl/soc/triha_soc_memory.v', 'rtl/soc/include/soc_map.vh',
            'tb/soc/tb_soc_memory.v', 'scripts/cpu/run_modelsim.do', 'scripts/cpu/run_memory_control.py']}
        origins['candidate.v'] = args.source.resolve()
        for n, p in origins.items():
            row['input_hashes'][n] = sha(p)
            row['input_origins'][n] = str(p)
            dst = work / 'src' / n
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(p.read_bytes())
        parent = (work / 'src/rtl/soc/triha_soc_memory.v').read_text()
        assert parent.count('module triha_soc_memory #(') == 1
        (work / 'parent.v').write_text(parent.replace('module triha_soc_memory #(', 'module triha_soc_memory_parent #('), encoding='utf-8')
        (work / 'rom.hex').write_text('00028067000102b7\n' + '0010007300100073\n' * 1023, encoding='ascii')
        (work / 'sram.hex').write_text('a5a5a5a5a5a5a5a5\n' * 4096, encoding='ascii')
        native('vsim', ['-version'], 'version')
        native('vmap', ['-c'], 'vmap')
        native('vlib', ['work'], 'vlib')
        sources = [work / 'src/rtl/soc' / n for n in ['triha_sram.v', 'triha_boot_rom.v', 'triha_uart_tx.v']]
        native('vlog', ['+define+COMPARE_MEMORY_PARENT', '+incdir+' + (work / 'src/rtl/soc/include').as_posix(),
            *sources, work / 'parent.v', work / 'src/candidate.v', work / 'src/tb/soc/tb_soc_memory.v'], 'compile')
        output = native('vsim', ['-c', '-onfinish', 'exit', '-voptargs=+acc',
            '-gCHECK_ROM_STRUCTURE=' + str(int(args.rom_structure)),
            '-gCHECK_SELECTOR_STRUCTURE=' + str(int(args.selector_structure)), 'work.tb_soc_memory',
            *(['+FAULT_READ=1'] if args.fault_read else []), '-do', work / 'src/scripts/cpu/run_modelsim.do'], 'simulation')
        if 'SOC_MEMORY_PASS' not in output or any(s in output for s in ['SOC_MEMORY_FAIL', '** Error', '** Fatal']):
            raise ValueError('Memory self-check failed')
        row['status'] = 'PASS'
    except Exception as error:
        row['status'] = 'FAIL'
        row['error'] = str(error)
    finally:
        row['source_unchanged'] = all(sha(row['input_origins'][n]) == d for n, d in row['input_hashes'].items())
        row['external_unchanged'] = all(sha(n) == d for n, d in row['external_hashes'].items())
        if not row['source_unchanged'] or not row['external_unchanged']:
            row['status'] = 'FAIL'
        row['output_hashes'] = {p.relative_to(work).as_posix(): sha(p) for p in work.rglob('*') if p.is_file() and p != work / 'result.json'}
        row['elapsed_seconds'] = time.monotonic() - started
        row['runner_return_code'] = 0 if row['status'] == 'PASS' else 1
        save(work / 'result.json', row)
    print('MEMORY_CONTROL', row['status'], work / 'result.json')
    return row['runner_return_code']


if __name__ == '__main__':
    sys.exit(main())
