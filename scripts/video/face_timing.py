"""Audit BOX board routed STA, with an independent conservative Gray delay bound.

PDS 2022.2-SP6.4 can omit max-skew assertions from its text report and overall
summary. A PASS summary alone is insufficient. For registered Gray buses with
direct routes or native-netlist-proven identity buffers,
each nonnegative clock-pin-to-D delay lies in [0, max_delay - setup_slack].
The largest such bound also bounds datapath skew, including either transition.
This is deliberately more conservative than subtracting two reported maxima.
It is a datapath bound; clock-tree skew is a separate physical timing check.
"""
import re
from pds_timing import KINDS, NUMBER, data_lines, finite, section


def parse_tables(text):
    if text.count('Timing analysis mode : multi corner') != 1:
        raise ValueError('Expected dual-corner timing')
    clocks = {}
    for line in data_lines(section(text, 'Clock Summary:')):
        match = re.fullmatch(r'\s*(\w+)\s+('+NUMBER+r')\s+\{[^}]+\}\s+'
            r'(Declared|Generated \([^)]+\))\s+(\d+)\s+(\d+)\s+\{([^}]+)\}\s*', line)
        if not match or match[1] in clocks:
            raise ValueError('Invalid or duplicate clock')
        clocks[match[1]] = dict(period_ns=finite(match[2]), loads=int(match[4]), source=match[6])
    expected = dict(sys_clk=37.037, pixel_clk=25, cfg_clk=99.9999, rx_pixel_clk=25,
        ref_clk=8, rst_clk=8, ddrphy_sysclk=8, compute_clk=20,
        phy_dq_clk_0=1, phy_dq_sysclk_0=8, phy_dq_clk_1=1, phy_dq_sysclk_1=8)
    if set(clocks) != set(expected) or any(abs(clocks[n]['period_ns']-v)>0.0001
            or (n != 'ref_clk' and clocks[n]['loads'] <= 0) for n,v in expected.items()):
        raise ValueError('Clock contract differs from 50/125/40 MHz BOX board')
    groups = [line.split() for line in data_lines(section(text, 'Clock Groups:'))
              if ' '.join(line.split()) != 'Clock Group Group Type Clocks']
    if sorted(groups) != sorted([[n,'asynchronous',n] for n in
                                ('ref_clk','rst_clk','phy_dq_clk_0','phy_dq_clk_1')]):
        raise ValueError('Unexpected asynchronous clock-group cut')
    summaries = {}
    for kind,label in KINDS.items():
        summaries[kind] = {}
        for corner in ('slow','fast'):
            rows = []
            for line in data_lines(section(text, label+' Summary('+corner.title()+' Corner):')):
                f = line.split()
                if len(f) != (5 if kind=='pulse_width' else 6):
                    raise ValueError('Malformed timing row: '+line)
                names = f[:-4]
                if any(n not in clocks for n in names): raise ValueError('Unknown summary clock')
                wns,tns = map(finite,f[-4:-2]); failed,count = map(int,f[-2:])
                if (count<=0 or not 0<=failed<=count or (wns<0)!=(failed>0)
                        or (tns<0)!=(failed>0) or tns>0
                        or (failed and (tns>wns+0.001 or tns<failed*(wns-0.001)))):
                    raise ValueError('Contradictory timing row')
                row = dict(launch_clock=names[0],capture_clock=names[-1],wns_ns=wns,
                           total_negative_slack_ns=tns,failing_endpoints=failed,endpoints=count)
                if any((x['launch_clock'],x['capture_clock'])==tuple((names[0],names[-1])) for x in rows):
                    raise ValueError('Duplicate clock pair')
                rows.append(row)
            if not rows: raise ValueError('Missing '+corner+' '+kind)
            summaries[kind][corner] = rows
        pairs = lambda c:{(x['launch_clock'],x['capture_clock']) for x in summaries[kind][c]}
        if pairs('slow') != pairs('fast'): raise ValueError('Corner coverage differs')
        if kind in ('setup','hold') and not {(n,n) for n in
            ('sys_clk','pixel_clk','cfg_clk','rx_pixel_clk','rst_clk','ddrphy_sysclk','compute_clk')} <= pairs('slow'):
            raise ValueError('Missing local clock timing coverage')
    met = all(x['failing_endpoints']==0 for k in summaries.values() for rows in k.values() for x in rows)
    if re.findall(r'Design Summary\s*:\s*(All Constraints Met|Some Constraints Violated)\.',text) != [
            'All Constraints Met' if met else 'Some Constraints Violated']:
        raise ValueError('Design summary disagrees with tables')
    return dict(clocks=clocks,summaries=summaries,all_tables_met=met)


