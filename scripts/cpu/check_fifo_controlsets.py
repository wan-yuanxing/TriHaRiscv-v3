"""Check the actual ADS FIFO CE groups for a local mapping experiment."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re


def inspect(report, minimum, netlist=None):
    text = report.read_text(encoding='utf-8')
    header = re.search(r'Number of unique control sets\s*:\s*(\d+)', text)
    if not header:
        raise ValueError('Not an ADS control-set report')
    if len(re.findall(r'(?m)^  CLK\(', text)) != int(header[1]):
        raise ValueError('Control-set summary is incomplete')
    for kind in ('CE', 'CLK', 'CP', 'RS'):
        if not re.search(r'Number of DFF:' + kind + r' Signals\s*:\s*\d+', text):
            raise ValueError('Control-signal section missing: ' + kind)
    if netlist is None or netlist.resolve().parent != report.resolve().parent:
        raise ValueError('Need the mapped Verilog netlist beside this report')
    modules = re.findall(r'(?ms)^module triha_fetch_fifo\b.*?^endmodule',
                         netlist.read_text(encoding='utf-8'))
    if len(modules) != 1:
        raise ValueError('Actual FIFO module missing or ambiguous in mapped netlist')
    flops = Counter(re.findall(r'(?m)^\s+(GTP_DFF\w*)\b', modules[0]))
    if not flops:
        raise ValueError('Actual FIFO has no mapped FF evidence')
    groups = [dict(signal=m[1], registers=int(m[2])) for m in re.finditer(
        r'(?m)^\s*CLK\([^\r\n]*?CE\(([^\r\n]*?u_fifo[./][^\r\n]*?)\)\s*:\s*(\d+)\s*$', text)]
    enabled = sum(count for primitive, count in flops.items() if primitive.endswith('E'))
    if bool(groups) != bool(enabled):
        raise ValueError('FIFO CE report disagrees with actual mapped FF primitives')
    rejected = [g for g in groups if g['registers'] < minimum]
    return dict(status='FAIL' if rejected else 'PASS',
                report=str(report), report_sha256=hashlib.sha256(report.read_bytes()).hexdigest(),
                minimum=minimum, fifo_ce_groups=groups, small_fifo_ce_groups=rejected,
                netlist=str(netlist), netlist_sha256=hashlib.sha256(netlist.read_bytes()).hexdigest(),
                fifo_ff_primitives=dict(flops), fifo_ff_total=sum(flops.values()),
                scope='ADS mapping check only; no timing or functional acceptance')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('report', type=Path)
    parser.add_argument('--minimum', type=int, default=192)
    parser.add_argument('--netlist', type=Path, required=True)
    args = parser.parse_args()
    if args.minimum <= 0:
        parser.error('minimum must be positive')
    row = inspect(args.report, args.minimum, args.netlist)
    print(json.dumps(row, indent=2))
    raise SystemExit(0 if row['status'] == 'PASS' else 1)
