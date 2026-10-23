"""Independently bind same-loaded-program Cache on/off RTL measurements."""
import argparse
import hashlib
from itertools import zip_longest
import json
from pathlib import Path
import re
import struct


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def verify_outputs(directory):
    row = load(directory/'result.json')
    if row['status'] != 'PASS' or not row['source_unchanged'] or not row['external_unchanged']:
        raise ValueError('need successful unchanged native evidence')
    for name,digest in row['output_hashes'].items():
        if sha(directory/name) != digest:
            raise ValueError('frozen output drift: '+name)
    for name,digest in row['input_hashes'].items():
        if sha(directory/'src'/name) != digest:
            raise ValueError('frozen input drift: '+name)
    return row


def elf_sections(path):
    data = path.read_bytes()
    offset = struct.unpack_from('<I',data,32)[0]
    size,count,strings = struct.unpack_from('<HHH',data,46)
    rows = [struct.unpack_from('<10I',data,offset+i*size) for i in range(count)]
    names = data[rows[strings][4]:rows[strings][4]+rows[strings][5]]
    return {names[row[0]:].split(b'\0',1)[0].decode('ascii'):
            dict(flags=row[2],data=data[row[4]:row[4]+row[5]],link=row[6],entry_size=row[9])
            for row in rows}, rows


def started_symbol(path):
    sections,rows = elf_sections(path)
    symtab = sections['.symtab']
    names = sections['.strtab']['data']
    found = []
    for at in range(0,len(symtab['data']),16):
        name,value,size,info,other,index = struct.unpack_from('<IIIBBH',symtab['data'],at)
        if names[name:].split(b'\0',1)[0] == b'started':
            found.append(value)
    if len(found) != 1:
        raise ValueError('ambiguous CoreMark started symbol')
    return found[0]


def compare_traces(cached,uncached,trace_names=('cpu-cache.wb.log','cpu-cache.store.log')):
    output = {}
    initial_values = None
    start_addr = started_symbol(cached/'firmware.elf')
    if start_addr != started_symbol(uncached/'firmware.elf'):
        raise ValueError('timing storage address changed')
    for name in trace_names:
        digest = hashlib.sha256()
        with (cached/name).open('rb') as a,(uncached/name).open('rb') as b:
            for count,(x,y) in enumerate(zip_longest(a,b),1):
                if x is None or y is None:
                    raise ValueError('trace length mismatch')
                p,q = x.split(),y.split()
                if name.endswith('wb.log') and (p[-1] != b'00' or q[-1] != b'00'):
                    raise ValueError('exception in timed benchmark observation')
                if count == 1 and name.endswith('wb.log'):
                    if p[:3] != q[:3] or (int(p[1],16)&0xfffff07f) != 0xc0002073:
                        raise ValueError('first observation is not the expected cycle CSR read')
                    initial_values = (p[3],q[3])
                elif count == 1:
                    if p[:2] != q[:2] or int(p[0],16) != start_addr or p[1] != b'f' or (p[2],q[2]) != initial_values:
                        raise ValueError('first store is not the matching absolute start timestamp')
                else:
                    if x != y:
                        raise ValueError(f'timed observation mismatch: {name}:{count}')
                    digest.update(x)
        output[name] = dict(events=count, identical_except_initial_absolute_cycle=True,
                            normalized_tail_sha256=digest.hexdigest(), cached_sha256=sha(cached/name),
                            uncached_sha256=sha(uncached/name))
    return output


def area(directory,expected_enabled,simulation):
    row = verify_outputs(directory)
    if row.get('stage') != 'map' or row.get('target') != 'cpu-cache':
        raise ValueError('need CPU+Cache native mapping scope')
    for name,digest in simulation['input_hashes'].items():
        if name.startswith('rtl/') and name.endswith('.v') and name in row['input_hashes']:
            if row['input_hashes'][name] != digest:
                raise ValueError('mapped RTL differs from benchmark: '+name)
    log = (directory/'compile/run.log').read_text(encoding='utf-8')
    scope = 'triha_cached_core_map_top/u_subsystem'
    blocks = re.findall(r'(?ms)^I: Module instance \{'+re.escape(scope)+r'\} parameter value:\r?\n(.*?)(?=^I:|\Z)',log)
    if len(blocks) != 1:
        raise ValueError('missing actual mapped CPU/Cache parameter scope')
    values = re.findall(r"(?m)^\s*CACHE_ENABLE = (?:1|32)'b([01]+)\s*$",blocks[0])
    if len(values) != 1 or int(values[0],2) != expected_enabled:
        raise ValueError('wrong actual mapped Cache enable')
    report = (directory/'synthesize/triha_cached_core_map_top.snr').read_text(encoding='utf-8')
    def hierarchy(name):
        rows = re.findall(r'(?m)^\|[ +]*'+re.escape(name)+r'\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+(\d+)\s+\|\s+([\d.]+)',report)
        if len(rows) != 1:
            raise ValueError('missing/duplicate resource hierarchy: '+name)
        lut,ff,ram,apm,drm = rows[0]
        return dict(lut=int(lut),ff=int(ff),distributed_ram_luts_included=int(ram),apm=int(apm),drm36k_equivalent=float(drm))
    resources = hierarchy('u_subsystem')
    if resources['lut'] != row['resources']['lut']:
        raise ValueError('native area summary/report mismatch')
    return dict(directory=str(directory),result_sha256=sha(directory/'result.json'),
                resources=resources,core=hierarchy('u_core'),cache_and_transport=hierarchy('u_cache'),
                fixture_excluded=True,timing_closed=False)


