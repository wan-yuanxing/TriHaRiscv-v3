"""Create an isolated nominal-95MHz board boundary; retain exact v83 CPU."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'build/cpu/dual-board-v83-ledreg-20261101'
DEST=ROOT/'build/cpu/dual-board-v83-95mhz-20261101'
P=DEST/'project'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def change(name,old,new,count=None):
    p=P/name;t=p.read_text(encoding='utf-8')
    if count is not None:assert t.count(old)==count,(name,old,t.count(old))
    else:assert old in t,(name,old)
    p.write_text(t.replace(old,new),encoding='utf-8',newline='\n')

def write_json(name,data):
    (P/name).write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')

def clone():
    assert not DEST.exists()
    d=json.loads((SOURCE/'prepared-board.json').read_text(encoding='utf-8'))
    for n,h in d['project_files'].items():
        s=SOURCE/'project'/n;assert sha(s)==h,n
        target=P/n;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(s,target)
    shutil.copyfile(SOURCE/'prepared-board.json',DEST/'source-prepared-board.json')
    print('BOARD95_CLONE',P)

def adapt():
    cfg=json.loads((P/'config/cpu_board.json').read_text());cfg['cpu_hz']=95000000
    cfg['pll'].update(input_divider=5,multiplier=1,feedback_divider=38,output_divider=10)
    write_json('config/cpu_board.json',cfg)
    cfg=json.loads((P/'config/soc_map.json').read_text());cfg['clock_hz']=95000000;write_json('config/soc_map.json',cfg)
    change('scripts/soc/gen_board.py','100_000_000','95_000_000')
    change('scripts/soc/gen_board.py','100MHz','95MHz')
    change('scripts/soc/gen_board.py','-multiply_by 4 -divide_by 5','-multiply_by 19 -divide_by 25',1)
    change('scripts/soc/board_pll.py','100.00000000','95.00000000',1)
    change('scripts/soc/board_pll.py','100MHz','95MHz')
    change('tb/soc/cpu_board_pll_model.v','always #5 clkout0','always #(1000.0/190.0) clkout0',1)
    change('tb/soc/tb_cpu_board_clock.v','> 9.999','> 10.525',1)
    change('tb/soc/tb_cpu_board_clock.v','< 10.001','< 10.527',1)
    change('tb/soc/tb_cpu_board_clock.v','actual_period_ns=10','actual_period_ns=10.526315789',1)
    change('tb/soc/tb_cpu_board_clock.v','            check(($realtime - previous_edge',
        '            if (checks == 1) $display("BOARD95_CLOCK_OBS delta_ns=%0.9f", $realtime-previous_edge);\n            check(($realtime - previous_edge',1)
    change('scripts/soc/run_board.py','"1ps"','"1fs"',1)
    change('tb/cpu/tb_dual_board_coremark.v','repeat (1302)','repeat (1237)',1)
    change('tb/cpu/tb_dual_board_coremark.v','repeat (868)','repeat (825)',1)
    name='sw/benchmarks/coremark/port/core_portme.c'
    change(name,'100000000u','95000000u')
    change(name,'clock_hz=100000000','clock_hz=95000000')
    change(name,'(ticks % 95000000u) / 100u','(ticks % 95000000u) * 1000000u / 95000000u',1)
    change(name,'ticks < 1000000000u','ticks < 950000000u',1)
    change('scripts/soc/coremark_board.py','hz != 100000000','hz != 95000000',1)
    recipe=json.loads((P/'fpga/pg2l100h/project/cpu_board.json').read_text())
    recipe['period_ns']=1000/95
    recipe['physical_constraints']=['fpga/pg2l100h/constraints/cpu_board_mul_region.fdc']
    recipe['scope']='Nominal95MHz board measurement fallback, same v83 CPU, registered LEDs, original IO/hold budgets, multiplier X1/Y2'
    write_json('fpga/pg2l100h/project/cpu_board.json',recipe)
    shutil.copyfile(SOURCE/'project/fpga/pg2l100h/constraints/cpu_board_mul_region.fdc',P/recipe['physical_constraints'][0])
    change('scripts/soc/run_dual_board_route.ps1','$recipe.period_ns -ne 10','$recipe.period_ns -ne (1000.0/95.0)',1)
    change('scripts/soc/run_dual_board_route.ps1','Get-TrihaRouteTiming ([IO.File]::ReadAllText($report))','Get-TrihaRouteTiming ([IO.File]::ReadAllText($report)) (1000.0/95.0)',1)
    # Generated clocks can retain four decimals; preserve only the two exact
    # report precisions of the frozen 125MHz*19/25 clock, not arbitrary clocks.
    name='scripts/cpu/route_reports.ps1'
    change(name,"if([Math]::Abs($actualPeriod-$quantized) -gt 0.00005 -or [Math]::Abs($actualHalf-$actualPeriod/2) -gt 0.00005)",
        "if(([Math]::Abs($actualPeriod-$quantized) -gt 0.00005 -and [Math]::Abs($actualPeriod-[Math]::Round($RequestedPeriodNs,4)) -gt 0.00005) -or [Math]::Abs($actualHalf-[Math]::Round($RequestedPeriodNs/2,3,[MidpointRounding]::AwayFromZero)) -gt 0.00005)",1)
    change(name,"[Math]::Abs($frequency-1000.0/$actualPeriod) -gt 0.0001",
        "([Math]::Abs($frequency-1000.0/$actualPeriod) -gt 0.0002 -and [Math]::Abs($frequency-95.0) -gt 0.00005)",1)
    name='scripts/soc/review_board.py'
    change(name,'100_000_000','95_000_000')
    change(name,'-multiply_by 4 -divide_by 5','-multiply_by 19 -divide_by 25',1)
    change(name,r'10\.0000\s+\{0\.0000 5\.0000\}',r'10\.526[03]\s+\{0\.0000 5\.263[02]\}',1)
    change(name,r'100\.0000 MHz\s+\d+\.\d+ MHz\s+10\.0000',r'95\.\d{4} MHz\s+\d+\.\d+ MHz\s+10\.526[03]',1)
    marker='    worst = min(row["slack_ns"] for row in rows if row["check"] == "Setup")'
    extra='''    frequency_rows = re.findall(r"(?m)^\\s*cpu_clk\\s+(95\\.\\d{4}) MHz\\s+\\d+\\.\\d+ MHz\\s+(10\\.526[03])\\s+", report)
    assert len(frequency_rows) == 1
    reported_hz, reported_period = map(float, frequency_rows[0])
    assert abs(reported_period - 1000/95) <= 0.00032
    assert abs(reported_hz - 1000/reported_period) <= 0.0002 or abs(reported_hz - 95.0) <= 0.00005
'''
    change(name,marker,extra+marker,1)
    change('scripts/soc/package_dual_board.py','100MHz','95MHz')
    change('scripts/soc/package_dual_board.py','cpu_core_luts=checked[\'cpu_hierarchy_resources\'][\'lut\'],',"cpu_hz=95000000, cpu_core_luts=checked['cpu_hierarchy_resources']['lut'],",1)
    change('scripts/soc/program_board.py','100MHz','95MHz')
    change('scripts/soc/program_board.py',"    top = image_top(manifest)","    if manifest.get('cpu_hz') != 95000000: raise ValueError('Need exact95MHz package clock')\n    top = image_top(manifest)",1)
    for command in [['scripts/soc/gen_config.py'],['scripts/soc/gen_config.py','--check'],['scripts/soc/gen_board.py'],['scripts/soc/gen_board.py','--check']]:
        subprocess.run([sys.executable,*command],cwd=P,check=True)
    source=json.loads((SOURCE/'prepared-board.json').read_text())
    manifest=json.loads((ROOT/source['cpu_manifest']).read_text(encoding='utf-8'))
    for n,e in manifest['sources'].items():assert sha(P/n)==e['candidate_sha256'],n
    source.update(project=str(P),cpu_hz=95000000,source_prepared_sha256=sha(DEST/'source-prepared-board.json'),
        clock_adaptation_tool_sha256=sha(Path(__file__)),clock_adaptation_scope='Same exact22 CPU sources. Board PLL, UART, software clock and independent expected STA boundary changed together to nominal95MHz. 100MHz records retained; no claim95 proves100.')
    source['project_files']={f.relative_to(P).as_posix():sha(f) for f in P.rglob('*')
        if f.is_file() and '__pycache__' not in f.parts and f.suffix != '.pyc'}
    (DEST/'prepared-board.json').write_text(json.dumps(source,indent=2)+'\n',encoding='utf-8')
    shutil.copyfile(Path(__file__),DEST/'prepare_board95.frozen.py')
    print('BOARD95_PREPARED',P)

if __name__=='__main__':
    {'clone':clone,'adapt':adapt}[sys.argv[1]]()
