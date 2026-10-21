"""Re-read pinned DDR, actual simulation, native mapping and all frozen bindings."""
import argparse
import json
from pathlib import Path
import re

from run_cache import ROOT, sha, save
from review_cache_soc import verify_run, hierarchy


def verify_binding(row, spec):
    if not row.get('pinned_unchanged'):
        raise ValueError('pinned stability not established')
    actual = row['binding']
    if actual['revision'] != spec['revision']:
        raise ValueError('pinned revision mismatch')
    if set(actual['files']) != set(spec['files']):
        raise ValueError('pinned dependency set mismatch')
    for name, digest in spec['files'].items():
        file = actual['files'][name]
        if file['sha256'] != digest or sha(file['path']) != digest:
            raise ValueError('pinned content drift: '+name)


def review(args):
    spec = json.loads((ROOT/'config/cpu_ddr.json').read_text(encoding='utf-8'))
    bound, cdc, systems, negatives = {}, [], [], []
    def load(directory, negative=False):
        directory = Path(directory).resolve()
        row = verify_run(directory, negative=negative)
        verify_binding(row, spec)
        bound[str(directory/'result.json')] = sha(directory/'result.json')
        return row
    for directory in args.cdc:
        row = load(directory)
        text = (directory/'simulation.log').read_text(encoding='utf-8')
        match = re.search(r'CPU_AXI_CDC_PASS channels=5 messages_per_channel_epoch=256 epochs_completed=2 live_reset=1 cpu_half=(\d+) ddr_half=(\d+)', text)
        if row['test'] != 'cdc' or row['fault'] != 'none' or not match:
            raise ValueError('missing full five-channel CDC coverage')
        cdc.append(dict(directory=str(directory), cpu_half_ns=int(match[1]), ddr_half_ns=int(match[2])))
    if {(r['cpu_half_ns'], r['ddr_half_ns']) for r in cdc} != {(5,4), (3,6), (7,4)}:
        raise ValueError('CDC clock-ratio coverage incomplete')
    for directory, enable in [(args.system, True), (args.bypass_system, False)]:
        row = load(directory)
        text = (directory/'simulation.log').read_text(encoding='utf-8')
        match = re.search(r'CPU_DDR_SYSTEM_PASS cycles=(\d+) checks=(\d+) native_reads=(\d+) native_writes=22 traps=3 cache=([01]) live_reset=1', text)
        if row['test'] != 'system' or row['fault'] != 'none' or row['cache_enable'] != enable or not match or int(match[4]) != enable:
            raise ValueError('actual CPU/DDR test mode or coverage mismatch')
        systems.append(dict(directory=str(directory), cache_enable=enable, cycles=int(match[1]),
            checks=int(match[2]), native_read_beats=int(match[3]), native_write_beats=22,
            scope='directed RTL software with forced recoverable AXI read error and native init-loss; not CoreMark or physical DDR'))
    for name in ['rom.hex', 'sram.hex', 'firmware.elf']:
        if (args.system/name).read_bytes() != (args.bypass_system/name).read_bytes():
            raise ValueError('system cache modes used different firmware')
    for directory in args.negative:
        row = load(directory, True)
        text = (directory/'simulation.log').read_text(encoding='utf-8')
        reason = ('watchdog' if row['fault'] == 'watchdog' else
            'payload/order channel=5' if row['test'] == 'cdc' else 'real firmware success exit')
        if row['fault'] not in ['data', 'watchdog'] or reason not in text:
            raise ValueError('wrong negative failure reason')
        negatives.append(dict(directory=str(directory), test=row['test'], fault=row['fault'], actual_failure=reason))
    if {(r['test'],r['fault']) for r in negatives} != {('cdc','data'),('cdc','watchdog'),('system','data'),('system','watchdog')}:
        raise ValueError('negative coverage incomplete')
    area = load(args.area)
    text = (args.area/'synthesize/triha_cpu_ddr_map_top.snr').read_text(encoding='utf-8')
    rows = {name:hierarchy(text, name) for name in ['u_system','u_soc','u_core','u_cache','u_memory','u_cdc','u_bridge']}
    if rows != area['hierarchy_resources'] or area['stage'] != 'map' or area['timing_closed']:
        raise ValueError('native area scope/summary mismatch')
    log = (args.area/'pds.stdout.log').read_text(encoding='utf-8')
    for stage in ['compile','synthesize','dev_map']:
        if not re.search(r'(?m)^Executing : '+stage+r'(?: [^\r\n]*)? successfully\.\s*$', log):
            raise ValueError('native stage did not finish: '+stage)
    compile_text = (args.area/'compile/run.log').read_text(encoding='utf-8')
    def parameters(scope, expected):
        blocks = re.findall(r'(?ms)^I: Module instance \{triha_cpu_ddr_map_top/'+re.escape(scope)+r'\} parameter value:\r?\n(.*?)(?=^I:|\Z)', compile_text)
        if len(blocks) != 1:
            raise ValueError('missing/duplicate actual elaboration: '+scope)
        for key, value in expected.items():
            fields = re.findall(r'(?m)^\s*'+key+r" = (?:1|32)'b([01]+)\s*$", blocks[0])
            if len(fields) != 1 or int(fields[0], 2) != value:
                raise ValueError('actual elaboration mismatch: '+scope+'/'+key)
    parameters('u_system/u_soc', {'CACHE_ENABLE':1})
    parameters('u_system/u_soc/u_core', {'DUAL_ISSUE':0})
    parameters('u_system/u_soc/u_core/u_cpu', {'SUPPORT_DUAL_ISSUE':0,'NUM_BTB_ENTRIES':512,'NUM_BHT_ENTRIES':512,'NUM_RAS_ENTRIES':4,'GSHARE_ENABLE':0})
    for channel, width in [('aw',49),('w',145),('b',6),('ar',49),('r',135)]:
        parameters('u_system/u_cdc/u_'+channel+'_fifo', {'DATA_WIDTH':width,'ADDR_WIDTH':2})
    if rows['u_cdc']['drm'] <= 0:
        raise ValueError('CDC did not map to native synchronous RAM')
    return dict(status='PASS', bound_results=bound, pinned_revision=spec['revision'], cdc_runs=cdc,
        system_runs=systems, negatives=negatives, hierarchy_resources=rows,
        actual_postroute_100mhz_verified=False, physical_ddr_validated=False,
        shared_fabric_validated=False, programmed=False, reviewer_sha256=sha(Path(__file__)),
        scope='Digital CPU/CDC/pinned-bridge functional and native area checkpoint; not deployment')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--cdc', action='append', required=True, type=Path)
    parser.add_argument('--system', required=True, type=Path)
    parser.add_argument('--bypass-system', required=True, type=Path)
    parser.add_argument('--negative', action='append', required=True, type=Path)
    parser.add_argument('--area', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    save(args.output, review(args))
    print('CPU_DDR_REVIEW_PASS', args.output)
