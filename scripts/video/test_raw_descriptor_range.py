"""Actual RAW admission vs independent unbounded byte arithmetic, plus mutations."""
import argparse
import json
from pathlib import Path
import random
import subprocess
from common import ROOT, tool, sha256, write_json


def vectors(width, height):
    row = ((width*3+15)//16)*16
    last = max(0, height-1)
    maximum = ((0x08000000-row)//last) if last else 0xffffffff
    cases = []
    def add(base, stride, slot=0):
        base &= 0xffffffff
        stride &= 0xffffffff
        invalid = (base%16 != 0 or stride%16 != 0 or stride < width*3 or
                   base < 0x80000000 or base+stride*(height-1)+row > 0x88000000 or
                   not 1 <= width <= 800 or not 1 <= height <= 600 or slot > 2)
        cases.append((base << 67) | (stride << 35) | (17 << 3) | (slot << 1) | int(invalid))
    strides = [0, 1, row-16, row, row+16, 0x10000000, 0x40000000,
               0x80000000, 0xfffffff0, 0xffffffff]
    strides += [maximum+d for d in [-32, -16, -1, 0, 1, 16, 32]]
    for stride in strides:
        for base in [0, 0x7ffffff0, 0x80000000, 0x87fffff0, 0x88000000, 0xfffffff0]:
            for slot in [0, 2, 3]:
                add(base, stride, slot)
        end_base = 0x88000000 - ((stride & 0xffffffff)*last+row)
        for delta in [-16, -1, 0, 1, 16]:
            add(end_base+delta, stride)
    rng = random.Random(0xD35C + width*601+height)
    for _ in range(5000):
        stride = rng.choice([rng.getrandbits(32), rng.randrange(0, max(16, maximum+64))])
        base = rng.choice([rng.getrandbits(32), 0x80000000+rng.randrange(0x8000000)])
        add(base & ~15, stride & ~15)
        # Also exercise a dense set of accepted and exact-boundary descriptors.
        stride = max(row, min(stride & ~15, maximum & ~15))
        end_base = 0x88000000-stride*last-row
        if 0x80000000 <= end_base <= 0xffffffff:
            add(end_base+rng.choice([-16, 0, 16]), stride)
    return cases


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--rtl',type=Path,default=ROOT/'rtl/video/raw_display.sv')
    args=parser.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    source=args.rtl.read_text(encoding='utf-8');bench=ROOT/'tb/video/tb_raw_descriptor_range.sv'
    result=dict(status='RUNNING',inputs={str(p.resolve()):sha256(p) for p in [args.rtl,bench,Path(__file__)]},cases={})
    write_json(out/'result.json',result)
    frozen=out/'raw_display.sv';frozen.write_text(source,encoding='utf-8')
    tb=out/bench.name;tb.write_bytes(bench.read_bytes())
    def run(name,rtl,w,h,negative=False):
        work=out/name;work.mkdir()
        data=vectors(w,h);v=work/'vectors.hex'
        v.write_text(''.join(f'{x:025x}\n' for x in data),encoding='ascii')
        exe=work/'sim.vvp'
        cp=subprocess.run([str(tool('iverilog')),'-g2012','-s','tb_raw_descriptor_range','-o',str(exe),
            f'-Ptb_raw_descriptor_range.W={w}',f'-Ptb_raw_descriptor_range.H={h}',
            f'-Ptb_raw_descriptor_range.COUNT={len(data)}',str(rtl),str(tb)],capture_output=True,text=True,timeout=60)
        (work/'compile.log').write_text(cp.stdout+cp.stderr,encoding='utf-8')
        assert cp.returncode==0, cp.stderr
        cp=subprocess.run([str(tool('vvp')),str(exe),'+VECTORS='+v.as_posix()],capture_output=True,text=True,timeout=60)
        log=cp.stdout+cp.stderr;(work/'simulation.log').write_text(log,encoding='utf-8')
        ok=(cp.returncode!=0 and 'range mismatch' in log) if negative else (cp.returncode==0 and 'RAW_DESCRIPTOR_RANGE_PASS' in log)
        assert ok, name+': '+log
        result['cases'][name]=dict(vectors=len(data),expected_failure=negative,returncode=cp.returncode,verified=True)
    try:
        for w,h in [(800,600),(800,599),(800,1),(1,1),(1,600),(5,3),(17,2),(31,5),(801,600),(800,601),(0,1),(800,0)]:
            run(f'geometry_{w}_{h}',frozen,w,h)
        # Removing the minimum pitch must admit an invalid overlapping image.
        bad=source.replace('record_stride<ROW_BYTES',"1'b0")
        assert bad!=source
        mutant=out/'mutant_pitch.sv';mutant.write_text(bad,encoding='utf-8');run('negative_pitch',mutant,800,600,True)
        if 'wire [63:0] record_bus_end' in source:
            bad=source.replace('wire [63:0] record_bus_end','wire [31:0] record_bus_end')
            name='negative_truncated_extent'
        else:
            bad=source.replace('record_end_beat>WINDOW_BEATS','record_end_beat>=WINDOW_BEATS')
            name='negative_exclusive_upper_bound'
        assert bad!=source
        mutant=out/'mutant_extent.sv';mutant.write_text(bad,encoding='utf-8');run(name,mutant,800,600,True)
        if 'record_stride[31:4]>MAX_ROW_STRIDE_BEATS' in source:
            bad=source.replace('record_stride[31:4]>MAX_ROW_STRIDE_BEATS',"1'b0")
            mutant=out/'mutant_stride_bound.sv';mutant.write_text(bad,encoding='utf-8')
            run('negative_missing_stride_bound',mutant,800,600,True)
        assert all(sha256(p)==h for p,h in result['inputs'].items()),'input changed'
        result.update(status='PASS',board_verified=False,physical_timing_verified=False)
    except Exception as error:
        result.update(status='FAIL',error=str(error))
    write_json(out/'result.json',result)
    print(result['status'],result.get('error',''),out)
    return 0 if result['status']=='PASS' else 1


if __name__=='__main__':
    raise SystemExit(main())
