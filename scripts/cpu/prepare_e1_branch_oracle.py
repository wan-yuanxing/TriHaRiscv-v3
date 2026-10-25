"""Bind the independent clocked oracle to the unchanged measured parent."""
import argparse
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]


def prepare(parent,output):
    output=output.resolve()
    if output.exists() or not output.is_relative_to((ROOT/'build/cpu').resolve()):
        raise ValueError('Use a new file below build/cpu')
    source=parent.read_text(encoding='utf-8')
    marker='module triha_branch_exec'
    if source.count(marker)!=1:
        raise ValueError('Expected one complete parent branch module')
    source=source[source.index(marker):].replace(marker,'module triha_branch_parent',1)
    bench=(ROOT/'tb/cpu/tb_e1_branch_resolve.v').read_text(encoding='utf-8')
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_bytes(('`include "biriscv_defs.v"\n'+bench+'\n'+source).encode('utf-8'))
    return output


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--parent',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    print(prepare(args.parent,args.output))