def require_routed_report(text, routed_db):
    for label,value in [('Design','triha_face_board_top'),('Device','PG2L100H'),
                        ('Speed Grade','-6'),('Package','FBG676'),('Timing Models','Production')]:
        if len(re.findall(r'^\| '+label+r'\s*:\s*'+re.escape(value)+r'\s*$',text,re.M)) != 1:
            raise ValueError('Wrong report design/device/model: '+label)
    commands = re.findall(r'^\| Tcl Command\s*:\s*(.+)',text,re.M)
    if len(commands)!=1 or not commands[0].startswith('report_timing '):
        raise ValueError('Not a native routed timing command')
    if re.search(r'\s-(?:from|to|through|clock_group_limit|slack_greater_than|slack_less_than|'
                 r'path_logic_level_gt_than|disable_package_delay|delay_type)\b',commands[0]):
        raise ValueError('Filtered report cannot certify full board timing')
    inputs = re.findall(r'^\| Input\s*\|\s*(.+?)\s*$',text,re.M)
    if inputs != [routed_db] or not routed_db.endswith('_pnr.adf'):
        raise ValueError('Timing report is not bound to the completed route DB')


def path_blocks(text):
    return re.split(r'(?=^Startpoint\s*:)',text,flags=re.M)[1:]


def field(block, label):
    values = re.findall(r'^'+label+r'\s*:\s*([^\n]+)',block,re.M)
    if len(values)!=1: raise ValueError('Missing/duplicate '+label)
    return values[0].strip()


def audit_paths(text, tables):
    paths=[];external=[]
    for block in path_blocks(text):
        p={key:field(block,label) for key,label in [('start','Startpoint'),('end','Endpoint'),
            ('group','Path Group'),('type','Path Type'),('class','Path Class')]}
        if p['class']=='combinational timing path':
            if p['group']!='**default**' or not any(p[k].endswith('(port)') for k in ('start','end')):
                raise ValueError('Unconstrained internal timing path')
            external.append(p)
            continue
        typ=re.fullmatch(r'(max|min) \((slow|fast) corner\)',p['type'])
        if not typ or p['class'] not in ('sequential timing path','async timing path'):
            raise ValueError('Unknown timing path class')
        maximum=typ[1]=='max';corner=typ[2]
        kind=('recovery' if maximum else 'removal') if p['class']=='async timing path' else ('setup' if maximum else 'hold')
        slack=re.findall(r'^\s*Slack \((MET|VIOLATED)\)\s+('+NUMBER+r')\s*$',block,re.M)
        if len(slack)!=1 or (finite(slack[0][1])<0)!=(slack[0][0]=='VIOLATED'):
            raise ValueError('Invalid path slack')
        p['slack_ns']=finite(slack[0][1]);p['corner']=corner;p['kind']=kind
        rows=[r for r in tables['summaries'][kind][corner] if r['capture_clock']==p['group']]
        clocks=re.findall(r'^\s*Clock (\S+) \((?:rising|falling) edge\)',block,re.M)
        if len(clocks)==2:
            rows=[r for r in rows if (r['launch_clock'],r['capture_clock'])==tuple(clocks)]
        elif clocks or not re.search(r'^Timing Exception\s*:\s*MaxDelay Path\s+'+NUMBER+r'ns -datapath_only\s*$',block,re.M):
            raise ValueError('Unknown timing exception or clocks')
        if not rows or p['slack_ns']<min(r['wns_ns'] for r in rows)-0.001:
            raise ValueError('Path is worse than its timing summary')
        times={}
        for label in ('arrival','required'):
            values=re.findall(r'^\s*Data '+label+r' time\s+('+NUMBER+r')',block,re.M)
            if not 1<=len(values)<=2 or max(map(finite,values))-min(map(finite,values))>0.002:
                raise ValueError('Invalid path arithmetic fields')
            times[label]=finite(values[0])
        difference=times['required']-times['arrival']
        if abs((difference if maximum else -difference)-p['slack_ns'])>0.0021:
            raise ValueError('Path arithmetic disagrees with slack')
        if clocks:
            p['clocks']=clocks
            p['uncertainty_ns']=[finite(v) for v in re.findall(r'^\s*clock uncertainty\s+('+NUMBER+r')',block,re.M)]
        paths.append(p)
    if not paths: raise ValueError('No critical paths')
    uncertainties={}
    for clock in ('compute_clk','ddrphy_sysclk'):
        relevant=[p for p in paths if p['kind']=='setup' and p.get('clocks')==[clock,clock]]
        if not relevant or any(len(p['uncertainty_ns'])!=1 or p['uncertainty_ns'][0]>-0.2 for p in relevant):
            raise ValueError('Missing at least 0.2 ns setup uncertainty: '+clock)
        uncertainties[clock]=sorted({-p['uncertainty_ns'][0] for p in relevant})
    return dict(count=len(paths),worst_slack_ns=min(p['slack_ns'] for p in paths),
                reported_setup_uncertainty_ns=uncertainties,external_unconstrained_paths=len(external),
                external_io_timing_verified=False)


