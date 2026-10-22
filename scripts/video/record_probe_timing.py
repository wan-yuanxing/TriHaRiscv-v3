"""Qualified all-path dual-corner STA for the registered record component."""
import re
from pds_timing import KINDS, NUMBER, section, data_lines, finite


def parse_record_probe_timing(text):
    if len(re.findall(r'^Timing analysis mode : multi corner\s*$',text,re.M))!=1:
        raise ValueError('Expected a multi-corner routed report')
    for label,value in [('Design','video_record_probe'),('Timing Models','Production')]:
        if len(re.findall(r'^\| '+label+r'\s*:\s*'+value+r'\s*$',text,re.M))!=1:
            raise ValueError('Unexpected routed design/timing model')
    commands=re.findall(r'^\| Tcl Command\s*:\s*(.+)',text,re.M)
    if len(commands)!=1 or not re.match(r'report_timing(?:\s|$)',commands[0]) or re.search(
            r'\s-(?:from|to|through|clock_group_limit|slack_greater_than|slack_less_than|disable_package_delay)\b',commands[0]):
        raise ValueError('Filtered timing report is not a full component check')
    if re.search(r'_(?:plc|map|syn)\.adf\b',commands[0],re.I):
        raise ValueError('Placement/mapped DB cannot certify completed routing')
    clocks={}
    for line in data_lines(section(text,'Clock Summary:')):
        match=re.fullmatch(r'\s*(\w+)\s+('+NUMBER+r')\s+\{[^}]+\}\s+Declared\s+(\d+)\s+(\d+)\s+\{([^}]+)\}\s*',line)
        if not match or match[1] in clocks:
            raise ValueError('Malformed/duplicate routed clock')
        clocks[match[1]]={'period_ns':finite(match[2]),'loads':int(match[3]),'source':match[5]}
    if set(clocks)!={'core_clk','pixel_clk'} or any(clocks[n]['period_ns']!=p or clocks[n]['loads']<=0
            or clocks[n]['source']!=source for n,p,source in
            [('core_clk',8.0,'clk_i'),('pixel_clk',25.0,'pixel_clk')]):
        raise ValueError('Routed clocks differ from 125/40 MHz')
    if any(' '.join(line.split())!='Clock Group Group Type Clocks'
           for line in data_lines(section(text,'Clock Groups:'))):
        raise ValueError('Unexpected routed clock-group cut')
    summaries={}
    for key,label in KINDS.items():
        summaries[key]={}
        for corner in ('slow','fast'):
            rows=[]
            for line in data_lines(section(text,label+' Summary('+corner.title()+' Corner):')):
                fields=line.split();size=5 if key=='pulse_width' else 6
                if len(fields)!=size or not all(re.fullmatch(r'\d+',n) for n in fields[-2:]):
                    raise ValueError('Malformed routed timing row: '+line)
                names=fields[:-4]
                if any(n not in clocks for n in names):raise ValueError('Unknown routed summary clock')
                wns,total=map(finite,fields[-4:-2]);failing,count=map(int,fields[-2:])
                if (count<=0 or failing>count or (wns<0)!=(failing>0) or (total<0)!=(failing>0)
                        or total>0 or (failing and (total>wns+0.001 or total<failing*(wns-0.001)))):
                    raise ValueError('Contradictory routed endpoint/slack values')
                row={'launch_clock':names[0],'capture_clock':names[-1],'wns_ns':wns,
                     'total_negative_slack_ns':total,'failing_endpoints':failing,'endpoints':count}
                if any((r['launch_clock'],r['capture_clock'])==(names[0],names[-1]) for r in rows):
                    raise ValueError('Duplicate routed clock pair')
                rows.append(row)
            if any(not any(r['launch_clock']==n==r['capture_clock'] for r in rows) for n in clocks):
                raise ValueError('Missing routed clock/corner coverage: '+label+' '+corner)
            summaries[key][corner]=rows
        if {(r['launch_clock'],r['capture_clock']) for r in summaries[key]['slow']} != {
                (r['launch_clock'],r['capture_clock']) for r in summaries[key]['fast']}:
            raise ValueError('Routed clock-pair coverage differs between corners: '+label)
    met=all(r['wns_ns']>=0 for k in summaries.values() for rows in k.values() for r in rows)
    declarations=re.findall(r'Design Summary\s*:\s*(All Constraints Met|Some Constraints Violated)\.',text)
    if len(declarations)!=1 or (declarations[0]=='All Constraints Met')!=met:
        raise ValueError('Routed design summary contradicts the tables')
    paths=[]
    for block in re.split(r'(?=^Startpoint\s*:)',text,flags=re.M)[1:]:
        path={}
        for key,label in [('startpoint','Startpoint'),('endpoint','Endpoint'),('group','Path Group'),
                          ('type','Path Type'),('class','Path Class')]:
            values=re.findall('^'+label+r'\s*:\s*([^\n]+)',block,re.M)
            if len(values)!=1:raise ValueError('Missing/duplicate routed path '+label)
            path[key]=values[0].strip()
        kind_match=re.fullmatch(r'(max|min) \((slow|fast) corner\)',path['type'])
        if not kind_match or path['class'] not in ('sequential timing path','async timing path'):
            raise ValueError('Unexpected routed path type/class')
        maximum=kind_match[1]=='max';corner=kind_match[2]
        kind=('recovery' if maximum else 'removal') if path['class']=='async timing path' else ('setup' if maximum else 'hold')
        slack_lines=[s for s in re.findall(r'^[ \t]*Slack\b[^\n]*',block,re.M)
                     if ' '.join(s.split())!='Slack Actual Width Require Width Type Location Pin']
        slack=re.fullmatch(r'\s*Slack \((MET|VIOLATED)\)\s+('+NUMBER+r')\s*',slack_lines[0]) if len(slack_lines)==1 else None
        if not slack or (finite(slack[2])<0)!=(slack[1]=='VIOLATED'):
            raise ValueError('Invalid routed path slack')
        path['slack_ns']=finite(slack[2]);path['analysis']=kind;path['corner']=corner
        applicable=[r for r in summaries[kind][corner] if r['capture_clock']==path['group']]
        edge_clocks=re.findall(r'^\s*Clock (\S+) \((?:rising|falling) edge\)',block,re.M)
        if len(edge_clocks)==2:
            applicable=[r for r in applicable if (r['launch_clock'],r['capture_clock'])==tuple(edge_clocks)]
            path['summary_match']='clock_pair'
        elif not edge_clocks and re.search(r'^Timing Exception\s*:\s*MaxDelay Path\s+'+NUMBER+r'ns -datapath_only\s*$',block,re.M):
            path['summary_match']='capture_group_lower_bound'
        else:raise ValueError('Unknown routed path clocks/exception')
        if not applicable or path['slack_ns']<min(r['wns_ns'] for r in applicable)-0.001:
            raise ValueError('Routed path contradicts its summary')
        times={}
        for label in ('arrival','required'):
            numbers=re.findall(r'^\s*Data '+label+r' time\s+('+NUMBER+r')\b',block,re.M)
            if not 1<=len(numbers)<=2:raise ValueError('Missing/duplicate routed path time')
            times[label]=finite(numbers[0])
            if any(abs(finite(n)-times[label])>0.002 for n in numbers):raise ValueError('Conflicting routed path times')
        difference=times['required']-times['arrival']
        if abs((difference if maximum else -difference)-path['slack_ns'])>0.0021:
            raise ValueError('Routed path arithmetic contradicts slack')
        paths.append(path)
    if not paths:raise ValueError('No routed critical paths')
    return {'stage':'routed_component','path_scope':'all_constrained_paths',
            'corners_with_data':['slow','fast'],'clocks':clocks,'summaries':summaries,'paths':paths,
            'component_route_timing_met':met,'timing_closed':False,
            'physical_board':False,'external_io_timing_verified':False}