def compare(cached,uncached,cached_area=None,uncached_area=None):
    cached,uncached = Path(cached).resolve(),Path(uncached).resolve()
    a,b = verify_outputs(cached),verify_outputs(uncached)
    if a.get('cache_enable') is not True or b.get('cache_enable') is not False:
        raise ValueError('need distinct actual Cache-on/off measurements')
    if a['memory_model'] != b['memory_model'] or a['iterations'] != b['iterations']:
        raise ValueError('memory model or iteration mismatch')
    for row in [a,b]:
        if '-O2' not in row['compiler_flags'] or any('flto' in flag or flag == '-O3' for flag in row['compiler_flags']):
            raise ValueError('benchmark optimization contract mismatch')
    if sha(cached/'firmware.hex') != sha(uncached/'firmware.hex'):
        raise ValueError('different loaded programs')
    sa,_ = elf_sections(cached/'firmware.elf')
    sb,_ = elf_sections(uncached/'firmware.elf')
    differences = [name for name in sa if sa[name] != sb[name]]
    if set(sa) != set(sb) or any(name != '.strtab' or sa[name]['flags'] != 0 for name in differences):
        raise ValueError('ELF differences exceed non-loaded source-path string table')
    ca,cb = a['measurement']['cycles'],b['measurement']['cycles']
    output = dict(status='PASS',scope='Same-loaded-program five-iteration RTL comparison; modeled AXI DDR, not board or official score',
        cached_directory=str(cached),uncached_directory=str(uncached),
        cached_result_sha256=sha(cached/'result.json'),uncached_result_sha256=sha(uncached/'result.json'),
        loaded_image_sha256=sha(cached/'firmware.hex'),elf_raw_equal=sha(cached/'firmware.elf')==sha(uncached/'firmware.elf'),
        differing_nonloaded_sections=differences,trace_comparison=compare_traces(cached,uncached),
        cached=a['measurement'],uncached=b['measurement'],memory_model=a['memory_model'],iterations=a['iterations'],
        cycles_reduced_percent=(1-ca/cb)*100,throughput_gain_percent=(cb/ca-1)*100,
        actual_postroute_100mhz=False,board_score_validated=False,programmed=False)
    if cached_area:
        output['cached_area'] = area(Path(cached_area).resolve(),1,a)
        output['cached_coremark_per_lut_nominal100mhz'] = a['measurement']['coremark_per_mhz']*100/output['cached_area']['resources']['lut']
    if uncached_area:
        output['uncached_area'] = area(Path(uncached_area).resolve(),0,b)
        output['uncached_coremark_per_lut_nominal100mhz'] = b['measurement']['coremark_per_mhz']*100/output['uncached_area']['resources']['lut']
    return output


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('cached')
    parser.add_argument('uncached')
    parser.add_argument('--cached-area')
    parser.add_argument('--uncached-area')
    parser.add_argument('--output',required=True)
    args = parser.parse_args()
    output = Path(args.output).resolve()
    if output.is_relative_to(Path(args.cached).resolve()) or output.is_relative_to(Path(args.uncached).resolve()):
        raise ValueError('comparison output must not overwrite native run evidence')
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(dict(status='RUNNING',cached=args.cached,uncached=args.uncached))+'\n',encoding='utf-8',newline='\n')
    try:
        result = compare(args.cached,args.uncached,args.cached_area,args.uncached_area)
        result['runner_return_code'] = 0
    except Exception as error:
        result = dict(status='FAIL',error=str(error),runner_return_code=1)
    output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    print('CPU_CACHE_COMPARISON_'+result['status'],result.get('throughput_gain_percent',result.get('error')))
    raise SystemExit(result['runner_return_code'])