def gray_bounds(text, fdc, sites, netlist=None):
    """Check every mapped Gray bit in both corners, never extrapolate a sample."""
    cells = re.findall(r'^def_inst_site \{([^}]+)\}',sites,re.M)
    logical = {re.sub(r'/opit_\d+(?:_inv)?$','',name):name for name in cells}
    groups = []
    for command in fdc.splitlines():
        if not command.startswith('set_max_skew '): continue
        match = re.fullmatch(r'set_max_skew ('+NUMBER+r') -from \[get_cells -regexp \{([^}]+)\}\] '
                             r'-to \[get_cells \{([^}]+)\}\]',command)
        if not match: raise ValueError('Unsupported Gray constraint: '+command)
        starts = {name:cell for name,cell in logical.items() if re.fullmatch(match[2],name)}
        # Only a terminal wildcard is allowed; fnmatch treats literal [bits] specially.
        target = match[3]
        if target.count('*')!=1 or not target.endswith('*'): raise ValueError('Unexpected Gray target')
        ends = {name:cell for name,cell in logical.items() if name.startswith(target[:-1])}
        if len(starts)<2 or len(ends)!=len(starts): raise ValueError('Missing mapped Gray bits')
        bit = lambda name:int(re.search(r'\[(\d+)\]$',name)[1])
        if {bit(n) for n in starts} != set(range(len(starts))) or {bit(n) for n in ends} != set(range(len(starts))):
            raise ValueError('Noncontiguous Gray bit coverage')
        group = dict(command=command,limit_ns=finite(match[1]),starts=starts,ends=ends,paths={})
        groups.append(group)
    if len(groups)!=23 or sum(len(g['starts']) for g in groups)!=116:
        raise ValueError('BOX Gray contract must contain 23 groups and 116 bits')
    by_start = {cell:g for g in groups for cell in g['starts'].values()}
    for block in path_blocks(text):
        start = field(block,'Startpoint').removesuffix('/CLK')
        if start not in by_start: continue
        end = field(block,'Endpoint').removesuffix('/D'); g=by_start[start]
        if end not in g['ends'].values(): continue
        source_bit = int(re.search(r'\[(\d+)\]/opit_',start)[1])
        if int(re.search(r'\[(\d+)\]/opit_',end)[1]) != source_bit:
            raise ValueError('Gray bit crosses to a different index')
        kind = re.fullmatch(r'max \((slow|fast) corner\)',field(block,'Path Type'))
        if not kind: raise ValueError('Unexpected Gray path type')
        key=(kind[1],source_bit)
        if key in g['paths']: raise ValueError('Duplicate Gray path')
        exception = re.fullmatch(r'MaxDelay Path ('+NUMBER+r')ns -datapath_only',field(block,'Timing Exception'))
        if not exception or finite(exception[1])!=g['limit_ns']:
            raise ValueError('Gray flight-time constraint changed')
        arrivals=re.findall(r'^\s*Data arrival time\s+('+NUMBER+r')',block,re.M)
        required=re.findall(r'^\s*Data required time\s+('+NUMBER+r')',block,re.M)
        slack=re.findall(r'^\s*Slack \((MET|VIOLATED)\)\s+('+NUMBER+r')\s*$',block,re.M)
        if not arrivals or not required or len(slack)!=1 or len(set(arrivals))!=1 or len(set(required))!=1:
            raise ValueError('Invalid Gray timing arithmetic fields')
        arrival,need,margin=finite(arrivals[0]),finite(required[0]),finite(slack[0][1])
        if arrival<0 or need>g['limit_ns']+0.001 or abs(need-arrival-margin)>0.0021:
            raise ValueError('Gray timing arithmetic contradicts nonnegative setup/delay')
        levels = re.search(r'Logic Levels: (\d+)\b', block)
        if not levels or re.search(r'^\s*Clock \S+ \(',block,re.M):
            raise ValueError('Expected direct, datapath-only registered Gray bit')
        identity = None
        if int(levels[1]):
            if netlist is None:
                raise ValueError('Gray physical buffer requires native netlist identity proof')
            identity = netlist.prove(block, start, end, int(levels[1]))
        bound=g['limit_ns']-margin+0.002  # conservative text rounding, both transitions
        if bound<arrival or bound>=g['limit_ns']:
            raise ValueError('Gray delay/skew conservative bound violates limit')
        g['paths'][key] = dict(bit=source_bit,corner=kind[1],arrival_ns=arrival,upper_bound_ns=bound,
                              setup_slack_ns=margin,start=start,end=end)
        if identity is not None:
            g['paths'][key]['identity_proof'] = identity
    output=[]
    for g in groups:
        expected={(c,b) for c in ('slow','fast') for b in range(len(g['starts']))}
        if set(g['paths'])!=expected: raise ValueError('Missing Gray bit/corner report coverage')
        output.append(dict(constraint=g['command'],bits=len(g['starts']),limit_ns=g['limit_ns'],
            datapath_skew_upper_bound_ns=max(x['upper_bound_ns'] for x in g['paths'].values()),
            paths=list(g['paths'].values())))
    return dict(status='PASS_CONSERVATIVE_DATAPATH_BOUND',groups=output,total_bits=116,
        native_skew_assertion_reported=False,clock_tree_skew_verified=False,
        scope='All 116 bits/23 groups, both corners; 0 <= path delay <= bound, hence datapath skew <= bound. Clock-tree skew requires separate review.')
